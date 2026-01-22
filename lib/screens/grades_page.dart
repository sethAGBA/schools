import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/evaluation_template.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/screens/dashboard_home.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/report_card_custom_export_service.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/category.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:excel/excel.dart' as ex show Excel;
import 'package:sqflite/sqflite.dart';
// import 'package:pdf/pdf.dart' as pw; // removed unused import
import 'package:school_manager/screens/students/student_profile_page.dart';
import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:school_manager/screens/statistics_modal.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'dart:ui' as ui;

// Import/Export helpers (top-level)
class _ImportPreview {
  final List<String> headers;
  final List<List<dynamic>> rows;
  final List<String> issues;
  _ImportPreview({
    required this.headers,
    required this.rows,
    required this.issues,
  });
}

class _ProfessorEditResult {
  final Map<String, String> professeurs;
  final bool save;

  _ProfessorEditResult({required this.professeurs, required this.save});
}

class _ImportResult {
  final List<Map<String, dynamic>> rowResults;
  _ImportResult(this.rowResults);
}

class AppColors {
  static const primaryBlue = Color(0xFF3B82F6);
  static const bluePrimary = Color(0xFF3B82F6);
  static const successGreen = Color(0xFF10B981);
  static const shadowDark = Color(0xFF000000);
}

// SchoolInfo et loadSchoolInfo déplacés dans `models/school_info.dart`

// Ajout du notifier global pour le niveau scolaire
final schoolLevelNotifier = ValueNotifier<String>('');

class GradesPage extends StatefulWidget {
  const GradesPage({Key? key}) : super(key: key);

  @override
  _GradesPageState createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> with TickerProviderStateMixin {
  late TabController _tabController;
  late VoidCallback _assignmentsListener;
  String? selectedSubject;
  String? selectedTerm;
  String? selectedStudent;
  String? selectedAcademicYear;
  String? selectedClass;
  String _periodWorkflowStatus = 'Brouillon';
  bool _periodWorkflowLocked = false;
  String? _periodWorkflowUpdatedAt;
  String? _periodWorkflowUpdatedBy;
  bool _isDarkMode = true;
  String _studentSearchQuery = '';
  String _reportSearchQuery = '';
  String _archiveSearchQuery = '';
  String _periodMode = 'Trimestre'; // ou 'Semestre'
  String? _decisionAutomatique;
  int _archiveCurrentPage = 0;
  final int _archiveItemsPerPage = 10;
  String _adminCivility = 'M.';
  bool _searchAllYears = false;
  // Ensure we only auto-save default subject appreciations once per subject per build context
  final Set<String> _initialSubjectAppSave = {};
  // Empêche les rechargements multiples des synthèses déjà chargées
  final Set<String> _loadedReportCardKeys = {};

  List<Student> students = [];
  List<Class> classes = [];
  List<Course> subjects = [];
  List<Category> categories = [];
  Staff? _currentTeacherStaff;
  final Map<String, Set<String>> _teacherSubjectsByClassYear = {};
  final Set<String> _teacherClassYearKeys = {};
  Map<String, String> _assignedTeacherByCourseId = {};

  // Contrôleurs persistants pour les appréciations et notes
  final Map<String, TextEditingController> _appreciationControllers = {};
  final Map<String, TextEditingController> _moyClasseControllers = {};
  final Map<String, TextEditingController> _coeffControllers = {};
  final Map<String, TextEditingController> _profControllers = {};

  // Contrôleurs pour les champs globaux du bulletin
  final TextEditingController _appreciationGeneraleController =
      TextEditingController();
  final TextEditingController _decisionController = TextEditingController();
  final TextEditingController _recommandationsController =
      TextEditingController();
  final TextEditingController _forcesController = TextEditingController();
  final TextEditingController _pointsDevelopperController =
      TextEditingController();
  final TextEditingController _conduiteController = TextEditingController();
  final TextEditingController _absJustifieesController =
      TextEditingController();
  final TextEditingController _absInjustifieesController =
      TextEditingController();
  final TextEditingController _retardsController = TextEditingController();
  final TextEditingController _presencePercentController =
      TextEditingController();
  final TextEditingController _sanctionsController = TextEditingController();
  final TextEditingController _telEtabController = TextEditingController();
  final TextEditingController _mailEtabController = TextEditingController();
  final TextEditingController _webEtabController = TextEditingController();
  final TextEditingController _faitAController = TextEditingController();
  final TextEditingController _leDateController = TextEditingController();

  Timer? _debounceTimer;
  String? _lastLoadedStudentId;
  String? _lastLoadedTerm;
  String? _lastLoadedClass;
  String? _lastLoadedYear;

  bool get _isTeacherRestricted => _currentTeacherStaff != null;

  String _classYearKey(String className, String academicYear) =>
      '$className|$academicYear';

  bool _teacherAllowsClass(String className) {
    if (_currentTeacherStaff == null) return true;
    if (_teacherClassYearKeys.isNotEmpty) {
      final year = _effectiveSelectedAcademicYear() ?? '';
      if (year.isEmpty) return false;
      return _teacherClassYearKeys.contains(_classYearKey(className, year));
    }
    return _currentTeacherStaff!.classes.contains(className);
  }

  bool _teacherAllowsSubjectName(String subjectName) {
    if (_currentTeacherStaff == null) return true;
    final s = subjectName.trim().toLowerCase();
    if (_teacherSubjectsByClassYear.isNotEmpty) {
      final cls = selectedClass;
      final year = _effectiveSelectedAcademicYear() ?? '';
      if (cls == null || year.isEmpty) return false;
      final allowed =
          _teacherSubjectsByClassYear[_classYearKey(cls, year)] ??
          const <String>{};
      return allowed.contains(s);
    }
    return _currentTeacherStaff!.courses
        .map((e) => e.trim().toLowerCase())
        .contains(s);
  }

  String _normalizeSubjectKey(String subject) {
    return subject.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isBlankValue(String? value) {
    final v = value?.trim() ?? '';
    return v.isEmpty || v == '-';
  }

  String? _resolveSubjectName(
    String? subject,
    Map<String, String> canonicalByKey,
  ) {
    final raw = subject?.trim() ?? '';
    if (raw.isEmpty) return null;
    final key = _normalizeSubjectKey(raw);
    return canonicalByKey[key] ?? raw;
  }

  String _getAutomaticAppreciation(double average) {
    if (average >= 19) return 'Excellent';
    if (average >= 16) return 'Très Bien';
    if (average >= 14) return 'Bien';
    if (average >= 12) return 'Assez Bien';
    if (average >= 10) return 'Passable';
    return 'Insuffisant';
  }

  void _debounceSave(Function action) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      action();
    });
  }

  TextEditingController _getSubjectController(
    Map<String, TextEditingController> map,
    String subject,
    String? initialValue,
  ) {
    if (!map.containsKey(subject)) {
      map[subject] = TextEditingController(text: initialValue ?? '');
    } else if (initialValue != null &&
        map[subject]!.text.isEmpty &&
        initialValue.isNotEmpty) {
      // Si le contrôleur existe mais est vide, on peut tenter de le pré-remplir
      // mais attention aux re-builds. Pour l'instant on garde le texte actuel.
    }
    return map[subject]!;
  }

  Future<Map<String, String>> _computeClassSubjectAverages({
    required String className,
    required String academicYear,
    required String term,
    required List<Course> classSubjects,
  }) async {
    final gradesForTerm = await _dbService.getAllGradesForPeriod(
      className: className,
      academicYear: academicYear,
      term: term,
    );

    // Filtrage strict par les élèves inscrits
    final currentStudents = await _dbService.getStudentsByClassAndClassYear(
      className,
      academicYear,
    );
    final Set<String> validStudentIds = currentStudents
        .map((s) => s.id)
        .toSet();

    final Map<String, String> nameByKey = {
      for (final subject in classSubjects)
        _normalizeSubjectKey(subject.name): subject.name,
    };
    final Map<String, String> nameById = {
      for (final subject in classSubjects) subject.id: subject.name,
    };
    final Map<String, double> totalBySubject = {};
    final Map<String, double> coeffBySubject = {};
    for (final grade in gradesForTerm) {
      if (!validStudentIds.contains(grade.studentId)) continue;
      if (grade.type != 'Devoir' && grade.type != 'Composition') continue;
      if (grade.maxValue <= 0 || grade.coefficient <= 0) continue;
      String? subjectName;
      if (grade.subjectId.trim().isNotEmpty) {
        subjectName = nameById[grade.subjectId];
      }
      subjectName ??= grade.subject;
      final resolved = _resolveSubjectName(subjectName, nameByKey);
      if (resolved == null) continue;
      final scaled = ((grade.value / grade.maxValue) * 20) * grade.coefficient;
      totalBySubject[resolved] = (totalBySubject[resolved] ?? 0.0) + scaled;
      coeffBySubject[resolved] =
          (coeffBySubject[resolved] ?? 0.0) + grade.coefficient;
    }
    final Map<String, String> averages = {};
    totalBySubject.forEach((subject, total) {
      final coeff = coeffBySubject[subject] ?? 0.0;
      if (coeff > 0) {
        averages[subject] = (total / coeff).toStringAsFixed(2);
      }
    });
    return averages;
  }

  bool _ensureTeacherCanEditSelection() {
    if (!_isTeacherRestricted) return true;
    final cls = selectedClass;
    final sub = selectedSubject;
    if (cls == null || sub == null) return false;
    if (!_teacherAllowsClass(cls) || !_teacherAllowsSubjectName(sub)) {
      showSnackBar(
        context,
        'Accès refusé: vous ne pouvez saisir que vos classes/matières attribuées.',
        isError: true,
      );
      return false;
    }
    return true;
  }

  void _saveSubjectAppreciationPersistently(String subject) {
    if (selectedStudent == null || selectedStudent == 'all') return;
    final studentId = selectedStudent!;
    final className = selectedClass ?? '';
    final academicYear = selectedAcademicYear ?? academicYearNotifier.value;
    final term = selectedTerm ?? '';
    if (_isPeriodLocked()) return;
    if (!SafeModeService.instance.isActionAllowed()) return;

    _debounceSave(() async {
      final prof = _profControllers[subject]?.text;
      final app = _appreciationControllers[subject]?.text;
      final mc = _moyClasseControllers[subject]?.text;
      final coeff = double.tryParse(
        (_coeffControllers[subject]?.text ?? '').replaceAll(',', '.'),
      );

      await _dbService.insertOrUpdateSubjectAppreciation(
        studentId: studentId,
        className: className,
        academicYear: academicYear,
        subject: subject,
        term: term,
        professeur: prof,
        appreciation: app,
        moyenneClasse: mc,
        coefficient: coeff,
      );
    });
  }

  String _autoConduiteText({
    required int absInj,
    required int retards,
    required String sanctions,
  }) {
    if (sanctions.trim().isNotEmpty) return 'À améliorer';
    if (absInj > 0 || retards > 0) return 'Passable';
    return 'Très bonne conduite';
  }

  void _applyAutoBehavioralFields(
    double moyenneGenerale,
    double? moyenneAnnuelle,
  ) {
    final avg = (moyenneAnnuelle != null && moyenneAnnuelle > 0.0)
        ? moyenneAnnuelle
        : moyenneGenerale;

    String autoAppr(double average) {
      if (average >= 19.0) return 'Excellent';
      if (average >= 16.0) return 'Très Bien';
      if (average >= 14.0) return 'Bien';
      if (average >= 12.0) return 'Assez Bien';
      if (average >= 10.0) return 'Passable';
      return 'Insuffisant';
    }

    final List<String> standardGeneral = [
      'Excellent',
      'Excellent travail',
      'Très Bien',
      'Très bien',
      'Très bon travail',
      'Bien',
      'Bon travail',
      'Assez Bien',
      'Assez bien',
      'Passable',
      'Insuffisant',
    ];

    if (_appreciationGeneraleController.text.trim().isEmpty ||
        _appreciationGeneraleController.text == '-' ||
        standardGeneral.contains(_appreciationGeneraleController.text.trim())) {
      _appreciationGeneraleController.text = autoAppr(avg);
    }
    if (_recommandationsController.text.trim().isEmpty ||
        _recommandationsController.text == '-' ||
        _recommandationsController.text == 'Très bonne conduite' ||
        _recommandationsController.text == 'Passable' ||
        _recommandationsController.text == 'À améliorer') {
      final ac = _autoConduiteText(
        absInj: int.tryParse(_absInjustifieesController.text.trim()) ?? 0,
        retards: int.tryParse(_retardsController.text.trim()) ?? 0,
        sanctions: _sanctionsController.text.trim(),
      );
      _recommandationsController.text = ac;
    }
    if (_forcesController.text.trim().isEmpty ||
        _forcesController.text == '-' ||
        _forcesController.text == 'OUI' ||
        _forcesController.text == 'NON') {
      _forcesController.text = avg >= 16.0 ? 'OUI' : 'NON';
    }
    if (_pointsDevelopperController.text.trim().isEmpty ||
        _pointsDevelopperController.text == '-' ||
        _pointsDevelopperController.text == 'OUI' ||
        _pointsDevelopperController.text == 'NON') {
      _pointsDevelopperController.text = (avg >= 14.0 && avg < 16.0)
          ? 'OUI'
          : 'NON';
    }
  }

  Future<void> _applyAutomaticAppreciations({
    required Student student,
    required List<Grade> studentGrades,
    required List<Course> effectiveSubjects,
    required double moyenneGenerale,
    double? moyenneAnnuelle,
    int? rang,
    int? nbEleves,
    String? mention,
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    int? rangAnnuel,
    int? nbElevesAnnuel,
    bool updateControllers = true,
  }) async {
    if (_isPeriodLocked()) return;
    if (!SafeModeService.instance.isActionAllowed()) return;

    final className = selectedClass ?? '';
    final academicYear = selectedAcademicYear ?? academicYearNotifier.value;
    final term = selectedTerm ?? '';

    for (final course in effectiveSubjects) {
      final subject = course.name;
      final targetKey = _normalizeSubjectKey(subject);
      final sg = studentGrades.where((g) {
        if (g.subjectId.trim().isNotEmpty && course.id.trim().isNotEmpty) {
          return g.subjectId == course.id;
        }
        final gKey = _normalizeSubjectKey(g.subject);
        return gKey == targetKey;
      }).toList();

      if (sg.isEmpty) continue;

      final moyM = PdfService.computeWeightedAverageOn20(sg);
      final autoAppr = _getAutomaticAppreciation(moyM);

      String? currentApp;
      String? currentMoyClasse;
      double? currentCoeff;
      String? currentProf;

      if (updateControllers && selectedStudent == student.id) {
        final List<String> standardSubject = [
          'Excellent',
          'Excellent travail',
          'Très Bien',
          'Très bien',
          'Très bon travail',
          'Bien',
          'Bon travail',
          'Assez Bien',
          'Assez bien',
          'Passable',
          'Insuffisant',
        ];
        if (_appreciationControllers[subject]?.text.trim().isEmpty == true ||
            _appreciationControllers[subject]?.text == '-' ||
            standardSubject.contains(
              _appreciationControllers[subject]?.text.trim(),
            )) {
          _appreciationControllers[subject]?.text = autoAppr;
        }
        final classMoy = _calculateClassAverageForSubject(subject);
        if (_moyClasseControllers[subject]?.text.trim().isEmpty == true ||
            _moyClasseControllers[subject]?.text == '-' ||
            _moyClasseControllers[subject]?.text == '0.00' ||
            _moyClasseControllers[subject]?.text == '0,00') {
          if (classMoy != null) {
            _moyClasseControllers[subject]?.text = classMoy.toStringAsFixed(2);
          }
        } else if (classMoy != null && nbEleves == 1) {
          // Si l'effectif est de 1, la moyenne de classe DOIT correspondre à la note de l'élève
          _moyClasseControllers[subject]?.text = classMoy.toStringAsFixed(2);
        }
        currentApp = _appreciationControllers[subject]?.text;
        currentMoyClasse = _moyClasseControllers[subject]?.text;
        currentCoeff = double.tryParse(
          (_coeffControllers[subject]?.text ?? '').replaceAll(',', '.'),
        );
        currentProf = _profControllers[subject]?.text;
      } else {
        // Direct DB mode
        final existing = await _dbService.getSubjectAppreciation(
          studentId: student.id,
          className: className,
          academicYear: academicYear,
          subject: subject,
          term: term,
        );
        final List<String> standardSubject = [
          'Excellent',
          'Excellent travail',
          'Très Bien',
          'Très bien',
          'Très bon travail',
          'Bien',
          'Bon travail',
          'Assez Bien',
          'Assez bien',
          'Passable',
          'Insuffisant',
        ];
        currentApp = existing?['appreciation'];
        if (currentApp == null ||
            currentApp.trim().isEmpty ||
            currentApp == '-' ||
            standardSubject.contains(currentApp.trim())) {
          currentApp = autoAppr;
        }
        currentMoyClasse = existing?['moyenne_classe'];
        if (currentMoyClasse == null ||
            currentMoyClasse.trim().isEmpty ||
            currentMoyClasse == '-') {
          final classMoy = _calculateClassAverageForSubject(subject);
          if (classMoy != null) {
            currentMoyClasse = classMoy.toStringAsFixed(2);
          }
        }
        currentCoeff = (existing?['coefficient'] as num?)?.toDouble();
        currentProf = existing?['professeur'];
      }

      // Persist the changes
      await _dbService.insertOrUpdateSubjectAppreciation(
        studentId: student.id,
        className: className,
        academicYear: academicYear,
        subject: subject,
        term: term,
        professeur: currentProf,
        appreciation: currentApp,
        moyenneClasse: currentMoyClasse,
        coefficient: currentCoeff,
      );
    }

    // Apply behavioral fields
    if (updateControllers && selectedStudent == student.id) {
      _applyAutoBehavioralFields(moyenneGenerale, moyenneAnnuelle);
      await _saveReportCardSynthesisPersistently();
    } else {
      // Direct DB mode for synthesis
      final rc = await _dbService.getReportCard(
        studentId: student.id,
        className: className,
        academicYear: academicYear,
        term: term,
      );

      final avg = (moyenneAnnuelle != null && moyenneAnnuelle > 0.0)
          ? moyenneAnnuelle
          : moyenneGenerale;

      String autoAppr(double average) {
        if (average >= 19.0) return 'Excellent';
        if (average >= 16.0) return 'Très Bien';
        if (average >= 14.0) return 'Bien';
        if (average >= 12.0) return 'Assez Bien';
        if (average >= 10.0) return 'Passable';
        return 'Insuffisant';
      }

      final List<String> standardGeneral = [
        'Excellent',
        'Excellent travail',
        'Très Bien',
        'Très bien',
        'Très bon travail',
        'Bien',
        'Bon travail',
        'Assez Bien',
        'Assez bien',
        'Passable',
        'Insuffisant',
      ];
      String? appGen = rc?['appreciation_generale'];
      if (appGen == null ||
          appGen.trim().isEmpty ||
          appGen == '-' ||
          standardGeneral.contains(appGen.trim())) {
        appGen = autoAppr(avg);
      }

      String? recommendations = rc?['recommandations'];
      if (recommendations == null ||
          recommendations.trim().isEmpty ||
          recommendations == '-' ||
          recommendations == 'Très bonne conduite' ||
          recommendations == 'Passable' ||
          recommendations == 'À améliorer') {
        recommendations = _autoConduiteText(
          absInj: rc?['attendance_injustifiee'] ?? 0,
          retards: rc?['retards'] ?? 0,
          sanctions: rc?['sanctions'] ?? '',
        );
      }

      String? forces = rc?['forces'];
      if (forces == null ||
          forces.trim().isEmpty ||
          forces == '-' ||
          forces == 'OUI' ||
          forces == 'NON') {
        forces = avg >= 16.0 ? 'OUI' : 'NON';
      }

      String? pointsA = rc?['points_a_developper'];
      if (pointsA == null ||
          pointsA.trim().isEmpty ||
          pointsA == '-' ||
          pointsA == 'OUI' ||
          pointsA == 'NON') {
        pointsA = (avg >= 14.0 && avg < 16.0) ? 'OUI' : 'NON';
      }
      await _dbService.insertOrUpdateReportCard(
        studentId: student.id,
        className: className,
        academicYear: academicYear,
        term: term,
        appreciationGenerale: appGen,
        decision: rc?['decision'],
        recommandations: recommendations,
        forces: forces,
        pointsADevelopper: pointsA,
        moyenneGenerale: moyenneGenerale,
        moyenneAnnuelle: moyenneAnnuelle,
        rang: rang,
        nbEleves: nbEleves,
        mention: mention,
        moyenneGeneraleDeLaClasse: moyenneGeneraleDeLaClasse,
        moyenneLaPlusForte: moyenneLaPlusForte,
        moyenneLaPlusFaible: moyenneLaPlusFaible,
        conduite: rc?['conduite'],
        attendanceJustifiee: rc?['attendance_justifiee'],
        attendanceInjustifiee: rc?['attendance_injustifiee'],
        retards: rc?['retards'],
        presencePercent: rc?['presence_percent'],
        sanctions: rc?['sanctions'],
        faitA: rc?['fait_a'],
        leDate: rc?['le_date'],
      );
    }
  }

  Future<void> _applyBulkAutomaticAppreciations() async {
    if (selectedClass == null || selectedTerm == null) return;
    if (_isPeriodLocked()) return;
    if (!SafeModeService.instance.isActionAllowed()) return;

    final academicYear = selectedAcademicYear ?? academicYearNotifier.value;
    final students = await _dbService.getStudentsByClassAndClassYear(
      selectedClass!,
      academicYear,
    );
    final theme = Theme.of(context);
    final Color mainColor = theme.primaryColor;

    if (students.isEmpty) {
      showSnackBar(context, 'Aucun élève trouvé dans cette classe.');
      return;
    }

    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Génération massive'),
        content: Text(
          'Voulez-vous générer automatiquement les appréciations pour les ${students.length} élèves de la classe $selectedClass pour le $selectedTerm ?\n\nCela ne remplira que les champs vides.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: mainColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Générer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // IMPORTANT: Refresh the global 'grades' list for the whole class
    // so that _calculateClassAverageForSubject (used in auto-appreciation logic)
    // uses the most up-to-date values for everyone.
    await _loadAllGradesForPeriod();

    // Progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Génération des appréciations en cours...'),
          ],
        ),
      ),
    );

    int count = 0;
    try {
      for (final student in students) {
        final data = await _prepareReportCardData(student);
        final grades = data['grades'] as List<Grade>;
        final effSubjects = data['effectiveSubjects'] as List<Course>;
        final moyG = data['moyenneGenerale'] as double;
        final moyA = data['moyenneAnnuelle'] as double?;
        final rang = data['rang'] as int?;
        final nbEleves = data['nbEleves'] as int?;
        final mention = data['mention'] as String?;
        final classMoy = data['moyenneGeneraleDeLaClasse'] as double?;
        final forte = data['moyenneLaPlusForte'] as double?;
        final faible = data['moyenneLaPlusFaible'] as double?;
        final rangAnn = data['rangAnnuel'] as int?;
        final nbAnn = data['nbElevesAnnuel'] as int?;

        await _applyAutomaticAppreciations(
          student: student,
          studentGrades: grades,
          effectiveSubjects: effSubjects,
          moyenneGenerale: moyG,
          moyenneAnnuelle: moyA,
          rang: rang,
          nbEleves: nbEleves,
          mention: mention,
          moyenneGeneraleDeLaClasse: classMoy,
          moyenneLaPlusForte: forte,
          moyenneLaPlusFaible: faible,
          rangAnnuel: rangAnn,
          nbElevesAnnuel: nbAnn,
          updateControllers: student.id == selectedStudent,
        );
        count++;
      }
    } catch (e) {
      debugPrint('Error in bulk generation: $e');
    } finally {
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        if (selectedStudent != null && selectedStudent != 'all') {
          // If we are viewing a student, reload their data to refresh controllers
          final sId = selectedStudent!;
          final sObj = students.firstWhere(
            (s) => s.id == sId,
            orElse: () => Student.empty(),
          );
          if (sObj.id.isNotEmpty) {
            final data = await _prepareReportCardData(sObj);
            final sNames = data['subjects'] as List<String>;
            await _initializeReportCardControllers(
              student: sObj,
              className: selectedClass!,
              academicYear: academicYear,
              term: selectedTerm!,
              subjectNames: sNames,
            );
          }
        }
        setState(() {});
        showSnackBar(context, 'Appréciations générées pour $count élèves.');
      }
    }
  }

  Future<void> _saveReportCardSynthesisPersistently() async {
    if (selectedStudent == null || selectedStudent == 'all') return;
    final studentId = selectedStudent!;
    final className = selectedClass ?? '';
    final academicYear = selectedAcademicYear ?? academicYearNotifier.value;
    final term = selectedTerm ?? '';
    if (_isPeriodLocked()) return;
    if (!SafeModeService.instance.isActionAllowed()) return;

    _debounceSave(() async {
      final data = {
        'studentId': studentId,
        'className': className,
        'academicYear': academicYear,
        'term': term,
        'appreciation_generale': _appreciationGeneraleController.text,
        'decision': _decisionController.text,
        'recommandations': _recommandationsController.text,
        'forces': _forcesController.text,
        'points_a_developper': _pointsDevelopperController.text,
        'conduite': _conduiteController.text,
        'attendance_justifiee':
            int.tryParse(_absJustifieesController.text) ?? 0,
        'attendance_injustifiee':
            int.tryParse(_absInjustifieesController.text) ?? 0,
        'retards': int.tryParse(_retardsController.text) ?? 0,
        'presence_percent':
            double.tryParse(
              _presencePercentController.text.replaceAll('%', ''),
            ) ??
            0.0,
        'sanctions': _sanctionsController.text,
        'fait_a': _faitAController.text,
        'le_date': _leDateController.text,
      };

      await _dbService.insertOrUpdateReportCard(
        studentId: studentId,
        className: className,
        academicYear: academicYear,
        term: term,
        appreciationGenerale: data['appreciation_generale'] as String?,
        decision: data['decision'] as String?,
        recommandations: data['recommandations'] as String?,
        forces: data['forces'] as String?,
        pointsADevelopper: data['points_a_developper'] as String?,
        conduite: data['conduite'] as String?,
        attendanceJustifiee: data['attendance_justifiee'] as int?,
        attendanceInjustifiee: data['attendance_injustifiee'] as int?,
        retards: data['retards'] as int?,
        presencePercent: data['presence_percent'] as double?,
        sanctions: data['sanctions'] as String?,
        faitA: data['fait_a'] as String?,
        leDate: data['le_date'] as String?,
      );
    });
  }

  Future<void> _initializeReportCardControllers({
    required Student student,
    required String className,
    required String academicYear,
    required String term,
    required List<String> subjectNames,
  }) async {
    final String loadKey = '$className|$academicYear|$term|${student.id}';
    final String currentKey =
        '$_lastLoadedClass|$_lastLoadedYear|$_lastLoadedTerm|$_lastLoadedStudentId';

    if (loadKey == currentKey) return;

    _lastLoadedStudentId = student.id;
    _lastLoadedTerm = term;
    _lastLoadedClass = className;
    _lastLoadedYear = academicYear;

    // Charger les appréciations de matières
    final assignmentMap = await _dbService.getTeacherNameByCourseForClass(
      className: className,
      academicYear: academicYear,
    );
    _assignedTeacherByCourseId = assignmentMap;

    final coursesForClass = await _dbService.getCoursesForClass(
      className,
      academicYear,
    );
    final courseIdByName = {for (final c in coursesForClass) c.name: c.id};

    for (final subject in subjectNames) {
      final data = await _dbService.getSubjectAppreciation(
        studentId: student.id,
        className: className,
        academicYear: academicYear,
        subject: subject,
        term: term,
      );

      final ctrlApp = _getSubjectController(
        _appreciationControllers,
        subject,
        data?['appreciation'],
      );
      ctrlApp.text = data?['appreciation'] ?? '';

      final ctrlMc = _getSubjectController(
        _moyClasseControllers,
        subject,
        data?['moyenne_classe'],
      );
      ctrlMc.text = data?['moyenne_classe'] ?? '';

      final coeffVal = (data?['coefficient'] as num?)?.toDouble();
      final ctrlCoeff = _getSubjectController(
        _coeffControllers,
        subject,
        coeffVal?.toString(),
      );
      ctrlCoeff.text = coeffVal != null ? coeffVal.toString() : '';

      final courseId = courseIdByName[subject] ?? '';
      final assigned = courseId.isNotEmpty
          ? (assignmentMap[courseId] ?? '')
          : '';

      final ctrlProf = _getSubjectController(_profControllers, subject, null);
      if (_isPeriodLocked()) {
        ctrlProf.text =
            data?['professeur'] ?? (assigned.isNotEmpty ? assigned : '');
      } else {
        ctrlProf.text = assigned.isNotEmpty
            ? assigned
            : (data?['professeur'] ?? '');
      }
    }

    // Charger la synthèse générale
    final rc = await _dbService.getReportCard(
      studentId: student.id,
      className: className,
      academicYear: academicYear,
      term: term,
    );

    _appreciationGeneraleController.text = rc?['appreciation_generale'] ?? '';
    _decisionController.text = rc?['decision'] ?? '';
    _recommandationsController.text = rc?['recommandations'] ?? '';
    _forcesController.text = rc?['forces'] ?? '';
    _pointsDevelopperController.text = rc?['points_a_developper'] ?? '';
    _conduiteController.text = rc?['conduite'] ?? '';
    _absJustifieesController.text = (rc?['attendance_justifiee'] ?? 0)
        .toString();
    _absInjustifieesController.text = (rc?['attendance_injustifiee'] ?? 0)
        .toString();
    _retardsController.text = (rc?['retards'] ?? 0).toString();

    final double pres = (rc?['presence_percent'] ?? 0.0).toDouble();
    _presencePercentController.text = pres > 0
        ? '${pres.toStringAsFixed(1)}%'
        : '';

    _sanctionsController.text = rc?['sanctions'] ?? '';
    _faitAController.text = rc?['fait_a'] ?? '';
    _leDateController.text = rc?['le_date'] ?? '';

    // Charger les infos établissement si les champs sont vides
    final prefs = await SharedPreferences.getInstance();
    _telEtabController.text = prefs.getString('school_phone') ?? '';
    _mailEtabController.text = prefs.getString('school_email') ?? '';
    _webEtabController.text = prefs.getString('school_website') ?? '';

    if (_faitAController.text.isEmpty) {
      final info = await loadSchoolInfo();
      _faitAController.text = info.address;
    }
    if (_leDateController.text.isEmpty) {
      _leDateController.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
    }
  }

  Future<Map<String, Map<String, num>>> _computeRankPerTermForStudentUI(
    Student student,
    List<String> terms,
  ) async {
    final Map<String, Map<String, num>> rankPerTerm = {};
    String effectiveYear;
    if (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty) {
      effectiveYear = selectedAcademicYear!;
    } else {
      effectiveYear = classes
          .firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          )
          .academicYear;
    }

    // Récupérer la liste officielle des élèves de la classe
    final currentStudents = await _dbService.getStudentsByClassAndClassYear(
      selectedClass!,
      effectiveYear,
    );
    final Set<String> validStudentIds = currentStudents
        .map((s) => s.id)
        .toSet();

    const double eps = 0.001;
    for (final term in terms) {
      final gradesForTerm = await _dbService.getAllGradesForPeriod(
        className: selectedClass!,
        academicYear: effectiveYear,
        term: term,
      );
      final Map<String, double> nByStudent = {};
      final Map<String, double> cByStudent = {};
      for (final g in gradesForTerm.where(
        (g) =>
            validStudentIds.contains(g.studentId) &&
            (g.type == 'Devoir' || g.type == 'Composition'),
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

      // S'assurer que tous les élèves de la classe sont comptés, même sans notes
      for (final sid in validStudentIds) {
        final n = nByStudent[sid] ?? 0.0;
        final c = cByStudent[sid] ?? 0.0;
        final avg = c > 0 ? (n / c) : 0.0;
        avgs.add(avg);
        if (sid == student.id) myAvg = avg;
      }

      avgs.sort((a, b) => b.compareTo(a));
      final int nb = avgs.length;
      final int rank = 1 + avgs.where((v) => (v - myAvg) > eps).length;
      rankPerTerm[term] = {'rank': rank, 'nb': nb, 'avg': myAvg};
    }
    return rankPerTerm;
  }

  List<String> years = [];
  List<Grade> grades = [];
  List<Staff> staff = [];
  bool isLoading = true;

  // Saisie instantanée: brouillons et debounce pour sauvegarde auto
  final Map<String, String> _gradeDrafts = {}; // key: studentId -> typed text
  final Map<String, Timer> _gradeDebouncers =
      {}; // key: studentId -> debounce timer

  List<EvaluationTemplate> _currentDevoirTemplates = [];
  List<EvaluationTemplate> _currentCompositionTemplates = [];

  final List<String> terms = ['Trimestre 1', 'Trimestre 2', 'Trimestre 3'];

  final DatabaseService _dbService = DatabaseService();

  final TextEditingController studentSearchController = TextEditingController();
  final TextEditingController reportSearchController = TextEditingController();
  final TextEditingController archiveSearchController = TextEditingController();

  List<String> get _periods => _periodMode == 'Trimestre'
      ? ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']
      : ['Semestre 1', 'Semestre 2'];

  // ===== Import dialog persistent state =====
  _ImportPreview? _importPreview;
  PlatformFile? _importPickedFile;
  bool _importValidating = false;
  String? _importError;
  int _importSuccessCount = 0;
  int _importErrorCount = 0;
  double _importProgress = 0.0;
  List<Map<String, dynamic>> _importRowResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _assignmentsListener = () {
      if (!mounted) return;
      _onFilterChanged();
    };
    DatabaseService.teacherAssignmentsVersion.addListener(_assignmentsListener);
    selectedTerm = _periods.first;
    academicYearNotifier.addListener(_onAcademicYearChanged);
    getCurrentAcademicYear().then((year) {
      setState(() {
        selectedAcademicYear = year;
      });
      _loadAllData();
    });
    // Initialiser le niveau scolaire depuis les préférences
    SharedPreferences.getInstance().then((prefs) {
      schoolLevelNotifier.value = prefs.getString('school_level') ?? '';
      _adminCivility = (prefs.getString('school_admin_civility') ?? 'M.')
          .trim();
    });
  }

  Future<void> _onFilterChanged() async {
    setState(() {
      isLoading = true;
      _gradeDrafts.clear();
    });
    if (selectedClass != null) {
      String? classYear = selectedAcademicYear;
      if (classYear == null || classYear.isEmpty) {
        try {
          classYear = classes
              .firstWhere((c) => c.name == selectedClass)
              .academicYear;
        } catch (_) {
          classYear = null;
        }
      }
      if (classYear != null && classYear.isNotEmpty) {
        subjects = await _dbService.getCoursesForClass(
          selectedClass!,
          classYear,
        );
        // Charger les catégories pour permettre un affichage groupé
        categories = await _dbService.getCategories();
        if (_currentTeacherStaff != null) {
          if (_teacherSubjectsByClassYear.isNotEmpty) {
            final allowedSubjects =
                _teacherSubjectsByClassYear[_classYearKey(
                  selectedClass!,
                  classYear,
                )] ??
                const <String>{};
            subjects = subjects
                .where(
                  (c) => allowedSubjects.contains(c.name.trim().toLowerCase()),
                )
                .toList();
          } else {
            final allowedSubjects = _currentTeacherStaff!.courses
                .map((s) => s.trim().toLowerCase())
                .where((s) => s.isNotEmpty)
                .toSet();
            subjects = subjects
                .where(
                  (c) => allowedSubjects.contains(c.name.trim().toLowerCase()),
                )
                .toList();
          }
        }
        _assignedTeacherByCourseId = await _dbService
            .getTeacherNameByCourseForClass(
              className: selectedClass!,
              academicYear: classYear,
            );
        if (subjects.isNotEmpty &&
            (selectedSubject == null ||
                !subjects.any((c) => c.name == selectedSubject))) {
          selectedSubject = subjects.first.name;
        }
      } else {
        subjects = [];
        selectedSubject = null;
        _assignedTeacherByCourseId = {};
      }
    } else {
      subjects = [];
      selectedSubject = null;
      _assignedTeacherByCourseId = {};
    }
    await _loadPeriodWorkflow();
    await _loadAllGradesForPeriod();
    await _loadEvaluationTemplatesForCurrentSelection();
    setState(() => isLoading = false);
  }

  String? _effectiveSelectedAcademicYear() {
    if (selectedAcademicYear != null &&
        selectedAcademicYear!.trim().isNotEmpty) {
      return selectedAcademicYear!.trim();
    }
    if (selectedClass != null && (selectedClass?.trim().isNotEmpty ?? false)) {
      try {
        final cls = classes.firstWhere(
          (c) => c.name == selectedClass,
          orElse: () => Class.empty(),
        );
        if (cls.academicYear.trim().isNotEmpty) return cls.academicYear.trim();
      } catch (_) {}
    }
    final fallback = academicYearNotifier.value.trim();
    return fallback.isNotEmpty ? fallback : null;
  }

  String _normalizeGradeLabel({required String type, String? label}) {
    final l = (label ?? '').trim();
    return l.isNotEmpty ? l : type;
  }

  Future<void> _applyAssignmentProfessors({
    required String className,
    required String academicYear,
    required List<String> subjectNames,
    required Map<String, String> professeurs,
  }) async {
    if (_isPeriodLocked()) return;
    final assignmentMap = await _dbService.getTeacherNameByCourseForClass(
      className: className,
      academicYear: academicYear,
    );
    if (assignmentMap.isEmpty) return;
    final coursesForClass = await _dbService.getCoursesForClass(
      className,
      academicYear,
    );
    final courseIdByName = {for (final c in coursesForClass) c.name: c.id};
    for (final subject in subjectNames) {
      final courseId = courseIdByName[subject];
      if (courseId == null || courseId.isEmpty) continue;
      final assigned = assignmentMap[courseId] ?? '';
      final current = (professeurs[subject] ?? '').trim();
      final shouldFill = current.isEmpty || current == '-';
      if (shouldFill && assigned.trim().isNotEmpty) {
        professeurs[subject] = assigned;
      }
    }
  }

  Future<void> _snapshotPeriodDataOnLock({
    required String className,
    required String academicYear,
    required String term,
  }) async {
    final studentsInClass = await _dbService.getStudents(
      className: className,
      academicYear: academicYear,
    );
    if (studentsInClass.isEmpty) return;
    final subjects = await _dbService.getCoursesForClass(
      className,
      academicYear,
    );
    if (subjects.isEmpty) return;
    final assignmentMap = await _dbService.getTeacherNameByCourseForClass(
      className: className,
      academicYear: academicYear,
    );
    final courseIdByName = {for (final c in subjects) c.name: c.id};
    final subjectNames = subjects.map((s) => s.name).toList();
    for (final student in studentsInClass) {
      final existingRows = await _dbService.getSubjectAppreciations(
        studentId: student.id,
        className: className,
        academicYear: academicYear,
        term: term,
      );
      final existingBySubject = {
        for (final row in existingRows) (row['subject'] as String?) ?? '': row,
      };
      for (final subject in subjectNames) {
        final row = existingBySubject[subject];
        final courseId = courseIdByName[subject] ?? '';
        final assigned = courseId.isNotEmpty
            ? (assignmentMap[courseId] ?? '')
            : '';
        final currentProf = (row?['professeur'] as String?)?.trim() ?? '';
        final profToSave = currentProf.isNotEmpty ? currentProf : assigned;
        await _dbService.insertOrUpdateSubjectAppreciation(
          studentId: student.id,
          className: className,
          academicYear: academicYear,
          subject: subject,
          term: term,
          professeur: profToSave.isNotEmpty ? profToSave : null,
          appreciation: row?['appreciation'] as String?,
          moyenneClasse: row?['moyenne_classe'] as String?,
          coefficient: (row?['coefficient'] as num?)?.toDouble(),
        );
      }
    }
  }

  Future<_ProfessorEditResult?> _showEditProfessorsDialog({
    required List<String> subjects,
    required Map<String, String> current,
    required bool allowSave,
  }) async {
    if (subjects.isEmpty) return null;
    final controllers = <String, TextEditingController>{
      for (final s in subjects)
        s: TextEditingController(text: current[s] ?? ''),
    };
    final result = await showDialog<_ProfessorEditResult>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Modifier les professeurs'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final subject in subjects)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: controllers[subject],
                        decoration: InputDecoration(
                          labelText: 'Professeur • $subject',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                final updated = <String, String>{
                  for (final s in subjects)
                    s: (controllers[s]?.text ?? '').trim(),
                };
                Navigator.pop(
                  ctx,
                  _ProfessorEditResult(professeurs: updated, save: false),
                );
              },
              child: const Text('Appliquer'),
            ),
            if (allowSave)
              ElevatedButton(
                onPressed: () {
                  final updated = <String, String>{
                    for (final s in subjects)
                      s: (controllers[s]?.text ?? '').trim(),
                  };
                  Navigator.pop(
                    ctx,
                    _ProfessorEditResult(professeurs: updated, save: true),
                  );
                },
                child: const Text('Enregistrer'),
              ),
          ],
        );
      },
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    return result;
  }

  Grade? _findGradeForTemplate({
    required String studentId,
    required String className,
    required String academicYear,
    required String term,
    required String subject,
    required String type,
    required String label,
  }) {
    final targetLabel = _normalizeGradeLabel(type: type, label: label);
    final candidates = grades
        .where(
          (g) =>
              g.studentId == studentId &&
              g.className == className &&
              g.academicYear == academicYear &&
              g.term == term &&
              g.subject == subject &&
              g.type == type,
        )
        .toList();
    for (final g in candidates) {
      if (_normalizeGradeLabel(type: type, label: g.label) == targetLabel) {
        return g;
      }
    }
    if (candidates.length == 1) return candidates.first;
    return null;
  }

  Future<void> _loadEvaluationTemplatesForCurrentSelection() async {
    final cls = (selectedClass ?? '').trim();
    final year = (_effectiveSelectedAcademicYear() ?? '').trim();
    final subjectName = (selectedSubject ?? '').trim();
    if (cls.isEmpty || year.isEmpty || subjectName.isEmpty) {
      if (!mounted) return;
      setState(() {
        _currentDevoirTemplates = [];
        _currentCompositionTemplates = [];
      });
      return;
    }
    final course = subjects.firstWhere(
      (c) => c.name == subjectName,
      orElse: () => Course.empty(),
    );
    if (course.id.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _currentDevoirTemplates = [];
        _currentCompositionTemplates = [];
      });
      return;
    }

    final templates = await _dbService.getEvaluationTemplates(
      className: cls,
      academicYear: year,
      subjectId: course.id,
    );
    final devoir = templates
        .where((t) => t.type.toLowerCase() == 'devoir')
        .toList();
    final compo = templates
        .where((t) => t.type.toLowerCase() == 'composition')
        .toList();
    devoir.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    compo.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (!mounted) return;
    setState(() {
      _currentDevoirTemplates = devoir;
      _currentCompositionTemplates = compo;
    });
  }

  Future<void> _loadPeriodWorkflow() async {
    final cls = (selectedClass ?? '').trim();
    final term = (selectedTerm ?? '').trim();
    final year = (_effectiveSelectedAcademicYear() ?? '').trim();
    if (cls.isEmpty || term.isEmpty || year.isEmpty) {
      if (!mounted) return;
      setState(() {
        _periodWorkflowStatus = 'Brouillon';
        _periodWorkflowLocked = false;
        _periodWorkflowUpdatedAt = null;
        _periodWorkflowUpdatedBy = null;
      });
      return;
    }
    final row = await _dbService.getGradesPeriodWorkflow(
      className: cls,
      academicYear: year,
      term: term,
    );
    if (!mounted) return;
    setState(() {
      _periodWorkflowStatus = (row?['status'] ?? 'Brouillon').toString();
      _periodWorkflowLocked = ((row?['locked'] ?? 0) as int) == 1;
      _periodWorkflowUpdatedAt = row?['updatedAt']?.toString();
      _periodWorkflowUpdatedBy = row?['updatedBy']?.toString();
    });
  }

  bool _isPeriodLocked() => _periodWorkflowLocked;

  Future<void> _setPeriodWorkflow({
    required String status,
    required bool locked,
  }) async {
    final cls = (selectedClass ?? '').trim();
    final term = (selectedTerm ?? '').trim();
    final year = (_effectiveSelectedAcademicYear() ?? '').trim();
    if (cls.isEmpty || term.isEmpty || year.isEmpty) return;
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String? by;
    try {
      final u = await AuthService.instance.getCurrentUser();
      by = u?.displayName ?? u?.username;
    } catch (_) {}

    if (locked) {
      await _snapshotPeriodDataOnLock(
        className: cls,
        academicYear: year,
        term: term,
      );
    }

    await _dbService.setGradesPeriodWorkflow(
      className: cls,
      academicYear: year,
      term: term,
      status: status,
      locked: locked,
      updatedBy: by,
    );
    await _loadPeriodWorkflow();
  }

  void _onAcademicYearChanged() {
    setState(() {
      selectedAcademicYear = academicYearNotifier.value;
      // Si la classe sélectionnée n'appartient pas à la nouvelle année, choisir une classe de cette année
      if (selectedClass != null) {
        final currentClass = classes.firstWhere(
          (c) => c.name == selectedClass,
          orElse: () => Class.empty(),
        );
        if (currentClass.academicYear != selectedAcademicYear) {
          final Class newYearClass = classes.firstWhere(
            (c) => c.academicYear == selectedAcademicYear,
            orElse: () => Class.empty(),
          );
          selectedClass = newYearClass.name.isNotEmpty
              ? newYearClass.name
              : null;
        }
      }
    });
    _onFilterChanged();
  }

  Future<void> _loadAllData() async {
    setState(() => isLoading = true);
    final currentUser = await AuthService.instance.getCurrentUser();
    students = await _dbService.getStudents();
    classes = await _dbService.getClasses();
    staff = await _dbService.getStaff();
    final allCourses = await _dbService.getCourses();
    final courseNameById = {for (final c in allCourses) c.id: c.name};

    _currentTeacherStaff = null;
    _teacherClassYearKeys.clear();
    _teacherSubjectsByClassYear.clear();
    if (currentUser != null &&
        currentUser.role == 'prof' &&
        (currentUser.staffId ?? '').trim().isNotEmpty) {
      final sid = currentUser.staffId!.trim();
      try {
        _currentTeacherStaff = staff.firstWhere((s) => s.id == sid);
      } catch (_) {
        _currentTeacherStaff = null;
      }
      if (_currentTeacherStaff != null) {
        final assignments = await _dbService.getTeacherAssignmentsForTeacher(
          _currentTeacherStaff!.id,
        );
        if (assignments.isNotEmpty) {
          for (final a in assignments) {
            _teacherClassYearKeys.add(
              _classYearKey(a.className, a.academicYear),
            );
            final subjectName = courseNameById[a.courseId];
            if (subjectName == null || subjectName.trim().isEmpty) continue;
            final key = _classYearKey(a.className, a.academicYear);
            (_teacherSubjectsByClassYear[key] ??= <String>{}).add(
              subjectName.trim().toLowerCase(),
            );
          }
          classes = classes
              .where(
                (c) => _teacherClassYearKeys.contains(
                  _classYearKey(c.name, c.academicYear),
                ),
              )
              .toList();
        } else {
          final allowedClasses = _currentTeacherStaff!.classes.toSet();
          classes = classes
              .where((c) => allowedClasses.contains(c.name))
              .toList();
        }
      } else {
        classes = [];
      }
    }

    years = classes.map((c) => c.academicYear).toSet().toList()..sort();
    // Sélections par défaut
    // Conserver l'année académique déjà définie (courante). Choisir une classe de cette année si possible
    if (classes.isNotEmpty) {
      if (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty) {
        final Class defaultClassForYear = classes.firstWhere(
          (c) => c.academicYear == selectedAcademicYear,
          orElse: () => classes.first,
        );
        selectedClass = defaultClassForYear.name;
      } else {
        selectedClass = classes.first.name;
        selectedAcademicYear = classes.first.academicYear;
      }
    } else {
      selectedClass = null;
    }
    selectedStudent = 'all';
    // Charger les matières de la classe sélectionnée
    if (selectedClass != null) {
      String? classYear = selectedAcademicYear;
      if (classYear == null || classYear.isEmpty) {
        try {
          classYear = classes
              .firstWhere((c) => c.name == selectedClass)
              .academicYear;
        } catch (_) {
          classYear = null;
        }
      }
      if (classYear != null && classYear.isNotEmpty) {
        subjects = await _dbService.getCoursesForClass(
          selectedClass!,
          classYear,
        );
        if (_currentTeacherStaff != null) {
          if (_teacherSubjectsByClassYear.isNotEmpty) {
            final allowedSubjects =
                _teacherSubjectsByClassYear[_classYearKey(
                  selectedClass!,
                  classYear,
                )] ??
                const <String>{};
            subjects = subjects
                .where(
                  (c) => allowedSubjects.contains(c.name.trim().toLowerCase()),
                )
                .toList();
          } else {
            final allowedSubjects = _currentTeacherStaff!.courses
                .map((s) => s.trim().toLowerCase())
                .where((s) => s.isNotEmpty)
                .toSet();
            subjects = subjects
                .where(
                  (c) => allowedSubjects.contains(c.name.trim().toLowerCase()),
                )
                .toList();
          }
        }
        _assignedTeacherByCourseId = await _dbService
            .getTeacherNameByCourseForClass(
              className: selectedClass!,
              academicYear: classYear,
            );
      } else {
        subjects = [];
        _assignedTeacherByCourseId = {};
      }
    } else {
      subjects = [];
      _assignedTeacherByCourseId = {};
    }
    selectedSubject = subjects.isNotEmpty ? subjects.first.name : null;
    await _loadPeriodWorkflow();
    await _loadAllGradesForPeriod();
    setState(() => isLoading = false);
  }

  String _displayStudentName(Student student) {
    final lastName = student.lastName.trim();
    final firstName = student.firstName.trim();
    if (lastName.isEmpty) return firstName;
    if (firstName.isEmpty) return lastName;
    return '$lastName $firstName';
  }

  int _compareStudentsByName(Student a, Student b) {
    final compare = _displayStudentName(
      a,
    ).toLowerCase().compareTo(_displayStudentName(b).toLowerCase());
    if (compare != 0) return compare;
    return a.id.compareTo(b.id);
  }

  Future<String?> _loadDecisionAutomatique(
    String className,
    String academicYear,
    double moyenne,
  ) async {
    try {
      final seuils = await _dbService.getClassPassingThresholds(
        className,
        academicYear,
      );

      if (moyenne >= seuils['felicitations']!) {
        return 'Admis en classe supérieure avec félicitations';
      } else if (moyenne >= seuils['encouragements']!) {
        return 'Admis en classe supérieure avec encouragements';
      } else if (moyenne >= seuils['admission']!) {
        return 'Admis en classe supérieure';
      } else if (moyenne >= seuils['avertissement']!) {
        return 'Admis en classe supérieure avec avertissement';
      } else if (moyenne >= seuils['conditions']!) {
        return 'Admis en classe supérieure sous conditions';
      } else {
        return 'Redouble la classe';
      }
    } catch (e) {
      print('Erreur lors du chargement des seuils: $e');
      return null;
    }
  }

  Future<void> _loadAllGradesForPeriod() async {
    if (selectedClass != null && selectedTerm != null) {
      String? targetYear =
          (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
          ? selectedAcademicYear
          : classes
                .firstWhere(
                  (c) => c.name == selectedClass,
                  orElse: () => Class.empty(),
                )
                .academicYear;
      if (targetYear != null && targetYear.isNotEmpty) {
        grades = await _dbService.getAllGradesForPeriod(
          className: selectedClass!,
          academicYear: targetYear,
          term: selectedTerm!,
        );
      } else {
        grades = [];
      }
    } else {
      grades = [];
    }
  }

  @override
  void dispose() {
    // Annuler les debounces actifs
    for (final t in _gradeDebouncers.values) {
      t.cancel();
    }
    DatabaseService.teacherAssignmentsVersion.removeListener(
      _assignmentsListener,
    );
    academicYearNotifier.removeListener(_onAcademicYearChanged);
    _tabController.dispose();
    studentSearchController.dispose();
    reportSearchController.dispose();
    archiveSearchController.dispose();
    super.dispose();
  }

  Future<void> _saveOrUpdateGrade({
    required Student student,
    required double note,
    required String type,
    required String label,
    required double coefficient,
    required double maxValue,
    Grade? existing,
  }) async {
    // Vérifier le mode coffre fort
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    if (_isPeriodLocked()) {
      showSnackBar(
        context,
        'Période verrouillée ($_periodWorkflowStatus) : modification impossible.',
        isError: true,
      );
      return;
    }

    if (!_ensureTeacherCanEditSelection()) return;

    if (selectedClass == null ||
        selectedAcademicYear == null ||
        selectedSubject == null ||
        selectedTerm == null)
      return;
    final course = subjects.firstWhere(
      (c) => c.name == selectedSubject,
      orElse: () => Course.empty(),
    );
    final newGrade = Grade(
      id: existing?.id,
      studentId: student.id,
      className: selectedClass!,
      academicYear: selectedAcademicYear!,
      subjectId: course.id,
      subject: selectedSubject!,
      term: selectedTerm!,
      value: note,
      label: label,
      type: type,
      coefficient: coefficient,
      maxValue: maxValue,
    );
    if (existing == null) {
      await _dbService.insertGrade(newGrade);
    } else {
      await _dbService.updateGrade(newGrade);
    }

    // Recalculer la moyenne de classe pour cette matière immédiatement
    if (selectedSubject != null) {
      // On recharge d'abord toutes les notes pour avoir les données fraîches
      await _loadAllGradesForPeriod();
      final double? avg = _calculateClassAverageForSubject(selectedSubject!);
      if (avg != null) {
        // Mettre à jour le contrôleur pour l'affichage immédiat
        setState(() {
          _moyClasseControllers[selectedSubject!]?.text = avg.toStringAsFixed(
            2,
          );
        });
      }
    } else {
      await _loadAllGradesForPeriod();
    }

    // Auto-update appreciations for the current student
    if (student.id == selectedStudent) {
      final data = await _prepareReportCardData(student);
      final gradesList = data['grades'] as List<Grade>;
      final effSubjects = data['effectiveSubjects'] as List<Course>;
      final moyG = data['moyenneGenerale'] as double;
      final moyA = data['moyenneAnnuelle'] as double?;
      final rang = data['rang'] as int?;
      final nbEleves = data['nbEleves'] as int?;
      final mention = data['mention'] as String?;
      final classMoy = data['moyenneGeneraleDeLaClasse'] as double?;
      final forte = data['moyenneLaPlusForte'] as double?;
      final faible = data['moyenneLaPlusFaible'] as double?;
      final rangAnn = data['rangAnnuel'] as int?;
      final nbAnn = data['nbElevesAnnuel'] as int?;

      await _applyAutomaticAppreciations(
        student: student,
        studentGrades: gradesList,
        effectiveSubjects: effSubjects,
        moyenneGenerale: moyG,
        moyenneAnnuelle: moyA,
        rang: rang,
        nbEleves: nbEleves,
        mention: mention,
        moyenneGeneraleDeLaClasse: classMoy,
        moyenneLaPlusForte: forte,
        moyenneLaPlusFaible: faible,
        rangAnnuel: rangAnn,
        nbElevesAnnuel: nbAnn,
        updateControllers: true,
      );
    }
    final saved = _findGradeForTemplate(
      studentId: student.id,
      className: selectedClass!,
      academicYear: selectedAcademicYear!,
      term: selectedTerm!,
      subject: selectedSubject!,
      type: type,
      label: label,
    );
    if (saved != null) {
      _gradeDrafts.remove(student.id);
    } else {
      _gradeDrafts[student.id] = note.toString();
    }
    if (mounted) setState(() {});
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Color(0xFFF9FAFB),
      cardColor: Colors.white,
      dividerColor: Color(0xFFE5E7EB),
      shadowColor: Colors.black.withOpacity(0.1),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Color(0xFF111827),
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        labelMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFF374151),
        ),
      ),
      iconTheme: IconThemeData(color: Color(0xFF4F46E5)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF4F46E5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      colorScheme: ColorScheme.light(
        primary: Color(0xFF4F46E5),
        secondary: Color(0xFF10B981),
        surface: Colors.white,
        onSurface: Color(0xFF1F2937),
        background: Color(0xFFF9FAFB),
        error: Color(0xFFEF4444),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Color(0xFF111827),
      cardColor: Color(0xFF1F2937),
      dividerColor: Color(0xFF374151),
      shadowColor: Colors.black.withOpacity(0.4),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFFF9FAFB),
        ),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        labelMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFFD1D5DB),
        ),
      ),
      iconTheme: IconThemeData(color: Color(0xFF818CF8)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF4F46E5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      colorScheme: ColorScheme.dark(
        primary: Color(0xFF6366F1),
        secondary: Color(0xFF34D399),
        surface: Color(0xFF1F2937),
        onSurface: Color(0xFFF9FAFB),
        background: Color(0xFF111827),
        error: Color(0xFFF87171),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDarkMode, bool isDesktop) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.grade,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des Notes',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Système intégré de notation et bulletins',
                        style: TextStyle(
                          fontSize: isDesktop ? 16 : 14,
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.7,
                          ),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  _buildQuickActions(),
                  SizedBox(width: 16),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      color: theme.iconTheme.color,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final theme = Theme.of(context);
    return Row(
      children: [
        _buildActionButton(
          Icons.upload_file,
          'Importer depuis Excel/CSV',
          theme.colorScheme.primary,
          SafeModeService.instance.isActionAllowed()
              ? () => _showImportDialog()
              : () => showSnackBar(
                  context,
                  SafeModeService.instance.getBlockedActionMessage(),
                  isError: true,
                ),
        ),
        const SizedBox(width: 8),
        _buildActionButton(
          Icons.analytics,
          'Statistiques',
          theme.colorScheme.secondary,
          () => _showStatsDialog(),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  void _showStatsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatisticsModal(
          className: selectedClass,
          academicYear: selectedAcademicYear,
          term: selectedTerm,
          students: students,
          grades: grades,
          subjects: subjects,
          dbService: _dbService,
        );
      },
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Theme.of(context).colorScheme.onSurface,
        unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: 'Saisie Notes'),
          Tab(text: 'Bulletins'),
          Tab(text: 'Archives'),
        ],
      ),
    );
  }

  Widget _buildGradeInputTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(
            controller: studentSearchController,
            hintText: 'Rechercher un élève...',
            onChanged: (val) => setState(() => _studentSearchQuery = val),
          ),
          const SizedBox(height: 16),
          _buildSelectionSection(),
          const SizedBox(height: 24),
          _buildStudentGradesSection(),
          const SizedBox(height: 24),
          _buildGradeDistributionSection(),
        ],
      ),
    );
  }

  Widget _buildSelectionSection() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(color: theme.shadowColor, blurRadius: 10, spreadRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodWorkflowBar(theme),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Mode : ', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _periodMode,
                items: ['Trimestre', 'Semestre']
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m, style: theme.textTheme.bodyMedium),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _periodMode = val!;
                    selectedTerm = _periods.first;
                    _onFilterChanged();
                  });
                },
                dropdownColor: theme.cardColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.tune, color: theme.iconTheme.color, size: 24),
              const SizedBox(width: 12),
              Text(
                'Sélection Matière et Période',
                style: theme.textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  'Matière',
                  selectedSubject ?? '',
                  subjects.map((c) => c.name).toList(),
                  (value) async {
                    setState(() {
                      selectedSubject = value!;
                      _gradeDrafts.clear();
                    });
                    await _loadPeriodWorkflow();
                    await _loadAllGradesForPeriod();
                    await _loadEvaluationTemplatesForCurrentSelection();
                  },
                  Icons.book,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdown(
                  _periodMode == 'Trimestre' ? 'Trimestre' : 'Semestre',
                  selectedTerm ?? '',
                  _periods,
                  (value) async {
                    setState(() {
                      selectedTerm = value!;
                      _gradeDrafts.clear();
                      _decisionAutomatique =
                          null; // Reset decision when term changes
                    });
                    await _loadPeriodWorkflow();
                    await _loadAllGradesForPeriod();
                  },
                  Icons.calendar_today,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedClass != null &&
              (selectedClass?.isNotEmpty ?? false) &&
              (selectedSubject?.isNotEmpty ?? false))
            FutureBuilder<Map<String, double>>(
              future: _dbService.getClassSubjectCoefficients(
                selectedClass!,
                (selectedAcademicYear != null &&
                        selectedAcademicYear!.isNotEmpty)
                    ? selectedAcademicYear!
                    : (classes
                              .firstWhere(
                                (c) => c.name == selectedClass,
                                orElse: () => Class.empty(),
                              )
                              .academicYear
                              .isNotEmpty
                          ? classes
                                .firstWhere(
                                  (c) => c.name == selectedClass,
                                  orElse: () => Class.empty(),
                                )
                                .academicYear
                          : academicYearNotifier.value),
              ),
              builder: (context, snap) {
                final coeff =
                    (snap.data ?? const <String, double>{})[selectedSubject!];
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.06),
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Coeff. matière (classe): ' +
                          (coeff != null ? coeff.toStringAsFixed(2) : '-'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: academicYearNotifier,
                  builder: (context, currentYear, _) {
                    final yearList = years.toSet().toList();
                    return DropdownButton<String?>(
                      value: selectedAcademicYear,
                      hint: Text(
                        'Année Académique',
                        style: theme.textTheme.bodyLarge,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Toutes les années'),
                        ),
                        DropdownMenuItem<String?>(
                          value: currentYear,
                          child: Text(
                            'Année courante ($currentYear)',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        ...yearList
                            .where((y) => y != currentYear)
                            .map(
                              (y) => DropdownMenuItem<String?>(
                                value: y,
                                child: Text(
                                  y,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ),
                      ],
                      onChanged: (String? value) {
                        setState(() {
                          selectedAcademicYear = value;
                        });
                        _onFilterChanged();
                      },
                      isExpanded: true,
                      dropdownColor: theme.cardColor,
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdown(
                  'Classe',
                  selectedClass ?? '',
                  classes
                      .where(
                        (c) =>
                            selectedAcademicYear == null ||
                            c.academicYear == selectedAcademicYear,
                      )
                      .map((c) => c.name)
                      .toList(),
                  (value) {
                    setState(() {
                      selectedClass = value!;
                      _decisionAutomatique =
                          null; // Reset decision when class changes
                    });
                    _onFilterChanged();
                  },
                  Icons.class_,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodWorkflowBar(ThemeData theme) {
    final locked = _periodWorkflowLocked;
    final status = _periodWorkflowStatus;
    Color chipColor() {
      switch (status.toLowerCase()) {
        case 'validé':
          return Colors.green;
        case 'soumis':
          return Colors.orange;
        default:
          return Colors.blueGrey;
      }
    }

    String details = '';
    if ((_periodWorkflowUpdatedAt ?? '').trim().isNotEmpty) {
      final d = DateTime.tryParse(_periodWorkflowUpdatedAt!);
      if (d != null) details = DateFormat('dd/MM/yyyy HH:mm').format(d);
      if ((_periodWorkflowUpdatedBy ?? '').trim().isNotEmpty) {
        details = details.isNotEmpty
            ? '$details • ${_periodWorkflowUpdatedBy!}'
            : _periodWorkflowUpdatedBy!;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 18,
                color: locked ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                locked ? 'Période verrouillée' : 'Période ouverte',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Chip(
            label: Text('Statut: $status'),
            backgroundColor: chipColor().withOpacity(0.12),
            labelStyle: TextStyle(color: chipColor()),
            side: BorderSide(color: chipColor().withOpacity(0.3)),
          ),
          if (details.isNotEmpty)
            Text(
              details,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
          ElevatedButton.icon(
            onPressed: locked || status.toLowerCase() != 'brouillon'
                ? null
                : () => _setPeriodWorkflow(status: 'Soumis', locked: true),
            icon: const Icon(Icons.send),
            label: const Text('Soumettre'),
          ),
          const SizedBox(width: 8),
          if (!locked &&
              status.toLowerCase() == 'brouillon' &&
              SafeModeService.instance.isActionAllowed())
            ElevatedButton.icon(
              onPressed: _applyBulkAutomaticAppreciations,
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text('Générer les appréciations'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ElevatedButton.icon(
            onPressed: status.toLowerCase() != 'soumis'
                ? null
                : () async {
                    final u = await AuthService.instance.getCurrentUser();
                    if ((u?.role ?? '').toLowerCase() != 'admin') {
                      showRootSnackBar(
                        const SnackBar(
                          content: Text('Validation réservée au compte admin.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    await _setPeriodWorkflow(status: 'Validé', locked: true);
                  },
            icon: const Icon(Icons.verified),
            label: const Text('Valider'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          OutlinedButton.icon(
            onPressed: !locked
                ? null
                : () async {
                    final u = await AuthService.instance.getCurrentUser();
                    if ((u?.role ?? '').toLowerCase() != 'admin') {
                      showRootSnackBar(
                        const SnackBar(
                          content: Text(
                            'Déverrouillage réservé au compte admin.',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Déverrouiller la période ?'),
                        content: Text(
                          'Le déverrouillage remet le statut en Brouillon et permet à nouveau la modification des notes et appréciations.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Annuler'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Déverrouiller'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    await _setPeriodWorkflow(
                      status: 'Brouillon',
                      locked: false,
                    );
                  },
            icon: const Icon(Icons.lock_open),
            label: const Text('Déverrouiller'),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String? value,
    List<String> items,
    Function(String?) onChanged,
    IconData icon,
  ) {
    String? currentValue = (value != null && items.contains(value))
        ? value
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              isExpanded: true,
              icon: Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              dropdownColor: Theme.of(context).cardColor,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            color: Theme.of(context).iconTheme.color,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                onChanged(val);
                _onFilterChanged();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentGradesSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.people,
                    color: Theme.of(context).iconTheme.color,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Notes des Élèves',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: SafeModeService.instance.isActionAllowed()
                        ? () => _openEvaluationTemplatesDialog()
                        : () => showSnackBar(
                            context,
                            SafeModeService.instance.getBlockedActionMessage(),
                            isError: true,
                          ),
                    icon: const Icon(Icons.rule, size: 18),
                    label: const Text('Modèles'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: SafeModeService.instance.isActionAllowed()
                        ? () => _showBulkGradeDialog()
                        : () => showSnackBar(
                            context,
                            SafeModeService.instance.getBlockedActionMessage(),
                            isError: true,
                          ),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Saisie Rapide'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildClassAverage(),
          _buildStudentGradesList(),
        ],
      ),
    );
  }

  Widget _buildClassAverage() {
    if (isLoading || grades.isEmpty || selectedSubject == null)
      return const SizedBox.shrink();
    final theme = Theme.of(context);
    final classAvg = _calculateClassAverageForSubject(selectedSubject!);
    if (classAvg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.leaderboard, color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          Text(
            'Moyenne de la classe : ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            classAvg.toStringAsFixed(2),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentGradesList() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Filtrage dynamique des élèves
    List<Student> filteredStudents = students.where((s) {
      final classMatch = selectedClass == null || s.className == selectedClass;
      // Pour la saisie, si aucune année n'est sélectionnée, on retient l'année de l'élève
      final String effectiveYear =
          (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
          ? selectedAcademicYear!
          : s.academicYear;
      final yearMatch = s.academicYear == effectiveYear;
      final query = _studentSearchQuery.toLowerCase();
      final searchMatch =
          query.isEmpty ||
          _displayStudentName(s).toLowerCase().contains(query) ||
          s.name.toLowerCase().contains(query);
      return classMatch && yearMatch && searchMatch;
    }).toList()..sort(_compareStudentsByName);
    if (filteredStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.group_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Aucun élève trouvé.',
              style: TextStyle(color: Colors.grey, fontSize: 18),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        ...filteredStudents
            .map((student) => _buildStudentGradeCard(student))
            .toList(),
      ],
    );
  }

  Widget _buildStudentGradeCard(Student student) {
    // Saisie rapide (carte) : par défaut sur "Devoir" (modèle 1 si défini)
    final devoirTemplate = _currentDevoirTemplates.isNotEmpty
        ? _currentDevoirTemplates.first
        : null;
    final devoirLabel = _normalizeGradeLabel(
      type: 'Devoir',
      label: devoirTemplate?.label ?? 'Devoir',
    );

    Grade? grade;
    final targetYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : student.academicYear;
    if (selectedClass != null &&
        selectedClass!.trim().isNotEmpty &&
        selectedTerm != null &&
        selectedTerm!.trim().isNotEmpty &&
        selectedSubject != null &&
        selectedSubject!.trim().isNotEmpty) {
      grade = _findGradeForTemplate(
        studentId: student.id,
        className: selectedClass!,
        academicYear: targetYear,
        term: selectedTerm!,
        subject: selectedSubject!,
        type: 'Devoir',
        label: devoirLabel,
      );
    }
    final initialText =
        _gradeDrafts[student.id] ??
        (grade != null ? grade.value.toString() : '');
    final controller = TextEditingController(text: initialText);

    final double? studentAvg = (_gradeDrafts.containsKey(student.id))
        ? _parseQuickEntryValue(
            _gradeDrafts[student.id]!,
            grade?.maxValue ?? 20.0,
          )
        : grade?.value;

    final double effectiveCoeff =
        devoirTemplate?.coefficient ?? (grade?.coefficient ?? 1.0);
    final double effectiveMax =
        devoirTemplate?.maxValue ?? (grade?.maxValue ?? 20.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.1),
            child: Text(
              student.firstName.isNotEmpty ? student.firstName[0] : '?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayStudentName(student),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Classe: ${student.className}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Container(
            width: 80,
            child: TextField(
              controller: controller,
              enabled:
                  SafeModeService.instance.isActionAllowed() &&
                  !_isPeriodLocked(),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                color:
                    SafeModeService.instance.isActionAllowed() &&
                        !_isPeriodLocked()
                    ? Theme.of(context).textTheme.bodyLarge?.color
                    : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                labelText: 'Note',
                labelStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surface.withOpacity(0.5),
              ),
              onChanged: (val) {
                // Met à jour l'affichage immédiat et lance une sauvegarde avec debounce
                setState(() => _gradeDrafts[student.id] = val);
                _gradeDebouncers[student.id]?.cancel();
                _gradeDebouncers[student
                    .id] = Timer(const Duration(milliseconds: 700), () async {
                  final note = _parseQuickEntryValue(val, effectiveMax);
                  if (note != null) {
                    if (selectedClass != null &&
                        selectedAcademicYear != null &&
                        selectedSubject != null &&
                        selectedTerm != null) {
                      await _saveOrUpdateGrade(
                        student: student,
                        note: note,
                        type: 'Devoir',
                        label: devoirLabel,
                        coefficient: effectiveCoeff,
                        maxValue: effectiveMax,
                        existing: grade,
                      );
                      if (mounted) {
                        showRootSnackBar(
                          SnackBar(
                            content: Text(
                              'Note enregistrée pour ${_displayStudentName(student)}',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } else if (mounted) {
                      showRootSnackBar(
                        const SnackBar(
                          content: Text(
                            'Sélectionnez classe, matière, période et année avant de saisir.',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                });
              },
              onSubmitted: (val) async {
                final note = _parseQuickEntryValue(val, effectiveMax);
                if (note != null) {
                  if (selectedClass != null &&
                      selectedAcademicYear != null &&
                      selectedSubject != null &&
                      selectedTerm != null) {
                    await _saveOrUpdateGrade(
                      student: student,
                      note: note,
                      type: 'Devoir',
                      label: devoirLabel,
                      coefficient: effectiveCoeff,
                      maxValue: effectiveMax,
                      existing: grade,
                    );
                    if (mounted) {
                      showRootSnackBar(
                        SnackBar(
                          content: Text(
                            'Note enregistrée pour ${_displayStudentName(student)}',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else if (mounted) {
                    showRootSnackBar(
                      const SnackBar(
                        content: Text(
                          'Sélectionnez classe, matière, période et année avant de saisir.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Icon(
                Icons.bar_chart,
                size: 18,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              Text(
                studentAvg != null ? studentAvg.toStringAsFixed(2) : '-',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.edit, color: Colors.orange),
            tooltip: 'Modifier toutes les notes',
            onPressed: () {
              if (!SafeModeService.instance.isActionAllowed()) {
                showSnackBar(
                  context,
                  SafeModeService.instance.getBlockedActionMessage(),
                  isError: true,
                );
                return;
              }
              if (_isPeriodLocked()) {
                showSnackBar(
                  context,
                  'Période verrouillée ($_periodWorkflowStatus) : modification impossible.',
                  isError: true,
                );
                return;
              }
              _showEditStudentGradesDialog(student);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGradeDistributionSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart,
                color: Theme.of(context).iconTheme.color,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Répartition des Notes - ${selectedSubject ?? ""}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildGradeChart(),
        ],
      ),
    );
  }

  Widget _buildGradeChart() {
    final theme = Theme.of(context);
    // Construire une distribution en tenant compte des saisies en cours
    List<Grade> relevant;
    if (selectedSubject != null) {
      relevant = _effectiveGradesForSubject(selectedSubject!);
    } else {
      relevant = grades
          .where(
            (g) =>
                g.className == selectedClass &&
                g.academicYear == selectedAcademicYear &&
                g.term == selectedTerm &&
                (g.type == 'Devoir' || g.type == 'Composition') &&
                g.value != null &&
                g.maxValue > 0,
          )
          .toList();
    }

    double to20(Grade g) => (g.value / g.maxValue) * 20.0;
    final scores = relevant.map(to20).toList();
    int count(bool Function(double) p) => scores.where(p).length;

    final labels = [
      '[0-5[',
      '[5-10[',
      '[10-12[',
      '[12-14[',
      '[14-16[',
      '[16-20]',
    ];
    final counts = [
      count((s) => s >= 0 && s < 5),
      count((s) => s >= 5 && s < 10),
      count((s) => s >= 10 && s < 12),
      count((s) => s >= 12 && s < 14),
      count((s) => s >= 14 && s < 16),
      count((s) => s >= 16 && s <= 20),
    ];
    final int total = scores.length;
    final colors = [
      Colors.red.shade400,
      Colors.orange.shade400,
      Colors.amber.shade600,
      Colors.lightGreen.shade500,
      Colors.green.shade600,
      Colors.teal.shade600,
    ];

    if (total == 0) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'Aucune note disponible pour afficher la répartition.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return Container(
      height: 220,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(labels.length, (index) {
          final ratio = counts[index] / total;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: colors[index],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 36,
                height: (ratio * 160).clamp(2, 160),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [colors[index], colors[index].withOpacity(0.6)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: colors[index].withOpacity(0.25),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(labels[index], style: theme.textTheme.bodyMedium),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildReportCardsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(
            controller: reportSearchController,
            hintText: 'Rechercher un élève (bulletin)...',
            onChanged: (val) => setState(() => _reportSearchQuery = val),
          ),
          const SizedBox(height: 16),
          _buildSelectionSection(),
          const SizedBox(height: 24),
          _buildReportCardSelection(),
          const SizedBox(height: 24),
          _buildReportCardPreview(),
        ],
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
        ),
        prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
        filled: true,
        fillColor: theme.cardColor,
        contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
      style: theme.textTheme.bodyLarge,
    );
  }

  Widget _buildReportCardSelection() {
    final filteredStudents = students.where((s) {
      final classMatch =
          selectedClass == null ||
          (s.className == selectedClass &&
              (selectedAcademicYear == null ||
                  selectedAcademicYear!.isEmpty ||
                  s.academicYear == selectedAcademicYear));
      // Logique Paiements: si une année est choisie => filtrer par année classe ET élève; sinon toutes les années
      final bool yearMatch =
          (selectedAcademicYear == null || selectedAcademicYear!.isEmpty)
          ? true
          : s.academicYear == selectedAcademicYear;
      final query = _reportSearchQuery.toLowerCase();
      final searchMatch =
          query.isEmpty ||
          _displayStudentName(s).toLowerCase().contains(query) ||
          s.name.toLowerCase().contains(query);
      return classMatch && yearMatch && searchMatch;
    }).toList()..sort(_compareStudentsByName);

    final dropdownItems = [
      {'id': 'all', 'name': 'Sélectionner un élève'},
      ...filteredStudents.map(
        (s) => {'id': s.id, 'name': _displayStudentName(s)},
      ),
    ];

    if (selectedStudent == null ||
        !dropdownItems.any((item) => item['id'] == selectedStudent)) {
      selectedStudent = dropdownItems.first['id'];
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment,
                color: Theme.of(context).iconTheme.color,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Génération & Exportation',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 20),
          DropdownButton<String>(
            value: selectedStudent,
            items: dropdownItems
                .map(
                  (item) => DropdownMenuItem(
                    value: item['id'],
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          color: Theme.of(context).iconTheme.color,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item['name']!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) async {
              setState(() => selectedStudent = val!);
              // Ajuster automatiquement classe/année/période pour l'aperçu si non définis
              final Student sel = students.firstWhere(
                (s) => s.id == val,
                orElse: () => Student.empty(),
              );
              String? effectiveClass = selectedClass;
              String? effectiveYear = selectedAcademicYear;
              if (effectiveClass == null || effectiveClass.isEmpty)
                effectiveClass = sel.className;
              if (effectiveYear == null || effectiveYear.isEmpty)
                effectiveYear = sel.academicYear;
              String? effTerm = selectedTerm;
              if (effTerm == null || effTerm.isEmpty) {
                effTerm = _periodMode == 'Trimestre'
                    ? 'Trimestre 1'
                    : 'Semestre 1';
              }
              setState(() {
                selectedClass = effectiveClass;
                selectedAcademicYear = effectiveYear;
                selectedTerm = effTerm;
              });
              await _onFilterChanged();
            },
            isExpanded: true,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: (selectedClass == null || selectedClass!.isEmpty)
                      ? null
                      : SafeModeService.instance.isActionAllowed()
                      ? () => _exportClassReportCards()
                      : () => showSnackBar(
                          context,
                          SafeModeService.instance.getBlockedActionMessage(),
                          isError: true,
                        ),
                  icon: const Icon(Icons.archive, size: 18),
                  label: const Text('Exporter bulletins (ZIP)'),
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                    backgroundColor: MaterialStateProperty.all(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: (selectedClass == null || selectedClass!.isEmpty)
                      ? null
                      : SafeModeService.instance.isActionAllowed()
                      ? () => _exportClassReportCardsCompact()
                      : () => showSnackBar(
                          context,
                          SafeModeService.instance.getBlockedActionMessage(),
                          isError: true,
                        ),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Exporter PDF compact (ZIP)'),
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                    backgroundColor: MaterialStateProperty.all(
                      Colors.indigo.shade600,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: (selectedClass == null || selectedClass!.isEmpty)
                      ? null
                      : SafeModeService.instance.isActionAllowed()
                      ? () => _exportClassReportCardsUltraCompact()
                      : () => showSnackBar(
                          context,
                          SafeModeService.instance.getBlockedActionMessage(),
                          isError: true,
                        ),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Exporter PDF ultra compact (ZIP)'),
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                    backgroundColor: MaterialStateProperty.all(
                      Colors.deepPurple.shade600,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: (selectedClass == null || selectedClass!.isEmpty)
                      ? null
                      : SafeModeService.instance.isActionAllowed()
                      ? () => _exportClassReportCardsCustom()
                      : () => showSnackBar(
                          context,
                          SafeModeService.instance.getBlockedActionMessage(),
                          isError: true,
                        ),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Exporter PDF custom (ZIP)'),
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                    backgroundColor: MaterialStateProperty.all(
                      Colors.teal.shade700,
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

  Widget _buildReportCardPreview() {
    if (selectedStudent == null || selectedStudent == 'all') {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade100, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade100.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Sélectionnez un élève pour voir son bulletin.',
            style: TextStyle(color: Colors.blueGrey.shade700),
          ),
        ),
      );
    }
    final student = students.firstWhere(
      (s) => s.id == selectedStudent,
      orElse: () => Student.empty(),
    );
    if (student.id.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade100, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade100.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Aucun élève trouvé.',
            style: TextStyle(color: Colors.blueGrey.shade700),
          ),
        ),
      );
    }
    return FutureBuilder<SchoolInfo>(
      future: loadSchoolInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final info = snapshot.data!;
        // Ajout ValueListenableBuilder pour le niveau scolaire
        return ValueListenableBuilder<String>(
          valueListenable: schoolLevelNotifier,
          builder: (context, niveau, _) {
            final String effectiveYear =
                (selectedAcademicYear != null &&
                    selectedAcademicYear!.isNotEmpty)
                ? selectedAcademicYear!
                : student.academicYear;
            final schoolYear = effectiveYear;
            final periodLabel = _periodMode == 'Trimestre'
                ? 'Trimestre'
                : 'Semestre';
            final String effClass =
                (selectedClass == null || selectedClass!.isEmpty)
                ? student.className
                : selectedClass!;
            final String effTerm =
                (selectedTerm == null || selectedTerm!.isEmpty)
                ? (_periodMode == 'Trimestre' ? 'Trimestre 1' : 'Semestre 1')
                : selectedTerm!;

            return FutureBuilder<void>(
              future: _initializeReportCardControllers(
                student: student,
                className: effClass,
                academicYear: effectiveYear,
                term: effTerm,
                subjectNames: subjects.map((s) => s.name).toList(),
              ),
              builder: (context, initSnapshot) {
                if (initSnapshot.connectionState == ConnectionState.waiting &&
                    _lastLoadedStudentId != student.id) {
                  return const Center(child: CircularProgressIndicator());
                }

                final studentGrades = grades
                    .where(
                      (g) =>
                          g.studentId == student.id &&
                          g.className == effClass &&
                          g.academicYear == effectiveYear &&
                          g.term == effTerm,
                    )
                    .toList();
                final subjectNames = subjects.map((c) => c.name).toList();
                final types = ['Devoir', 'Composition'];
                final Color mainColor = Colors.blue.shade800;
                final Color secondaryColor = Colors.blueGrey.shade700;
                final Color tableHeaderBg = Colors.blue.shade200;
                final Color tableHeaderText = Colors.white;
                final Color tableRowAlt = Colors.blue.shade50;
                final DateTime now = DateTime.now();
                final int nbEleves = students
                    .where(
                      (s) =>
                          s.className == effClass &&
                          s.academicYear == effectiveYear,
                    )
                    .length;
                // Bloc élève : nom, prénom, sexe
                final String prenom = student.firstName;
                final String nom = student.lastName;
                final String sexe = student.gender;
                final Class classInfo = classes.firstWhere(
                  (c) => c.name == effClass && c.academicYear == effectiveYear,
                  orElse: () => Class.empty(),
                );
                final String niveau =
                    (classInfo.level?.trim().isNotEmpty ?? false)
                    ? classInfo.level!.trim()
                    : schoolLevelNotifier.value;
                final bool isComplexe =
                    schoolLevelNotifier.value.toLowerCase().contains(
                      'complexe',
                    ) ||
                    (info.directorPrimary?.trim().isNotEmpty ?? false) ||
                    (info.directorCollege?.trim().isNotEmpty ?? false) ||
                    (info.directorLycee?.trim().isNotEmpty ?? false) ||
                    (info.directorUniversity?.trim().isNotEmpty ?? false);

                // Helpers pour l'en-tête administratif (aperçu)
                String fmtDate(String s) {
                  if (s.isEmpty) return s;
                  try {
                    DateTime? d;
                    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
                      d = DateTime.tryParse(s);
                    } else if (RegExp(r'^\d{2}/\d{2}/\d{4}').hasMatch(s)) {
                      final parts = s.split('/');
                      d = DateTime(
                        int.parse(parts[2]),
                        int.parse(parts[1]),
                        int.parse(parts[0]),
                      );
                    }
                    if (d != null) return DateFormat('dd/MM/yyyy').format(d);
                  } catch (_) {}
                  return s;
                }

                List<String> splitTwoLines(String input) {
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
                    running += words[i].length + 1;
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

                double measureText(String text, TextStyle style) {
                  final tp = TextPainter(
                    text: TextSpan(text: text, style: style),
                    maxLines: 1,
                    textDirection: ui.TextDirection.ltr,
                  );
                  tp.layout();
                  return tp.width;
                }

                final adminBold = TextStyle(
                  fontWeight: FontWeight.bold,
                  color: secondaryColor,
                );
                final parts = splitTwoLines(info.ministry ?? '');
                final double w1 = parts.isNotEmpty
                    ? measureText(parts[0], adminBold)
                    : 0;
                final double w2 = parts.length > 1
                    ? measureText(parts[1], adminBold)
                    : 0;
                final double maxW = (w1 > w2 ? w1 : w2);
                final double padFirst = (w2 > w1) ? ((w2 - w1) / 2) : 0;
                final double padSecond = (w1 > w2) ? ((w1 - w2) / 2) : 0;
                // --- Mise à jour en temps réel via listeners (une seule fois) ---
                // Les listeners sont gérés par les contrôleurs persistants maintenant.
                // --- Moyennes par période ---
                final List<String> allTerms = _periodMode == 'Trimestre'
                    ? ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']
                    : ['Semestre 1', 'Semestre 2'];
                final Map<String, double> subjectWeights = {
                  for (final s in subjectNames)
                    s:
                        double.tryParse(
                          (_coeffControllers[s]?.text ?? '').replaceAll(
                            ',',
                            '.',
                          ),
                        ) ??
                        0.0,
                };
                final List<double?> moyennesParPeriode = allTerms.map((term) {
                  final termGrades = grades
                      .where(
                        (g) =>
                            g.studentId == student.id &&
                            g.className == selectedClass &&
                            g.academicYear == effectiveYear &&
                            g.term == term &&
                            (g.type == 'Devoir' || g.type == 'Composition') &&
                            g.value != null,
                      )
                      .toList();
                  double sumPts = 0.0;
                  double sumW = 0.0;
                  for (final subject in subjectNames) {
                    final subjectGrades = termGrades
                        .where((g) => g.subject == subject)
                        .toList();
                    if (subjectGrades.isEmpty) continue;
                    final moyenneMatiere = _computeWeightedAverageOn20(
                      subjectGrades,
                    );
                    final totalCoeff = subjectGrades
                        .where((g) => g.maxValue > 0 && g.coefficient > 0)
                        .fold<double>(0.0, (s, g) => s + g.coefficient);
                    final w = (subjectWeights[subject] ?? 0.0) > 0
                        ? subjectWeights[subject]!
                        : totalCoeff;
                    if (w > 0) {
                      sumPts += moyenneMatiere * w;
                      sumW += w;
                    }
                  }
                  return (sumW > 0) ? (sumPts / sumW) : null;
                }).toList();
                // Calcul de la moyenne générale pondérée (devoirs + compos)
                double sumPtsSel = 0.0;
                double sumWSel = 0.0;
                for (final subject in subjectNames) {
                  final subjectGrades = studentGrades
                      .where((g) => g.subject == subject)
                      .toList();
                  if (subjectGrades.isEmpty) continue;
                  final moyenneMatiere = _computeWeightedAverageOn20(
                    subjectGrades,
                  );
                  final totalCoeff = subjectGrades
                      .where((g) => g.maxValue > 0 && g.coefficient > 0)
                      .fold<double>(0.0, (s, g) => s + g.coefficient);
                  final w = (subjectWeights[subject] ?? 0.0) > 0
                      ? subjectWeights[subject]!
                      : totalCoeff;
                  if (w > 0) {
                    sumPtsSel += moyenneMatiere * w;
                    sumWSel += w;
                  }
                }
                final moyenneGenerale = (sumWSel > 0)
                    ? (sumPtsSel / sumWSel)
                    : 0.0;

                // Define the logic here but also ensure we have the class-level version
                final int selectedIndex = allTerms.indexOf(selectedTerm ?? '');
                if (selectedIndex >= 0 &&
                    selectedIndex < moyennesParPeriode.length) {
                  moyennesParPeriode[selectedIndex] = moyenneGenerale;
                }
                // Calcul du rang
                final classStudentIds = students
                    .where((s) {
                      if (s.className != effClass) return false;
                      final classObj = classes.firstWhere(
                        (c) => c.name == s.className,
                        orElse: () => Class.empty(),
                      );
                      // Align with effectiveYear so single exports mirror ZIP exports
                      return classObj.academicYear == effectiveYear &&
                          s.academicYear == effectiveYear;
                    })
                    .map((s) => s.id)
                    .toList();
                final List<double> allMoyennes = classStudentIds.map((sid) {
                  final sg = grades
                      .where(
                        (g) =>
                            g.studentId == sid &&
                            g.className == effClass &&
                            g.academicYear == effectiveYear &&
                            g.term == effTerm &&
                            (g.type == 'Devoir' || g.type == 'Composition') &&
                            g.value != null,
                      )
                      .toList();
                  double sumPts = 0.0;
                  double sumW = 0.0;
                  for (final subject in subjectNames) {
                    final subjectGrades = sg
                        .where((g) => g.subject == subject)
                        .toList();
                    if (subjectGrades.isEmpty) continue;
                    final moyenneMatiere = _computeWeightedAverageOn20(
                      subjectGrades,
                    );
                    final totalCoeff = subjectGrades
                        .where((g) => g.maxValue > 0 && g.coefficient > 0)
                        .fold<double>(0.0, (s, g) => s + g.coefficient);
                    final w = (subjectWeights[subject] ?? 0.0) > 0
                        ? subjectWeights[subject]!
                        : totalCoeff;
                    if (w > 0) {
                      sumPts += moyenneMatiere * w;
                      sumW += w;
                    }
                  }
                  return (sumW > 0) ? (sumPts / sumW) : 0.0;
                }).toList();
                allMoyennes.sort((a, b) => b.compareTo(a));
                final rang =
                    allMoyennes.indexWhere(
                      (m) => (m - moyenneGenerale).abs() < 0.001,
                    ) +
                    1;

                final double? moyenneGeneraleDeLaClasse = allMoyennes.isNotEmpty
                    ? allMoyennes.reduce((a, b) => a + b) / allMoyennes.length
                    : null;
                final double? moyenneLaPlusForte = allMoyennes.isNotEmpty
                    ? allMoyennes.reduce((a, b) => a > b ? a : b)
                    : null;
                final double? moyenneLaPlusFaible = allMoyennes.isNotEmpty
                    ? allMoyennes.reduce((a, b) => a < b ? a : b)
                    : null;

                // Calcul de la moyenne annuelle
                double? moyenneAnnuelle;
                final allGradesForYear = grades
                    .where(
                      (g) =>
                          g.studentId == student.id &&
                          g.className == selectedClass &&
                          g.academicYear == selectedAcademicYear &&
                          (g.type == 'Devoir' || g.type == 'Composition') &&
                          g.value != null,
                    )
                    .toList();

                if (allGradesForYear.isNotEmpty) {
                  double totalAnnualNotes = 0.0;
                  double totalAnnualCoeffs = 0.0;
                  for (final g in allGradesForYear) {
                    if (g.maxValue > 0 && g.coefficient > 0) {
                      totalAnnualNotes +=
                          ((g.value / g.maxValue) * 20) * g.coefficient;
                      totalAnnualCoeffs += g.coefficient;
                    }
                  }
                  moyenneAnnuelle = totalAnnualCoeffs > 0
                      ? totalAnnualNotes / totalAnnualCoeffs
                      : null;
                }

                // Mention
                String mention;
                if (moyenneGenerale >= 19) {
                  mention = 'EXCELLENT';
                } else if (moyenneGenerale >= 18) {
                  mention = 'TRÈS BIEN';
                } else if (moyenneGenerale >= 15) {
                  mention = 'BIEN';
                } else if (moyenneGenerale >= 12) {
                  mention = 'ASSEZ BIEN';
                } else if (moyenneGenerale >= 10) {
                  mention = 'PASSABLE';
                } else {
                  mention = 'INSUFFISANT';
                }

                // Décision automatique du conseil de classe basée sur la moyenne annuelle
                // Ne s'affiche qu'en fin d'année (Trimestre 3 ou Semestre 2)
                final bool isEndOfYear =
                    selectedTerm == 'Trimestre 3' ||
                    selectedTerm == 'Semestre 2';

                if (isEndOfYear && _decisionAutomatique == null) {
                  // Récupérer les seuils spécifiques à la classe de manière asynchrone
                  _loadDecisionAutomatique(
                    selectedClass ?? '',
                    effectiveYear,
                    moyenneAnnuelle ?? moyenneGenerale,
                  ).then((decision) {
                    if (mounted) {
                      setState(() {
                        _decisionAutomatique = decision;
                      });
                    }
                  });
                }
                // --- Chargement initial et sauvegarde automatique de la synthèse ---
                final String effectiveYearForKey =
                    (selectedAcademicYear != null &&
                        selectedAcademicYear!.isNotEmpty)
                    ? selectedAcademicYear!
                    : academicYearNotifier.value;
                Future<void> loadReportCardSynthese() async {
                  final row = await _dbService.getReportCard(
                    studentId: student.id,
                    className: selectedClass ?? '',
                    academicYear: effectiveYearForKey,
                    term: selectedTerm ?? '',
                  );

                  Future<Map<String, dynamic>> loadDisciplineSummary() async {
                    try {
                      final attendance = await _dbService.getAttendanceEvents(
                        academicYear: effectiveYearForKey,
                        className: (selectedClass ?? '').trim().isNotEmpty
                            ? selectedClass
                            : null,
                        studentId: student.id,
                      );
                      int absJust = 0;
                      int absInj = 0;
                      int retards = 0;
                      for (final e in attendance) {
                        final type = (e['type'] as String?) ?? '';
                        final justified =
                            (e['justified'] as num?)?.toInt() == 1;
                        if (type == 'absence') {
                          if (justified) {
                            absJust += 1;
                          } else {
                            absInj += 1;
                          }
                        } else if (type == 'retard') {
                          retards += 1;
                        }
                      }

                      final sanctionsRows = await _dbService.getSanctionEvents(
                        academicYear: effectiveYearForKey,
                        className: (selectedClass ?? '').trim().isNotEmpty
                            ? selectedClass
                            : null,
                        studentId: student.id,
                      );
                      final sanctionsLines = <String>[];
                      final limit = 10;
                      for (final e in sanctionsRows.take(limit)) {
                        final type = (e['type'] as String?) ?? '';
                        final desc = (e['description'] as String?) ?? '';
                        final date = DateTime.tryParse(
                          (e['date'] as String?) ?? '',
                        );
                        final d = date == null
                            ? ''
                            : DateFormat('dd/MM/yyyy').format(date);
                        final left = [
                          d,
                          type,
                        ].where((s) => s.trim().isNotEmpty);
                        final line = left.isEmpty
                            ? desc.trim()
                            : '${left.join(' - ')}: ${desc.trim()}';
                        if (line.trim().isNotEmpty)
                          sanctionsLines.add(line.trim());
                      }
                      if (sanctionsRows.length > limit) {
                        sanctionsLines.add(
                          '+${sanctionsRows.length - limit} autre(s) sanction(s)',
                        );
                      }
                      final sanctionsText = sanctionsLines.join('\n');
                      return {
                        'absJust': absJust,
                        'absInj': absInj,
                        'retards': retards,
                        'sanctionsText': sanctionsText,
                      };
                    } catch (_) {
                      return {
                        'absJust': 0,
                        'absInj': 0,
                        'retards': 0,
                        'sanctionsText': '',
                      };
                    }
                  }

                  final disciplineSummary = await loadDisciplineSummary();
                  if (row != null) {
                    _appreciationGeneraleController.text =
                        row['appreciation_generale'] ?? '';
                    // Pré-remplir la décision automatique si elle est vide ET qu'on est en fin d'année
                    final decisionExistante = row['decision'] ?? '';
                    if (decisionExistante.trim().isEmpty &&
                        isEndOfYear &&
                        _decisionAutomatique != null) {
                      _decisionController.text = _decisionAutomatique!;
                    } else {
                      _decisionController.text = decisionExistante;
                    }
                    _recommandationsController.text =
                        row['recommandations'] ?? '';
                    _forcesController.text = row['forces'] ?? '';
                    _pointsDevelopperController.text =
                        row['points_a_developper'] ?? '';
                    _sanctionsController.text = row['sanctions'] ?? '';
                    _absJustifieesController.text =
                        (row['attendance_justifiee'] ?? 0).toString();
                    _absInjustifieesController.text =
                        (row['attendance_injustifiee'] ?? 0).toString();
                    _retardsController.text = (row['retards'] ?? 0).toString();
                    _presencePercentController.text =
                        (row['presence_percent'] ?? 0.0).toString();
                    _conduiteController.text = row['conduite'] ?? '';
                    _faitAController.text = row['fait_a'] ?? '';
                    _leDateController.text = row['le_date'] ?? '';

                    final existingAbsJust =
                        int.tryParse(_absJustifieesController.text.trim()) ?? 0;
                    final existingAbsInj =
                        int.tryParse(_absInjustifieesController.text.trim()) ??
                        0;
                    final existingRetards =
                        int.tryParse(_retardsController.text.trim()) ?? 0;
                    final existingSanctions = _sanctionsController.text.trim();
                    final computedAbsJust =
                        (disciplineSummary['absJust'] as int?) ?? 0;
                    final computedAbsInj =
                        (disciplineSummary['absInj'] as int?) ?? 0;
                    final computedRetards =
                        (disciplineSummary['retards'] as int?) ?? 0;
                    final computedSanctions =
                        (disciplineSummary['sanctionsText'] as String?)
                            ?.trim() ??
                        '';

                    if (existingAbsJust == 0 && computedAbsJust > 0) {
                      _absJustifieesController.text = computedAbsJust
                          .toString();
                    }
                    if (existingAbsInj == 0 && computedAbsInj > 0) {
                      _absInjustifieesController.text = computedAbsInj
                          .toString();
                    }
                    if (existingRetards == 0 && computedRetards > 0) {
                      _retardsController.text = computedRetards.toString();
                    }
                    if (existingSanctions.isEmpty &&
                        computedSanctions.isNotEmpty) {
                      _sanctionsController.text = computedSanctions;
                    }
                    _applyAutoBehavioralFields(
                      moyenneGenerale,
                      moyenneAnnuelle,
                    );
                  } else {
                    // Si aucune donnée existante, pré-remplir avec la décision automatique seulement en fin d'année
                    if (isEndOfYear && _decisionAutomatique != null) {
                      _decisionController.text = _decisionAutomatique!;
                    }

                    final computedAbsJust =
                        (disciplineSummary['absJust'] as int?) ?? 0;
                    final computedAbsInj =
                        (disciplineSummary['absInj'] as int?) ?? 0;
                    final computedRetards =
                        (disciplineSummary['retards'] as int?) ?? 0;
                    final computedSanctions =
                        (disciplineSummary['sanctionsText'] as String?)
                            ?.trim() ??
                        '';
                    if (computedAbsJust > 0) {
                      _absJustifieesController.text = computedAbsJust
                          .toString();
                    }
                    if (computedAbsInj > 0) {
                      _absInjustifieesController.text = computedAbsInj
                          .toString();
                    }
                    if (computedRetards > 0) {
                      _retardsController.text = computedRetards.toString();
                    }
                    if (computedSanctions.isNotEmpty) {
                      _sanctionsController.text = computedSanctions;
                    }
                    _applyAutoBehavioralFields(
                      moyenneGenerale,
                      moyenneAnnuelle,
                    );
                  }
                }

                // Charger la synthèse depuis la base
                loadReportCardSynthese();

                Future<void> saveSynthese() async {
                  if (_isPeriodLocked()) return;
                  if (!SafeModeService.instance.isActionAllowed()) return;
                  final String effectiveYear =
                      (selectedAcademicYear != null &&
                          selectedAcademicYear!.isNotEmpty)
                      ? selectedAcademicYear!
                      : academicYearNotifier.value;
                  debugPrint(
                    '[GradesPage] saveSynthese -> student=${student.id} class=${selectedClass ?? ''} year=$effectiveYear term=${selectedTerm ?? ''}',
                  );
                  debugPrint(
                    '[GradesPage] saveSynthese fields: apprGen="' +
                        _appreciationGeneraleController.text +
                        '" decision="' +
                        _decisionController.text +
                        '" recos="' +
                        _recommandationsController.text +
                        '" forces="' +
                        _forcesController.text +
                        '" points="' +
                        _pointsDevelopperController.text +
                        '" sanctions="' +
                        _sanctionsController.text +
                        '" absJ=' +
                        _absJustifieesController.text +
                        ' absIJ=' +
                        _absInjustifieesController.text +
                        ' retards=' +
                        _retardsController.text +
                        ' presence=' +
                        _presencePercentController.text +
                        ' conduite="' +
                        _conduiteController.text +
                        '" faitA="' +
                        _faitAController.text +
                        '" leDate="' +
                        _leDateController.text +
                        '"',
                  );
                  await _dbService.insertOrUpdateReportCard(
                    studentId: student.id,
                    className: selectedClass ?? '',
                    academicYear: effectiveYear,
                    term: selectedTerm ?? '',
                    appreciationGenerale: _appreciationGeneraleController.text,
                    decision: _decisionController.text,
                    recommandations: _recommandationsController.text,
                    forces: _forcesController.text,
                    pointsADevelopper: _pointsDevelopperController.text,
                    faitA: _faitAController.text,
                    leDate: _leDateController.text,
                    moyenneGenerale: moyenneGenerale,
                    rang: rang,
                    nbEleves: nbEleves,
                    mention: mention,
                    moyennesParPeriode: moyennesParPeriode.toString(),
                    allTerms: allTerms.toString(),
                    moyenneGeneraleDeLaClasse: moyenneGeneraleDeLaClasse,
                    moyenneLaPlusForte: moyenneLaPlusForte,
                    moyenneLaPlusFaible: moyenneLaPlusFaible,
                    moyenneAnnuelle: moyenneAnnuelle,
                    sanctions: _sanctionsController.text,
                    attendanceJustifiee: int.tryParse(
                      _absJustifieesController.text,
                    ),
                    attendanceInjustifiee: int.tryParse(
                      _absInjustifieesController.text,
                    ),
                    retards: int.tryParse(_retardsController.text),
                    presencePercent: double.tryParse(
                      _presencePercentController.text,
                    ),
                    conduite: _conduiteController.text,
                  );
                }

                // Sauvegarde automatique sur changement de chaque champ texte
                for (final ctrl in [
                  _appreciationGeneraleController,
                  _decisionController,
                  _recommandationsController,
                  _forcesController,
                  _pointsDevelopperController,
                  _sanctionsController,
                  _absJustifieesController,
                  _absInjustifieesController,
                  _retardsController,
                  _presencePercentController,
                  _conduiteController,
                  _faitAController,
                  _leDateController,
                ]) {
                  ctrl.addListener(() {
                    if (_isPeriodLocked()) return;
                    if (!SafeModeService.instance.isActionAllowed()) return;
                    saveSynthese();
                  });
                }

                // Auto-archivage non sollicité au rendu
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (_isPeriodLocked()) return;
                  final String effectiveYear =
                      (selectedAcademicYear != null &&
                          selectedAcademicYear!.isNotEmpty)
                      ? selectedAcademicYear!
                      : academicYearNotifier.value;
                  final synthese = {
                    'appreciation_generale':
                        _appreciationGeneraleController.text,
                    'decision': _decisionController.text,
                    'recommandations': _recommandationsController.text,
                    'forces': _forcesController.text,
                    'points_a_developper': _pointsDevelopperController.text,
                    'fait_a': _faitAController.text,
                    'le_date': _leDateController.text,
                    'moyenne_generale': moyenneGenerale,
                    'rang': rang,
                    'nb_eleves': nbEleves,
                    'mention': mention,
                    'moyennes_par_periode': moyennesParPeriode.toString(),
                    'all_terms': allTerms.toString(),
                    'moyenne_annuelle': moyenneAnnuelle,
                    'sanctions': _sanctionsController.text,
                    'attendance_justifiee':
                        int.tryParse(_absJustifieesController.text) ?? 0,
                    'attendance_injustifiee':
                        int.tryParse(_absInjustifieesController.text) ?? 0,
                    'retards': int.tryParse(_retardsController.text) ?? 0,
                    'presence_percent':
                        double.tryParse(_presencePercentController.text) ?? 0.0,
                    'conduite': _conduiteController.text,
                    'moyenne_generale_classe': moyenneGeneraleDeLaClasse,
                    'moyenne_la_plus_forte': moyenneLaPlusForte,
                    'moyenne_la_plus_faible': moyenneLaPlusFaible,
                  };

                  await _dbService.insertOrUpdateReportCard(
                    studentId: student.id,
                    className: selectedClass ?? '',
                    academicYear: effectiveYear,
                    term: selectedTerm ?? '',
                    appreciationGenerale: _appreciationGeneraleController.text,
                    decision: _decisionController.text,
                    recommandations: _recommandationsController.text,
                    forces: _forcesController.text,
                    pointsADevelopper: _pointsDevelopperController.text,
                    faitA: _faitAController.text,
                    leDate: _leDateController.text,
                    moyenneGenerale: moyenneGenerale,
                    rang: rang,
                    nbEleves: nbEleves,
                    mention: mention,
                    moyennesParPeriode: moyennesParPeriode.toString(),
                    allTerms: allTerms.toString(),
                    moyenneGeneraleDeLaClasse: moyenneGeneraleDeLaClasse,
                    moyenneLaPlusForte: moyenneLaPlusForte,
                    moyenneLaPlusFaible: moyenneLaPlusFaible,
                    moyenneAnnuelle: moyenneAnnuelle,
                    sanctions: _sanctionsController.text,
                    attendanceJustifiee: int.tryParse(
                      _absJustifieesController.text,
                    ),
                    attendanceInjustifiee: int.tryParse(
                      _absInjustifieesController.text,
                    ),
                    retards: int.tryParse(_retardsController.text),
                    presencePercent: double.tryParse(
                      _presencePercentController.text,
                    ),
                    conduite: _conduiteController.text,
                  );

                  final professeurs = <String, String>{
                    for (final s in subjectNames)
                      s: (_profControllers[s]?.text ?? '-').trim().isNotEmpty
                          ? _profControllers[s]!.text
                          : '-',
                  };
                  final appreciations = <String, String>{
                    for (final s in subjectNames)
                      s:
                          (_appreciationControllers[s]?.text ?? '-')
                              .trim()
                              .isNotEmpty
                          ? _appreciationControllers[s]!.text
                          : '-',
                  };
                  final moyennesClasse = <String, String>{
                    for (final s in subjectNames)
                      s:
                          (_moyClasseControllers[s]?.text ?? '-')
                              .trim()
                              .isNotEmpty
                          ? _moyClasseControllers[s]!.text
                          : '-',
                  };

                  await _dbService.archiveSingleReportCard(
                    studentId: student.id,
                    className: selectedClass ?? '',
                    academicYear: selectedAcademicYear ?? '',
                    term: selectedTerm ?? '',
                    grades: studentGrades,
                    professeurs: professeurs,
                    appreciations: appreciations,
                    moyennesClasse: moyennesClasse,
                    synthese: synthese,
                  );
                });
                return Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.blue.shade200, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.shade100.withOpacity(0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // En-tête administratif (aperçu) : Ministère / République / Devise / Inspection / Direction
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child:
                                    (info.ministry != null &&
                                        info.ministry!.trim().isNotEmpty)
                                    ? (maxW > 0
                                          ? SizedBox(
                                              width: maxW,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (parts.isNotEmpty)
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        left: padFirst,
                                                      ),
                                                      child: Text(
                                                        parts[0],
                                                        style: adminBold,
                                                      ),
                                                    ),
                                                  if (parts.length > 1)
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        left: padSecond,
                                                      ),
                                                      child: Text(
                                                        parts[1],
                                                        style: adminBold,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            )
                                          : Text(
                                              info.ministry!.toUpperCase(),
                                              style: adminBold,
                                            ))
                                    : const SizedBox.shrink(),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      (info.republic ?? 'RÉPUBLIQUE')
                                          .toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                    if ((info.republicMotto ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          info.republicMotto!,
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: secondaryColor,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: (info.inspection ?? '').trim().isNotEmpty
                                    ? Text(
                                        'Inspection: ${info.inspection}',
                                        style: TextStyle(color: secondaryColor),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child:
                                      (info.educationDirection ?? '')
                                          .trim()
                                          .isNotEmpty
                                      ? Text(
                                          "Direction de l'enseignement: ${info.educationDirection}",
                                          style: TextStyle(
                                            color: secondaryColor,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          ),
                          if ((student.photoPath ?? '').trim().isNotEmpty &&
                              File(student.photoPath!).existsSync())
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.blue.shade100,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.file(
                                    File(student.photoPath!),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 4),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // En-tête établissement amélioré
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (info.logoPath != null &&
                              File(info.logoPath!).existsSync())
                            Padding(
                              padding: const EdgeInsets.only(right: 24),
                              child: Image.file(
                                File(info.logoPath!),
                                height: 80,
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  info.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 30,
                                    color: mainColor,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // Année (sous le nom)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'Année académique : $schoolYear',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: secondaryColor,
                                    ),
                                  ),
                                ),
                                // if (info.director.isNotEmpty) Text('Directeur : ${info.director}', style: TextStyle(fontSize: 15, color: secondaryColor)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _telEtabController,
                                        enabled: false,
                                        decoration: InputDecoration(
                                          hintText: 'Téléphone',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: secondaryColor,
                                        ),
                                        onChanged: (val) {},
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _mailEtabController,
                                        enabled: false,
                                        decoration: InputDecoration(
                                          hintText: 'Email',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: secondaryColor,
                                        ),
                                        onChanged: (val) {},
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _webEtabController,
                                        enabled: false,
                                        decoration: InputDecoration(
                                          hintText: 'Site web',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: secondaryColor,
                                        ),
                                        onChanged: (val) {},
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'BULLETIN SCOLAIRE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: mainColor,
                                letterSpacing: 2,
                              ),
                            ),
                            if ((info.motto ?? '').isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                info.motto!,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: mainColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Bloc élève (matricule, nom, prénom, sexe, date/lieu naissance, statut)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Matricule : ${student.matricule ?? '-'}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Nom : $nom',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Prénom : $prenom',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Sexe : $sexe',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Date et lieu de naissance : ${fmtDate(student.dateOfBirth)}${(student.placeOfBirth ?? '').trim().isNotEmpty ? ' à ${student.placeOfBirth!.trim()}' : ''}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Statut : ${student.status}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                ),
                                const Expanded(child: SizedBox()),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.class_, color: mainColor),
                            const SizedBox(width: 8),
                            Text(
                              'Classe : ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: mainColor,
                              ),
                            ),
                            Text(
                              student.className,
                              style: TextStyle(color: secondaryColor),
                            ),
                            const Spacer(),
                            Text(
                              'Effectif : ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: mainColor,
                              ),
                            ),
                            Text(
                              '$nbEleves',
                              style: TextStyle(color: secondaryColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Tableau matières (groupé par catégories si disponibles)
                      ...() {
                        // Regrouper les matières par catégorie
                        final Map<String?, List<String>> grouped = {};
                        for (final c in subjects) {
                          grouped
                              .putIfAbsent(c.categoryId, () => [])
                              .add(c.name);
                        }
                        final bool hasCategories = grouped.keys.any(
                          (k) => k != null,
                        );

                        Widget buildTableForSubjects(
                          List<String> names, {
                          bool showTotals = true,
                        }) {
                          // Compact styles for preview to reduce height
                          const cellTextStyle = TextStyle(fontSize: 12);
                          const headerTextStyle = TextStyle(
                            fontWeight: FontWeight.bold,
                          );

                          // Charger coefficients de matière définis au niveau de la classe
                          final Map<String, double> classWeights = {};
                          String _splitHeaderWords(String s) =>
                              s.trim().split(RegExp(r'\s+')).join('\n');
                          // Ce FutureBuilder garantit que les coefficients sont récupérés
                          return FutureBuilder<Map<String, double>>(
                            future: _dbService.getClassSubjectCoefficients(
                              selectedClass ?? student.className,
                              selectedAcademicYear ?? effectiveYear,
                            ),
                            builder: (context, wSnapshot) {
                              final weights = wSnapshot.data ?? {};
                              return Table(
                                border: TableBorder.all(
                                  color: Colors.blue.shade100,
                                ),
                                columnWidths: const {
                                  0: FlexColumnWidth(2),
                                  1: FlexColumnWidth(2),
                                  2: FlexColumnWidth(),
                                  3: FlexColumnWidth(),
                                  4: FlexColumnWidth(),
                                  5: FlexColumnWidth(), // Coeff.
                                  6: FlexColumnWidth(1.2), // Moyenne Generale
                                  7: FlexColumnWidth(
                                    1.4,
                                  ), // Moyenne Generale Coef
                                  8: FlexColumnWidth(1.2), // Moy. classe
                                  9: FlexColumnWidth(2), // Appréciation
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: tableHeaderBg,
                                    ),
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'Matière',
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'Professeur(s)',
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'Sur',
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'Devoir',
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'Composition',
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'Coeff.',
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          _splitHeaderWords('Moyenne Generale'),
                                          textAlign: TextAlign.center,
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          _splitHeaderWords(
                                            'Moyenne Generale Coef',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'Moy. classe',
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'Appréciation prof.',
                                          style: headerTextStyle.copyWith(
                                            color: tableHeaderText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  ...names.map((subject) {
                                    // Ensure each row has fixed intrinsic height to avoid border row offset assertions
                                    final subjectGrades = studentGrades
                                        .where((g) => g.subject == subject)
                                        .toList();
                                    final devoirs = subjectGrades
                                        .where((g) => g.type == 'Devoir')
                                        .toList();
                                    final compositions = subjectGrades
                                        .where((g) => g.type == 'Composition')
                                        .toList();
                                    final devoirAvgOn20 = devoirs.isNotEmpty
                                        ? PdfService.computeWeightedAverageOn20(
                                            devoirs,
                                          )
                                        : null;
                                    final compoAvgOn20 = compositions.isNotEmpty
                                        ? PdfService.computeWeightedAverageOn20(
                                            compositions,
                                          )
                                        : null;
                                    final devoirNote = devoirAvgOn20 != null
                                        ? devoirAvgOn20.toStringAsFixed(2)
                                        : '-';
                                    final devoirSur = devoirAvgOn20 != null
                                        ? '20'
                                        : '-';
                                    final compoNote = compoAvgOn20 != null
                                        ? compoAvgOn20.toStringAsFixed(2)
                                        : '-';
                                    final compoSur = compoAvgOn20 != null
                                        ? '20'
                                        : '-';
                                    final moyenneMatiere =
                                        PdfService.computeWeightedAverageOn20([
                                          ...devoirs,
                                          ...compositions,
                                        ]);

                                    // Trouver le professeur et pré-remplir le champ
                                    final classInfo = classes.firstWhere(
                                      (c) => c.name == selectedClass,
                                      orElse: () => Class.empty(),
                                    );
                                    final titulaire =
                                        classInfo.titulaire ?? '-';
                                    final course = subjects.firstWhere(
                                      (c) => c.name == subject,
                                      orElse: () => Course.empty(),
                                    );
                                    String profName = '';
                                    if (course.id.isNotEmpty) {
                                      profName =
                                          _assignedTeacherByCourseId[course
                                              .id] ??
                                          '';
                                    }
                                    if (profName.trim().isEmpty) {
                                      profName = titulaire;
                                    }
                                    if ((_profControllers[subject]?.text ?? '')
                                        .trim()
                                        .isEmpty) {
                                      _profControllers[subject]?.text =
                                          profName;
                                    }

                                    final classSubjectAverage =
                                        _calculateClassAverageForSubject(
                                          subject,
                                        );
                                    // Toujours forcer la mise à jour avec la valeur fraîche pour garantir la synchro
                                    _moyClasseControllers[subject]?.text =
                                        classSubjectAverage != null
                                        ? classSubjectAverage.toStringAsFixed(2)
                                        : '-';
                                    final totalCoeff =
                                        [...devoirs, ...compositions]
                                            .where(
                                              (g) =>
                                                  g.maxValue > 0 &&
                                                  g.coefficient > 0,
                                            )
                                            .fold<double>(
                                              0.0,
                                              (s, g) => s + g.coefficient,
                                            );
                                    final double subjectWeight =
                                        (weights[subject] ?? totalCoeff);
                                    final double moyenneGeneraleCoef =
                                        moyenneMatiere * subjectWeight;
                                    // Appréciation automatique calculée dynamiquement pour le hintText
                                    final autoAppr = _getAutomaticAppreciation(
                                      moyenneMatiere,
                                    );

                                    return TableRow(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                      ),
                                      children: [
                                        SizedBox(
                                          height: 44,
                                          child: Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Text(
                                              subject,
                                              style: TextStyle(
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 44,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: TextField(
                                              controller:
                                                  _profControllers[subject],
                                              enabled:
                                                  SafeModeService.instance
                                                      .isActionAllowed() &&
                                                  !_isPeriodLocked(),
                                              decoration: InputDecoration(
                                                hintText: 'Professeur',
                                                hintStyle: TextStyle(
                                                  color: secondaryColor,
                                                  fontSize: 10,
                                                ),
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                fillColor: Colors.white,
                                                filled: true,
                                              ),
                                              style: TextStyle(
                                                color: secondaryColor,
                                                fontSize: 12,
                                              ),
                                              onChanged: (_) =>
                                                  _saveSubjectAppreciationPersistently(
                                                    subject,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 44,
                                          child: Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Text(
                                              devoirSur != '-'
                                                  ? devoirSur
                                                  : compoSur,
                                              style: TextStyle(
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 44,
                                          child: Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Text(
                                              devoirNote,
                                              style: TextStyle(
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 36,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Text(
                                              compoNote,
                                              style: cellTextStyle.copyWith(
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 36,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Text(
                                              subjectWeight > 0
                                                  ? subjectWeight
                                                        .toStringAsFixed(2)
                                                  : '-',
                                              style: cellTextStyle.copyWith(
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 36,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Text(
                                              moyenneMatiere.toStringAsFixed(2),
                                              style: cellTextStyle.copyWith(
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 36,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Text(
                                              moyenneGeneraleCoef
                                                  .toStringAsFixed(2),
                                              style: cellTextStyle.copyWith(
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 36,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: TextField(
                                              controller:
                                                  _moyClasseControllers[subject],
                                              enabled:
                                                  SafeModeService.instance
                                                      .isActionAllowed() &&
                                                  !_isPeriodLocked(),
                                              decoration: InputDecoration(
                                                hintText: 'Moy. classe',
                                                hintStyle: TextStyle(
                                                  color: secondaryColor,
                                                  fontSize: 10,
                                                ),
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                fillColor: Colors.white,
                                                filled: true,
                                              ),
                                              style: TextStyle(
                                                color: secondaryColor,
                                                fontSize: 12,
                                              ),
                                              onChanged: (_) =>
                                                  _saveSubjectAppreciationPersistently(
                                                    subject,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 44,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: TextField(
                                              controller:
                                                  _appreciationControllers[subject],
                                              enabled:
                                                  SafeModeService.instance
                                                      .isActionAllowed() &&
                                                  !_isPeriodLocked(),
                                              decoration: InputDecoration(
                                                hintText: autoAppr,
                                                hintStyle: TextStyle(
                                                  color: secondaryColor
                                                      .withOpacity(0.5),
                                                  fontSize: 10,
                                                ),
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                fillColor: Colors.white,
                                                filled: true,
                                              ),
                                              maxLines: 2,
                                              style: TextStyle(
                                                color: secondaryColor,
                                                fontSize: 12,
                                              ),
                                              onChanged: (_) =>
                                                  _saveSubjectAppreciationPersistently(
                                                    subject,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                  // Ligne des totaux (unique si showTotals)
                                  if (showTotals)
                                    (() {
                                      double sumCoeff = 0.0;
                                      double sumPtsEleve =
                                          0.0; // Σ (moyenne_matiere * coeff_matiere)
                                      double sumPtsClasse =
                                          0.0; // Σ (moy_classe_matiere * coeff_matiere)
                                      for (final subject in names) {
                                        final subjectGrades = studentGrades
                                            .where((g) => g.subject == subject)
                                            .toList();
                                        final devoirs = subjectGrades
                                            .where((g) => g.type == 'Devoir')
                                            .toList();
                                        final compositions = subjectGrades
                                            .where(
                                              (g) => g.type == 'Composition',
                                            )
                                            .toList();
                                        double total = 0.0;
                                        double totalCoeff = 0.0;
                                        for (final g in [
                                          ...devoirs,
                                          ...compositions,
                                        ]) {
                                          if (g.maxValue > 0 &&
                                              g.coefficient > 0) {
                                            total +=
                                                ((g.value / g.maxValue) * 20) *
                                                g.coefficient;
                                            totalCoeff += g.coefficient;
                                          }
                                        }
                                        final moyenneMatiere = totalCoeff > 0
                                            ? (total / totalCoeff)
                                            : 0.0;
                                        final subjectWeight =
                                            (weights[subject] ?? totalCoeff);
                                        sumCoeff += subjectWeight;
                                        // Points élève = moyenne matière * coeff matière
                                        if (subjectGrades.isNotEmpty)
                                          sumPtsEleve +=
                                              moyenneMatiere * subjectWeight;
                                        final txt =
                                            (_moyClasseControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim();
                                        final val = double.tryParse(
                                          txt.replaceAll(',', '.'),
                                        );
                                        if (val != null) {
                                          // Points classe = moyenne_classe * coeff matière
                                          sumPtsClasse += val * subjectWeight;
                                        }
                                      }
                                      final bool sumOk =
                                          (sumCoeff - 20).abs() < 1e-6;
                                      return TableRow(
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                        ),
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Text(
                                              'TOTAUX',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: mainColor,
                                              ),
                                            ),
                                          ),
                                          SizedBox.shrink(),
                                          SizedBox.shrink(),
                                          SizedBox.shrink(),
                                          SizedBox.shrink(),
                                          Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Text(
                                              sumCoeff > 0
                                                  ? sumCoeff.toStringAsFixed(2)
                                                  : '0',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: sumOk
                                                    ? secondaryColor
                                                    : Colors.red,
                                              ),
                                            ),
                                          ),
                                          SizedBox.shrink(),
                                          Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Text(
                                              sumPtsEleve > 0
                                                  ? sumPtsEleve.toStringAsFixed(
                                                      2,
                                                    )
                                                  : '0',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Text(
                                              sumPtsClasse > 0
                                                  ? sumPtsClasse
                                                        .toStringAsFixed(2)
                                                  : '0',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ),
                                          SizedBox.shrink(),
                                        ],
                                      );
                                    })(),
                                ],
                              );
                            },
                          );
                        }

                        if (!hasCategories) {
                          return [buildTableForSubjects(subjectNames)];
                        }
                        // Ordonner les sections selon l'ordre des catégories, puis Non classée
                        final List<String?> orderedKeys = [];
                        for (final cat in categories) {
                          if (grouped.containsKey(cat.id))
                            orderedKeys.add(cat.id);
                        }
                        if (grouped.containsKey(null)) orderedKeys.add(null);

                        final List<Widget> sections = [];
                        for (final key in orderedKeys) {
                          final bool isUncat = key == null;
                          final String label = isUncat
                              ? 'Matières non classées'
                              : 'Matières ' +
                                    categories
                                        .firstWhere(
                                          (c) => c.id == key,
                                          orElse: () => Category.empty(),
                                        )
                                        .name
                                        .toLowerCase();
                          final Color badge = isUncat
                              ? Colors.blueGrey
                              : Color(
                                  int.parse(
                                    (categories
                                            .firstWhere(
                                              (c) => c.id == key,
                                              orElse: () => Category.empty(),
                                            )
                                            .color)
                                        .replaceFirst('#', '0xff'),
                                  ),
                                );
                          sections.add(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: badge,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: secondaryColor,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${grouped[key]!.length} matière(s)',
                                    style: TextStyle(
                                      color: secondaryColor.withOpacity(0.7),
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
                            ),
                          );
                          sections.add(const SizedBox(height: 12));
                        }
                        // Un seul TOTAUX global additionnant toutes les matières
                        sections.add(
                          FutureBuilder<Map<String, double>>(
                            future: _dbService.getClassSubjectCoefficients(
                              selectedClass ?? student.className,
                              selectedAcademicYear ?? effectiveYear,
                            ),
                            builder: (context, wSnapshot) {
                              final weights = wSnapshot.data ?? {};
                              double sumCoeff = 0.0;
                              double sumPtsEleve = 0.0;
                              double sumPtsClasse = 0.0;
                              for (final subject in subjectNames) {
                                final subjectGrades = studentGrades
                                    .where((g) => g.subject == subject)
                                    .toList();
                                final devoirs = subjectGrades
                                    .where((g) => g.type == 'Devoir')
                                    .toList();
                                final compositions = subjectGrades
                                    .where((g) => g.type == 'Composition')
                                    .toList();
                                double total = 0.0;
                                double totalCoeff = 0.0;
                                for (final g in [...devoirs, ...compositions]) {
                                  if (g.maxValue > 0 && g.coefficient > 0) {
                                    total +=
                                        ((g.value / g.maxValue) * 20) *
                                        g.coefficient;
                                    totalCoeff += g.coefficient;
                                  }
                                }
                                final moyenneMatiere = totalCoeff > 0
                                    ? (total / totalCoeff)
                                    : 0.0;
                                final subjectWeight =
                                    (weights[subject] ?? totalCoeff);
                                sumCoeff += subjectWeight;
                                if (subjectGrades.isNotEmpty)
                                  sumPtsEleve += moyenneMatiere * subjectWeight;
                                final txt =
                                    (_moyClasseControllers[subject]?.text ?? '')
                                        .trim();
                                final val = double.tryParse(
                                  txt.replaceAll(',', '.'),
                                );
                                if (val != null)
                                  sumPtsClasse += val * subjectWeight;
                              }
                              final bool sumOk = (sumCoeff - 20).abs() < 1e-6;
                              return Table(
                                border: TableBorder.all(
                                  color: Colors.blue.shade100,
                                ),
                                columnWidths: const {
                                  0: FlexColumnWidth(2),
                                  1: FlexColumnWidth(2),
                                  2: FlexColumnWidth(),
                                  3: FlexColumnWidth(),
                                  4: FlexColumnWidth(),
                                  5: FlexColumnWidth(),
                                  6: FlexColumnWidth(1.2),
                                  7: FlexColumnWidth(1.4),
                                  8: FlexColumnWidth(1.2),
                                  9: FlexColumnWidth(2),
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                    ),
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'TOTAUX',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: mainColor,
                                          ),
                                        ),
                                      ),
                                      SizedBox.shrink(),
                                      SizedBox.shrink(),
                                      SizedBox.shrink(),
                                      SizedBox.shrink(),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          sumCoeff > 0
                                              ? sumCoeff.toStringAsFixed(2)
                                              : '0',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: sumOk
                                                ? secondaryColor
                                                : Colors.red,
                                          ),
                                        ),
                                      ),
                                      SizedBox.shrink(),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          sumPtsEleve > 0
                                              ? sumPtsEleve.toStringAsFixed(2)
                                              : '0',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          sumPtsClasse > 0
                                              ? sumPtsClasse.toStringAsFixed(2)
                                              : '0',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                      SizedBox.shrink(),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                        return sections;
                      }(),
                      const SizedBox(height: 24),
                      // Synthèse : tableau des moyennes par période
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Moyennes par $_periodMode',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: mainColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<Map<String, Map<String, num>>>(
                              future: _computeRankPerTermForStudentUI(
                                student,
                                allTerms,
                              ),
                              builder: (context, snapshot) {
                                final rankPerTerm = snapshot.data ?? {};
                                return Table(
                                  border: TableBorder.all(
                                    color: Colors.blue.shade100,
                                  ),
                                  columnWidths: {
                                    for (int i = 0; i < allTerms.length; i++)
                                      i: FlexColumnWidth(),
                                  },
                                  children: [
                                    TableRow(
                                      decoration: BoxDecoration(
                                        color: tableHeaderBg,
                                      ),
                                      children: List.generate(allTerms.length, (
                                        i,
                                      ) {
                                        final label = allTerms[i];
                                        return Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: tableHeaderText,
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                    TableRow(
                                      children: List.generate(allTerms.length, (
                                        i,
                                      ) {
                                        // Determine if this column corresponds to the currently selected term
                                        final isSelected =
                                            selectedTerm != null &&
                                            allTerms[i] == selectedTerm;
                                        // Compute previous period index
                                        final prevIndex = i - 1;
                                        final prevAvgAvailable =
                                            prevIndex >= 0 &&
                                            prevIndex <
                                                moyennesParPeriode.length &&
                                            moyennesParPeriode[prevIndex] !=
                                                null;
                                        final mainAvg =
                                            (i < moyennesParPeriode.length &&
                                                moyennesParPeriode[i] != null)
                                            ? moyennesParPeriode[i]!
                                                  .toStringAsFixed(2)
                                            : '-';
                                        final prevText = prevAvgAvailable
                                            ? moyennesParPeriode[prevIndex]!
                                                  .toStringAsFixed(2)
                                            : null;
                                        final term = allTerms[i];
                                        final r = rankPerTerm[term];
                                        // If moyennesParPeriode n'a pas la valeur (car 'grades' ne contient que la période sélectionnée),
                                        // utilise la moyenne calculée côté Future (avg) pour cette période
                                        String effectiveAvg = mainAvg;
                                        if (isSelected) {
                                          effectiveAvg = moyenneGenerale
                                              .toStringAsFixed(2);
                                        } else if (mainAvg == '-' &&
                                            r != null &&
                                            (r['avg'] ?? 0) > 0) {
                                          effectiveAvg = (r['avg'] as num)
                                              .toStringAsFixed(2);
                                        }
                                        String suffix = '';
                                        if (nbEleves > 0 &&
                                            effectiveAvg != '-') {
                                          suffix = ' (rang $rang/$nbEleves)';
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              RichText(
                                                text: TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: effectiveAvg,
                                                      style: TextStyle(
                                                        color: secondaryColor,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    if (suffix.isNotEmpty)
                                                      TextSpan(
                                                        text: ' ' + suffix,
                                                        style: const TextStyle(
                                                          color: Colors.grey,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              if (isSelected &&
                                                  prevText != null) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Précédent: ' + prevText,
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Assiduité (de retour à sa place sous le bloc moyennes par période)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ASSIDUITÉ ET CONDUITE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: mainColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _presencePercentController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      labelText: 'PRÉSENCE :',
                                      labelStyle: TextStyle(
                                        color: secondaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      hintText: ':',
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _retardsController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      labelText: 'RETARDS :',
                                      labelStyle: TextStyle(
                                        color: secondaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      hintText: ':',
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _absJustifieesController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      labelText: 'ABS. JUSTIFIÉES :',
                                      labelStyle: TextStyle(
                                        color: secondaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      hintText: ':',
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _absInjustifieesController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      labelText: 'ABS. INJUSTIFIÉES :',
                                      labelStyle: TextStyle(
                                        color: secondaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      hintText: ':',
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _conduiteController,
                              enabled:
                                  SafeModeService.instance.isActionAllowed() &&
                                  !_isPeriodLocked(),
                              decoration: InputDecoration(
                                labelText: 'PUNITIONS :',
                                labelStyle: TextStyle(
                                  color: secondaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                hintText: ':',
                                hintStyle: TextStyle(
                                  color: Colors.blueGrey.shade400,
                                  fontWeight: FontWeight.bold,
                                ),
                                filled: true,
                                fillColor: Colors.blueGrey.shade50,
                              ),
                              maxLines: 2,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'SANCTIONS :',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: secondaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _sanctionsController,
                              enabled:
                                  SafeModeService.instance.isActionAllowed() &&
                                  !_isPeriodLocked(),
                              decoration: InputDecoration(
                                hintText: 'Saisir les sanctions',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                hintStyle: TextStyle(
                                  color: secondaryColor.withOpacity(0.7),
                                ),
                                filled: true,
                                fillColor: Colors.blueGrey.shade50,
                              ),
                              style: TextStyle(
                                color: secondaryColor,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Synthèse générale
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: FutureBuilder<Map<String, dynamic>>(
                                future: _prepareReportCardData(student),
                                builder: (context, statsSnapshot) {
                                  double moyenneEleve = moyenneGenerale;
                                  double? moyenneClasse =
                                      moyenneGeneraleDeLaClasse;
                                  double? moyenneMax = moyenneLaPlusForte;
                                  double? moyenneMin = moyenneLaPlusFaible;
                                  double? moyenneAnn = moyenneAnnuelle;
                                  int rangValue = rang;
                                  int nbElevesValue = nbEleves;
                                  bool exaequoValue = false;
                                  String mentionValue = mention;
                                  List<double?> moyennesPeriodes =
                                      List<double?>.from(moyennesParPeriode);
                                  String selectedTermValue = selectedTerm ?? '';

                                  if (statsSnapshot.hasData) {
                                    final stats = statsSnapshot.data!;
                                    moyenneEleve =
                                        (stats['moyenneGenerale'] as double?) ??
                                        moyenneEleve;
                                    moyenneClasse =
                                        stats['moyenneGeneraleDeLaClasse']
                                            as double? ??
                                        moyenneClasse;
                                    moyenneMax =
                                        stats['moyenneLaPlusForte']
                                            as double? ??
                                        moyenneMax;
                                    moyenneMin =
                                        stats['moyenneLaPlusFaible']
                                            as double? ??
                                        moyenneMin;
                                    moyenneAnn =
                                        stats['moyenneAnnuelle'] as double? ??
                                        moyenneAnn;
                                    rangValue =
                                        (stats['rang'] as int?) ?? rangValue;
                                    nbElevesValue =
                                        (stats['nbEleves'] as int?) ??
                                        nbElevesValue;
                                    exaequoValue =
                                        (stats['exaequo'] as bool?) ??
                                        exaequoValue;
                                    mentionValue =
                                        (stats['mention'] as String?) ??
                                        mentionValue;
                                    moyennesPeriodes =
                                        (stats['moyennesParPeriode'] as List)
                                            .cast<double?>();
                                    selectedTermValue =
                                        (stats['selectedTerm'] as String?) ??
                                        selectedTermValue;
                                  }

                                  // Affiche la moyenne annuelle/ rang annuel uniquement en fin de période
                                  bool _isEndOfYear(
                                    String periodLabel,
                                    String selectedTerm,
                                  ) {
                                    final pl = periodLabel.toLowerCase();
                                    final st = selectedTerm.toLowerCase();
                                    if (pl.contains('trimestre'))
                                      return st.contains('3');
                                    if (pl.contains('semestre'))
                                      return st.contains('2');
                                    return false;
                                  }

                                  final bool showAnnual = _isEndOfYear(
                                    periodLabel,
                                    selectedTermValue,
                                  );

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Moyenne de l\'élève : ${moyenneEleve.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: mainColor,
                                          fontSize: 18,
                                        ),
                                      ),
                                      if (moyenneClasse != null)
                                        Text(
                                          'Moyenne de la classe : ${moyenneClasse.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      if (moyenneMax != null)
                                        Text(
                                          'Moyenne la plus forte : ${moyenneMax.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      if (moyenneMin != null)
                                        Text(
                                          'Moyenne la plus faible : ${moyenneMin.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      if (showAnnual && moyenneAnn != null)
                                        Text(
                                          'Moyenne annuelle : ${moyenneAnn.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      // Moyenne annuelle de la classe
                                      if (showAnnual &&
                                          statsSnapshot.hasData &&
                                          (statsSnapshot
                                                      .data!['moyenneAnnuelleClasse']
                                                  as double?) !=
                                              null)
                                        Text(
                                          'Moyenne annuelle de la classe : ${(statsSnapshot.data!['moyenneAnnuelleClasse'] as double).toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      // Rang annuel
                                      if (showAnnual &&
                                          statsSnapshot.hasData &&
                                          (statsSnapshot.data!['rangAnnuel']
                                                  as int?) !=
                                              null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              'Rang annuel : ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: secondaryColor,
                                              ),
                                            ),
                                            Text(
                                              '${(statsSnapshot.data!['rangAnnuel'] as int)} / ${(statsSnapshot.data!['nbElevesAnnuel'] as int?) ?? nbElevesValue}',
                                              style: TextStyle(
                                                color: secondaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (moyennesPeriodes.length > 1 &&
                                          moyennesPeriodes.any(
                                            (m) => m != null,
                                          )) ...[
                                        const SizedBox(height: 8),
                                      ],
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            'Rang : ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: secondaryColor,
                                            ),
                                          ),
                                          Text(
                                            exaequoValue
                                                ? '$rangValue (ex æquo) / $nbElevesValue'
                                                : '$rangValue / $nbElevesValue',
                                            style: TextStyle(
                                              color: secondaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            'Mention : ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: secondaryColor,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: mainColor,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              mentionValue,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'APPRÉCIATION GÉNÉRALE :',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: secondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _appreciationGeneraleController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Saisir une appréciation générale',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    maxLines: 2,
                                    style: TextStyle(
                                      color: secondaryColor,
                                      fontSize: 14,
                                    ),
                                    onChanged: (_) =>
                                        _saveReportCardSynthesisPersistently(),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'DÉCISION DU CONSEIL DE CLASSE :',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                      // Bouton de réinitialisation seulement en fin d'année
                                      if (isEndOfYear &&
                                          _decisionAutomatique != null)
                                        IconButton(
                                          onPressed:
                                              (SafeModeService.instance
                                                      .isActionAllowed() &&
                                                  !_isPeriodLocked())
                                              ? () {
                                                  _decisionController.text =
                                                      _decisionAutomatique!;
                                                  _saveReportCardSynthesisPersistently();
                                                }
                                              : null,
                                          icon: Icon(
                                            Icons.refresh,
                                            size: 18,
                                            color: mainColor,
                                          ),
                                          tooltip:
                                              'Réinitialiser à la décision automatique',
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Indicateur de décision automatique seulement en fin d'année
                                  if (isEndOfYear &&
                                      _decisionAutomatique != null &&
                                      _decisionController.text ==
                                          _decisionAutomatique)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.blue.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.auto_awesome,
                                            size: 16,
                                            color: Colors.blue.shade600,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Décision automatique basée sur la moyenne annuelle (${moyenneAnnuelle?.toStringAsFixed(2) ?? moyenneGenerale.toStringAsFixed(2)})',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue.shade700,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  TextField(
                                    controller: _decisionController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      hintText: 'Saisir la décision',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    style: TextStyle(
                                      color: secondaryColor,
                                      fontSize: 14,
                                    ),
                                    onChanged: (_) =>
                                        _saveReportCardSynthesisPersistently(),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'RECOMMANDATIONS :',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: secondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _recommandationsController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      hintText: 'Saisir les recommandations',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    maxLines: 2,
                                    style: TextStyle(
                                      color: secondaryColor,
                                      fontSize: 14,
                                    ),
                                    onChanged: (_) =>
                                        _saveReportCardSynthesisPersistently(),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'FORCES :',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: secondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _forcesController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      hintText: 'Saisir les forces',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    maxLines: 2,
                                    style: TextStyle(
                                      color: secondaryColor,
                                      fontSize: 14,
                                    ),
                                    onChanged: (_) =>
                                        _saveReportCardSynthesisPersistently(),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'POINTS À DÉVELOPPER :',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: secondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _pointsDevelopperController,
                                    enabled:
                                        SafeModeService.instance
                                            .isActionAllowed() &&
                                        !_isPeriodLocked(),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Saisir les points à développer',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      hintStyle: TextStyle(
                                        color: secondaryColor.withOpacity(0.7),
                                      ),
                                      filled: true,
                                      fillColor: Colors.blueGrey.shade50,
                                    ),
                                    maxLines: 2,
                                    style: TextStyle(
                                      color: secondaryColor,
                                      fontSize: 14,
                                    ),
                                    onChanged: (_) =>
                                        _saveReportCardSynthesisPersistently(),
                                  ),
                                ],
                              ),
                            ),
                            // 3e colonne retirée: Conduite, Retards, Sanctions sont déplacés sous le bloc Assiduité
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.shade100,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Fait à : ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: mainColor,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          _faitAController.text.isNotEmpty
                                              ? _faitAController.text
                                              : (info.address.isNotEmpty
                                                    ? info.address
                                                    : '__________________________'),
                                          style: TextStyle(
                                            color: secondaryColor,
                                          ),
                                          overflow: TextOverflow.visible,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    niveau.toLowerCase().contains('lyc')
                                        ? 'Proviseur(e) :'
                                        : 'Directeur(ice) :',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '__________________________',
                                    style: TextStyle(color: secondaryColor),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      String directorName = info.director
                                          .trim();
                                      String civility =
                                          _adminCivility.isNotEmpty
                                          ? _adminCivility
                                          : 'M.';
                                      if (isComplexe) {
                                        final n = niveau.toLowerCase();
                                        if (n.contains('primaire') ||
                                            n.contains('maternelle')) {
                                          directorName =
                                              info.directorPrimary?.trim() ??
                                              directorName;
                                          civility =
                                              info.civilityPrimary?.trim() ??
                                              civility;
                                        } else if (n.contains('coll')) {
                                          directorName =
                                              info.directorCollege?.trim() ??
                                              directorName;
                                          civility =
                                              info.civilityCollege?.trim() ??
                                              civility;
                                        } else if (n.contains('lyc')) {
                                          directorName =
                                              info.directorLycee?.trim() ??
                                              directorName;
                                          civility =
                                              info.civilityLycee?.trim() ??
                                              civility;
                                        } else if (n.contains('univ')) {
                                          directorName =
                                              info.directorUniversity?.trim() ??
                                              directorName;
                                          civility =
                                              info.civilityUniversity?.trim() ??
                                              civility;
                                        }
                                      }
                                      if (directorName.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          "$civility $directorName",
                                          style: TextStyle(
                                            color: secondaryColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 32),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Le : ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: mainColor,
                                        ),
                                      ),
                                      Text(
                                        _leDateController.text.isNotEmpty
                                            ? _leDateController.text
                                            : DateFormat(
                                                'dd/MM/yyyy',
                                              ).format(DateTime.now()),
                                        style: TextStyle(color: secondaryColor),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 16),
                                  Builder(
                                    builder: (context) {
                                      final currentClass = classes.firstWhere(
                                        (c) => c.name == selectedClass,
                                        orElse: () => Class.empty(),
                                      );
                                      final t = currentClass.titulaire ?? '';
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'Titulaire : ',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: mainColor,
                                                ),
                                              ),
                                              if (t.isNotEmpty)
                                                Text(
                                                  t,
                                                  style: TextStyle(
                                                    color: secondaryColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '__________________________',
                                            style: TextStyle(
                                              color: secondaryColor,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Bouton Export PDF
                      Align(
                        alignment: Alignment.centerRight,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    // Vérifier le mode coffre fort
                                    if (!SafeModeService.instance
                                        .isActionAllowed()) {
                                      showSnackBar(
                                        context,
                                        SafeModeService.instance
                                            .getBlockedActionMessage(),
                                        isError: true,
                                      );
                                      return;
                                    }

                                    // Demande l'orientation
                                    final orientation =
                                        await showDialog<String>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Orientation du PDF'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  title: Text('Portrait'),
                                                  leading: Icon(
                                                    Icons.stay_current_portrait,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('portrait'),
                                                ),
                                                ListTile(
                                                  title: Text('Paysage'),
                                                  leading: Icon(
                                                    Icons
                                                        .stay_current_landscape,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('landscape'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ) ??
                                        'portrait';
                                    final isLandscape =
                                        orientation == 'landscape';
                                    final professeurs = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_profControllers[subject]?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_profControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    await _applyAssignmentProfessors(
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ?? effectiveYear,
                                      subjectNames: subjectNames,
                                      professeurs: professeurs,
                                    );
                                    final appreciations = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_appreciationControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_appreciationControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final moyennesClasse = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_moyClasseControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_moyClasseControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final appreciationGenerale =
                                        _appreciationGeneraleController.text;
                                    final decision = _decisionController.text;
                                    final telEtab = _telEtabController.text;
                                    final mailEtab = _mailEtabController.text;
                                    final webEtab = _webEtabController.text;
                                    // Adresse et date d'export automatiques
                                    final String faitA =
                                        (_faitAController.text
                                            .trim()
                                            .isNotEmpty)
                                        ? _faitAController.text.trim()
                                        : info.address;
                                    final String leDate = DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(DateTime.now());
                                    final currentClass = classes.firstWhere(
                                      (c) => c.name == selectedClass,
                                      orElse: () => Class.empty(),
                                    );
                                    final data = await _prepareReportCardData(
                                      student,
                                    );
                                    final List<double?> moyennesParPeriodePdf =
                                        (data['moyennesParPeriode'] as List)
                                            .cast<double?>();
                                    final double moyenneGeneralePdf =
                                        data['moyenneGenerale'] as double;
                                    final int rangPdf = data['rang'] as int;
                                    final int nbElevesPdf =
                                        data['nbEleves'] as int;
                                    final String mentionPdf =
                                        data['mention'] as String;
                                    final List<String> allTermsPdf =
                                        (data['allTerms'] as List)
                                            .cast<String>();
                                    final String periodLabelPdf =
                                        data['periodLabel'] as String;
                                    final String selectedTermPdf =
                                        data['selectedTerm'] as String;
                                    final String academicYearPdf =
                                        data['academicYear'] as String;
                                    final String niveauPdf =
                                        data['niveau'] as String;
                                    final double? moyenneGeneraleDeLaClassePdf =
                                        data['moyenneGeneraleDeLaClasse']
                                            as double?;
                                    final double? moyenneLaPlusFortePdf =
                                        data['moyenneLaPlusForte'] as double?;
                                    final double? moyenneLaPlusFaiblePdf =
                                        data['moyenneLaPlusFaible'] as double?;
                                    final double? moyenneAnnuellePdf =
                                        data['moyenneAnnuelle'] as double?;
                                    final pdfBytes =
                                        await PdfService.generateReportCardPdf(
                                          student: student,
                                          schoolInfo: info,
                                          grades: (data['grades'] as List)
                                              .cast<Grade>(),
                                          professeurs: professeurs,
                                          appreciations: appreciations,
                                          moyennesClasse: moyennesClasse,
                                          appreciationGenerale:
                                              appreciationGenerale,
                                          decision: decision,
                                          recommandations:
                                              _recommandationsController.text,
                                          forces: _forcesController.text,
                                          pointsADevelopper:
                                              _pointsDevelopperController.text,
                                          sanctions: _sanctionsController.text,
                                          attendanceJustifiee:
                                              int.tryParse(
                                                _absJustifieesController.text,
                                              ) ??
                                              0,
                                          attendanceInjustifiee:
                                              int.tryParse(
                                                _absInjustifieesController.text,
                                              ) ??
                                              0,
                                          retards:
                                              int.tryParse(
                                                _retardsController.text,
                                              ) ??
                                              0,
                                          presencePercent:
                                              double.tryParse(
                                                _presencePercentController.text,
                                              ) ??
                                              0.0,
                                          conduite: _conduiteController.text,
                                          telEtab: telEtab,
                                          mailEtab: mailEtab,
                                          webEtab: webEtab,
                                          titulaire:
                                              currentClass.titulaire ?? '',
                                          subjects: subjectNames,
                                          moyennesParPeriode:
                                              moyennesParPeriodePdf,
                                          moyenneGenerale: moyenneGeneralePdf,
                                          rang: rangPdf,
                                          exaequo:
                                              (data['exaequo'] as bool?) ??
                                              false,
                                          nbEleves: nbElevesPdf,
                                          mention: mentionPdf,
                                          allTerms: allTermsPdf,
                                          periodLabel: periodLabelPdf,
                                          selectedTerm: selectedTermPdf,
                                          academicYear: academicYearPdf,
                                          faitA: faitA,
                                          leDate: leDate,
                                          isLandscape: isLandscape,
                                          niveau: niveauPdf,
                                          moyenneGeneraleDeLaClasse:
                                              moyenneGeneraleDeLaClassePdf,
                                          moyenneLaPlusForte:
                                              moyenneLaPlusFortePdf,
                                          moyenneLaPlusFaible:
                                              moyenneLaPlusFaiblePdf,
                                          moyenneAnnuelle: moyenneAnnuellePdf,
                                        );
                                    await Printing.layoutPdf(
                                      onLayout: (format) async =>
                                          Uint8List.fromList(pdfBytes),
                                    );
                                  },
                                  icon: Icon(Icons.picture_as_pdf),
                                  label: Text('Aperçu PDF'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: mainColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    // Vérifier le mode coffre fort
                                    if (!SafeModeService.instance
                                        .isActionAllowed()) {
                                      showSnackBar(
                                        context,
                                        SafeModeService.instance
                                            .getBlockedActionMessage(),
                                        isError: true,
                                      );
                                      return;
                                    }

                                    // Demande l'orientation
                                    final orientation =
                                        await showDialog<String>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Orientation du PDF'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  title: Text('Portrait'),
                                                  leading: Icon(
                                                    Icons.stay_current_portrait,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('portrait'),
                                                ),
                                                ListTile(
                                                  title: Text('Paysage'),
                                                  leading: Icon(
                                                    Icons
                                                        .stay_current_landscape,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('landscape'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ) ??
                                        'portrait';
                                    final isLandscape =
                                        orientation == 'landscape';
                                    final professeurs = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_profControllers[subject]?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_profControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    await _applyAssignmentProfessors(
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ?? effectiveYear,
                                      subjectNames: subjectNames,
                                      professeurs: professeurs,
                                    );
                                    final appreciations = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_appreciationControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_appreciationControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final moyennesClasse = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_moyClasseControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_moyClasseControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final appreciationGenerale =
                                        _appreciationGeneraleController.text;
                                    final decision = _decisionController.text;
                                    final telEtab = _telEtabController.text;
                                    final mailEtab = _mailEtabController.text;
                                    final webEtab = _webEtabController.text;
                                    // Adresse et date d'export automatiques
                                    final String faitA =
                                        (_faitAController.text
                                            .trim()
                                            .isNotEmpty)
                                        ? _faitAController.text.trim()
                                        : info.address;
                                    final String leDate = DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(DateTime.now());
                                    final currentClass = classes.firstWhere(
                                      (c) => c.name == selectedClass,
                                      orElse: () => Class.empty(),
                                    );
                                    final data = await _prepareReportCardData(
                                      student,
                                    );
                                    final List<double?> moyennesParPeriodePdf =
                                        (data['moyennesParPeriode'] as List)
                                            .cast<double?>();
                                    final double moyenneGeneralePdf =
                                        data['moyenneGenerale'] as double;
                                    final int rangPdf = data['rang'] as int;
                                    final int nbElevesPdf =
                                        data['nbEleves'] as int;
                                    final String mentionPdf =
                                        data['mention'] as String;
                                    final List<String> allTermsPdf =
                                        (data['allTerms'] as List)
                                            .cast<String>();
                                    final String periodLabelPdf =
                                        data['periodLabel'] as String;
                                    final String selectedTermPdf =
                                        data['selectedTerm'] as String;
                                    final String academicYearPdf =
                                        data['academicYear'] as String;
                                    final String niveauPdf =
                                        data['niveau'] as String;
                                    final double? moyenneGeneraleDeLaClassePdf =
                                        data['moyenneGeneraleDeLaClasse']
                                            as double?;
                                    final double? moyenneLaPlusFortePdf =
                                        data['moyenneLaPlusForte'] as double?;
                                    final double? moyenneLaPlusFaiblePdf =
                                        data['moyenneLaPlusFaible'] as double?;
                                    final double? moyenneAnnuellePdf =
                                        data['moyenneAnnuelle'] as double?;
                                    final pdfBytes =
                                        await PdfService.generateReportCardPdfUltraCompact(
                                          student: student,
                                          schoolInfo: info,
                                          grades: (data['grades'] as List)
                                              .cast<Grade>(),
                                          professeurs: professeurs,
                                          appreciations: appreciations,
                                          moyennesClasse: moyennesClasse,
                                          appreciationGenerale:
                                              appreciationGenerale,
                                          decision: decision,
                                          recommandations:
                                              _recommandationsController.text,
                                          forces: _forcesController.text,
                                          pointsADevelopper:
                                              _pointsDevelopperController.text,
                                          sanctions: _sanctionsController.text,
                                          attendanceJustifiee:
                                              int.tryParse(
                                                _absJustifieesController.text,
                                              ) ??
                                              0,
                                          attendanceInjustifiee:
                                              int.tryParse(
                                                _absInjustifieesController.text,
                                              ) ??
                                              0,
                                          retards:
                                              int.tryParse(
                                                _retardsController.text,
                                              ) ??
                                              0,
                                          presencePercent:
                                              double.tryParse(
                                                _presencePercentController.text,
                                              ) ??
                                              0.0,
                                          conduite: _conduiteController.text,
                                          telEtab: telEtab,
                                          mailEtab: mailEtab,
                                          webEtab: webEtab,
                                          titulaire:
                                              currentClass.titulaire ?? '',
                                          subjects: subjectNames,
                                          moyennesParPeriode:
                                              moyennesParPeriodePdf,
                                          moyenneGenerale: moyenneGeneralePdf,
                                          rang: rangPdf,
                                          exaequo:
                                              (data['exaequo'] as bool?) ??
                                              false,
                                          nbEleves: nbElevesPdf,
                                          mention: mentionPdf,
                                          allTerms: allTermsPdf,
                                          periodLabel: periodLabelPdf,
                                          selectedTerm: selectedTermPdf,
                                          academicYear: academicYearPdf,
                                          faitA: faitA,
                                          leDate: leDate,
                                          isLandscape: isLandscape,
                                          niveau: niveauPdf,
                                          moyenneGeneraleDeLaClasse:
                                              moyenneGeneraleDeLaClassePdf,
                                          moyenneLaPlusForte:
                                              moyenneLaPlusFortePdf,
                                          moyenneLaPlusFaible:
                                              moyenneLaPlusFaiblePdf,
                                          moyenneAnnuelle: moyenneAnnuellePdf,
                                        );
                                    await Printing.layoutPdf(
                                      onLayout: (format) async =>
                                          Uint8List.fromList(pdfBytes),
                                    );
                                  },
                                  icon: Icon(Icons.picture_as_pdf_outlined),
                                  label: Text('Aperçu PDF ultra compact'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    // Vérifier le mode coffre fort
                                    if (!SafeModeService.instance
                                        .isActionAllowed()) {
                                      showSnackBar(
                                        context,
                                        SafeModeService.instance
                                            .getBlockedActionMessage(),
                                        isError: true,
                                      );
                                      return;
                                    }

                                    // Demande l'orientation
                                    final orientation =
                                        await showDialog<String>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Orientation du PDF'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  title: Text('Portrait'),
                                                  leading: Icon(
                                                    Icons.stay_current_portrait,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('portrait'),
                                                ),
                                                ListTile(
                                                  title: Text('Paysage'),
                                                  leading: Icon(
                                                    Icons
                                                        .stay_current_landscape,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('landscape'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ) ??
                                        'portrait';
                                    final isLandscape =
                                        orientation == 'landscape';
                                    final professeurs = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_profControllers[subject]?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_profControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    await _applyAssignmentProfessors(
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ?? effectiveYear,
                                      subjectNames: subjectNames,
                                      professeurs: professeurs,
                                    );
                                    final appreciations = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_appreciationControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_appreciationControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final moyennesClasse = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_moyClasseControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_moyClasseControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final appreciationGenerale =
                                        _appreciationGeneraleController.text;
                                    final decision = _decisionController.text;
                                    final telEtab = _telEtabController.text;
                                    final mailEtab = _mailEtabController.text;
                                    final webEtab = _webEtabController.text;
                                    // Adresse et date d'export automatiques
                                    final String faitA =
                                        (_faitAController.text
                                            .trim()
                                            .isNotEmpty)
                                        ? _faitAController.text.trim()
                                        : info.address;
                                    final String leDate = DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(DateTime.now());
                                    final currentClass = classes.firstWhere(
                                      (c) => c.name == selectedClass,
                                      orElse: () => Class.empty(),
                                    );
                                    final data = await _prepareReportCardData(
                                      student,
                                    );
                                    final List<double?> moyennesParPeriodePdf =
                                        (data['moyennesParPeriode'] as List)
                                            .cast<double?>();
                                    final double moyenneGeneralePdf =
                                        data['moyenneGenerale'] as double;
                                    final int rangPdf = data['rang'] as int;
                                    final int nbElevesPdf =
                                        data['nbEleves'] as int;
                                    final String mentionPdf =
                                        data['mention'] as String;
                                    final List<String> allTermsPdf =
                                        (data['allTerms'] as List)
                                            .cast<String>();
                                    final String periodLabelPdf =
                                        data['periodLabel'] as String;
                                    final String selectedTermPdf =
                                        data['selectedTerm'] as String;
                                    final String academicYearPdf =
                                        data['academicYear'] as String;
                                    final String niveauPdf =
                                        data['niveau'] as String;
                                    final double? moyenneGeneraleDeLaClassePdf =
                                        data['moyenneGeneraleDeLaClasse']
                                            as double?;
                                    final double? moyenneLaPlusFortePdf =
                                        data['moyenneLaPlusForte'] as double?;
                                    final double? moyenneLaPlusFaiblePdf =
                                        data['moyenneLaPlusFaible'] as double?;
                                    final double? moyenneAnnuellePdf =
                                        data['moyenneAnnuelle'] as double?;
                                    final pdfBytes =
                                        await PdfService.generateReportCardPdfCompact(
                                          student: student,
                                          schoolInfo: info,
                                          grades: (data['grades'] as List)
                                              .cast<Grade>(),
                                          professeurs: professeurs,
                                          appreciations: appreciations,
                                          moyennesClasse: moyennesClasse,
                                          appreciationGenerale:
                                              appreciationGenerale,
                                          decision: decision,
                                          recommandations:
                                              _recommandationsController.text,
                                          forces: _forcesController.text,
                                          pointsADevelopper:
                                              _pointsDevelopperController.text,
                                          sanctions: _sanctionsController.text,
                                          attendanceJustifiee:
                                              int.tryParse(
                                                _absJustifieesController.text,
                                              ) ??
                                              0,
                                          attendanceInjustifiee:
                                              int.tryParse(
                                                _absInjustifieesController.text,
                                              ) ??
                                              0,
                                          retards:
                                              int.tryParse(
                                                _retardsController.text,
                                              ) ??
                                              0,
                                          presencePercent:
                                              double.tryParse(
                                                _presencePercentController.text,
                                              ) ??
                                              0.0,
                                          conduite: _conduiteController.text,
                                          telEtab: telEtab,
                                          mailEtab: mailEtab,
                                          webEtab: webEtab,
                                          titulaire:
                                              currentClass.titulaire ?? '',
                                          subjects: subjectNames,
                                          moyennesParPeriode:
                                              moyennesParPeriodePdf,
                                          moyenneGenerale: moyenneGeneralePdf,
                                          rang: rangPdf,
                                          exaequo:
                                              (data['exaequo'] as bool?) ??
                                              false,
                                          nbEleves: nbElevesPdf,
                                          mention: mentionPdf,
                                          allTerms: allTermsPdf,
                                          periodLabel: periodLabelPdf,
                                          selectedTerm: selectedTermPdf,
                                          academicYear: academicYearPdf,
                                          faitA: faitA,
                                          leDate: leDate,
                                          isLandscape: isLandscape,
                                          niveau: niveauPdf,
                                          moyenneGeneraleDeLaClasse:
                                              moyenneGeneraleDeLaClassePdf,
                                          moyenneLaPlusForte:
                                              moyenneLaPlusFortePdf,
                                          moyenneLaPlusFaible:
                                              moyenneLaPlusFaiblePdf,
                                          moyenneAnnuelle: moyenneAnnuellePdf,
                                        );
                                    await Printing.layoutPdf(
                                      onLayout: (format) async =>
                                          Uint8List.fromList(pdfBytes),
                                    );
                                  },
                                  icon: Icon(Icons.picture_as_pdf_outlined),
                                  label: Text('Aperçu PDF compact'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await _saveCustomReportCardPdf(
                                      student: student,
                                      info: info,
                                      subjectNames: subjectNames,
                                      profCtrls: _profControllers,
                                      appreciationCtrls:
                                          _appreciationControllers,
                                      moyClasseCtrls: _moyClasseControllers,
                                      generalAppreciationCtrl:
                                          _appreciationGeneraleController,
                                      decisionCtrl: _decisionController,
                                      conduiteCtrl: _conduiteController,
                                      faitACtrl: _faitAController,
                                      absJustifieesCtrl:
                                          _absJustifieesController,
                                      absInjustifieesCtrl:
                                          _absInjustifieesController,
                                      retardsCtrl: _retardsController,
                                      presencePercentCtrl:
                                          _presencePercentController,
                                      recommandationsCtrl:
                                          _recommandationsController,
                                      forcesCtrl: _forcesController,
                                      pointsDevelopperCtrl:
                                          _pointsDevelopperController,
                                      sanctionsCtrl: _sanctionsController,
                                    );
                                  },
                                  icon: Icon(Icons.picture_as_pdf_outlined),
                                  label: Text('Exporter PDF custom'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await _printCustomReportCardPdf(
                                      student: student,
                                      info: info,
                                      subjectNames: subjectNames,
                                      profCtrls: _profControllers,
                                      appreciationCtrls:
                                          _appreciationControllers,
                                      moyClasseCtrls: _moyClasseControllers,
                                      generalAppreciationCtrl:
                                          _appreciationGeneraleController,
                                      decisionCtrl: _decisionController,
                                      conduiteCtrl: _conduiteController,
                                      faitACtrl: _faitAController,
                                      absJustifieesCtrl:
                                          _absJustifieesController,
                                      absInjustifieesCtrl:
                                          _absInjustifieesController,
                                      retardsCtrl: _retardsController,
                                      presencePercentCtrl:
                                          _presencePercentController,
                                      recommandationsCtrl:
                                          _recommandationsController,
                                      forcesCtrl: _forcesController,
                                      pointsDevelopperCtrl:
                                          _pointsDevelopperController,
                                      sanctionsCtrl: _sanctionsController,
                                    );
                                  },
                                  icon: Icon(Icons.print),
                                  label: Text('Imprimer PDF custom'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade900,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    // Vérifier le mode coffre fort
                                    if (!SafeModeService.instance
                                        .isActionAllowed()) {
                                      showSnackBar(
                                        context,
                                        SafeModeService.instance
                                            .getBlockedActionMessage(),
                                        isError: true,
                                      );
                                      return;
                                    }

                                    // Demande l'orientation
                                    final orientation =
                                        await showDialog<String>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Orientation du PDF'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  title: Text('Portrait'),
                                                  leading: Icon(
                                                    Icons.stay_current_portrait,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('portrait'),
                                                ),
                                                ListTile(
                                                  title: Text('Paysage'),
                                                  leading: Icon(
                                                    Icons
                                                        .stay_current_landscape,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('landscape'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ) ??
                                        'portrait';
                                    final isLandscape =
                                        orientation == 'landscape';
                                    final professeurs = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_profControllers[subject]?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_profControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    await _applyAssignmentProfessors(
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ?? effectiveYear,
                                      subjectNames: subjectNames,
                                      professeurs: professeurs,
                                    );
                                    final appreciations = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_appreciationControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_appreciationControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final moyennesClasse = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_moyClasseControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_moyClasseControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final appreciationGenerale =
                                        _appreciationGeneraleController.text;
                                    final decision = _decisionController.text;
                                    final telEtab = _telEtabController.text;
                                    final mailEtab = _mailEtabController.text;
                                    final webEtab = _webEtabController.text;
                                    // Adresse et date d'export automatiques
                                    final String faitA =
                                        (_faitAController.text
                                            .trim()
                                            .isNotEmpty)
                                        ? _faitAController.text.trim()
                                        : info.address;
                                    final String leDate = DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(DateTime.now());
                                    final currentClass = classes.firstWhere(
                                      (c) => c.name == selectedClass,
                                      orElse: () => Class.empty(),
                                    );
                                    final data = await _prepareReportCardData(
                                      student,
                                    );
                                    final List<double?> moyennesParPeriodePdf =
                                        (data['moyennesParPeriode'] as List)
                                            .cast<double?>();
                                    final double moyenneGeneralePdf =
                                        data['moyenneGenerale'] as double;
                                    final int rangPdf = data['rang'] as int;
                                    final int nbElevesPdf =
                                        data['nbEleves'] as int;
                                    final String mentionPdf =
                                        data['mention'] as String;
                                    final List<String> allTermsPdf =
                                        (data['allTerms'] as List)
                                            .cast<String>();
                                    final String periodLabelPdf =
                                        data['periodLabel'] as String;
                                    final String selectedTermPdf =
                                        data['selectedTerm'] as String;
                                    final String academicYearPdf =
                                        data['academicYear'] as String;
                                    final String niveauPdf =
                                        data['niveau'] as String;
                                    final double? moyenneGeneraleDeLaClassePdf =
                                        data['moyenneGeneraleDeLaClasse']
                                            as double?;
                                    final double? moyenneLaPlusFortePdf =
                                        data['moyenneLaPlusForte'] as double?;
                                    final double? moyenneLaPlusFaiblePdf =
                                        data['moyenneLaPlusFaible'] as double?;
                                    final double? moyenneAnnuellePdf =
                                        data['moyenneAnnuelle'] as double?;
                                    final pdfBytes =
                                        await PdfService.generateReportCardPdfCompact(
                                          student: student,
                                          schoolInfo: info,
                                          grades: (data['grades'] as List)
                                              .cast<Grade>(),
                                          professeurs: professeurs,
                                          appreciations: appreciations,
                                          moyennesClasse: moyennesClasse,
                                          appreciationGenerale:
                                              appreciationGenerale,
                                          decision: decision,
                                          recommandations:
                                              _recommandationsController.text,
                                          forces: _forcesController.text,
                                          pointsADevelopper:
                                              _pointsDevelopperController.text,
                                          sanctions: _sanctionsController.text,
                                          attendanceJustifiee:
                                              int.tryParse(
                                                _absJustifieesController.text,
                                              ) ??
                                              0,
                                          attendanceInjustifiee:
                                              int.tryParse(
                                                _absInjustifieesController.text,
                                              ) ??
                                              0,
                                          retards:
                                              int.tryParse(
                                                _retardsController.text,
                                              ) ??
                                              0,
                                          presencePercent:
                                              double.tryParse(
                                                _presencePercentController.text,
                                              ) ??
                                              0.0,
                                          conduite: _conduiteController.text,
                                          telEtab: telEtab,
                                          mailEtab: mailEtab,
                                          webEtab: webEtab,
                                          titulaire:
                                              currentClass.titulaire ?? '',
                                          subjects: subjectNames,
                                          moyennesParPeriode:
                                              moyennesParPeriodePdf,
                                          moyenneGenerale: moyenneGeneralePdf,
                                          rang: rangPdf,
                                          exaequo:
                                              (data['exaequo'] as bool?) ??
                                              false,
                                          nbEleves: nbElevesPdf,
                                          mention: mentionPdf,
                                          allTerms: allTermsPdf,
                                          periodLabel: periodLabelPdf,
                                          selectedTerm: selectedTermPdf,
                                          academicYear: academicYearPdf,
                                          faitA: faitA,
                                          leDate: leDate,
                                          isLandscape: isLandscape,
                                          niveau: niveauPdf,
                                          moyenneGeneraleDeLaClasse:
                                              moyenneGeneraleDeLaClassePdf,
                                          moyenneLaPlusForte:
                                              moyenneLaPlusFortePdf,
                                          moyenneLaPlusFaible:
                                              moyenneLaPlusFaiblePdf,
                                          moyenneAnnuelle: moyenneAnnuellePdf,
                                        );
                                    String? directoryPath = await FilePicker
                                        .platform
                                        .getDirectoryPath(
                                          dialogTitle:
                                              'Choisir le dossier de sauvegarde',
                                        );
                                    if (directoryPath != null) {
                                      final fileName =
                                          'Bulletin_compact_${'${student.firstName}_${student.lastName}'.replaceAll(' ', '_')}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
                                      final file = File(
                                        '$directoryPath/$fileName',
                                      );
                                      await file.writeAsBytes(pdfBytes);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Bulletin compact enregistré dans $directoryPath',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  },
                                  icon: Icon(Icons.save_alt),
                                  label: Text('Enregistrer PDF compact...'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade800,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    // Vérifier le mode coffre fort
                                    if (!SafeModeService.instance
                                        .isActionAllowed()) {
                                      showSnackBar(
                                        context,
                                        SafeModeService.instance
                                            .getBlockedActionMessage(),
                                        isError: true,
                                      );
                                      return;
                                    }

                                    // Demande l'orientation
                                    final orientation =
                                        await showDialog<String>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Orientation du PDF'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  title: Text('Portrait'),
                                                  leading: Icon(
                                                    Icons.stay_current_portrait,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('portrait'),
                                                ),
                                                ListTile(
                                                  title: Text('Paysage'),
                                                  leading: Icon(
                                                    Icons
                                                        .stay_current_landscape,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('landscape'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ) ??
                                        'portrait';
                                    final isLandscape =
                                        orientation == 'landscape';
                                    final professeurs = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_profControllers[subject]?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_profControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    await _applyAssignmentProfessors(
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ?? effectiveYear,
                                      subjectNames: subjectNames,
                                      professeurs: professeurs,
                                    );
                                    final appreciations = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_appreciationControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_appreciationControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final moyennesClasse = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            (_moyClasseControllers[subject]
                                                        ?.text ??
                                                    '')
                                                .trim()
                                                .isNotEmpty
                                            ? (_moyClasseControllers[subject]
                                                          ?.text ??
                                                      '')
                                                  .trim()
                                            : '-',
                                    };
                                    final appreciationGenerale =
                                        _appreciationGeneraleController.text;
                                    final decision = _decisionController.text;
                                    final telEtab = _telEtabController.text;
                                    final mailEtab = _mailEtabController.text;
                                    final webEtab = _webEtabController.text;
                                    // Adresse et date d'export automatiques
                                    final String faitA =
                                        (_faitAController.text
                                            .trim()
                                            .isNotEmpty)
                                        ? _faitAController.text.trim()
                                        : info.address;
                                    final String leDate = DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(DateTime.now());
                                    final currentClass = classes.firstWhere(
                                      (c) => c.name == selectedClass,
                                      orElse: () => Class.empty(),
                                    );
                                    final data = await _prepareReportCardData(
                                      student,
                                    );
                                    final List<double?> moyennesParPeriodePdf =
                                        (data['moyennesParPeriode'] as List)
                                            .cast<double?>();
                                    final double moyenneGeneralePdf =
                                        data['moyenneGenerale'] as double;
                                    final int rangPdf = data['rang'] as int;
                                    final int nbElevesPdf =
                                        data['nbEleves'] as int;
                                    final String mentionPdf =
                                        data['mention'] as String;
                                    final List<String> allTermsPdf =
                                        (data['allTerms'] as List)
                                            .cast<String>();
                                    final String periodLabelPdf =
                                        data['periodLabel'] as String;
                                    final String selectedTermPdf =
                                        data['selectedTerm'] as String;
                                    final String academicYearPdf =
                                        data['academicYear'] as String;
                                    final String niveauPdf =
                                        data['niveau'] as String;
                                    final double? moyenneGeneraleDeLaClassePdf =
                                        data['moyenneGeneraleDeLaClasse']
                                            as double?;
                                    final double? moyenneLaPlusFortePdf =
                                        data['moyenneLaPlusForte'] as double?;
                                    final double? moyenneLaPlusFaiblePdf =
                                        data['moyenneLaPlusFaible'] as double?;
                                    final double? moyenneAnnuellePdf =
                                        data['moyenneAnnuelle'] as double?;
                                    final pdfBytes =
                                        await PdfService.generateReportCardPdfUltraCompact(
                                          student: student,
                                          schoolInfo: info,
                                          grades: (data['grades'] as List)
                                              .cast<Grade>(),
                                          professeurs: professeurs,
                                          appreciations: appreciations,
                                          moyennesClasse: moyennesClasse,
                                          appreciationGenerale:
                                              appreciationGenerale,
                                          decision: decision,
                                          recommandations:
                                              _recommandationsController.text,
                                          forces: _forcesController.text,
                                          pointsADevelopper:
                                              _pointsDevelopperController.text,
                                          sanctions: _sanctionsController.text,
                                          attendanceJustifiee:
                                              int.tryParse(
                                                _absJustifieesController.text,
                                              ) ??
                                              0,
                                          attendanceInjustifiee:
                                              int.tryParse(
                                                _absInjustifieesController.text,
                                              ) ??
                                              0,
                                          retards:
                                              int.tryParse(
                                                _retardsController.text,
                                              ) ??
                                              0,
                                          presencePercent:
                                              double.tryParse(
                                                _presencePercentController.text,
                                              ) ??
                                              0.0,
                                          conduite: _conduiteController.text,
                                          telEtab: telEtab,
                                          mailEtab: mailEtab,
                                          webEtab: webEtab,
                                          titulaire:
                                              currentClass.titulaire ?? '',
                                          subjects: subjectNames,
                                          moyennesParPeriode:
                                              moyennesParPeriodePdf,
                                          moyenneGenerale: moyenneGeneralePdf,
                                          rang: rangPdf,
                                          exaequo:
                                              (data['exaequo'] as bool?) ??
                                              false,
                                          nbEleves: nbElevesPdf,
                                          mention: mentionPdf,
                                          allTerms: allTermsPdf,
                                          periodLabel: periodLabelPdf,
                                          selectedTerm: selectedTermPdf,
                                          academicYear: academicYearPdf,
                                          faitA: faitA,
                                          leDate: leDate,
                                          isLandscape: isLandscape,
                                          niveau: niveauPdf,
                                          moyenneGeneraleDeLaClasse:
                                              moyenneGeneraleDeLaClassePdf,
                                          moyenneLaPlusForte:
                                              moyenneLaPlusFortePdf,
                                          moyenneLaPlusFaible:
                                              moyenneLaPlusFaiblePdf,
                                          moyenneAnnuelle: moyenneAnnuellePdf,
                                        );
                                    String? directoryPath = await FilePicker
                                        .platform
                                        .getDirectoryPath(
                                          dialogTitle:
                                              'Choisir le dossier de sauvegarde',
                                        );
                                    if (directoryPath != null) {
                                      final fileName =
                                          'Bulletin_ultra_compact_${'${student.firstName}_${student.lastName}'.replaceAll(' ', '_')}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
                                      final file = File(
                                        '$directoryPath/$fileName',
                                      );
                                      await file.writeAsBytes(pdfBytes);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Bulletin ultra compact enregistré dans $directoryPath',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  },
                                  icon: Icon(Icons.save_alt),
                                  label: Text(
                                    'Enregistrer PDF ultra compact...',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    // Vérifier le mode coffre fort
                                    if (!SafeModeService.instance
                                        .isActionAllowed()) {
                                      showSnackBar(
                                        context,
                                        SafeModeService.instance
                                            .getBlockedActionMessage(),
                                        isError: true,
                                      );
                                      return;
                                    }

                                    // Demande l'orientation
                                    final orientation =
                                        await showDialog<String>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Orientation du PDF'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  title: Text('Portrait'),
                                                  leading: Icon(
                                                    Icons.stay_current_portrait,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('portrait'),
                                                ),
                                                ListTile(
                                                  title: Text('Paysage'),
                                                  leading: Icon(
                                                    Icons
                                                        .stay_current_landscape,
                                                  ),
                                                  onTap: () => Navigator.of(
                                                    context,
                                                  ).pop('landscape'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ) ??
                                        'portrait';
                                    final isLandscape =
                                        orientation == 'landscape';
                                    final professeurs = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            _profControllers[subject]?.text ??
                                            '-',
                                    };
                                    await _applyAssignmentProfessors(
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ?? effectiveYear,
                                      subjectNames: subjectNames,
                                      professeurs: professeurs,
                                    );
                                    final appreciations = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            _appreciationControllers[subject]
                                                ?.text ??
                                            '-',
                                    };
                                    final moyennesClasse = <String, String>{
                                      for (final subject in subjectNames)
                                        subject:
                                            _moyClasseControllers[subject]
                                                ?.text ??
                                            '-',
                                    };
                                    final appreciationGenerale =
                                        _appreciationGeneraleController.text;
                                    final decision = _decisionController.text;
                                    final telEtab = _telEtabController.text;
                                    final mailEtab = _mailEtabController.text;
                                    final webEtab = _webEtabController.text;
                                    // Adresse et date d'export automatiques
                                    final String faitA =
                                        (_faitAController.text
                                            .trim()
                                            .isNotEmpty)
                                        ? _faitAController.text.trim()
                                        : info.address;
                                    final String leDate = DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(DateTime.now());
                                    final currentClass = classes.firstWhere(
                                      (c) => c.name == selectedClass,
                                      orElse: () => Class.empty(),
                                    );
                                    final data = await _prepareReportCardData(
                                      student,
                                    );
                                    final List<double?> moyennesParPeriodePdf =
                                        (data['moyennesParPeriode'] as List)
                                            .cast<double?>();
                                    final double moyenneGeneralePdf =
                                        data['moyenneGenerale'] as double;
                                    final int rangPdf = data['rang'] as int;
                                    final int nbElevesPdf =
                                        data['nbEleves'] as int;
                                    final String mentionPdf =
                                        data['mention'] as String;
                                    final List<String> allTermsPdf =
                                        (data['allTerms'] as List)
                                            .cast<String>();
                                    final String periodLabelPdf =
                                        data['periodLabel'] as String;
                                    final String selectedTermPdf =
                                        data['selectedTerm'] as String;
                                    final String academicYearPdf =
                                        data['academicYear'] as String;
                                    final String niveauPdf =
                                        data['niveau'] as String;
                                    final double? moyenneGeneraleDeLaClassePdf =
                                        data['moyenneGeneraleDeLaClasse']
                                            as double?;
                                    final double? moyenneLaPlusFortePdf =
                                        data['moyenneLaPlusForte'] as double?;
                                    final double? moyenneLaPlusFaiblePdf =
                                        data['moyenneLaPlusFaible'] as double?;
                                    final double? moyenneAnnuellePdf =
                                        data['moyenneAnnuelle'] as double?;
                                    final pdfBytes =
                                        await PdfService.generateReportCardPdf(
                                          student: student,
                                          schoolInfo: info,
                                          grades: (data['grades'] as List)
                                              .cast<Grade>(),
                                          professeurs: professeurs,
                                          appreciations: appreciations,
                                          moyennesClasse: moyennesClasse,
                                          appreciationGenerale:
                                              appreciationGenerale,
                                          decision: decision,
                                          recommandations:
                                              _recommandationsController.text,
                                          forces: _forcesController.text,
                                          pointsADevelopper:
                                              _pointsDevelopperController.text,
                                          sanctions: _sanctionsController.text,
                                          attendanceJustifiee:
                                              int.tryParse(
                                                _absJustifieesController.text,
                                              ) ??
                                              0,
                                          attendanceInjustifiee:
                                              int.tryParse(
                                                _absInjustifieesController.text,
                                              ) ??
                                              0,
                                          retards:
                                              int.tryParse(
                                                _retardsController.text,
                                              ) ??
                                              0,
                                          presencePercent:
                                              double.tryParse(
                                                _presencePercentController.text,
                                              ) ??
                                              0.0,
                                          conduite: _conduiteController.text,
                                          telEtab: telEtab,
                                          mailEtab: mailEtab,
                                          webEtab: webEtab,
                                          titulaire:
                                              currentClass.titulaire ?? '',
                                          subjects: subjectNames,
                                          moyennesParPeriode:
                                              moyennesParPeriodePdf,
                                          moyenneGenerale: moyenneGeneralePdf,
                                          rang: rangPdf,
                                          exaequo:
                                              (data['exaequo'] as bool?) ??
                                              false,
                                          nbEleves: nbElevesPdf,
                                          mention: mentionPdf,
                                          allTerms: allTermsPdf,
                                          periodLabel: periodLabelPdf,
                                          selectedTerm: selectedTermPdf,
                                          academicYear: academicYearPdf,
                                          faitA: faitA,
                                          leDate: leDate,
                                          isLandscape: isLandscape,
                                          niveau: niveauPdf,
                                          moyenneGeneraleDeLaClasse:
                                              moyenneGeneraleDeLaClassePdf,
                                          moyenneLaPlusForte:
                                              moyenneLaPlusFortePdf,
                                          moyenneLaPlusFaible:
                                              moyenneLaPlusFaiblePdf,
                                          moyenneAnnuelle: moyenneAnnuellePdf,
                                        );
                                    String? directoryPath = await FilePicker
                                        .platform
                                        .getDirectoryPath(
                                          dialogTitle:
                                              'Choisir le dossier de sauvegarde',
                                        );
                                    if (directoryPath != null) {
                                      final fileName =
                                          'Bulletin_${'${student.firstName}_${student.lastName}'.replaceAll(' ', '_')}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
                                      final file = File(
                                        '$directoryPath/$fileName',
                                      );
                                      await file.writeAsBytes(pdfBytes);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Bulletin enregistré dans $directoryPath',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  },
                                  icon: Icon(Icons.save_alt),
                                  label: Text('Enregistrer PDF...'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  double? _calculateClassAverageForSubject(String subject) {
    final targetKey = _normalizeSubjectKey(subject);
    final gradesForSubject = grades
        .where(
          (g) =>
              g.className == selectedClass &&
              g.academicYear ==
                  (selectedAcademicYear ?? academicYearNotifier.value) &&
              _normalizeSubjectKey(g.subject) == targetKey &&
              g.term == selectedTerm &&
              (g.type == 'Devoir' || g.type == 'Composition'),
        )
        .toList();

    if (gradesForSubject.isEmpty) return null;

    double total = 0.0;
    double totalCoeff = 0.0;
    for (final g in gradesForSubject) {
      if (g.maxValue > 0 && g.coefficient > 0) {
        total += ((g.value / g.maxValue) * 20) * g.coefficient;
        totalCoeff += g.coefficient;
      }
    }
    return totalCoeff > 0 ? (total / totalCoeff) : null;
  }

  double? _parseQuickEntryValue(String raw, double maxValue) {
    final cleaned = raw.replaceAll(',', '.').trim();
    final v = double.tryParse(cleaned);
    if (v == null) return null;
    return v;
  }

  double _computeWeightedAverageOn20(List<Grade> grades) {
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

  List<Grade> _effectiveGradesForSubject(String subject) {
    final targetKey = _normalizeSubjectKey(subject);
    final base = grades
        .where(
          (g) =>
              g.className == selectedClass &&
              g.academicYear ==
                  (selectedAcademicYear ?? academicYearNotifier.value) &&
              _normalizeSubjectKey(g.subject) == targetKey &&
              g.term == selectedTerm &&
              (g.type == 'Devoir' || g.type == 'Composition'),
        )
        .toList();

    // Applique les brouillons (valeur tapée mais pas encore sauvegardée)
    final Map<String, Grade> byStudent = {for (final g in base) g.studentId: g};
    _gradeDrafts.forEach((studentId, txt) {
      final existing = byStudent[studentId];
      final maxValue = existing?.maxValue ?? 20.0;
      final v = _parseQuickEntryValue(txt, maxValue);
      if (v == null) return;
      if (existing != null) {
        byStudent[studentId] = Grade(
          id: existing.id,
          studentId: existing.studentId,
          className: existing.className,
          academicYear: existing.academicYear,
          subjectId: existing.subjectId,
          subject: existing.subject,
          term: existing.term,
          value: v,
          label: existing.label,
          maxValue: existing.maxValue,
          coefficient: existing.coefficient,
          type: existing.type,
        );
      } else if (selectedClass != null &&
          selectedAcademicYear != null &&
          selectedTerm != null) {
        // Si pas de note existante pour cet élève, mais saisie en cours -> inclure dans le calcul
        final course = subjects.firstWhere(
          (c) => c.name == subject,
          orElse: () => Course.empty(),
        );
        byStudent[studentId] = Grade(
          studentId: studentId,
          className: selectedClass!,
          academicYear: selectedAcademicYear!,
          subjectId: course.id,
          subject: subject,
          term: selectedTerm!,
          value: v,
          label: null,
          maxValue: 20.0,
          coefficient: 1.0,
          type: 'Devoir',
        );
      }
    });
    return byStudent.values.toList();
  }

  Widget _buildArchiveTab() {
    // Vérifier le mode coffre fort
    if (!SafeModeService.instance.isActionAllowed()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Mode coffre fort activé',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              SafeModeService.instance.getBlockedActionMessage(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(
            controller: archiveSearchController,
            hintText: 'Rechercher dans les archives...',
            onChanged: (val) => setState(() => _archiveSearchQuery = val),
          ),
          CheckboxListTile(
            title: Text("Rechercher dans toutes les années"),
            value: _searchAllYears,
            onChanged: (bool? value) {
              setState(() {
                _searchAllYears = value ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 16),
          if (!_searchAllYears) _buildSelectionSection(),
          const SizedBox(height: 24),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _searchAllYears
                ? _dbService.getAllArchivedReportCards()
                : (selectedAcademicYear == null ||
                      selectedAcademicYear!.isEmpty ||
                      selectedClass == null ||
                      selectedClass!.isEmpty)
                ? Future.value([])
                : _dbService.getArchivedReportCardsByClassAndYear(
                    academicYear: selectedAcademicYear!,
                    className: selectedClass!,
                  ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Text(
                    'Aucune archive trouvée pour cette sélection.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              final allArchivedReportCards = snapshot.data!;
              final studentIdsFromArchive = allArchivedReportCards
                  .map((rc) => rc['studentId'] as String)
                  .toSet();

              // Filtrer les élèves en fonction de la recherche et des archives
              final filteredStudents = students.where((student) {
                final query = _archiveSearchQuery.toLowerCase();
                final nameMatch =
                    query.isEmpty ||
                    _displayStudentName(
                      student,
                    ).toLowerCase().contains(query) ||
                    student.name.toLowerCase().contains(query);
                final inArchive = studentIdsFromArchive.contains(student.id);
                return nameMatch && inArchive;
              }).toList()..sort(_compareStudentsByName);

              if (filteredStudents.isEmpty) {
                return Center(
                  child: Text(
                    'Aucun élève correspondant trouvé dans les archives.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              // Logique de pagination
              final startIndex = _archiveCurrentPage * _archiveItemsPerPage;
              final endIndex =
                  (startIndex + _archiveItemsPerPage > filteredStudents.length)
                  ? filteredStudents.length
                  : startIndex + _archiveItemsPerPage;
              final paginatedStudents = filteredStudents.sublist(
                startIndex,
                endIndex,
              );

              return Column(
                children: [
                  ...paginatedStudents.map((student) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          child: Text(
                            student.firstName.isNotEmpty
                                ? student.firstName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          _displayStudentName(student),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        subtitle: Text(
                          'Classe: ${student.className}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onSelected: (value) async {
                            if (value == 'profile') {
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    StudentProfilePage(student: student),
                              );
                            } else if (value == 'view') {
                              // Aperçu du bulletin (PDF preview) avec en-tête administratif harmonisé
                              try {
                                final info = await loadSchoolInfo();
                                // Orientation
                                final orientation =
                                    await showDialog<String>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Orientation du PDF'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              title: const Text('Portrait'),
                                              leading: const Icon(
                                                Icons.stay_current_portrait,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('portrait'),
                                            ),
                                            ListTile(
                                              title: const Text('Paysage'),
                                              leading: const Icon(
                                                Icons.stay_current_landscape,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('landscape'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ) ??
                                    'portrait';
                                final bool isLandscape =
                                    orientation == 'landscape';

                                // Construit les données comme pour l'export ZIP
                                final data = await _prepareReportCardData(
                                  student,
                                );
                                final subjectNames = (data['subjects'] as List)
                                    .cast<String>();
                                final archiveCard = await _dbService
                                    .getReportCardArchive(
                                      studentId: student.id,
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ??
                                          data['academicYear'],
                                      term:
                                          selectedTerm ?? data['selectedTerm'],
                                    );
                                final archived =
                                    archiveCard ??
                                    await _dbService.getReportCard(
                                      studentId: student.id,
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ??
                                          data['academicYear'],
                                      term:
                                          selectedTerm ?? data['selectedTerm'],
                                    );
                                final bool useArchived = archiveCard != null;
                                // Récupérer appréciations/professeurs/moyenne_classe enregistrées
                                final apps = useArchived
                                    ? await _dbService
                                          .getSubjectAppreciationsArchiveByKeys(
                                            studentId: student.id,
                                            className:
                                                selectedClass ??
                                                student.className,
                                            academicYear:
                                                selectedAcademicYear ??
                                                data['academicYear'],
                                            term:
                                                selectedTerm ??
                                                data['selectedTerm'],
                                          )
                                    : await _dbService.getSubjectAppreciations(
                                        studentId: student.id,
                                        className:
                                            selectedClass ?? student.className,
                                        academicYear:
                                            selectedAcademicYear ??
                                            data['academicYear'],
                                        term:
                                            selectedTerm ??
                                            data['selectedTerm'],
                                      );
                                final professeurs = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final appreciations = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final moyennesClasse = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final coeffs = <String, double?>{
                                  for (final s in subjectNames) s: null,
                                };
                                for (final row in apps) {
                                  final subject = row['subject'] as String?;
                                  if (subject != null) {
                                    professeurs[subject] =
                                        (row['professeur'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['professeur'] as String
                                        : '-';
                                    appreciations[subject] =
                                        (row['appreciation'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['appreciation'] as String
                                        : '-';
                                    moyennesClasse[subject] =
                                        (row['moyenne_classe'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['moyenne_classe'] as String
                                        : '-';
                                    final coeff = row['coefficient'] as num?;
                                    if (coeff != null) {
                                      coeffs[subject] = coeff.toDouble();
                                    }
                                  }
                                }
                                final className =
                                    selectedClass ?? student.className;
                                final academicYear =
                                    selectedAcademicYear ??
                                    data['academicYear'];
                                if (!useArchived) {
                                  await _applyAssignmentProfessors(
                                    className: className,
                                    academicYear: academicYear,
                                    subjectNames: subjectNames,
                                    professeurs: professeurs,
                                  );
                                  final profsForEdit = <String, String>{
                                    for (final s in subjectNames)
                                      s: (professeurs[s] ?? '') == '-'
                                          ? ''
                                          : (professeurs[s] ?? ''),
                                  };
                                  final editResult =
                                      await _showEditProfessorsDialog(
                                        subjects: subjectNames,
                                        current: profsForEdit,
                                        allowSave: true,
                                      );
                                  if (editResult != null) {
                                    final cleaned = <String, String>{
                                      for (final s in subjectNames)
                                        s:
                                            (editResult.professeurs[s] ?? '')
                                                .trim()
                                                .isNotEmpty
                                            ? editResult.professeurs[s]!
                                            : '-',
                                    };
                                    professeurs
                                      ..clear()
                                      ..addAll(cleaned);
                                    if (editResult.save) {
                                      final term =
                                          selectedTerm ?? data['selectedTerm'];
                                      for (final subject in subjectNames) {
                                        final prof =
                                            (professeurs[subject] ?? '').trim();
                                        final app =
                                            (appreciations[subject] ?? '')
                                                .trim();
                                        final moy =
                                            (moyennesClasse[subject] ?? '')
                                                .trim();
                                        await _dbService
                                            .insertOrUpdateSubjectAppreciation(
                                              studentId: student.id,
                                              className: className,
                                              academicYear: academicYear,
                                              subject: subject,
                                              term: term,
                                              professeur:
                                                  prof.isNotEmpty && prof != '-'
                                                  ? prof
                                                  : null,
                                              appreciation:
                                                  app.isNotEmpty && app != '-'
                                                  ? app
                                                  : null,
                                              moyenneClasse:
                                                  moy.isNotEmpty && moy != '-'
                                                  ? moy
                                                  : null,
                                              coefficient: coeffs[subject],
                                            );
                                      }
                                    }
                                  }
                                }

                                final currentClass = classes.firstWhere(
                                  (c) =>
                                      c.name ==
                                      (selectedClass ?? student.className),
                                  orElse: () => Class.empty(),
                                );
                                final pdfBytes =
                                    await PdfService.generateReportCardPdf(
                                      student: student,
                                      schoolInfo: info,
                                      grades: (data['grades'] as List)
                                          .cast<Grade>(),
                                      professeurs: professeurs,
                                      appreciations: appreciations,
                                      moyennesClasse: moyennesClasse,
                                      appreciationGenerale:
                                          archived?['appreciation_generale']
                                              as String? ??
                                          '',
                                      decision:
                                          archived?['decision'] as String? ??
                                          '',
                                      recommandations:
                                          archived?['recommandations']
                                              as String? ??
                                          '',
                                      forces:
                                          archived?['forces'] as String? ?? '',
                                      pointsADevelopper:
                                          archived?['points_a_developper']
                                              as String? ??
                                          '',
                                      sanctions:
                                          archived?['sanctions'] as String? ??
                                          '',
                                      attendanceJustifiee:
                                          (archived?['attendance_justifiee']
                                              as int?) ??
                                          0,
                                      attendanceInjustifiee:
                                          (archived?['attendance_injustifiee']
                                              as int?) ??
                                          0,
                                      retards:
                                          (archived?['retards'] as int?) ?? 0,
                                      presencePercent:
                                          ((archived?['presence_percent']
                                                  as num?)
                                              ?.toDouble()) ??
                                          0.0,
                                      conduite:
                                          archived?['conduite'] as String? ??
                                          '',
                                      telEtab: info.telephone ?? '',
                                      mailEtab: info.email ?? '',
                                      webEtab: info.website ?? '',
                                      titulaire: currentClass.titulaire ?? '',
                                      subjects: subjectNames,
                                      moyennesParPeriode:
                                          (data['moyennesParPeriode'] as List)
                                              .cast<double?>(),
                                      moyenneGenerale:
                                          (data['moyenneGenerale'] as num)
                                              .toDouble(),
                                      rang: (data['rang'] as num).toInt(),
                                      exaequo:
                                          (data['exaequo'] as bool?) ?? false,
                                      nbEleves: (data['nbEleves'] as num)
                                          .toInt(),
                                      mention: data['mention'] as String,
                                      allTerms: (data['allTerms'] as List)
                                          .cast<String>(),
                                      periodLabel:
                                          data['periodLabel'] as String,
                                      selectedTerm:
                                          data['selectedTerm'] as String,
                                      academicYear:
                                          data['academicYear'] as String,
                                      faitA:
                                          archived?['fait_a'] as String? ?? '',
                                      leDate:
                                          archived?['le_date'] as String? ?? '',
                                      isLandscape: isLandscape,
                                      niveau: data['niveau'] as String,
                                      moyenneGeneraleDeLaClasse:
                                          (data['moyenneGeneraleDeLaClasse']
                                              as double?),
                                      moyenneLaPlusForte:
                                          (data['moyenneLaPlusForte']
                                              as double?),
                                      moyenneLaPlusFaible:
                                          (data['moyenneLaPlusFaible']
                                              as double?),
                                      moyenneAnnuelle:
                                          (data['moyenneAnnuelle'] as double?),
                                      duplicata: useArchived,
                                    );
                                await Printing.layoutPdf(
                                  onLayout: (format) async =>
                                      Uint8List.fromList(pdfBytes),
                                );
                              } catch (e) {
                                showRootSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Impossible d\'afficher le bulletin: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } else if (value == 'view_custom') {
                              try {
                                final info = await loadSchoolInfo();
                                final orientation =
                                    await showDialog<String>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Orientation du PDF'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              title: const Text('Portrait'),
                                              leading: const Icon(
                                                Icons.stay_current_portrait,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('portrait'),
                                            ),
                                            ListTile(
                                              title: const Text('Paysage'),
                                              leading: const Icon(
                                                Icons.stay_current_landscape,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('landscape'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ) ??
                                    'portrait';
                                final bool isLandscape =
                                    orientation == 'landscape';

                                final formatChoice =
                                    await showDialog<String>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Format du PDF'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              title: const Text(
                                                'Format long (A4 standard)',
                                              ),
                                              subtitle: const Text(
                                                'Dimensions standard A4',
                                              ),
                                              leading: const Icon(
                                                Icons.description,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('long'),
                                            ),
                                            ListTile(
                                              title: const Text(
                                                'Format court (compact)',
                                              ),
                                              subtitle: const Text(
                                                'Dimensions réduites',
                                              ),
                                              leading: const Icon(
                                                Icons.view_compact,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('short'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ) ??
                                    'long';
                                final bool useLongFormat =
                                    formatChoice == 'long';

                                final data = await _prepareReportCardData(
                                  student,
                                );
                                final subjectNames = (data['subjects'] as List)
                                    .cast<String>();
                                final archiveCard = await _dbService
                                    .getReportCardArchive(
                                      studentId: student.id,
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ??
                                          data['academicYear'],
                                      term:
                                          selectedTerm ?? data['selectedTerm'],
                                    );
                                final archived =
                                    archiveCard ??
                                    await _dbService.getReportCard(
                                      studentId: student.id,
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ??
                                          data['academicYear'],
                                      term:
                                          selectedTerm ?? data['selectedTerm'],
                                    );
                                final bool useArchived = archiveCard != null;
                                final apps = useArchived
                                    ? await _dbService
                                          .getSubjectAppreciationsArchiveByKeys(
                                            studentId: student.id,
                                            className:
                                                selectedClass ??
                                                student.className,
                                            academicYear:
                                                selectedAcademicYear ??
                                                data['academicYear'],
                                            term:
                                                selectedTerm ??
                                                data['selectedTerm'],
                                          )
                                    : await _dbService.getSubjectAppreciations(
                                        studentId: student.id,
                                        className:
                                            selectedClass ?? student.className,
                                        academicYear:
                                            selectedAcademicYear ??
                                            data['academicYear'],
                                        term:
                                            selectedTerm ??
                                            data['selectedTerm'],
                                      );
                                final professeurs = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final appreciations = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final moyennesClasse = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final coeffs = <String, double?>{
                                  for (final s in subjectNames) s: null,
                                };
                                for (final row in apps) {
                                  final subject = row['subject'] as String?;
                                  if (subject != null) {
                                    professeurs[subject] =
                                        (row['professeur'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['professeur'] as String
                                        : '-';
                                    appreciations[subject] =
                                        (row['appreciation'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['appreciation'] as String
                                        : '-';
                                    moyennesClasse[subject] =
                                        (row['moyenne_classe'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['moyenne_classe'] as String
                                        : '-';
                                    final coeff = row['coefficient'] as num?;
                                    if (coeff != null) {
                                      coeffs[subject] = coeff.toDouble();
                                    }
                                  }
                                }
                                final className =
                                    selectedClass ?? student.className;
                                final academicYear =
                                    selectedAcademicYear ??
                                    data['academicYear'];
                                if (!useArchived) {
                                  await _applyAssignmentProfessors(
                                    className: className,
                                    academicYear: academicYear,
                                    subjectNames: subjectNames,
                                    professeurs: professeurs,
                                  );
                                }
                                final currentClass = classes.firstWhere(
                                  (c) =>
                                      c.name ==
                                      (selectedClass ?? student.className),
                                  orElse: () => Class.empty(),
                                );
                                final prefs =
                                    await SharedPreferences.getInstance();
                                final footerNote =
                                    prefs.getString(
                                      'report_card_footer_note',
                                    ) ??
                                    '';
                                final adminCivility =
                                    prefs.getString('school_admin_civility') ??
                                    'M.';
                                final pdfBytes =
                                    await ReportCardCustomExportService.generateReportCardCustomPdf(
                                      student: student,
                                      schoolInfo: info,
                                      grades: (data['grades'] as List)
                                          .cast<Grade>(),
                                      subjects: subjectNames,
                                      professeurs: professeurs,
                                      appreciations: appreciations,
                                      moyennesClasse: moyennesClasse,
                                      moyennesParPeriode:
                                          (data['moyennesParPeriode'] as List)
                                              .cast<double?>(),
                                      allTerms: (data['allTerms'] as List)
                                          .cast<String>(),
                                      moyenneGenerale:
                                          (data['moyenneGenerale'] as num)
                                              .toDouble(),
                                      rang: (data['rang'] as num).toInt(),
                                      nbEleves: (data['nbEleves'] as num)
                                          .toInt(),
                                      periodLabel:
                                          data['periodLabel'] as String,
                                      appreciationGenerale:
                                          archived?['appreciation_generale']
                                              as String? ??
                                          '',
                                      mention: data['mention'] as String,
                                      decision:
                                          archived?['decision'] as String? ??
                                          '',
                                      decisionAutomatique:
                                          data['decisionAutomatique']
                                              as String? ??
                                          '',
                                      conduite:
                                          archived?['conduite'] as String? ??
                                          '',
                                      recommandations:
                                          archived?['recommandations']
                                              as String? ??
                                          '',
                                      forces:
                                          archived?['forces'] as String? ?? '',
                                      pointsADevelopper:
                                          archived?['points_a_developper']
                                              as String? ??
                                          '',
                                      sanctions:
                                          archived?['sanctions'] as String? ??
                                          '',
                                      attendanceJustifiee:
                                          (archived?['attendance_justifiee']
                                              as int?) ??
                                          0,
                                      attendanceInjustifiee:
                                          (archived?['attendance_injustifiee']
                                              as int?) ??
                                          0,
                                      retards:
                                          (archived?['retards'] as int?) ?? 0,
                                      presencePercent:
                                          ((archived?['presence_percent']
                                                  as num?)
                                              ?.toDouble()) ??
                                          0.0,
                                      moyenneGeneraleDeLaClasse:
                                          (data['moyenneGeneraleDeLaClasse']
                                              as double?),
                                      moyenneLaPlusForte:
                                          (data['moyenneLaPlusForte']
                                              as double?),
                                      moyenneLaPlusFaible:
                                          (data['moyenneLaPlusFaible']
                                              as double?),
                                      moyenneAnnuelle:
                                          (data['moyenneAnnuelle'] as double?),
                                      moyenneAnnuelleClasse:
                                          (data['moyenneAnnuelleClasse']
                                              as double?),
                                      rangAnnuel: data['rangAnnuel'] as int?,
                                      nbElevesAnnuel:
                                          data['nbElevesAnnuel'] as int?,
                                      academicYear:
                                          data['academicYear'] as String,
                                      term: data['selectedTerm'] as String,
                                      className: className,
                                      selectedTerm:
                                          data['selectedTerm'] as String,
                                      faitA:
                                          archived?['fait_a'] as String? ?? '',
                                      leDate:
                                          archived?['le_date'] as String? ?? '',
                                      titulaireName:
                                          currentClass.titulaire ?? '',
                                      directorName: _resolveDirectorForLevel(
                                        info,
                                        data['niveau'] as String,
                                      ),
                                      titulaireCivility: 'M.',
                                      directorCivility: adminCivility,
                                      footerNote: footerNote,
                                      isLandscape: isLandscape,
                                      duplicata: useArchived,
                                      useLongFormat: useLongFormat,
                                    );
                                await Printing.layoutPdf(
                                  onLayout: (format) async =>
                                      Uint8List.fromList(pdfBytes),
                                );
                              } catch (e) {
                                showRootSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Impossible d\'afficher le bulletin custom: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } else if (value == 'export_custom') {
                              try {
                                final info = await loadSchoolInfo();
                                final orientation =
                                    await showDialog<String>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Orientation du PDF'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              title: const Text('Portrait'),
                                              leading: const Icon(
                                                Icons.stay_current_portrait,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('portrait'),
                                            ),
                                            ListTile(
                                              title: const Text('Paysage'),
                                              leading: const Icon(
                                                Icons.stay_current_landscape,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('landscape'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ) ??
                                    'portrait';
                                final bool isLandscape =
                                    orientation == 'landscape';

                                final formatChoice =
                                    await showDialog<String>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Format du PDF'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              title: const Text(
                                                'Format long (A4 standard)',
                                              ),
                                              subtitle: const Text(
                                                'Dimensions standard A4',
                                              ),
                                              leading: const Icon(
                                                Icons.description,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('long'),
                                            ),
                                            ListTile(
                                              title: const Text(
                                                'Format court (compact)',
                                              ),
                                              subtitle: const Text(
                                                'Dimensions réduites',
                                              ),
                                              leading: const Icon(
                                                Icons.view_compact,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('short'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ) ??
                                    'long';
                                final bool useLongFormat =
                                    formatChoice == 'long';

                                final data = await _prepareReportCardData(
                                  student,
                                );
                                final subjectNames = (data['subjects'] as List)
                                    .cast<String>();
                                final archiveCard = await _dbService
                                    .getReportCardArchive(
                                      studentId: student.id,
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ??
                                          data['academicYear'],
                                      term:
                                          selectedTerm ?? data['selectedTerm'],
                                    );
                                final archived =
                                    archiveCard ??
                                    await _dbService.getReportCard(
                                      studentId: student.id,
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ??
                                          data['academicYear'],
                                      term:
                                          selectedTerm ?? data['selectedTerm'],
                                    );
                                final bool useArchived = archiveCard != null;
                                final apps = useArchived
                                    ? await _dbService
                                          .getSubjectAppreciationsArchiveByKeys(
                                            studentId: student.id,
                                            className:
                                                selectedClass ??
                                                student.className,
                                            academicYear:
                                                selectedAcademicYear ??
                                                data['academicYear'],
                                            term:
                                                selectedTerm ??
                                                data['selectedTerm'],
                                          )
                                    : await _dbService.getSubjectAppreciations(
                                        studentId: student.id,
                                        className:
                                            selectedClass ?? student.className,
                                        academicYear:
                                            selectedAcademicYear ??
                                            data['academicYear'],
                                        term:
                                            selectedTerm ??
                                            data['selectedTerm'],
                                      );
                                final professeurs = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final appreciations = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final moyennesClasse = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final coeffs = <String, double?>{
                                  for (final s in subjectNames) s: null,
                                };
                                for (final row in apps) {
                                  final subject = row['subject'] as String?;
                                  if (subject != null) {
                                    professeurs[subject] =
                                        (row['professeur'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['professeur'] as String
                                        : '-';
                                    appreciations[subject] =
                                        (row['appreciation'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['appreciation'] as String
                                        : '-';
                                    moyennesClasse[subject] =
                                        (row['moyenne_classe'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['moyenne_classe'] as String
                                        : '-';
                                    final coeff = row['coefficient'] as num?;
                                    if (coeff != null) {
                                      coeffs[subject] = coeff.toDouble();
                                    }
                                  }
                                }
                                final className =
                                    selectedClass ?? student.className;
                                final academicYear =
                                    selectedAcademicYear ??
                                    data['academicYear'];
                                if (!useArchived) {
                                  await _applyAssignmentProfessors(
                                    className: className,
                                    academicYear: academicYear,
                                    subjectNames: subjectNames,
                                    professeurs: professeurs,
                                  );
                                }
                                final currentClass = classes.firstWhere(
                                  (c) =>
                                      c.name ==
                                      (selectedClass ?? student.className),
                                  orElse: () => Class.empty(),
                                );
                                final prefs =
                                    await SharedPreferences.getInstance();
                                final footerNote =
                                    prefs.getString(
                                      'report_card_footer_note',
                                    ) ??
                                    '';
                                final adminCivility =
                                    prefs.getString('school_admin_civility') ??
                                    'M.';
                                final pdfBytes =
                                    await ReportCardCustomExportService.generateReportCardCustomPdf(
                                      student: student,
                                      schoolInfo: info,
                                      grades: (data['grades'] as List)
                                          .cast<Grade>(),
                                      subjects: subjectNames,
                                      professeurs: professeurs,
                                      appreciations: appreciations,
                                      moyennesClasse: moyennesClasse,
                                      moyennesParPeriode:
                                          (data['moyennesParPeriode'] as List)
                                              .cast<double?>(),
                                      allTerms: (data['allTerms'] as List)
                                          .cast<String>(),
                                      moyenneGenerale:
                                          (data['moyenneGenerale'] as num)
                                              .toDouble(),
                                      rang: (data['rang'] as num).toInt(),
                                      nbEleves: (data['nbEleves'] as num)
                                          .toInt(),
                                      periodLabel:
                                          data['periodLabel'] as String,
                                      appreciationGenerale:
                                          archived?['appreciation_generale']
                                              as String? ??
                                          '',
                                      mention: data['mention'] as String,
                                      decision:
                                          archived?['decision'] as String? ??
                                          '',
                                      decisionAutomatique:
                                          data['decisionAutomatique']
                                              as String? ??
                                          '',
                                      conduite:
                                          archived?['conduite'] as String? ??
                                          '',
                                      recommandations:
                                          archived?['recommandations']
                                              as String? ??
                                          '',
                                      forces:
                                          archived?['forces'] as String? ?? '',
                                      pointsADevelopper:
                                          archived?['points_a_developper']
                                              as String? ??
                                          '',
                                      sanctions:
                                          archived?['sanctions'] as String? ??
                                          '',
                                      attendanceJustifiee:
                                          (archived?['attendance_justifiee']
                                              as int?) ??
                                          0,
                                      attendanceInjustifiee:
                                          (archived?['attendance_injustifiee']
                                              as int?) ??
                                          0,
                                      retards:
                                          (archived?['retards'] as int?) ?? 0,
                                      presencePercent:
                                          ((archived?['presence_percent']
                                                  as num?)
                                              ?.toDouble()) ??
                                          0.0,
                                      moyenneGeneraleDeLaClasse:
                                          (data['moyenneGeneraleDeLaClasse']
                                              as double?),
                                      moyenneLaPlusForte:
                                          (data['moyenneLaPlusForte']
                                              as double?),
                                      moyenneLaPlusFaible:
                                          (data['moyenneLaPlusFaible']
                                              as double?),
                                      moyenneAnnuelle:
                                          (data['moyenneAnnuelle'] as double?),
                                      moyenneAnnuelleClasse:
                                          (data['moyenneAnnuelleClasse']
                                              as double?),
                                      rangAnnuel: data['rangAnnuel'] as int?,
                                      academicYear:
                                          data['academicYear'] as String,
                                      term: data['selectedTerm'] as String,
                                      className: className,
                                      selectedTerm:
                                          data['selectedTerm'] as String,
                                      faitA:
                                          archived?['fait_a'] as String? ?? '',
                                      leDate:
                                          archived?['le_date'] as String? ?? '',
                                      titulaireName:
                                          currentClass.titulaire ?? '',
                                      directorName: _resolveDirectorForLevel(
                                        info,
                                        data['niveau'] as String,
                                      ),
                                      titulaireCivility: 'M.',
                                      directorCivility: adminCivility,
                                      footerNote: footerNote,
                                      isLandscape: isLandscape,
                                      duplicata: useArchived,
                                      useLongFormat: useLongFormat,
                                    );
                                final directory = await FilePicker.platform
                                    .getDirectoryPath(
                                      dialogTitle: 'Choisir dossier',
                                    );
                                if (directory == null) return;
                                final safeName =
                                    '${student.firstName}_${student.lastName}'
                                        .replaceAll(' ', '_');
                                final safeTerm =
                                    (data['selectedTerm'] as String).replaceAll(
                                      ' ',
                                      '_',
                                    );
                                final safeYear =
                                    (data['academicYear'] as String).replaceAll(
                                      '/',
                                      '_',
                                    );
                                final filePath =
                                    '$directory/Bulletin_custom_${safeName}_${safeTerm}_$safeYear.pdf';
                                final file = File(filePath);
                                await file.writeAsBytes(pdfBytes, flush: true);
                                showSnackBar(
                                  context,
                                  'Export terminé: $filePath',
                                  isError: false,
                                );
                              } catch (e) {
                                showRootSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Impossible d\'exporter le bulletin custom: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'profile',
                              child: Text('Voir le profil'),
                            ),
                            const PopupMenuItem(
                              value: 'view',
                              child: Text('Voir le bulletin'),
                            ),
                            const PopupMenuItem(
                              value: 'view_custom',
                              child: Text('Voir bulletin custom'),
                            ),
                            const PopupMenuItem(
                              value: 'export_custom',
                              child: Text('Exporter bulletin custom'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  _buildPaginationControls(filteredStudents.length),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls(int totalItems) {
    final totalPages = (totalItems / _archiveItemsPerPage).ceil();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: _archiveCurrentPage > 0
              ? () {
                  setState(() {
                    _archiveCurrentPage--;
                  });
                }
              : null,
        ),
        Text('Page ${_archiveCurrentPage + 1} sur $totalPages'),
        IconButton(
          icon: Icon(Icons.arrow_forward),
          onPressed: _archiveCurrentPage < totalPages - 1
              ? () {
                  setState(() {
                    _archiveCurrentPage++;
                  });
                }
              : null,
        ),
      ],
    );
  }

  void _showImportDialog() {
    // Vérifier le mode coffre fort
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          // reset view state
          void resetState() {
            _importError = null;
            _importSuccessCount = 0;
            _importErrorCount = 0;
            _importProgress = 0.0;
            _importRowResults = [];
            setStateDialog(() {});
          }

          Future<void> pickAndValidate() async {
            resetState();
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['xlsx', 'xls', 'csv'],
              withData: true,
            );
            if (result == null || result.files.isEmpty) return;
            _importPickedFile = result.files.first;
            // Taille max 10MB
            if ((_importPickedFile!.size) > 10 * 1024 * 1024) {
              _importError = 'Fichier trop volumineux (>10MB)';
              setStateDialog(() {});
              return;
            }
            _importValidating = true;
            setStateDialog(() {});
            try {
              final bytes =
                  _importPickedFile!.bytes ??
                  await File(_importPickedFile!.path!).readAsBytes();
              final String ext =
                  _importPickedFile!.extension?.toLowerCase() ?? '';
              if (ext == 'csv') {
                await _parseCsvForPreview(
                  bytes,
                  setStateDialog,
                  (e) => _importError = e,
                );
              } else {
                await _parseExcelForPreview(
                  bytes,
                  setStateDialog,
                  (e) => _importError = e,
                );
              }
            } catch (e) {
              _importError = 'Erreur lecture: $e';
            } finally {
              _importValidating = false;
              setStateDialog(() {});
            }
          }

          Future<void> importNow({required bool skipErrors}) async {
            if (_importPreview == null) return;
            if (!SafeModeService.instance.isActionAllowed()) {
              showRootSnackBar(
                SnackBar(
                  content: Text(
                    SafeModeService.instance.getBlockedActionMessage(),
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            if (_isPeriodLocked()) {
              showRootSnackBar(
                SnackBar(
                  content: Text(
                    'Période verrouillée ($_periodWorkflowStatus) : import impossible.',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            _importValidating = true;
            _importError = null;
            _importSuccessCount = 0;
            _importErrorCount = 0;
            _importProgress = 0;
            setStateDialog(() {});
            try {
              final result = await _performBulkImport(
                preview: _importPreview!,
                onProgress: (cur, total) {
                  _importProgress = total == 0 ? 0 : cur / total;
                  setStateDialog(() {});
                },
                onCounts: (ok, ko) {
                  _importSuccessCount = ok;
                  _importErrorCount = ko;
                  setStateDialog(() {});
                },
                skipErrors: skipErrors,
              );
              _importRowResults = result.rowResults;
              // Log import
              final first = _importPreview!.rows.isNotEmpty
                  ? _rowToMap(
                      _importPreview!.headers,
                      _importPreview!.rows.first,
                    )
                  : {};
              await _dbService.insertImportLog(
                filename: (_importPickedFile?.name ?? ''),
                user: null, // TODO: current user
                mode: skipErrors ? 'partial' : 'all_or_nothing',
                className: ((first['Classe'] ?? selectedClass ?? ''))
                    .toString(),
                academicYear: ((first['Annee'] ?? selectedAcademicYear ?? ''))
                    .toString(),
                term: ((first['Periode'] ?? selectedTerm ?? '')).toString(),
                total: _importPreview!.rows.length,
                success: _importSuccessCount,
                errors: _importErrorCount,
                warnings: 0,
                detailsJson: jsonEncode(result.rowResults),
              );
              // Invalider le cache de chargement des synthèses pour refléter les nouvelles valeurs importées
              _loadedReportCardKeys.clear();
              setState(() {});
              // Snackbar succès
              showRootSnackBar(
                SnackBar(
                  content: Text(
                    'Import terminé: ${_importSuccessCount} réussites, ${_importErrorCount} erreurs',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              _importError = '$e';
              showRootSnackBar(
                SnackBar(
                  content: Text('Erreur import: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            } finally {
              _importValidating = false;
              setStateDialog(() {});
            }
          }

          return AlertDialog(
            title: const Text('Import notes depuis Excel/CSV'),
            content: SizedBox(
              width: 900,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isPeriodLocked())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Période verrouillée ($_periodWorkflowStatus) : import désactivé.',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _importValidating ? null : pickAndValidate,
                        icon: const Icon(Icons.attach_file),
                        label: const Text(
                          'Sélectionner un fichier (.xlsx/.xls/.csv)',
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_importValidating)
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _importProgress == 0
                                ? null
                                : _importProgress,
                          ),
                        ),
                    ],
                  ),
                  if (_importError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _importError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildImportPreviewTable(),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        Text(
                          'OK: ${_importSuccessCount}  Erreurs: ${_importErrorCount}',
                        ),
                        OutlinedButton(
                          onPressed:
                              (_importPreview == null ||
                                  _importValidating ||
                                  _isPeriodLocked() ||
                                  !SafeModeService.instance.isActionAllowed())
                              ? null
                              : () => importNow(skipErrors: false),
                          child: const Text('Importer (tout ou rien)'),
                        ),
                        ElevatedButton(
                          onPressed:
                              (_importPreview == null ||
                                  _importValidating ||
                                  _isPeriodLocked() ||
                                  !SafeModeService.instance.isActionAllowed())
                              ? null
                              : () => importNow(skipErrors: true),
                          child: const Text('Importer (ignorer erreurs)'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_importRowResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: _importRowResults.take(100).map((res) {
                          final isError = (res['status'] == 'error');
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isError ? Icons.error : Icons.check_circle,
                              color: isError ? Colors.red : Colors.green,
                              size: 18,
                            ),
                            title: Text(
                              'Ligne ${res['row']} - ${res['status']}',
                            ),
                            subtitle: isError && res['message'] != null
                                ? Text(res['message'])
                                : null,
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImportPreviewTable() {
    if (_importPreview == null) {
      return const SizedBox.shrink();
    }
    final preview = _importPreview!;
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 350),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: preview.headers
              .map((h) => DataColumn(label: Text(h)))
              .toList(),
          rows: preview.rows.take(50).map((r) {
            return DataRow(
              cells: r.map((c) => DataCell(Text(c?.toString() ?? ''))).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _parseExcelForPreview(
    Uint8List bytes,
    void Function(void Function()) setStateDialog,
    void Function(String) setError,
  ) async {
    // Parse simple via 'excel' for headers and values
    try {
      final excel = ex.Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.isNotEmpty
          ? excel.tables.values.first
          : null;
      if (sheet == null) {
        setError('Feuille Excel vide ou invalide');
        return;
      }
      final headers = sheet.rows.isNotEmpty
          ? sheet.rows.first.map((c) => (c?.value ?? '').toString()).toList()
          : <String>[];
      final rows = <List<dynamic>>[];
      for (int i = 1; i < sheet.rows.length; i++) {
        rows.add(sheet.rows[i].map((c) => c?.value).toList());
      }
      _importPreview = _buildPreviewFromHeadersAndRows(headers, rows);
      setStateDialog(() {});
    } catch (e) {
      setError('Erreur parsing Excel: $e');
    }
  }

  Future<void> _parseCsvForPreview(
    Uint8List bytes,
    void Function(void Function()) setStateDialog,
    void Function(String) setError,
  ) async {
    try {
      final content = String.fromCharCodes(bytes);
      // Détection séparateur ; ou ,
      final hasSemicolon = content.contains(';');
      final sep = hasSemicolon ? ';' : ',';
      final lines = content
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        setError('Fichier CSV vide');
        return;
      }
      final headers = lines.first.split(sep);
      final rows = lines
          .skip(1)
          .map((l) => l.split(sep).map((s) => s.trim()).toList())
          .toList();
      _importPreview = _buildPreviewFromHeadersAndRows(headers, rows);
      setStateDialog(() {});
    } catch (e) {
      setError('Erreur parsing CSV: $e');
    }
  }

  _ImportPreview _buildPreviewFromHeadersAndRows(
    List<String> headers,
    List<List<dynamic>> rows,
  ) {
    // Validation d'en-têtes minimales
    final required = ['ID_Eleve', 'Nom', 'Classe', 'Annee', 'Periode'];
    final missing = required.where((r) => !headers.contains(r)).toList();
    final issues = <String>[];
    if (missing.isNotEmpty) {
      issues.add('En-têtes manquants: ${missing.join(', ')}');
    }
    return _ImportPreview(headers: headers, rows: rows, issues: issues);
  }

  Future<_ImportResult> _performBulkImport({
    required _ImportPreview preview,
    required void Function(int current, int total) onProgress,
    required void Function(int ok, int ko) onCounts,
    required bool skipErrors,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      throw Exception(SafeModeService.instance.getBlockedActionMessage());
    }
    if (_isPeriodLocked()) {
      throw Exception(
        'Période verrouillée ($_periodWorkflowStatus) : import impossible.',
      );
    }
    final db = await _dbService.database;
    final total = preview.rows.length;
    int ok = 0, ko = 0, cur = 0;
    final results = <Map<String, dynamic>>[];

    // Backup simple: dupliquer tables grades + subject_appreciation + report_cards en fichiers externes non nécessaire ici (SQLite embarqué).
    // On fera transaction atomique.

    await db.transaction((txn) async {
      for (final row in preview.rows) {
        cur++;
        onProgress(cur, total);
        try {
          final map = _rowToMap(preview.headers, row);
          await _importOneRow(map, txn);
          ok++;
          results.add({'row': cur, 'status': 'ok'});
        } catch (e) {
          ko++;
          results.add({'row': cur, 'status': 'error', 'message': e.toString()});
          if (!skipErrors) {
            throw Exception(e.toString()); // abort transaction
          }
        }
        onCounts(ok, ko);
      }
    });

    // Recharger UI
    await _loadAllGradesForPeriod();
    setState(() {});
    return _ImportResult(results);
  }

  Map<String, dynamic> _rowToMap(List<String> headers, List<dynamic> row) {
    final data = <String, dynamic>{};
    for (int i = 0; i < headers.length && i < row.length; i++) {
      // Convertit les types de cellules possibles (excel) en String brut
      final dynamic cell = row[i];
      final String header = headers[i];
      String toStringCell(dynamic v) {
        if (v == null) return '';
        // excel package: CellValue types have .value
        try {
          final dynamic inner = (v as dynamic).value;
          if (inner != null) return inner.toString();
        } catch (_) {}
        return v.toString();
      }

      // Pour les colonnes texte (ID/Classe/Annee/Periode/Prof/App/MoyClasse/subject), garde en String
      data[header] = toStringCell(cell);
    }
    return data;
  }

  Future<void> _importOneRow(Map<String, dynamic> data, Transaction txn) async {
    // Champs fixes
    final String studentId = (data['ID_Eleve'] ?? '').toString();
    final String className = (data['Classe'] ?? '').toString();
    final String academicYear = (data['Annee'] ?? '').toString();
    final String term = (data['Periode'] ?? '').toString();
    if (studentId.isEmpty ||
        className.isEmpty ||
        academicYear.isEmpty ||
        term.isEmpty) {
      throw Exception('Champs requis manquants');
    }
    // Vérif élève/existence
    final st = await txn.query(
      'students',
      where: 'id = ?',
      whereArgs: [studentId],
    );
    if (st.isEmpty) {
      throw Exception("Élève introuvable: $studentId");
    }
    // Récup matières de la classe (via txn)
    final currentClass = selectedClass ?? className;
    final List<Map<String, dynamic>> subjectRows = await txn.rawQuery(
      '''
      SELECT c.* FROM courses c INNER JOIN class_courses cc ON cc.courseId = c.id WHERE cc.className = ?
    ''',
      [currentClass],
    );
    final subjectNames = subjectRows.map((m) => (m['name'] as String)).toList();

    // Scanner les colonnes matière
    for (final subject in subjectNames) {
      final devKey = 'Devoir [$subject]';
      final compKey = 'Composition [$subject]';
      final coeffDevKey = 'Coeff Devoir [$subject]';
      final coeffCompKey = 'Coeff Composition [$subject]';
      final surDevKey = 'Sur Devoir [$subject]';
      final surCompKey = 'Sur Composition [$subject]';
      final profKey = 'Prof [$subject]';
      final appKey = 'App [$subject]';
      final moyClasseKey = 'MoyClasse [$subject]';

      double? parseNum(dynamic v) {
        if (v == null) return null;
        // unwrap excel CellValue if present
        try {
          final dynamic inner = (v as dynamic).value;
          if (inner is num) return inner.toDouble();
          if (inner is String)
            return double.tryParse(inner.replaceAll(',', '.'));
        } catch (_) {}
        if (v is num) return v.toDouble();
        final s = v.toString().replaceAll(',', '.');
        return double.tryParse(s);
      }

      Future<void> upsertGrade({
        required String type,
        required String label,
        required String valueKey,
        required String coeffKey,
        required String surKey,
      }) async {
        final val = parseNum(data[valueKey]);
        if (val == null) return; // ignore empty
        if (val < 0 || val > 20) {
          throw Exception('Note invalide ($subject/$type): $val');
        }
        final coeff = parseNum(data[coeffKey]) ?? 1.0;
        final sur = parseNum(data[surKey]) ?? 20.0;
        // check existing (inclure label pour gérer plusieurs devoirs/compositions)
        final existing = await txn.query(
          'grades',
          where:
              'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ? AND type = ? AND label = ?',
          whereArgs: [
            studentId,
            className,
            academicYear,
            subject,
            term,
            type,
            label,
          ],
        );
        final courseRow = subjectRows.firstWhere(
          (r) => r['name'] == subject,
          orElse: () => <String, dynamic>{'id': ''},
        );
        final newMap = {
          'studentId': studentId,
          'className': className,
          'academicYear': academicYear,
          'subjectId': courseRow['id'] as String,
          'subject': subject,
          'term': term,
          'value': val,
          'label': label,
          'maxValue': sur,
          'coefficient': coeff,
          'type': type,
        };
        if (existing.isEmpty) {
          await txn.insert('grades', newMap);
        } else {
          await txn.update(
            'grades',
            newMap,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }

      // Import Devoir simple + séries Devoir i
      Future<void> importSeries({
        required String type,
        required String baseKey,
        required String coeffBaseKey,
        required String surBaseKey,
      }) async {
        // Base non numérotée
        await upsertGrade(
          type: type,
          label: type,
          valueKey: baseKey,
          coeffKey: coeffBaseKey,
          surKey: surBaseKey,
        );
        // Série 1..10
        for (int i = 1; i <= 10; i++) {
          final valueKey = '$type $i [$subject]';
          final coeffKey = 'Coeff $type $i [$subject]';
          final surKey = 'Sur $type $i [$subject]';
          final v = parseNum(data[valueKey]);
          if (v == null) continue;
          await upsertGrade(
            type: type,
            label: '$type $i',
            valueKey: valueKey,
            coeffKey:
                (data.containsKey(coeffKey) && parseNum(data[coeffKey]) != null)
                ? coeffKey
                : coeffBaseKey,
            surKey: (data.containsKey(surKey) && parseNum(data[surKey]) != null)
                ? surKey
                : surBaseKey,
          );
        }
      }

      await importSeries(
        type: 'Devoir',
        baseKey: devKey,
        coeffBaseKey: coeffDevKey,
        surBaseKey: surDevKey,
      );
      await importSeries(
        type: 'Composition',
        baseKey: compKey,
        coeffBaseKey: coeffCompKey,
        surBaseKey: surCompKey,
      );

      // Appréciations/prof
      final prof = (data[profKey] ?? '').toString();
      final app = (data[appKey] ?? '').toString();
      String moyClasse = (data[moyClasseKey] ?? '').toString();
      if (prof.isNotEmpty || app.isNotEmpty || moyClasse.isNotEmpty) {
        final existing = await txn.query(
          'subject_appreciation',
          where:
              'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
          whereArgs: [studentId, className, academicYear, subject, term],
        );
        final row = {
          'studentId': studentId,
          'className': className,
          'academicYear': academicYear,
          'subject': subject,
          'term': term,
          'professeur': prof.isNotEmpty ? prof : null,
          'appreciation': app.isNotEmpty ? app : null,
          'moyenne_classe': moyClasse.isNotEmpty ? moyClasse : null,
        };
        if (existing.isEmpty) {
          await txn.insert('subject_appreciation', row);
        } else {
          await txn.update(
            'subject_appreciation',
            row,
            where:
                'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
            whereArgs: [studentId, className, academicYear, subject, term],
          );
        }
      }

      // Calcul/MAJ de la moyenne de classe pour cette matière si non fournie
      try {
        final classSubjectGrades = await txn.query(
          'grades',
          where:
              'className = ? AND academicYear = ? AND term = ? AND subject = ?',
          whereArgs: [className, academicYear, term, subject],
        );
        double total = 0.0, coeffTotal = 0.0;
        for (final g in classSubjectGrades) {
          final double maxValue = (g['maxValue'] is int)
              ? (g['maxValue'] as int).toDouble()
              : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
          final double coefficient = (g['coefficient'] is int)
              ? (g['coefficient'] as int).toDouble()
              : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
          final double value = (g['value'] is int)
              ? (g['value'] as int).toDouble()
              : (g['value'] as num?)?.toDouble() ?? 0.0;
          if (maxValue > 0 && coefficient > 0) {
            total += ((value / maxValue) * 20) * coefficient;
            coeffTotal += coefficient;
          }
        }
        final double? classSubjectAvg = coeffTotal > 0
            ? total / coeffTotal
            : null;
        if (classSubjectAvg != null && (moyClasse.isEmpty)) {
          await txn.update(
            'subject_appreciation',
            {'moyenne_classe': classSubjectAvg.toStringAsFixed(2)},
            where:
                'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
            whereArgs: [studentId, className, academicYear, subject, term],
          );
        }
      } catch (_) {}
    }

    // Recalcul et sauvegarde de la synthèse du bulletin
    final studentGradesRows = await txn.query(
      'grades',
      where: 'className = ? AND academicYear = ? AND term = ?',
      whereArgs: [className, academicYear, term],
    );
    // Calcul moyenne etc. similaire au preview
    final thisStudentGrades = studentGradesRows
        .where((g) => g['studentId'] == studentId)
        .toList();
    double notes = 0, coeffs = 0;
    for (final g in thisStudentGrades) {
      final double maxValue = (g['maxValue'] is int)
          ? (g['maxValue'] as int).toDouble()
          : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
      final double coefficient = (g['coefficient'] is int)
          ? (g['coefficient'] as int).toDouble()
          : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
      final double value = (g['value'] is int)
          ? (g['value'] as int).toDouble()
          : (g['value'] as num?)?.toDouble() ?? 0.0;
      if (maxValue > 0 && coefficient > 0) {
        notes += ((value / maxValue) * 20) * coefficient;
        coeffs += coefficient;
      }
    }
    final moyenne = coeffs > 0 ? notes / coeffs : 0.0;
    final studentsRows = await txn.query(
      'students',
      where: 'className = ?',
      whereArgs: [className],
    );
    final ids = studentsRows.map((r) => r['id'] as String).toList();
    final moyennes = <double>[];
    for (final sid in ids) {
      final sg = studentGradesRows.where((g) => g['studentId'] == sid).toList();
      double n = 0, c = 0;
      for (final g in sg) {
        final double maxValue = (g['maxValue'] is int)
            ? (g['maxValue'] as int).toDouble()
            : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
        final double coefficient = (g['coefficient'] is int)
            ? (g['coefficient'] as int).toDouble()
            : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
        final double value = (g['value'] is int)
            ? (g['value'] as int).toDouble()
            : (g['value'] as num?)?.toDouble() ?? 0.0;
        if (maxValue > 0 && coefficient > 0) {
          n += ((value / maxValue) * 20) * coefficient;
          c += coefficient;
        }
      }
      moyennes.add(c > 0 ? n / c : 0.0);
    }
    moyennes.sort((a, b) => b.compareTo(a));
    final rang = moyennes.indexWhere((m) => (m - moyenne).abs() < 0.001) + 1;
    final double? moyenneGeneraleClasse = moyennes.isNotEmpty
        ? (moyennes.reduce((a, b) => a + b) / moyennes.length)
        : null;
    final double? moyenneLaPlusForte = moyennes.isNotEmpty
        ? moyennes.first
        : null;
    final double? moyenneLaPlusFaible = moyennes.isNotEmpty
        ? moyennes.last
        : null;

    // Moyennes par période (liste ordonnée de toutes les périodes de l'élève)
    final allTermsRows = await txn.query(
      'grades',
      columns: ['term'],
      where: 'studentId = ? AND className = ? AND academicYear = ?',
      whereArgs: [studentId, className, academicYear],
    );
    final termsSet = allTermsRows.map((e) => (e['term'] as String)).toSet();
    List<String> orderedTerms = termsSet.toList();
    if (orderedTerms.any((t) => t.toLowerCase().contains('semestre'))) {
      orderedTerms.sort((a, b) => a.compareTo(b));
      orderedTerms = [
        'Semestre 1',
        'Semestre 2',
      ].where((t) => termsSet.contains(t)).toList();
    } else {
      orderedTerms = [
        'Trimestre 1',
        'Trimestre 2',
        'Trimestre 3',
      ].where((t) => termsSet.contains(t)).toList();
    }
    final List<double?> moyennesParPeriode = [];
    for (final t in orderedTerms) {
      final termGrades = studentGradesRows
          .where((g) => g['studentId'] == studentId && g['term'] == t)
          .toList();
      double tn = 0, tc = 0;
      for (final g in termGrades) {
        final double maxValue = (g['maxValue'] is int)
            ? (g['maxValue'] as int).toDouble()
            : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
        final double coefficient = (g['coefficient'] is int)
            ? (g['coefficient'] as int).toDouble()
            : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
        final double value = (g['value'] is int)
            ? (g['value'] as int).toDouble()
            : (g['value'] as num?)?.toDouble() ?? 0.0;
        if (maxValue > 0 && coefficient > 0) {
          tn += ((value / maxValue) * 20) * coefficient;
          tc += coefficient;
        }
      }
      moyennesParPeriode.add(tc > 0 ? tn / tc : null);
    }

    // Moyenne annuelle (toutes périodes de l'année)
    double? moyenneAnnuelle;
    final allYearGrades = await txn.query(
      'grades',
      where: 'studentId = ? AND className = ? AND academicYear = ?',
      whereArgs: [studentId, className, academicYear],
    );
    if (allYearGrades.isNotEmpty) {
      double an = 0, ac = 0;
      for (final g in allYearGrades) {
        final double maxValue = (g['maxValue'] is int)
            ? (g['maxValue'] as int).toDouble()
            : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
        final double coefficient = (g['coefficient'] is int)
            ? (g['coefficient'] as int).toDouble()
            : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
        final double value = (g['value'] is int)
            ? (g['value'] as int).toDouble()
            : (g['value'] as num?)?.toDouble() ?? 0.0;
        if (maxValue > 0 && coefficient > 0) {
          an += ((value / maxValue) * 20) * coefficient;
          ac += coefficient;
        }
      }
      moyenneAnnuelle = ac > 0 ? an / ac : null;
    }

    // Mention
    String mention;
    if (moyenne >= 19)
      mention = 'EXCELLENT';
    else if (moyenne >= 16)
      mention = 'TRÈS BIEN';
    else if (moyenne >= 14)
      mention = 'BIEN';
    else if (moyenne >= 12)
      mention = 'ASSEZ BIEN';
    else if (moyenne >= 10)
      mention = 'PASSABLE';
    else
      mention = 'INSUFFISANT';
    final existingRc = await txn.query(
      'report_cards',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, term],
    );
    // Conserver/Mettre à jour les champs texte si déjà saisis auparavant ou importés
    Map<String, dynamic> previous = {};
    if (existingRc.isNotEmpty) {
      previous = existingRc.first;
    }
    // Lire éventuellement depuis la ligne importée si présente
    String apprGen = (data['Appreciation Generale'] ?? '').toString();
    String decision = (data['Decision'] ?? '').toString();
    String recommandations = (data['Recommandations'] ?? '').toString();
    String forces = (data['Forces'] ?? '').toString();
    String pointsDev = (data['Points a Developper'] ?? '').toString();
    String sanctions = (data['Sanctions'] ?? '').toString();

    // Assiduité (heures) depuis import si présents
    int? absJust = int.tryParse((data['Abs Justifiees'] ?? '').toString());
    int? absInj = int.tryParse((data['Abs Injustifiees'] ?? '').toString());
    int? retards = int.tryParse((data['Retards'] ?? '').toString());
    double? presence = double.tryParse(
      (data['Presence (%)'] ?? '').toString().replaceAll(',', '.'),
    );
    String conduite = (data['Conduite'] ?? '').toString();
    final rcData = {
      'studentId': studentId,
      'className': className,
      'academicYear': academicYear,
      'term': term,
      'moyenne_generale': moyenne,
      'rang': rang,
      'nb_eleves': ids.length,
      'mention': mention,
      'moyennes_par_periode': moyennesParPeriode.toString(),
      'all_terms': orderedTerms.toString(),
      'moyenne_generale_classe': moyenneGeneraleClasse,
      'moyenne_la_plus_forte': moyenneLaPlusForte,
      'moyenne_la_plus_faible': moyenneLaPlusFaible,
      'moyenne_annuelle': moyenneAnnuelle,
      'appreciation_generale': apprGen.isNotEmpty
          ? apprGen
          : previous['appreciation_generale'],
      'decision': decision.isNotEmpty ? decision : previous['decision'],
      'recommandations': recommandations.isNotEmpty
          ? recommandations
          : previous['recommandations'],
      'forces': forces.isNotEmpty ? forces : previous['forces'],
      'points_a_developper': pointsDev.isNotEmpty
          ? pointsDev
          : previous['points_a_developper'],
      'attendance_justifiee': absJust ?? previous['attendance_justifiee'],
      'attendance_injustifiee': absInj ?? previous['attendance_injustifiee'],
      'retards': retards ?? previous['retards'],
      'presence_percent': presence ?? previous['presence_percent'],
      'conduite': conduite.isNotEmpty ? conduite : previous['conduite'],
      'sanctions': sanctions.isNotEmpty ? sanctions : previous['sanctions'],
    };
    if (existingRc.isEmpty) {
      await txn.insert('report_cards', rcData);
    } else {
      await txn.update(
        'report_cards',
        rcData,
        where:
            'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
        whereArgs: [studentId, className, academicYear, term],
      );
    }
  }

  Future<void> _openEvaluationTemplatesDialog() async {
    // Vérifier le mode coffre fort
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    final cls = (selectedClass ?? '').trim();
    final year = (_effectiveSelectedAcademicYear() ?? '').trim();
    final subjectName = (selectedSubject ?? '').trim();
    if (cls.isEmpty || year.isEmpty || subjectName.isEmpty) {
      showRootSnackBar(
        const SnackBar(
          content: Text('Sélectionnez une classe, une année et une matière.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final course = subjects.firstWhere(
      (c) => c.name == subjectName,
      orElse: () => Course.empty(),
    );
    if (course.id.trim().isEmpty) {
      showRootSnackBar(
        const SnackBar(
          content: Text('Matière invalide.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    List<EvaluationTemplate> templates = await _dbService
        .getEvaluationTemplates(
          className: cls,
          academicYear: year,
          subjectId: course.id,
        );
    double defaultCoeff = 1.0;
    try {
      final subjectCoeffs = await _dbService.getClassSubjectCoefficients(
        cls,
        year,
      );
      final v = subjectCoeffs[subjectName];
      if (v != null && v > 0) defaultCoeff = v;
    } catch (_) {}

    Future<void> reload(StateSetter setDialogState) async {
      final t = await _dbService.getEvaluationTemplates(
        className: cls,
        academicYear: year,
        subjectId: course.id,
      );
      setDialogState(() => templates = t);
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final devoir =
              templates.where((t) => t.type.toLowerCase() == 'devoir').toList()
                ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
          final compo =
              templates
                  .where((t) => t.type.toLowerCase() == 'composition')
                  .toList()
                ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

          Widget section(String title, List<EvaluationTemplate> list) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  Text(
                    'Aucun modèle.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  ...list.map((t) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.label),
                      subtitle: Text(
                        'Sur ${t.maxValue.toStringAsFixed(0)} • Coeff ${t.coefficient.toStringAsFixed(2)} • Ordre ${t.orderIndex}',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Modifier',
                            onPressed: () async {
                              final edited =
                                  await _showEvaluationTemplateFormDialog(
                                    className: cls,
                                    academicYear: year,
                                    subject: course,
                                    existing: t,
                                    defaultCoefficient: defaultCoeff,
                                  );
                              if (edited == null) return;
                              await _dbService.upsertEvaluationTemplate(edited);
                              await reload(setDialogState);
                            },
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            tooltip: 'Supprimer',
                            onPressed: () async {
                              final ok = await _confirmDeleteEvaluationTemplate(
                                t,
                              );
                              if (!ok) return;
                              if (t.id != null) {
                                await _dbService.deleteEvaluationTemplate(
                                  t.id!,
                                );
                                await reload(setDialogState);
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            );
          }

          return AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Icon(Icons.rule, color: AppColors.primaryBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Modèles d'évaluations - $subjectName",
                          style: Theme.of(context).textTheme.headlineMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
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
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.6,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Définissez le libellé, le barème et le coefficient pour les évaluations.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    section('Devoirs', devoir),
                    const SizedBox(height: 16),
                    section('Compositions', compo),
                    const SizedBox(height: 8),
                    if (templates.isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            await _dbService.ensureDefaultEvaluationTemplates(
                              className: cls,
                              academicYear: year,
                              subject: course,
                            );
                            await reload(setDialogState);
                          },
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Créer les modèles par défaut'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final created = await _showEvaluationTemplateFormDialog(
                    className: cls,
                    academicYear: year,
                    subject: course,
                    defaultCoefficient: defaultCoeff,
                  );
                  if (created == null) return;
                  await _dbService.upsertEvaluationTemplate(created);
                  await reload(setDialogState);
                },
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );

    await _loadEvaluationTemplatesForCurrentSelection();
  }

  Future<bool> _confirmDeleteEvaluationTemplate(EvaluationTemplate t) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le modèle ?'),
        content: Text('Supprimer "${t.label}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<EvaluationTemplate?> _showEvaluationTemplateFormDialog({
    required String className,
    required String academicYear,
    required Course subject,
    EvaluationTemplate? existing,
    double? defaultCoefficient,
  }) async {
    final labelController = TextEditingController(text: existing?.label ?? '');
    final maxController = TextEditingController(
      text: (existing?.maxValue ?? 20).toString(),
    );
    final coeffController = TextEditingController(
      text:
          (existing?.coefficient ??
                  (defaultCoefficient != null && defaultCoefficient > 0
                      ? defaultCoefficient
                      : 1))
              .toString(),
    );
    final orderController = TextEditingController(
      text: (existing?.orderIndex ?? 1).toString(),
    );
    String selectedType = (existing?.type ?? 'Devoir').trim().isNotEmpty
        ? (existing?.type ?? 'Devoir')
        : 'Devoir';

    final result = await showDialog<EvaluationTemplate>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Ajouter un modèle' : 'Modifier le modèle',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'Devoir', child: Text('Devoir')),
                    DropdownMenuItem(
                      value: 'Composition',
                      child: Text('Composition'),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedType = v ?? 'Devoir'),
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Libellé',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: maxController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Sur',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: coeffController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Coefficient',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: orderController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ordre',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                final label = labelController.text.trim();
                final max = double.tryParse(maxController.text.trim());
                final coeff = double.tryParse(coeffController.text.trim());
                final order = int.tryParse(orderController.text.trim());
                if (label.isEmpty ||
                    max == null ||
                    coeff == null ||
                    order == null) {
                  showRootSnackBar(
                    const SnackBar(
                      content: Text(
                        'Veuillez remplir correctement tous les champs.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop(
                  EvaluationTemplate(
                    id: existing?.id,
                    className: className,
                    academicYear: academicYear,
                    subjectId: subject.id,
                    subject: subject.name,
                    type: selectedType,
                    label: label,
                    maxValue: max,
                    coefficient: coeff,
                    orderIndex: order,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<void> _showBulkGradeDialog() async {
    // Vérifier le mode coffre fort
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    if (selectedClass == null || selectedSubject == null) {
      showRootSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner une classe et une matière.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Restreindre aux élèves de l'année académique en cours de saisie
    String? classYear;
    if (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty) {
      classYear = selectedAcademicYear;
    } else {
      classYear = classes
          .firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          )
          .academicYear;
    }
    final String effectiveYear = (classYear != null && classYear.isNotEmpty)
        ? classYear
        : academicYearNotifier.value;
    debugPrint(
      '[GradesPage] Saisie Rapide -> class=$selectedClass subject=$selectedSubject term=$selectedTerm year=$effectiveYear',
    );
    final classStudents = await _dbService.getStudents(
      className: selectedClass!,
      academicYear: effectiveYear,
    );
    classStudents.sort(_compareStudentsByName);
    // Charger le coefficient de la matière au niveau de la classe (détails de la classe)
    final Map<String, double> classWeights = await _dbService
        .getClassSubjectCoefficients(selectedClass!, effectiveYear);
    final double? subjectWeight = selectedSubject != null
        ? classWeights[selectedSubject!]
        : null;
    debugPrint(
      '[GradesPage] Saisie Rapide -> students.count=${classStudents.length}',
    );
    final course = subjects.firstWhere(
      (c) => c.name == selectedSubject,
      orElse: () => Course.empty(),
    );
    await _loadEvaluationTemplatesForCurrentSelection();
    if (_currentDevoirTemplates.isEmpty &&
        _currentCompositionTemplates.isEmpty &&
        course.id.trim().isNotEmpty) {
      await _dbService.ensureDefaultEvaluationTemplates(
        className: selectedClass!,
        academicYear: effectiveYear,
        subject: course,
      );
      await _loadEvaluationTemplatesForCurrentSelection();
    }
    final devoirTemplates = List<EvaluationTemplate>.from(
      _currentDevoirTemplates,
    );
    final compositionTemplates = List<EvaluationTemplate>.from(
      _currentCompositionTemplates,
    );
    final List<EvaluationTemplate> allTemplates = [
      ...devoirTemplates,
      ...compositionTemplates,
    ];

    String templateKey(EvaluationTemplate t) {
      if (t.id != null) return 'id:${t.id}';
      return '${t.type}::${t.label}';
    }

    String fieldKey(String studentId, EvaluationTemplate t) =>
        '$studentId::${templateKey(t)}';

    final Map<String, TextEditingController> templateControllers = {};
    for (final student in classStudents) {
      for (final tpl in allTemplates) {
        final g = _findGradeForTemplate(
          studentId: student.id,
          className: selectedClass!,
          academicYear: effectiveYear,
          term: selectedTerm!,
          subject: selectedSubject!,
          type: tpl.type,
          label: tpl.label,
        );
        templateControllers[fieldKey(student.id, tpl)] = TextEditingController(
          text: g != null ? g.value.toString() : '',
        );
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, _) => AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.edit_note, color: AppColors.primaryBlue),
                    const SizedBox(width: 10),
                    Text(
                      'Saisie Rapide - ${selectedSubject!}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: 12),
                    if (subjectWeight != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Text(
                          'Coeff. matière: ${subjectWeight.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
          content: Container(
            width: MediaQuery.of(context).size.width * 0.7,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (allTemplates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Aucun modèle défini pour cette matière. Cliquez sur "Modèles" pour en créer.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => _openEvaluationTemplatesDialog(),
                            icon: const Icon(Icons.rule),
                            label: const Text('Modèles'),
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...allTemplates.map((t) {
                            final typeShort = t.type.toLowerCase() == 'devoir'
                                ? 'D'
                                : 'C';
                            return Chip(
                              label: Text(
                                '$typeShort • ${t.label} • Sur ${t.maxValue.toStringAsFixed(0)} • Coeff ${t.coefficient.toStringAsFixed(2)}',
                              ),
                            );
                          }),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _openEvaluationTemplatesDialog(),
                            icon: const Icon(Icons.rule),
                            label: const Text('Modèles'),
                          ),
                        ],
                      ),
                    ),
                  if (subjectWeight != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Coeff. matière (classe): ' +
                            subjectWeight.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      columnWidths: {
                        0: const FixedColumnWidth(240),
                        for (int i = 0; i < allTemplates.length; i++)
                          i + 1: const FixedColumnWidth(180),
                      },
                      border: TableBorder.all(
                        color: Theme.of(context).dividerColor,
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.1),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                'Élève',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            ...allTemplates.map((t) {
                              final typeShort = t.type.toLowerCase() == 'devoir'
                                  ? 'D'
                                  : 'C';
                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: 180,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$typeShort • ${t.label}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Sur ${t.maxValue.toStringAsFixed(0)} • Coeff ${t.coefficient.toStringAsFixed(2)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        ...classStudents.map((student) {
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  _displayStudentName(student),
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                              ...allTemplates.map((t) {
                                return Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: SizedBox(
                                    width: 180,
                                    child: TextFormField(
                                      controller:
                                          templateControllers[fieldKey(
                                            student.id,
                                            t,
                                          )],
                                      enabled:
                                          SafeModeService.instance
                                              .isActionAllowed() &&
                                          !_isPeriodLocked(),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (_isPeriodLocked()) {
                  showRootSnackBar(
                    SnackBar(
                      content: Text(
                        'Période verrouillée ($_periodWorkflowStatus) : modification impossible.',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                for (final student in classStudents) {
                  for (final t in allTemplates) {
                    final raw = templateControllers[fieldKey(student.id, t)]!
                        .text
                        .trim();
                    final note = double.tryParse(raw);
                    if (note == null) continue;
                    await _saveGrade(
                      student,
                      t.type,
                      t.label,
                      note,
                      t.coefficient,
                      t.maxValue,
                      academicYearOverride: effectiveYear,
                    );
                  }
                }
                await _loadAllGradesForPeriod();
                Navigator.of(context).pop();
                showRootSnackBar(
                  const SnackBar(
                    content: Text('Notes enregistrées avec succès.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Tout Enregistrer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveGrade(
    Student student,
    String type,
    String label,
    double value,
    double coefficient,
    double maxValue, {
    String? academicYearOverride,
  }) async {
    if (_isPeriodLocked()) {
      showRootSnackBar(
        SnackBar(
          content: Text(
            'Période verrouillée ($_periodWorkflowStatus) : modification impossible.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_ensureTeacherCanEditSelection()) return;
    final course = subjects.firstWhere(
      (c) => c.name == selectedSubject,
      orElse: () => Course.empty(),
    );
    final String year =
        (academicYearOverride ?? _effectiveSelectedAcademicYear() ?? '')
            .trim()
            .isNotEmpty
        ? (academicYearOverride ?? _effectiveSelectedAcademicYear() ?? '')
              .trim()
        : academicYearNotifier.value;
    final grade = _findGradeForTemplate(
      studentId: student.id,
      className: selectedClass!,
      academicYear: year,
      term: selectedTerm!,
      subject: selectedSubject!,
      type: type,
      label: label,
    );

    final newGrade = Grade(
      id: grade?.id,
      studentId: student.id,
      className: selectedClass!,
      academicYear: year,
      subjectId: course.id,
      subject: selectedSubject!,
      term: selectedTerm!,
      value: value,
      label: label,
      type: type,
      coefficient: coefficient,
      maxValue: maxValue,
    );
    if (grade == null) {
      await _dbService.insertGrade(newGrade);
    } else {
      await _dbService.updateGrade(newGrade);
    }
  }

  Future<Map<String, dynamic>> _prepareReportCardData(Student student) async {
    final info = await loadSchoolInfo();
    final String effectiveYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : (selectedClass != null
              ? (classes
                    .firstWhere(
                      (c) => c.name == selectedClass,
                      orElse: () => Class.empty(),
                    )
                    .academicYear)
              : academicYearNotifier.value);
    final schoolYear = effectiveYear;
    final periodLabel = _periodMode == 'Trimestre' ? 'Trimestre' : 'Semestre';
    final Class classInfo = classes.firstWhere(
      (c) => c.name == selectedClass && c.academicYear == effectiveYear,
      orElse: () => Class.empty(),
    );
    final String niveau = (classInfo.level?.trim().isNotEmpty ?? false)
        ? classInfo.level!.trim()
        : schoolLevelNotifier.value;

    // Charger les notes et les matières directement depuis la base de données
    // (Les listes 'grades' et 'subjects' en mémoire peuvent être incomplètes lors d'un export massif)
    final List<Grade> allGradesForPeriod = await _dbService
        .getAllGradesForPeriod(
          className: selectedClass!,
          academicYear: effectiveYear,
          term: selectedTerm!,
        );

    final studentGrades = allGradesForPeriod
        .where((g) => g.studentId == student.id)
        .toList();

    final List<Course> effectiveSubjects = await _dbService.getCoursesForClass(
      selectedClass!,
      effectiveYear,
    );

    final subjectNames = effectiveSubjects.map((c) => c.name).toList();

    // Charger coefficients de matières définis au niveau de la classe
    final Map<String, double> subjectWeightsById = await _dbService
        .getClassCourseCoefficientsById(selectedClass!, effectiveYear);
    final Map<String, double> subjectWeightsByName = await _dbService
        .getClassSubjectCoefficients(selectedClass!, effectiveYear);
    // --- Moyennes par période ---
    final List<String> allTerms = _periodMode == 'Trimestre'
        ? ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']
        : ['Semestre 1', 'Semestre 2'];
    final List<double?> moyennesParPeriode = [];

    // Récupérer la liste officielle des élèves de la classe pour filtrer les calculs
    final currentClassStudents = await _dbService
        .getStudentsByClassAndClassYear(selectedClass!, effectiveYear);
    final Set<String> classStudentIdsSet = currentClassStudents
        .map((s) => s.id)
        .toSet();
    final List<String> classStudentIds = classStudentIdsSet.toList();

    // Pour le calcul annuel, on agrégera toutes les notes des périodes
    double totalAnnualPoints = 0.0;
    double totalAnnualWeights = 0.0;
    // Pour la moyenne annuelle de la classe et le rang annuel
    final Map<String, double> nAnnualByStudent = {};
    final Map<String, double> cAnnualByStudent = {};
    for (final term in allTerms) {
      // Charger toutes les notes de la classe pour la période, puis filtrer l'élève
      final periodGrades = await _dbService.getAllGradesForPeriod(
        className: selectedClass!,
        academicYear: effectiveYear,
        term: term,
      );
      // Calcul pondéré par matière pour l'élève
      double sumPts = 0.0;
      double sumW = 0.0;
      for (final course in effectiveSubjects) {
        final sg = periodGrades
            .where(
              (g) =>
                  g.studentId == student.id &&
                  (g.subjectId.trim().isNotEmpty
                      ? g.subjectId == course.id
                      : g.subject == course.name) &&
                  (g.type == 'Devoir' || g.type == 'Composition'),
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
        final double moyM = c > 0 ? (n / c) : 0.0;
        final double w =
            subjectWeightsById[course.id] ??
            subjectWeightsByName[course.name] ??
            c;
        if (w > 0) {
          sumPts += moyM * w;
          sumW += w;
        }
      }
      moyennesParPeriode.add(sumW > 0 ? (sumPts / sumW) : null);
      // Agrégation annuelle pondérée
      totalAnnualPoints += sumPts;
      totalAnnualWeights += sumW;
      // Agréger pour la classe (par élève) pour l'annuel - UNIQUEMENT pour les élèves de la classe
      for (final g in periodGrades.where(
        (g) =>
            classStudentIdsSet.contains(g.studentId) &&
            (g.type == 'Devoir' || g.type == 'Composition'),
      )) {
        if (g.maxValue > 0 && g.coefficient > 0) {
          nAnnualByStudent[g.studentId] =
              (nAnnualByStudent[g.studentId] ?? 0) +
              ((g.value / g.maxValue) * 20) * g.coefficient;
          cAnnualByStudent[g.studentId] =
              (cAnnualByStudent[g.studentId] ?? 0) + g.coefficient;
        }
      }
    }

    // Calcul de la moyenne générale pondérée par coefficients de matières (période sélectionnée)
    double sumPtsSel = 0.0;
    double sumWSel = 0.0;
    final Map<String, double?> subjectAverages = {};
    for (final course in effectiveSubjects) {
      final sg = studentGrades
          .where(
            (g) =>
                (g.subjectId.trim().isNotEmpty
                    ? g.subjectId == course.id
                    : g.subject == course.name) &&
                (g.type == 'Devoir' || g.type == 'Composition'),
          )
          .toList();
      if (sg.isEmpty) {
        subjectAverages[course.name] = null;
        continue;
      }
      double n = 0.0;
      double c = 0.0;
      for (final g in sg) {
        if (g.maxValue > 0 && g.coefficient > 0) {
          n += ((g.value / g.maxValue) * 20) * g.coefficient;
          c += g.coefficient;
        }
      }
      final double moyM = c > 0 ? (n / c) : 0.0;
      subjectAverages[course.name] = moyM;
      final double w =
          subjectWeightsById[course.id] ??
          subjectWeightsByName[course.name] ??
          c;
      if (w > 0) {
        sumPtsSel += moyM * w;
        sumWSel += w;
      }
    }
    final moyenneGenerale = sumWSel > 0 ? (sumPtsSel / sumWSel) : 0.0;

    // Calcul de la moyenne annuelle (toutes périodes de l'année)
    double? moyenneAnnuelle;
    if (totalAnnualWeights > 0) {
      moyenneAnnuelle = totalAnnualPoints / totalAnnualWeights;
    }
    // Moyenne annuelle de la classe et rang annuel
    double? moyenneAnnuelleClasse;
    int? rangAnnuel;
    int? nbElevesAnnuel;
    if (nAnnualByStudent.isNotEmpty) {
      final List<double> annualAvgs = [];
      double? myAnnual;
      nAnnualByStudent.forEach((sid, n) {
        final c = cAnnualByStudent[sid] ?? 0.0;
        final avg = c > 0 ? (n / c) : 0.0;
        if (c > 0) {
          // Ne compter que les élèves avec des coefficients > 0
          annualAvgs.add(avg);
          if (sid == student.id) myAnnual = avg;
        }
      });
      if (annualAvgs.isNotEmpty && myAnnual != null) {
        moyenneAnnuelleClasse =
            annualAvgs.reduce((a, b) => a + b) / annualAvgs.length;
        annualAvgs.sort((a, b) => b.compareTo(a));
        // Calcul du rang : nombre d'élèves avec une moyenne strictement supérieure
        final double myAnnualValue = myAnnual!;
        rangAnnuel =
            1 + annualAvgs.where((v) => v > myAnnualValue + 0.001).length;
        nbElevesAnnuel = annualAvgs.length;
      }
    }

    // Calcul du rang et statistiques de classe (effectif basé sur l'année en cours uniquement)
    // Strict effectif: class academicYear must match (guard against student rows with mismatched year)
    final List<double> allMoyennes = classStudentIds.map((sid) {
      final sg = allGradesForPeriod
          .where(
            (g) =>
                g.studentId == sid &&
                (g.type == 'Devoir' || g.type == 'Composition'),
          )
          .toList();
      double pts = 0.0;
      double wsum = 0.0;
      for (final course in effectiveSubjects) {
        final sl = sg
            .where(
              (g) => (g.subjectId.trim().isNotEmpty
                  ? g.subjectId == course.id
                  : g.subject == course.name),
            )
            .toList();
        if (sl.isEmpty) continue;
        double n = 0.0;
        double c = 0.0;
        for (final g in sl) {
          if (g.maxValue > 0 && g.coefficient > 0) {
            n += ((g.value / g.maxValue) * 20) * g.coefficient;
            c += g.coefficient;
          }
        }
        final double moyM = c > 0 ? (n / c) : 0.0;
        final double w =
            subjectWeightsById[course.id] ??
            subjectWeightsByName[course.name] ??
            c;
        if (w > 0) {
          pts += moyM * w;
          wsum += w;
        }
      }
      return wsum > 0 ? (pts / wsum) : 0.0;
    }).toList();
    allMoyennes.sort((a, b) => b.compareTo(a));
    const double eps = 0.001;
    final rang =
        allMoyennes.indexWhere((m) => (m - moyenneGenerale).abs() < eps) + 1;
    final int tiesCount = allMoyennes
        .where((m) => (m - moyenneGenerale).abs() < eps)
        .length;
    final bool isExAequo = tiesCount > 1;
    final int nbEleves = classStudentIds.length;
    final double? moyenneGeneraleDeLaClasse = allMoyennes.isNotEmpty
        ? allMoyennes.reduce((a, b) => a + b) / allMoyennes.length
        : null;
    final double? moyenneLaPlusForte = allMoyennes.isNotEmpty
        ? allMoyennes.reduce((a, b) => a > b ? a : b)
        : null;
    final double? moyenneLaPlusFaible = allMoyennes.isNotEmpty
        ? allMoyennes.reduce((a, b) => a < b ? a : b)
        : null;

    // Mention
    String mention;
    if (moyenneGenerale >= 19) {
      mention = 'EXCELLENT';
    } else if (moyenneGenerale >= 16) {
      mention = 'TRÈS BIEN';
    } else if (moyenneGenerale >= 14) {
      mention = 'BIEN';
    } else if (moyenneGenerale >= 12) {
      mention = 'ASSEZ BIEN';
    } else if (moyenneGenerale >= 10) {
      mention = 'PASSABLE';
    } else {
      mention = 'INSUFFISANT';
    }

    // Décision automatique du conseil de classe basée sur la moyenne annuelle
    // Ne s'affiche qu'en fin d'année (Trimestre 3 ou Semestre 2)
    String? decisionAutomatique;
    final bool isEndOfYear =
        selectedTerm == 'Trimestre 3' || selectedTerm == 'Semestre 2';

    if (isEndOfYear) {
      // Récupérer les seuils spécifiques à la classe
      final seuils = await _dbService.getClassPassingThresholds(
        selectedClass ?? '',
        effectiveYear,
      );

      final double moyenne = moyenneAnnuelle ?? moyenneGenerale;

      if (moyenne >= seuils['felicitations']!) {
        decisionAutomatique = 'Admis en classe supérieure avec félicitations';
      } else if (moyenne >= seuils['encouragements']!) {
        decisionAutomatique = 'Admis en classe supérieure avec encouragements';
      } else if (moyenne >= seuils['admission']!) {
        decisionAutomatique = 'Admis en classe supérieure';
      } else if (moyenne >= seuils['avertissement']!) {
        decisionAutomatique = 'Admis en classe supérieure avec avertissement';
      } else if (moyenne >= seuils['conditions']!) {
        decisionAutomatique = 'Admis en classe supérieure sous conditions';
      } else {
        decisionAutomatique = 'Redouble la classe';
      }
    }

    return {
      'student': student,
      'schoolInfo': info,
      'grades': studentGrades,
      'subjects': subjectNames,
      'effectiveSubjects': effectiveSubjects,
      'subjectAverages': subjectAverages,
      'moyennesParPeriode': moyennesParPeriode,
      'moyenneGenerale': moyenneGenerale,
      'rang': rang,
      'exaequo': isExAequo,
      'nbEleves': nbEleves,
      'mention': mention,
      'allTerms': allTerms,
      'periodLabel': periodLabel,
      'selectedTerm': selectedTerm ?? '',
      'academicYear': schoolYear,
      'niveau': niveau,
      'moyenneGeneraleDeLaClasse': moyenneGeneraleDeLaClasse,
      'moyenneLaPlusForte': moyenneLaPlusForte,
      'moyenneLaPlusFaible': moyenneLaPlusFaible,
      'moyenneAnnuelle': moyenneAnnuelle,
      'moyenneAnnuelleClasse': moyenneAnnuelleClasse,
      'rangAnnuel': rangAnnuel,
      'nbElevesAnnuel': nbElevesAnnuel,
      'decisionAutomatique': decisionAutomatique,
    };
  }

  Future<Map<String, dynamic>?> _buildCustomReportCardPdfPayload({
    required Student student,
    required SchoolInfo info,
    required List<String> subjectNames,
    required Map<String, TextEditingController> profCtrls,
    required Map<String, TextEditingController> appreciationCtrls,
    required Map<String, TextEditingController> moyClasseCtrls,
    required TextEditingController generalAppreciationCtrl,
    required TextEditingController decisionCtrl,
    required TextEditingController conduiteCtrl,
    required TextEditingController faitACtrl,
    required TextEditingController absJustifieesCtrl,
    required TextEditingController absInjustifieesCtrl,
    required TextEditingController retardsCtrl,
    required TextEditingController presencePercentCtrl,
    required TextEditingController recommandationsCtrl,
    required TextEditingController forcesCtrl,
    required TextEditingController pointsDevelopperCtrl,
    required TextEditingController sanctionsCtrl,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return null;
    }

    final orientation =
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Orientation du PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('Portrait'),
                  leading: Icon(Icons.stay_current_portrait),
                  onTap: () => Navigator.of(context).pop('portrait'),
                ),
                ListTile(
                  title: Text('Paysage'),
                  leading: Icon(Icons.stay_current_landscape),
                  onTap: () => Navigator.of(context).pop('landscape'),
                ),
              ],
            ),
          ),
        ) ??
        'portrait';
    final isLandscape = orientation == 'landscape';

    final formatChoice =
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Format du PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Format long (agrandi)'),
                  subtitle: const Text('Dimensions agrandies'),
                  leading: const Icon(Icons.description),
                  onTap: () => Navigator.of(context).pop('long'),
                ),
                ListTile(
                  title: const Text('Format court (A4 standard)'),
                  subtitle: const Text('Dimensions standard A4'),
                  leading: const Icon(Icons.view_compact),
                  onTap: () => Navigator.of(context).pop('short'),
                ),
              ],
            ),
          ),
        ) ??
        'long';
    final bool useLongFormat = formatChoice == 'long';

    final data = await _prepareReportCardData(student);

    final professeurs = <String, String>{
      for (final subject in subjectNames)
        subject: (profCtrls[subject]?.text ?? '').trim().isNotEmpty
            ? (profCtrls[subject]?.text ?? '').trim()
            : '-',
    };
    await _applyAssignmentProfessors(
      className: selectedClass ?? student.className,
      academicYear: selectedAcademicYear ?? academicYearNotifier.value,
      subjectNames: subjectNames,
      professeurs: professeurs,
    );

    final appreciations = <String, String>{
      for (final subject in subjectNames)
        subject: (() {
          final manual = (appreciationCtrls[subject]?.text ?? '').trim();
          if (manual.isNotEmpty && manual != '-') return manual;

          // Fallback automatique via les moyennes déjà calculées
          final double? avg =
              (data['subjectAverages'] as Map<String, double?>)[subject];
          if (avg != null) return _getAutomaticAppreciation(avg);
          return '-';
        })(),
    };

    final moyennesClasse = <String, String>{
      for (final subject in subjectNames)
        subject: (moyClasseCtrls[subject]?.text ?? '').trim().isNotEmpty
            ? (moyClasseCtrls[subject]?.text ?? '').trim()
            : '-',
    };
    final prefs = await SharedPreferences.getInstance();
    final footerNote = prefs.getString('report_card_footer_note') ?? '';
    final adminCivility = prefs.getString('school_admin_civility') ?? 'M.';
    final appreciationGenerale = generalAppreciationCtrl.text;
    final decision = decisionCtrl.text;
    final conduite = conduiteCtrl.text;
    final sanctions = sanctionsCtrl.text;
    final String faitA = _faitAController.text.trim().isNotEmpty
        ? _faitAController.text.trim()
        : info.address;
    final String leDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final classNameForPdf = selectedClass ?? student.className;
    final currentClass = classes.firstWhere(
      (c) =>
          c.name == classNameForPdf &&
          c.academicYear == (data['academicYear'] as String),
      orElse: () => Class.empty(),
    );
    final pdfBytes =
        await ReportCardCustomExportService.generateReportCardCustomPdf(
          student: student,
          schoolInfo: info,
          grades: (data['grades'] as List).cast<Grade>(),
          subjects: subjectNames,
          professeurs: professeurs,
          appreciations: appreciations,
          moyennesClasse: moyennesClasse,
          moyennesParPeriode: (data['moyennesParPeriode'] as List)
              .cast<double?>(),
          allTerms: (data['allTerms'] as List).cast<String>(),
          moyenneGenerale: data['moyenneGenerale'] as double,
          rang: data['rang'] as int,
          nbEleves: data['nbEleves'] as int,
          periodLabel: data['periodLabel'] as String,
          appreciationGenerale: appreciationGenerale,
          mention: data['mention'] as String,
          decision: decision,
          decisionAutomatique: data['decisionAutomatique'] as String? ?? '',
          conduite: conduite,
          recommandations: recommandationsCtrl.text,
          forces: forcesCtrl.text,
          pointsADevelopper: pointsDevelopperCtrl.text,
          sanctions: sanctions,
          attendanceJustifiee: int.tryParse(absJustifieesCtrl.text) ?? 0,
          attendanceInjustifiee: int.tryParse(absInjustifieesCtrl.text) ?? 0,
          retards: int.tryParse(retardsCtrl.text) ?? 0,
          presencePercent: double.tryParse(presencePercentCtrl.text) ?? 0.0,
          moyenneGeneraleDeLaClasse:
              data['moyenneGeneraleDeLaClasse'] as double?,
          moyenneLaPlusForte: data['moyenneLaPlusForte'] as double?,
          moyenneLaPlusFaible: data['moyenneLaPlusFaible'] as double?,
          moyenneAnnuelle: data['moyenneAnnuelle'] as double?,
          moyenneAnnuelleClasse: data['moyenneAnnuelleClasse'] as double?,
          rangAnnuel: data['rangAnnuel'] as int?,
          nbElevesAnnuel: data['nbElevesAnnuel'] as int?,
          academicYear: data['academicYear'] as String,
          term: data['selectedTerm'] as String,
          className: classNameForPdf,
          selectedTerm: data['selectedTerm'] as String,
          faitA: faitA,
          leDate: leDate,
          titulaireName: currentClass.titulaire ?? '',
          directorName: _resolveDirectorForLevel(
            info,
            data['niveau'] as String,
          ),
          titulaireCivility: 'M.',
          directorCivility: _resolveCivilityForLevel(
            info,
            data['niveau'] as String,
            adminCivility,
          ),
          footerNote: footerNote,
          isLandscape: isLandscape,
          useLongFormat: useLongFormat,
        );

    return {
      'bytes': pdfBytes,
      'academicYear': data['academicYear'] as String,
      'term': data['selectedTerm'] as String,
    };
  }

  Future<void> _printCustomReportCardPdf({
    required Student student,
    required SchoolInfo info,
    required List<String> subjectNames,
    required Map<String, TextEditingController> profCtrls,
    required Map<String, TextEditingController> appreciationCtrls,
    required Map<String, TextEditingController> moyClasseCtrls,
    required TextEditingController generalAppreciationCtrl,
    required TextEditingController decisionCtrl,
    required TextEditingController conduiteCtrl,
    required TextEditingController faitACtrl,
    required TextEditingController absJustifieesCtrl,
    required TextEditingController absInjustifieesCtrl,
    required TextEditingController retardsCtrl,
    required TextEditingController presencePercentCtrl,
    required TextEditingController recommandationsCtrl,
    required TextEditingController forcesCtrl,
    required TextEditingController pointsDevelopperCtrl,
    required TextEditingController sanctionsCtrl,
  }) async {
    final payload = await _buildCustomReportCardPdfPayload(
      student: student,
      info: info,
      subjectNames: subjectNames,
      profCtrls: profCtrls,
      appreciationCtrls: appreciationCtrls,
      moyClasseCtrls: moyClasseCtrls,
      generalAppreciationCtrl: generalAppreciationCtrl,
      decisionCtrl: decisionCtrl,
      conduiteCtrl: conduiteCtrl,
      faitACtrl: faitACtrl,
      absJustifieesCtrl: absJustifieesCtrl,
      absInjustifieesCtrl: absInjustifieesCtrl,
      retardsCtrl: retardsCtrl,
      presencePercentCtrl: presencePercentCtrl,
      recommandationsCtrl: recommandationsCtrl,
      forcesCtrl: forcesCtrl,
      pointsDevelopperCtrl: pointsDevelopperCtrl,
      sanctionsCtrl: sanctionsCtrl,
    );
    if (payload == null) return;
    final pdfBytes = payload['bytes'] as List<int>;
    await Printing.layoutPdf(
      onLayout: (format) async => Uint8List.fromList(pdfBytes),
    );
  }

  Future<void> _saveCustomReportCardPdf({
    required Student student,
    required SchoolInfo info,
    required List<String> subjectNames,
    required Map<String, TextEditingController> profCtrls,
    required Map<String, TextEditingController> appreciationCtrls,
    required Map<String, TextEditingController> moyClasseCtrls,
    required TextEditingController generalAppreciationCtrl,
    required TextEditingController decisionCtrl,
    required TextEditingController conduiteCtrl,
    required TextEditingController faitACtrl,
    required TextEditingController absJustifieesCtrl,
    required TextEditingController absInjustifieesCtrl,
    required TextEditingController retardsCtrl,
    required TextEditingController presencePercentCtrl,
    required TextEditingController recommandationsCtrl,
    required TextEditingController forcesCtrl,
    required TextEditingController pointsDevelopperCtrl,
    required TextEditingController sanctionsCtrl,
  }) async {
    final payload = await _buildCustomReportCardPdfPayload(
      student: student,
      info: info,
      subjectNames: subjectNames,
      profCtrls: profCtrls,
      appreciationCtrls: appreciationCtrls,
      moyClasseCtrls: moyClasseCtrls,
      generalAppreciationCtrl: generalAppreciationCtrl,
      decisionCtrl: decisionCtrl,
      conduiteCtrl: conduiteCtrl,
      faitACtrl: faitACtrl,
      absJustifieesCtrl: absJustifieesCtrl,
      absInjustifieesCtrl: absInjustifieesCtrl,
      retardsCtrl: retardsCtrl,
      presencePercentCtrl: presencePercentCtrl,
      recommandationsCtrl: recommandationsCtrl,
      forcesCtrl: forcesCtrl,
      pointsDevelopperCtrl: pointsDevelopperCtrl,
      sanctionsCtrl: sanctionsCtrl,
    );
    if (payload == null) return;
    final pdfBytes = payload['bytes'] as List<int>;
    final academicYear = payload['academicYear'] as String;
    final term = payload['term'] as String;

    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir dossier',
    );
    if (directory == null) return;
    final safeName = '${student.firstName}_${student.lastName}'.replaceAll(
      ' ',
      '_',
    );
    final safeTerm = term.replaceAll(' ', '_');
    final safeYear = academicYear.replaceAll('/', '_');
    final filePath =
        '$directory/Bulletin_custom_${safeName}_${safeTerm}_$safeYear.pdf';
    final file = File(filePath);
    await file.writeAsBytes(pdfBytes, flush: true);
    showSnackBar(context, 'Export terminé: $filePath', isError: false);
  }

  String _resolveDirectorForLevel(SchoolInfo schoolInfo, String niveau) {
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

  String _resolveCivilityForLevel(
    SchoolInfo schoolInfo,
    String niveau,
    String defaultCivility,
  ) {
    final n = niveau.trim().toLowerCase();
    String? candidate;
    if (n.contains('primaire') || n.contains('maternelle')) {
      candidate = schoolInfo.civilityPrimary;
    } else if (n.contains('coll')) {
      candidate = schoolInfo.civilityCollege;
    } else if (n.contains('lyc')) {
      candidate = schoolInfo.civilityLycee;
    } else if (n.contains('univ')) {
      candidate = schoolInfo.civilityUniversity;
    }
    final resolved = candidate?.trim();
    return (resolved != null && resolved.isNotEmpty)
        ? resolved
        : defaultCivility;
  }

  Future<void> _exportClassReportCards() async {
    // Vérifier le mode coffre fort
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    if (selectedClass == null || selectedClass!.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Veuillez sélectionner une classe.')),
      );
      return;
    }

    // Restreindre à l'année académique effective (sélectionnée ou année courante)
    final String effectiveYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : academicYearNotifier.value;
    debugPrint(
      '[GradesPage] Export ZIP -> class=$selectedClass term=$selectedTerm year=$effectiveYear',
    );
    final studentsInClass = await _dbService.getStudents(
      className: selectedClass!,
      academicYear: effectiveYear,
    );
    // Charger les matières pour garantir que subjectNames n'est pas vide
    final subjectsForClass = await _dbService.getCoursesForClass(
      selectedClass!,
      effectiveYear,
    );
    debugPrint(
      '[GradesPage] Export ZIP -> students.count=${studentsInClass.length} subjects.count=${subjectsForClass.length}',
    );
    if (studentsInClass.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Aucun élève dans cette classe.')),
      );
      return;
    }

    // Choix de l'orientation (harmonise avec export unitaire)
    final orientation =
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Orientation du PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Portrait'),
                  leading: const Icon(Icons.stay_current_portrait),
                  onTap: () => Navigator.of(context).pop('portrait'),
                ),
                ListTile(
                  title: const Text('Paysage'),
                  leading: const Icon(Icons.stay_current_landscape),
                  onTap: () => Navigator.of(context).pop('landscape'),
                ),
              ],
            ),
          ),
        ) ??
        'portrait';
    final bool isLandscape = orientation == 'landscape';

    showRootSnackBar(
      SnackBar(content: Text('Génération des bulletins en cours...')),
    );

    final archive = Archive();

    // Validation minimale: les coefficients de matières doivent totaliser > 0
    if (studentsInClass.isNotEmpty) {
      final coeffs = await _dbService.getClassSubjectCoefficients(
        selectedClass!,
        effectiveYear,
      );
      double sumWeights = 0.0;
      coeffs.forEach((_, v) {
        sumWeights += v;
      });
      if (sumWeights <= 0) {
        showRootSnackBar(
          SnackBar(
            content: Text(
              'Coefficients de matières invalides (somme ≤ 0). Veuillez les définir pour la classe.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final classSubjectAverages = await _computeClassSubjectAverages(
      className: selectedClass!,
      academicYear: effectiveYear,
      term: selectedTerm!,
      classSubjects: subjectsForClass,
    );

    for (final student in studentsInClass) {
      final data = await _prepareReportCardData(student);
      // S'assurer que les matières utilisées sont celles chargées localement
      final subjectNames = subjectsForClass.map((s) => s.name).toList();
      final subjectNameByKey = {
        for (final s in subjectNames) _normalizeSubjectKey(s): s,
      };
      final archiveCard = await _dbService.getReportCardArchive(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final List<Map<String, dynamic>> liveApps = await _dbService
          .getSubjectAppreciations(
            studentId: student.id,
            className: selectedClass!,
            academicYear: effectiveYear,
            term: selectedTerm!,
          );
      final List<Map<String, dynamic>> archivedApps = archiveCard != null
          ? await _dbService.getSubjectAppreciationsArchiveByKeys(
              studentId: student.id,
              className: selectedClass!,
              academicYear: effectiveYear,
              term: selectedTerm!,
            )
          : [];
      final Map<String, Map<String, dynamic>> mergedApps = {};
      for (final row in archivedApps) {
        final subject = _resolveSubjectName(
          row['subject'] as String?,
          subjectNameByKey,
        );
        if (subject == null) continue;
        mergedApps[subject] = Map<String, dynamic>.from(row);
      }
      for (final row in liveApps) {
        final subject = _resolveSubjectName(
          row['subject'] as String?,
          subjectNameByKey,
        );
        if (subject == null) continue;
        final existing = mergedApps[subject];
        if (existing == null) {
          mergedApps[subject] = Map<String, dynamic>.from(row);
          continue;
        }
        final liveProf = row['professeur'] as String?;
        if (!_isBlankValue(liveProf)) {
          existing['professeur'] = liveProf;
        }
        final liveApp = row['appreciation'] as String?;
        if (!_isBlankValue(liveApp)) {
          existing['appreciation'] = liveApp;
        }
        final liveMc = row['moyenne_classe'] as String?;
        if (!_isBlankValue(liveMc)) {
          existing['moyenne_classe'] = liveMc;
        }
        final num? liveCoeff = row['coefficient'] as num?;
        if (liveCoeff != null) {
          existing['coefficient'] = liveCoeff;
        }
      }
      final professeurs = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final appreciations = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final moyennesClasse = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final coefficients = <String, double>{};
      for (final entry in mergedApps.entries) {
        final subject = entry.key;
        final row = entry.value;

        professeurs[subject] =
            (row['professeur'] as String?)?.trim().isNotEmpty == true
            ? row['professeur'] as String
            : '-';
        appreciations[subject] =
            (row['appreciation'] as String?)?.trim().isNotEmpty == true
            ? row['appreciation'] as String
            : '-';
        moyennesClasse[subject] =
            (row['moyenne_classe'] as String?)?.trim().isNotEmpty == true
            ? row['moyenne_classe'] as String
            : '-';
        final num? c = row['coefficient'] as num?;
        if (c != null) coefficients[subject] = c.toDouble();
      }
      for (final subject in subjectNames) {
        // Fallback pour les moyennes de classe
        final currentMoy = (moyennesClasse[subject] ?? '').trim();
        if (currentMoy.isEmpty || currentMoy == '-') {
          final fallback = classSubjectAverages[subject];
          if (fallback != null && fallback.trim().isNotEmpty) {
            moyennesClasse[subject] = fallback;
          }
        }

        // Fallback pour les appréciations (Basé sur la moyenne déjà calculée de manière robuste)
        final currentAppr = (appreciations[subject] ?? '').trim();
        if (currentAppr.isEmpty || currentAppr == '-') {
          final double? avg =
              (data['subjectAverages'] as Map<String, double?>)[subject];
          if (avg != null) {
            appreciations[subject] = _getAutomaticAppreciation(avg);
          }
        }
      }
      // Synthèse générale depuis report_cards
      final rcLive = await _dbService.getReportCard(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final rc = rcLive ?? archiveCard;
      final appreciationGenerale =
          rc?['appreciation_generale'] as String? ?? '';
      final decision = rc?['decision'] as String? ?? '';
      final recommandations = rc?['recommandations'] as String? ?? '';
      final forces = rc?['forces'] as String? ?? '';
      final pointsADevelopper = rc?['points_a_developper'] as String? ?? '';
      final sanctions = rc?['sanctions'] as String? ?? '';
      final attendanceJustifiee = (rc?['attendance_justifiee'] as int?) ?? 0;
      final attendanceInjustifiee =
          (rc?['attendance_injustifiee'] as int?) ?? 0;
      final retards = (rc?['retards'] as int?) ?? 0;
      final num? presenceNum = rc?['presence_percent'] as num?;
      final presencePercent = presenceNum?.toDouble() ?? 0.0;
      final conduite = rc?['conduite'] as String? ?? '';
      final faitA = rc?['fait_a'] as String? ?? '';
      final leDate = rc?['le_date'] as String? ?? '';
      final String faitAEff = faitA.trim().isNotEmpty
          ? faitA.trim()
          : (data['schoolInfo'].address as String? ?? '');
      final String leDateEff = DateFormat('dd/MM/yyyy').format(DateTime.now());

      // Ensure professor fallback from assignments/titulaire if not saved
      if (archiveCard == null) {
        await _applyAssignmentProfessors(
          className: selectedClass!,
          academicYear: effectiveYear,
          subjectNames: subjectNames,
          professeurs: professeurs,
        );
      }
      for (final subject in subjectNames) {
        if ((professeurs[subject] ?? '-').trim().isEmpty ||
            professeurs[subject] == '-') {
          final currentClass = classes.firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          );
          if ((currentClass.titulaire ?? '').isNotEmpty) {
            professeurs[subject] = currentClass.titulaire!;
          }
        }
      }
      final currentClass = classes.firstWhere(
        (c) => c.name == selectedClass,
        orElse: () => Class.empty(),
      );
      final pdfBytes = await PdfService.generateReportCardPdf(
        student: data['student'],
        schoolInfo: data['schoolInfo'],
        grades: data['grades'],
        professeurs: professeurs,
        appreciations: appreciations,
        moyennesClasse: moyennesClasse,
        appreciationGenerale: appreciationGenerale,
        decision: decision,
        recommandations: recommandations,
        forces: forces,
        pointsADevelopper: pointsADevelopper,
        sanctions: sanctions,
        attendanceJustifiee: attendanceJustifiee,
        attendanceInjustifiee: attendanceInjustifiee,
        retards: retards,
        presencePercent: presencePercent,
        conduite: conduite,
        telEtab: data['schoolInfo'].telephone ?? '',
        mailEtab: data['schoolInfo'].email ?? '',
        webEtab: data['schoolInfo'].website ?? '',
        titulaire: currentClass.titulaire ?? '',
        subjects: data['subjects'],
        moyennesParPeriode: data['moyennesParPeriode'],
        moyenneGenerale: data['moyenneGenerale'],
        rang: data['rang'],
        exaequo: (data['exaequo'] as bool?) ?? false,
        nbEleves: data['nbEleves'],
        mention: data['mention'],
        allTerms: data['allTerms'],
        periodLabel: data['periodLabel'],
        selectedTerm: data['selectedTerm'],
        academicYear: data['academicYear'],
        faitA: faitAEff,
        leDate: leDateEff,
        isLandscape: isLandscape,
        niveau: data['niveau'],
        moyenneGeneraleDeLaClasse: data['moyenneGeneraleDeLaClasse'],
        moyenneLaPlusForte: data['moyenneLaPlusForte'],
        moyenneLaPlusFaible: data['moyenneLaPlusFaible'],
        moyenneAnnuelle: data['moyenneAnnuelle'],
      );
      // Use student ID to ensure unique filenames even if names collide
      final safeName = '${student.firstName}_${student.lastName}'.replaceAll(
        ' ',
        '_',
      );
      final safeId = student.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      final fileName =
          'Bulletin_${safeName}_${safeId}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
      debugPrint(
        '[GradesPage] Export ZIP -> adding $fileName (${pdfBytes.length} bytes)',
      );
      archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));

      // Archive the report card snapshot for this student/period
      try {
        final String effectiveYear =
            (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
            ? selectedAcademicYear!
            : academicYearNotifier.value;
        final gradesForPeriod = (data['grades'] as List<Grade>?) ?? [];
        await _dbService.archiveSingleReportCard(
          studentId: student.id,
          className: selectedClass!,
          academicYear: effectiveYear,
          term: selectedTerm!,
          grades: gradesForPeriod,
          professeurs: professeurs,
          appreciations: appreciations,
          moyennesClasse: moyennesClasse,
          synthese: {
            'appreciation_generale': appreciationGenerale,
            'decision': decision,
            'recommandations': recommandations,
            'forces': forces,
            'points_a_developper': pointsADevelopper,
            'fait_a': faitA,
            'le_date': leDate,
            'moyenne_generale': data['moyenneGenerale'],
            'rang': data['rang'],
            'nb_eleves': data['nbEleves'],
            'mention': data['mention'],
            'moyennes_par_periode': data['moyennesParPeriode'].toString(),
            'all_terms': data['allTerms'].toString(),
            'moyenne_generale_classe': data['moyenneGeneraleDeLaClasse'],
            'moyenne_la_plus_forte': data['moyenneLaPlusForte'],
            'moyenne_la_plus_faible': data['moyenneLaPlusFaible'],
            'moyenne_annuelle': data['moyenneAnnuelle'],
            'sanctions': sanctions,
            'attendance_justifiee': attendanceJustifiee,
            'attendance_injustifiee': attendanceInjustifiee,
            'retards': retards,
            'presence_percent': presencePercent,
            'conduite': conduite,
            'coefficients': coefficients,
          },
        );
      } catch (e) {
        debugPrint(
          '[GradesPage] Export ZIP -> archiveSingleReportCard failed for ${student.id}: $e',
        );
      }
    }

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    if (zipBytes == null) {
      showRootSnackBar(
        SnackBar(content: Text('Erreur lors de la création du fichier ZIP.')),
      );
      return;
    }

    String? directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directoryPath != null) {
      final fileName =
          'Bulletins_${selectedClass!.replaceAll(' ', '_')}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.zip';
      final file = File('$directoryPath/$fileName');
      await file.writeAsBytes(zipBytes);
      showRootSnackBar(
        SnackBar(
          content: Text('Bulletins exportés dans $directoryPath'),
          backgroundColor: Colors.green,
        ),
      );
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'report_card',
          action: 'export_report_cards',
          username: u?.username,
          details:
              'class=$selectedClass year=$selectedAcademicYear term=$selectedTerm count=${studentsInClass.length} file=$fileName',
        );
      } catch (_) {}
    }
  }

  Future<void> _exportClassReportCardsCompact() async {
    // Vérifier le mode coffre fort
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    if (selectedClass == null || selectedClass!.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Veuillez sélectionner une classe.')),
      );
      return;
    }

    // Restreindre à l'année académique effective (sélectionnée ou année courante)
    final String effectiveYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : academicYearNotifier.value;
    debugPrint(
      '[GradesPage] Export ZIP compact -> class=$selectedClass term=$selectedTerm year=$effectiveYear',
    );
    final studentsInClass = await _dbService.getStudents(
      className: selectedClass!,
      academicYear: effectiveYear,
    );
    debugPrint(
      '[GradesPage] Export ZIP compact -> students.count=${studentsInClass.length}',
    );
    if (studentsInClass.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Aucun élève dans cette classe.')),
      );
      return;
    }

    // Choix de l'orientation (harmonise avec export unitaire)
    final orientation =
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Orientation du PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Portrait'),
                  leading: const Icon(Icons.stay_current_portrait),
                  onTap: () => Navigator.of(context).pop('portrait'),
                ),
                ListTile(
                  title: const Text('Paysage'),
                  leading: const Icon(Icons.stay_current_landscape),
                  onTap: () => Navigator.of(context).pop('landscape'),
                ),
              ],
            ),
          ),
        ) ??
        'portrait';
    final bool isLandscape = orientation == 'landscape';

    showRootSnackBar(
      SnackBar(content: Text('Génération des bulletins compacts...')),
    );

    final archive = Archive();

    // Validation minimale: les coefficients de matières doivent totaliser > 0
    if (studentsInClass.isNotEmpty) {
      final coeffs = await _dbService.getClassSubjectCoefficients(
        selectedClass!,
        effectiveYear,
      );
      double sumWeights = 0.0;
      coeffs.forEach((_, v) {
        sumWeights += v;
      });
      if (sumWeights <= 0) {
        showRootSnackBar(
          SnackBar(
            content: Text(
              'Coefficients de matières invalides (somme ≤ 0). Veuillez les définir pour la classe.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final classSubjectAverages = await _computeClassSubjectAverages(
      className: selectedClass!,
      academicYear: effectiveYear,
      term: selectedTerm!,
      classSubjects: subjects,
    );

    for (final student in studentsInClass) {
      final data = await _prepareReportCardData(student);
      // Récupérer appréciations/professeurs/moyenne_classe enregistrées
      final subjectNames = data['subjects'] as List<String>;
      final subjectNameByKey = {
        for (final s in subjectNames) _normalizeSubjectKey(s): s,
      };
      final archiveCard = await _dbService.getReportCardArchive(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final List<Map<String, dynamic>> liveApps = await _dbService
          .getSubjectAppreciations(
            studentId: student.id,
            className: selectedClass!,
            academicYear: effectiveYear,
            term: selectedTerm!,
          );
      final List<Map<String, dynamic>> archivedApps = archiveCard != null
          ? await _dbService.getSubjectAppreciationsArchiveByKeys(
              studentId: student.id,
              className: selectedClass!,
              academicYear: effectiveYear,
              term: selectedTerm!,
            )
          : [];
      final Map<String, Map<String, dynamic>> mergedApps = {};
      for (final row in archivedApps) {
        final subject = _resolveSubjectName(
          row['subject'] as String?,
          subjectNameByKey,
        );
        if (subject == null) continue;
        mergedApps[subject] = Map<String, dynamic>.from(row);
      }
      for (final row in liveApps) {
        final subject = _resolveSubjectName(
          row['subject'] as String?,
          subjectNameByKey,
        );
        if (subject == null) continue;
        final existing = mergedApps[subject];
        if (existing == null) {
          mergedApps[subject] = Map<String, dynamic>.from(row);
          continue;
        }
        final liveProf = row['professeur'] as String?;
        if (!_isBlankValue(liveProf)) {
          existing['professeur'] = liveProf;
        }
        final liveApp = row['appreciation'] as String?;
        if (!_isBlankValue(liveApp)) {
          existing['appreciation'] = liveApp;
        }
        final liveMc = row['moyenne_classe'] as String?;
        if (!_isBlankValue(liveMc)) {
          existing['moyenne_classe'] = liveMc;
        }
        final num? liveCoeff = row['coefficient'] as num?;
        if (liveCoeff != null) {
          existing['coefficient'] = liveCoeff;
        }
      }
      final professeurs = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final appreciations = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final moyennesClasse = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final coefficients = <String, double>{};
      for (final entry in mergedApps.entries) {
        final subject = entry.key;
        final row = entry.value;
        if (subject != null) {
          professeurs[subject] =
              (row['professeur'] as String?)?.trim().isNotEmpty == true
              ? row['professeur'] as String
              : '-';
          appreciations[subject] =
              (row['appreciation'] as String?)?.trim().isNotEmpty == true
              ? row['appreciation'] as String
              : '-';
          moyennesClasse[subject] =
              (row['moyenne_classe'] as String?)?.trim().isNotEmpty == true
              ? row['moyenne_classe'] as String
              : '-';
          final num? c = row['coefficient'] as num?;
          if (c != null) coefficients[subject] = c.toDouble();
        }
      }
      for (final subject in subjectNames) {
        final current = (moyennesClasse[subject] ?? '').trim();
        if (current.isEmpty || current == '-') {
          final fallback = classSubjectAverages[subject];
          if (fallback != null && fallback.trim().isNotEmpty) {
            moyennesClasse[subject] = fallback;
          }
        }
      }
      // Synthèse générale depuis report_cards
      final rcLive = await _dbService.getReportCard(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final rc = rcLive ?? archiveCard;
      final appreciationGenerale =
          rc?['appreciation_generale'] as String? ?? '';
      final decision = rc?['decision'] as String? ?? '';
      final recommandations = rc?['recommandations'] as String? ?? '';
      final forces = rc?['forces'] as String? ?? '';
      final pointsADevelopper = rc?['points_a_developper'] as String? ?? '';
      final sanctions = rc?['sanctions'] as String? ?? '';
      final attendanceJustifiee = (rc?['attendance_justifiee'] as int?) ?? 0;
      final attendanceInjustifiee =
          (rc?['attendance_injustifiee'] as int?) ?? 0;
      final retards = (rc?['retards'] as int?) ?? 0;
      final num? presenceNum = rc?['presence_percent'] as num?;
      final presencePercent = presenceNum?.toDouble() ?? 0.0;
      final conduite = rc?['conduite'] as String? ?? '';
      final faitA = rc?['fait_a'] as String? ?? '';
      final leDate = rc?['le_date'] as String? ?? '';
      final String faitAEff = faitA.trim().isNotEmpty
          ? faitA.trim()
          : (data['schoolInfo'].address as String? ?? '');
      final String leDateEff = DateFormat('dd/MM/yyyy').format(DateTime.now());

      // Ensure professor fallback from assignments/titulaire if not saved
      if (archiveCard == null) {
        await _applyAssignmentProfessors(
          className: selectedClass!,
          academicYear: effectiveYear,
          subjectNames: subjectNames,
          professeurs: professeurs,
        );
      }
      for (final subject in subjectNames) {
        if ((professeurs[subject] ?? '-').trim().isEmpty ||
            professeurs[subject] == '-') {
          final currentClass = classes.firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          );
          if ((currentClass.titulaire ?? '').isNotEmpty) {
            professeurs[subject] = currentClass.titulaire!;
          }
        }
      }
      final currentClass = classes.firstWhere(
        (c) => c.name == selectedClass,
        orElse: () => Class.empty(),
      );
      final pdfBytes = await PdfService.generateReportCardPdfCompact(
        student: data['student'],
        schoolInfo: data['schoolInfo'],
        grades: data['grades'],
        professeurs: professeurs,
        appreciations: appreciations,
        moyennesClasse: moyennesClasse,
        appreciationGenerale: appreciationGenerale,
        decision: decision,
        recommandations: recommandations,
        forces: forces,
        pointsADevelopper: pointsADevelopper,
        sanctions: sanctions,
        attendanceJustifiee: attendanceJustifiee,
        attendanceInjustifiee: attendanceInjustifiee,
        retards: retards,
        presencePercent: presencePercent,
        conduite: conduite,
        telEtab: data['schoolInfo'].telephone ?? '',
        mailEtab: data['schoolInfo'].email ?? '',
        webEtab: data['schoolInfo'].website ?? '',
        titulaire: currentClass.titulaire ?? '',
        subjects: data['subjects'],
        moyennesParPeriode: data['moyennesParPeriode'],
        moyenneGenerale: data['moyenneGenerale'],
        rang: data['rang'],
        exaequo: (data['exaequo'] as bool?) ?? false,
        nbEleves: data['nbEleves'],
        mention: data['mention'],
        allTerms: data['allTerms'],
        periodLabel: data['periodLabel'],
        selectedTerm: data['selectedTerm'],
        academicYear: data['academicYear'],
        faitA: faitAEff,
        leDate: leDateEff,
        isLandscape: isLandscape,
        niveau: data['niveau'],
        moyenneGeneraleDeLaClasse: data['moyenneGeneraleDeLaClasse'],
        moyenneLaPlusForte: data['moyenneLaPlusForte'],
        moyenneLaPlusFaible: data['moyenneLaPlusFaible'],
        moyenneAnnuelle: data['moyenneAnnuelle'],
      );
      // Use student ID to ensure unique filenames even if names collide
      final safeName = '${student.firstName}_${student.lastName}'.replaceAll(
        ' ',
        '_',
      );
      final safeId = student.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      final fileName =
          'Bulletin_compact_${safeName}_${safeId}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
      debugPrint(
        '[GradesPage] Export ZIP compact -> adding $fileName (${pdfBytes.length} bytes)',
      );
      archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));

      // Archive the report card snapshot for this student/period
      try {
        final String effectiveYear =
            (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
            ? selectedAcademicYear!
            : academicYearNotifier.value;
        final gradesForPeriod = (data['grades'] as List<Grade>?) ?? [];
        await _dbService.archiveSingleReportCard(
          studentId: student.id,
          className: selectedClass!,
          academicYear: effectiveYear,
          term: selectedTerm!,
          grades: gradesForPeriod,
          professeurs: professeurs,
          appreciations: appreciations,
          moyennesClasse: moyennesClasse,
          synthese: {
            'appreciation_generale': appreciationGenerale,
            'decision': decision,
            'recommandations': recommandations,
            'forces': forces,
            'points_a_developper': pointsADevelopper,
            'fait_a': faitA,
            'le_date': leDate,
            'moyenne_generale': data['moyenneGenerale'],
            'rang': data['rang'],
            'nb_eleves': data['nbEleves'],
            'mention': data['mention'],
            'moyennes_par_periode': data['moyennesParPeriode'].toString(),
            'all_terms': data['allTerms'].toString(),
            'moyenne_generale_classe': data['moyenneGeneraleDeLaClasse'],
            'moyenne_la_plus_forte': data['moyenneLaPlusForte'],
            'moyenne_la_plus_faible': data['moyenneLaPlusFaible'],
            'moyenne_annuelle': data['moyenneAnnuelle'],
            'sanctions': sanctions,
            'attendance_justifiee': attendanceJustifiee,
            'attendance_injustifiee': attendanceInjustifiee,
            'retards': retards,
            'presence_percent': presencePercent,
            'conduite': conduite,
            'coefficients': coefficients,
          },
        );
      } catch (e) {
        debugPrint(
          '[GradesPage] Export ZIP compact -> archiveSingleReportCard failed for ${student.id}: $e',
        );
      }
    }

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    if (zipBytes == null) {
      showRootSnackBar(
        SnackBar(content: Text('Erreur lors de la création du fichier ZIP.')),
      );
      return;
    }

    String? directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directoryPath != null) {
      final fileName =
          'Bulletins_compact_${selectedClass!.replaceAll(' ', '_')}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.zip';
      final file = File('$directoryPath/$fileName');
      await file.writeAsBytes(zipBytes);
      showRootSnackBar(
        SnackBar(
          content: Text('Bulletins compacts exportés dans $directoryPath'),
          backgroundColor: Colors.green,
        ),
      );
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'report_card',
          action: 'export_report_cards_compact',
          username: u?.username,
          details:
              'class=$selectedClass year=$selectedAcademicYear term=$selectedTerm count=${studentsInClass.length} file=$fileName',
        );
      } catch (_) {}
    }
  }

  Future<void> _exportClassReportCardsUltraCompact() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    if (selectedClass == null || selectedClass!.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Veuillez sélectionner une classe.')),
      );
      return;
    }

    final String effectiveYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : academicYearNotifier.value;
    debugPrint(
      '[GradesPage] Export ZIP ultra compact -> class=$selectedClass term=$selectedTerm year=$effectiveYear',
    );
    final studentsInClass = await _dbService.getStudents(
      className: selectedClass!,
      academicYear: effectiveYear,
    );
    debugPrint(
      '[GradesPage] Export ZIP ultra compact -> students.count=${studentsInClass.length}',
    );
    if (studentsInClass.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Aucun élève dans cette classe.')),
      );
      return;
    }

    final orientation =
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Orientation du PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Portrait'),
                  leading: const Icon(Icons.stay_current_portrait),
                  onTap: () => Navigator.of(context).pop('portrait'),
                ),
                ListTile(
                  title: const Text('Paysage'),
                  leading: const Icon(Icons.stay_current_landscape),
                  onTap: () => Navigator.of(context).pop('landscape'),
                ),
              ],
            ),
          ),
        ) ??
        'portrait';
    final bool isLandscape = orientation == 'landscape';

    showRootSnackBar(
      SnackBar(content: Text('Génération des bulletins ultra compacts...')),
    );

    final archive = Archive();

    if (studentsInClass.isNotEmpty) {
      final coeffs = await _dbService.getClassSubjectCoefficients(
        selectedClass!,
        effectiveYear,
      );
      double sumWeights = 0.0;
      coeffs.forEach((_, v) {
        sumWeights += v;
      });
      if (sumWeights <= 0) {
        showRootSnackBar(
          SnackBar(
            content: Text(
              'Coefficients de matières invalides (somme ≤ 0). Veuillez les définir pour la classe.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final classSubjectAverages = await _computeClassSubjectAverages(
      className: selectedClass!,
      academicYear: effectiveYear,
      term: selectedTerm!,
      classSubjects: subjects,
    );

    for (final student in studentsInClass) {
      final data = await _prepareReportCardData(student);
      final subjectNames = data['subjects'] as List<String>;
      final subjectNameByKey = {
        for (final s in subjectNames) _normalizeSubjectKey(s): s,
      };
      final archiveCard = await _dbService.getReportCardArchive(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final List<Map<String, dynamic>> liveApps = await _dbService
          .getSubjectAppreciations(
            studentId: student.id,
            className: selectedClass!,
            academicYear: effectiveYear,
            term: selectedTerm!,
          );
      final List<Map<String, dynamic>> archivedApps = archiveCard != null
          ? await _dbService.getSubjectAppreciationsArchiveByKeys(
              studentId: student.id,
              className: selectedClass!,
              academicYear: effectiveYear,
              term: selectedTerm!,
            )
          : [];
      final Map<String, Map<String, dynamic>> mergedApps = {};
      for (final row in archivedApps) {
        final subject = _resolveSubjectName(
          row['subject'] as String?,
          subjectNameByKey,
        );
        if (subject == null) continue;
        mergedApps[subject] = Map<String, dynamic>.from(row);
      }
      for (final row in liveApps) {
        final subject = _resolveSubjectName(
          row['subject'] as String?,
          subjectNameByKey,
        );
        if (subject == null) continue;
        final existing = mergedApps[subject];
        if (existing == null) {
          mergedApps[subject] = Map<String, dynamic>.from(row);
          continue;
        }
        final liveProf = row['professeur'] as String?;
        if (!_isBlankValue(liveProf)) {
          existing['professeur'] = liveProf;
        }
        final liveApp = row['appreciation'] as String?;
        if (!_isBlankValue(liveApp)) {
          existing['appreciation'] = liveApp;
        }
        final liveMc = row['moyenne_classe'] as String?;
        if (!_isBlankValue(liveMc)) {
          existing['moyenne_classe'] = liveMc;
        }
        final num? liveCoeff = row['coefficient'] as num?;
        if (liveCoeff != null) {
          existing['coefficient'] = liveCoeff;
        }
      }
      final professeurs = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final appreciations = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final moyennesClasse = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final coefficients = <String, double>{};
      for (final entry in mergedApps.entries) {
        final subject = entry.key;
        final row = entry.value;
        if (subject != null) {
          professeurs[subject] =
              (row['professeur'] as String?)?.trim().isNotEmpty == true
              ? row['professeur'] as String
              : '-';
          appreciations[subject] =
              (row['appreciation'] as String?)?.trim().isNotEmpty == true
              ? row['appreciation'] as String
              : '-';
          moyennesClasse[subject] =
              (row['moyenne_classe'] as String?)?.trim().isNotEmpty == true
              ? row['moyenne_classe'] as String
              : '-';
          final num? c = row['coefficient'] as num?;
          if (c != null) coefficients[subject] = c.toDouble();
        }
      }
      for (final subject in subjectNames) {
        final current = (moyennesClasse[subject] ?? '').trim();
        if (current.isEmpty || current == '-') {
          final fallback = classSubjectAverages[subject];
          if (fallback != null && fallback.trim().isNotEmpty) {
            moyennesClasse[subject] = fallback;
          }
        }
      }
      final rcLive = await _dbService.getReportCard(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final rc = rcLive ?? archiveCard;
      final appreciationGenerale =
          rc?['appreciation_generale'] as String? ?? '';
      final decision = rc?['decision'] as String? ?? '';
      final recommandations = rc?['recommandations'] as String? ?? '';
      final forces = rc?['forces'] as String? ?? '';
      final pointsADevelopper = rc?['points_a_developper'] as String? ?? '';
      final sanctions = rc?['sanctions'] as String? ?? '';
      final attendanceJustifiee = (rc?['attendance_justifiee'] as int?) ?? 0;
      final attendanceInjustifiee =
          (rc?['attendance_injustifiee'] as int?) ?? 0;
      final retards = (rc?['retards'] as int?) ?? 0;
      final num? presenceNum = rc?['presence_percent'] as num?;
      final presencePercent = presenceNum?.toDouble() ?? 0.0;
      final conduite = rc?['conduite'] as String? ?? '';
      final faitA = rc?['fait_a'] as String? ?? '';
      final leDate = rc?['le_date'] as String? ?? '';
      final String faitAEff = faitA.trim().isNotEmpty
          ? faitA.trim()
          : (data['schoolInfo'].address as String? ?? '');
      final String leDateEff = DateFormat('dd/MM/yyyy').format(DateTime.now());

      if (archiveCard == null) {
        await _applyAssignmentProfessors(
          className: selectedClass!,
          academicYear: effectiveYear,
          subjectNames: subjectNames,
          professeurs: professeurs,
        );
      }
      for (final subject in subjectNames) {
        if ((professeurs[subject] ?? '-').trim().isEmpty ||
            professeurs[subject] == '-') {
          final currentClass = classes.firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          );
          if ((currentClass.titulaire ?? '').isNotEmpty) {
            professeurs[subject] = currentClass.titulaire!;
          }
        }
      }
      final currentClass = classes.firstWhere(
        (c) => c.name == selectedClass,
        orElse: () => Class.empty(),
      );
      final pdfBytes = await PdfService.generateReportCardPdfUltraCompact(
        student: data['student'],
        schoolInfo: data['schoolInfo'],
        grades: data['grades'],
        professeurs: professeurs,
        appreciations: appreciations,
        moyennesClasse: moyennesClasse,
        appreciationGenerale: appreciationGenerale,
        decision: decision,
        recommandations: recommandations,
        forces: forces,
        pointsADevelopper: pointsADevelopper,
        sanctions: sanctions,
        attendanceJustifiee: attendanceJustifiee,
        attendanceInjustifiee: attendanceInjustifiee,
        retards: retards,
        presencePercent: presencePercent,
        conduite: conduite,
        telEtab: data['schoolInfo'].telephone ?? '',
        mailEtab: data['schoolInfo'].email ?? '',
        webEtab: data['schoolInfo'].website ?? '',
        titulaire: currentClass.titulaire ?? '',
        subjects: data['subjects'],
        moyennesParPeriode: data['moyennesParPeriode'],
        moyenneGenerale: data['moyenneGenerale'],
        rang: data['rang'],
        exaequo: (data['exaequo'] as bool?) ?? false,
        nbEleves: data['nbEleves'],
        mention: data['mention'],
        allTerms: data['allTerms'],
        periodLabel: data['periodLabel'],
        selectedTerm: data['selectedTerm'],
        academicYear: data['academicYear'],
        faitA: faitAEff,
        leDate: leDateEff,
        isLandscape: isLandscape,
        niveau: data['niveau'],
        moyenneGeneraleDeLaClasse: data['moyenneGeneraleDeLaClasse'],
        moyenneLaPlusForte: data['moyenneLaPlusForte'],
        moyenneLaPlusFaible: data['moyenneLaPlusFaible'],
        moyenneAnnuelle: data['moyenneAnnuelle'],
      );
      final safeName = '${student.firstName}_${student.lastName}'.replaceAll(
        ' ',
        '_',
      );
      final safeId = student.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      final fileName =
          'Bulletin_ultra_compact_${safeName}_${safeId}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
      debugPrint(
        '[GradesPage] Export ZIP ultra compact -> adding $fileName (${pdfBytes.length} bytes)',
      );
      archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));

      try {
        final String effectiveYear =
            (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
            ? selectedAcademicYear!
            : academicYearNotifier.value;
        final gradesForPeriod = (data['grades'] as List<Grade>?) ?? [];
        await _dbService.archiveSingleReportCard(
          studentId: student.id,
          className: selectedClass!,
          academicYear: effectiveYear,
          term: selectedTerm!,
          grades: gradesForPeriod,
          professeurs: professeurs,
          appreciations: appreciations,
          moyennesClasse: moyennesClasse,
          synthese: {
            'appreciation_generale': appreciationGenerale,
            'decision': decision,
            'recommandations': recommandations,
            'forces': forces,
            'points_a_developper': pointsADevelopper,
            'fait_a': faitA,
            'le_date': leDate,
            'moyenne_generale': data['moyenneGenerale'],
            'rang': data['rang'],
            'nb_eleves': data['nbEleves'],
            'mention': data['mention'],
            'moyennes_par_periode': data['moyennesParPeriode'].toString(),
            'all_terms': data['allTerms'].toString(),
            'moyenne_generale_classe': data['moyenneGeneraleDeLaClasse'],
            'moyenne_la_plus_forte': data['moyenneLaPlusForte'],
            'moyenne_la_plus_faible': data['moyenneLaPlusFaible'],
            'moyenne_annuelle': data['moyenneAnnuelle'],
            'sanctions': sanctions,
            'attendance_justifiee': attendanceJustifiee,
            'attendance_injustifiee': attendanceInjustifiee,
            'retards': retards,
            'presence_percent': presencePercent,
            'conduite': conduite,
            'coefficients': coefficients,
          },
        );
      } catch (e) {
        debugPrint(
          '[GradesPage] Export ZIP ultra compact -> archiveSingleReportCard failed for ${student.id}: $e',
        );
      }
    }

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    if (zipBytes == null) {
      showRootSnackBar(
        SnackBar(content: Text('Erreur lors de la création du fichier ZIP.')),
      );
      return;
    }

    String? directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directoryPath != null) {
      final fileName =
          'Bulletins_ultra_compact_${selectedClass!.replaceAll(' ', '_')}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.zip';
      final file = File('$directoryPath/$fileName');
      await file.writeAsBytes(zipBytes);
      showRootSnackBar(
        SnackBar(
          content: Text(
            'Bulletins ultra compacts exportés dans $directoryPath',
          ),
          backgroundColor: Colors.green,
        ),
      );
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'report_card',
          action: 'export_report_cards_ultra_compact',
          username: u?.username,
          details:
              'class=$selectedClass year=$selectedAcademicYear term=$selectedTerm count=${studentsInClass.length} file=$fileName',
        );
      } catch (_) {}
    }
  }

  Future<void> _exportClassReportCardsCustom() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    if (selectedClass == null || selectedClass!.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Veuillez sélectionner une classe.')),
      );
      return;
    }

    final String effectiveYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : academicYearNotifier.value;
    debugPrint(
      '[GradesPage] Export ZIP custom -> class=$selectedClass term=$selectedTerm year=$effectiveYear',
    );
    final studentsInClass = await _dbService.getStudents(
      className: selectedClass!,
      academicYear: effectiveYear,
    );
    debugPrint(
      '[GradesPage] Export ZIP custom -> students.count=${studentsInClass.length}',
    );
    if (studentsInClass.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Aucun élève dans cette classe.')),
      );
      return;
    }

    final orientation =
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Orientation du PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Portrait'),
                  leading: const Icon(Icons.stay_current_portrait),
                  onTap: () => Navigator.of(context).pop('portrait'),
                ),
                ListTile(
                  title: const Text('Paysage'),
                  leading: const Icon(Icons.stay_current_landscape),
                  onTap: () => Navigator.of(context).pop('landscape'),
                ),
              ],
            ),
          ),
        ) ??
        'portrait';
    final bool isLandscape = orientation == 'landscape';

    final formatChoice =
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Format du PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Format long (agrandi)'),
                  subtitle: const Text('Dimensions agrandies'),
                  leading: const Icon(Icons.description),
                  onTap: () => Navigator.of(context).pop('long'),
                ),
                ListTile(
                  title: const Text('Format court (A4 standard)'),
                  subtitle: const Text('Dimensions standard A4'),
                  leading: const Icon(Icons.view_compact),
                  onTap: () => Navigator.of(context).pop('short'),
                ),
              ],
            ),
          ),
        ) ??
        'long';
    final bool useLongFormat = formatChoice == 'long';

    showRootSnackBar(
      SnackBar(content: Text('Génération des bulletins custom en cours...')),
    );

    final archive = Archive();
    final prefs = await SharedPreferences.getInstance();
    final footerNote = prefs.getString('report_card_footer_note') ?? '';
    final adminCivility = prefs.getString('school_admin_civility') ?? 'M.';

    if (studentsInClass.isNotEmpty) {
      final coeffs = await _dbService.getClassSubjectCoefficients(
        selectedClass!,
        effectiveYear,
      );
      double sumWeights = 0.0;
      coeffs.forEach((_, v) {
        sumWeights += v;
      });
      if (sumWeights <= 0) {
        showRootSnackBar(
          SnackBar(
            content: Text(
              'Coefficients de matières invalides (somme ≤ 0). Veuillez les définir pour la classe.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final classSubjectAverages = await _computeClassSubjectAverages(
      className: selectedClass!,
      academicYear: effectiveYear,
      term: selectedTerm!,
      classSubjects: subjects,
    );

    for (final student in studentsInClass) {
      final data = await _prepareReportCardData(student);
      final subjectNames = data['subjects'] as List<String>;
      final subjectNameByKey = {
        for (final s in subjectNames) _normalizeSubjectKey(s): s,
      };
      final archiveCard = await _dbService.getReportCardArchive(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final List<Map<String, dynamic>> liveApps = await _dbService
          .getSubjectAppreciations(
            studentId: student.id,
            className: selectedClass!,
            academicYear: effectiveYear,
            term: selectedTerm!,
          );
      final List<Map<String, dynamic>> archivedApps = archiveCard != null
          ? await _dbService.getSubjectAppreciationsArchiveByKeys(
              studentId: student.id,
              className: selectedClass!,
              academicYear: effectiveYear,
              term: selectedTerm!,
            )
          : [];
      final Map<String, Map<String, dynamic>> mergedApps = {};
      for (final row in archivedApps) {
        final subject = _resolveSubjectName(
          row['subject'] as String?,
          subjectNameByKey,
        );
        if (subject == null) continue;
        mergedApps[subject] = Map<String, dynamic>.from(row);
      }
      for (final row in liveApps) {
        final subject = _resolveSubjectName(
          row['subject'] as String?,
          subjectNameByKey,
        );
        if (subject == null) continue;
        final existing = mergedApps[subject];
        if (existing == null) {
          mergedApps[subject] = Map<String, dynamic>.from(row);
          continue;
        }
        final liveProf = row['professeur'] as String?;
        if (!_isBlankValue(liveProf)) {
          existing['professeur'] = liveProf;
        }
        final liveApp = row['appreciation'] as String?;
        if (!_isBlankValue(liveApp)) {
          existing['appreciation'] = liveApp;
        }
        final liveMc = row['moyenne_classe'] as String?;
        if (!_isBlankValue(liveMc)) {
          existing['moyenne_classe'] = liveMc;
        }
        final num? liveCoeff = row['coefficient'] as num?;
        if (liveCoeff != null) {
          existing['coefficient'] = liveCoeff;
        }
      }
      final professeurs = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final appreciations = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final moyennesClasse = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      for (final entry in mergedApps.entries) {
        final subject = entry.key;
        final row = entry.value;
        professeurs[subject] =
            (row['professeur'] as String?)?.trim().isNotEmpty == true
            ? row['professeur'] as String
            : '-';
        appreciations[subject] =
            (row['appreciation'] as String?)?.trim().isNotEmpty == true
            ? row['appreciation'] as String
            : '-';
        moyennesClasse[subject] =
            (row['moyenne_classe'] as String?)?.trim().isNotEmpty == true
            ? row['moyenne_classe'] as String
            : '-';
      }
      for (final subject in subjectNames) {
        final current = (moyennesClasse[subject] ?? '').trim();
        if (current.isEmpty || current == '-') {
          final fallback = classSubjectAverages[subject];
          if (fallback != null && fallback.trim().isNotEmpty) {
            moyennesClasse[subject] = fallback;
          }
        }
      }

      final rcLive = await _dbService.getReportCard(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final rc = rcLive ?? archiveCard;
      final appreciationGenerale =
          rc?['appreciation_generale'] as String? ?? '';
      final decision = rc?['decision'] as String? ?? '';
      final recommandations = rc?['recommandations'] as String? ?? '';
      final forces = rc?['forces'] as String? ?? '';
      final pointsADevelopper = rc?['points_a_developper'] as String? ?? '';
      final conduite = rc?['conduite'] as String? ?? '';
      final attendanceJustifiee = (rc?['attendance_justifiee'] as int?) ?? 0;
      final attendanceInjustifiee =
          (rc?['attendance_injustifiee'] as int?) ?? 0;
      final retards = (rc?['retards'] as int?) ?? 0;
      final num? presenceNum = rc?['presence_percent'] as num?;
      final presencePercent = presenceNum?.toDouble() ?? 0.0;
      final faitA = rc?['fait_a'] as String? ?? '';
      final leDate = rc?['le_date'] as String? ?? '';
      final String faitAEff = faitA.trim().isNotEmpty
          ? faitA.trim()
          : (data['schoolInfo'].address as String? ?? '');
      final String leDateEff = DateFormat('dd/MM/yyyy').format(DateTime.now());

      if (archiveCard == null) {
        await _applyAssignmentProfessors(
          className: selectedClass!,
          academicYear: effectiveYear,
          subjectNames: subjectNames,
          professeurs: professeurs,
        );
      }
      for (final subject in subjectNames) {
        if ((professeurs[subject] ?? '-').trim().isEmpty ||
            professeurs[subject] == '-') {
          final currentClass = classes.firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          );
          if ((currentClass.titulaire ?? '').isNotEmpty) {
            professeurs[subject] = currentClass.titulaire!;
          }
        }
      }

      final classNameForPdf = selectedClass ?? student.className;
      final currentClass = classes.firstWhere(
        (c) => c.name == classNameForPdf && c.academicYear == effectiveYear,
        orElse: () => Class.empty(),
      );
      final pdfBytes =
          await ReportCardCustomExportService.generateReportCardCustomPdf(
            student: data['student'] as Student,
            schoolInfo: data['schoolInfo'] as SchoolInfo,
            grades: (data['grades'] as List).cast<Grade>(),
            subjects: (data['subjects'] as List).cast<String>(),
            professeurs: professeurs,
            appreciations: appreciations,
            moyennesClasse: moyennesClasse,
            moyennesParPeriode: (data['moyennesParPeriode'] as List)
                .cast<double?>(),
            allTerms: (data['allTerms'] as List).cast<String>(),
            moyenneGenerale: data['moyenneGenerale'] as double,
            rang: data['rang'] as int,
            nbEleves: data['nbEleves'] as int,
            periodLabel: data['periodLabel'] as String,
            appreciationGenerale: appreciationGenerale,
            mention: data['mention'] as String,
            decision: decision,
            decisionAutomatique: data['decisionAutomatique'] as String? ?? '',
            conduite: conduite,
            recommandations: recommandations,
            forces: forces,
            pointsADevelopper: pointsADevelopper,
            sanctions: rc?['sanctions'] as String? ?? '',
            attendanceJustifiee: attendanceJustifiee,
            attendanceInjustifiee: attendanceInjustifiee,
            retards: retards,
            presencePercent: presencePercent,
            moyenneGeneraleDeLaClasse:
                data['moyenneGeneraleDeLaClasse'] as double?,
            moyenneLaPlusForte: data['moyenneLaPlusForte'] as double?,
            moyenneLaPlusFaible: data['moyenneLaPlusFaible'] as double?,
            moyenneAnnuelle: data['moyenneAnnuelle'] as double?,
            moyenneAnnuelleClasse: data['moyenneAnnuelleClasse'] as double?,
            rangAnnuel: data['rangAnnuel'] as int?,
            nbElevesAnnuel: data['nbElevesAnnuel'] as int?,
            academicYear: data['academicYear'] as String,
            term: data['selectedTerm'] as String,
            className: classNameForPdf,
            selectedTerm: data['selectedTerm'] as String,
            faitA: faitAEff,
            leDate: leDateEff,
            titulaireName: currentClass.titulaire ?? '',
            directorName: _resolveDirectorForLevel(
              data['schoolInfo'] as SchoolInfo,
              data['niveau'] as String,
            ),
            titulaireCivility: 'M.',
            directorCivility: _resolveCivilityForLevel(
              data['schoolInfo'] as SchoolInfo,
              data['niveau'] as String,
              adminCivility,
            ),
            footerNote: footerNote,
            isLandscape: isLandscape,
            useLongFormat: useLongFormat,
          );

      final safeName = '${student.firstName}_${student.lastName}'.replaceAll(
        ' ',
        '_',
      );
      final safeId = student.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      final fileName =
          'Bulletin_custom_${safeName}_${safeId}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
      debugPrint(
        '[GradesPage] Export ZIP custom -> adding $fileName (${pdfBytes.length} bytes)',
      );
      archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));
    }

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    if (zipBytes == null) {
      showRootSnackBar(
        SnackBar(content: Text('Erreur lors de la création du fichier ZIP.')),
      );
      return;
    }

    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir dossier',
    );
    if (directory == null) return;
    final safeClass = (selectedClass ?? 'classe').replaceAll(' ', '_');
    final String safeTerm = (selectedTerm ?? '').replaceAll(' ', '_');
    final String safeYear = effectiveYear.replaceAll('/', '_');
    final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final filePath =
        '$directory/bulletins_custom_${safeClass}_${safeTerm}_${safeYear}_$stamp.zip';
    final file = File(filePath);
    await file.writeAsBytes(zipBytes, flush: true);
    showRootSnackBar(SnackBar(content: Text('Export terminé: $filePath')));
  }

  void _showEditStudentGradesDialog(Student student) async {
    // Vérifier le mode coffre fort
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    final List<String> subjectNames = subjects.map((c) => c.name).toList();
    // Charger les coefficients de matières définis dans les détails de la classe pour l'année en cours
    String effYear;
    if (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty) {
      effYear = selectedAcademicYear!;
    } else {
      effYear = classes
          .firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          )
          .academicYear;
      if (effYear.isEmpty) effYear = academicYearNotifier.value;
    }
    final Map<String, double> classSubjectWeights = await _dbService
        .getClassSubjectCoefficients(selectedClass!, effYear);
    // Récupère toutes les notes de l'élève pour la période sélectionnée directement depuis la base
    List<Grade> allGradesForPeriod = await _dbService.getAllGradesForPeriod(
      className: selectedClass!,
      academicYear: effYear,
      term: selectedTerm!,
    );
    final templatesAll = await _dbService.getEvaluationTemplates(
      className: selectedClass!,
      academicYear: effYear,
    );
    final Map<String, Map<String, List<EvaluationTemplate>>> tplBySubjectType =
        {};
    for (final t in templatesAll) {
      tplBySubjectType.putIfAbsent(t.subject, () => {});
      tplBySubjectType[t.subject]!.putIfAbsent(t.type, () => []);
      tplBySubjectType[t.subject]![t.type]!.add(t);
    }
    for (final m in tplBySubjectType.values) {
      for (final list in m.values) {
        list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      }
    }
    // Nouvelle structure : pour chaque matière, pour chaque type, liste de notes
    final types = ['Devoir', 'Composition'];
    Map<String, Map<String, List<Grade>>> subjectTypeGrades = {};
    for (final subject in subjectNames) {
      subjectTypeGrades[subject] = {};
      for (final type in types) {
        final existing = allGradesForPeriod
            .where(
              (g) =>
                  g.studentId == student.id &&
                  g.subject == subject &&
                  g.type == type,
            )
            .toList();
        final course = subjects.firstWhere(
          (c) => c.name == subject,
          orElse: () => Course.empty(),
        );
        final templates =
            (tplBySubjectType[subject] ?? const {})[type] ?? const [];
        final labelSet = existing
            .map((g) => _normalizeGradeLabel(type: type, label: g.label))
            .toSet();
        for (final tpl in templates) {
          if (labelSet.contains(tpl.label.trim())) continue;
          existing.add(
            Grade(
              id: null,
              studentId: student.id,
              className: selectedClass!,
              academicYear: effYear,
              subjectId: course.id,
              subject: subject,
              term: selectedTerm!,
              value: 0,
              label: tpl.label,
              maxValue: tpl.maxValue,
              coefficient: tpl.coefficient,
              type: type,
            ),
          );
        }
        if (existing.isEmpty) {
          existing.add(
            Grade(
              id: null,
              studentId: student.id,
              className: selectedClass!,
              academicYear: effYear,
              subjectId: course.id,
              subject: subject,
              term: selectedTerm!,
              value: 0,
              label: type,
              maxValue: 20,
              coefficient: 1,
              type: type,
            ),
          );
        }
        subjectTypeGrades[subject]![type] = existing;
      }
    }
    // Contrôleurs pour chaque note (clé : subject-type-index)
    final Map<String, TextEditingController> valueControllers = {};
    final Map<String, TextEditingController> labelControllers = {};
    final Map<String, TextEditingController> maxValueControllers = {};
    // Coefficients d'évaluation non éditables dans ce formulaire
    subjectTypeGrades.forEach((subject, typeMap) {
      typeMap.forEach((type, gradesList) {
        for (int i = 0; i < gradesList.length; i++) {
          final key = '$subject-$type-$i';
          valueControllers[key] = TextEditingController(
            text: gradesList[i].value.toString(),
          );
          labelControllers[key] = TextEditingController(
            text: gradesList[i].label ?? subject,
          );
          maxValueControllers[key] = TextEditingController(
            text: gradesList[i].maxValue.toString(),
          );
        }
      });
    });

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.edit, color: AppColors.primaryBlue),
                    const SizedBox(width: 10),
                    Text(
                      'Notes de ${_displayStudentName(student)}',
                      style: Theme.of(context).textTheme.headlineMedium,
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
          content: Container(
            width: MediaQuery.of(context).size.width * 0.6,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: subjectNames.map((subject) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ExpansionTile(
                      leading: const Icon(
                        Icons.subject,
                        color: AppColors.primaryBlue,
                      ),
                      title: Text(
                        subject,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      subtitle: Text(
                        'Coeff. matière (classe): ' +
                            ((classSubjectWeights[subject] != null)
                                ? classSubjectWeights[subject]!.toStringAsFixed(
                                    2,
                                  )
                                : '-'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      children: types.map((type) {
                        final gradesList = subjectTypeGrades[subject]![type]!;
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                type,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Divider(),
                              ...List.generate(gradesList.length, (i) {
                                final key = '$subject-$type-$i';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: labelControllers[key],
                                          enabled:
                                              SafeModeService.instance
                                                  .isActionAllowed() &&
                                              !_isPeriodLocked(),
                                          decoration: const InputDecoration(
                                            labelText: 'Nom de la note',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          controller: valueControllers[key],
                                          enabled:
                                              SafeModeService.instance
                                                  .isActionAllowed() &&
                                              !_isPeriodLocked(),
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
                                            labelText: 'Note',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          controller: maxValueControllers[key],
                                          enabled:
                                              SafeModeService.instance
                                                  .isActionAllowed() &&
                                              !_isPeriodLocked(),
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
                                            labelText: 'Sur',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      // Coefficient supprimé de l'édition ici
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton.icon(
              onPressed:
                  (_isPeriodLocked() ||
                      !SafeModeService.instance.isActionAllowed())
                  ? null
                  : () async {
                      if (!_ensureTeacherCanEditSelection()) return;
                      for (final subject in subjectNames) {
                        for (final type in types) {
                          final gradesList = subjectTypeGrades[subject]![type]!;
                          for (int i = 0; i < gradesList.length; i++) {
                            final key = '$subject-$type-$i';
                            final value = double.tryParse(
                              valueControllers[key]!.text,
                            );
                            final maxValue = double.tryParse(
                              maxValueControllers[key]!.text,
                            );
                            final coefficient = gradesList[i].coefficient;
                            final label = labelControllers[key]!.text;

                            if (value != null) {
                              final course = subjects.firstWhere(
                                (c) => c.name == subject,
                                orElse: () => Course.empty(),
                              );
                              final newGrade = Grade(
                                id: gradesList[i].id,
                                studentId: student.id,
                                className: selectedClass!,
                                academicYear: effYear,
                                subjectId: course.id,
                                subject: subject,
                                term: selectedTerm!,
                                value: value,
                                label: label,
                                maxValue: maxValue ?? 20,
                                coefficient:
                                    (coefficient == 0 || coefficient.isNaN)
                                    ? 1
                                    : coefficient,
                                type: type,
                              );
                              if (newGrade.id == null) {
                                await _dbService.insertGrade(newGrade);
                              } else {
                                await _dbService.updateGrade(newGrade);
                              }
                            }
                          }
                        }
                      }
                      await _loadAllGradesForPeriod();
                      Navigator.of(context).pop();
                      showRootSnackBar(
                        const SnackBar(
                          content: Text('Notes enregistrées avec succès.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _isDarkMode ? _buildDarkTheme() : _buildLightTheme();
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: _isDarkMode ? Colors.black : Colors.grey[100],
        body: Column(
          children: [
            _buildHeader(context, _isDarkMode, isDesktop),
            const SizedBox(height: 16),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGradeInputTab(),
                  _buildReportCardsTab(),
                  _buildArchiveTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
