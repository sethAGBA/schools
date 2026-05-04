import 'dart:convert';

import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/api/remote_students_service.dart';
import 'package:school_manager/services/database_service.dart';

class StudentsUpsertResult {
  const StudentsUpsertResult({
    required this.usedOfflineFallback,
    this.remoteError,
  });

  final bool usedOfflineFallback;
  final Object? remoteError;
}

class StudentsSyncService {
  StudentsSyncService._();
  static final StudentsSyncService instance = StudentsSyncService._();

  Future<StudentsUpsertResult> upsertStudent(
    Student student, {
    required bool isUpdate,
  }) async {
    // Try remote first
    try {
      if (isUpdate) {
        await RemoteStudentsService.instance.updateStudent(student);
      } else {
        await RemoteStudentsService.instance.createStudent(student);
      }

      // Keep local cache in sync too
      if (isUpdate) {
        await DatabaseService().updateStudent(student.id, student);
      } else {
        await DatabaseService().insertStudent(student);
      }
      return const StudentsUpsertResult(usedOfflineFallback: false);
    } catch (remoteError) {
      // fallback offline: store locally + enqueue pending sync
      if (isUpdate) {
        await DatabaseService().updateStudent(student.id, student);
        await DatabaseService().enqueuePendingSync(
          entity: 'student',
          operation: 'update',
          entityId: student.id,
          payloadJson: jsonEncode(student.toMap()),
        );
      } else {
        await DatabaseService().insertStudent(student);
        await DatabaseService().enqueuePendingSync(
          entity: 'student',
          operation: 'create',
          entityId: student.id,
          payloadJson: jsonEncode(student.toMap()),
        );
      }

      return StudentsUpsertResult(
        usedOfflineFallback: true,
        remoteError: remoteError,
      );
    }
  }

  Future<({int processed, int succeeded, int failed})> syncPending() async {
    final rows = await DatabaseService().getPendingSync(entity: 'student', limit: 200);
    int processed = 0;
    int succeeded = 0;
    int failed = 0;

    for (final r in rows) {
      processed += 1;
      final int id = (r['id'] as int?) ?? 0;
      final op = r['operation']?.toString() ?? '';
      final payload = r['payloadJson']?.toString() ?? '';

      try {
        final map = (jsonDecode(payload) as Map).cast<String, dynamic>();
        final student = Student.fromMap(map);

        if (op == 'create') {
          await RemoteStudentsService.instance.createStudent(student);
        } else if (op == 'update') {
          await RemoteStudentsService.instance.updateStudent(student);
        } else if (op == 'delete') {
          await RemoteStudentsService.instance.deleteStudent(student.id);
        } else {
          throw Exception('Unknown operation: $op');
        }

        await DatabaseService().deletePendingSync(id);
        succeeded += 1;
      } catch (e) {
        failed += 1;
        if (id != 0) {
          await DatabaseService().markPendingSyncFailure(id, e.toString());
        }
      }
    }

    return (processed: processed, succeeded: succeeded, failed: failed);
  }

  Future<StudentsUpsertResult> deleteStudent(Student student) async {
    try {
      await RemoteStudentsService.instance.deleteStudent(student.id);
      await DatabaseService().softDeleteStudents(studentIds: [student.id]);
      return const StudentsUpsertResult(usedOfflineFallback: false);
    } catch (remoteError) {
      await DatabaseService().softDeleteStudents(studentIds: [student.id]);
      await DatabaseService().enqueuePendingSync(
        entity: 'student',
        operation: 'delete',
        entityId: student.id,
        payloadJson: jsonEncode(student.toMap()),
      );
      return StudentsUpsertResult(
        usedOfflineFallback: true,
        remoteError: remoteError,
      );
    }
  }
}

