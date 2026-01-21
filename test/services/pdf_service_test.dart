import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/services/pdf_service.dart';

void main() {
  group('PdfService.dashIfBlank', () {
    test('returns placeholder for null/blank', () {
      expect(PdfService.dashIfBlank(null), '-');
      expect(PdfService.dashIfBlank(''), '-');
      expect(PdfService.dashIfBlank('   '), '-');
    });

    test('trims and keeps non-blank', () {
      expect(PdfService.dashIfBlank('  M. Dupont  '), 'M. Dupont');
    });

    test('supports custom placeholder', () {
      expect(PdfService.dashIfBlank('', placeholder: 'N/A'), 'N/A');
    });
  });
}

