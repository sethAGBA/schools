import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/discipline/discipline_data.dart';
import 'package:school_manager/screens/discipline/discipline_page.dart';

class FakeDisciplineData implements DisciplineData {
  final List<Student> _students = [];
  final List<String> _classes = [];
  int _seq = 1;
  final List<Map<String, dynamic>> _attendance = [];
  final List<Map<String, dynamic>> _sanctions = [];

  void seedStudent(Student s) {
    _students.add(s);
    if (!_classes.contains(s.className)) _classes.add(s.className);
  }

  @override
  Future<List<Student>> getStudents({required String academicYear}) async =>
      _students.where((s) => s.academicYear == academicYear).toList();

  @override
  Future<List<String>> getClassNames({required String academicYear}) async =>
      _classes;

  @override
  Future<List<Map<String, dynamic>>> getAttendanceTotals({
    required String academicYear,
    String? className,
    String? studentId,
  }) async {
    final filtered = _attendance.where((e) {
      if (e['academicYear'] != academicYear) return false;
      if ((className ?? '').trim().isNotEmpty && e['className'] != className) {
        return false;
      }
      if ((studentId ?? '').trim().isNotEmpty && e['studentId'] != studentId) {
        return false;
      }
      return true;
    }).toList();

    final Map<String, Map<String, dynamic>> acc = {};
    for (final e in filtered) {
      final id = e['studentId'] as String;
      acc.putIfAbsent(id, () {
        return {
          'studentId': id,
          'studentName': e['studentName'],
          'className': e['className'],
          'absenceMinutes': 0,
          'retardMinutes': 0,
          'absenceCount': 0,
          'retardCount': 0,
        };
      });
      final row = acc[id]!;
      final type = (e['type'] as String?) ?? '';
      final minutes = (e['minutes'] as int?) ?? 0;
      if (type == 'absence') {
        row['absenceMinutes'] = (row['absenceMinutes'] as int) + minutes;
        row['absenceCount'] = (row['absenceCount'] as int) + 1;
      } else if (type == 'retard') {
        row['retardMinutes'] = (row['retardMinutes'] as int) + minutes;
        row['retardCount'] = (row['retardCount'] as int) + 1;
      }
    }
    final list = acc.values.toList();
    list.sort(
      (a, b) =>
          (a['studentName'] as String).compareTo((b['studentName'] as String)),
    );
    return list;
  }

  @override
  Future<List<Map<String, dynamic>>> getAttendanceEvents({
    required String academicYear,
    String? className,
    String? studentId,
    String? type,
  }) async {
    return _attendance.where((e) {
      if (e['academicYear'] != academicYear) return false;
      if ((className ?? '').trim().isNotEmpty && e['className'] != className) {
        return false;
      }
      if ((studentId ?? '').trim().isNotEmpty && e['studentId'] != studentId) {
        return false;
      }
      if ((type ?? '').trim().isNotEmpty && e['type'] != type) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getSanctionEvents({
    required String academicYear,
    String? className,
    String? studentId,
    String? type,
  }) async {
    return _sanctions.where((e) {
      if (e['academicYear'] != academicYear) return false;
      if ((className ?? '').trim().isNotEmpty && e['className'] != className) {
        return false;
      }
      if ((studentId ?? '').trim().isNotEmpty && e['studentId'] != studentId) {
        return false;
      }
      if ((type ?? '').trim().isNotEmpty && e['type'] != type) return false;
      return true;
    }).toList();
  }

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
  }) async {
    final student = _students.firstWhere((s) => s.id == studentId);
    _attendance.add({
      'id': _seq++,
      'studentId': studentId,
      'studentName': student.name,
      'academicYear': academicYear,
      'className': className,
      'date': date.toIso8601String(),
      'type': type,
      'minutes': minutes,
      'justified': justified ? 1 : 0,
      'reason': reason ?? '',
      'recordedBy': recordedBy,
    });
    return _seq - 1;
  }

  @override
  Future<int> addSanctionEvent({
    required String studentId,
    required String academicYear,
    required String className,
    required DateTime date,
    required String type,
    required String description,
    String? recordedBy,
  }) async {
    final student = _students.firstWhere((s) => s.id == studentId);
    _sanctions.add({
      'id': _seq++,
      'studentId': studentId,
      'studentName': student.name,
      'academicYear': academicYear,
      'className': className,
      'date': date.toIso8601String(),
      'type': type,
      'description': description,
      'recordedBy': recordedBy,
    });
    return _seq - 1;
  }

  @override
  Future<void> deleteAttendanceEvent({required int id}) async {
    _attendance.removeWhere((e) => e['id'] == id);
  }

  @override
  Future<void> deleteSanctionEvent({required int id}) async {
    _sanctions.removeWhere((e) => e['id'] == id);
  }
}

void main() {
  testWidgets('DisciplinePage shows sanctions and attendance lists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final fake = FakeDisciplineData();
    fake.seedStudent(
      Student(
        id: 'S1',
        firstName: 'Jean',
        lastName: 'Dupont',
        dateOfBirth: '2015-01-01',
        address: 'Addr',
        gender: 'M',
        contactNumber: '000',
        email: 'j@example.com',
        emergencyContact: '000',
        guardianName: 'G',
        guardianContact: '000',
        className: 'CE1',
        academicYear: '2024-2025',
        enrollmentDate: '2024-09-01',
      ),
    );
    await fake.addAttendanceEvent(
      studentId: 'S1',
      academicYear: '2024-2025',
      className: 'CE1',
      date: DateTime.parse('2025-01-10'),
      type: 'retard',
      minutes: 10,
      justified: false,
      reason: 'Transport',
    );
    await fake.addSanctionEvent(
      studentId: 'S1',
      academicYear: '2024-2025',
      className: 'CE1',
      date: DateTime.parse('2025-01-11'),
      type: 'avertissement',
      description: 'Bavardage',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DisciplinePage(data: fake, initialAcademicYear: '2024-2025'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suivi de la discipline'), findsOneWidget);
    expect(find.text('Absences & retards'), findsOneWidget);
    expect(find.text('Cumul par élève'), findsOneWidget);
    expect(find.text('Retard'), findsOneWidget);
    expect(find.textContaining('Retards: 0h10 (1)'), findsOneWidget);

    final tabController = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    tabController.animateTo(1);
    await tester.pumpAndSettle();

    expect(find.text('Sanctions & avertissements'), findsOneWidget);
    expect(find.text('avertissement'), findsOneWidget);
    expect(find.textContaining('Bavardage'), findsOneWidget);
  });
}
