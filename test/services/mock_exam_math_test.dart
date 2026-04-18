import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/services/mock_exam_pdf_service.dart';

void main() {
  group('MockExamPdfService Weighted Average Tests', () {
    test('Calculate weighted average with different coefficients', () {
      final grades = [
        Grade(
          studentId: '1',
          className: 'Test',
          academicYear: '2025',
          subjectId: 'A',
          subject: 'Subject A',
          term: 'Exam 1',
          value: 15.0,
          coefficient: 4.0,
        ),
        Grade(
          studentId: '1',
          className: 'Test',
          academicYear: '2025',
          subjectId: 'B',
          subject: 'Subject B',
          term: 'Exam 1',
          value: 5.0,
          coefficient: 1.0,
        ),
      ];

      final result = MockExamPdfService.calculateWeightedAverage(grades, {
        'A': 4.0,
        'B': 1.0,
      });
      
      // (15 * 4 + 5 * 1) / (4 + 1) = (60 + 5) / 5 = 65 / 5 = 13.0
      expect(result, 13.0);
    });

    test('Calculate average with coefficient 0 (should ignore)', () {
      final grades = [
        Grade(
          studentId: '1',
          className: 'Test',
          academicYear: '2025',
          subjectId: 'A',
          subject: 'Subject A',
          term: 'Exam 1',
          value: 20.0,
          coefficient: 1.0, // Should be overridden by map
        ),
        Grade(
          studentId: '1',
          className: 'Test',
          academicYear: '2025',
          subjectId: 'B',
          subject: 'Subject B',
          term: 'Exam 1',
          value: 0.0,
          coefficient: 1.0, // Should be overridden by map
        ),
      ];

      final result = MockExamPdfService.calculateWeightedAverage(grades, {
        'A': 2.0,
        'B': 0.0,
      });
      
      // (20 * 2 + 0 * 0) / (2 + 0) = 40 / 2 = 20.0
      expect(result, 20.0);
    });

    test('Return 0.0 for empty list', () {
      expect(MockExamPdfService.calculateWeightedAverage([], {}), 0.0);
    });
  });
}
