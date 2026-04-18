import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:intl/intl.dart';

class MockExamPdfService {
  static Future<List<int>> generateMockExamResultSlipsPdf({
    required List<Student> students,
    required List<Grade> sessionGrades,
    required List<Course> subjects,
    required String session,
    required String academicYear,
    required SchoolInfo schoolInfo,
    required Map<String, double> subjectCoefficients,
    bool isLandscape = false,
  }) async {
    final pdf = pw.Document();
    final fonts = await PdfService.loadPdfFonts();
    final regularFont = fonts.regular;
    final boldFont = fonts.bold;

    for (final student in students) {
      final studentGrades = sessionGrades.where((g) => g.studentId == student.id).toList();
      
      // Skip students with no grades? Maybe better to keep them with '-'
      // if (studentGrades.isEmpty) continue;

      final pageFormat = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (context) {
            return pw.Stack(
              children: [
                // Watermark
                if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
                  pw.Positioned.fill(
                    child: pw.Center(
                      child: pw.Opacity(
                        opacity: 0.08,
                        child: pw.Image(
                          pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                          width: 300,
                        ),
                      ),
                    ),
                  ),
                // Content
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildHeader(schoolInfo, regularFont, boldFont, academicYear),
                    pw.SizedBox(height: 20),
                    pw.Center(
                      child: pw.Text(
                        'RELEVÉ DE NOTES - ${session.toUpperCase()}',
                        style: pw.TextStyle(font: boldFont, fontSize: 14),
                      ),
                    ),
                    pw.SizedBox(height: 20),
                    _buildStudentInfo(student, regularFont, boldFont),
                    pw.SizedBox(height: 20),
                    _buildGradesTable(subjects, studentGrades, regularFont, boldFont, subjectCoefficients),
                    pw.SizedBox(height: 20),
                    _buildSummary(studentGrades, regularFont, boldFont, subjectCoefficients),
                    pw.Spacer(),
                    _buildFooter(schoolInfo, regularFont, boldFont),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  static Future<List<int>> generateMockExamSynthesisPdf({
    required List<Student> students,
    required List<Grade> sessionGrades,
    required List<Course> subjects,
    required String session,
    required String academicYear,
    required SchoolInfo schoolInfo,
    required String className,
    required Map<String, double> subjectCoefficients,
    bool isLandscape = true,
  }) async {
    final pdf = pw.Document();
    final fonts = await PdfService.loadPdfFonts();
    final regularFont = fonts.regular;
    final boldFont = fonts.bold;

    // Sort students by session average
    final List<Map<String, dynamic>> studentsWithAvg = students.map((s) {
      final grades = sessionGrades.where((g) => g.studentId == s.id).toList();
      double weightedSum = 0;
      double coeffSum = 0;
      for (final g in grades) {
        final coeff = subjectCoefficients[g.subjectId] ?? 1.0;
        weightedSum += (g.value * coeff);
        coeffSum += coeff;
      }
      final avg = coeffSum > 0 ? weightedSum / coeffSum : 0.0;
      return {'student': s, 'avg': avg};
    }).toList();

    studentsWithAvg.sort((a, b) => (b['avg'] as double).compareTo(a['avg'] as double));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(schoolInfo.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 12)),
                pw.Text('SESSION : ${session.toUpperCase()}', style: pw.TextStyle(font: boldFont, fontSize: 12)),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Center(
              child: pw.Text(
                'TABLEAU DE SYNTHÈSE DES RÉSULTATS - $className ($academicYear)',
                style: pw.TextStyle(font: boldFont, fontSize: 14, decoration: pw.TextDecoration.underline),
              ),
            ),
            pw.SizedBox(height: 15),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FlexColumnWidth(3),
                ...Map.fromIterable(
                  Iterable.generate(subjects.length),
                  key: (i) => i + 2,
                  value: (_) => const pw.FixedColumnWidth(40),
                ),
                subjects.length + 2: const pw.FixedColumnWidth(50),
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('N°', boldFont),
                    _cell('Nom & Prénoms', boldFont, center: false),
                    ...subjects.map((sub) => _cell(sub.name, boldFont)),
                    _cell('Moy.', boldFont),
                  ],
                ),
                // Rows
                ...studentsWithAvg.asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final s = data['student'] as Student;
                  final avg = data['avg'] as double;
                  final grades = sessionGrades.where((g) => g.studentId == s.id).toList();

                  return pw.TableRow(
                    children: [
                      _cell((index + 1).toString(), regularFont),
                      _cell('${s.lastName} ${s.firstName}', regularFont, center: false),
                      ...subjects.map((sub) {
                        final g = grades.firstWhere(
                          (grade) => grade.subject == sub.name,
                          orElse: () => Grade(studentId: '', className: '', academicYear: '', subjectId: '', subject: '', term: '', value: -1, type: ''),
                        );
                        return _cell(g.value >= 0 ? g.value.toStringAsFixed(1) : '-', regularFont);
                      }),
                      _cell(avg.toStringAsFixed(2), boldFont),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text('Fait à ${schoolInfo.address ?? ''}, le ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: pw.TextStyle(font: regularFont, fontSize: 10)),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<List<int>> generateMockExamRankingPdf({
    required List<Student> students,
    required List<Grade> sessionGrades,
    required String session,
    required String academicYear,
    required SchoolInfo schoolInfo,
    required String className,
    required Map<String, double> subjectCoefficients,
  }) async {
    final pdf = pw.Document();
    final fonts = await PdfService.loadPdfFonts();
    final regularFont = fonts.regular;
    final boldFont = fonts.bold;

    final List<Map<String, dynamic>> studentsWithAvg = students.map((s) {
      final grades = sessionGrades.where((g) => g.studentId == s.id).toList();
      double weightedSum = 0;
      double coeffSum = 0;
      for (final g in grades) {
        final coeff = subjectCoefficients[g.subjectId] ?? 1.0;
        weightedSum += (g.value * coeff);
        coeffSum += coeff;
      }
      final avg = coeffSum > 0 ? weightedSum / coeffSum : 0.0;
      return {'student': s, 'avg': avg};
    }).toList();

    studentsWithAvg.sort((a, b) => (b['avg'] as double).compareTo(a['avg'] as double));

    for (int i = 0; i < studentsWithAvg.length; i++) {
      if (i > 0 && (studentsWithAvg[i]['avg'] as double) == (studentsWithAvg[i - 1]['avg'] as double)) {
        studentsWithAvg[i]['rank'] = studentsWithAvg[i - 1]['rank'];
        studentsWithAvg[i]['isEx'] = true;
        studentsWithAvg[i - 1]['isEx'] = true;
      } else {
        studentsWithAvg[i]['rank'] = i + 1;
        studentsWithAvg[i]['isEx'] = false;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) {
          return [
            _buildHeader(schoolInfo, regularFont, boldFont, academicYear),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'CLASSEMENT PAR MÉRITE - ${session.toUpperCase()}',
                style: pw.TextStyle(font: boldFont, fontSize: 14, decoration: pw.TextDecoration.underline),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Classe : $className', style: pw.TextStyle(font: boldFont, fontSize: 12)),
              ]
            ),
            pw.SizedBox(height: 15),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FixedColumnWidth(45),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(70),
                3: const pw.FixedColumnWidth(100),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('Rang', boldFont),
                    _cell('Nom & Prénoms', boldFont, center: false),
                    _cell('Moy. / 20', boldFont),
                    _cell('Mention', boldFont),
                  ],
                ),
                ...studentsWithAvg.map((data) {
                  final s = data['student'] as Student;
                  final avg = data['avg'] as double;
                  final rank = data['rank'] as int;
                  final isEx = data['isEx'] as bool;

                  String rankStr = '$rank';
                  if (rank == 1) rankStr = '1er';
                  else rankStr = '${rank}ème';
                  
                  if (isEx) {
                    rankStr += ' ex';
                  }

                  return pw.TableRow(
                    children: [
                      _cell(rankStr, boldFont),
                      _cell('${s.lastName} ${s.firstName}', regularFont, center: false),
                      _cell(avg.toStringAsFixed(2), boldFont),
                      _cell(_getMention(avg), regularFont),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text('Fait à ${schoolInfo.address ?? ''}, le ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: pw.TextStyle(font: regularFont, fontSize: 10)),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(SchoolInfo info, pw.Font regular, pw.Font bold, String academicYear) {
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left: Ministry / Education Direction
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (info.ministry != null && info.ministry!.isNotEmpty)
                    pw.Text(info.ministry!.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 8)),
                  if (info.educationDirection != null && info.educationDirection!.isNotEmpty)
                    pw.Text(info.educationDirection!, style: pw.TextStyle(font: regular, fontSize: 7)),
                  if (info.inspection != null && info.inspection!.isNotEmpty)
                    pw.Text('Inspection: ${info.inspection}', style: pw.TextStyle(font: regular, fontSize: 7)),
                ],
              ),
            ),
            // Center: Logo
            if (info.logoPath != null && File(info.logoPath!).existsSync())
              pw.Expanded(
                flex: 1,
                child: pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(File(info.logoPath!).readAsBytesSync()),
                    height: 50,
                  ),
                ),
              )
            else
              pw.Spacer(flex: 1),
            // Right: Republic / Motto
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (info.republic != null && info.republic!.isNotEmpty)
                    pw.Text(info.republic!.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 8)),
                  if (info.republicMotto != null && info.republicMotto!.isNotEmpty)
                    pw.Text(info.republicMotto!, style: pw.TextStyle(font: regular, fontSize: 7, fontStyle: pw.FontStyle.italic)),
                  pw.SizedBox(height: 4),
                  pw.Text('Année Académique: $academicYear', style: pw.TextStyle(font: regular, fontSize: 8)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        // Center: School Identity
        pw.Text(info.name.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 12, color: PdfColors.blue800)),
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1, color: PdfColors.grey400),
      ],
    );
  }

  static pw.Widget _buildStudentInfo(Student student, pw.Font regular, pw.Font bold) {
    String formattedDate = student.dateOfBirth;
    try {
      if (student.dateOfBirth.contains('T')) {
        final date = DateTime.parse(student.dateOfBirth);
        formattedDate = DateFormat('dd/MM/yyyy').format(date);
      } else if (student.dateOfBirth.contains('-')) {
        final parts = student.dateOfBirth.split('-');
        if (parts.length == 3) {
          formattedDate = '${parts[2]}/${parts[1]}/${parts[0]}';
        }
      }
    } catch (_) {}

    final birthInfo = student.placeOfBirth != null && student.placeOfBirth!.isNotEmpty
        ? '$formattedDate à ${student.placeOfBirth!}'
        : formattedDate;

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              pw.Expanded(child: _infoRow('Nom et Prénoms:', '${student.lastName} ${student.firstName}', bold)),
              pw.Expanded(child: _infoRow('Classe:', student.className, bold)),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            children: [
              pw.Expanded(child: _infoRow('Né(e) le:', birthInfo, regular)),
              pw.Expanded(child: _infoRow('Sexe:', student.gender == 'M' ? 'Masculin' : 'Féminin', regular)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(String label, String value, pw.Font font) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label ', style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey700)),
          pw.TextSpan(text: value, style: pw.TextStyle(font: font, fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _buildGradesTable(List<Course> subjects, List<Grade> grades, pw.Font regular, pw.Font bold, Map<String, double> subjectCoefficients) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _cell('Matière', bold, center: false),
            _cell('Coef', bold),
            _cell('Note / 20', bold),
            _cell('Mention', bold),
          ],
        ),
        ...subjects.map((sub) {
          final g = grades.firstWhere(
            (g) => g.subject == sub.name,
            orElse: () => Grade(studentId: '', className: '', academicYear: '', subjectId: sub.id, subject: sub.name, term: '', value: 0, type: '', coefficient: 1.0),
          );
          
          final hasGrade = grades.any((gr) => gr.subject == sub.name);
          final coeff = subjectCoefficients[sub.id] ?? 1.0;

          return pw.TableRow(
            children: [
              _cell(sub.name, regular, center: false),
              _cell(coeff.toStringAsFixed(coeff % 1 == 0 ? 0 : 1), regular),
              _cell(hasGrade ? g.value.toStringAsFixed(2) : '-', regular),
              _cell(hasGrade ? _getMention(g.value) : '-', regular),
            ],
          );
        }).toList(),
      ],
    );
  }

  static pw.Widget _cell(String text, pw.Font font, {bool center = true}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 11),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  static double calculateWeightedAverage(List<Grade> grades, Map<String, double> subjectCoefficients) {
    if (grades.isEmpty) return 0.0;
    double totalWeighted = 0;
    double totalCoeffs = 0;
    for (final g in grades) {
      final coeff = subjectCoefficients[g.subjectId] ?? 1.0;
      totalWeighted += (g.value * coeff);
      totalCoeffs += coeff;
    }
    return totalCoeffs > 0 ? totalWeighted / totalCoeffs : 0.0;
  }

  static pw.Widget _buildSummary(List<Grade> grades, pw.Font regular, pw.Font bold, Map<String, double> subjectCoefficients) {
    if (grades.isEmpty) return pw.SizedBox();

    final avg = calculateWeightedAverage(grades, subjectCoefficients);
    
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            border: pw.Border.all(color: PdfColors.blue100),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('MOYENNE GÉNÉRALE: ${avg.toStringAsFixed(2)} / 20', style: pw.TextStyle(font: bold, fontSize: 13, color: PdfColors.blue800)),
              pw.Text('Observation: ${_getObservation(avg)}', style: pw.TextStyle(font: regular, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  static String _getMention(double note) {
    if (note >= 16) return 'Excellent';
    if (note >= 14) return 'Bien';
    if (note >= 12) return 'Assez Bien';
    if (note >= 10) return 'Passable';
    return 'Insuffisant';
  }

  static String _getObservation(double avg) {
    if (avg >= 10) return 'Session réussie';
    return 'Session non validée';
  }

  static pw.Widget _buildFooter(SchoolInfo info, pw.Font regular, pw.Font bold) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: pw.TextStyle(font: regular, fontSize: 9)),
            pw.Text('Le Chef d\'Établissement (Signature et Cachet)', style: pw.TextStyle(font: bold, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
