import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';

abstract class DisciplineData {
  Future<List<Student>> getStudents({required String academicYear});
  Future<List<String>> getClassNames({required String academicYear});

  Future<List<Map<String, dynamic>>> getAttendanceTotals({
    required String academicYear,
    String? className,
    String? studentId,
  });

  Future<List<Map<String, dynamic>>> getAttendanceEvents({
    required String academicYear,
    String? className,
    String? studentId,
    String? type, // absence | retard
  });

  Future<List<Map<String, dynamic>>> getSanctionEvents({
    required String academicYear,
    String? className,
    String? studentId,
    String? type, // avertissement | blame | exclusion | autre
  });

  Future<int> addAttendanceEvent({
    required String studentId,
    required String academicYear,
    required String className,
    required DateTime date,
    required String type,
    required int minutes,
    required bool justified,
    String? reason,
    String? recordedBy,
  });

  Future<int> addSanctionEvent({
    required String studentId,
    required String academicYear,
    required String className,
    required DateTime date,
    required String type,
    required String description,
    String? recordedBy,
  });

  Future<void> deleteAttendanceEvent({required int id});
  Future<void> deleteSanctionEvent({required int id});
}

class DatabaseDisciplineData implements DisciplineData {
  final DatabaseService _db;
  DatabaseDisciplineData([DatabaseService? db]) : _db = db ?? DatabaseService();

  @override
  Future<List<Student>> getStudents({required String academicYear}) =>
      _db.getStudents(academicYear: academicYear);

  @override
  Future<List<String>> getClassNames({required String academicYear}) async {
    final classes = await _db.getClasses();
    return classes
        .where((c) => c.academicYear == academicYear)
        .map((c) => c.name)
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<List<Map<String, dynamic>>> getAttendanceEvents({
    required String academicYear,
    String? className,
    String? studentId,
    String? type,
  }) => _db.getAttendanceEvents(
    academicYear: academicYear,
    className: className,
    studentId: studentId,
    type: type,
  );

  @override
  Future<List<Map<String, dynamic>>> getAttendanceTotals({
    required String academicYear,
    String? className,
    String? studentId,
  }) => _db.getAttendanceTotals(
    academicYear: academicYear,
    className: className,
    studentId: studentId,
  );

  @override
  Future<List<Map<String, dynamic>>> getSanctionEvents({
    required String academicYear,
    String? className,
    String? studentId,
    String? type,
  }) => _db.getSanctionEvents(
    academicYear: academicYear,
    className: className,
    studentId: studentId,
    type: type,
  );

  @override
  Future<int> addAttendanceEvent({
    required String studentId,
    required String academicYear,
    required String className,
    required DateTime date,
    required String type,
    required int minutes,
    required bool justified,
    String? reason,
    String? recordedBy,
  }) => _db.insertAttendanceEvent(
    studentId: studentId,
    academicYear: academicYear,
    className: className,
    date: date,
    type: type,
    minutes: minutes,
    justified: justified,
    reason: reason,
    recordedBy: recordedBy,
  );

  @override
  Future<int> addSanctionEvent({
    required String studentId,
    required String academicYear,
    required String className,
    required DateTime date,
    required String type,
    required String description,
    String? recordedBy,
  }) => _db.insertSanctionEvent(
    studentId: studentId,
    academicYear: academicYear,
    className: className,
    date: date,
    type: type,
    description: description,
    recordedBy: recordedBy,
  );

  @override
  Future<void> deleteAttendanceEvent({required int id}) =>
      _db.deleteAttendanceEvent(id: id);

  @override
  Future<void> deleteSanctionEvent({required int id}) =>
      _db.deleteSanctionEvent(id: id);
}
