import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/family_crypto.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';
import 'package:uuid/uuid.dart';

class OnboardingResult {
  const OnboardingResult({
    required this.familyId,
    required this.memberId,
    required this.deviceId,
    required this.familySecret,
  });

  final String familyId;
  final String memberId;
  final String deviceId;
  final String familySecret;
}

class OnboardingService {
  OnboardingService({
    required this.db,
    required this.keyStore,
  });

  final AppDatabase db;
  final SecureKeyStore keyStore;
  static const Uuid _uuid = Uuid();

  Future<String> getOrCreateDeviceId() async {
    final existing = await keyStore.read(SecureStorageKeys.deviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = _uuid.v4();
    await keyStore.write(SecureStorageKeys.deviceId, created);
    return created;
  }

  /// Creates a new family workspace as Admin, generates a 256-bit family_secret,
  /// seeds default Indonesian categories & starter wallets.
  Future<OnboardingResult> createNewFamily({
    required String familyName,
    required String adminName,
    required int paydayDay,
    int initialCashBalance = 0,
    int initialBankBalance = 0,
  }) async {
    final trimmedFamily = familyName.trim();
    final trimmedAdmin = adminName.trim();
    if (trimmedFamily.isEmpty) {
      throw ArgumentError('Nama keluarga wajib diisi.');
    }
    if (trimmedAdmin.isEmpty) {
      throw ArgumentError('Nama Anda wajib diisi.');
    }

    final deviceId = await getOrCreateDeviceId();
    final familyId = _uuid.v4();
    final memberId = _uuid.v4();
    final familySecret = FamilyCrypto.generateFamilySecret();
    final clampedPayday = paydayDay.clamp(1, 31);

    await db.seedNewFamilyWorkspace(
      familyId: familyId,
      familyName: trimmedFamily,
      paydayDay: clampedPayday,
      adminMemberId: memberId,
      adminName: trimmedAdmin,
      deviceId: deviceId,
      initialCashBalance: initialCashBalance,
      initialBankBalance: initialBankBalance,
    );

    await keyStore.write(SecureStorageKeys.familyId, familyId);
    await keyStore.write(SecureStorageKeys.memberId, memberId);
    await keyStore.write(SecureStorageKeys.familySecret, familySecret);

    return OnboardingResult(
      familyId: familyId,
      memberId: memberId,
      deviceId: deviceId,
      familySecret: familySecret,
    );
  }

  /// Joins an existing family workspace using an invite QR payload JSON string.
  Future<OnboardingResult> joinFamilyFromQr({
    required String qrPayloadRaw,
    required String memberName,
  }) async {
    final trimmedName = memberName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Nama Anda wajib diisi.');
    }

    final payload = FamilyPairingPayload.fromQrString(qrPayloadRaw);
    final deviceId = await getOrCreateDeviceId();
    final memberId = _uuid.v4();

    await db.seedJoinedFamilyWorkspace(
      familyId: payload.familyId,
      familyName: payload.familyName,
      paydayDay: payload.paydayDay,
      memberId: memberId,
      memberName: trimmedName,
      deviceId: deviceId,
    );

    await keyStore.write(SecureStorageKeys.familyId, payload.familyId);
    await keyStore.write(SecureStorageKeys.memberId, memberId);
    await keyStore.write(SecureStorageKeys.familySecret, payload.familySecret);

    // Import bundled AI configuration (9Router or Gemini) if included in QR
    final hasNineRouter = payload.nineRouterBaseUrl != null &&
        payload.nineRouterBaseUrl!.isNotEmpty &&
        payload.nineRouterModel != null &&
        payload.nineRouterModel!.isNotEmpty;
    final hasGemini =
        payload.geminiApiKey != null && payload.geminiApiKey!.isNotEmpty;

    if (hasNineRouter) {
      await keyStore.write(
        SecureStorageKeys.nineRouterBaseUrl,
        payload.nineRouterBaseUrl!,
      );
      await keyStore.write(
        SecureStorageKeys.nineRouterModel,
        payload.nineRouterModel!,
      );
      if (payload.nineRouterApiKey != null &&
          payload.nineRouterApiKey!.isNotEmpty) {
        await keyStore.write(
          SecureStorageKeys.nineRouterApiKey,
          payload.nineRouterApiKey!,
        );
      }
    }

    if (hasGemini) {
      await keyStore.write(
        SecureStorageKeys.geminiApiKey,
        payload.geminiApiKey!,
      );
      if (payload.geminiModel != null && payload.geminiModel!.isNotEmpty) {
        await keyStore.write(
          SecureStorageKeys.geminiModel,
          payload.geminiModel!,
        );
      }
    }

    if (payload.aiProvider == AiProviderType.nineRouter && hasNineRouter) {
      await keyStore.write(
        SecureStorageKeys.aiProvider,
        AiProviderType.nineRouter,
      );
    } else if (payload.aiProvider == AiProviderType.gemini && hasGemini) {
      await keyStore.write(
        SecureStorageKeys.aiProvider,
        AiProviderType.gemini,
      );
    } else if (hasNineRouter) {
      await keyStore.write(
        SecureStorageKeys.aiProvider,
        AiProviderType.nineRouter,
      );
    } else if (hasGemini) {
      await keyStore.write(
        SecureStorageKeys.aiProvider,
        AiProviderType.gemini,
      );
    }

    return OnboardingResult(
      familyId: payload.familyId,
      memberId: memberId,
      deviceId: deviceId,
      familySecret: payload.familySecret,
    );
  }

