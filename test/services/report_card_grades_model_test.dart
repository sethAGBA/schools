import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/services/pdf_service.dart';

void main() {
  group('Bulletin - modèle de notes (moyennes pondérées)', () {
    test('computeWeightedAverageOn20 uses all grades + coefficients', () {
      final grades = <Grade>[
        Grade(
          id: 1,
          studentId: 'S1',
          className: 'CE1',
          academicYear: '2024-2025',
          term: 'Trimestre 1',
          subjectId: 'math',
          subject: 'Mathématiques',
          type: 'Devoir',
          label: 'Devoir 1',
          value: 10,
          maxValue: 20,
          coefficient: 1,
        ),
        Grade(
          id: 2,
          studentId: 'S1',
          className: 'CE1',
          academicYear: '2024-2025',
          term: 'Trimestre 1',
          subjectId: 'math',
          subject: 'Mathématiques',
          type: 'Devoir',
          label: 'Devoir 2',
          value: 20,
          maxValue: 20,
          coefficient: 2,
        ),
        Grade(
          id: 3,
          studentId: 'S1',
          className: 'CE1',
          academicYear: '2024-2025',
          term: 'Trimestre 1',
          subjectId: 'math',
          subject: 'Mathématiques',
          type: 'Composition',
          label: 'Composition 1',
          value: 15,
          maxValue: 30,
          coefficient: 1,
        ),
      ];

      // (10/20*20)*1 = 10
      // (20/20*20)*2 = 40
      // (15/30*20)*1 = 10
      // total = 60 ; coeff = 4 ; moyenne = 15
      final avg = PdfService.computeWeightedAverageOn20(grades);
      expect(avg, closeTo(15.0, 0.0001));
    });

    test('computeWeightedAverageOn20 ignores invalid maxValue/coefficient', () {
      final grades = <Grade>[
        Grade(
          id: 1,
          studentId: 'S1',
          className: 'CE1',
          academicYear: '2024-2025',
          term: 'Trimestre 1',
          subjectId: 'math',
          subject: 'Mathématiques',
          type: 'Devoir',
          label: 'Devoir 1',
          value: 10,
          maxValue: 20,
          coefficient: 1,
        ),
        Grade(
          id: 2,
          studentId: 'S1',
          className: 'CE1',
          academicYear: '2024-2025',
          term: 'Trimestre 1',
          subjectId: 'math',
          subject: 'Mathématiques',
          type: 'Devoir',
          label: 'Devoir invalide',
          value: 20,
          maxValue: 0,
          coefficient: 3,
        ),
        Grade(
          id: 3,
          studentId: 'S1',
          className: 'CE1',
          academicYear: '2024-2025',
          term: 'Trimestre 1',
          subjectId: 'math',
          subject: 'Mathématiques',
          type: 'Composition',
          label: 'Composition invalide',
          value: 20,
          maxValue: 20,
          coefficient: 0,
        ),
      ];

      // Seule la première note compte => (10/20*20) = 10
      final avg = PdfService.computeWeightedAverageOn20(grades);
      expect(avg, closeTo(10.0, 0.0001));
    });
  });
}
