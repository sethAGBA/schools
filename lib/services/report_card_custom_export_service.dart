import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:school_manager/models/category.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';

class ReportCardCustomExportService {
  static Future<List<int>> generateReportCardCustomPdf({
    required Student student,
    required SchoolInfo schoolInfo,
    required List<Grade> grades,
    required List<String> subjects,
    required Map<String, String> professeurs,
    required Map<String, String> appreciations,
    required Map<String, String> moyennesClasse,
    required List<double?> moyennesParPeriode,
    required List<String> allTerms,
    required double moyenneGenerale,
    required int rang,
    required int nbEleves,
    required String periodLabel,
    required String academicYear,
    required String term,
    required String className,
    required String selectedTerm,
    bool isLandscape = false,
    String appreciationGenerale = '',
    String mention = '',
    String decision = '',
    String decisionAutomatique = '',
    String conduite = '',
    String recommandations = '',
    String forces = '',
    String pointsADevelopper = '',
    String sanctions = '',
    int attendanceJustifiee = 0,
    int attendanceInjustifiee = 0,
    int retards = 0,
    double presencePercent = 0.0,
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    double? moyenneAnnuelle,
    double? moyenneAnnuelleClasse,
    int? rangAnnuel,
    int? nbElevesAnnuel,
    String faitA = '',
    String leDate = '',
    String footerNote = '',
    String titulaireName = '',
    String directorName = '',
    String titulaireCivility = '',
    String directorCivility = '',
    bool duplicata = false,
    bool useLongFormat = true,
  }) async {
    final pdf = pw.Document();
    final pageFormat = useLongFormat
        ? (isLandscape
              ? PdfPageFormat(760, 595) // Format long : dimensions agrandies
              : PdfPageFormat(595.28, 820))
        : (isLandscape
              ? PdfPageFormat
                    .a4
                    .landscape // Format court : A4 standard
              : PdfPageFormat.a4);
    final font = await pw.Font.times();
    final fontBold = await pw.Font.timesBold();
    final DatabaseService db = DatabaseService();
    final subjectWeights = await db.getClassSubjectCoefficients(
      className,
      academicYear,
    );
    final List<Category> categories = await db.getCategories();
    final List<Course> classCourses = await db.getCoursesForClass(
      className,
      academicYear,
    );
    final subjectRanks = await _computeSubjectRanks(
      db,
      studentId: student.id,
      className: className,
      academicYear: academicYear,
      term: term,
      subjects: subjects,
    );
    final moyenneSem = moyenneGenerale;
    final resolvedAverage = (moyenneAnnuelle != null && moyenneAnnuelle > 0.0)
        ? moyenneAnnuelle
        : moyenneGenerale;
    final appreciation = appreciationGenerale.trim().isNotEmpty
        ? appreciationGenerale.trim()
        : _autoAppreciationGeneraleText(resolvedAverage);
    final resolvedConduite = conduite.trim().isNotEmpty
        ? conduite.trim()
        : (recommandations.trim().isNotEmpty
              ? recommandations.trim()
              : _autoConduiteText(
                  attendanceInjustifiee: attendanceInjustifiee,
                  retards: retards,
                  sanctions: sanctions,
                ));
    final resolvedHonneur = forces.trim().isNotEmpty
        ? forces.trim()
        : _autoHonneurText(resolvedAverage);
    final resolvedEncouragement = pointsADevelopper.trim().isNotEmpty
        ? pointsADevelopper.trim()
        : _autoEncouragementText(resolvedAverage);
    final resolvedMention = mention.trim().isNotEmpty
        ? mention.trim()
        : _getAppreciation(resolvedAverage);
    final showAnnual = _shouldShowAnnual(periodLabel, term);
    final resolvedFaitA = faitA.trim().isNotEmpty
        ? faitA.trim()
        : '_________________';
    final resolvedLeDate = leDate.trim().isNotEmpty
        ? leDate.trim()
        : '__________________';

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Stack(
          children: [
            if (schoolInfo.logoPath != null &&
                schoolInfo.logoPath!.isNotEmpty &&
                File(schoolInfo.logoPath!).existsSync())
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.08,
                    child: pw.Image(
                      pw.MemoryImage(
                        File(schoolInfo.logoPath!).readAsBytesSync(),
                      ),
                      width: pageFormat.width * 0.5,
                      height: pageFormat.height * 0.5,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildHeader(schoolInfo, fontBold, font),
                  if (duplicata)
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(top: 2),
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.red, width: 1),
                          color: PdfColors.red50,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          'DUPLICATA',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 7,
                            color: PdfColors.red800,
                          ),
                        ),
                      ),
                    ),
                  pw.SizedBox(height: 0),
                  pw.Center(
                    child: pw.Text(
                      'BULLETIN D\'EVALUATION',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 11,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _buildStudentInfo(
                    student,
                    academicYear,
                    term,
                    className,
                    nbEleves,
                    fontBold,
                    font,
                  ),
                  pw.SizedBox(height: 10),
                  _buildGradesTable(
                    grades,
                    subjects,
                    subjectWeights,
                    subjectRanks,
                    categories,
                    classCourses,
                    professeurs,
                    appreciations,
                    moyennesClasse,
                    fontBold,
                    font,
                  ),
                  pw.SizedBox(height: 12),
                  _buildAveragesSection(
                    appreciation,
                    resolvedMention,
                    moyennesParPeriode,
                    allTerms,
                    showAnnual ? moyenneAnnuelle : null,
                    moyenneGeneraleDeLaClasse,
                    moyenneLaPlusForte,
                    moyenneLaPlusFaible,
                    rang,
                    nbEleves,
                    moyenneGenerale,
                    selectedTerm,
                    attendanceJustifiee,
                    attendanceInjustifiee,
                    retards,
                    presencePercent,
                    periodLabel,
                    showAnnual ? moyenneAnnuelleClasse : null,
                    showAnnual ? rangAnnuel : null,
                    showAnnual ? nbElevesAnnuel : null,
                    fontBold,
                    font,
                  ),
                  pw.SizedBox(height: 10),
                  _buildCouncilSection(
                    appreciation,
                    resolvedConduite,
                    decision,
                    decisionAutomatique,
                    resolvedHonneur,
                    resolvedEncouragement,
                    fontBold,
                    font,
                  ),
                  pw.SizedBox(height: 12),
                  _buildFooter(
                    resolvedFaitA,
                    resolvedLeDate,
                    titulaireName,
                    directorName,
                    titulaireCivility,
                    directorCivility,
                    fontBold,
                    font,
                  ),
                  pw.Spacer(),
                  _buildFooterNote(footerNote, font),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(
    SchoolInfo schoolInfo,
    pw.Font fontBold,
    pw.Font font,
  ) {
    final ministry = schoolInfo.ministry?.trim().isNotEmpty == true
        ? schoolInfo.ministry!.trim()
        : 'MINISTERE DE L\'EDUCATION NATIONALE';
    final educationDirection =
        schoolInfo.educationDirection?.trim().isNotEmpty == true
        ? schoolInfo.educationDirection!.trim()
        : 'DRE-MARITIME';
    final inspection = schoolInfo.inspection?.trim().isNotEmpty == true
        ? schoolInfo.inspection!.trim()
        : 'IESG-VOGAN';
    final republic = schoolInfo.republic?.trim().isNotEmpty == true
        ? schoolInfo.republic!.trim()
        : 'REPUBLIQUE TOGOLAISE';
    final republicMotto = schoolInfo.republicMotto?.trim().isNotEmpty == true
        ? schoolInfo.republicMotto!.trim()
        : 'Travail-Liberte-Patrie';
    final address = schoolInfo.address.trim();
    final bpValue = schoolInfo.bp?.trim().isNotEmpty == true
        ? schoolInfo.bp!.trim()
        : address;
    final phone = schoolInfo.telephone?.trim() ?? '';
    final motto = schoolInfo.motto?.trim() ?? '';
    final hasLogo =
        schoolInfo.logoPath != null &&
        schoolInfo.logoPath!.isNotEmpty &&
        File(schoolInfo.logoPath!).existsSync();
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  ministry,
                  style: pw.TextStyle(font: fontBold, fontSize: 6.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '-----------------------------',
                  style: pw.TextStyle(font: font, fontSize: 5.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  educationDirection,
                  style: pw.TextStyle(font: fontBold, fontSize: 6.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '-----------------------------',
                  style: pw.TextStyle(font: font, fontSize: 5.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  inspection,
                  style: pw.TextStyle(font: fontBold, fontSize: 6.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '-----------------------------',
                  style: pw.TextStyle(font: font, fontSize: 5.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 2),
            ],
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (hasLogo)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Image(
                    pw.MemoryImage(
                      File(schoolInfo.logoPath!).readAsBytesSync(),
                    ),
                    height: 28,
                    fit: pw.BoxFit.contain,
                  ),
                ),
              pw.Text(
                schoolInfo.name.toUpperCase(),
                style: pw.TextStyle(font: fontBold, fontSize: 7.5),
                textAlign: pw.TextAlign.center,
              ),
              if (bpValue.isNotEmpty)
                pw.Text(
                  'BP : $bpValue',
                  style: pw.TextStyle(font: font, fontSize: 6),
                  textAlign: pw.TextAlign.center,
                ),
              if (phone.isNotEmpty)
                pw.Text(
                  'Tel: $phone',
                  style: pw.TextStyle(font: font, fontSize: 6),
                  textAlign: pw.TextAlign.center,
                ),
              if (motto.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 1),
                  child: pw.Text(
                    motto,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 6,
                      fontStyle: pw.FontStyle.italic,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                republic,
                style: pw.TextStyle(font: fontBold, fontSize: 6.5),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                republicMotto,
                style: pw.TextStyle(font: font, fontSize: 6),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildStudentInfo(
    Student student,
    String academicYear,
    String term,
    String className,
    int nbEleves,
    pw.Font fontBold,
    pw.Font font,
  ) {
    final birthInfo = _buildBirthInfo(student);
    final genderLabel = _formatGender(student.gender);
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all()),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                flex: 2,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'NOM ET PRENOMS :',
                        style: pw.TextStyle(font: fontBold, fontSize: 9),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${student.lastName} ${student.firstName}'.trim(),
                        style: pw.TextStyle(font: font, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Container(width: 1, height: 30, color: PdfColors.black),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          children: [
                            pw.Text(
                              'Annee scolaire',
                              style: pw.TextStyle(font: fontBold, fontSize: 7),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.Text(
                              academicYear,
                              style: pw.TextStyle(font: font, fontSize: 8),
                              textAlign: pw.TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      pw.Container(
                        width: 1,
                        height: 28,
                        color: PdfColors.black,
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          children: [
                            pw.Text(
                              'Période',
                              style: pw.TextStyle(font: fontBold, fontSize: 7),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.Text(
                              term,
                              style: pw.TextStyle(font: font, fontSize: 8),
                              textAlign: pw.TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Container(width: 1, height: 30, color: PdfColors.black),
              pw.Container(
                width: 70,
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Classe',
                      style: pw.TextStyle(font: fontBold, fontSize: 7),
                    ),
                    pw.Text(
                      className,
                      style: pw.TextStyle(font: font, fontSize: 8),
                    ),
                  ],
                ),
              ),
              pw.Container(width: 1, height: 30, color: PdfColors.black),
              pw.Container(
                width: 50,
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Effectif',
                      style: pw.TextStyle(font: fontBold, fontSize: 7),
                    ),
                    pw.Text(
                      nbEleves > 0 ? '$nbEleves' : '-',
                      style: pw.TextStyle(font: font, fontSize: 8),
                    ),
                  ],
                ),
              ),
              pw.Container(width: 1, height: 30, color: PdfColors.black),
              pw.Container(
                width: 40,
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Sexe',
                      style: pw.TextStyle(font: fontBold, fontSize: 7),
                    ),
                    pw.Text(
                      genderLabel,
                      style: pw.TextStyle(font: font, fontSize: 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.Container(height: 1, color: PdfColors.black),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Matricule: ${dashIfBlank(student.matricule)}',
                    style: pw.TextStyle(font: fontBold, fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Date et lieu de naissance: $birthInfo',
                    style: pw.TextStyle(font: fontBold, fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Statut: ${dashIfBlank(student.status)}',
                    style: pw.TextStyle(font: fontBold, fontSize: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildGradesTable(
    List<Grade> grades,
    List<String> subjects,
    Map<String, double> subjectWeights,
    Map<String, String> subjectRanks,
    List<Category> categories,
    List<Course> classCourses,
    Map<String, String> professeurs,
    Map<String, String> appreciations,
    Map<String, String> moyennesClasse,
    pw.Font fontBold,
    pw.Font font,
  ) {
    double sumCoefficients = 0.0;
    double sumPoints = 0.0;
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(4.0),
      1: const pw.FlexColumnWidth(1.1),
      2: const pw.FlexColumnWidth(1.1),
      3: const pw.FlexColumnWidth(1.1),
      4: const pw.FlexColumnWidth(1.1),
      5: const pw.FlexColumnWidth(0.8),
      6: const pw.FlexColumnWidth(1.1),
      7: const pw.FlexColumnWidth(0.8),
      8: const pw.FlexColumnWidth(4.0),
      9: const pw.FlexColumnWidth(2.5),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _cellHeader('Matieres', fontBold),
        _cellHeader('Moy. Clas.\nSur 20', fontBold),
        _cellHeader('Dev.\nSur 20', fontBold),
        _cellHeader('Compo.\nSur 20', fontBold),
        _cellHeader('Moy.\nSem.\nSur 20', fontBold),
        _cellHeader('Coef.', fontBold),
        _cellHeader('Notes\nDefinitives', fontBold),
        _cellHeader('Rang', fontBold),
        _cellHeader('Appreciations', fontBold),
        _cellHeader('Professeurs', fontBold),
      ],
    );
    List<pw.TableRow> buildSubjectRows(List<String> subjectList) {
      final rows = <pw.TableRow>[];
      for (final subject in subjectList) {
        final subjectGrades = grades
            .where((g) => g.subject == subject)
            .toList();
        final devoirs = subjectGrades.where((g) => g.type == 'Devoir').toList();
        final compositions = subjectGrades
            .where((g) => g.type == 'Composition')
            .toList();
        final devoirAvg = devoirs.isNotEmpty
            ? _computeWeightedAverageOn20(devoirs)
            : null;
        final compoAvg = compositions.isNotEmpty
            ? _computeWeightedAverageOn20(compositions)
            : null;
        final moyenneMatiere = subjectGrades.isNotEmpty
            ? _computeWeightedAverageOn20(subjectGrades)
            : 0.0;
        final totalCoeff = subjectGrades
            .where((g) => g.maxValue > 0 && g.coefficient > 0)
            .fold<double>(0.0, (s, g) => s + g.coefficient);
        final subjectWeight = subjectWeights[subject] ?? totalCoeff;
        final notesDefinitives = subjectGrades.isNotEmpty
            ? moyenneMatiere * subjectWeight
            : 0.0;
        if (subjectGrades.isNotEmpty && subjectWeight > 0) {
          sumCoefficients += subjectWeight;
          sumPoints += notesDefinitives;
        }
        rows.add(
          pw.TableRow(
            children: [
              _cell(subject, font),
              _cell(dashIfBlank(moyennesClasse[subject]), font),
              _cell(_formatOptionalNumber(devoirAvg), font),
              _cell(_formatOptionalNumber(compoAvg), font),
              _cell(_formatOptionalNumber(moyenneMatiere), font),
              _cell(
                subjectWeight > 0 ? _formatCoefficient(subjectWeight) : '-',
                font,
              ),
              _cell(
                subjectGrades.isNotEmpty
                    ? _formatNumber(notesDefinitives)
                    : '-',
                font,
              ),
              _cell(subjectRanks[subject] ?? '-', font),
              _cell(dashIfBlank(appreciations[subject]), font, fontSize: 7),
              _cell(teacherSurname(professeurs[subject]), font, fontSize: 7),
            ],
          ),
        );
      }
      return rows;
    }

    final Map<String, String?> subjectCat = {
      for (final c in classCourses) c.name: c.categoryId,
    };
    final Map<String?, List<String>> grouped = {};
    for (final subject in subjects) {
      grouped.putIfAbsent(subjectCat[subject], () => []).add(subject);
    }
    final hasCategories = grouped.keys.any((k) => k != null);
    final Map<String, Category> categoryById = {
      for (final c in categories) c.id: c,
    };
    final orderedCategoryIds =
        grouped.keys.where((k) => k != null).cast<String>().toList()..sort(
          (a, b) => (categoryById[a]?.order ?? 0).compareTo(
            categoryById[b]?.order ?? 0,
          ),
        );
    final orderedKeys = <String?>[
      ...orderedCategoryIds,
      if (grouped.containsKey(null)) null,
    ];
    if (hasCategories) {
      final widgets = <pw.Widget>[
        pw.Table(
          border: pw.TableBorder.all(),
          columnWidths: columnWidths,
          children: [headerRow],
        ),
      ];
      for (final catId in orderedKeys) {
        final subjectList = grouped[catId] ?? [];
        if (catId != null) {
          final categoryName = categoryById[catId]?.name ?? 'Categorie';
          double catStudentTotal = 0.0;
          double catStudentCoeff = 0.0;
          double catClassTotal = 0.0;
          double catClassCoeff = 0.0;
          for (final subject in subjectList) {
            final subjectGrades = grades
                .where((g) => g.subject == subject)
                .toList();
            final totalCoeff = subjectGrades
                .where((g) => g.maxValue > 0 && g.coefficient > 0)
                .fold<double>(0.0, (s, g) => s + g.coefficient);
            final subjectWeight = subjectWeights[subject] ?? totalCoeff;
            if (subjectGrades.isNotEmpty && subjectWeight > 0) {
              final avg = _computeWeightedAverageOn20(subjectGrades);
              catStudentTotal += avg * subjectWeight;
              catStudentCoeff += subjectWeight;
            }
            final classAvg = _parseMaybeNumber(moyennesClasse[subject]);
            if (classAvg != null && subjectWeight > 0) {
              catClassTotal += classAvg * subjectWeight;
              catClassCoeff += subjectWeight;
            }
          }
          final catStudentAvg = catStudentCoeff > 0
              ? catStudentTotal / catStudentCoeff
              : null;
          final catClassAvg = catClassCoeff > 0
              ? catClassTotal / catClassCoeff
              : null;
          widgets.add(
            _buildCategorySummaryRow(
              'Matières $categoryName',
              catStudentAvg,
              catClassAvg,
              subjectList.length,
              fontBold,
              font,
            ),
          );
        }
        widgets.add(
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: columnWidths,
            children: buildSubjectRows(subjectList),
          ),
        );
      }
      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(),
          columnWidths: columnWidths,
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _cellHeader('TOTAL', fontBold),
                _cell('', font),
                _cell('', font),
                _cell('', font),
                _cell('', font),
                _cell(
                  sumCoefficients > 0
                      ? _formatCoefficient(sumCoefficients)
                      : '-',
                  fontBold,
                ),
                _cell(
                  sumCoefficients > 0 ? _formatNumber(sumPoints) : '-',
                  fontBold,
                ),
                _cell('', font),
                _cell('', font),
                _cell('', font),
              ],
            ),
          ],
        ),
      );
      return pw.Column(children: widgets);
    }
    final rows = <pw.TableRow>[headerRow, ...buildSubjectRows(subjects)];
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cellHeader('TOTAL', fontBold),
          _cell('', font),
          _cell('', font),
          _cell('', font),
          _cell('', font),
          _cell(
            sumCoefficients > 0 ? _formatCoefficient(sumCoefficients) : '-',
            fontBold,
          ),
          _cell(sumCoefficients > 0 ? _formatNumber(sumPoints) : '-', fontBold),
          _cell('', font),
          _cell('', font),
          _cell('', font),
        ],
      ),
    );
    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: columnWidths,
      children: rows,
    );
  }

  static Future<Map<String, String>> _computeSubjectRanks(
    DatabaseService db, {
    required String studentId,
    required String className,
    required String academicYear,
    required String term,
    required List<String> subjects,
  }) async {
    final ranks = <String, String>{};
    for (final subject in subjects) {
      final allGrades = await db.getGradesForSelection(
        className: className,
        academicYear: academicYear,
        subject: subject,
        term: term,
      );
      if (allGrades.isEmpty) {
        ranks[subject] = '-';
        continue;
      }
      final byStudent = <String, List<Grade>>{};
      for (final grade in allGrades) {
        byStudent.putIfAbsent(grade.studentId, () => []).add(grade);
      }
      final myGrades = byStudent[studentId];
      if (myGrades == null || myGrades.isEmpty) {
        ranks[subject] = '-';
        continue;
      }
      final myAvg = _computeWeightedAverageOn20(myGrades);
      final averages = byStudent.values
          .map(_computeWeightedAverageOn20)
          .toList();
      final rank = 1 + averages.where((v) => v > myAvg + 0.001).length;
      ranks[subject] = '$rank';
    }
    return ranks;
  }

  static pw.Widget _buildAveragesSection(
    String appreciation,
    String mention,
    List<double?> moyennesParPeriode,
    List<String> allTerms,
    double? moyenneAnnuelle,
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    int rang,
    int nbEleves,
    double moyenneGenerale,
    String selectedTerm,
    int attendanceJustifiee,
    int attendanceInjustifiee,
    int retards,
    double presencePercent,
    String periodLabel,
    double? moyenneAnnuelleClasse,
    int? rangAnnuel,
    int? nbElevesAnnuel,
    pw.Font fontBold,
    pw.Font font,
  ) {
    final List<Map<String, String>> periodRows = [];
    final bool showAllRanks = moyenneAnnuelle != null;
    for (int i = 0; i < allTerms.length; i++) {
      final value = (i < moyennesParPeriode.length)
          ? moyennesParPeriode[i]
          : null;
      final label = allTerms[i];
      final bool isSelected =
          selectedTerm.trim().isNotEmpty && label == selectedTerm;
      final String resolvedValue = isSelected
          ? _formatNumber(moyenneGenerale)
          : (value != null ? _formatNumber(value) : '-');
      final suffix =
          (nbEleves > 0 && rang <= nbEleves && (showAllRanks || isSelected))
          ? ' (r $rang/$nbEleves)'
          : '';
      periodRows.add({'label': label, 'value': resolvedValue + suffix});
    }
    final moyenneAnn = moyenneAnnuelle != null
        ? _formatNumber(moyenneAnnuelle)
        : null;
    final moyenneClass =
        moyenneGeneraleDeLaClasse != null && moyenneGeneraleDeLaClasse > 0
        ? _formatNumber(moyenneGeneraleDeLaClasse)
        : '-';
    final moyenneMax = moyenneLaPlusForte != null && moyenneLaPlusForte > 0
        ? _formatNumber(moyenneLaPlusForte)
        : '-';
    final moyenneMin = moyenneLaPlusFaible != null && moyenneLaPlusFaible > 0
        ? _formatNumber(moyenneLaPlusFaible)
        : '-';
    final mentionText = mention.trim().isNotEmpty ? mention.trim() : '-';
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all()),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'I-Moyennes',
                  style: pw.TextStyle(font: fontBold, fontSize: 8.5),
                ),
                pw.SizedBox(height: 3),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.2),
                    1: pw.FlexColumnWidth(1.8),
                  },
                  children: [
                    for (final row in periodRows)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 3,
                            ),
                            child: pw.Text(
                              row['label']!,
                              style: pw.TextStyle(font: font, fontSize: 7.5),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 3,
                            ),
                            child: pw.Text(
                              row['value']!,
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 7.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (moyenneAnn != null) ...[
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Presence: ' +
                        (presencePercent > 0
                            ? '${presencePercent.toStringAsFixed(1)}%'
                            : '-') +
                        '    |    Abs. h: ' +
                        ((attendanceJustifiee + attendanceInjustifiee) > 0
                            ? '${attendanceJustifiee + attendanceInjustifiee}'
                            : '-') +
                        '    |    Just.: ' +
                        (attendanceJustifiee > 0
                            ? '$attendanceJustifiee'
                            : '-') +
                        '    |    Inj.: ' +
                        (attendanceInjustifiee > 0
                            ? '$attendanceInjustifiee'
                            : '-') +
                        '    |    Ret.: ' +
                        (retards > 0 ? '$retards' : '-'),
                    style: pw.TextStyle(font: font, fontSize: 7),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 4,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    _badgeText('Mention', mentionText, font, fontBold),
                    pw.SizedBox(width: 6),
                    _badgeText(
                      'Rang',
                      nbEleves > 0 && rang <= nbEleves
                          ? '$rang/$nbEleves'
                          : '-',
                      font,
                      fontBold,
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.2),
                    1: pw.FlexColumnWidth(0.8),
                    2: pw.FlexColumnWidth(1.2),
                    3: pw.FlexColumnWidth(0.8),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        _miniCell('Moy. forte', font),
                        _miniCell(moyenneMax, fontBold),
                        _miniCell('Moy. faible', font),
                        _miniCell(moyenneMin, fontBold),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        _miniCell('Moy. classe', font),
                        _miniCell(moyenneClass, fontBold),
                        _miniCell('Rang', font),
                        _miniCell(
                          (nbEleves > 0 && rang <= nbEleves)
                              ? '$rang/$nbEleves'
                              : '-',
                          fontBold,
                        ),
                      ],
                    ),
                    if (moyenneAnn != null) ...[
                      pw.TableRow(
                        children: [
                          _miniCell('Moy. annuelle', font),
                          _miniCell(moyenneAnn, fontBold),
                          _miniCell('Moy. ann. classe', font),
                          _miniCell(
                            moyenneAnnuelleClasse != null
                                ? _formatNumber(moyenneAnnuelleClasse)
                                : '-',
                            fontBold,
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          _miniCell('Rang annuel', font),
                          _miniCell(
                            (rangAnnuel != null &&
                                    nbElevesAnnuel != null &&
                                    nbElevesAnnuel > 0)
                                ? '$rangAnnuel/$nbElevesAnnuel'
                                : '-',
                            fontBold,
                          ),
                          _miniCell('', font),
                          _miniCell('', fontBold),
                        ],
                      ),
                    ],
                  ],
                ),
                if (moyenneAnn == null) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Presence: ' +
                        (presencePercent > 0
                            ? '${presencePercent.toStringAsFixed(1)}%'
                            : '-') +
                        '    |    Abs. h: ' +
                        ((attendanceJustifiee + attendanceInjustifiee) > 0
                            ? '${attendanceJustifiee + attendanceInjustifiee}'
                            : '-') +
                        '    |    Just.: ' +
                        (attendanceJustifiee > 0
                            ? '$attendanceJustifiee'
                            : '-') +
                        '    |    Inj.: ' +
                        (attendanceInjustifiee > 0
                            ? '$attendanceInjustifiee'
                            : '-') +
                        '    |    Ret.: ' +
                        (retards > 0 ? '$retards' : '-'),
                    style: pw.TextStyle(font: font, fontSize: 7),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCouncilSection(
    String travail,
    String conduite,
    String decision,
    String decisionAutomatique,
    String honneur,
    String encouragement,
    pw.Font fontBold,
    pw.Font font,
  ) {
    final resolvedTravail = travail.trim().isNotEmpty
        ? travail.trim()
        : '____________________';
    final resolvedConduite = conduite.trim().isNotEmpty
        ? conduite.trim()
        : '____________________';
    final travailCheck = honneur.trim().toUpperCase() == 'OUI';
    final encouragementCheck = encouragement.trim().toUpperCase() == 'OUI';
    final resolvedDecision = decision.trim().isNotEmpty
        ? decision.trim()
        : (decisionAutomatique.trim().isNotEmpty
              ? decisionAutomatique.trim()
              : '................................................');
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all()),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'II-Appreciations du conseil des professeurs',
            style: pw.TextStyle(font: fontBold, fontSize: 8.5),
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Travail: $resolvedTravail',
                  style: pw.TextStyle(font: font, fontSize: 7.5),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  'Conduite: $resolvedConduite',
                  style: pw.TextStyle(font: font, fontSize: 7.5),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Felicitations: ${_checkboxText(travailCheck)}  |  Encouragements: ${_checkboxText(encouragementCheck)}  |  Tableau d\'honneur: ${_checkboxText(travailCheck)}',
            style: pw.TextStyle(font: font, fontSize: 7.5),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'III- Decision du conseil des professeurs: $resolvedDecision',
            style: pw.TextStyle(font: font, fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  static pw.Widget _miniCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 7.2)),
    );
  }

  static pw.Widget _badgeText(
    String label,
    String value,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border.all(width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(font: font, fontSize: 7)),
          pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 7)),
        ],
      ),
    );
  }

  static pw.Widget _buildCategorySummaryRow(
    String categoryName,
    double? studentAvg,
    double? classAvg,
    int subjectCount,
    pw.Font fontBold,
    pw.Font font,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
        color: PdfColors.grey100,
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          style: pw.TextStyle(font: font, fontSize: 7.5),
          children: [
            pw.TextSpan(
              text: categoryName,
              style: pw.TextStyle(font: fontBold, fontSize: 7.5),
            ),
            pw.TextSpan(
              text:
                  '  |  Moy. intermédiaire: ${_formatOptionalNumber(studentAvg)}'
                  '  |  Moy. cat. classe: ${_formatOptionalNumber(classAvg)}'
                  '  |  $subjectCount matière(s)',
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _avgRow(
    String label,
    String value,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8.5)),
        ),
        pw.SizedBox(width: 6),
        pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 9)),
      ],
    );
  }

  static pw.Widget _buildFooter(
    String faitA,
    String leDate,
    String titulaireName,
    String directorName,
    String titulaireCivility,
    String directorCivility,
    pw.Font fontBold,
    pw.Font font,
  ) {
    final titulaireLabel = titulaireName.trim();
    final directorLabel = _withCivility(directorName, directorCivility);
    final titulaire = titulaireLabel.isNotEmpty
        ? titulaireLabel
        : '__________________';
    final director = directorLabel.isNotEmpty
        ? directorLabel
        : '__________________';

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Fait à $faitA, le $leDate',
              style: pw.TextStyle(font: font, fontSize: 9),
            ),
            pw.SizedBox(height: 15),
            pw.Text(
              'Le titulaire',
              style: pw.TextStyle(font: fontBold, fontSize: 9),
            ),
            pw.SizedBox(height: 4),
            _signatureBlock(titulaire, fontBold, font),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(height: 15),
            pw.Text(
              'Le Chef d\'établissement',
              style: pw.TextStyle(font: fontBold, fontSize: 9),
            ),
            pw.SizedBox(height: 4),
            _signatureBlock(director, fontBold, font),
          ],
        ),
      ],
    );
  }

  static pw.Widget _signatureBlock(
    String name,
    pw.Font fontBold,
    pw.Font font,
  ) {
    return pw.Column(
      children: [
        pw.Container(
          width: 120,
          height: 34,
          decoration: pw.BoxDecoration(border: pw.Border.all()),
        ),
        pw.Container(
          width: 120,
          height: 14,
          decoration: pw.BoxDecoration(border: pw.Border.all()),
          alignment: pw.Alignment.center,
          child: pw.Text(
            name,
            style: pw.TextStyle(font: fontBold, fontSize: 7),
          ),
        ),
      ],
    );
  }

  static String _withCivility(String name, String civility) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final civ = civility.trim();
    return civ.isNotEmpty ? '$civ $trimmed' : trimmed;
  }

  static pw.Widget _buildFooterNote(String footerNote, pw.Font font) {
    final note = footerNote.trim();
    if (note.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Center(
        child: pw.Text(
          note,
          style: pw.TextStyle(
            font: font,
            fontSize: 7,
            fontStyle: pw.FontStyle.italic,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
  }

  static pw.Widget _cellHeader(String text, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(3),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 8),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _cell(String text, pw.Font font, {double fontSize = 8}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(3),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: fontSize),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static String _getAppreciation(double moyenne) {
    if (moyenne >= 16) return 'Tres Bien';
    if (moyenne >= 19) return 'Excellent';
    if (moyenne >= 16) return 'Très Bien';
    if (moyenne >= 14) return 'Bien';
    if (moyenne >= 12) return 'Assez Bien';
    if (moyenne >= 10) return 'Passable';
    return 'Insuffisant';
  }

  static String dashIfBlank(String? value, {String placeholder = '-'}) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? placeholder : v;
  }

  static String _formatDate(String dateString) {
    if (dateString.trim().isEmpty) return '-';
    try {
      DateTime? date;
      if (dateString.contains('-') && dateString.length >= 10) {
        date = DateTime.tryParse(dateString);
      } else if (dateString.contains('/')) {
        final parts = dateString.split('/');
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final year = int.tryParse(parts[2]);
          if (day != null && month != null && year != null) {
            date = DateTime(year, month, day);
          }
        }
      }
      if (date != null) {
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      }
    } catch (_) {}
    return dateString;
  }

  static String _buildBirthInfo(Student student) {
    final date = _formatDate(student.dateOfBirth);
    final place = student.placeOfBirth?.trim();
    if (place != null && place.isNotEmpty) {
      return '$date à $place';
    }
    return date;
  }

  static String _formatGender(String value) {
    final v = value.trim().toLowerCase();
    if (v.startsWith('m')) return 'M';
    if (v.startsWith('f')) return 'F';
    return '-';
  }

  static String _checkboxText(bool value) => value ? 'OUI' : 'NON';

  static bool _shouldShowAnnual(String periodLabel, String term) {
    final pl = periodLabel.toLowerCase();
    final t = term.toLowerCase();
    if (pl.contains('trimestre')) return t.contains('3');
    if (pl.contains('semestre')) return t.contains('2');
    return false;
  }

  static String _autoConduiteText({
    required int attendanceInjustifiee,
    required int retards,
    required String sanctions,
  }) {
    if (sanctions.trim().isNotEmpty) return 'A ameliorer';
    if (attendanceInjustifiee > 0 || retards > 0) return 'Passable';
    return 'Tres bonne conduite';
  }

  static String _autoHonneurText(double average) {
    return average >= 16.0 ? 'OUI' : 'NON';
  }

  static String _autoEncouragementText(double average) {
    if (average >= 14.0 && average < 16.0) return 'OUI';
    return 'NON';
  }

  static String _autoAppreciationGeneraleText(double average) {
    if (average >= 16.0) return 'Excellent travail';
    if (average >= 14.0) return 'Tres bon dans l\'ensemble';
    if (average >= 12.0) return 'Bon dans l\'ensemble';
    if (average >= 19.0) return 'Excellent travail';
    if (average >= 16.0) return 'Très bon dans l\'ensemble';
    if (average >= 14.0) return 'Bon dans l\'ensemble';
    if (average >= 12.0) return 'Assez Bien';
    if (average >= 10.0) return 'Passable';
    return 'Insuffisant';
  }

  static Future<Map<String, Map<String, int>>> _computeRankPerTerm({
    required String studentId,
    required String className,
    required String academicYear,
    required List<String> terms,
  }) async {
    final DatabaseService db = DatabaseService();
    final Map<String, Map<String, int>> rankPerTerm = {};
    const double eps = 0.001;
    for (final term in terms) {
      final gradesForTerm = await db.getAllGradesForPeriod(
        className: className,
        academicYear: academicYear,
        term: term,
      );
      final Map<String, double> nByStudent = {};
      final Map<String, double> cByStudent = {};
      for (final g in gradesForTerm.where(
        (g) =>
            (g.type == 'Devoir' || g.type == 'Composition') && g.value != null,
      )) {
        if (g.maxValue > 0 && g.coefficient > 0) {
          nByStudent[g.studentId] =
              (nByStudent[g.studentId] ?? 0) +
              ((g.value / g.maxValue) * 20) * g.coefficient;
          cByStudent[g.studentId] =
              (cByStudent[g.studentId] ?? 0) + g.coefficient;
        }
      }
      final List<double> avgs = [];
      double myAvg = 0.0;
      nByStudent.forEach((sid, n) {
        final c = cByStudent[sid] ?? 0.0;
        final avg = c > 0 ? (n / c) : 0.0;
        avgs.add(avg);
        if (sid == studentId) myAvg = avg;
      });
      avgs.sort((a, b) => b.compareTo(a));
      final int nb = avgs.length;
      final int rank = 1 + avgs.where((v) => (v - myAvg) > eps).length;
      rankPerTerm[term] = {'rank': rank, 'nb': nb};
    }
    return rankPerTerm;
  }

  static String teacherSurname(String? value, {String placeholder = '-'}) {
    final v = (value ?? '').replaceAll(',', ' ').trim();
    if (v.isEmpty) return placeholder;
    final parts = v.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return placeholder;
    return parts.last;
  }

  static double _computeWeightedAverageOn20(List<Grade> grades) {
    double total = 0.0;
    double totalCoeff = 0.0;
    for (final g in grades) {
      if (g.maxValue > 0 && g.coefficient > 0) {
        total += ((g.value / g.maxValue) * 20) * g.coefficient;
        totalCoeff += g.coefficient;
      }
    }
    return totalCoeff > 0 ? (total / totalCoeff) : 0.0;
  }

  static String _formatOptionalNumber(double? value) {
    if (value == null) return '-';
    return _formatNumber(value);
  }

  static String _formatNumber(double value) {
    return value.toStringAsFixed(2);
  }

  static String _formatCoefficient(double value) {
    // Enlève les zéros inutiles après la virgule pour les coefficients
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    } else if ((value * 10) == (value * 10).truncateToDouble()) {
      return value.toStringAsFixed(1);
    } else {
      return value.toStringAsFixed(2);
    }
  }

  static double? _parseMaybeNumber(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '-') return null;
    final normalized = trimmed.replaceAll(',', '.');
    return double.tryParse(normalized);
  }
}
