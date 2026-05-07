import 'dart:convert';

import 'package:school_manager/services/api/remote_settings_service.dart';
import 'package:school_manager/services/api/token_storage_service.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsSyncService {
  SettingsSyncService._();
  static final SettingsSyncService instance = SettingsSyncService._();

  static const String _pendingEntity = 'school_settings';

  /// Sauvegarde les paramètres : essai API-first, fallback SharedPreferences + pending_sync.
  Future<({bool usedOfflineFallback, Object? remoteError})> upsertSettings(
    Map<String, String> settings,
  ) async {
    // Toujours sauvegarder localement
    final prefs = await SharedPreferences.getInstance();
    for (final entry in settings.entries) {
      await prefs.setString(entry.key, entry.value);
    }

    // Si pas de token, on reste offline
    final token = await TokenStorageService.instance.getAccessToken();
    if (token == null) {
      return (usedOfflineFallback: true, remoteError: null);
    }

    // Essai remote
    try {
      await RemoteSettingsService.instance.upsertSettings(settings);
      return (usedOfflineFallback: false, remoteError: null);
    } catch (e) {
      // Enqueue pour sync ultérieure
      await DatabaseService().enqueuePendingSync(
        entity: _pendingEntity,
        operation: 'upsert',
        entityId: 'batch',
        payloadJson: jsonEncode(settings),
      );
      return (usedOfflineFallback: true, remoteError: e);
    }
  }

  /// Charge les paramètres : essai API-first (si forceRemote), fallback SharedPreferences.
  Future<({Map<String, String> settings, bool fromRemote})> loadSettings({
    bool forceRemote = true,
  }) async {
    final token = await TokenStorageService.instance.getAccessToken();
    if (forceRemote && token != null) {
      try {
        final remote = await RemoteSettingsService.instance.getSettings();
        if (remote.isNotEmpty) {
          // Synchronise le cache local avec les valeurs distantes
          final prefs = await SharedPreferences.getInstance();
          for (final entry in remote.entries) {
            await prefs.setString(entry.key, entry.value);
          }
          return (settings: remote, fromRemote: true);
        }
      } catch (_) {
        // fallback local
      }
    }

    // Fallback SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final keys = [
      'school_name',
      'school_address',
      'school_bp',
      'school_phone',
      'school_email',
      'school_website',
      'school_motto',
      'school_director',
      'school_director_primary',
      'school_director_college',
      'school_director_lycee',
      'school_director_university',
      'school_code',
      'school_level',
      'school_ministry',
      'school_republic_motto',
      'school_republic',
      'school_education_direction',
      'school_inspection',
      'report_card_footer_note',
      'school_slogan',
      'school_admin_civility',
      'school_civility_primary',
      'school_civility_college',
      'school_civility_lycee',
      'school_civility_university',
      'academic_year',
      'school_registration_fees',
    ];
    final result = <String, String>{};
    for (final k in keys) {
      final v = prefs.get(k);
      if (v != null) result[k] = v.toString();
    }
    return (settings: result, fromRemote: false);
  }

  /// Rejoue les settings en attente de sync.
  Future<({int processed, int succeeded, int failed})> syncPending() async {
    final rows = await DatabaseService().getPendingSync(
      entity: _pendingEntity,
      limit: 50,
    );
    int processed = 0, succeeded = 0, failed = 0;

    for (final r in rows) {
      processed++;
      final int id = (r['id'] as int?) ?? 0;
      final payload = r['payloadJson']?.toString() ?? '{}';

      try {
        final map = (jsonDecode(payload) as Map).cast<String, String>();
        await RemoteSettingsService.instance.upsertSettings(map);
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
