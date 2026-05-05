import 'dart:convert';
import 'package:school_manager/models/attendance_event.dart';
import 'package:school_manager/models/sanction_event.dart';
import 'package:school_manager/services/api/remote_discipline_service.dart';
import 'package:school_manager/services/database_service.dart';

class DisciplineSyncResult {
  final bool usedOfflineFallback;
  final Object? remoteError;

  DisciplineSyncResult({this.usedOfflineFallback = false, this.remoteError});
}

class DisciplineSyncService {
  DisciplineSyncService._();
  static final DisciplineSyncService instance = DisciplineSyncService._();

  Future<DisciplineSyncResult> upsertAttendance(AttendanceEvent ev) async {
    try {
      await RemoteDisciplineService.instance.bulkUpsertAttendance([ev.toMap()]);
      return DisciplineSyncResult(usedOfflineFallback: false);
    } catch (e) {
      if (ev.id != null) {
        await DatabaseService().enqueuePendingSync(
          entity: 'attendance_event',
          entityId: ev.id.toString(),
          operation: 'upsert',
          payloadJson: jsonEncode(ev.toMap()),
        );
      }
      return DisciplineSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<DisciplineSyncResult> deleteAttendance(AttendanceEvent ev) async {
    if (ev.remoteId == null) {
      // If no remoteId, we just delete locally (already done usually)
      return DisciplineSyncResult(usedOfflineFallback: false);
    }
    try {
      await RemoteDisciplineService.instance.deleteAttendance(ev.remoteId!);
      return DisciplineSyncResult(usedOfflineFallback: false);
    } catch (e) {
      await DatabaseService().enqueuePendingSync(
        entity: 'attendance_event',
        entityId: ev.id?.toString() ?? 'unknown',
        operation: 'delete',
        payloadJson: jsonEncode({'remote_id': ev.remoteId}),
      );
      return DisciplineSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<DisciplineSyncResult> upsertSanction(SanctionEvent ev) async {
    try {
      await RemoteDisciplineService.instance.bulkUpsertSanctions([ev.toMap()]);
      return DisciplineSyncResult(usedOfflineFallback: false);
    } catch (e) {
      if (ev.id != null) {
        await DatabaseService().enqueuePendingSync(
          entity: 'sanction_event',
          entityId: ev.id.toString(),
          operation: 'upsert',
          payloadJson: jsonEncode(ev.toMap()),
        );
      }
      return DisciplineSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<DisciplineSyncResult> deleteSanction(SanctionEvent ev) async {
    if (ev.remoteId == null) {
      return DisciplineSyncResult(usedOfflineFallback: false);
    }
    try {
      await RemoteDisciplineService.instance.deleteSanction(ev.remoteId!);
      return DisciplineSyncResult(usedOfflineFallback: false);
    } catch (e) {
      await DatabaseService().enqueuePendingSync(
        entity: 'sanction_event',
        entityId: ev.id?.toString() ?? 'unknown',
        operation: 'delete',
        payloadJson: jsonEncode({'remote_id': ev.remoteId}),
      );
      return DisciplineSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<({int processed, int succeeded, int failed})> syncPending() async {
    int processed = 0;
    int succeeded = 0;
    int failed = 0;

    // Attendance
    final attRows = await DatabaseService().getPendingSync(entity: 'attendance_event', limit: 100);
    for (final r in attRows) {
      processed++;
      final op = r['operation'] as String;
      final payload = jsonDecode(r['payloadJson'] as String);
      final syncId = r['id'] as int;
      try {
        if (op == 'delete') {
          final rid = payload['remote_id'] as String?;
          if (rid != null) {
            await RemoteDisciplineService.instance.deleteAttendance(rid);
          }
        } else {
          await RemoteDisciplineService.instance.bulkUpsertAttendance([payload]);
        }
        await DatabaseService().deletePendingSync(syncId);
        succeeded++;
      } catch (e) {
        failed++;
        await DatabaseService().markPendingSyncFailure(syncId, e.toString());
      }
    }

    // Sanctions
    final sancRows = await DatabaseService().getPendingSync(entity: 'sanction_event', limit: 100);
    for (final r in sancRows) {
      processed++;
      final op = r['operation'] as String;
      final payload = jsonDecode(r['payloadJson'] as String);
      final syncId = r['id'] as int;
      try {
        if (op == 'delete') {
          final rid = payload['remote_id'] as String?;
          if (rid != null) {
            await RemoteDisciplineService.instance.deleteSanction(rid);
          }
        } else {
          await RemoteDisciplineService.instance.bulkUpsertSanctions([payload]);
        }
        await DatabaseService().deletePendingSync(syncId);
        succeeded++;
      } catch (e) {
        failed++;
        await DatabaseService().markPendingSyncFailure(syncId, e.toString());
      }
    }

    return (processed: processed, succeeded: succeeded, failed: failed);
  }
}
