import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/utils/student_sort.dart';

Student _student({
  required String id,
  required String firstName,
  required String lastName,
}) {
  return Student(
    id: id,
    firstName: firstName,
    lastName: lastName,
    dateOfBirth: '',
    placeOfBirth: '',
    address: '',
    gender: 'M',
    contactNumber: '',
    email: '',
    emergencyContact: '',
    guardianName: '',
    guardianContact: '',
    className: '',
    academicYear: '',
    enrollmentDate: '',
  );
}

void main() {
  test('compareStudentsByName sorts by lastName then firstName', () {
    final students = [
      _student(id: '2', firstName: 'Zoé', lastName: 'Alpha'),
      _student(id: '3', firstName: 'Adam', lastName: 'Alpha'),
      _student(id: '1', firstName: 'Bob', lastName: 'Zola'),
    ]..sort(compareStudentsByName);

    expect(students.map((s) => '${s.lastName} ${s.firstName}').toList(), [
      'Alpha Adam',
      'Alpha Zoé',
      'Zola Bob',
    ]);
  });

  test('normalizeForSort folds common accents', () {
    expect(normalizeForSort('Élève'), 'eleve');
    expect(normalizeForSort('  À  Ç  '), 'a c');
    expect(normalizeForSort('Œuvre'), 'oeuvre');
  });
}