  /// Builds the QR payload string for inviting another family member.
  /// When [includeAiConfig] is true, bundles the currently active BYOK AI
  /// configuration (either Gemini or 9Router) so the invited member can use AI right away.
  Future<FamilyPairingPayload?> buildInvitePayload({
    bool includeAiConfig = false,
  }) async {
    final family = await db.getActiveFamily();
    final secret = await keyStore.read(SecureStorageKeys.familySecret);
    if (family == null || secret == null || secret.isEmpty) return null;

    String? aiProvider;
    String? geminiApiKey;
    String? geminiModel;
    String? nineRouterBaseUrl;
    String? nineRouterApiKey;
    String? nineRouterModel;

    if (includeAiConfig) {
      final activeProvider =
          (await keyStore.read(SecureStorageKeys.aiProvider))?.trim();
      if (activeProvider == AiProviderType.nineRouter) {
        final baseUrl =
            (await keyStore.read(SecureStorageKeys.nineRouterBaseUrl))?.trim();
        final model =
            (await keyStore.read(SecureStorageKeys.nineRouterModel))?.trim();
        final apiKey =
            (await keyStore.read(SecureStorageKeys.nineRouterApiKey))?.trim();
        if (baseUrl != null &&
            baseUrl.isNotEmpty &&
            model != null &&
            model.isNotEmpty) {
          aiProvider = AiProviderType.nineRouter;
          nineRouterBaseUrl = baseUrl;
          nineRouterModel = model;
          if (apiKey != null && apiKey.isNotEmpty) {
            nineRouterApiKey = apiKey;
          }
        }
      } else {
        final apiKey =
            (await keyStore.read(SecureStorageKeys.geminiApiKey))?.trim();
        final model =
            (await keyStore.read(SecureStorageKeys.geminiModel))?.trim();
        if (apiKey != null && apiKey.isNotEmpty) {
          aiProvider = AiProviderType.gemini;
          geminiApiKey = apiKey;
          if (model != null && model.isNotEmpty) {
            geminiModel = model;
          }
        }
      }
    }

    return FamilyPairingPayload(
      version: SyncConstants.protocolVersion,
      familyId: family.id,
      familyName: family.name,
      familySecret: secret,
      paydayDay: family.paydayDay,
      aiProvider: aiProvider,
      geminiApiKey: geminiApiKey,
      geminiModel: geminiModel,
      nineRouterBaseUrl: nineRouterBaseUrl,
      nineRouterApiKey: nineRouterApiKey,
      nineRouterModel: nineRouterModel,
    );
  }
}
