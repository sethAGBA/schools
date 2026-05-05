import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:school_manager/services/api/remote_academics_service.dart';
import 'package:school_manager/services/database_service.dart';

class AcademicsSyncResult {
  final bool usedOfflineFallback;
  final Object? remoteError;
  AcademicsSyncResult({required this.usedOfflineFallback, this.remoteError});
}

class AcademicsSyncService {
  AcademicsSyncService._();
  static final AcademicsSyncService instance = AcademicsSyncService._();

  /// Syncs a single grade (aggregated from notes and appreciation)
  Future<AcademicsSyncResult> upsertGrade({
    required String studentId,
    required String subjectId,
    required String period,
    double? devoirNote,
    double? compositionNote,
    double? average,
    String? teacherComment,
    double? classAverage,
  }) async {
    final payload = {
      'studentId': studentId,
      'subjectId': subjectId,
      'period': period,
      'devoirNote': devoirNote,
      'compositionNote': compositionNote,
      'average': average,
      'teacherComment': teacherComment,
      'classAverage': classAverage,
    };

    try {
      await RemoteAcademicsService.instance.bulkUpsertGrades([payload]);
      return AcademicsSyncResult(usedOfflineFallback: false);
    } catch (e) {
      debugPrint('[AcademicsSyncService] Error upserting grade: $e');
      
      // Enqueue for later
      await DatabaseService().enqueuePendingSync(
        entity: 'grade',
        operation: 'upsert',
        entityId: '$studentId|$subjectId|$period',
        payloadJson: jsonEncode(payload),
      );

      return AcademicsSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  /// Syncs multiple grades at once
  Future<AcademicsSyncResult> bulkUpsertGrades(List<Map<String, dynamic>> grades) async {
    try {
      await RemoteAcademicsService.instance.bulkUpsertGrades(grades);
      return AcademicsSyncResult(usedOfflineFallback: false);
    } catch (e) {
      debugPrint('[AcademicsSyncService] Error bulk upserting grades: $e');
      
      for (final g in grades) {
        await DatabaseService().enqueuePendingSync(
          entity: 'grade',
          operation: 'upsert',
          entityId: '${g['studentId']}|${g['subjectId']}|${g['period']}',
          payloadJson: jsonEncode(g),
        );
      }

      return AcademicsSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<({int processed, int succeeded, int failed})> syncPending() async {
    final rows = await DatabaseService().getPendingSync(entity: 'grade', limit: 200);
    if (rows.isEmpty) return (processed: 0, succeeded: 0, failed: 0);

    int processed = 0;
    int succeeded = 0;
    int failed = 0;

    final List<Map<String, dynamic>> batch = [];
    final List<int> rowIds = [];

    for (final r in rows) {
      processed++;
      try {
        final payload = jsonDecode(r['payloadJson']) as Map<String, dynamic>;
        batch.add(payload);
        rowIds.add(r['id'] as int);
      } catch (e) {
        failed++;
        await DatabaseService().markPendingSyncFailure(r['id'] as int, e.toString());
      }
    }

    if (batch.isNotEmpty) {
      try {
        await RemoteAcademicsService.instance.bulkUpsertGrades(batch);
        for (final id in rowIds) {
          await DatabaseService().deletePendingSync(id);
        }
        succeeded += batch.length;
      } catch (e) {
        failed += batch.length;
        for (final id in rowIds) {
          await DatabaseService().markPendingSyncFailure(id, e.toString());
        }
      }
    }

    return (processed: processed, succeeded: succeeded, failed: failed);
  }
}
