import 'package:flutter/foundation.dart';
import 'package:school_manager/services/students_sync_service.dart';
import 'package:school_manager/services/academics_sync_service.dart';
import 'package:school_manager/services/finance_sync_service.dart';
import 'package:school_manager/services/staff_sync_service.dart';
import 'package:school_manager/services/discipline_sync_service.dart';
import 'package:school_manager/services/timetable_sync_service.dart';
import 'package:school_manager/services/mock_exams_sync_service.dart';
import 'package:school_manager/services/expense_sync_service.dart';
import 'package:school_manager/services/settings_sync_service.dart';
import 'package:school_manager/services/categories_sync_service.dart';

class SyncManager extends ChangeNotifier {
  SyncManager._internal();
  static final SyncManager instance = SyncManager._internal();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();
    debugPrint('[SyncManager] Starting global sync...');

    try {
      await Future.wait<dynamic>([
        StudentsSyncService.instance.syncPending(),
        AcademicsSyncService.instance.syncPending(),
        FinanceSyncService.instance.syncPending(),
        StaffSyncService.instance.syncPending(),
        DisciplineSyncService.instance.syncPending(),
        TimetableSyncService.instance.syncPending(),
        MockExamsSyncService.instance.syncPending(),
        ExpenseSyncService.instance.syncPending(),
        SettingsSyncService.instance.syncPending(),
        CategoriesSyncService.instance.syncPending(),
      ]);
      debugPrint('[SyncManager] Global sync completed successfully.');
    } catch (e) {
      debugPrint('[SyncManager] Global sync failed: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
