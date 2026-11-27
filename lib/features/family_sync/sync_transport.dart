// Modular SyncTransport abstraction so Wi-Fi LAN (Option A) and future
// Bluetooth / Nearby Connections (Option B) share the exact same SyncEngine & SyncCrypto.

class SyncPeerInfo {
  const SyncPeerInfo({
    required this.deviceId,
    required this.name,
    required this.host,
    required this.port,
    required this.familyHash,
    this.isManual = false,
  });

  final String deviceId;
  final String name;
  final String host;
  final int port;
  final String familyHash;
  final bool isManual;
}

class SyncRunResult {
  const SyncRunResult({
    required this.peerName,
    required this.sentRecords,
    required this.receivedApplied,
    required this.receivedSkipped,
  });

  final String peerName;
  final int sentRecords;
  final int receivedApplied;
  final int receivedSkipped;
}

abstract class SyncTransport {
  Stream<List<SyncPeerInfo>> get discoveredPeers;
  Future<int> startHostAndDiscovery();
  Future<void> stopAll();
  Future<SyncRunResult> syncWithPeer(SyncPeerInfo peer);
}
