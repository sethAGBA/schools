import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';

abstract class ReEnrollmentData {
  Future<List<Class>> getClasses();

  Future<List<Student>> getStudentsByClassAndClassYear(
    String className,
    String academicYear,
  );

  Future<Map<String, dynamic>?> getPreferredReportCardForStudent({
    required String studentId,
    required String className,
    required String academicYear,
  });

  Future<Map<String, double>> getClassPassingThresholds(
    String className,
    String academicYear,
  );

  Future<void> updateStudent(String oldId, Student updatedStudent);

  Future<int> countReportCardsForClassYear({
    required String className,
    required String academicYear,
  });

  Future<int> countReportCardsForAcademicYear(String academicYear);

  Future<void> archiveReportCardsForYear(String academicYear);

  Future<void> logAudit({
    required String category,
    required String action,
    String? details,
    String? username,
    bool success,
  });
}

class DatabaseReEnrollmentData implements ReEnrollmentData {
  DatabaseReEnrollmentData({DatabaseService? db})
    : _db = db ?? DatabaseService();

  final DatabaseService _db;

  @override
  Future<List<Class>> getClasses() => _db.getClasses();

  @override
  Future<List<Student>> getStudentsByClassAndClassYear(
    String className,
    String academicYear,
  ) => _db.getStudentsByClassAndClassYear(className, academicYear);

  @override
  Future<Map<String, dynamic>?> getPreferredReportCardForStudent({
    required String studentId,
    required String className,
    required String academicYear,
  }) => _db.getPreferredReportCardForStudent(
    studentId: studentId,
    className: className,
    academicYear: academicYear,
  );

  @override
  Future<Map<String, double>> getClassPassingThresholds(
    String className,
    String academicYear,
  ) => _db.getClassPassingThresholds(className, academicYear);

  @override
  Future<void> updateStudent(String oldId, Student updatedStudent) =>
      _db.updateStudent(oldId, updatedStudent);

  @override
  Future<int> countReportCardsForClassYear({
    required String className,
    required String academicYear,
  }) => _db.countReportCardsForClassYear(
    className: className,
    academicYear: academicYear,
  );

  @override
  Future<int> countReportCardsForAcademicYear(String academicYear) =>
      _db.countReportCardsForAcademicYear(academicYear);

  @override
  Future<void> archiveReportCardsForYear(String academicYear) =>
      _db.archiveReportCardsForYear(academicYear);

  @override
  Future<void> logAudit({
    required String category,
    required String action,
    String? details,
    String? username,
    bool success = true,
  }) => _db.logAudit(
    category: category,
    action: action,
    details: details,
    username: username,
    success: success,
  );
}
