import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:school_manager/models/category.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/signature.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/services/signature_pdf_service.dart';

class ReportCardUltraCompactPdfService {
  /// Vérifie si l'action est autorisée (non bloquée par le mode coffre fort)
  static void _checkSafeMode() {
    if (!SafeModeService.instance.isActionAllowed()) {
      throw Exception(SafeModeService.instance.getBlockedActionMessage());
    }
  }

  /// Normalise un champ texte pour l'affichage PDF (évite les cellules "vides").
  static String dashIfBlank(String? value, {String placeholder = '-'}) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? placeholder : v;
  }

  /// Affiche uniquement le nom (dernier token) d'un professeur.
  static String teacherSurname(String? value, {String placeholder = '-'}) {
    final v = (value ?? '').replaceAll(',', ' ').trim();
    if (v.isEmpty) return placeholder;
    final parts = v.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return placeholder;
    return parts.last;
  }

  /// Calcule une moyenne sur 20 pondérée par `Grade.coefficient`.
  ///
  /// Formule appliquée sur chaque note : `((value / maxValue) * 20) * coefficient`.
  /// Les notes avec `maxValue <= 0` ou `coefficient <= 0` sont ignorées.
  static double computeWeightedAverageOn20(List<Grade> grades) {
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

  /// Helper method pour formater les dates
  static String _formatDate(String dateString) {
    if (dateString.isEmpty) return 'Non renseigné';

    try {
      // Essayer de parser la date dans différents formats
      DateTime? date;

      // Format ISO (2024-01-15)
      if (dateString.contains('-') && dateString.length >= 10) {
        date = DateTime.tryParse(dateString);
      }
      // Format français (15/01/2024)
      else if (dateString.contains('/')) {
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
        return DateFormat('dd/MM/yyyy').format(date);
      }
    } catch (_) {}

    return dateString;
  }

  static String _resolveDirectorForLevel(SchoolInfo schoolInfo, String niveau) {
    final n = niveau.trim().toLowerCase();
    String? candidate;
    if (n.contains('primaire') || n.contains('maternelle')) {
      candidate = schoolInfo.directorPrimary;
    } else if (n.contains('coll')) {
      candidate = schoolInfo.directorCollege;
    } else if (n.contains('lyc')) {
      candidate = schoolInfo.directorLycee;
    } else if (n.contains('univ')) {
      candidate = schoolInfo.directorUniversity;
    }
    final resolved = candidate?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return schoolInfo.director.trim();
  }

  static String _resolveAdminRoleForLevel(
    SchoolInfo schoolInfo,
    String niveau,
  ) {
    final bool isComplexe =
        (schoolInfo.directorPrimary?.trim().isNotEmpty ?? false) ||
        (schoolInfo.directorCollege?.trim().isNotEmpty ?? false) ||
        (schoolInfo.directorLycee?.trim().isNotEmpty ?? false) ||
        (schoolInfo.directorUniversity?.trim().isNotEmpty ?? false);
    final n = niveau.trim().toLowerCase();
    if (isComplexe) {
      if (n.contains('primaire') || n.contains('maternelle')) {
        return 'directeur_primaire';
      }
      if (n.contains('coll')) return 'directeur_college';
      if (n.contains('lyc')) return 'directeur_lycee';
      if (n.contains('univ')) return 'directeur_universite';
    }
    return n.contains('lyc') ? 'proviseur' : 'directeur';
  }

  static String _autoConduiteText({
    required int attendanceInjustifiee,
    required int retards,
    required String sanctions,
  }) {
    if (sanctions.trim().isNotEmpty) return 'À améliorer';
    if (attendanceInjustifiee > 0 || retards > 0) return 'Passable';
    return 'Très bonne conduite';
  }

  static String _autoHonneurText(double average) {
    return average >= 16.0 ? 'OUI' : 'NON';
  }

  static String _autoEncouragementText(double average) {
    if (average >= 14.0 && average < 16.0) return 'OUI';
    return 'NON';
  }

  static String _autoAppreciationGeneraleText(double average) {
    if (average >= 19.0) return 'Excellent travail';
    if (average >= 16.0) return 'Très bien';
    if (average >= 14.0) return 'Bien';
    if (average >= 12.0) return 'Assez Bien';
    if (average >= 10.0) return 'Passable';
    return 'Insuffisant';
  }

  /// Génère un PDF ultra compact du bulletin scolaire d'un élève
  static Future<List<int>> generateReportCardPdfUltraCompact({
    required Student student,
    required SchoolInfo schoolInfo,
    required List<Grade> grades,
    required Map<String, String> professeurs,
    required Map<String, String> appreciations,
    required Map<String, String> moyennesClasse,
    required String appreciationGenerale,
    required String decision,
    String recommandations = '',
    String forces = '',
    String pointsADevelopper = '',
    String sanctions = '',
    int attendanceJustifiee = 0,
    int attendanceInjustifiee = 0,
    int retards = 0,
    double presencePercent = 0.0,
    String conduite = '',
    required String telEtab,
    required String mailEtab,
    required String webEtab,
    String titulaire = '',
    required List<String> subjects,
    required List<double?> moyennesParPeriode,
    required double moyenneGenerale,
    required int rang,
    required int nbEleves,
    bool exaequo = false,
    required String mention,
    required List<String> allTerms,
    required String periodLabel,
    required String selectedTerm,
    required String academicYear,
    required String faitA,
    required String leDate,
    required bool isLandscape,
    String niveau = '',
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    double? moyenneAnnuelle,
    bool duplicata = false,
    String footerNote = '',
    String adminCivility = 'M.',
  }) async {
    _checkSafeMode(); // Vérifier le mode coffre fort
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final secondaryColor = PdfColors.blueGrey800;
    final mainColor = PdfColors.blue800;
    final tableHeaderBg = PdfColors.blue200;
    final tableHeaderText = PdfColors.white;
    final tableRowAlt = PdfColors.blue50;
    final resolvedFooterNote = footerNote.trim();
    final resolvedCivility = adminCivility.trim().isNotEmpty
        ? adminCivility.trim()
        : 'M.';
    final resolvedAverage = (moyenneAnnuelle != null && moyenneAnnuelle > 0.0)
        ? moyenneAnnuelle
        : moyenneGenerale;
    final autoConduite = _autoConduiteText(
      attendanceInjustifiee: attendanceInjustifiee,
      retards: retards,
      sanctions: sanctions,
    );
    final resolvedAppreciationGenerale = appreciationGenerale.trim().isNotEmpty
        ? appreciationGenerale
        : _autoAppreciationGeneraleText(resolvedAverage);
    final resolvedConduite = recommandations.trim().isNotEmpty
        ? recommandations
        : autoConduite;
    final resolvedHonneur = forces.trim().isNotEmpty
        ? forces
        : _autoHonneurText(resolvedAverage);
    final resolvedEncouragement = pointsADevelopper.trim().isNotEmpty
        ? pointsADevelopper
        : _autoEncouragementText(resolvedAverage);
    final resolvedAssiduiteConduite = conduite.trim().isNotEmpty
        ? conduite
        : '';
    final directorName = _resolveDirectorForLevel(schoolInfo, niveau);
    final directorDisplay = directorName.isNotEmpty
        ? '$resolvedCivility $directorName'
        : '';
    // Charger catégories et matières de la classe pour permettre un groupement par catégories
    final DatabaseService _db = DatabaseService();
    final List<Category> _pdfCategories = await _db.getCategories();
    final List<Course> _pdfClassCourses = await _db.getCoursesForClass(
      student.className,
      academicYear,
    );
    final List<Grade> classPeriodGrades = await _db.getAllGradesForPeriod(
      className: student.className,
      academicYear: academicYear,
      term: selectedTerm,
    );

    // Récupérer la liste officielle des élèves de la classe pour filtrer les calculs
    final List<Student> currentClassStudents = await _db
        .getStudentsByClassAndClassYear(student.className, academicYear);
    final Set<String> classStudentIds = currentClassStudents
        .map((s) => s.id)
        .toSet();
    // Charger coefficients de matière au niveau de la classe; fallback sur appreciations (archive incluse)
    Map<String, double> subjectWeights = await _db.getClassSubjectCoefficients(
      student.className,
      academicYear,
    );
    if (subjectWeights.isEmpty) {
      List<Map<String, dynamic>> subjAppsRows = await _db
          .getSubjectAppreciations(
            studentId: student.id,
            className: student.className,
            academicYear: academicYear,
            term: selectedTerm,
          );
      if (subjAppsRows.isEmpty) {
        subjAppsRows = await _db.getSubjectAppreciationsArchiveByKeys(
          studentId: student.id,
          className: student.className,
          academicYear: academicYear,
          term: selectedTerm,
        );
      }
      subjectWeights = {
        for (final r in subjAppsRows)
          if ((r['subject'] as String?) != null && r['coefficient'] != null)
            (r['subject'] as String): (r['coefficient'] as num).toDouble(),
      };
    }
    // Pré-calcul du rang/eff. par période pour le tableau des moyennes par période
    final Map<String, Map<String, int>> rankPerTerm = {};
    final Map<String, double> nAnnualByStudent = {};
    final Map<String, double> cAnnualByStudent = {};
    const double epsRank = 0.001;
    for (final term in allTerms) {
      final gradesForTerm = await _db.getAllGradesForPeriod(
        className: student.className,
        academicYear: academicYear,
        term: term,
      );
      // Accumulate annual (inchangé)
      for (final g in gradesForTerm.where(
        (g) =>
            classStudentIds.contains(g.studentId) &&
            (g.type == 'Devoir' || g.type == 'Composition') &&
            g.value != null,
      )) {
        if (g.maxValue > 0 && g.coefficient > 0) {
          nAnnualByStudent[g.studentId] =
              (nAnnualByStudent[g.studentId] ?? 0) +
              ((g.value / g.maxValue) * 20) * g.coefficient;
          cAnnualByStudent[g.studentId] =
              (cAnnualByStudent[g.studentId] ?? 0) + g.coefficient;
        }
      }
      // Classement pondéré par coefficients de matières
      final List<double> avgs = [];
      double myAvg = 0.0;
      for (final sid in classStudentIds) {
        double sumPoints = 0.0;
        double sumWeights = 0.0;
        for (final subject in subjects) {
          final sg = gradesForTerm
              .where(
                (g) =>
                    g.studentId == sid &&
                    g.subject == subject &&
                    (g.type == 'Devoir' || g.type == 'Composition') &&
                    g.value != null,
              )
              .toList();
          if (sg.isEmpty) continue;
          double n = 0.0;
          double c = 0.0;
          for (final g in sg) {
            if (g.maxValue > 0 && g.coefficient > 0) {
              n += ((g.value / g.maxValue) * 20) * g.coefficient;
              c += g.coefficient;
            }
          }
          final double moyMatiere = c > 0 ? (n / c) : 0.0;
          final double w =
              subjectWeights[subject] ?? c; // fallback si non défini
          if (w > 0) {
            sumPoints += moyMatiere * w;
            sumWeights += w;
          }
        }
        final double avg = sumWeights > 0 ? (sumPoints / sumWeights) : 0.0;
        avgs.add(avg);
        if (sid == student.id) myAvg = avg;
      }
      avgs.sort((a, b) => b.compareTo(a));
      final int nb = avgs.length;
      final int rank = 1 + avgs.where((v) => (v - myAvg) > epsRank).length;
      rankPerTerm[term] = {'rank': rank, 'nb': nb};
    }
    // Annual class average and rank for student
    double? moyenneAnnuelleClasseComputed;
    int? rangAnnuelComputed;
    if (nAnnualByStudent.isNotEmpty) {
      final List<double> annualAvgs = [];
      double myAnnual = 0.0;
      nAnnualByStudent.forEach((sid, n) {
        final c = cAnnualByStudent[sid] ?? 0.0;
        final avg = c > 0 ? (n / c) : 0.0;
        annualAvgs.add(avg);
        if (sid == student.id) myAnnual = avg;
      });
      if (annualAvgs.isNotEmpty) {
        moyenneAnnuelleClasseComputed =
            annualAvgs.reduce((a, b) => a + b) / annualAvgs.length;
        annualAvgs.sort((a, b) => b.compareTo(a));
        rangAnnuelComputed =
            1 + annualAvgs.where((v) => (v - myAnnual) > epsRank).length;
      }
    }
    final now = DateTime.now();
    final prenom = student.firstName;
    final nom = student.lastName;
    final sexe = student.gender;
    // Pré-charger les signatures/images pour ce bulletin
    final signaturePdfService = SignaturePdfService();
    final String adminRole = _resolveAdminRoleForLevel(schoolInfo, niveau);
    final Map<String, Signature?> _bulletinSignatures =
        await signaturePdfService.getSignaturesForBulletin(
          className: student.className,
          titulaire: titulaire,
          adminRole: adminRole,
        );
    // ---
    final PdfPageFormat _pageFormat = isLandscape
        ? PdfPageFormat(842, 595)
        : PdfPageFormat(595.28, 1000);
    final pw.PageTheme _pageTheme = pw.PageTheme(
      pageFormat: _pageFormat,
      // Réduit les marges pour gagner de l'espace vertical et éviter une 2e page
      margin: isLandscape
          ? const pw.EdgeInsets.all(8)
          : const pw.EdgeInsets.all(10),
      buildBackground:
          (schoolInfo.logoPath != null &&
              File(schoolInfo.logoPath!).existsSync())
          ? (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Opacity(
                opacity: 0.05,
                child: pw.Image(
                  pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                  fit: pw.BoxFit.cover,
                ),
              ),
            )
          : null,
    );
    final int totalSubjects = subjects.length;
    final bool denseModeFooter = totalSubjects > (isLandscape ? 10 : 8);
    final double footerFont = denseModeFooter
        ? (isLandscape ? 4.4 : 4.8)
        : (isLandscape ? 5.0 : 5.4);
    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme,
        footer: (context) {
          if (resolvedFooterNote.isEmpty) return pw.SizedBox();
          return pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Center(
              child: pw.Text(
                resolvedFooterNote,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: timesBold,
                  fontSize: footerFont,
                  color: secondaryColor,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
          );
        },
        build: (pw.Context context) {
          final int totalSubjects = subjects.length;
          final bool denseMode = totalSubjects > (isLandscape ? 10 : 8);
          final double smallFont = denseMode
              ? (isLandscape ? 4.4 : 4.8)
              : (isLandscape ? 5.0 : 5.4);
          final double baseFont = smallFont;
          final double headerFont = denseMode
              ? (isLandscape ? 7.6 : 8.6)
              : (isLandscape ? 8.6 : 11.0);
          final double spacing = denseMode
              ? (isLandscape ? 1.5 : 2)
              : (isLandscape ? 2.5 : 3.5);
          // Dimensions compactes pour les signatures/cachets afin d'éviter un saut de page
          final double sigImgHeight = isLandscape
              ? (denseMode ? 14 : 18)
              : (denseMode ? 12 : 16);
          final double sigImgWidth = 90;
          final double cachetHeight = isLandscape
              ? (denseMode ? 18 : 20)
              : (denseMode ? 16 : 18);
          final double cachetWidth = 90;
          final double lineFont = math.max(
            4.0,
            baseFont - (denseMode ? 1.5 : 1.0),
          );
          String _toOrdinalWord(int n) {
            switch (n) {
              case 1:
                return 'premier';
              case 2:
                return 'deuxième';
              case 3:
                return 'troisième';
              case 4:
                return 'quatrième';
              case 5:
                return 'cinquième';
              default:
                return '$nᵉ';
            }
          }

          String _buildBulletinSubtitle() {
            final String base = 'Bulletin du ';
            final String period = periodLabel.toLowerCase();
            final match = RegExp(r"(\d+)").firstMatch(selectedTerm);
            if (match != null) {
              final numStr = match.group(1);
              final idx = int.tryParse(numStr ?? '');
              if (idx != null) {
                return base + _toOrdinalWord(idx) + ' ' + period;
              }
            }
            if (selectedTerm.isNotEmpty) {
              return base + period + ' ' + selectedTerm.toLowerCase();
            }
            return base + period;
          }

          // Découpe un texte en 2 lignes équilibrées et en majuscules
          List<String> _splitTwoLines(String input) {
            final s = input.trim().toUpperCase();
            if (s.isEmpty) return [];
            final words = s.split(RegExp(r'\s+'));
            if (words.length <= 1) return [s];
            final totalLen = s.length;
            final target = totalLen ~/ 2;
            int bestIdx = 1;
            int bestDist = totalLen;
            int running = 0;
            for (int i = 0; i < words.length - 1; i++) {
              running += words[i].length + 1; // +space
              final dist = (running - target).abs();
              if (dist < bestDist) {
                bestDist = dist;
                bestIdx = i + 1;
              }
            }
            final first = words.sublist(0, bestIdx).join(' ');
            final second = words.sublist(bestIdx).join(' ');
            return [first, second];
          }

          final String bulletinSubtitle = _buildBulletinSubtitle();
          double _estimateTextWidth(String text, double fontSize) {
            if (text.isEmpty) return 0;
            // Approximate average glyph width factor for Times (safety tuned)
            return text.length * fontSize * 0.62;
          }

          return <pw.Widget>[
            // En-tête État: Ministère (gauche) / République + devise (droite)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 2,
                      child: (schoolInfo.ministry ?? '').isNotEmpty
                          ? () {
                              final parts = _splitTwoLines(
                                schoolInfo.ministry ?? '',
                              );
                              if (parts.isEmpty) return pw.SizedBox();
                              final hasTwo = parts.length > 1;
                              // Taille de police de base
                              final baseFs = smallFont + 1;
                              // Largeur dispo approximative pour la colonne gauche
                              final margin = isLandscape ? 12.0 : 20.0;
                              final contentWidth =
                                  _pageFormat.width - 2 * margin;
                              // Calculer la largeur réellement allouée à la colonne gauche
                              // Les Expanded du header utilisent les flex: gauche=2, centre=3, droite=2
                              // On calcule la part = 2 / (2+3+2) = 2/7 pour que la largeur utilisée
                              // corresponde exactement à l'espace rendu et évite la troncation.
                              const double leftFlex = 2;
                              const double centerFlex = 3;
                              const double rightFlex = 2;
                              final double totalFlex =
                                  leftFlex + centerFlex + rightFlex;
                              final leftColWidth =
                                  contentWidth * (leftFlex / totalFlex);
                              // Ajuste la taille si nécessaire pour forcer 2 lignes sans wrap
                              double fs = baseFs;
                              double w1Base = _estimateTextWidth(parts[0], fs);
                              double w2Base = hasTwo
                                  ? _estimateTextWidth(parts[1], fs)
                                  : 0.0;
                              double maxBase = hasTwo
                                  ? math.max(w1Base, w2Base)
                                  : w1Base;
                              if (maxBase > leftColWidth) {
                                final scale = leftColWidth / maxBase;
                                fs = (fs * scale).clamp(5.0, baseFs);
                                w1Base = _estimateTextWidth(parts[0], fs);
                                w2Base = hasTwo
                                    ? _estimateTextWidth(parts[1], fs)
                                    : 0.0;
                                maxBase = hasTwo
                                    ? math.max(w1Base, w2Base)
                                    : w1Base;
                              }
                              // Padding pour centrer la ligne la plus courte dans la largeur disponible
                              // On utilise explicitement leftColWidth (espace réel alloué) pour éviter
                              // que la seconde ligne soit tronquée : le container occupera toute la
                              // largeur disponible et le padding centre le texte à l'intérieur.
                              final availableW = leftColWidth;
                              double padFirst = 0;
                              double padSecond = 0;
                              if (hasTwo) {
                                if (w2Base > w1Base) {
                                  padFirst = (availableW - w1Base) / 2;
                                  padSecond = 0;
                                } else if (w1Base > w2Base) {
                                  padFirst = 0;
                                  padSecond = (availableW - w2Base) / 2;
                                }
                              }
                              return pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.Container(
                                    width: availableW,
                                    padding: pw.EdgeInsets.only(left: padFirst),
                                    child: pw.Text(
                                      parts[0],
                                      maxLines: 1,
                                      style: pw.TextStyle(
                                        font: timesBold,
                                        fontSize: fs,
                                        color: mainColor,
                                      ),
                                    ),
                                  ),
                                  if (hasTwo)
                                    pw.Container(
                                      width: availableW,
                                      padding: pw.EdgeInsets.only(
                                        left: padSecond,
                                      ),
                                      child: pw.Text(
                                        parts[1],
                                        maxLines: 1,
                                        style: pw.TextStyle(
                                          font: timesBold,
                                          fontSize: fs,
                                          color: mainColor,
                                        ),
                                      ),
                                    ),
                                  if ((schoolInfo.inspection ?? '')
                                      .isNotEmpty) ...[
                                    pw.SizedBox(height: isLandscape ? 3 : 6),
                                    pw.Text(
                                      'Inspection: ${schoolInfo.inspection}',
                                      style: pw.TextStyle(
                                        font: times,
                                        fontSize: smallFont + 1,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  ],
                                  // Photo élève en dessous de l'Inspection (si dispo)
                                  if (student.photoPath != null &&
                                      student.photoPath!.isNotEmpty &&
                                      File(
                                        student.photoPath!,
                                      ).existsSync()) ...[
                                    pw.SizedBox(height: 4),
                                    pw.Container(
                                      width: isLandscape ? 40 : 80,
                                      height: isLandscape ? 40 : 80,
                                      decoration: pw.BoxDecoration(
                                        borderRadius: pw.BorderRadius.circular(
                                          8,
                                        ),
                                        border: pw.Border.all(
                                          color: PdfColors.blue100,
                                          width: 1,
                                        ),
                                      ),
                                      child: pw.ClipRRect(
                                        child: pw.Image(
                                          pw.MemoryImage(
                                            File(
                                              student.photoPath!,
                                            ).readAsBytesSync(),
                                          ),
                                          fit: pw.BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            }()
                          : pw.SizedBox(),
                    ),
                    // Bloc central: logo + infos établissement
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          if (schoolInfo.logoPath != null &&
                              File(schoolInfo.logoPath!).existsSync())
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 2),
                              child: pw.Image(
                                pw.MemoryImage(
                                  File(schoolInfo.logoPath!).readAsBytesSync(),
                                ),
                                height: isLandscape ? 22 : 56,
                              ),
                            ),
                          pw.Text(
                            schoolInfo.name,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: headerFont,
                              color: mainColor,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: isLandscape ? 1 : 2),
                          pw.SizedBox(height: 1),
                          // Année académique déplacée sous "Direction de l'enseignement" (colonne droite)
                          if (schoolInfo.director.isNotEmpty) ...[
                            // Masqué: affichage du proviseur / directeur (gardé en commentaire pour restauration ultérieure)
                            // pw.SizedBox(height: 1),
                            // pw.Text(
                            //   (niveau.toLowerCase().contains('lycée') ? 'Proviseur(e) : ' : 'Directeur(ice) : ') + schoolInfo.director,
                            //   textAlign: pw.TextAlign.center,
                            //   style: pw.TextStyle(font: times, fontSize: smallFont, color: secondaryColor),
                            // ),
                          ],
                          // Contacts condensés
                          if (mailEtab.isNotEmpty ||
                              webEtab.isNotEmpty ||
                              telEtab.isNotEmpty) ...[
                            pw.SizedBox(height: 1),
                            pw.Text(
                              [
                                if (mailEtab.isNotEmpty) 'Email: ' + mailEtab,
                                if (webEtab.isNotEmpty) 'Site: ' + webEtab,
                                if (telEtab.isNotEmpty) 'Tél: ' + telEtab,
                              ].join('  |  '),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                font: times,
                                fontSize: smallFont,
                                color: secondaryColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Colonne droite: République + devise
                    pw.Expanded(
                      flex: 2,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              ((schoolInfo.republic ?? 'RÉPUBLIQUE')
                                  .toUpperCase()),
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: smallFont + 1,
                                color: mainColor,
                              ),
                            ),
                            if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Text(
                                  schoolInfo.republicMotto!,
                                  style: pw.TextStyle(
                                    font: times,
                                    fontStyle: pw.FontStyle.italic,
                                    fontSize: smallFont,
                                    color: secondaryColor,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                            if ((schoolInfo.educationDirection ?? '')
                                .isNotEmpty)
                              pw.Padding(
                                padding: pw.EdgeInsets.only(
                                  top: isLandscape ? 3 : 6,
                                ),
                                child: pw.Text(
                                  "Direction de l'enseignement: ${schoolInfo.educationDirection}",
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: smallFont + 1,
                                    color: secondaryColor,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                            pw.Padding(
                              padding: pw.EdgeInsets.only(
                                top: isLandscape ? 6 : 10,
                              ),
                              child: pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.blue50,
                                  borderRadius: pw.BorderRadius.circular(6),
                                  border: pw.Border.all(
                                    color: PdfColors.blue200,
                                    width: 1,
                                  ),
                                ),
                                child: pw.Text(
                                  'Année académique : $academicYear',
                                  style: pw.TextStyle(
                                    font: timesBold,
                                    fontSize: smallFont + 1,
                                    color: mainColor,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // (Inspection / Direction déjà affichées sous Ministère / République)
              ],
            ),
            if (duplicata)
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.red, width: 1),
                    color: PdfColors.red50,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    'DUPLICATA',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 10,
                      color: PdfColors.red800,
                    ),
                  ),
                ),
              ),
            pw.SizedBox(height: isLandscape ? 2 : 6),
            // (photo élève supprimée ici; elle est affichée sous Inspection)
            // Titre + photo (photo à droite, sous l'entête)
            pw.Stack(
              children: [
                pw.Center(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'BULLETIN SCOLAIRE',
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: headerFont,
                          color: mainColor,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        bulletinSubtitle,
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: smallFont,
                          color: secondaryColor,
                        ),
                      ),
                      if ((schoolInfo.motto ?? '').isNotEmpty) ...[
                        pw.SizedBox(height: 6),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Divider(
                                color: PdfColors.blue100,
                                thickness: 1,
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: pw.Text(
                                schoolInfo.motto!,
                                style: pw.TextStyle(
                                  font: times,
                                  fontStyle: pw.FontStyle.italic,
                                  fontSize: smallFont,
                                  color: secondaryColor,
                                ),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Divider(
                                color: PdfColors.blue100,
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // photo non affichée ici (déjà collée à la ligne "Année académique")
              ],
            ),
            pw.SizedBox(height: spacing),
            // Bloc élève
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: PdfColors.blue100),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Divider(
                          color: PdfColors.blue100,
                          thickness: 1,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                        child: pw.Text(
                          'Identité de l\'élève',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: smallFont,
                            color: secondaryColor,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Divider(
                          color: PdfColors.blue100,
                          thickness: 1,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 2,
                        child: pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(
                              font: timesBold,
                              color: mainColor,
                              fontSize: smallFont,
                            ),
                            children: [
                              const pw.TextSpan(text: 'Matricule : '),
                              pw.TextSpan(
                                text: dashIfBlank(student.matricule),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  color: mainColor,
                                  fontSize: smallFont + 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(
                              font: timesBold,
                              color: mainColor,
                              fontSize: smallFont,
                            ),
                            children: [
                              const pw.TextSpan(text: 'Nom : '),
                              pw.TextSpan(
                                text: nom,
                                style: pw.TextStyle(
                                  font: timesBold,
                                  color: mainColor,
                                  fontSize: smallFont + 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(
                              font: timesBold,
                              color: mainColor,
                              fontSize: smallFont,
                            ),
                            children: [
                              const pw.TextSpan(text: 'Prénom(s) : '),
                              pw.TextSpan(
                                text: prenom,
                                style: pw.TextStyle(
                                  font: timesBold,
                                  color: mainColor,
                                  fontSize: smallFont + 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(
                              font: timesBold,
                              color: mainColor,
                              fontSize: smallFont,
                            ),
                            children: [
                              const pw.TextSpan(text: 'Sexe : '),
                              pw.TextSpan(
                                text: sexe,
                                style: pw.TextStyle(
                                  font: timesBold,
                                  color: mainColor,
                                  fontSize: smallFont + 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(
                              font: timesBold,
                              color: mainColor,
                              fontSize: smallFont,
                            ),
                            children: [
                              const pw.TextSpan(
                                text: 'Date et lieu de naissance : ',
                              ),
                              pw.TextSpan(
                                text:
                                    _formatDate(student.dateOfBirth) +
                                    (student.placeOfBirth != null &&
                                            student.placeOfBirth!
                                                .trim()
                                                .isNotEmpty
                                        ? ' à ${student.placeOfBirth!.trim()}'
                                        : ''),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  color: mainColor,
                                  fontSize: smallFont + 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(
                              font: timesBold,
                              color: mainColor,
                              fontSize: smallFont,
                            ),
                            children: [
                              const pw.TextSpan(text: 'Statut : '),
                              pw.TextSpan(
                                text: student.status.isNotEmpty
                                    ? student.status
                                    : '-',
                                style: pw.TextStyle(
                                  font: timesBold,
                                  color: mainColor,
                                  fontSize: smallFont + 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(child: pw.SizedBox()),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: PdfColors.blue100),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Row(
                      children: [
                        pw.Text(
                          'Classe : ',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: mainColor,
                          ),
                        ),
                        pw.Text(
                          student.className,
                          style: pw.TextStyle(
                            font: times,
                            color: secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Row(
                    children: [
                      pw.Text(
                        'Effectif : ',
                        style: pw.TextStyle(font: timesBold, color: mainColor),
                      ),
                      pw.Text(
                        nbEleves > 0 ? '$nbEleves' : '-',
                        style: pw.TextStyle(font: times, color: secondaryColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: spacing),
            // Tableau matières (groupé par catégories si disponibles)
            ...(() {
              // Map subject -> categoryId
              final Map<String, String?> subjectCat = {
                for (final c in _pdfClassCourses) c.name: c.categoryId,
              };
              // Regrouper à partir de la liste subjects passée
              final Map<String?, List<String>> grouped = {};
              for (final s in subjects) {
                final catId = subjectCat[s];
                grouped.putIfAbsent(catId, () => []).add(s);
              }
              final bool hasCategories = grouped.keys.any((k) => k != null);

              pw.Widget buildTableForSubjects(
                List<String> names, {
                bool showTotals = false,
                bool showHeader = true,
              }) {
                double sumCoefficients = 0.0;
                double sumPointsEleve = 0.0;
                double sumPointsClasse = 0.0;

                final List<pw.TableRow> rows = [];
                if (showHeader) {
                  rows.add(
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: tableHeaderBg),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Disciplines',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Sur',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Dev',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Comp',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Coef',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Moy.Gen',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Moy.Gen Cl.',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Moy.Cl',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Prof.',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Obs. Prof.',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: tableHeaderText,
                              fontSize: 9,
                            ),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                for (final subject in names) {
                  final subjectGrades = grades
                      .where((g) => g.subject == subject)
                      .toList();
                  final devoirs = subjectGrades
                      .where((g) => g.type == 'Devoir')
                      .toList();
                  final compositions = subjectGrades
                      .where((g) => g.type == 'Composition')
                      .toList();
                  final devoirAvgOn20 = devoirs.isNotEmpty
                      ? computeWeightedAverageOn20(devoirs)
                      : null;
                  final compoAvgOn20 = compositions.isNotEmpty
                      ? computeWeightedAverageOn20(compositions)
                      : null;
                  final devoirNote = devoirAvgOn20 != null
                      ? devoirAvgOn20.toStringAsFixed(2)
                      : '-';
                  final devoirSur = devoirAvgOn20 != null ? '20' : '-';
                  final compoNote = compoAvgOn20 != null
                      ? compoAvgOn20.toStringAsFixed(2)
                      : '-';
                  final compoSur = compoAvgOn20 != null ? '20' : '-';
                  final allGradesForSubject = [...devoirs, ...compositions];
                  final totalCoeff = allGradesForSubject
                      .where((g) => g.maxValue > 0 && g.coefficient > 0)
                      .fold<double>(0.0, (s, g) => s + g.coefficient);
                  final moyenneMatiere = computeWeightedAverageOn20(
                    allGradesForSubject,
                  );

                  final double subjectWeight =
                      subjectWeights[subject] ?? totalCoeff;
                  sumCoefficients += subjectWeight;
                  final double moyGenCoef = (subjectGrades.isNotEmpty)
                      ? (moyenneMatiere * subjectWeight)
                      : 0.0;
                  if (subjectGrades.isNotEmpty) sumPointsEleve += moyGenCoef;
                  final mcText = (moyennesClasse[subject] ?? '').replaceAll(
                    ',',
                    '.',
                  );
                  final mcVal = double.tryParse(mcText);
                  if (mcVal != null) sumPointsClasse += mcVal * subjectWeight;

                  rows.add(
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.white),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            subject,
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            devoirSur != '-' ? devoirSur : compoSur,
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            devoirNote,
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            compoNote,
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            (subjectWeights[subject] ?? totalCoeff) > 0
                                ? (subjectWeights[subject] ?? totalCoeff)
                                      .toStringAsFixed(2)
                                : '-',
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            subjectGrades.isNotEmpty
                                ? moyenneMatiere.toStringAsFixed(2)
                                : '-',
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            subjectGrades.isNotEmpty
                                ? moyGenCoef.toStringAsFixed(2)
                                : '-',
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            dashIfBlank(moyennesClasse[subject]),
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            teacherSurname(professeurs[subject]),
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            dashIfBlank(appreciations[subject]),
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Ligne de totaux (aucune contrainte stricte sur la somme des coefficients)
                if (showTotals) {
                  final bool sumOk = sumCoefficients > 0;
                  final PdfColor totalColor = sumOk
                      ? secondaryColor
                      : PdfColors.red;

                  rows.add(
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.blue50),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'TOTAUX',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: mainColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        pw.SizedBox(),
                        pw.SizedBox(),
                        pw.SizedBox(),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            sumCoefficients > 0
                                ? sumCoefficients.toStringAsFixed(2)
                                : '0',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: totalColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        pw.SizedBox(),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            sumPointsEleve > 0
                                ? sumPointsEleve.toStringAsFixed(2)
                                : '0',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: secondaryColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            sumPointsClasse > 0
                                ? sumPointsClasse.toStringAsFixed(2)
                                : '0',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: secondaryColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        pw.SizedBox(),
                        pw.SizedBox(),
                      ],
                    ),
                  );
                }

                return pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.blue100),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.3), // Matière
                    1: const pw.FlexColumnWidth(0.5), // Sur
                    2: const pw.FlexColumnWidth(0.5), // Dev
                    3: const pw.FlexColumnWidth(0.5), // Comp
                    4: const pw.FlexColumnWidth(0.5), // Coef
                    5: const pw.FlexColumnWidth(0.55), // Moy Gen
                    6: const pw.FlexColumnWidth(0.65), // Moy Gen Clas
                    7: const pw.FlexColumnWidth(0.6), // Moy Cl
                    8: const pw.FlexColumnWidth(1.3), // Professeur
                    9: const pw.FlexColumnWidth(1.7), // Appréciation
                  },
                  children: rows,
                );
              }

              pw.Widget buildGlobalTotals() {
                double sumCoefficients = 0.0;
                double sumPointsEleve = 0.0;
                double sumPointsClasse = 0.0;
                for (final subject in subjects) {
                  final subjectGrades = grades
                      .where((g) => g.subject == subject)
                      .toList();
                  final devoirs = subjectGrades
                      .where((g) => g.type == 'Devoir')
                      .toList();
                  final compositions = subjectGrades
                      .where((g) => g.type == 'Composition')
                      .toList();
                  final all = [...devoirs, ...compositions];
                  final moyenneMatiere = computeWeightedAverageOn20(all);
                  final totalCoeff = all
                      .where((g) => g.maxValue > 0 && g.coefficient > 0)
                      .fold<double>(0.0, (s, g) => s + g.coefficient);
                  final subjectWeight = subjectWeights[subject] ?? totalCoeff;
                  sumCoefficients += subjectWeight;
                  if (subjectGrades.isNotEmpty)
                    sumPointsEleve += moyenneMatiere * subjectWeight;
                  final mcText = (moyennesClasse[subject] ?? '').replaceAll(
                    ',',
                    '.',
                  );
                  final mcVal = double.tryParse(mcText);
                  if (mcVal != null) sumPointsClasse += mcVal * subjectWeight;
                }

                // Validation minimale: somme des coefficients doit être > 0
                final bool sumOk = sumCoefficients > 0;
                final PdfColor totalColor = sumOk
                    ? secondaryColor
                    : PdfColors.red;

                return pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.blue100),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.3),
                    1: const pw.FlexColumnWidth(0.6),
                    2: const pw.FlexColumnWidth(0.6),
                    3: const pw.FlexColumnWidth(0.6),
                    4: const pw.FlexColumnWidth(0.6),
                    5: const pw.FlexColumnWidth(0.8),
                    6: const pw.FlexColumnWidth(0.9),
                    7: const pw.FlexColumnWidth(0.8),
                    8: const pw.FlexColumnWidth(1.3),
                    9: const pw.FlexColumnWidth(1.7),
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.blue50),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'TOTAUX',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: mainColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        pw.SizedBox(),
                        pw.SizedBox(),
                        pw.SizedBox(),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            sumCoefficients.toStringAsFixed(2),
                            style: pw.TextStyle(
                              font: timesBold,
                              color: totalColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        pw.SizedBox(),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            sumPointsEleve.toStringAsFixed(2),
                            style: pw.TextStyle(
                              font: timesBold,
                              color: secondaryColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            sumPointsClasse.toStringAsFixed(2),
                            style: pw.TextStyle(
                              font: timesBold,
                              color: secondaryColor,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        pw.SizedBox(),
                        pw.SizedBox(),
                      ],
                    ),
                  ],
                );
              }

              if (!hasCategories) {
                return <pw.Widget>[
                  buildTableForSubjects(subjects, showTotals: false),
                  pw.SizedBox(height: 6),
                  buildGlobalTotals(),
                ];
              }

              final List<String?> orderedKeys = [];
              for (final cat in _pdfCategories) {
                if (grouped.containsKey(cat.id)) orderedKeys.add(cat.id);
              }
              if (grouped.containsKey(null)) orderedKeys.add(null);

              final List<pw.Widget> sections = [];
              bool headerShown = false;
              for (final key in orderedKeys) {
                final bool isUncat = key == null;
                final String label = isUncat
                    ? 'Matières non classées'
                    : 'Matières ' +
                          _pdfCategories
                              .firstWhere(
                                (c) => c.id == key,
                                orElse: () => Category.empty(),
                              )
                              .name
                              .toLowerCase();
                final PdfColor badge = isUncat
                    ? PdfColors.blueGrey
                    : PdfColor.fromHex(
                        _pdfCategories
                            .firstWhere(
                              (c) => c.id == key,
                              orElse: () => Category.empty(),
                            )
                            .color
                            .replaceFirst('#', ''),
                      );
                sections.add(
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    margin: const pw.EdgeInsets.only(bottom: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Container(
                          width: 6,
                          height: 12,
                          decoration: pw.BoxDecoration(
                            color: badge,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Text(
                          label,
                          style: pw.TextStyle(
                            font: timesBold,
                            color: secondaryColor,
                            fontSize: 8,
                          ),
                        ),
                        pw.Spacer(),
                        pw.Text(
                          '${grouped[key]!.length} matière(s)',
                          style: pw.TextStyle(
                            font: times,
                            color: secondaryColor,
                            fontSize: 7.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                sections.add(
                  buildTableForSubjects(
                    grouped[key]!,
                    showTotals: false,
                    showHeader: !headerShown,
                  ),
                );
                headerShown = true;
                sections.add(pw.SizedBox(height: 4));
              }
              sections.add(buildGlobalTotals());
              return sections;
            }()),
            pw.SizedBox(height: spacing),
            // Synthèse : tableau des moyennes par période
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: PdfColors.blue100),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Moyenne par ' + periodLabel.toLowerCase(),
                    style: pw.TextStyle(
                      font: timesBold,
                      color: mainColor,
                      fontSize: smallFont,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.blue100),
                    columnWidths: {
                      for (int i = 0; i < allTerms.length; i++)
                        i: const pw.FlexColumnWidth(),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: tableHeaderBg),
                        children: List.generate(allTerms.length, (i) {
                          final label = allTerms[i];
                          final avg =
                              (i < moyennesParPeriode.length &&
                                  moyennesParPeriode[i] != null)
                              ? ' (' +
                                    (moyennesParPeriode[i]!.toStringAsFixed(
                                      2,
                                    )) +
                                    ')'
                              : '';
                          return pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              label + avg,
                              style: pw.TextStyle(
                                font: timesBold,
                                color: tableHeaderText,
                                fontSize: smallFont,
                              ),
                            ),
                          );
                        }),
                      ),
                      pw.TableRow(
                        children: List.generate(allTerms.length, (i) {
                          final String term = allTerms[i];
                          final double? m = (i < moyennesParPeriode.length)
                              ? moyennesParPeriode[i]
                              : null;
                          final r = rankPerTerm[term];
                          final String mainTxt = m != null
                              ? m.toStringAsFixed(2)
                              : '-';
                          final String? suffix =
                              (m != null && r != null && (r['nb'] ?? 0) > 0)
                              ? '(rang ${r['rank']}/${r['nb']})'
                              : null;
                          return pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  mainTxt,
                                  style: pw.TextStyle(
                                    color: secondaryColor,
                                    fontSize: smallFont,
                                  ),
                                ),
                                if (suffix != null) ...[
                                  pw.SizedBox(width: 4),
                                  pw.Text(
                                    suffix,
                                    style: pw.TextStyle(
                                      color: PdfColors.grey600,
                                      fontSize: smallFont - 0.5,
                                      fontStyle: pw.FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: spacing),
            // Synthèse générale
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: PdfColors.blue100),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Moyenne de l\'élève : ${moyenneGenerale.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: mainColor,
                            fontSize: smallFont + 2,
                          ),
                        ),
                        if (moyenneGeneraleDeLaClasse != null)
                          pw.Text(
                            'Moyenne de la classe : ${moyenneGeneraleDeLaClasse.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: secondaryColor,
                              fontSize: smallFont + 1,
                            ),
                          ),
                        if (moyenneLaPlusForte != null)
                          pw.Text(
                            'Moyenne la plus forte : ${moyenneLaPlusForte.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: secondaryColor,
                              fontSize: smallFont + 1,
                            ),
                          ),
                        if (moyenneLaPlusFaible != null)
                          pw.Text(
                            'Moyenne la plus faible : ${moyenneLaPlusFaible.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              font: timesBold,
                              color: secondaryColor,
                              fontSize: smallFont + 1,
                            ),
                          ),
                        // Afficher la moyenne/rang annuels uniquement en fin de période (T3 ou S2)
                        if ((() {
                          final pl = periodLabel.toLowerCase();
                          final st = selectedTerm.toLowerCase();
                          if (pl.contains('trimestre')) return st.contains('3');
                          if (pl.contains('semestre')) return st.contains('2');
                          return false;
                        })()) ...[
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 4),
                            child: pw.Text(
                              'Moyenne annuelle : ' +
                                  (moyenneAnnuelle != null
                                      ? moyenneAnnuelle.toStringAsFixed(2)
                                      : (moyennesParPeriode.isNotEmpty &&
                                                moyennesParPeriode.every(
                                                  (m) => m != null,
                                                )
                                            ? (moyennesParPeriode
                                                          .whereType<double>()
                                                          .reduce(
                                                            (a, b) => a + b,
                                                          ) /
                                                      moyennesParPeriode.length)
                                                  .toStringAsFixed(2)
                                            : '-')),
                              style: pw.TextStyle(
                                font: timesBold,
                                color: mainColor,
                                fontSize: smallFont + 1,
                              ),
                            ),
                          ),
                          if (moyenneAnnuelleClasseComputed != null)
                            pw.Text(
                              'Moyenne annuelle de la classe : ' +
                                  moyenneAnnuelleClasseComputed!
                                      .toStringAsFixed(2),
                              style: pw.TextStyle(
                                font: timesBold,
                                color: secondaryColor,
                                fontSize: smallFont + 1,
                              ),
                            ),
                          if (rangAnnuelComputed != null && nbEleves > 0)
                            pw.Text(
                              'Rang annuel : ${rangAnnuelComputed!} / $nbEleves',
                              style: pw.TextStyle(
                                font: timesBold,
                                color: secondaryColor,
                                fontSize: smallFont + 1,
                              ),
                            ),
                        ],
                        pw.SizedBox(height: 8),
                        pw.Row(
                          children: [
                            pw.Text(
                              'Rang : ',
                              style: pw.TextStyle(
                                font: timesBold,
                                color: secondaryColor,
                                fontSize: smallFont + 1,
                              ),
                            ),
                            pw.Text(
                              exaequo
                                  ? '$rang (ex æquo) / $nbEleves'
                                  : '$rang / $nbEleves',
                              style: pw.TextStyle(
                                color: secondaryColor,
                                fontSize: smallFont + 1,
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 8),
                        pw.Row(
                          children: [
                            pw.Text(
                              'Mention : ',
                              style: pw.TextStyle(
                                font: timesBold,
                                color: secondaryColor,
                                fontSize: smallFont + 1,
                              ),
                            ),
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: pw.BoxDecoration(
                                color: mainColor,
                                borderRadius: pw.BorderRadius.circular(8),
                              ),
                              child: pw.Text(
                                mention,
                                style: pw.TextStyle(
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: smallFont + 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'APPRÉCIATION GÉNÉRALE :',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          resolvedAppreciationGenerale,
                          style: pw.TextStyle(
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 16),
                        pw.Text(
                          'DÉCISION DU CONSEIL DE CLASSE :',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          decision,
                          style: pw.TextStyle(
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'CONDUITE :',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          resolvedConduite,
                          style: pw.TextStyle(
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'HONNEUR :',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          resolvedHonneur,
                          style: pw.TextStyle(
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'ENCOURAGEMENT :',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          resolvedEncouragement,
                          style: pw.TextStyle(
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ASSIDUITÉ ET CONDUITE',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: mainColor,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.RichText(
                                text: pw.TextSpan(
                                  style: pw.TextStyle(
                                    color: secondaryColor,
                                    fontSize: smallFont,
                                  ),
                                  children: [
                                    const pw.TextSpan(text: 'PRÉSENCE: '),
                                    pw.TextSpan(
                                      text: presencePercent > 0
                                          ? presencePercent.toStringAsFixed(1)
                                          : ':',
                                      style: pw.TextStyle(
                                        font: timesBold,
                                        fontSize: smallFont + 1,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.RichText(
                                text: pw.TextSpan(
                                  style: pw.TextStyle(
                                    color: secondaryColor,
                                    fontSize: smallFont,
                                  ),
                                  children: [
                                    const pw.TextSpan(text: 'RETARDS: '),
                                    pw.TextSpan(
                                      text: retards > 0 ? '$retards' : ':',
                                      style: pw.TextStyle(
                                        font: timesBold,
                                        fontSize: smallFont + 1,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.RichText(
                                text: pw.TextSpan(
                                  style: pw.TextStyle(
                                    color: secondaryColor,
                                    fontSize: smallFont,
                                  ),
                                  children: [
                                    const pw.TextSpan(
                                      text: 'ABS. JUSTIFIÉES: ',
                                    ),
                                    pw.TextSpan(
                                      text: attendanceJustifiee > 0
                                          ? '$attendanceJustifiee'
                                          : ':',
                                      style: pw.TextStyle(
                                        font: timesBold,
                                        fontSize: smallFont + 1,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.RichText(
                                text: pw.TextSpan(
                                  style: pw.TextStyle(
                                    color: secondaryColor,
                                    fontSize: smallFont,
                                  ),
                                  children: [
                                    const pw.TextSpan(
                                      text: 'ABS. INJUSTIFIÉES: ',
                                    ),
                                    pw.TextSpan(
                                      text: attendanceInjustifiee > 0
                                          ? '$attendanceInjustifiee'
                                          : ':',
                                      style: pw.TextStyle(
                                        font: timesBold,
                                        fontSize: smallFont + 1,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(
                              color: secondaryColor,
                              fontSize: smallFont,
                            ),
                            children: [
                              const pw.TextSpan(text: 'PUNITIONS: '),
                              pw.TextSpan(
                                text: resolvedAssiduiteConduite.isNotEmpty
                                    ? resolvedAssiduiteConduite
                                    : ':',
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: smallFont + 1,
                                  color: secondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'SANCTIONS',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: PdfColors.red700,
                            fontSize: smallFont,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          sanctions.isNotEmpty ? sanctions : '-',
                          style: pw.TextStyle(
                            color: secondaryColor,
                            fontSize: smallFont,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: spacing),
            // Bloc signature
            pw.Container(
              padding: pw.EdgeInsets.all(isLandscape ? 6 : 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: PdfColors.blue100, width: 1),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Fait à : ',
                              style: pw.TextStyle(
                                font: timesBold,
                                color: mainColor,
                                fontSize: baseFont,
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                () {
                                  final String v = faitA.trim();
                                  if (v.isNotEmpty) return v;
                                  final String addr = (schoolInfo.address)
                                      .trim();
                                  return addr.isNotEmpty
                                      ? addr
                                      : '__________________________';
                                }(),
                                style: pw.TextStyle(
                                  font: times,
                                  color: secondaryColor,
                                  fontSize: baseFont,
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: spacing / 2),
                        pw.Text(
                          niveau.toLowerCase().contains('lycée')
                              ? 'Proviseur(e) :'
                              : 'Directeur(ice) :',
                          style: pw.TextStyle(
                            font: timesBold,
                            color: mainColor,
                            fontSize: baseFont,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        // Nom sous la signature (déplacé plus bas)
                        // Signature du directeur: image au-dessus de la ligne
                        if (_bulletinSignatures['directeur'] != null &&
                            _bulletinSignatures['directeur']!.imagePath != null)
                          pw.Container(
                            width: sigImgWidth,
                            height: sigImgHeight,
                            child: pw.Image(
                              pw.MemoryImage(
                                File(
                                  _bulletinSignatures['directeur']!.imagePath!,
                                ).readAsBytesSync(),
                              ),
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '__________________________',
                          style: pw.TextStyle(
                            font: times,
                            color: secondaryColor,
                            fontSize: lineFont,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        if (directorDisplay.isNotEmpty)
                          pw.Text(
                            directorDisplay,
                            style: pw.TextStyle(
                              font: timesBold,
                              color: secondaryColor,
                              fontSize: baseFont + (denseMode ? 0.5 : 1.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: isLandscape ? 12 : 24),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Le : ',
                              style: pw.TextStyle(
                                font: timesBold,
                                color: mainColor,
                                fontSize: baseFont,
                              ),
                            ),
                            pw.Text(
                              () {
                                final String v = leDate.trim();
                                if (v.isNotEmpty) return _formatDate(v);
                                return DateFormat(
                                  'dd/MM/yyyy',
                                ).format(DateTime.now());
                              }(),
                              style: pw.TextStyle(
                                font: times,
                                color: secondaryColor,
                                fontSize: baseFont,
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: spacing / 2),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Titulaire : ',
                              style: pw.TextStyle(
                                font: timesBold,
                                color: mainColor,
                                fontSize: baseFont,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            // Nom sous la signature (déplacé plus bas)
                            // Signature du titulaire: image au-dessus de la ligne
                            if (_bulletinSignatures['titulaire'] != null &&
                                _bulletinSignatures['titulaire']!.imagePath !=
                                    null)
                              pw.Container(
                                width: sigImgWidth,
                                height: sigImgHeight,
                                child: pw.Image(
                                  pw.MemoryImage(
                                    File(
                                      _bulletinSignatures['titulaire']!
                                          .imagePath!,
                                    ).readAsBytesSync(),
                                  ),
                                  fit: pw.BoxFit.contain,
                                ),
                              ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              '__________________________',
                              style: pw.TextStyle(
                                font: times,
                                color: secondaryColor,
                                fontSize: lineFont,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            if (titulaire.isNotEmpty)
                              pw.Text(
                                titulaire,
                                style: pw.TextStyle(
                                  font: timesBold,
                                  color: secondaryColor,
                                  fontSize: baseFont + (denseMode ? 0.5 : 1.5),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Sanctions now displayed in the right column
            pw.SizedBox(height: isLandscape ? 8 : 24),
          ];
        },
      ),
    );
    return pdf.save();
  }
}
