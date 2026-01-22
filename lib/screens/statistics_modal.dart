import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:intl/intl.dart';

import 'package:school_manager/models/school_info.dart';

class StatisticsModal extends StatefulWidget {
  final String? className;
  final String? academicYear;
  final String? term;
  final List<Student> students;
  final List<Grade> grades;
  final List<Course> subjects;
  final DatabaseService dbService;

  const StatisticsModal({
    Key? key,
    required this.className,
    required this.academicYear,
    required this.term,
    required this.students,
    required this.grades,
    required this.subjects,
    required this.dbService,
  }) : super(key: key);

  @override
  _StatisticsModalState createState() => _StatisticsModalState();
}

class _StatisticsModalState extends State<StatisticsModal> {
  bool isLoading = true;
  Map<String, dynamic> stats = {};
  late SchoolInfo schoolInfo;

  String _displayStudentName(Student student) {
    final lastName = student.lastName.trim();
    final firstName = student.firstName.trim();
    if (lastName.isEmpty) return firstName;
    if (firstName.isEmpty) return lastName;
    return '$lastName $firstName';
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

  static double _sumCoefficients(List<Grade> grades) {
    double totalCoeff = 0.0;
    for (final g in grades) {
      if (g.maxValue > 0 && g.coefficient > 0) {
        totalCoeff += g.coefficient;
      }
    }
    return totalCoeff;
  }

  @override
  void initState() {
    super.initState();
    _loadSchoolInfo();
    _loadStats();
  }

  Future<void> _loadSchoolInfo() async {
    schoolInfo = await loadSchoolInfo();
  }

  Future<void> _loadStats() async {
    if (widget.className == null ||
        widget.academicYear == null ||
        widget.term == null) {
      setState(() => isLoading = false);
      return;
    }

    final classStudents = widget.students
        .where(
          (s) =>
              s.className == widget.className &&
              s.academicYear == widget.academicYear,
        )
        .toList();
    stats['student_count'] = classStudents.length;

    final Map<String, double> subjectWeightsById = await widget.dbService
        .getClassCourseCoefficientsById(
          widget.className!,
          widget.academicYear!,
        );
    final Map<String, double> subjectWeightsByName = await widget.dbService
        .getClassSubjectCoefficients(widget.className!, widget.academicYear!);

    // Calculate general average for each student
    List<Map<String, dynamic>> studentAverages = [];
    for (var student in classStudents) {
      final studentGrades = widget.grades
          .where((g) => g.studentId == student.id && g.term == widget.term)
          .toList();
      final Map<String, List<Grade>> bySubject = {};
      for (final g in studentGrades) {
        final key = g.subjectId.trim().isNotEmpty ? g.subjectId : g.subject;
        bySubject.putIfAbsent(key, () => []).add(g);
      }
      double sumPoints = 0.0;
      double sumWeights = 0.0;
      bySubject.forEach((_, list) {
        final average = _computeWeightedAverageOn20(list);
        final subjectId = list.first.subjectId.trim();
        final subjectName = list.first.subject;
        double? weight = subjectId.isNotEmpty
            ? subjectWeightsById[subjectId]
            : null;
        weight ??= subjectWeightsByName[subjectName];
        weight ??= _sumCoefficients(list);
        if (weight > 0) {
          sumPoints += average * weight;
          sumWeights += weight;
        }
      });
      final average = sumWeights > 0 ? (sumPoints / sumWeights) : 0.0;
      studentAverages.add({'student': student, 'average': average});
    }

    // Classement par mérite (avec ex æquo)
    studentAverages.sort((a, b) => b['average'].compareTo(a['average']));
    const double eps = 0.001; // tolérance d'égalité des moyennes
    int position = 0; // position 1..N
    int currentRank = 0; // rang affiché (standard competition ranking)
    double? prevAvg;
    for (int i = 0; i < studentAverages.length; i++) {
      final entry = studentAverages[i];
      position += 1;
      final double avg = entry['average'] as double;
      if (prevAvg == null || (avg - prevAvg!).abs() > eps) {
        currentRank = position;
        prevAvg = avg;
      }
      // Ex æquo si voisin (précédent ou suivant) a même moyenne
      bool ex = false;
      if (i > 0) {
        final double prev = (studentAverages[i - 1]['average'] as double);
        if ((avg - prev).abs() <= eps) ex = true;
      }
      if (!ex && i < studentAverages.length - 1) {
        final double next = (studentAverages[i + 1]['average'] as double);
        if ((avg - next).abs() <= eps) ex = true;
      }
      entry['rank'] = currentRank;
      entry['exaequo'] = ex;
    }
    stats['merit_ranking'] = studentAverages;

    // Top 3 et Bottom 3
    stats['top_3_students'] = studentAverages.take(3).toList();
    stats['bottom_3_students'] = studentAverages.reversed.take(3).toList();

    // Taux de réussite par matière & Moyennes de classe par matière
    Map<String, double> successRateBySubject = {};
    Map<String, double> classAverageBySubject = {};
    for (var subject in widget.subjects) {
      int studentsWithAverage = 0;
      double totalSubjectAverage = 0;
      int studentCountForSubject = 0;

      for (var student in classStudents) {
        final subjectGrades = widget.grades.where(
          (g) =>
              g.studentId == student.id &&
              (g.subjectId.trim().isNotEmpty
                  ? g.subjectId == subject.id
                  : g.subject == subject.name) &&
              g.term == widget.term,
        );
        final subjectList = subjectGrades.toList();
        final double subjectAverage = _computeWeightedAverageOn20(subjectList);
        if (_sumCoefficients(subjectList) > 0) {
          totalSubjectAverage += subjectAverage;
          studentCountForSubject++;
          if (subjectAverage >= 10) {
            studentsWithAverage++;
          }
        }
      }

      if (classStudents.isNotEmpty) {
        successRateBySubject[subject.name] =
            (studentsWithAverage / classStudents.length) * 100;
      }
      if (studentCountForSubject > 0) {
        classAverageBySubject[subject.name] =
            totalSubjectAverage / studentCountForSubject;
      }
    }
    stats['success_rate_by_subject'] = successRateBySubject;
    stats['class_average_by_subject'] = classAverageBySubject;

    // Nombre d'élèves par tranche de notes
    stats['excellent_students'] = studentAverages
        .where((s) => s['average'] >= 19)
        .length;
    stats['tres_bien_students'] = studentAverages
        .where((s) => s['average'] >= 16 && s['average'] < 19)
        .length;
    stats['bien_students'] = studentAverages
        .where((s) => s['average'] >= 14 && s['average'] < 16)
        .length;
    stats['assez_bien_students'] = studentAverages
        .where((s) => s['average'] >= 12 && s['average'] < 14)
        .length;
    stats['passable_students'] = studentAverages
        .where((s) => s['average'] >= 10 && s['average'] < 12)
        .length;
    stats['insuffisant_students'] = studentAverages
        .where((s) => s['average'] < 10)
        .length;

    // --- New: Global Class Success Rate, Gender & Status Breakdown ---
    int globalAdmis = studentAverages
        .where((s) => (s['average'] as double) >= 10)
        .length;
    stats['global_success_rate'] = studentAverages.isNotEmpty
        ? (globalAdmis / studentAverages.length) * 100
        : 0.0;

    final genderBreakdown = <String, Map<String, int>>{};
    final statusBreakdown = <String, Map<String, int>>{};

    for (var entry in studentAverages) {
      final s = entry['student'] as Student;
      final avg = entry['average'] as double;
      final isPassing = avg >= 10;
      final gender = (s.gender.trim().isEmpty ? 'M' : s.gender.trim())
          .toUpperCase();
      final status = (s.status.trim().isEmpty ? 'Nouveau' : s.status.trim());

      // Gender Tracking
      genderBreakdown.putIfAbsent(gender, () => {'success': 0, 'total': 0});
      genderBreakdown[gender]!['total'] =
          genderBreakdown[gender]!['total']! + 1;
      if (isPassing)
        genderBreakdown[gender]!['success'] =
            genderBreakdown[gender]!['success']! + 1;

      // Status Tracking
      statusBreakdown.putIfAbsent(status, () => {'success': 0, 'total': 0});
      statusBreakdown[status]!['total'] =
          statusBreakdown[status]!['total']! + 1;
      if (isPassing)
        statusBreakdown[status]!['success'] =
            statusBreakdown[status]!['success']! + 1;
    }
    stats['gender_breakdown'] = genderBreakdown;
    stats['status_breakdown'] = statusBreakdown;
    // -----------------------------------------------------------------

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.className == null ||
        widget.academicYear == null ||
        widget.term == null) {
      return const AlertDialog(
        title: Text("Statistiques"),
        content: Text(
          "Veuillez sélectionner une classe, une année académique et une période pour voir les statistiques.",
        ),
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFFF0F4F8),
      title: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.analytics, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  "Statistiques - ${widget.className}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Année Académique: ${widget.academicYear}"),
            Text("Période: ${widget.term}"),
            const SizedBox(height: 20),
            _buildStatCard(
              "Nombre d'élèves",
              stats['student_count'].toString(),
              Icons.people,
            ),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    "Effectif",
                    stats['student_count'].toString(),
                    Icons.people,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    "Taux Réussite",
                    "${(stats['global_success_rate'] as double).toStringAsFixed(1)}%",
                    Icons.check_circle,
                    color: (stats['global_success_rate'] as double) >= 50
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
            _buildDivider(),
            _buildRankingSection(),
            _buildDivider(),
            _buildSubjectStatsSection(),
            const SizedBox(height: 12),
            _buildClassAverageBarChart(),
            _buildDivider(),
            _buildModernBreakdownSection(
              title: "Réussite par Genre",
              icon: Icons.wc,
              data: stats['gender_breakdown'],
              color: Colors.indigo,
            ),
            _buildDivider(),
            _buildModernBreakdownSection(
              title: "Réussite par Statut",
              icon: Icons.badge_outlined,
              data: stats['status_breakdown'],
              color: Colors.teal,
            ),
            _buildDivider(),
            _buildGradeDistributionSection(),
            _buildDivider(),
            _buildTopBottomStudentsSection(),
          ],
        ),
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: _exportToExcel,
          icon: const Icon(Icons.grid_on, color: Colors.white),
          label: const Text('Exporter en Excel'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _exportToPdf,
          icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
          label: const Text('Exporter en PDF'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportToExcel() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return; // User canceled the picker

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Statistiques'];

    // Headers
    sheetObject.appendRow([
      TextCellValue('Statistiques pour la classe ${widget.className}'),
    ]);
    sheetObject.appendRow([
      TextCellValue('Année Académique: ${widget.academicYear}'),
      TextCellValue('Période: ${widget.term}'),
    ]);
    sheetObject.appendRow([]);

    sheetObject.appendRow([
      TextCellValue('Taux de réussite global'),
      TextCellValue(
        '${(stats['global_success_rate'] as double).toStringAsFixed(1)}%',
      ),
    ]);
    sheetObject.appendRow([]);

    // Ranking
    sheetObject.appendRow([TextCellValue('Classement par mérite')]);
    sheetObject.appendRow([
      TextCellValue('Rang'),
      TextCellValue('Élève'),
      TextCellValue('Moyenne'),
      TextCellValue('Ex æquo'),
    ]);
    final List<Map<String, dynamic>> ranking = stats['merit_ranking'];
    for (var i = 0; i < ranking.length; i++) {
      final Student student = ranking[i]['student'] as Student;
      sheetObject.appendRow([
        IntCellValue((ranking[i]['rank'] ?? (i + 1)) as int),
        TextCellValue(_displayStudentName(student)),
        DoubleCellValue(ranking[i]['average']),
        TextCellValue(
          ((ranking[i]['exaequo'] as bool?) ?? false) ? 'Oui' : 'Non',
        ),
      ]);
    }
    sheetObject.appendRow([]);

    // Subject Stats
    sheetObject.appendRow([TextCellValue('Statistiques par matière')]);
    sheetObject.appendRow([
      TextCellValue('Matière'),
      TextCellValue('Taux de réussite'),
      TextCellValue('Moyenne de classe'),
    ]);
    final Map<String, double> successRate = stats['success_rate_by_subject'];
    final Map<String, double> classAverage = stats['class_average_by_subject'];
    for (var subject in widget.subjects) {
      sheetObject.appendRow([
        TextCellValue(subject.name),
        DoubleCellValue(successRate[subject.name] ?? 0),
        DoubleCellValue(classAverage[subject.name] ?? 0),
      ]);
    }
    sheetObject.appendRow([]);

    // Grade Distribution
    sheetObject.appendRow([TextCellValue('Répartition des notes')]);
    sheetObject.appendRow([
      TextCellValue('Excellent (>= 19)'),
      IntCellValue(stats['excellent_students']),
    ]);
    sheetObject.appendRow([
      TextCellValue('Très Bien (16-19)'),
      IntCellValue(stats['tres_bien_students']),
    ]);
    sheetObject.appendRow([
      TextCellValue('Bien (14-16)'),
      IntCellValue(stats['bien_students']),
    ]);
    sheetObject.appendRow([
      TextCellValue('Assez Bien (12-14)'),
      IntCellValue(stats['assez_bien_students']),
    ]);
    sheetObject.appendRow([
      TextCellValue('Passable (10-12)'),
      IntCellValue(stats['passable_students']),
    ]);
    sheetObject.appendRow([
      TextCellValue('Insuffisant (< 10)'),
      IntCellValue(stats['insuffisant_students']),
    ]);
    sheetObject.appendRow([]);

    // Success Breakdowns
    sheetObject.appendRow([TextCellValue('Réussite détaillée')]);
    sheetObject.appendRow([TextCellValue('Par Sexe')]);
    final Map<String, dynamic> genderStats = stats['gender_breakdown'];
    genderStats.forEach((key, value) {
      final success = (value['success'] as num).toDouble();
      final total = (value['total'] as num).toDouble();
      final successRate = total > 0 ? (success / total) * 100 : 0.0;
      sheetObject.appendRow([
        TextCellValue(key),
        IntCellValue(value['total'] as int),
        TextCellValue('${successRate.toStringAsFixed(1)}%'),
      ]);
    });
    sheetObject.appendRow([]);

    sheetObject.appendRow([TextCellValue('Par Statut')]);
    final Map<String, dynamic> statusStats = stats['status_breakdown'];
    statusStats.forEach((key, value) {
      final success = (value['success'] as num).toDouble();
      final total = (value['total'] as num).toDouble();
      final successRate = total > 0 ? (success / total) * 100 : 0.0;
      sheetObject.appendRow([
        TextCellValue(key),
        IntCellValue(value['total'] as int),
        TextCellValue('${successRate.toStringAsFixed(1)}%'),
      ]);
    });
    sheetObject.appendRow([]);

    // Top/Bottom 3
    sheetObject.appendRow([TextCellValue('Top 3 des élèves')]);
    final List<Map<String, dynamic>> top3 = stats['top_3_students'];
    for (var s in top3) {
      final Student student = s['student'] as Student;
      sheetObject.appendRow([
        TextCellValue(_displayStudentName(student)),
        DoubleCellValue(s['average']),
      ]);
    }
    sheetObject.appendRow([]);
    sheetObject.appendRow([TextCellValue('3 derniers élèves')]);
    final List<Map<String, dynamic>> bottom3 = stats['bottom_3_students'];
    for (var s in bottom3) {
      final Student student = s['student'] as Student;
      sheetObject.appendRow([
        TextCellValue(_displayStudentName(student)),
        DoubleCellValue(s['average']),
      ]);
    }

    // Save file
    final path = '$directory/statistiques_${widget.className}.xlsx';
    final file = File(path);
    await file.writeAsBytes(excel.encode()!);

    OpenFile.open(path);
  }

  Future<void> _exportToPdf() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return; // User canceled the picker

    final pdf = pw.Document();
    final regularData = await rootBundle.load(
      'assets/fonts/nunito/Nunito-Regular.ttf',
    );
    final boldData = await rootBundle.load(
      'assets/fonts/nunito/Nunito-Bold.ttf',
    );
    final symbolsData = await rootBundle.load(
      'assets/fonts/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf',
    );
    final times = pw.Font.ttf(regularData);
    final timesBold = pw.Font.ttf(boldData);
    final symbolsFont = pw.Font.ttf(symbolsData);
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: times, bold: timesBold),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: light,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (schoolInfo.logoPath != null &&
                      File(schoolInfo.logoPath!).existsSync())
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(
                        pw.MemoryImage(
                          File(schoolInfo.logoPath!).readAsBytesSync(),
                        ),
                        width: 50,
                        height: 50,
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo.name,
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 18,
                            color: accent,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          schoolInfo.address,
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 10,
                            color: primary,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Année académique: ${widget.academicYear}  •  Généré le: ' +
                              DateFormat(
                                'dd/MM/yyyy HH:mm',
                              ).format(DateTime.now()),
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 10,
                            color: primary,
                            fontFallback: [symbolsFont],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Title
            pw.Text(
              'Rapport de Statistiques - ${widget.className}',
              style: pw.TextStyle(
                font: timesBold,
                fontSize: 20,
                color: accent,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),

            // Global KPI
            pw.Row(
              children: [
                pw.Text(
                  'Taux de réussite global: ',
                  style: pw.TextStyle(font: timesBold, fontSize: 12),
                ),
                pw.Text(
                  '${(stats['global_success_rate'] as double).toStringAsFixed(1)}%',
                  style: pw.TextStyle(
                    font: timesBold,
                    fontSize: 12,
                    color: accent,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Ranking
            pw.Text(
              'Classement par mérite',
              style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent),
            ),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(
                font: timesBold,
                fontWeight: pw.FontWeight.bold,
                fontFallback: [symbolsFont],
              ),
              cellStyle: pw.TextStyle(font: times, fontFallback: [symbolsFont]),
              headerDecoration: pw.BoxDecoration(color: light),
              headers: ['Rang', 'Élève', 'Moyenne', 'Ex æquo'],
              data: (stats['merit_ranking'] as List<Map<String, dynamic>>)
                  .map(
                    (e) => [
                      (e['rank'] ?? '').toString(),
                      _displayStudentName(e['student'] as Student),
                      (e['average'] as double).toStringAsFixed(2),
                      ((e['exaequo'] as bool?) ?? false) ? 'Oui' : 'Non',
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 16),

            // Subject Stats
            pw.Text(
              'Statistiques par matière',
              style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent),
            ),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(
                font: timesBold,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: pw.BoxDecoration(color: light),
              headers: ['Matière', 'Taux de réussite', 'Moyenne de classe'],
              data: widget.subjects
                  .map(
                    (s) => [
                      s.name,
                      '${stats['success_rate_by_subject'][s.name]?.toStringAsFixed(2) ?? 'N/A'}%',
                      stats['class_average_by_subject'][s.name]
                              ?.toStringAsFixed(2) ??
                          'N/A',
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 16),

            pw.Text(
              'Répartition des notes',
              style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Excellent (>= 19): ${stats['excellent_students']}'),
            pw.Text('Très Bien (16-19): ${stats['tres_bien_students']}'),
            pw.Text('Bien (14-16): ${stats['bien_students']}'),
            pw.Text('Assez Bien (12-14): ${stats['assez_bien_students']}'),
            pw.Text('Passable (10-12): ${stats['passable_students']}'),
            pw.Text('Insuffisant (< 10): ${stats['insuffisant_students']}'),
            pw.Table.fromTextArray(
              headerDecoration: pw.BoxDecoration(color: light),
              headers: ['Tranche', 'Nombre d\'élèves'],
              data: [
                ['Excellent (>= 19)', stats['excellent_students'].toString()],
                ['Très Bien (16-19)', stats['tres_bien_students'].toString()],
                ['Bien (14-16)', stats['bien_students'].toString()],
                ['Assez Bien (12-14)', stats['assez_bien_students'].toString()],
                ['Passable (10-12)', stats['passable_students'].toString()],
                [
                  'Insuffisant (< 10)',
                  stats['insuffisant_students'].toString(),
                ],
              ],
            ),
            pw.SizedBox(height: 16),

            // Breakdowns
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Réussite par Genre',
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 12,
                          color: accent,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Table.fromTextArray(
                        headerDecoration: pw.BoxDecoration(color: light),
                        headers: ['Genre', 'Eff.', 'Réussite'],
                        data:
                            (stats['gender_breakdown'] as Map<String, dynamic>)
                                .entries
                                .map((e) {
                                  final success = (e.value['success'] as num)
                                      .toDouble();
                                  final total = (e.value['total'] as num)
                                      .toDouble();
                                  final rate = total > 0
                                      ? (success / total) * 100
                                      : 0.0;
                                  return [
                                    e.key,
                                    e.value['total'].toString(),
                                    '${rate.toStringAsFixed(1)}%',
                                  ];
                                })
                                .toList(),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Réussite par Statut',
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 12,
                          color: accent,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Table.fromTextArray(
                        headerDecoration: pw.BoxDecoration(color: light),
                        headers: ['Statut', 'Eff.', 'Réussite'],
                        data:
                            (stats['status_breakdown'] as Map<String, dynamic>)
                                .entries
                                .map((e) {
                                  final success = (e.value['success'] as num)
                                      .toDouble();
                                  final total = (e.value['total'] as num)
                                      .toDouble();
                                  final rate = total > 0
                                      ? (success / total) * 100
                                      : 0.0;
                                  return [
                                    e.key,
                                    e.value['total'].toString(),
                                    '${rate.toStringAsFixed(1)}%',
                                  ];
                                })
                                .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Top/Bottom 3
            pw.Text(
              'Top 3 des élèves',
              style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent),
            ),
            ...(stats['top_3_students'] as List<Map<String, dynamic>>).map(
              (s) => pw.Text(
                '${_displayStudentName(s['student'] as Student)}: ${s['average'].toStringAsFixed(2)}',
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              '3 derniers élèves',
              style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent),
            ),
            ...(stats['bottom_3_students'] as List<Map<String, dynamic>>).map(
              (s) => pw.Text(
                '${_displayStudentName(s['student'] as Student)}: ${s['average'].toStringAsFixed(2)}',
              ),
            ),
          ];
        },
      ),
    );

    final path = '$directory/statistiques_${widget.className}.pdf';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    OpenFile.open(path);
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16.0),
      child: Divider(height: 1, color: Colors.grey),
    );
  }

  Widget _buildRankingSection() {
    final List<Map<String, dynamic>> ranking = stats['merit_ranking'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.emoji_events, color: Colors.amber),
            SizedBox(width: 8),
            Text(
              "Classement par mérite",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DataTable(
          columns: const [
            DataColumn(label: Text("Rang")),
            DataColumn(label: Text("Élève")),
            DataColumn(label: Text("Moyenne")),
          ],
          rows: ranking.map((entry) {
            int rank = (entry['rank'] as int?) ?? 0;
            bool ex = (entry['exaequo'] as bool?) ?? false;
            Student student = entry['student'];
            double average = entry['average'];
            return DataRow(
              cells: [
                DataCell(Text(ex ? '$rank (ex æquo)' : rank.toString())),
                DataCell(Text(_displayStudentName(student))),
                DataCell(Text(average.toStringAsFixed(2))),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubjectStatsSection() {
    final Map<String, double> successRate = stats['success_rate_by_subject'];
    final Map<String, double> classAverage = stats['class_average_by_subject'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.subject, color: Colors.blue),
            SizedBox(width: 8),
            Text(
              "Statistiques par matière",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DataTable(
          columns: const [
            DataColumn(label: Text("Matière")),
            DataColumn(label: Text("Taux de réussite")),
            DataColumn(label: Text("Moyenne de classe")),
          ],
          rows: widget.subjects.map((subject) {
            return DataRow(
              cells: [
                DataCell(Text(subject.name)),
                DataCell(
                  Text(
                    "${successRate[subject.name]?.toStringAsFixed(2) ?? 'N/A'}%",
                  ),
                ),
                DataCell(
                  Text(classAverage[subject.name]?.toStringAsFixed(2) ?? 'N/A'),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGradeDistributionSection() {
    // Let's use the stats as they are calculated in _loadStats:
    final int total = stats['student_count'] ?? 0;
    if (total == 0) return const SizedBox.shrink();

    // Re-calculating counts for the 6-bin format if necessary, or just using the 5 bins.
    // Actually, in StatisticsModal._loadStats, I have:
    // excellent (>= 19), bien (15 -16), assez bien (12-14), passable (10-12), insuffisant (< 10).
    // To match GradesPage's labels exactly, I might need to split 'insuffisant'.
    // But since this is a summary from averages, let's keep it consistent with what's already there or slightly adapt.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.pie_chart, color: Colors.green),
            Icon(Icons.bar_chart, color: Colors.green),
            SizedBox(width: 8),
            Text(
              "Répartition des notes",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildStatCard(
          "Excellent (>= 19)",
          stats['excellent_students'].toString(),
          Icons.star,
          color: Colors.amber,
        ),
        _buildStatCard(
          "Très Bien (16-18)",
          stats['tres_bien_students'].toString(),
          Icons.star,
          color: Colors.amber,
        ),
        _buildStatCard(
          "Bien (14-16)",
          stats['bien_students'].toString(),
          Icons.thumb_up,
          color: Colors.lightGreen,
        ),
        _buildStatCard(
          "Assez Bien (12-14)",
          stats['assez_bien_students'].toString(),
          Icons.check_circle,
          color: Colors.blue,
        ),
        _buildStatCard(
          "Passable (10-12)",
          stats['passable_students'].toString(),
          Icons.check,
          color: Colors.orange,
        ),
        _buildStatCard(
          "Insuffisant (< 10)",
          stats['insuffisant_students'].toString(),
          Icons.warning,
          color: Colors.red,
        ),
        const SizedBox(height: 20),
        Container(
          height: 180,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(
                context,
                "Exc.",
                stats['excellent_students'],
                total,
                Colors.purple,
              ),
              _buildBar(
                context,
                "T.Bien",
                stats['tres_bien_students'],
                total,
                Colors.teal,
              ),
              _buildBar(
                context,
                "Bien",
                stats['bien_students'],
                total,
                Colors.green,
              ),
              _buildBar(
                context,
                "A.Bien",
                stats['assez_bien_students'],
                total,
                Colors.lightGreen,
              ),
              _buildBar(
                context,
                "Pass.",
                stats['passable_students'],
                total,
                Colors.orange,
              ),
              _buildBar(
                context,
                "Ins.",
                stats['insuffisant_students'],
                total,
                Colors.red,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBar(
    BuildContext context,
    String label,
    int count,
    int total,
    Color color,
  ) {
    final double ratio = total > 0 ? count / total : 0.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 30,
          height: (ratio * 120).clamp(2.0, 120.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [color, color.withOpacity(0.6)],
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildTopBottomStudentsSection() {
    final List<Map<String, dynamic>> top3 = stats['top_3_students'];
    final List<Map<String, dynamic>> bottom3 = stats['bottom_3_students'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.arrow_upward, color: Colors.green),
            SizedBox(width: 8),
            Text(
              "Top 3 des élèves",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        ...top3.map(
          (s) => Text(
            "${_displayStudentName(s['student'] as Student)}: ${s['average'].toStringAsFixed(2)}",
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: const [
            Icon(Icons.arrow_downward, color: Colors.red),
            SizedBox(width: 8),
            Text(
              "3 derniers élèves",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        ...bottom3.map(
          (s) => Text(
            "${_displayStudentName(s['student'] as Student)}: ${s['average'].toStringAsFixed(2)}",
          ),
        ),
      ],
    );
  }

  Widget _buildClassAverageBarChart() {
    final Map<String, double> classAverage = stats['class_average_by_subject'];
    if (classAverage.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.legend_toggle, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text(
              "Moyennes de Classe par Matière",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.start,
            children: widget.subjects.map((subject) {
              final avg = classAverage[subject.name] ?? 0.0;
              final color = avg >= 10 ? Colors.blueAccent : Colors.orangeAccent;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      avg.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 24,
                      height: (avg / 20 * 120).clamp(2.0, 120.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [color, color.withOpacity(0.6)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.15),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 50,
                      child: Text(
                        subject.name.length > 8
                            ? '${subject.name.substring(0, 6)}..'
                            : subject.name,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildModernBreakdownSection({
    required String title,
    required IconData icon,
    required Map<String, Map<String, int>> data,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...data.entries.map((e) {
          final label = e.key;
          final success = e.value['success'] ?? 0;
          final total = e.value['total'] ?? 1;
          final rate = (success / total) * 100;
          final statusColor = rate >= 50 ? Colors.green : Colors.red;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${rate.toStringAsFixed(1)}% ($success/$total)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: rate / 100,
                    minHeight: 8,
                    backgroundColor: statusColor.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon, {
    Color color = Colors.blue,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
