import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/services/api/remote_timetable_service.dart';
import 'package:school_manager/services/database_service.dart';

class TimetableSyncResult {
  final bool success;
  final bool usedOfflineFallback;
  final String? error;

  TimetableSyncResult({
    required this.success,
    this.usedOfflineFallback = false,
    this.error,
  });
}

class TimetableSyncService {
  TimetableSyncService._internal();
  static final TimetableSyncService instance = TimetableSyncService._internal();

  final DatabaseService _db = DatabaseService();
  final RemoteTimetableService _remote = RemoteTimetableService.instance;

  Future<TimetableSyncResult> upsertEntry(TimetableEntry entry) async {
    try {
      // 1. Try Remote
      await _remote.bulkUpsert([entry]);
      
      // 2. If successful, update local cache (remote_id will be handled in next fetch or we can assume it's synced)
      // Actually, bulkUpsert doesn't return the remoteId here, but we can assume it exists on server.
      return TimetableSyncResult(success: true);
    } catch (e) {
      debugPrint('[TimetableSyncService] Remote upsert failed, queueing: $e');
      
      // 3. Queue for sync
      await _db.enqueuePendingSync(
        entity: 'timetable',
        operation: 'upsert',
        entityId: entry.id?.toString() ?? 'new_${DateTime.now().millisecondsSinceEpoch}',
        payloadJson: jsonEncode(entry.toMap()),
      );
      
      return TimetableSyncResult(success: true, usedOfflineFallback: true);
    }
  }

  Future<TimetableSyncResult> deleteEntry(TimetableEntry entry) async {
    final remoteId = entry.remoteId;
    if (remoteId == null) {
      // If it's local only, we don't need to sync deletion with remote
      return TimetableSyncResult(success: true);
    }

    try {
      await _remote.deleteEntry(remoteId);
      return TimetableSyncResult(success: true);
    } catch (e) {
      debugPrint('[TimetableSyncService] Remote delete failed, queueing: $e');
      await _db.enqueuePendingSync(
        entity: 'timetable',
        operation: 'delete',
        entityId: remoteId,
        payloadJson: jsonEncode(entry.toMap()),
      );
      return TimetableSyncResult(success: true, usedOfflineFallback: true);
    }
  }

  Future<void> syncPending() async {
    final pending = await _db.getPendingSyncByEntity('timetable');
    if (pending.isEmpty) return;

    debugPrint('[TimetableSyncService] Syncing ${pending.length} pending operations');

    for (var item in pending) {
      try {
        final payload = jsonDecode(item['payloadJson'] as String) as Map<String, dynamic>;
        final operation = item['operation'] as String;
        final entry = TimetableEntry.fromMap(payload);

        if (operation == 'delete') {
          if (entry.remoteId != null) {
            await _remote.deleteEntry(entry.remoteId!);
          }
        } else {
          await _remote.bulkUpsert([entry]);
        }

        await _db.deletePendingSync(item['id'] as int);
      } catch (e) {
        debugPrint('[TimetableSyncService] Failed to sync item ${item['id']}: $e');
        await _db.incrementPendingSyncAttempts(item['id'] as int, e.toString());
      }
    }
  }
}
