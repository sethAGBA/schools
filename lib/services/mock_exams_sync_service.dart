import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:school_manager/services/api/remote_mock_exams_service.dart';
import 'package:school_manager/services/database_service.dart';

class MockExamsSyncResult {
  final bool usedOfflineFallback;
  final Object? remoteError;
  MockExamsSyncResult({required this.usedOfflineFallback, this.remoteError});
}

class MockExamsSyncService extends ChangeNotifier {
  MockExamsSyncService._();
  static final MockExamsSyncService instance = MockExamsSyncService._();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  String _dataSource = 'Local 💾';
  String get dataSource => _dataSource;

  /// Loads sessions with optional remote refresh
  Future<List<String>> loadSessions({bool forceRemote = false}) async {
    if (forceRemote) {
      try {
        _isSyncing = true;
        notifyListeners();
        
        final remoteSessions = await RemoteMockExamsService.instance.getSessions();
        // Update local DB
        await DatabaseService().clearMockExamSessions();
        for (var s in remoteSessions) {
          await DatabaseService().addMockExamSession(s['name']);
        }
        
        _dataSource = 'Cloud ☁️';
      } catch (e) {
        debugPrint('[MockExamsSyncService] Error loading remote sessions: $e');
      } finally {
        _isSyncing = false;
        notifyListeners();
      }
    }
    
    return await DatabaseService().getMockExamSessions();
  }

  Future<MockExamsSyncResult> saveGrade({
    required String studentId,
    required String subjectId,
    required String session,
    required double value,
  }) async {
    final payload = {
      'studentId': studentId,
      'subjectId': subjectId,
      'session': session,
      'value': value,
    };

    try {
      await RemoteMockExamsService.instance.bulkUpsertGrades([payload]);
      return MockExamsSyncResult(usedOfflineFallback: false);
    } catch (e) {
      debugPrint('[MockExamsSyncService] Error saving mock grade: $e');
      
      await DatabaseService().enqueuePendingSync(
        entity: 'mock_grade',
        operation: 'upsert',
        entityId: '$studentId|$subjectId|$session',
        payloadJson: jsonEncode(payload),
      );

      return MockExamsSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<MockExamsSyncResult> saveSession(String name) async {
    try {
      await RemoteMockExamsService.instance.syncSessions([{'name': name, 'orderIndex': 0}]);
      return MockExamsSyncResult(usedOfflineFallback: false);
    } catch (e) {
      await DatabaseService().enqueuePendingSync(
        entity: 'mock_session',
        operation: 'create',
        entityId: name,
        payloadJson: jsonEncode({'name': name}),
      );
      return MockExamsSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<void> syncAll() async {
    _isSyncing = true;
    notifyListeners();
    
    await syncPending();
    await loadSessions(forceRemote: true);
    
    _isSyncing = false;
    notifyListeners();
  }

  Future<void> syncPending() async {
    // 1. Sync Sessions
    final sessionRows = await DatabaseService().getPendingSync(entity: 'mock_session');
    if (sessionRows.isNotEmpty) {
      try {
        final List<Map<String, dynamic>> sessions = [];
        for (var r in sessionRows) {
          sessions.add(jsonDecode(r['payloadJson']));
        }
        await RemoteMockExamsService.instance.syncSessions(sessions);
        for (var r in sessionRows) {
          await DatabaseService().deletePendingSync(r['id']);
        }
      } catch (e) {
        debugPrint('[MockExamsSyncService] Failed to sync pending sessions: $e');
      }
    }

    // 2. Sync Grades
    final gradeRows = await DatabaseService().getPendingSync(entity: 'mock_grade');
    if (gradeRows.isNotEmpty) {
      try {
        final List<Map<String, dynamic>> grades = [];
        for (var r in gradeRows) {
          grades.add(jsonDecode(r['payloadJson']));
        }
        await RemoteMockExamsService.instance.bulkUpsertGrades(grades);
        for (var r in gradeRows) {
          await DatabaseService().deletePendingSync(r['id']);
        }
      } catch (e) {
        debugPrint('[MockExamsSyncService] Failed to sync pending grades: $e');
      }
    }
  }
}
