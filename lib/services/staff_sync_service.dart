import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/services/api/remote_staff_service.dart';
import 'package:school_manager/services/database_service.dart';

class StaffSyncResult {
  final bool usedOfflineFallback;
  final Object? remoteError;

  StaffSyncResult({required this.usedOfflineFallback, this.remoteError});
}

class StaffSyncService {
  StaffSyncService._();
  static final StaffSyncService instance = StaffSyncService._();

  final RemoteStaffService _remote = RemoteStaffService.instance;

  Future<List<Staff>> getAllStaff() async {
    try {
      final remoteList = await _remote.fetchStaff();
      final localList = await DatabaseService().getStaff();
      final remoteIds = remoteList.map((s) => s.id).toSet();
      
      return [
        ...remoteList,
        ...localList.where((s) => !remoteIds.contains(s.id))
      ];
    } catch (e) {
      debugPrint('[StaffSyncService] getAllStaff remote failed: $e');
      return await DatabaseService().getStaff();
    }
  }

  Future<StaffSyncResult> upsertStaff(Staff staff) async {
    try {
      final success = await _remote.bulkUpsert([staff]);
      if (success) {
        return StaffSyncResult(usedOfflineFallback: false);
      } else {
        throw Exception('Remote upsert failed');
      }
    } catch (e) {
      debugPrint('[StaffSyncService] Error upserting staff: $e');
      await DatabaseService().enqueuePendingSync(
        entity: 'staff',
        operation: 'upsert',
        entityId: staff.id,
        payloadJson: jsonEncode(staff.toMap()),
      );
      return StaffSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<StaffSyncResult> deleteStaff(String id) async {
    try {
      final success = await _remote.deleteStaff(id);
      if (success) {
        return StaffSyncResult(usedOfflineFallback: false);
      } else {
        throw Exception('Remote delete failed');
      }
    } catch (e) {
      debugPrint('[StaffSyncService] Error deleting staff: $e');
      await DatabaseService().enqueuePendingSync(
        entity: 'staff',
        operation: 'delete',
        entityId: id,
        payloadJson: jsonEncode({'id': id}),
      );
      return StaffSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<({int processed, int succeeded, int failed})> syncPending() async {
    final pending = await DatabaseService().getPendingSync(entity: 'staff');
    if (pending.isEmpty) return (processed: 0, succeeded: 0, failed: 0);

    int processed = 0;
    int succeeded = 0;
    int failed = 0;

    debugPrint('[StaffSyncService] Syncing ${pending.length} pending operations');

    for (var item in pending) {
      processed++;
      try {
        final payload = jsonDecode(item['payloadJson']) as Map<String, dynamic>;
        final operation = item['operation'] as String;

        if (operation == 'delete') {
          final success = await _remote.deleteStaff(item['entityId'] as String);
          if (!success) throw Exception('Remote delete failed');
        } else {
          final staff = Staff.fromMap(payload);
          final success = await _remote.bulkUpsert([staff]);
          if (!success) throw Exception('Remote upsert failed');
        }

        await DatabaseService().deletePendingSync(item['id'] as int);
        succeeded++;
      } catch (e) {
        failed++;
        debugPrint('[StaffSyncService] Failed to sync item ${item['id']}: $e');
        await DatabaseService().markPendingSyncFailure(item['id'] as int, e.toString());
      }
    }
    return (processed: processed, succeeded: succeeded, failed: failed);
  }
}
