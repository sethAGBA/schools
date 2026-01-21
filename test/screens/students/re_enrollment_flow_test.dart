import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/students/re_enrollment_batch_dialog.dart';
import 'package:school_manager/screens/students/re_enrollment_data.dart';
import 'package:school_manager/screens/students/re_enrollment_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeReEnrollmentData implements ReEnrollmentData {
  final List<Class> classes = [];
  final Map<String, Student> studentsById = {};
  final Map<String, List<Student>> studentsByClassYear = {};
  final Map<String, Map<String, dynamic>> preferredReportCardByKey = {};
  final Map<String, Map<String, double>> thresholdsByKey = {};
  final List<Map<String, dynamic>> auditLogs = [];
  int archiveCalls = 0;

  String _classYearKey(String className, String year) => '$className::$year';

  String _preferredKey(String studentId, String className, String year) =>
      '$studentId::$className::$year';

  @override
  Future<List<Class>> getClasses() async => classes;

  @override
  Future<List<Student>> getStudentsByClassAndClassYear(
    String className,
    String academicYear,
  ) async => List<Student>.from(
    studentsByClassYear[_classYearKey(className, academicYear)] ?? const [],
  );

  @override
  Future<Map<String, dynamic>?> getPreferredReportCardForStudent({
    required String studentId,
    required String className,
    required String academicYear,
  }) async =>
      preferredReportCardByKey[_preferredKey(
        studentId,
        className,
        academicYear,
      )];

  @override
  Future<Map<String, double>> getClassPassingThresholds(
    String className,
    String academicYear,
  ) async =>
      thresholdsByKey[_classYearKey(className, academicYear)] ??
      const {
        'felicitations': 16.0,
        'encouragements': 14.0,
        'admission': 12.0,
        'avertissement': 10.0,
        'conditions': 8.0,
        'redoublement': 8.0,
      };

  void _upsertStudent(Student student) {
    studentsById[student.id] = student;
    for (final entry in studentsByClassYear.entries) {
      entry.value.removeWhere((s) => s.id == student.id);
    }
    final key = _classYearKey(student.className, student.academicYear);
    studentsByClassYear.putIfAbsent(key, () => <Student>[]);
    studentsByClassYear[key]!.add(student);
  }

  @override
  Future<void> updateStudent(String oldId, Student updatedStudent) async {
    _upsertStudent(updatedStudent);
  }

  @override
  Future<int> countReportCardsForClassYear({
    required String className,
    required String academicYear,
  }) async {
    return preferredReportCardByKey.values
        .where(
          (m) =>
              m['className'] == className && m['academicYear'] == academicYear,
        )
        .length;
  }

  @override
  Future<int> countReportCardsForAcademicYear(String academicYear) async {
    return preferredReportCardByKey.values
        .where((m) => m['academicYear'] == academicYear)
        .length;
  }

  @override
  Future<void> archiveReportCardsForYear(String academicYear) async {
    archiveCalls += 1;
  }

  @override
  Future<void> logAudit({
    required String category,
    required String action,
    String? details,
    String? username,
    bool success = true,
  }) async {
    auditLogs.add({
      'category': category,
      'action': action,
      'details': details,
      'username': username,
      'success': success,
    });
  }
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 200,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for ${finder.description}');
}

Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 200,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for ${finder.description} to disappear');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'academic_year': '2024-2025',
      'current_username': 'tester',
    });
  });

  testWidgets('Per-class re-enrollment updates students and logs audit', (
    tester,
  ) async {
    final fake = FakeReEnrollmentData();

    fake.classes.addAll([
      Class(name: 'CE1', academicYear: '2025-2026'),
      Class(name: 'CE2', academicYear: '2025-2026'),
    ]);

    final s1 = Student(
      id: 'S1',
      firstName: 'Alice',
      lastName: 'A',
      dateOfBirth: '2015-01-01',
      address: 'Addr',
      gender: 'F',
      contactNumber: '000',
      email: 'a@example.com',
      emergencyContact: '000',
      guardianName: 'G',
      guardianContact: '000',
      className: 'CE1',
      academicYear: '2024-2025',
      enrollmentDate: '2024-09-01',
    );
    final s2 = Student(
      id: 'S2',
      firstName: 'Bob',
      lastName: 'B',
      dateOfBirth: '2015-01-01',
      address: 'Addr',
      gender: 'M',
      contactNumber: '000',
      email: 'b@example.com',
      emergencyContact: '000',
      guardianName: 'G',
      guardianContact: '000',
      className: 'CE1',
      academicYear: '2024-2025',
      enrollmentDate: '2024-09-01',
    );
    fake.updateStudent('S1', s1);
    fake.updateStudent('S2', s2);

    fake.preferredReportCardByKey['S1::CE1::2024-2025'] = {
      'studentId': 'S1',
      'className': 'CE1',
      'academicYear': '2024-2025',
      'decision': 'Admis en classe supérieure',
      'moyenne_annuelle': 13.5,
    };
    fake.preferredReportCardByKey['S2::CE1::2024-2025'] = {
      'studentId': 'S2',
      'className': 'CE1',
      'academicYear': '2024-2025',
      'decision': 'Admis en classe supérieure sous conditions',
      'moyenne_annuelle': 9.0,
    };

    final source = Class(name: 'CE1', academicYear: '2024-2025');
    final students = await fake.getStudentsByClassAndClassYear(
      'CE1',
      '2024-2025',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<bool>(
                    context: context,
                    builder: (_) => ReEnrollmentDialog(
                      sourceClass: source,
                      students: students,
                      data: fake,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await pumpUntilFound(
      tester,
      find.byKey(ReEnrollmentDialog.targetYearFieldKey),
    );

    await tester.enterText(
      find.byKey(ReEnrollmentDialog.targetYearFieldKey),
      '2025-2026',
    );
    await tester.tap(find.byKey(ReEnrollmentDialog.loadClassesButtonKey));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(ReEnrollmentDialog.admittedTargetDropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CE2').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ReEnrollmentDialog.applyButtonKey));
    await tester.tap(find.byKey(ReEnrollmentDialog.applyButtonKey));
    await tester.pumpAndSettle();

    // Archive prompt appears because report cards exist.
    await tester.tap(find.text('Continuer sans archiver'));
    await tester.pumpAndSettle();

    await pumpUntilFound(
      tester,
      find.byKey(ReEnrollmentDialog.confirmApplyButtonKey),
    );
    await tester.tap(find.byKey(ReEnrollmentDialog.confirmApplyButtonKey));
    await pumpUntilGone(tester, find.textContaining('Réinscription —'));

    final s1Updated = fake.studentsById['S1']!;
    final s2Updated = fake.studentsById['S2']!;
    expect(s1Updated.academicYear, '2025-2026');
    expect(s1Updated.className, 'CE2');
    expect(s2Updated.academicYear, '2025-2026');
    expect(
      s2Updated.className,
      'CE1',
    ); // Sous conditions -> redouble par défaut

    expect(
      fake.auditLogs.any(
        (l) => l['category'] == 're_enrollment' && l['action'] == 'apply',
      ),
      isTrue,
    );
  });

  testWidgets('Batch re-enrollment applies per-class mapping and logs audit', (
    tester,
  ) async {
    final fake = FakeReEnrollmentData();

    fake.classes.addAll([
      Class(name: 'CE1', academicYear: '2024-2025'),
      Class(name: 'CE2', academicYear: '2024-2025'),
      Class(name: 'CE1', academicYear: '2025-2026'),
      Class(name: 'CE2', academicYear: '2025-2026'),
      Class(name: 'CE3', academicYear: '2025-2026'),
    ]);

    final b1 = Student(
      id: 'B1',
      firstName: 'E1',
      lastName: 'L1',
      dateOfBirth: '2015-01-01',
      address: 'Addr',
      gender: 'F',
      contactNumber: '000',
      email: 'e1@example.com',
      emergencyContact: '000',
      guardianName: 'G',
      guardianContact: '000',
      className: 'CE1',
      academicYear: '2024-2025',
      enrollmentDate: '2024-09-01',
    );
    final b2 = Student(
      id: 'B2',
      firstName: 'E2',
      lastName: 'L2',
      dateOfBirth: '2015-01-01',
      address: 'Addr',
      gender: 'M',
      contactNumber: '000',
      email: 'e2@example.com',
      emergencyContact: '000',
      guardianName: 'G',
      guardianContact: '000',
      className: 'CE2',
      academicYear: '2024-2025',
      enrollmentDate: '2024-09-01',
    );
    await fake.updateStudent('B1', b1);
    await fake.updateStudent('B2', b2);

    fake.preferredReportCardByKey['B1::CE1::2024-2025'] = {
      'studentId': 'B1',
      'className': 'CE1',
      'academicYear': '2024-2025',
      'decision': 'Admis en classe supérieure',
      'moyenne_annuelle': 12.0,
    };
    fake.preferredReportCardByKey['B2::CE2::2024-2025'] = {
      'studentId': 'B2',
      'className': 'CE2',
      'academicYear': '2024-2025',
      'decision': 'Redouble la classe',
      'moyenne_annuelle': 7.0,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<bool>(
                    context: context,
                    builder: (_) => ReEnrollmentBatchDialog(data: fake),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await pumpUntilFound(
      tester,
      find.byKey(ReEnrollmentBatchDialog.targetYearFieldKey),
    );

    await tester.enterText(
      find.byKey(ReEnrollmentBatchDialog.targetYearFieldKey),
      '2025-2026',
    );
    await tester.tap(find.byKey(ReEnrollmentBatchDialog.reloadButtonKey));
    await tester.pump(const Duration(milliseconds: 200));

    // CE1 admitted -> CE2
    await tester.ensureVisible(
      find.byKey(const Key('re_enroll_batch_target_CE1')),
    );
    await tester.tap(find.byKey(const Key('re_enroll_batch_target_CE1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CE2').last);
    await tester.pumpAndSettle();

    // CE2 admitted -> CE3
    await tester.ensureVisible(
      find.byKey(const Key('re_enroll_batch_target_CE2')),
    );
    await tester.tap(find.byKey(const Key('re_enroll_batch_target_CE2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CE3').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(ReEnrollmentBatchDialog.applyButtonKey),
    );
    await tester.tap(find.byKey(ReEnrollmentBatchDialog.applyButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuer sans archiver'));
    await tester.pumpAndSettle();

    await pumpUntilFound(
      tester,
      find.byKey(ReEnrollmentBatchDialog.confirmApplyButtonKey),
    );
    await tester.ensureVisible(
      find.byKey(ReEnrollmentBatchDialog.confirmApplyButtonKey),
    );
    await tester.tap(find.byKey(ReEnrollmentBatchDialog.confirmApplyButtonKey));
    await tester.pumpAndSettle();

    // Wait until the batch apply completes (audit log written).
    var batchLogged = false;
    String? batchError;
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final errorFinder = find.textContaining(
        'Erreur lors de la réinscription',
      );
      if (errorFinder.evaluate().isNotEmpty) {
        final textWidget = tester.widget<Text>(errorFinder.first);
        batchError = textWidget.data ?? textWidget.textSpan?.toPlainText();
        break;
      }
      batchLogged = fake.auditLogs.any(
        (l) => l['category'] == 're_enrollment' && l['action'] == 'batch_apply',
      );
      if (batchLogged) break;
    }
    if (batchError != null) {
      fail('Batch apply failed: $batchError');
    }
    expect(batchLogged, isTrue);

    // If the dialog didn't close (e.g. error path), close it to allow assertions
    // to run and keep the test stable.
    if (find.text('Réinscription — Toute l\'école').evaluate().isNotEmpty) {
      await tester.tap(find.text('Fermer').last);
      await tester.pumpAndSettle();
    }

    final b1Updated = fake.studentsById['B1']!;
    final b2Updated = fake.studentsById['B2']!;
    expect(b1Updated.academicYear, '2025-2026');
    expect(b1Updated.className, 'CE2');
    expect(b2Updated.academicYear, '2025-2026');
    expect(
      b2Updated.className,
      'CE2',
    ); // Redouble -> repeat mapping defaults to same class

    expect(batchLogged, isTrue);
  });
}
