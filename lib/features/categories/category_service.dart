import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:uuid/uuid.dart';

class CategoryService {
  CategoryService({
    required this.db,
    required this.onboarding,
  });

  final AppDatabase db;
  final OnboardingService onboarding;
  static const Uuid _uuid = Uuid();

  Future<String> createCategory({
    required String familyId,
    required String name,
    required String type,
    required String icon,
    required int color,
  }) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) {
      throw ArgumentError('Nama kategori wajib diisi.');
    }
    final deviceId = await onboarding.getOrCreateDeviceId();
    return db.insertCategory(
      id: '${familyId}_custom_${_uuid.v4().substring(0, 8)}',
      familyId: familyId,
      name: cleaned,
      type: type,
      icon: icon,
      color: color,
      deviceId: deviceId,
    );
  }

  Future<void> updateCategory({
    required String categoryId,
    required String name,
    required String icon,
    required int color,
  }) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) {
      throw ArgumentError('Nama kategori wajib diisi.');
    }
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.updateCategoryRow(
      id: categoryId,
      name: cleaned,
      icon: icon,
      color: color,
      deviceId: deviceId,
    );
  }

  Future<void> deleteCategory(Category category) async {
    if (category.isDefault) {
      throw StateError(
        'Kategori bawaan tidak dapat dihapus agar kompatibel saat sinkronisasi. Anda tetap bisa mengubah nama, ikon, atau warnanya.',
      );
    }
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.softDeleteCategory(id: category.id, deviceId: deviceId);
  }
}
