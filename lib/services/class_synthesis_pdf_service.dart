import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/services/safe_mode_service.dart';

class ClassSynthesisPdfService {
  static void _checkSafeMode() {
    if (!SafeModeService.instance.isActionAllowed()) {
      throw Exception(SafeModeService.instance.getBlockedActionMessage());
    }
  }

  static Future<List<int>> generateClassSynthesisPdf({
    required SchoolInfo schoolInfo,
    required String className,
    required String academicYear,
    required String term,
    required List<Map<String, dynamic>> reportCards,
  }) async {
    _checkSafeMode();

    final pdf = pw.Document();

    // Sort by merit (descending average)
    final sortedCards = List<Map<String, dynamic>>.from(reportCards);
    sortedCards.sort((a, b) {
      final avgA = (a['moyenne_generale'] as num?)?.toDouble() ?? 0.0;
      final avgB = (b['moyenne_generale'] as num?)?.toDouble() ?? 0.0;
      return avgB.compareTo(avgA);
    });

    final fontRegular = pw.Font.courier();
    final fontBold = pw.Font.courierBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        orientation: pw.PageOrientation.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  schoolInfo.name.toUpperCase(),
                  style: pw.TextStyle(font: fontBold, fontSize: 14),
                ),
                pw.Text(
                  'ANNÉE SCOLAIRE $academicYear',
                  style: pw.TextStyle(font: fontBold, fontSize: 12),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'PROCÈS VERBAL DE DÉLIBÉRATION - $className - ${term.toUpperCase()}',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 16,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: [
                'Rang',
                'Nom & Prénoms',
                'Moyenne',
                'Mention',
                'Décision',
              ],
              data: sortedCards.map((rc) {
                return [
                  rc['rang']?.toString() ?? '-',
                  rc['studentName']?.toString() ?? '-',
                  ((rc['moyenne_generale'] as double?) ?? 0.0).toStringAsFixed(
                    2,
                  ),
                  rc['mention']?.toString() ?? '-',
                  rc['decision']?.toString() ?? '-',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(font: fontBold, fontSize: 10),
              cellStyle: pw.TextStyle(font: fontRegular, fontSize: 10),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
              },
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  "Le Chef d'Établissement",
                  style: pw.TextStyle(font: fontBold),
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
