import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:dio/dio.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/family_crypto.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/family_sync/sync_crypto.dart';
import 'package:si_hemat/features/family_sync/sync_engine.dart';
import 'package:si_hemat/features/family_sync/sync_transport.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';

/// Option A SyncTransport: Local Wi-Fi LAN using `bonsoir` mDNS discovery +
/// `dart:io` HttpServer with HMAC-SHA256 handshake & AES-256-GCM encryption.
class WifiLanSyncService implements SyncTransport {
  WifiLanSyncService({
    required this.db,
    required this.keyStore,
    required this.onboarding,
    Dio? dio,
  })  : _engine = SyncEngine(db),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
              ),
            );

  final AppDatabase db;
  final SecureKeyStore keyStore;
  final OnboardingService onboarding;
  final SyncEngine _engine;
  final Dio _dio;

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;

  final _peersById = <String, SyncPeerInfo>{};
  final _peersController = StreamController<List<SyncPeerInfo>>.broadcast();
  final _incomingSyncController = StreamController<SyncRunResult>.broadcast();

  String? _activeFamilyId;
  String? _activeFamilyHash;
  String? _activeFamilySecret;
  String? _myDeviceId;
  String? _myMemberName;
  int? _boundPort;
  String? _localIpv4;

  @override
  Stream<List<SyncPeerInfo>> get discoveredPeers => _peersController.stream;

  /// Emits when another family device initiates a sync against this device's server.
  Stream<SyncRunResult> get incomingSyncEvents =>
      _incomingSyncController.stream;

  int? get boundPort => _boundPort;
  String? get localIpv4 => _localIpv4;
  String? get activeFamilyHash => _activeFamilyHash;

  Future<void> _loadIdentity() async {
    final family = await db.getActiveFamily();
    final secret = await keyStore.read(SecureStorageKeys.familySecret);
    if (family == null || secret == null || secret.isEmpty) {
      throw StateError('Buku keluarga atau kunci sync belum tersedia.');
    }
    final deviceId = await onboarding.getOrCreateDeviceId();
    final members = await db.getFamilyMembers(family.id);
    final storedMemberId = await keyStore.read(SecureStorageKeys.memberId);
    final me = members
            .where((m) => m.id == storedMemberId || m.deviceId == deviceId)
            .firstOrNull ??
        members.firstOrNull;

    _activeFamilyId = family.id;
    _activeFamilySecret = secret;
    _activeFamilyHash = await FamilyCrypto.computeFamilyHash(family.id);
    _myDeviceId = deviceId;
    _myMemberName = me?.name ?? 'Anggota';
    _localIpv4 = await _detectLocalIpv4();
  }

  /// Starts ONLY the local HTTP server (also used directly in unit/integration tests
  /// without requiring platform mDNS channels).
  Future<int> startServerOnly({InternetAddress? bindAddress}) async {
    await _loadIdentity();
    if (_server != null) return _boundPort!;

    final server = await HttpServer.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
      shared: true,
    );
    _server = server;
    _boundPort = server.port;
    server.listen(_handleHttpRequest);
    return server.port;
  }

  @override
  Future<int> startHostAndDiscovery() async {
    final port = await startServerOnly();

    // Start mDNS broadcast so other family devices on the same Wi-Fi discover us
    try {
      final service = BonsoirService(
        name: 'SiHemat-${_myMemberName ?? 'Device'}-${_myDeviceId!.substring(0, 4)}',
        type: SyncConstants.mdnsServiceType,
        port: port,
        attributes: {
          'fh': _activeFamilyHash!,
          'did': _myDeviceId!,
          'name': _myMemberName ?? 'Anggota',
          'v': SyncConstants.protocolVersion.toString(),
        },
      );
      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.initialize();
      await _broadcast!.start();
    } catch (_) {
      // Allow manual IP fallback even if platform mDNS broadcast is unavailable.
    }

    // Start mDNS discovery
    try {
      _discovery = BonsoirDiscovery(type: SyncConstants.mdnsServiceType);
      await _discovery!.initialize();
      _discoverySub = _discovery!.eventStream?.listen(_onDiscoveryEvent);
      await _discovery!.start();
    } catch (_) {
      // Manual IP fallback remains available.
    }

    return port;
  }

  void _onDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        _discovery?.serviceResolver.resolveService(event.service);
      case BonsoirDiscoveryServiceResolvedEvent():
        _registerDiscoveredService(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        _registerDiscoveredService(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        final did = event.service.attributes['did'];
        if (did != null && _peersById.remove(did) != null) {
          _emitPeers();
        }
      default:
        break;
    }
  }

  void _registerDiscoveredService(BonsoirService service) {
    final attrs = service.attributes;
    final peerFamilyHash = attrs['fh'];
    final peerDeviceId = attrs['did'];
    final peerName = attrs['name'] ?? service.name;
    if (peerFamilyHash != _activeFamilyHash) return;
    if (peerDeviceId == null || peerDeviceId == _myDeviceId) return;

    final host = _pickPreferredHost(service.hostAddresses, service.hostname);
    if (host == null || host.isEmpty || service.port <= 0) return;

    _peersById[peerDeviceId] = SyncPeerInfo(
      deviceId: peerDeviceId,
      name: peerName,
      host: host,
      port: service.port,
      familyHash: peerFamilyHash!,
    );
    _emitPeers();
  }

  String? _pickPreferredHost(List<String> addresses, String? hostname) {
    // Prefer IPv4 addresses for straightforward HTTP authority formatting
    for (final addr in addresses) {
      if (addr.contains('.') && !addr.contains(':') && addr != '127.0.0.1') {
        return addr;
      }
    }
    if (addresses.isNotEmpty) return addresses.first;
    return hostname;
  }

  void _emitPeers() {
    if (!_peersController.isClosed) {
      _peersController.add(_peersById.values.toList());
    }
  }

  @override
  Future<void> stopAll() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;

    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;

    await _server?.close(force: true);
    _server = null;
    _boundPort = null;
    _peersById.clear();
    _emitPeers();
  }

  Future<void> dispose() async {
    await stopAll();
    await _peersController.close();
    await _incomingSyncController.close();
  }

  // ---------------------------------------------------------------------------
  // Local HTTP Sync Server Endpoints
  // ---------------------------------------------------------------------------

  Future<void> _handleHttpRequest(HttpRequest req) async {
    try {
      if (req.method == 'GET' && req.uri.path == '/sync/ping') {
        _writeJson(req.response, HttpStatus.ok, {
          'app': 'si_hemat',
          'v': SyncConstants.protocolVersion,
          'family_hash': _activeFamilyHash,
          'device_id': _myDeviceId,
          'member_name': _myMemberName,
        });
        return;
      }

      if (req.method == 'POST' && req.uri.path == '/sync/exchange') {
        final rawBody = await utf8.decoder.bind(req).join();
        final body = jsonDecode(rawBody) as Map<String, dynamic>;

        final peerDeviceId = body['device_id'] as String? ?? '';
        final peerName = body['member_name'] as String? ?? 'Anggota';
        final nonce = body['nonce'] as String? ?? '';
        final providedHmac = body['hmac'] as String? ?? '';
        final clientSinceTs = body['since_ts'] as int? ?? 0;
        final envelope = body['envelope'];

        if (peerDeviceId.isEmpty ||
            nonce.isEmpty ||
            envelope is! Map<String, dynamic>) {
          _writeJson(req.response, HttpStatus.badRequest, {
            'error': 'Payload sync tidak lengkap.',
          });
          return;
        }

        final validHmac = await SyncCrypto.verifyHandshakeHmac(
          familySecret: _activeFamilySecret!,
          deviceId: peerDeviceId,
          nonce: nonce,
          providedHmac: providedHmac,
        );
        if (!validHmac) {
          _writeJson(req.response, HttpStatus.forbidden, {
            'error': 'Kunci keluarga tidak cocok (HMAC ditolak).',
          });
          return;
        }

        // 1. Decrypt incoming client delta
        final clientDelta = await SyncCrypto.decryptJson(
          envelope: envelope,
          familySecret: _activeFamilySecret!,
        );

        // 2. Export our own delta for client BEFORE merging client's incoming rows
        // Apply a 60s clock-skew overlap window (safe because LWW merge is 100% idempotent).
        final safeSinceTs = clientSinceTs > 60000 ? clientSinceTs - 60000 : 0;
        final serverExport = await _engine.exportSharedDelta(
          familyId: _activeFamilyId!,
          sinceTimestamp: safeSinceTs,
        );

        // 3. Merge client's delta into our SQLite atomically
        final mergeStats = await _engine.mergeSharedDelta(
          expectedFamilyId: _activeFamilyId!,
          payload: clientDelta,
        );

        final syncTime = DateTime.now().toUtc().millisecondsSinceEpoch;
        await db.upsertSyncPeer(
          peerDeviceId: peerDeviceId,
          peerName: peerName,
          lastSyncedAt: syncTime,
          lastIp: req.connectionInfo?.remoteAddress.address,
        );

        // 4. Encrypt our delta back to the client
        final responseEnvelope = await SyncCrypto.encryptJson(
          payload: serverExport.payload,
          familySecret: _activeFamilySecret!,
        );

        if (!_incomingSyncController.isClosed) {
          _incomingSyncController.add(
            SyncRunResult(
              peerName: peerName,
              sentRecords: serverExport.recordCount,
              receivedApplied: mergeStats.applied,
              receivedSkipped: mergeStats.skipped,
            ),
          );
        }

        _writeJson(req.response, HttpStatus.ok, {
          'device_id': _myDeviceId,
          'member_name': _myMemberName,
          'synced_at': syncTime,
          'sent_count': serverExport.recordCount,
          'envelope': responseEnvelope,
        });
        return;
      }

      _writeJson(req.response, HttpStatus.notFound, {'error': 'Not found'});
    } on SyncAuthException catch (e) {
      _writeJson(req.response, HttpStatus.forbidden, {'error': e.message});
    } catch (e) {
      _writeJson(req.response, HttpStatus.internalServerError, {
        'error': e.toString(),
      });
    }
  }

  void _writeJson(HttpResponse res, int status, Map<String, dynamic> body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    res.close();
  }

  // ---------------------------------------------------------------------------
  // Client Sync Operations (Auto-discovered Peer or Manual IP:Port)
  // ---------------------------------------------------------------------------

  /// Pings a manual IP:Port on the local Wi-Fi and verifies it belongs to the same family.
  Future<SyncPeerInfo> probeManualPeer({
    required String host,
    required int port,
  }) async {
    await _loadIdentity();
    final url = 'http://${host.trim()}:$port/sync/ping';
    final res = await _dio.get<dynamic>(url);
    final data = res.data is Map<String, dynamic>
        ? res.data as Map<String, dynamic>
        : jsonDecode(res.data as String) as Map<String, dynamic>;

    if (data['app'] != 'si_hemat') {
      throw const SyncAuthException('Perangkat bukan aplikasi Si-Hemat.');
    }
    if (data['family_hash'] != _activeFamilyHash) {
      throw const SyncAuthException(
        'Perangkat tersebut bukan anggota Buku Keluarga yang sama.',
      );
    }
    final peerDeviceId = data['device_id'] as String? ?? '';
    if (peerDeviceId == _myDeviceId) {
      throw const SyncAuthException('Tidak dapat sync dengan perangkat sendiri.');
    }

    return SyncPeerInfo(
      deviceId: peerDeviceId,
      name: data['member_name'] as String? ?? 'Anggota',
      host: host.trim(),
      port: port,
      familyHash: data['family_hash'] as String,
      isManual: true,
    );
  }

  @override
  Future<SyncRunResult> syncWithPeer(SyncPeerInfo peer) async {
    await _loadIdentity();

    final knownPeer = await db.getSyncPeer(peer.deviceId);
    final sinceTs = knownPeer?.lastSyncedAt ?? 0;
    final safeSinceTs = sinceTs > 60000 ? sinceTs - 60000 : 0;

    final localExport = await _engine.exportSharedDelta(
      familyId: _activeFamilyId!,
      sinceTimestamp: safeSinceTs,
    );

    final nonce = SyncCrypto.generateNonce();
    final hmac = await SyncCrypto.computeHandshakeHmac(
      familySecret: _activeFamilySecret!,
      deviceId: _myDeviceId!,
      nonce: nonce,
    );
    final encryptedEnvelope = await SyncCrypto.encryptJson(
      payload: localExport.payload,
      familySecret: _activeFamilySecret!,
    );

    final url = 'http://${peer.host}:${peer.port}/sync/exchange';
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        url,
        data: jsonEncode({
          'device_id': _myDeviceId,
          'member_name': _myMemberName,
          'nonce': nonce,
          'hmac': hmac,
          'since_ts': sinceTs,
          'envelope': encryptedEnvelope,
        }),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == HttpStatus.forbidden) {
        throw const SyncAuthException(
          'Sync ditolak oleh perangkat tujuan: kunci keluarga tidak cocok.',
        );
      }
      throw Exception(
        'Gagal terhubung ke ${peer.name} (${peer.host}:${peer.port}). Pastikan kedua HP di Wi-Fi yang sama dan layar Sync terbuka.',
      );
    }

    final body = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : jsonDecode(response.data as String) as Map<String, dynamic>;
    final peerEnvelope = body['envelope'] as Map<String, dynamic>;

    final serverDelta = await SyncCrypto.decryptJson(
      envelope: peerEnvelope,
      familySecret: _activeFamilySecret!,
    );

    final mergeStats = await _engine.mergeSharedDelta(
      expectedFamilyId: _activeFamilyId!,
      payload: serverDelta,
    );

    final syncedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.upsertSyncPeer(
      peerDeviceId: peer.deviceId,
      peerName: body['member_name'] as String? ?? peer.name,
      lastSyncedAt: syncedAt,
      lastIp: peer.host,
    );

    return SyncRunResult(
      peerName: body['member_name'] as String? ?? peer.name,
      sentRecords: localExport.recordCount,
      receivedApplied: mergeStats.applied,
      receivedSkipped: mergeStats.skipped,
    );
  }

  Future<String?> _detectLocalIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
