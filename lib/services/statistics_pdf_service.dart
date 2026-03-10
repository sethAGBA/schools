import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:flutter/services.dart' show rootBundle, Uint8List;

class StatisticsPdfService {
  final DatabaseService _db = DatabaseService();
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'fr_FR');

  Future<Uint8List> exportAcademicReport({
    required Map<String, dynamic> stats,
    required String year,
    String? className,
    String? term,
  }) async {
    final pdf = pw.Document();
    final schoolInfo = await _db.getSchoolInfo();
    final fonts = await _loadFonts();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) =>
            _buildHeader(schoolInfo, year, 'RAPPORT ACADÉMIQUE', fonts),
        footer: (context) => _buildFooter(context, fonts),
        build: (context) => [
          _buildAcademicContent(stats, className, term, fonts),
        ],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> exportDisciplineReport({
    required Map<String, dynamic> stats,
    required String year,
  }) async {
    final pdf = pw.Document();
    final schoolInfo = await _db.getSchoolInfo();
    final fonts = await _loadFonts();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) =>
            _buildHeader(schoolInfo, year, 'RAPPORT DE DISCIPLINE', fonts),
        footer: (context) => _buildFooter(context, fonts),
        build: (context) => [_buildDisciplineContent(stats, fonts)],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> exportDemographicReport({
    required Map<String, dynamic> stats,
    required String year,
  }) async {
    final pdf = pw.Document();
    final schoolInfo = await _db.getSchoolInfo();
    final fonts = await _loadFonts();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) =>
            _buildHeader(schoolInfo, year, 'RAPPORT DÉMOGRAPHIQUE', fonts),
        footer: (context) => _buildFooter(context, fonts),
        build: (context) => [_buildDemographicContent(stats, fonts)],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> exportFinanceReport({
    required Map<String, dynamic> stats,
    required String year,
  }) async {
    final pdf = pw.Document();
    final schoolInfo = await _db.getSchoolInfo();
    final fonts = await _loadFonts();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) =>
            _buildHeader(schoolInfo, year, 'RAPPORT FINANCIER', fonts),
        footer: (context) => _buildFooter(context, fonts),
        build: (context) => [_buildFinanceContent(stats, fonts)],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader(
    SchoolInfo? schoolInfo,
    String year,
    String title,
    _PdfFonts fonts,
  ) {
    return pw.Column(
      children: [
        if (schoolInfo != null) ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (schoolInfo.ministry != null)
                    pw.Text(
                      schoolInfo.ministry!.toUpperCase(),
                      style: pw.TextStyle(font: fonts.bold, fontSize: 8),
                    ),
                  if (schoolInfo.inspection != null)
                    pw.Text(
                      schoolInfo.inspection!,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                    ),
                  if (schoolInfo.educationDirection != null)
                    pw.Text(
                      schoolInfo.educationDirection!,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (schoolInfo.republic != null)
                    pw.Text(
                      schoolInfo.republic!.toUpperCase(),
                      style: pw.TextStyle(font: fonts.bold, fontSize: 8),
                    ),
                  if (schoolInfo.republicMotto != null)
                    pw.Text(
                      schoolInfo.republicMotto!,
                      style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 7,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              if (schoolInfo.logoPath != null &&
                  File(schoolInfo.logoPath!).existsSync())
                pw.Image(
                  pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                  width: 50,
                  height: 50,
                ),
              pw.SizedBox(width: 15),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      schoolInfo.name,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 16),
                    ),
                    pw.Text(
                      schoolInfo.address,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                    ),
                    if (schoolInfo.telephone != null)
                      pw.Text(
                        'Tél: ${schoolInfo.telephone}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                      ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Année Académique: $year',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                  ),
                  pw.Text(
                    'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 1, color: PdfColors.grey300),
          pw.SizedBox(height: 10),
        ],
        pw.Center(
          child: pw.Text(
            title,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 18,
              color: PdfColors.blue900,
            ),
          ),
        ),
        pw.SizedBox(height: 20),
      ],
    );
  }

  pw.Widget _buildFooter(pw.Context context, _PdfFonts fonts) {
    return pw.Column(
      children: [
        pw.Divider(thickness: 0.5, color: PdfColors.grey300),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            // pw.Text(
            //   // 'Rapport Statistique - AtSchool'
            //   'Rapport Statistique - School Manager',
            //   style: pw.TextStyle(
            //     font: fonts.regular,
            //     fontSize: 8,
            //     color: PdfColors.grey600,
            //   ),
            // ),
            pw.Text(
              'Page ${context.pageNumber}/${context.pagesCount}',
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildAcademicContent(
    Map<String, dynamic> stats,
    String? className,
    String? term,
    _PdfFonts fonts,
  ) {
    final globalAvg = (stats['globalAverage'] as num?)?.toDouble() ?? 0.0;
    final successRate = (stats['globalSuccessRate'] as num?)?.toDouble() ?? 0.0;
    final totalSuccess = stats['totalSuccess'] ?? 0;
    final totalFailure = stats['totalFailure'] ?? 0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (className != null || term != null)
          pw.Text(
            'Filtres: ${className ?? "Toutes classes"} | ${term ?? "Toute l'année"}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 10),
          ),
        pw.SizedBox(height: 15),

        // Key Metrics Table
        pw.TableHelper.fromTextArray(
          headers: ['Indicateur', 'Valeur'],
          data: [
            ['Moyenne Générale', globalAvg.toStringAsFixed(2)],
            ['Taux de Réussite', '${successRate.toStringAsFixed(1)}%'],
            ['Nombre d\'Admis', totalSuccess.toString()],
            ['Nombre d\'Échecs', totalFailure.toString()],
          ],
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
          cellStyle: pw.TextStyle(font: fonts.regular),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1),
          },
        ),
        pw.SizedBox(height: 25),

        _buildSubTitle('Top Élèves', fonts),
        _buildStudentTable(stats['topStudents'] as List?, fonts),
        pw.SizedBox(height: 20),

        _buildSubTitle('Élèves en Difficulté', fonts),
        _buildStudentTable(stats['bottomStudents'] as List?, fonts),
        pw.SizedBox(height: 25),

        _buildSubTitle('Répartition par Classe', fonts),
        _buildClassStatsTable(stats['classStats'] as Map?, fonts),
      ],
    );
  }

  pw.Widget _buildDisciplineContent(
    Map<String, dynamic> stats,
    _PdfFonts fonts,
  ) {
    final topAbsent = stats['topAbsentStudents'] as List? ?? [];
    final sanctionsClass = stats['sanctionsByClass'] as Map? ?? {};
    final absByMonth = stats['absencesByMonth'] as Map? ?? {};

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSubTitle('Absences par Mois', fonts),
        pw.TableHelper.fromTextArray(
          headers: ['Mois', 'Nombre d\'absences'],
          data: absByMonth.entries
              .map((e) => [e.key, e.value.toString()])
              .toList(),
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
          cellStyle: pw.TextStyle(font: fonts.regular),
        ),
        pw.SizedBox(height: 25),

        _buildSubTitle('Top 10 des Élèves Absents', fonts),
        pw.TableHelper.fromTextArray(
          headers: ['Nom', 'Classe', 'Absences'],
          data: topAbsent
              .map((s) => [s['name'], s['className'], s['count'].toString()])
              .toList(),
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.orange700),
          cellStyle: pw.TextStyle(font: fonts.regular),
        ),
        pw.SizedBox(height: 25),

        _buildSubTitle('Sanctions par Classe', fonts),
        pw.TableHelper.fromTextArray(
          headers: ['Classe', 'Nombre de Sanctions'],
          data: sanctionsClass.entries
              .map((e) => [e.key, e.value.toString()])
              .toList(),
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.red900),
          cellStyle: pw.TextStyle(font: fonts.regular),
        ),
      ],
    );
  }

  pw.Widget _buildDemographicContent(
    Map<String, dynamic> stats,
    _PdfFonts fonts,
  ) {
    final gender = stats['gender'] as Map? ?? {};
    final status = stats['status'] as Map? ?? {};
    final age = stats['age'] as Map? ?? {};

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSubTitle('Répartition par Genre', fonts),
        pw.TableHelper.fromTextArray(
          headers: ['Genre', 'Effectif'],
          data: gender.entries.map((e) => [e.key, e.value.toString()]).toList(),
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
          cellStyle: pw.TextStyle(font: fonts.regular),
        ),
        pw.SizedBox(height: 25),

        _buildSubTitle('Répartition par Statut', fonts),
        pw.TableHelper.fromTextArray(
          headers: ['Statut', 'Effectif'],
          data: status.entries.map((e) => [e.key, e.value.toString()]).toList(),
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
          cellStyle: pw.TextStyle(font: fonts.regular),
        ),
        pw.SizedBox(height: 25),

        _buildSubTitle('Pyramide des Âges', fonts),
        pw.TableHelper.fromTextArray(
          headers: ['Âge', 'Effectif'],
          data: age.entries
              .map((e) => ['${e.key} ans', e.value.toString()])
              .toList(),
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.blueGrey700,
          ),
          cellStyle: pw.TextStyle(font: fonts.regular),
        ),
      ],
    );
  }

  pw.Widget _buildFinanceContent(Map<String, dynamic> stats, _PdfFonts fonts) {
    final totalIncome = stats['totalIncome'] as double? ?? 0.0;
    final totalExpense = stats['totalExpense'] as double? ?? 0.0;
    final balance = stats['balance'] as double? ?? 0.0;
    final incomeByMonth = stats['incomeByMonth'] as Map? ?? {};
    final expenseByMonth = stats['expenseByMonth'] as Map? ?? {};

    final allMonths = {...incomeByMonth.keys, ...expenseByMonth.keys}.toList()
      ..sort();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Summary Cards Table
        pw.TableHelper.fromTextArray(
          headers: ['Libellé', 'Montant'],
          data: [
            [
              'Total Encaissements',
              '${_currencyFormat.format(totalIncome)} FCFA',
            ],
            ['Total Dépenses', '${_currencyFormat.format(totalExpense)} FCFA'],
            ['Solde Net', '${_currencyFormat.format(balance)} FCFA'],
          ],
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
          cellStyle: pw.TextStyle(font: fonts.regular),
          cellAlignment: pw.Alignment.centerLeft,
          headerAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 25),

        _buildSubTitle('Évolution Mensuelle', fonts),
        pw.TableHelper.fromTextArray(
          headers: ['Mois', 'Revenus', 'Dépenses'],
          data: allMonths.map((m) {
            final inc = (incomeByMonth[m] as num? ?? 0.0).toDouble();
            final exp = (expenseByMonth[m] as num? ?? 0.0).toDouble();
            return [
              m,
              '${_currencyFormat.format(inc)} FCFA',
              '${_currencyFormat.format(exp)} FCFA',
            ];
          }).toList(),
          headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
          cellStyle: pw.TextStyle(font: fonts.regular),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
          },
        ),
      ],
    );
  }

  pw.Widget _buildSubTitle(String title, _PdfFonts fonts) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 13,
          color: PdfColors.blueGrey800,
        ),
      ),
    );
  }

  pw.Widget _buildStudentTable(List? students, _PdfFonts fonts) {
    if (students == null || students.isEmpty) {
      return pw.Text(
        'Aucune donnée',
        style: pw.TextStyle(
          font: fonts.regular,
          fontStyle: pw.FontStyle.italic,
        ),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: ['Nom', 'Classe', 'Moyenne'],
      data: students
          .map(
            (s) => [
              s['name'],
              s['className'],
              (s['average'] as num).toStringAsFixed(2),
            ],
          )
          .toList(),
      headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey500),
      cellStyle: pw.TextStyle(font: fonts.regular),
    );
  }

  pw.Widget _buildClassStatsTable(Map? classStats, _PdfFonts fonts) {
    if (classStats == null || classStats.isEmpty) {
      return pw.Text(
        'Aucune donnée',
        style: pw.TextStyle(
          font: fonts.regular,
          fontStyle: pw.FontStyle.italic,
        ),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: ['Classe', 'Effectif', 'Admis', 'Taux (%)'],
      data: classStats.entries.map((e) {
        final data = (e.value as Map).cast<String, int>();
        final success = data['success'] ?? 0;
        final total = data['total'] ?? 1;
        final rate = (success / total) * 100;
        return [
          e.key,
          total.toString(),
          success.toString(),
          '${rate.toStringAsFixed(1)}%',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(font: fonts.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellStyle: pw.TextStyle(font: fonts.regular),
    );
  }

  Future<_PdfFonts> _loadFonts() async {
    final regular = await rootBundle.load(
      'assets/fonts/nunito/Nunito-Regular.ttf',
    );
    final bold = await rootBundle.load('assets/fonts/nunito/Nunito-Bold.ttf');
    return _PdfFonts(regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
  }
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  _PdfFonts({required this.regular, required this.bold});
}
