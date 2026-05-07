import 'dart:convert';

import 'package:school_manager/models/category.dart';
import 'package:school_manager/services/api/remote_categories_service.dart';
import 'package:school_manager/services/api/token_storage_service.dart';
import 'package:school_manager/services/database_service.dart';

class CategoriesSyncService {
  CategoriesSyncService._();
  static final CategoriesSyncService instance = CategoriesSyncService._();

  static const String _entity = 'category';

  Future<({bool usedOfflineFallback, Object? remoteError})> upsertCategory(
    Category category, {
    required bool isUpdate,
  }) async {
    // Toujours sauvegarder en local
    if (isUpdate) {
      await DatabaseService().updateCategory(category.id, category);
    } else {
      await DatabaseService().insertCategory(category);
    }

    final token = await TokenStorageService.instance.getAccessToken();
    if (token == null) {
      return (usedOfflineFallback: true, remoteError: null);
    }

    try {
      if (isUpdate) {
        await RemoteCategoriesService.instance.updateCategory(category);
      } else {
        await RemoteCategoriesService.instance.createCategory(category);
      }
      return (usedOfflineFallback: false, remoteError: null);
    } catch (e) {
      await DatabaseService().enqueuePendingSync(
        entity: _entity,
        operation: isUpdate ? 'update' : 'create',
        entityId: category.id,
        payloadJson: jsonEncode(category.toMap()),
      );
      return (usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<({bool usedOfflineFallback, Object? remoteError})> deleteCategory(
    Category category,
  ) async {
    await DatabaseService().deleteCategory(category.id);

    final token = await TokenStorageService.instance.getAccessToken();
    if (token == null) {
      return (usedOfflineFallback: true, remoteError: null);
    }

    try {
      await RemoteCategoriesService.instance.deleteCategory(category.id);
      return (usedOfflineFallback: false, remoteError: null);
    } catch (e) {
      await DatabaseService().enqueuePendingSync(
        entity: _entity,
        operation: 'delete',
        entityId: category.id,
        payloadJson: jsonEncode(category.toMap()),
      );
      return (usedOfflineFallback: true, remoteError: e);
    }
  }

  /// Charge les catégories : API-first avec merge SQLite local.
  Future<({List<Category> categories, bool fromRemote})> loadCategories() async {
    final token = await TokenStorageService.instance.getAccessToken();
    if (token != null) {
      try {
        final remote = await RemoteCategoriesService.instance.listCategories();
        if (remote.isNotEmpty) {
          // Met à jour le cache local
          for (final c in remote) {
            try {
              await DatabaseService().insertCategory(c);
            } catch (_) {
              await DatabaseService().updateCategory(c.id, c);
            }
          }
          return (categories: remote, fromRemote: true);
        }
      } catch (_) {
        // fallback SQLite
      }
    }

    final local = await DatabaseService().getCategories();
    return (categories: local, fromRemote: false);
  }

  /// Rejoue les opérations de catégories en attente.
  Future<({int processed, int succeeded, int failed})> syncPending() async {
    final rows = await DatabaseService().getPendingSync(
      entity: _entity,
      limit: 100,
    );
    int processed = 0, succeeded = 0, failed = 0;

    for (final r in rows) {
      processed++;
      final int id = (r['id'] as int?) ?? 0;
      final op = r['operation']?.toString() ?? '';
      final payload = r['payloadJson']?.toString() ?? '{}';

      try {
        final map = (jsonDecode(payload) as Map).cast<String, dynamic>();
        final category = Category.fromMap(map);

        if (op == 'create') {
          await RemoteCategoriesService.instance.createCategory(category);
        } else if (op == 'update') {
          await RemoteCategoriesService.instance.updateCategory(category);
        } else if (op == 'delete') {
          await RemoteCategoriesService.instance.deleteCategory(category.id);
        }

        await DatabaseService().deletePendingSync(id);
        succeeded++;
      } catch (e) {
        failed++;
        if (id != 0) {
          await DatabaseService().markPendingSyncFailure(id, e.toString());
        }
      }
    }
    return (processed: processed, succeeded: succeeded, failed: failed);
  }
}
