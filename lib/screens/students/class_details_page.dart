import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:school_manager/models/course.dart';
import 'package:archive/archive.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
// ignore: depend_on_referenced_packages
import 'package:printing/printing.dart';
import 'package:school_manager/constants/strings.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:school_manager/screens/students/widgets/student_registration_form.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/student_id_card_service.dart';
import 'package:docx_template/docx_template.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:open_file/open_file.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/services/report_card_custom_export_service.dart';
import 'package:school_manager/services/class_synthesis_pdf_service.dart';
import 'package:school_manager/screens/students/re_enrollment_dialog.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClassDetailsPage extends StatefulWidget {
  final Class classe;
  final List<Student> students;

  const ClassDetailsPage({
    required this.classe,
    required this.students,
    Key? key,
  }) : super(key: key);

  @override
  State<ClassDetailsPage> createState() => _ClassDetailsPageState();
}

class _ClassDetailsPageState extends State<ClassDetailsPage>
    with TickerProviderStateMixin {
  late TextEditingController _nameController;
  late TextEditingController _yearController;
  late TextEditingController _titulaireController;
  late TextEditingController _fraisEcoleController;
  late TextEditingController _fraisCotisationParalleleController;
  late TextEditingController _searchController;
  // Contrôleurs pour les seuils de passage
  late TextEditingController _seuilFelicitationsController;
  late TextEditingController _seuilEncouragementsController;
  late TextEditingController _seuilAdmissionController;
  late TextEditingController _seuilAvertissementController;
  late TextEditingController _seuilConditionsController;
  late TextEditingController _seuilRedoublementController;
  final List<String> _levels = const [
    'Primaire',
    'Collège',
    'Lycée',
    'Université',
  ];
  late String _selectedLevel;
  late List<Student> _students;
  final DatabaseService _dbService = DatabaseService();
  final _formKey = GlobalKey<FormState>();
  String _studentSearchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = false;
  late FocusNode _nameFocusNode;
  late FocusNode _yearFocusNode;
  late FocusNode _titulaireFocusNode;
  late FocusNode _fraisEcoleFocusNode;
  late FocusNode _fraisCotisationFocusNode;
  late FocusNode _searchFocusNode;
  // Focus nodes pour les seuils de passage
  late FocusNode _seuilFelicitationsFocusNode;
  late FocusNode _seuilEncouragementsFocusNode;
  late FocusNode _seuilAdmissionFocusNode;
  late FocusNode _seuilAvertissementFocusNode;
  late FocusNode _seuilConditionsFocusNode;
  late FocusNode _seuilRedoublementFocusNode;
  String _sortBy = 'name'; // Sort by name or ID
  bool _sortAscending = true;
  String _studentStatusFilter = 'Tous'; // 'Tous', 'Payé', 'En attente'
  String _visibilityFilter = 'active'; // 'active' | 'deleted' | 'all'
  bool _selectionMode = false;
  final Set<String> _selectedStudentIds = <String>{};
  String? _selectedArchivedBulletinTerm;
  List<Course> _classSubjects = const [];
  final Map<String, TextEditingController> _coeffCtrls = {};
  double _sumCoeffs = 0.0;

  void _setSelectionMode(bool enabled) {
    setState(() {
      _selectionMode = enabled;
      if (!enabled) _selectedStudentIds.clear();
    });
  }

  void _toggleSelectedStudent(String studentId) {
    setState(() {
      if (_selectedStudentIds.contains(studentId)) {
        _selectedStudentIds.remove(studentId);
      } else {
        _selectedStudentIds.add(studentId);
      }
    });
  }

  Future<void> _selectAllFilteredStudents() async {
    final filtered = await _getFilteredAndSortedStudentsAsync();
    if (!mounted) return;
    setState(() {
      _selectedStudentIds
        ..clear()
        ..addAll(filtered.map((s) => s.id));
    });
  }

  List<Student> _sortedStudentsForExport() {
    final sorted = List<Student>.from(_students);
    sorted.sort((a, b) {
      final compare = _displayStudentName(
        a,
      ).toLowerCase().compareTo(_displayStudentName(b).toLowerCase());
      if (compare != 0) return compare;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  String _displayStudentName(Student student) {
    final lastName = student.lastName.trim().toUpperCase();
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.classe.name);
    _yearController = TextEditingController(text: widget.classe.academicYear);
    _titulaireController = TextEditingController(text: widget.classe.titulaire);
    _fraisEcoleController = TextEditingController(
      text: widget.classe.fraisEcole?.toString() ?? '',
    );
    _fraisCotisationParalleleController = TextEditingController(
      text: widget.classe.fraisCotisationParallele?.toString() ?? '',
    );
    _selectedLevel = (widget.classe.level?.trim().isNotEmpty ?? false)
        ? widget.classe.level!.trim()
        : 'Primaire';
    _searchController = TextEditingController();
    // Initialisation des contrôleurs pour les seuils de passage
    _seuilFelicitationsController = TextEditingController(
      text: widget.classe.seuilFelicitations.toString(),
    );
    _seuilEncouragementsController = TextEditingController(
      text: widget.classe.seuilEncouragements.toString(),
    );
    _seuilAdmissionController = TextEditingController(
      text: widget.classe.seuilAdmission.toString(),
    );
    _seuilAvertissementController = TextEditingController(
      text: widget.classe.seuilAvertissement.toString(),
    );
    _seuilConditionsController = TextEditingController(
      text: widget.classe.seuilConditions.toString(),
    );
    _seuilRedoublementController = TextEditingController(
      text: widget.classe.seuilRedoublement.toString(),
    );
    _students = List<Student>.from(widget.students);

    _nameFocusNode = FocusNode();
    _yearFocusNode = FocusNode();
    _titulaireFocusNode = FocusNode();
    _fraisEcoleFocusNode = FocusNode();
    _fraisCotisationFocusNode = FocusNode();
    _searchFocusNode = FocusNode();
    // Initialisation des focus nodes pour les seuils de passage
    _seuilFelicitationsFocusNode = FocusNode();
    _seuilEncouragementsFocusNode = FocusNode();
    _seuilAdmissionFocusNode = FocusNode();
    _seuilAvertissementFocusNode = FocusNode();
    _seuilConditionsFocusNode = FocusNode();
    _seuilRedoublementFocusNode = FocusNode();

    _animationController = AnimationController(
      duration: const Duration(
        milliseconds: 600,
      ), // Slightly faster for performance
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();

    _fraisEcoleController.addListener(_updateTotalClasse);
    _fraisCotisationParalleleController.addListener(_updateTotalClasse);

    _loadClassSubjectsAndCoeffs();

    getCurrentAcademicYear().then((year) {
      if (widget.classe.academicYear.isEmpty) {
        _yearController.text = year;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadStudentsForCurrentClass();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    _titulaireController.dispose();
    _fraisEcoleController.dispose();
    _fraisCotisationParalleleController.dispose();
    _searchController.dispose();
    // Disposal des contrôleurs pour les seuils de passage
    _seuilFelicitationsController.dispose();
    _seuilEncouragementsController.dispose();
    _seuilAdmissionController.dispose();
    _seuilAvertissementController.dispose();
    _seuilConditionsController.dispose();
    _seuilRedoublementController.dispose();
    _animationController.dispose();
    _nameFocusNode.dispose();
    _yearFocusNode.dispose();
    _titulaireFocusNode.dispose();
    _fraisEcoleFocusNode.dispose();
    _fraisCotisationFocusNode.dispose();
    _searchFocusNode.dispose();
    // Disposal des focus nodes pour les seuils de passage
    _seuilFelicitationsFocusNode.dispose();
    _seuilEncouragementsFocusNode.dispose();
    _seuilAdmissionFocusNode.dispose();
    _seuilAvertissementFocusNode.dispose();
    _seuilConditionsFocusNode.dispose();
    _seuilRedoublementFocusNode.dispose();
    _fraisEcoleController.removeListener(_updateTotalClasse);
    _fraisCotisationParalleleController.removeListener(_updateTotalClasse);
    super.dispose();
    for (final c in _coeffCtrls.values) c.dispose();
  }

  void _updateTotalClasse() {
    setState(() {}); // Force le rebuild pour mettre à jour le total
  }

  Future<void> _loadClassSubjectsAndCoeffs() async {
    final subs = await _dbService.getCoursesForClass(
      _nameController.text,
      _yearController.text,
    );
    final coeffs = await _dbService.getClassSubjectCoefficients(
      _nameController.text,
      _yearController.text,
    );
    setState(() {
      _classSubjects = subs;
      _coeffCtrls.clear();
      _sumCoeffs = 0.0;
      for (final s in subs) {
        final v = coeffs[s.name]?.toString() ?? '';
        final ctrl = TextEditingController(text: v);
        ctrl.addListener(() {
          _recomputeSum();
        });
        _coeffCtrls[s.id] = ctrl;
        final n = double.tryParse((v).replaceAll(',', '.'));
        if (n != null) _sumCoeffs += n;
      }
    });
  }

  void _recomputeSum() {
    double sum = 0.0;
    for (final ctrl in _coeffCtrls.values) {
      final n = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (n != null) sum += n;
    }
    setState(() {
      _sumCoeffs = sum;
    });
  }

  Future<void> _saveCoefficients() async {
    for (final course in _classSubjects) {
      final ctrl = _coeffCtrls[course.id];
      if (ctrl == null) continue;
      final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (val == null) continue;
      await _dbService.updateClassCourseCoefficient(
        className: _nameController.text,
        academicYear: _yearController.text,
        courseId: course.id,
        coefficient: val,
      );
    }
    _showModernSnackBar(
      'Coefficients mis à jour pour ${_nameController.text}.',
    );
  }

  Future<void> _saveClass() async {
    if (!_formKey.currentState!.validate()) {
      _showModernSnackBar(
        'Veuillez remplir tous les champs obligatoires',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedClass = Class(
        name: _nameController.text,
        academicYear: _yearController.text,
        level: _selectedLevel,
        titulaire: _titulaireController.text,
        fraisEcole: _fraisEcoleController.text.isNotEmpty
            ? double.tryParse(_fraisEcoleController.text)
            : null,
        fraisCotisationParallele:
            _fraisCotisationParalleleController.text.isNotEmpty
            ? double.tryParse(_fraisCotisationParalleleController.text)
            : null,
        // Seuils de passage personnalisés
        seuilFelicitations:
            double.tryParse(_seuilFelicitationsController.text) ?? 16.0,
        seuilEncouragements:
            double.tryParse(_seuilEncouragementsController.text) ?? 14.0,
        seuilAdmission: double.tryParse(_seuilAdmissionController.text) ?? 12.0,
        seuilAvertissement:
            double.tryParse(_seuilAvertissementController.text) ?? 10.0,
        seuilConditions:
            double.tryParse(_seuilConditionsController.text) ?? 8.0,
        seuilRedoublement:
            double.tryParse(_seuilRedoublementController.text) ?? 8.0,
      );
      await _dbService.updateClass(
        widget.classe.name,
        widget.classe.academicYear,
        updatedClass,
      );
      await _loadClassSubjectsAndCoeffs();
      final refreshedClass = await _dbService.getClassByName(
        updatedClass.name,
        academicYear: updatedClass.academicYear,
      );
      final refreshedStudents = await _dbService.getStudents(
        className: updatedClass.name,
        academicYear: updatedClass.academicYear,
        includeDeleted: _visibilityFilter == 'all',
        onlyDeleted: _visibilityFilter == 'deleted',
      );

      if (!mounted) return;
      setState(() {
        final cls = refreshedClass ?? updatedClass;
        _nameController.text = cls.name;
        _yearController.text = cls.academicYear;
        _titulaireController.text = cls.titulaire ?? '';
        _fraisEcoleController.text = cls.fraisEcole?.toString() ?? '';
        _fraisCotisationParalleleController.text =
            cls.fraisCotisationParallele?.toString() ?? '';
        _selectedLevel = (cls.level?.trim().isNotEmpty ?? false)
            ? cls.level!.trim()
            : 'Primaire';
        // Mise à jour des seuils de passage
        _seuilFelicitationsController.text = cls.seuilFelicitations.toString();
        _seuilEncouragementsController.text = cls.seuilEncouragements
            .toString();
        _seuilAdmissionController.text = cls.seuilAdmission.toString();
        _seuilAvertissementController.text = cls.seuilAvertissement.toString();
        _seuilConditionsController.text = cls.seuilConditions.toString();
        _seuilRedoublementController.text = cls.seuilRedoublement.toString();
        _students = refreshedStudents;
        _selectedStudentIds.clear();
        _selectionMode = false;
        _isLoading = false;
      });
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Succès'),
          content: const Text('Classe mise à jour avec succès !'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erreur'),
          content: Text(
            'Erreur lors de la mise à jour : ${e.toString().contains('unique') ? 'Nom de classe déjà existant' : e}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _copyClass() async {
    // Demander l'année cible à l'utilisateur
    final classes = await _dbService.getClasses();
    final years =
        classes
            .map((c) => c.academicYear)
            .where((y) => y.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final current = _yearController.text.trim();
    String suggestNext() {
      try {
        final parts = current.split('-');
        final s = int.parse(parts.first);
        final e = int.parse(parts.last);
        return '${s + 1}-${e + 1}';
      } catch (_) {
        final now = DateTime.now().year;
        return '$now-${now + 1}';
      }
    }

    final TextEditingController yearCtrl = TextEditingController(
      text: suggestNext(),
    );
    String? targetYear = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Copier la classe vers…'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (years.isNotEmpty) ...[
                    const Text('Années existantes'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: years
                          .map(
                            (y) => ChoiceChip(
                              label: Text(y),
                              selected: yearCtrl.text == y,
                              onSelected: (_) =>
                                  setStateDialog(() => yearCtrl.text = y),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: yearCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Année cible',
                      hintText: 'ex: 2025-2026',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, yearCtrl.text.trim()),
                  child: const Text('Copier'),
                ),
              ],
            );
          },
        );
      },
    );
    if (targetYear == null || targetYear.isEmpty) return;
    final valid = RegExp(r'^\d{4}-\d{4}$').hasMatch(targetYear);
    if (!valid) {
      _showModernSnackBar(
        'Format d\'année invalide. Utilisez 2025-2026.',
        isError: true,
      );
      return;
    }

    // Interdire une double copie de la même classe pour la même année cible
    final existingInTarget = (await _dbService.getClasses())
        .where((c) => c.academicYear == targetYear)
        .toList();
    final originalName = _nameController.text.trim();
    final alreadyCopied = existingInTarget.any(
      (c) => c.name == originalName || c.name == '$originalName ($targetYear)',
    );
    if (alreadyCopied) {
      _showModernSnackBar(
        'Cette classe a déjà été copiée pour l\'année $targetYear.',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Préférer le même nom si disponible, sinon suffixer avec l'année cible
      String desired = originalName;
      if (await _dbService.getClassByName(desired, academicYear: targetYear) !=
          null) {
        desired = '$originalName ($targetYear)';
      }
      // Assurer l'unicité en dernier recours (rare)
      String uniqueName = desired;
      int k = 2;
      while (await _dbService.getClassByName(
            uniqueName,
            academicYear: targetYear,
          ) !=
          null) {
        uniqueName = '$desired-$k';
        k++;
      }

      final newClass = Class(
        name: uniqueName,
        academicYear: targetYear,
        level: _selectedLevel,
        titulaire: _titulaireController.text,
        fraisEcole: _fraisEcoleController.text.isNotEmpty
            ? double.tryParse(_fraisEcoleController.text)
            : null,
        fraisCotisationParallele:
            _fraisCotisationParalleleController.text.isNotEmpty
            ? double.tryParse(_fraisCotisationParalleleController.text)
            : null,
      );
      await _dbService.insertClass(newClass);
      setState(() => _isLoading = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Succès'),
          content: Text(
            'Classe copiée vers $targetYear sous le nom "$uniqueName".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isLoading = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erreur'),
          content: Text('Erreur lors de la copie : $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showModernSnackBar(String message, {bool isError = false}) {
    // Dans un dialog sans Scaffold, basculer en AlertDialog
    final hasMessenger = ScaffoldMessenger.maybeOf(context) != null;
    final hasScaffold = Scaffold.maybeOf(context) != null;
    if (hasMessenger && hasScaffold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? const Color(0xFFE53E3E)
              : const Color(0xFF38A169),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isError ? 'Erreur' : 'Information'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _editStudent(Student student) async {
    final GlobalKey<StudentRegistrationFormState> studentFormKey =
        GlobalKey<StudentRegistrationFormState>();
    await showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: AppStrings.editStudent,
        content: StudentRegistrationForm(
          key: studentFormKey,
          className: student.className,
          classFieldReadOnly: true,
          onSubmit: () async {
            await _reloadStudentsForCurrentClass();
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Succès'),
                content: const Text('Élève mis à jour avec succès !'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          },
          student: student,
        ),
        fields: const [],
        onSubmit: () {
          studentFormKey.currentState?.submitForm();
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
          ElevatedButton(
            onPressed: () => studentFormKey.currentState?.submitForm(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3182CE),
              foregroundColor: Colors.white,
            ),
            child: const Text('Modifier'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStudent(Student student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _buildModernDeleteDialog(student),
    );
    if (confirm == true) {
      try {
        debugPrint(
          '[ClassDetailsPage] Mise en corbeille demandée: id=${student.id} name=${student.name}',
        );
        // Suppression logique (corbeille) : l'élève reste restaurable.
        await _dbService.softDeleteStudents(studentIds: [student.id]);
        await _reloadStudentsForCurrentClass();
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Succès'),
            content: const Text('Élève placé dans la corbeille.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } catch (e) {
        debugPrint(
          '[ClassDetailsPage] Erreur suppression: id=${student.id} error=$e',
        );
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Erreur'),
            content: Text('Erreur lors de la suppression : $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _restoreStudent(Student student) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer l\'élève ?'),
        content: Text(
          'Restaurer "${_displayStudentName(student)}" depuis la corbeille ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      debugPrint(
        '[ClassDetailsPage] restore student: id=${student.id} name=${student.name}',
      );
      await _dbService.restoreStudents(studentIds: [student.id]);
      await _reloadStudentsForCurrentClass();
      if (!mounted) return;
      _showModernSnackBar('Élève restauré.');
    } catch (e) {
      debugPrint('[ClassDetailsPage] restore error: id=${student.id} error=$e');
      if (!mounted) return;
      _showModernSnackBar('Erreur: $e', isError: true);
    }
  }

  List<Student> _selectedStudents() {
    return _students.where((s) => _selectedStudentIds.contains(s.id)).toList();
  }

  Future<void> _bulkDeleteSelectedStudents() async {
    final selected = _selectedStudents();
    if (selected.isEmpty) return;
    debugPrint(
      '[ClassDetailsPage] bulk delete requested: count=${selected.length} ids=${selected.map((s) => s.id).take(10).join(",")}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer les élèves ?'),
        content: Text(
          'Cette action place ${selected.length} élève(s) dans la corbeille (suppression logique).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    debugPrint('[ClassDetailsPage] bulk delete confirmed');
    await _dbService.softDeleteStudents(
      studentIds: selected.map((s) => s.id).toList(),
    );
    await _reloadStudentsForCurrentClass();
    if (!mounted) return;
    _showModernSnackBar('${selected.length} élève(s) supprimé(s).');
    _setSelectionMode(false);
  }

  Future<void> _bulkRestoreSelectedStudents() async {
    final selected = _selectedStudents();
    if (selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer les élèves ?'),
        content: Text(
          'Restaurer ${selected.length} élève(s) depuis la corbeille ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    debugPrint(
      '[ClassDetailsPage] bulk restore: count=${selected.length} ids=${selected.map((s) => s.id).take(10).join(",")}',
    );
    await _dbService.restoreStudents(
      studentIds: selected.map((s) => s.id).toList(),
    );
    await _reloadStudentsForCurrentClass();
    if (!mounted) return;
    _showModernSnackBar('${selected.length} élève(s) restauré(s).');
    _setSelectionMode(false);
  }

  Future<void> _bulkChangeClassYearSelected() async {
    final selected = _selectedStudents();
    if (selected.isEmpty) return;
    final allClasses = await _dbService.getClasses();
    if (!mounted) return;
    if (allClasses.isEmpty) {
      _showModernSnackBar('Aucune classe disponible.', isError: true);
      return;
    }

    String? selectedKey;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final keys =
              allClasses
                  .map((c) => '${c.name}:::${c.academicYear}')
                  .toSet()
                  .toList()
                ..sort();
          return AlertDialog(
            title: const Text('Changer classe/année'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appliquer à ${selected.length} élève(s).'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedKey,
                  decoration: const InputDecoration(
                    labelText: 'Nouvelle classe',
                    border: OutlineInputBorder(),
                  ),
                  items: keys.map((k) {
                    final parts = k.split(':::');
                    final label = parts.length == 2
                        ? '${parts[0]} (${parts[1]})'
                        : k;
                    return DropdownMenuItem(value: k, child: Text(label));
                  }).toList(),
                  onChanged: (v) => setState(() => selectedKey = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Note : ceci met à jour la classe/année de la fiche élève. Les historiques (paiements/notes) ne sont pas modifiés.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: selectedKey == null
                    ? null
                    : () => Navigator.of(ctx).pop(true),
                child: const Text('Appliquer'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || selectedKey == null) return;
    final parts = selectedKey!.split(':::');
    if (parts.length != 2) return;

    String? by;
    try {
      final user = await AuthService.instance.getCurrentUser();
      by = user?.displayName ?? user?.username;
    } catch (_) {}

    debugPrint(
      '[ClassDetailsPage] bulk change class/year: count=${selected.length} to=${parts[0]}(${parts[1]})',
    );
    await _dbService.updateStudentsClassAndYear(
      studentIds: selected.map((s) => s.id).toList(),
      className: parts[0],
      academicYear: parts[1],
      updatedBy: by,
    );
    await _reloadStudentsForCurrentClass();
    if (!mounted) return;
    _showModernSnackBar('Mise à jour effectuée (${selected.length}).');
    _setSelectionMode(false);
  }

  Future<void> _exportSelectedStudentIdCards() async {
    final selected = _selectedStudents();
    if (selected.isEmpty) return;
    debugPrint(
      '[ClassDetailsPage] export selected ID cards: count=${selected.length}',
    );
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Génération des cartes scolaires (${selected.length})...',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final result = await StudentIdCardService(dbService: _dbService)
          .exportStudentIdCardsPdf(
            students: selected,
            academicYear: _yearController.text,
            className: _nameController.text,
            dialogTitle: 'Choisissez un dossier de sauvegarde',
          );

      if (result.directoryResult.usedFallback &&
          result.directoryResult.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.directoryResult.errorMessage!}\nDossier: ${result.directoryResult.path}',
            ),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      await OpenFile.open(result.file.path);
    } catch (e) {
      debugPrint('[ClassDetailsPage] export selected ID cards error: $e');
      if (!mounted) return;
      _showModernSnackBar('Erreur: $e', isError: true);
    }
  }

  Future<void> _exportClassDeliberationMinutesPdf({
    required String term,
    required List<Map<String, dynamic>> reportCardsForTerm,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      _showModernSnackBar(
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directory == null) return;

    try {
      final info = await loadSchoolInfo();
      final className = _nameController.text.trim();
      final academicYear = _yearController.text.trim();

      // Enrich report cards with student names for the PV
      final List<Map<String, dynamic>> enrichedCards = [];
      for (final rc in reportCardsForTerm) {
        final studentId = (rc['studentId'] ?? '').toString();
        final student = await _dbService.getStudentById(studentId);
        final Map<String, dynamic> enriched = Map<String, dynamic>.from(rc);
        enriched['studentName'] = student != null
            ? '${student.lastName.toUpperCase()} ${student.firstName}'
            : studentId;
        enrichedCards.add(enriched);
      }

      final pdfBytes = await ClassSynthesisPdfService.generateClassSynthesisPdf(
        schoolInfo: info,
        className: className,
        academicYear: academicYear,
        term: term,
        reportCards: enrichedCards,
      );

      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final safeTerm = term.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final safeClass = className.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final fileName = 'PV_Deliberation_${safeClass}_${safeTerm}_$stamp.pdf';

      final file = File('$directory/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);

      if (!mounted) return;
      _showModernSnackBar('PV créé: $fileName');
      await OpenFile.open(file.path);
    } catch (e) {
      debugPrint(
        '[ClassDetailsPage] _exportClassDeliberationMinutesPdf error: $e',
      );
      _showModernSnackBar(
        'Erreur lors de la création du PV: $e',
        isError: true,
      );
    }
  }

  Future<_ArchivedBulletinsView> _loadArchivedBulletinsView() async {
    final year = _yearController.text.trim();
    final className = _nameController.text.trim();
    final reportCards = await _dbService.getArchivedReportCardsByClassAndYear(
      academicYear: year,
      className: className,
    );
    final students = await _dbService.getStudents(
      className: className,
      academicYear: year,
      includeDeleted: true,
    );
    final byId = <String, Student>{for (final s in students) s.id: s};

    // L'archive peut référencer des élèves qui ont changé de classe ensuite.
    // On complète donc la map en récupérant les fiches par ID au besoin.
    final archivedStudentIds = reportCards
        .map((e) => (e['studentId'] ?? '').toString())
        .where((e) => e.trim().isNotEmpty)
        .toSet();
    for (final id in archivedStudentIds) {
      if (byId.containsKey(id)) continue;
      try {
        final s = await _dbService.getStudentById(id);
        if (s != null) byId[id] = s;
      } catch (_) {}
    }
    return _ArchivedBulletinsView(reportCards: reportCards, studentsById: byId);
  }

  List<double?> _decodeDoubleList(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return const [];
    return s
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((e) => double.tryParse(e.trim()))
        .toList();
  }

  List<String> _decodeStringList(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return const [];
    return s
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _proposedDecisionForAverage(double moyenne) {
    final felic = double.tryParse(_seuilFelicitationsController.text) ?? 16.0;
    final encour = double.tryParse(_seuilEncouragementsController.text) ?? 14.0;
    final admis = double.tryParse(_seuilAdmissionController.text) ?? 12.0;
    final avert = double.tryParse(_seuilAvertissementController.text) ?? 10.0;
    final cond = double.tryParse(_seuilConditionsController.text) ?? 8.0;
    final redoub = double.tryParse(_seuilRedoublementController.text) ?? 8.0;

    if (moyenne >= felic) return 'Félicitations';
    if (moyenne >= encour) return 'Encouragements';
    if (moyenne >= admis) return 'Admis';
    if (moyenne >= avert) return 'Avertissement';
    if (moyenne >= cond) return 'Sous conditions';
    if (moyenne < redoub) return 'Redoublement';
    return 'Sous conditions';
  }

  Future<List<int>> _generateArchivedReportCardPdf({
    required Student student,
    required Map<String, dynamic> reportCard,
  }) async {
    final info = await loadSchoolInfo();
    final classRow = await _dbService.getClassByName(
      reportCard['className']?.toString() ?? student.className,
      academicYear:
          reportCard['academicYear']?.toString() ?? student.academicYear,
    );
    if (classRow == null) {
      throw Exception('Classe introuvable pour générer le bulletin.');
    }

    final academicYear = reportCard['academicYear']?.toString() ?? '';
    final term = reportCard['term']?.toString() ?? '';
    final archivedGradesAll = await _dbService.getArchivedGrades(
      academicYear: academicYear,
      className: classRow.name,
      studentId: student.id,
    );
    final archivedGrades = archivedGradesAll
        .where((g) => g.term == term)
        .toList();

    final subjectApps = await _dbService.getSubjectAppreciationsArchiveByKeys(
      studentId: student.id,
      className: classRow.name,
      academicYear: academicYear,
      term: term,
    );

    final professeurs = <String, String>{};
    final appreciations = <String, String>{};
    final moyennesClasse = <String, String>{};
    for (final row in subjectApps) {
      final subject = (row['subject'] ?? '').toString();
      if (subject.trim().isEmpty) continue;
      professeurs[subject] = (row['professeur'] ?? '-').toString();
      appreciations[subject] = (row['appreciation'] ?? '-').toString();
      moyennesClasse[subject] = (row['moyenne_classe'] ?? '-').toString();
    }

    final moyennesParPeriode = _decodeDoubleList(
      reportCard['moyennes_par_periode'],
    );
    final allTerms = _decodeStringList(reportCard['all_terms']);
    final isExAequo = (reportCard['exaequo'] is int)
        ? (reportCard['exaequo'] as int) == 1
        : (reportCard['exaequo']?.toString() == '1');

    return PdfService.generateReportCardPdf(
      student: student,
      schoolInfo: info,
      grades: archivedGrades,
      professeurs: professeurs,
      appreciations: appreciations,
      moyennesClasse: moyennesClasse,
      appreciationGenerale: (reportCard['appreciation_generale'] ?? '')
          .toString(),
      decision: (reportCard['decision'] ?? '').toString(),
      recommandations: (reportCard['recommandations'] ?? '').toString(),
      forces: (reportCard['forces'] ?? '').toString(),
      pointsADevelopper: (reportCard['points_a_developper'] ?? '').toString(),
      sanctions: (reportCard['sanctions'] ?? '').toString(),
      attendanceJustifiee: (reportCard['attendance_justifiee'] ?? 0) as int,
      attendanceInjustifiee: (reportCard['attendance_injustifiee'] ?? 0) as int,
      retards: (reportCard['retards'] ?? 0) as int,
      presencePercent: (reportCard['presence_percent'] ?? 0.0) is int
          ? (reportCard['presence_percent'] as int).toDouble()
          : (reportCard['presence_percent'] ?? 0.0) as double,
      conduite: (reportCard['conduite'] ?? '').toString(),
      telEtab: info.telephone ?? '',
      mailEtab: info.email ?? '',
      webEtab: info.website ?? '',
      titulaire: classRow.titulaire ?? '',
      subjects: archivedGrades.map((e) => e.subject).toSet().toList(),
      moyennesParPeriode: moyennesParPeriode,
      moyenneGenerale: reportCard['moyenne_generale']?.toDouble() ?? 0.0,
      rang: reportCard['rang'] ?? 0,
      exaequo: isExAequo,
      nbEleves: reportCard['nb_eleves'] ?? 0,
      mention: (reportCard['mention'] ?? '').toString(),
      allTerms: allTerms,
      periodLabel: term.contains('Semestre') ? 'Semestre' : 'Trimestre',
      selectedTerm: term,
      academicYear: academicYear,
      faitA: (reportCard['fait_a'] ?? '').toString(),
      leDate: (reportCard['le_date'] ?? '').toString(),
      isLandscape: false,
      niveau: classRow.level ?? '',
      moyenneGeneraleDeLaClasse:
          reportCard['moyenne_generale_classe']?.toDouble() ?? 0.0,
      moyenneLaPlusForte:
          reportCard['moyenne_la_plus_forte']?.toDouble() ?? 0.0,
      moyenneLaPlusFaible:
          reportCard['moyenne_la_plus_faible']?.toDouble() ?? 0.0,
      moyenneAnnuelle: reportCard['moyenne_annuelle']?.toDouble() ?? 0.0,
      duplicata: true,
    );
  }

  Future<List<int>> _generateArchivedReportCardPdfCustom({
    required Student student,
    required Map<String, dynamic> reportCard,
    required bool isLandscape,
    required bool useLongFormat,
  }) async {
    final info = await loadSchoolInfo();
    final classRow = await _dbService.getClassByName(
      reportCard['className']?.toString() ?? student.className,
      academicYear:
          reportCard['academicYear']?.toString() ?? student.academicYear,
    );
    if (classRow == null) {
      throw Exception('Classe introuvable pour générer le bulletin.');
    }

    final academicYear = reportCard['academicYear']?.toString() ?? '';
    final term = reportCard['term']?.toString() ?? '';
    final archivedGradesAll = await _dbService.getArchivedGrades(
      academicYear: academicYear,
      className: classRow.name,
      studentId: student.id,
    );
    final archivedGrades = archivedGradesAll
        .where((g) => g.term == term)
        .toList();

    final subjectApps = await _dbService.getSubjectAppreciationsArchiveByKeys(
      studentId: student.id,
      className: classRow.name,
      academicYear: academicYear,
      term: term,
    );

    final professeurs = <String, String>{};
    final appreciations = <String, String>{};
    final moyennesClasse = <String, String>{};
    for (final row in subjectApps) {
      final subject = (row['subject'] ?? '').toString();
      if (subject.trim().isEmpty) continue;
      professeurs[subject] = (row['professeur'] ?? '-').toString();
      appreciations[subject] = (row['appreciation'] ?? '-').toString();
      moyennesClasse[subject] = (row['moyenne_classe'] ?? '-').toString();
    }

    final moyennesParPeriode = _decodeDoubleList(
      reportCard['moyennes_par_periode'],
    );
    final allTerms = _decodeStringList(reportCard['all_terms']);

    final prefs = await SharedPreferences.getInstance();
    final footerNote = prefs.getString('report_card_footer_note') ?? '';
    final adminCivility = prefs.getString('school_admin_civility') ?? 'M.';

    return ReportCardCustomExportService.generateReportCardCustomPdf(
      student: student,
      schoolInfo: info,
      grades: archivedGrades,
      subjects: archivedGrades.map((e) => e.subject).toSet().toList(),
      professeurs: professeurs,
      appreciations: appreciations,
      moyennesClasse: moyennesClasse,
      moyennesParPeriode: moyennesParPeriode,
      allTerms: allTerms,
      moyenneGenerale: reportCard['moyenne_generale']?.toDouble() ?? 0.0,
      rang: reportCard['rang'] ?? 0,
      nbEleves: reportCard['nb_eleves'] ?? 0,
      periodLabel: term.contains('Semestre') ? 'Semestre' : 'Trimestre',
      appreciationGenerale: (reportCard['appreciation_generale'] ?? '')
          .toString(),
      mention: (reportCard['mention'] ?? '').toString(),
      decision: (reportCard['decision'] ?? '').toString(),
      decisionAutomatique: '',
      conduite: (reportCard['conduite'] ?? '').toString(),
      recommandations: (reportCard['recommandations'] ?? '').toString(),
      forces: (reportCard['forces'] ?? '').toString(),
      pointsADevelopper: (reportCard['points_a_developper'] ?? '').toString(),
      sanctions: (reportCard['sanctions'] ?? '').toString(),
      attendanceJustifiee: (reportCard['attendance_justifiee'] ?? 0) as int,
      attendanceInjustifiee: (reportCard['attendance_injustifiee'] ?? 0) as int,
      retards: (reportCard['retards'] ?? 0) as int,
      presencePercent: (reportCard['presence_percent'] ?? 0.0) is int
          ? (reportCard['presence_percent'] as int).toDouble()
          : (reportCard['presence_percent'] ?? 0.0) as double,
      moyenneGeneraleDeLaClasse:
          reportCard['moyenne_generale_classe']?.toDouble() ?? 0.0,
      moyenneLaPlusForte:
          reportCard['moyenne_la_plus_forte']?.toDouble() ?? 0.0,
      moyenneLaPlusFaible:
          reportCard['moyenne_la_plus_faible']?.toDouble() ?? 0.0,
      moyenneAnnuelle: reportCard['moyenne_annuelle']?.toDouble() ?? 0.0,
      moyenneAnnuelleClasse: null,
      rangAnnuel: null,
      nbElevesAnnuel: null,
      academicYear: academicYear,
      term: term,
      className: classRow.name,
      selectedTerm: term,
      faitA: (reportCard['fait_a'] ?? '').toString(),
      leDate: (reportCard['le_date'] ?? '').toString(),
      titulaireName: classRow.titulaire ?? '',
      directorName: info.director,
      titulaireCivility: 'M.',
      directorCivility: adminCivility,
      footerNote: footerNote,
      isLandscape: isLandscape,
      useLongFormat: useLongFormat,
      duplicata: true,
    );
  }

  Future<List<int>> _generateArchivedReportCardPdfCompact({
    required Student student,
    required Map<String, dynamic> reportCard,
  }) async {
    final info = await loadSchoolInfo();
    final classRow = await _dbService.getClassByName(
      reportCard['className']?.toString() ?? student.className,
      academicYear:
          reportCard['academicYear']?.toString() ?? student.academicYear,
    );
    if (classRow == null) {
      throw Exception('Classe introuvable pour générer le bulletin.');
    }

    final academicYear = reportCard['academicYear']?.toString() ?? '';
    final term = reportCard['term']?.toString() ?? '';
    final archivedGradesAll = await _dbService.getArchivedGrades(
      academicYear: academicYear,
      className: classRow.name,
      studentId: student.id,
    );
    final archivedGrades = archivedGradesAll
        .where((g) => g.term == term)
        .toList();

    final subjectApps = await _dbService.getSubjectAppreciationsArchiveByKeys(
      studentId: student.id,
      className: classRow.name,
      academicYear: academicYear,
      term: term,
    );

    final professeurs = <String, String>{};
    final appreciations = <String, String>{};
    final moyennesClasse = <String, String>{};
    for (final row in subjectApps) {
      final subject = (row['subject'] ?? '').toString();
      if (subject.trim().isEmpty) continue;
      professeurs[subject] = (row['professeur'] ?? '-').toString();
      appreciations[subject] = (row['appreciation'] ?? '-').toString();
      moyennesClasse[subject] = (row['moyenne_classe'] ?? '-').toString();
    }

    final moyennesParPeriode = _decodeDoubleList(
      reportCard['moyennes_par_periode'],
    );
    final allTerms = _decodeStringList(reportCard['all_terms']);
    final isExAequo = (reportCard['exaequo'] is int)
        ? (reportCard['exaequo'] as int) == 1
        : (reportCard['exaequo']?.toString() == '1');

    return PdfService.generateReportCardPdfCompact(
      student: student,
      schoolInfo: info,
      grades: archivedGrades,
      professeurs: professeurs,
      appreciations: appreciations,
      moyennesClasse: moyennesClasse,
      appreciationGenerale: (reportCard['appreciation_generale'] ?? '')
          .toString(),
      decision: (reportCard['decision'] ?? '').toString(),
      recommandations: (reportCard['recommandations'] ?? '').toString(),
      forces: (reportCard['forces'] ?? '').toString(),
      pointsADevelopper: (reportCard['points_a_developper'] ?? '').toString(),
      sanctions: (reportCard['sanctions'] ?? '').toString(),
      attendanceJustifiee: (reportCard['attendance_justifiee'] ?? 0) as int,
      attendanceInjustifiee: (reportCard['attendance_injustifiee'] ?? 0) as int,
      retards: (reportCard['retards'] ?? 0) as int,
      presencePercent: (reportCard['presence_percent'] ?? 0.0) is int
          ? (reportCard['presence_percent'] as int).toDouble()
          : (reportCard['presence_percent'] ?? 0.0) as double,
      conduite: (reportCard['conduite'] ?? '').toString(),
      telEtab: info.telephone ?? '',
      mailEtab: info.email ?? '',
      webEtab: info.website ?? '',
      titulaire: classRow.titulaire ?? '',
      subjects: archivedGrades.map((e) => e.subject).toSet().toList(),
      moyennesParPeriode: moyennesParPeriode,
      moyenneGenerale: reportCard['moyenne_generale']?.toDouble() ?? 0.0,
      rang: reportCard['rang'] ?? 0,
      exaequo: isExAequo,
      nbEleves: reportCard['nb_eleves'] ?? 0,
      mention: (reportCard['mention'] ?? '').toString(),
      allTerms: allTerms,
      periodLabel: term.contains('Semestre') ? 'Semestre' : 'Trimestre',
      selectedTerm: term,
      academicYear: academicYear,
      faitA: (reportCard['fait_a'] ?? '').toString(),
      leDate: (reportCard['le_date'] ?? '').toString(),
      isLandscape: false,
      niveau: classRow.level ?? '',
      moyenneGeneraleDeLaClasse:
          reportCard['moyenne_generale_classe']?.toDouble() ?? 0.0,
      moyenneLaPlusForte:
          reportCard['moyenne_la_plus_forte']?.toDouble() ?? 0.0,
      moyenneLaPlusFaible:
          reportCard['moyenne_la_plus_faible']?.toDouble() ?? 0.0,
      moyenneAnnuelle: reportCard['moyenne_annuelle']?.toDouble() ?? 0.0,
      duplicata: true,
    );
  }

  Future<List<int>> _generateArchivedReportCardPdfUltraCompact({
    required Student student,
    required Map<String, dynamic> reportCard,
  }) async {
    final info = await loadSchoolInfo();
    final classRow = await _dbService.getClassByName(
      reportCard['className']?.toString() ?? student.className,
      academicYear:
          reportCard['academicYear']?.toString() ?? student.academicYear,
    );
    if (classRow == null) {
      throw Exception('Classe introuvable pour générer le bulletin.');
    }

    final academicYear = reportCard['academicYear']?.toString() ?? '';
    final term = reportCard['term']?.toString() ?? '';
    final archivedGradesAll = await _dbService.getArchivedGrades(
      academicYear: academicYear,
      className: classRow.name,
      studentId: student.id,
    );
    final archivedGrades = archivedGradesAll
        .where((g) => g.term == term)
        .toList();

    final subjectApps = await _dbService.getSubjectAppreciationsArchiveByKeys(
      studentId: student.id,
      className: classRow.name,
      academicYear: academicYear,
      term: term,
    );

    final professeurs = <String, String>{};
    final appreciations = <String, String>{};
    final moyennesClasse = <String, String>{};
    for (final row in subjectApps) {
      final subject = (row['subject'] ?? '').toString();
      if (subject.trim().isEmpty) continue;
      professeurs[subject] = (row['professeur'] ?? '-').toString();
      appreciations[subject] = (row['appreciation'] ?? '-').toString();
      moyennesClasse[subject] = (row['moyenne_classe'] ?? '-').toString();
    }

    final moyennesParPeriode = _decodeDoubleList(
      reportCard['moyennes_par_periode'],
    );
    final allTerms = _decodeStringList(reportCard['all_terms']);
    final isExAequo = (reportCard['exaequo'] is int)
        ? (reportCard['exaequo'] as int) == 1
        : (reportCard['exaequo']?.toString() == '1');

    return PdfService.generateReportCardPdfUltraCompact(
      student: student,
      schoolInfo: info,
      grades: archivedGrades,
      professeurs: professeurs,
      appreciations: appreciations,
      moyennesClasse: moyennesClasse,
      appreciationGenerale: (reportCard['appreciation_generale'] ?? '')
          .toString(),
      decision: (reportCard['decision'] ?? '').toString(),
      recommandations: (reportCard['recommandations'] ?? '').toString(),
      forces: (reportCard['forces'] ?? '').toString(),
      pointsADevelopper: (reportCard['points_a_developper'] ?? '').toString(),
      sanctions: (reportCard['sanctions'] ?? '').toString(),
      attendanceJustifiee: (reportCard['attendance_justifiee'] ?? 0) as int,
      attendanceInjustifiee: (reportCard['attendance_injustifiee'] ?? 0) as int,
      retards: (reportCard['retards'] ?? 0) as int,
      presencePercent: (reportCard['presence_percent'] ?? 0.0) is int
          ? (reportCard['presence_percent'] as int).toDouble()
          : (reportCard['presence_percent'] ?? 0.0) as double,
      conduite: (reportCard['conduite'] ?? '').toString(),
      telEtab: info.telephone ?? '',
      mailEtab: info.email ?? '',
      webEtab: info.website ?? '',
      titulaire: classRow.titulaire ?? '',
      subjects: archivedGrades.map((e) => e.subject).toSet().toList(),
      moyennesParPeriode: moyennesParPeriode,
      moyenneGenerale: reportCard['moyenne_generale']?.toDouble() ?? 0.0,
      rang: reportCard['rang'] ?? 0,
      exaequo: isExAequo,
      nbEleves: reportCard['nb_eleves'] ?? 0,
      mention: (reportCard['mention'] ?? '').toString(),
      allTerms: allTerms,
      periodLabel: term.contains('Semestre') ? 'Semestre' : 'Trimestre',
      selectedTerm: term,
      academicYear: academicYear,
      faitA: (reportCard['fait_a'] ?? '').toString(),
      leDate: (reportCard['le_date'] ?? '').toString(),
      isLandscape: false,
      niveau: classRow.level ?? '',
      moyenneGeneraleDeLaClasse:
          reportCard['moyenne_generale_classe']?.toDouble() ?? 0.0,
      moyenneLaPlusForte:
          reportCard['moyenne_la_plus_forte']?.toDouble() ?? 0.0,
      moyenneLaPlusFaible:
          reportCard['moyenne_la_plus_faible']?.toDouble() ?? 0.0,
      moyenneAnnuelle: reportCard['moyenne_annuelle']?.toDouble() ?? 0.0,
      duplicata: true,
    );
  }

  Future<void> _exportArchivedBulletinsZip({
    required String term,
    required List<Map<String, dynamic>> reportCardsForTerm,
    required String variant,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      _showModernSnackBar(
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directory == null) return;

    final year = _yearController.text.trim();
    final className = _nameController.text.trim();

    bool isLandscape = false;
    bool useLongFormat = true;

    if (variant == 'custom') {
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
      isLandscape = orientation == 'landscape';

      final formatChoice =
          await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Format du PDF'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Format long (A4 standard)'),
                    subtitle: const Text('Dimensions standard A4'),
                    leading: const Icon(Icons.description),
                    onTap: () => Navigator.of(context).pop('long'),
                  ),
                  ListTile(
                    title: const Text('Format court (compact)'),
                    subtitle: const Text('Dimensions réduites'),
                    leading: const Icon(Icons.view_compact),
                    onTap: () => Navigator.of(context).pop('short'),
                  ),
                ],
              ),
            ),
          ) ??
          'long';
      useLongFormat = formatChoice == 'long';
    }

    debugPrint(
      '[ClassDetailsPage] export archived bulletins ZIP: class=$className year=$year term=$term variant=$variant count=${reportCardsForTerm.length}',
    );

    final archive = Archive();
    for (final rc in reportCardsForTerm) {
      final studentId = (rc['studentId'] ?? '').toString();
      if (studentId.isEmpty) continue;
      final student = await _dbService.getStudentById(studentId);
      if (student == null) continue;

      final pdfBytes = variant == 'compact'
          ? await _generateArchivedReportCardPdfCompact(
              student: student,
              reportCard: rc,
            )
          : variant == 'ultra'
          ? await _generateArchivedReportCardPdfUltraCompact(
              student: student,
              reportCard: rc,
            )
          : variant == 'custom'
          ? await _generateArchivedReportCardPdfCustom(
              student: student,
              reportCard: rc,
              isLandscape: isLandscape,
              useLongFormat: useLongFormat,
            )
          : await _generateArchivedReportCardPdf(
              student: student,
              reportCard: rc,
            );
      final safeName = '${student.firstName}_${student.lastName}'
          .trim()
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '');
      final safeId = student.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '');
      final safeTerm = term.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final fileName = 'Bulletin_${safeName}_${safeId}_${safeTerm}_$year.pdf';
      archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      _showModernSnackBar('Erreur lors de la création du ZIP.', isError: true);
      return;
    }

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final safeTerm = term.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final safeClass = className.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final suffix = variant == 'compact'
        ? '_compact'
        : variant == 'ultra'
        ? '_ultra_compact'
        : variant == 'custom'
        ? '_custom'
        : '';
    final out = File(
      '$directory/bulletins_archives_${safeClass}_${safeTerm}${suffix}_$stamp.zip',
    );
    await out.writeAsBytes(zipBytes, flush: true);
    if (!mounted) return;
    _showModernSnackBar('ZIP créé: ${out.path.split('/').last}');
    try {
      await OpenFile.open(out.path);
    } catch (_) {}
  }

  Widget _buildModernDeleteDialog(Student student) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.delete_outline_rounded, color: Color(0xFFE11D48)),
          SizedBox(width: 8),
          Text(
            'Mettre à la corbeille',
            style: TextStyle(
              color: Color(0xFFE11D48),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              size: 40,
              color: Color(0xFFE11D48),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Voulez-vous mettre l'élève ${_displayStudentName(student)} dans la corbeille ?\nVous pourrez le restaurer depuis la page Élèves.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color,
              height: 1.5,
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE11D48),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Corbeille'),
        ),
      ],
    );
  }

  Widget _buildModernSectionTitle(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Colors.white,
              semanticLabel: title,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge!.color,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernFormCard(List<Widget> children) {
    final int nbEleves = _students.length;
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double totalClasse = nbEleves * (fraisEcole + fraisCotisation);
    // color for totals will be derived from the theme where needed; remove unused local variable
    children.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: CustomFormField(
          controller: TextEditingController(
            text: '${totalClasse.toStringAsFixed(2)} FCFA',
          ),
          labelText: 'Total à payer pour la classe',
          hintText: '',
          readOnly: true,
          suffixIcon: Icons.summarize,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.98),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          // Nom de la classe
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _nameController,
                              labelText: AppStrings.classNameDialog,
                              hintText: 'Entrez le nom de la classe',
                              validator: (value) =>
                                  value!.isEmpty ? AppStrings.required : null,
                              suffixIcon: Icons.class_,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _yearController,
                              labelText: AppStrings.academicYearDialog,
                              hintText: "Entrez l'année scolaire",
                              validator: (value) =>
                                  value!.isEmpty ? AppStrings.required : null,
                              suffixIcon: Icons.calendar_today,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: DropdownButtonFormField<String>(
                              value: _selectedLevel,
                              decoration: const InputDecoration(
                                labelText: 'Niveau scolaire',
                                border: OutlineInputBorder(),
                              ),
                              items: _levels
                                  .map(
                                    (level) => DropdownMenuItem(
                                      value: level,
                                      child: Text(level),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _selectedLevel = value);
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _titulaireController,
                              labelText: 'Titulaire',
                              hintText: 'Nom du titulaire de la classe',
                              suffixIcon: Icons.person_outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _fraisEcoleController,
                              labelText: "Frais d'école",
                              hintText: "Montant des frais d'école",
                              validator: (value) {
                                if (value != null &&
                                    value.isNotEmpty &&
                                    double.tryParse(value) == null) {
                                  return 'Veuillez entrer un montant valide';
                                }
                                return null;
                              },
                              suffixIcon: Icons.attach_money,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _fraisCotisationParalleleController,
                              labelText: 'Frais de cotisation parallèle',
                              hintText:
                                  'Montant des frais de cotisation parallèle',
                              validator: (value) {
                                if (value != null &&
                                    value.isNotEmpty &&
                                    double.tryParse(value) == null) {
                                  return 'Veuillez entrer un montant valide';
                                }
                                return null;
                              },
                              suffixIcon: Icons.account_balance_wallet_outlined,
                            ),
                          ),
                          // Champ du montant total à payer pour la classe
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: TextEditingController(
                                text: '${totalClasse.toStringAsFixed(2)} FCFA',
                              ),
                              labelText: 'Total à payer pour la classe',
                              hintText: '',
                              readOnly: true,
                              suffixIcon: Icons.summarize,
                            ),
                          ),
                          // Section des seuils de passage
                          Container(
                            margin: const EdgeInsets.only(top: 24),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.school,
                                      color: Colors.blue.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Seuils de passage en classe supérieure',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Configurez les moyennes minimales pour chaque type de décision du conseil de classe :',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: CustomFormField(
                                        controller:
                                            _seuilFelicitationsController,
                                        labelText: 'Félicitations (≥)',
                                        hintText: '16.0',
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value != null &&
                                              value.isNotEmpty) {
                                            final val = double.tryParse(value);
                                            if (val == null ||
                                                val < 0 ||
                                                val > 20) {
                                              return 'Valeur entre 0 et 20';
                                            }
                                          }
                                          return null;
                                        },
                                        suffixIcon: Icons.star,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: CustomFormField(
                                        controller:
                                            _seuilEncouragementsController,
                                        labelText: 'Encouragements (≥)',
                                        hintText: '14.0',
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value != null &&
                                              value.isNotEmpty) {
                                            final val = double.tryParse(value);
                                            if (val == null ||
                                                val < 0 ||
                                                val > 20) {
                                              return 'Valeur entre 0 et 20';
                                            }
                                          }
                                          return null;
                                        },
                                        suffixIcon: Icons.thumb_up,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: CustomFormField(
                                        controller: _seuilAdmissionController,
                                        labelText: 'Admission (≥)',
                                        hintText: '12.0',
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value != null &&
                                              value.isNotEmpty) {
                                            final val = double.tryParse(value);
                                            if (val == null ||
                                                val < 0 ||
                                                val > 20) {
                                              return 'Valeur entre 0 et 20';
                                            }
                                          }
                                          return null;
                                        },
                                        suffixIcon: Icons.check_circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: CustomFormField(
                                        controller:
                                            _seuilAvertissementController,
                                        labelText: 'Avertissement (≥)',
                                        hintText: '10.0',
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value != null &&
                                              value.isNotEmpty) {
                                            final val = double.tryParse(value);
                                            if (val == null ||
                                                val < 0 ||
                                                val > 20) {
                                              return 'Valeur entre 0 et 20';
                                            }
                                          }
                                          return null;
                                        },
                                        suffixIcon: Icons.warning,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: CustomFormField(
                                        controller: _seuilConditionsController,
                                        labelText: 'Sous conditions (≥)',
                                        hintText: '8.0',
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value != null &&
                                              value.isNotEmpty) {
                                            final val = double.tryParse(value);
                                            if (val == null ||
                                                val < 0 ||
                                                val > 20) {
                                              return 'Valeur entre 0 et 20';
                                            }
                                          }
                                          return null;
                                        },
                                        suffixIcon: Icons.help_outline,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: CustomFormField(
                                        controller:
                                            _seuilRedoublementController,
                                        labelText: 'Redoublement (<)',
                                        hintText: '8.0',
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value != null &&
                                              value.isNotEmpty) {
                                            final val = double.tryParse(value);
                                            if (val == null ||
                                                val < 0 ||
                                                val > 20) {
                                              return 'Valeur entre 0 et 20';
                                            }
                                          }
                                          return null;
                                        },
                                        suffixIcon: Icons.repeat,
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
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _nameController,
                        labelText: AppStrings.classNameDialog,
                        hintText: 'Entrez le nom de la classe',
                        validator: (value) =>
                            value!.isEmpty ? AppStrings.required : null,
                        suffixIcon: Icons.class_,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _yearController,
                        labelText: AppStrings.academicYearDialog,
                        hintText: "Entrez l'année scolaire",
                        validator: (value) =>
                            value!.isEmpty ? AppStrings.required : null,
                        suffixIcon: Icons.calendar_today,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: DropdownButtonFormField<String>(
                        value: _selectedLevel,
                        decoration: const InputDecoration(
                          labelText: 'Niveau scolaire',
                          border: OutlineInputBorder(),
                        ),
                        items: _levels
                            .map(
                              (level) => DropdownMenuItem(
                                value: level,
                                child: Text(level),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _selectedLevel = value);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _titulaireController,
                        labelText: 'Titulaire',
                        hintText: 'Nom du titulaire de la classe',
                        suffixIcon: Icons.person_outline,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _fraisEcoleController,
                        labelText: "Frais d'école",
                        hintText: "Montant des frais d'école",
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              double.tryParse(value) == null) {
                            return 'Veuillez entrer un montant valide';
                          }
                          return null;
                        },
                        suffixIcon: Icons.attach_money,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _fraisCotisationParalleleController,
                        labelText: 'Frais de cotisation parallèle',
                        hintText: 'Montant des frais de cotisation parallèle',
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              double.tryParse(value) == null) {
                            return 'Veuillez entrer un montant valide';
                          }
                          return null;
                        },
                        suffixIcon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    // Champ du montant total à payer pour la classe (mobile)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: TextEditingController(
                          text: '${totalClasse.toStringAsFixed(2)} FCFA',
                        ),
                        labelText: 'Total à payer pour la classe',
                        hintText: '',
                        readOnly: true,
                        suffixIcon: Icons.summarize,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildModernSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'Rechercher par nom, ID ou genre...',
          hintStyle: TextStyle(
            color: Theme.of(
              context,
            ).textTheme.bodyMedium!.color?.withOpacity(0.6),
            fontSize: 16,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: Colors.white,
              size: 20,
              semanticLabel: 'Rechercher',
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
        ),
        style: const TextStyle(fontSize: 16),
        onChanged: (value) =>
            setState(() => _studentSearchQuery = value.trim()),
      ),
    );
  }

  Widget _buildModernStudentCard(
    Student student, {
    required bool selectionMode,
    required bool selected,
  }) {
    return FutureBuilder<double>(
      future: _dbService.getTotalPaidForStudent(student.id),
      builder: (context, snapshot) {
        final double fraisEcole =
            double.tryParse(_fraisEcoleController.text) ?? 0;
        final double fraisCotisation =
            double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
        final double montantMax = fraisEcole + fraisCotisation;
        final double totalPaid = snapshot.data ?? 0;
        final bool isPaid = montantMax > 0 && totalPaid >= montantMax;
        final theme = Theme.of(context);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: selectionMode && selected
                ? theme.primaryColor.withOpacity(0.06)
                : theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            onTap: selectionMode
                ? () {
                    _toggleSelectedStudent(student.id);
                    debugPrint(
                      '[ClassDetailsPage] toggle selected (tap): id=${student.id} selected=${_selectedStudentIds.contains(student.id)}',
                    );
                  }
                : null,
            leading: selectionMode
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: selected,
                        onChanged: (_) => _toggleSelectedStudent(student.id),
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(
                          0xFF667EEA,
                        ).withOpacity(0.1),
                        child: Text(
                          student.firstName.isNotEmpty
                              ? student.firstName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF667EEA),
                          ),
                        ),
                      ),
                    ],
                  )
                : CircleAvatar(
                    radius: 25,
                    backgroundColor: const Color(0xFF667EEA).withOpacity(0.1),
                    child: Text(
                      student.firstName.isNotEmpty
                          ? student.firstName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF667EEA),
                      ),
                    ),
                  ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    _displayStudentName(student),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: student.isDeleted
                        ? Colors.grey
                        : (isPaid ? Colors.green : Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    student.isDeleted
                        ? 'Corbeille'
                        : (isPaid ? 'Payé' : 'En attente'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ID: ${student.id} • ${student.gender == 'M' ? 'Garçon' : 'Fille'}',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ),
            ),
            trailing: selectionMode
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModernActionButton(
                        icon: Icons.person_rounded,
                        color: const Color(0xFF3182CE),
                        tooltip: 'Détails',
                        onPressed: () => _showStudentDetailsDialog(student),
                        semanticLabel: 'Voir détails',
                      ),
                      const SizedBox(width: 8),
                      if (!student.isDeleted) ...[
                        _buildModernActionButton(
                          icon: Icons.account_balance_wallet_rounded,
                          color: const Color(0xFF38A169),
                          tooltip: 'Paiement',
                          onPressed: () => _showPaymentDialog(student),
                          semanticLabel: 'Ajouter paiement',
                        ),
                        const SizedBox(width: 8),
                        _buildModernActionButton(
                          icon: Icons.edit_rounded,
                          color: const Color(0xFF667EEA),
                          tooltip: 'Modifier',
                          onPressed: () => _editStudent(student),
                          semanticLabel: 'Modifier élève',
                        ),
                        const SizedBox(width: 8),
                        _buildModernActionButton(
                          icon: Icons.delete_rounded,
                          color: const Color(0xFFE53E3E),
                          tooltip: 'Supprimer',
                          onPressed: () => _deleteStudent(student),
                          semanticLabel: 'Supprimer élève',
                        ),
                      ] else ...[
                        _buildModernActionButton(
                          icon: Icons.restore,
                          color: const Color(0xFF10B981),
                          tooltip: 'Restaurer',
                          onPressed: () => _restoreStudent(student),
                          semanticLabel: 'Restaurer élève',
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildModernActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    VoidCallback? onPressed,
    required String semanticLabel,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(onPressed != null ? 0.1 : 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color.withOpacity(onPressed != null ? 1.0 : 0.5),
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.school_rounded,
              size: 40,
              color: Color(0xFF667EEA),
              semanticLabel: 'Aucun élève',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun élève dans cette classe',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.titleMedium!.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Commencez par ajouter des élèves à cette classe',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium!.color?.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Student>> _getFilteredAndSortedStudentsAsync() async {
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    List<Student> filtered = [];
    for (final student in _students) {
      if (_visibilityFilter == 'active' && student.isDeleted) continue;
      if (_visibilityFilter == 'deleted' && !student.isDeleted) continue;
      final totalPaid = await _dbService.getTotalPaidForStudent(student.id);
      final isPaid = montantMax > 0 && totalPaid >= montantMax;
      final status = isPaid ? 'Payé' : 'En attente';
      final query = _studentSearchQuery.toLowerCase();
      final matchSearch =
          _studentSearchQuery.isEmpty ||
          _displayStudentName(student).toLowerCase().contains(query) ||
          student.name.toLowerCase().contains(query) ||
          student.id.toLowerCase().contains(query) ||
          (student.gender == 'M' && 'garçon'.contains(query)) ||
          (student.gender == 'F' && 'fille'.contains(query));
      if (_studentStatusFilter == 'Tous' && matchSearch) {
        filtered.add(student);
      } else if (_studentStatusFilter == status && matchSearch) {
        filtered.add(student);
      }
    }
    filtered.sort((a, b) {
      int compare;
      if (_sortBy == 'name') {
        compare = _compareStudentsByName(a, b);
      } else {
        compare = a.id.compareTo(b.id);
      }
      return _sortAscending ? compare : -compare;
    });
    return filtered;
  }

  Widget _buildSortControls() {
    return Row(
      children: [
        Text(
          'Trier par : ',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).textTheme.bodyMedium!.color,
          ),
        ),
        DropdownButton<String>(
          value: _sortBy,
          items: const [
            DropdownMenuItem(value: 'name', child: Text('Nom')),
            DropdownMenuItem(value: 'id', child: Text('ID')),
          ],
          onChanged: (value) => setState(() => _sortBy = value!),
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).textTheme.bodyLarge!.color,
          ),
          underline: const SizedBox(),
        ),
        IconButton(
          icon: Icon(
            _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 20,
            color: Theme.of(context).textTheme.bodyMedium!.color,
          ),
          onPressed: () => setState(() => _sortAscending = !_sortAscending),
          tooltip: _sortAscending ? 'Tri ascendant' : 'Tri descendant',
        ),
      ],
    );
  }

  void _showStudentDetailsDialog(Student student) async {
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    final totalPaid = await _dbService.getTotalPaidForStudent(student.id);
    final reste = montantMax - totalPaid;
    final status = (montantMax > 0 && totalPaid >= montantMax)
        ? 'Payé'
        : 'En attente';
    final db = await _dbService.database;
    final List<Map<String, dynamic>> allMaps = await db.query(
      'payments',
      where: 'studentId = ?',
      whereArgs: [student.id],
      orderBy: 'date DESC',
    );
    final payments = allMaps.map((m) => Payment.fromMap(m)).toList();
    showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: 'Détails de l\'élève',
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (student.photoPath != null && student.photoPath!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(student.photoPath!),
                      key: ValueKey(student.photoPath!),
                      width: double.infinity,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Center(child: Icon(Icons.error, color: Colors.red)),
                    ),
                  ),
                ),
              _buildDetailRow('Nom complet', _displayStudentName(student)),
              _buildDetailRow('ID', student.id),
              if (student.matricule != null && student.matricule!.isNotEmpty)
                _buildDetailRow('Matricule', student.matricule!),
              _buildDetailRow('Année scolaire', student.academicYear),
              _buildDetailRow(
                'Date d\'inscription',
                _formatIsoToDisplay(student.enrollmentDate),
              ),
              _buildDetailRow(
                'Date de naissance',
                '${_formatIsoToDisplay(student.dateOfBirth)} • ${_calculateAgeFromIso(student.dateOfBirth)}',
              ),
              _buildDetailRow(
                'Lieu de naissance',
                student.placeOfBirth ?? 'Non renseigné',
              ),
              _buildDetailRow('Statut', student.status),
              _buildDetailRow(
                'Sexe',
                student.gender == 'M' ? 'Garçon' : 'Fille',
              ),
              _buildDetailRow('Classe', student.className),
              _buildDetailRow('Adresse', student.address),
              _buildDetailRow('Contact', student.contactNumber),
              _buildDetailRow('Email', student.email),
              _buildDetailRow('Contact d\'urgence', student.emergencyContact),
              _buildDetailRow('Tuteur', student.guardianName),
              _buildDetailRow('Contact tuteur', student.guardianContact),
              if (student.medicalInfo != null &&
                  student.medicalInfo!.isNotEmpty)
                _buildDetailRow('Infos médicales', student.medicalInfo!),
              const SizedBox(height: 16),
              Divider(),
              Text(
                'Paiement',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Montant dû',
                '${montantMax.toStringAsFixed(2)} FCFA',
              ),
              _buildDetailRow(
                'Déjà payé',
                '${totalPaid.toStringAsFixed(2)} FCFA',
              ),
              _buildDetailRow(
                'Reste à payer',
                reste <= 0 ? 'Payé' : '${reste.toStringAsFixed(2)} FCFA',
              ),
              _buildDetailRow('Statut', status),
              const SizedBox(height: 8),
              if (payments.isNotEmpty) ...[
                Text(
                  'Historique des paiements',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...payments.map(
                  (p) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: p.isCancelled ? Colors.grey.shade200 : null,
                    child: ListTile(
                      leading: Icon(
                        Icons.attach_money,
                        color: p.isCancelled ? Colors.grey : Colors.green,
                      ),
                      title: Row(
                        children: [
                          Text(
                            '${p.amount.toStringAsFixed(2)} FCFA',
                            style: TextStyle(
                              color: p.isCancelled ? Colors.grey : null,
                              decoration: p.isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (p.isCancelled)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '(Annulé)',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p.date.replaceFirst('T', ' ').substring(0, 16)}',
                            style: TextStyle(
                              color: p.isCancelled ? Colors.grey : null,
                            ),
                          ),
                          if ((p.recordedBy ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Enregistré par : ${p.recordedBy}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (p.comment != null && p.comment!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Commentaire : ${p.comment!}',
                                style: TextStyle(
                                  color: Colors.deepPurple,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          if (p.isCancelled && (p.cancelBy ?? '').isNotEmpty)
                            const SizedBox(height: 2),
                          if (p.isCancelled && (p.cancelBy ?? '').isNotEmpty)
                            Text(
                              'Annulé par ${p.cancelBy}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          if (p.isCancelled && p.cancelledAt != null)
                            Text(
                              'Annulé le ${p.cancelledAt!.replaceFirst('T', ' ').substring(0, 16)}',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                        ],
                      ),
                      trailing: p.isCancelled
                          ? Icon(Icons.block, color: Colors.grey)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.print, color: Colors.blue),
                                  tooltip: 'Imprimer le reçu',
                                  onPressed: () => _printReceipt(p, student),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Annuler ce paiement',
                                  onPressed: () async {
                                    final motifCtrl = TextEditingController();
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => CustomDialog(
                                        title: 'Motif d\'annulation',
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Veuillez saisir un motif pour annuler ce paiement. Cette action est irréversible.',
                                            ),
                                            const SizedBox(height: 12),
                                            CustomFormField(
                                              controller: motifCtrl,
                                              labelText: 'Motif',
                                              hintText:
                                                  'Ex: erreur de saisie, remboursement, etc.',
                                              isTextArea: true,
                                              validator: (v) =>
                                                  (v == null ||
                                                      v.trim().isEmpty)
                                                  ? 'Motif requis'
                                                  : null,
                                            ),
                                          ],
                                        ),
                                        fields: const [],
                                        onSubmit: () =>
                                            Navigator.of(context).pop(true),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              context,
                                            ).pop(false),
                                            child: const Text('Annuler'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
                                            child: const Text('Confirmer'),
                                          ),
                                        ],
                                      ),
                                    );
                                    final reason = motifCtrl.text.trim();
                                    if (ok == true && reason.isNotEmpty) {
                                      // Fetch current user display name if available
                                      String? by;
                                      try {
                                        final user = await AuthService.instance
                                            .getCurrentUser();
                                        by =
                                            user?.displayName ?? user?.username;
                                      } catch (_) {}
                                      await _dbService.cancelPaymentWithReason(
                                        p.id!,
                                        reason,
                                        by: by,
                                      );
                                      Navigator.of(context).pop();
                                      _showModernSnackBar('Paiement annulé');
                                      setState(() {});
                                    } else if (ok == true && reason.isEmpty) {
                                      _showModernSnackBar(
                                        'Motif obligatoire pour annuler.',
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ] else ...[
                Text('Aucun paiement enregistré.'),
              ],
            ],
          ),
        ),
        fields: const [],
        onSubmit: () => Navigator.of(context).pop(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(Student student) async {
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    if (montantMax == 0) {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Alerte',
          content: const Text(
            'Veuillez renseigner un montant de frais d\'école ou de cotisation dans la fiche classe avant d\'enregistrer un paiement.',
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final montantController = TextEditingController(text: '0');
    final commentController = TextEditingController();
    final totalPaid = await _dbService.getTotalPaidForStudent(student.id);
    final reste = montantMax - totalPaid;
    if (reste <= 0) {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Alerte',
          content: const Text('L\'élève a déjà tout payé pour cette classe.'),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    void showMontantDepasseAlerte() {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Montant trop élevé',
          content: Text(
            'Le montant saisi dépasse le solde dû (${reste.toStringAsFixed(2)} FCFA).',
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: 'Paiement pour ${_displayStudentName(student)}',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Montant maximum autorisé : ${reste.toStringAsFixed(2)} FCFA',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Déjà payé : ${totalPaid.toStringAsFixed(2)} FCFA'),
            const SizedBox(height: 12),
            CustomFormField(
              controller: montantController,
              labelText: 'Montant à payer',
              hintText: 'Saisir le montant',
              suffixIcon: Icons.attach_money,
              validator: (value) {
                final val = double.tryParse(value ?? '');
                if (val == null || val < 0) return 'Montant invalide';
                if (val > reste) return 'Ne peut excéder $reste';
                return null;
              },
            ),
            const SizedBox(height: 12),
            CustomFormField(
              controller: commentController,
              labelText: 'Commentaire (optionnel)',
              hintText: 'Ex: acompte, solde, etc.',
              suffixIcon: Icons.comment,
            ),
          ],
        ),
        fields: const [],
        onSubmit: () async {
          final val = double.tryParse(montantController.text);
          if (val == null || val < 0) return;
          if (val > reste) {
            showMontantDepasseAlerte();
            return;
          }
          final user = await AuthService.instance.getCurrentUser();
          final payment = Payment(
            studentId: student.id,
            className: student.className,
            classAcademicYear: student.academicYear,
            amount: val,
            date: DateTime.now().toIso8601String(),
            comment: commentController.text.isNotEmpty
                ? commentController.text
                : null,
            recordedBy: user?.displayName ?? user?.username,
          );
          await _dbService.insertPayment(payment);
          Navigator.of(context).pop();
          _showModernSnackBar('Paiement enregistré !');
          setState(() {});
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(montantController.text);
              if (val == null || val < 0) return;
              if (val > reste) {
                showMontantDepasseAlerte();
                return;
              }
              final user = await AuthService.instance.getCurrentUser();
              final payment = Payment(
                studentId: student.id,
                className: student.className,
                classAcademicYear: student.academicYear,
                amount: val,
                date: DateTime.now().toIso8601String(),
                comment: commentController.text.isNotEmpty
                    ? commentController.text
                    : null,
                recordedBy: user?.displayName ?? user?.username,
              );
              await _dbService.insertPayment(payment);
              Navigator.of(context).pop();
              _showModernSnackBar('Paiement enregistré !');
              setState(() {});
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _printReceipt(Payment p, Student student) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'REÇU DE PAIEMENT',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Élève : ${_displayStudentName(student)}',
                style: pw.TextStyle(fontSize: 16),
              ),
              pw.Text(
                'Classe : ${student.className}',
                style: pw.TextStyle(fontSize: 16),
              ),
              pw.Text('ID : ${student.id}', style: pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 12),
              pw.Text(
                'Montant payé : ${p.amount.toStringAsFixed(2)} FCFA',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Date : ${p.date.replaceFirst('T', ' ').substring(0, 16)}',
                style: pw.TextStyle(fontSize: 14),
              ),
              if (p.comment != null && p.comment!.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    'Commentaire : ${p.comment!}',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
              if (p.isCancelled)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    'ANNULÉ le ${p.cancelledAt?.replaceFirst('T', ' ').substring(0, 16) ?? ''}',
                    style: pw.TextStyle(
                      color: PdfColor.fromInt(0xFFFF0000),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(height: 24),
              pw.Text(
                'Signature : ___________________________',
                style: pw.TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Future<void> _reloadStudentsForCurrentClass() async {
    final className = _nameController.text.trim();
    final year = _yearController.text.trim();
    final includeDeleted = _visibilityFilter == 'all';
    final onlyDeleted = _visibilityFilter == 'deleted';
    final refreshed = await _dbService.getStudents(
      className: className,
      academicYear: year,
      includeDeleted: includeDeleted,
      onlyDeleted: onlyDeleted,
    );
    if (!mounted) return;
    setState(() => _students = refreshed);
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label : ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomDialog(
      title: AppStrings.classDetailsTitle,
      content: SizedBox(
        width: MediaQuery.of(context).size.width > 1000
            ? 1000
            : MediaQuery.of(context).size.width * 0.95,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Boutons d'export
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _exportGradesTemplateExcel,
                              icon: const Icon(
                                Icons.table_view,
                                color: Colors.white,
                              ),
                              label: const Text('Modèle de notes (Excel)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0EA5E9),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _showSubjectTemplateDialog,
                              icon: const Icon(
                                Icons.view_list,
                                color: Colors.white,
                              ),
                              label: const Text('Relevé de notes par matière'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Élèves',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _exportStudentsPdf,
                              icon: const Icon(
                                Icons.picture_as_pdf,
                                color: Colors.white,
                              ),
                              label: const Text('Liste élèves (PDF)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _exportStudentsExcel,
                              icon: const Icon(
                                Icons.grid_on,
                                color: Colors.white,
                              ),
                              label: const Text('Liste élèves (Excel)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _exportStudentsWord,
                              icon: const Icon(
                                Icons.description,
                                color: Colors.white,
                              ),
                              label: const Text('Liste élèves (Word)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _exportStudentProfilesPdf,
                              icon: const Icon(
                                Icons.person,
                                color: Colors.white,
                              ),
                              label: const Text('Fiches élèves (PDF)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B5CF6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Cartes',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _exportStudentIdCards,
                              icon: const Icon(
                                Icons.badge,
                                color: Colors.white,
                              ),
                              label: const Text('Cartes scolaires (PDF)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C3AED),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Actions',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (!SafeModeService.instance
                                    .isActionAllowed()) {
                                  _showModernSnackBar(
                                    SafeModeService.instance
                                        .getBlockedActionMessage(),
                                    isError: true,
                                  );
                                  return;
                                }
                                final didApply = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => ReEnrollmentDialog(
                                    sourceClass: Class(
                                      name: _nameController.text.trim(),
                                      academicYear: _yearController.text.trim(),
                                      level: _selectedLevel,
                                      titulaire: _titulaireController.text
                                          .trim(),
                                      fraisEcole: double.tryParse(
                                        _fraisEcoleController.text,
                                      ),
                                      fraisCotisationParallele: double.tryParse(
                                        _fraisCotisationParalleleController
                                            .text,
                                      ),
                                      seuilFelicitations:
                                          double.tryParse(
                                            _seuilFelicitationsController.text,
                                          ) ??
                                          16.0,
                                      seuilEncouragements:
                                          double.tryParse(
                                            _seuilEncouragementsController.text,
                                          ) ??
                                          14.0,
                                      seuilAdmission:
                                          double.tryParse(
                                            _seuilAdmissionController.text,
                                          ) ??
                                          12.0,
                                      seuilAvertissement:
                                          double.tryParse(
                                            _seuilAvertissementController.text,
                                          ) ??
                                          10.0,
                                      seuilConditions:
                                          double.tryParse(
                                            _seuilConditionsController.text,
                                          ) ??
                                          8.0,
                                      seuilRedoublement:
                                          double.tryParse(
                                            _seuilRedoublementController.text,
                                          ) ??
                                          8.0,
                                    ),
                                    students: _students,
                                  ),
                                );
                                if (didApply == true) {
                                  await _reloadStudentsForCurrentClass();
                                }
                              },
                              icon: const Icon(
                                Icons.how_to_reg,
                                color: Colors.white,
                              ),
                              label: const Text('Réinscription'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildModernSectionTitle(
                      'Informations sur la classe',
                      Icons.class_rounded,
                    ),
                    _buildModernFormCard([
                      CustomFormField(
                        controller: _nameController,
                        labelText: AppStrings.classNameDialog,
                        hintText: 'Entrez le nom de la classe',
                        validator: (value) =>
                            value!.isEmpty ? AppStrings.required : null,
                      ),
                      CustomFormField(
                        controller: _yearController,
                        labelText: AppStrings.academicYearDialog,
                        hintText: "Entrez l'année scolaire",
                        validator: (value) =>
                            value!.isEmpty ? AppStrings.required : null,
                      ),
                      CustomFormField(
                        controller: _titulaireController,
                        labelText: 'Titulaire',
                        hintText: 'Nom du titulaire de la classe',
                      ),
                      CustomFormField(
                        controller: _fraisEcoleController,
                        labelText: "Frais d'école",
                        hintText: "Montant des frais d'école",
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              double.tryParse(value) == null) {
                            return 'Veuillez entrer un montant valide';
                          }
                          return null;
                        },
                      ),
                      CustomFormField(
                        controller: _fraisCotisationParalleleController,
                        labelText: 'Frais de cotisation parallèle',
                        hintText: 'Montant des frais de cotisation parallèle',
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              double.tryParse(value) == null) {
                            return 'Veuillez entrer un montant valide';
                          }
                          return null;
                        },
                      ),
                    ]),
                    const SizedBox(height: 32),
                    _buildModernSectionTitle(
                      'Élèves de la classe',
                      Icons.people_rounded,
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Ajouter un élève'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3182CE),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            final GlobalKey<StudentRegistrationFormState>
                            studentFormKey =
                                GlobalKey<StudentRegistrationFormState>();
                            await showDialog(
                              context: context,
                              builder: (context) => CustomDialog(
                                title: 'Ajouter un élève',
                                content: StudentRegistrationForm(
                                  key: studentFormKey,
                                  className: _nameController.text, // pré-rempli
                                  classFieldReadOnly:
                                      true, // à gérer dans le form
                                  onSubmit: () async {
                                    await _reloadStudentsForCurrentClass();
                                    _selectedStudentIds.clear();
                                    _selectionMode = false;
                                    // Ne pas fermer le dialog, juste vider le formulaire
                                    studentFormKey.currentState?.resetForm();
                                    _showModernSnackBar(
                                      'Élève ajouté avec succès !',
                                    );
                                  },
                                ),
                                fields: const [],
                                onSubmit: () {
                                  studentFormKey.currentState?.submitForm();
                                },
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('Fermer'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => studentFormKey.currentState
                                        ?.submitForm(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Ajouter'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: _buildModernSearchField()),
                        const SizedBox(width: 16),
                        _buildSortControls(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String>(
                          value: _visibilityFilter,
                          items: const [
                            DropdownMenuItem(
                              value: 'active',
                              child: Text('Actifs'),
                            ),
                            DropdownMenuItem(
                              value: 'deleted',
                              child: Text('Corbeille'),
                            ),
                            DropdownMenuItem(value: 'all', child: Text('Tous')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            debugPrint(
                              '[ClassDetailsPage] visibility filter changed: $v',
                            );
                            setState(() {
                              _visibilityFilter = v;
                              _selectionMode = false;
                              _selectedStudentIds.clear();
                            });
                            await _reloadStudentsForCurrentClass();
                          },
                        ),
                        TextButton.icon(
                          onPressed: () => _setSelectionMode(!_selectionMode),
                          icon: Icon(
                            _selectionMode ? Icons.close : Icons.checklist,
                          ),
                          label: Text(_selectionMode ? 'Quitter' : 'Sélection'),
                        ),
                        if (_selectionMode)
                          TextButton(
                            onPressed: _students.isEmpty
                                ? null
                                : () async {
                                    await _selectAllFilteredStudents();
                                    debugPrint(
                                      '[ClassDetailsPage] select all: count=${_selectedStudentIds.length}',
                                    );
                                  },
                            child: const Text('Tout sélectionner'),
                          ),
                        if (_selectionMode)
                          Text(
                            '${_selectedStudentIds.length} sélectionné(s)',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color?.withOpacity(0.8),
                            ),
                          ),
                      ],
                    ),
                    if (_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _selectedStudentIds.isEmpty
                                  ? null
                                  : _bulkChangeClassYearSelected,
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Classe/Année'),
                            ),
                            ElevatedButton.icon(
                              onPressed: _selectedStudentIds.isEmpty
                                  ? null
                                  : _exportSelectedStudentIdCards,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Cartes scolaires (PDF)'),
                            ),
                            ElevatedButton.icon(
                              onPressed: _selectedStudentIds.isEmpty
                                  ? null
                                  : _bulkDeleteSelectedStudents,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Supprimer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            if (_visibilityFilter == 'deleted')
                              ElevatedButton.icon(
                                onPressed: _selectedStudentIds.isEmpty
                                    ? null
                                    : _bulkRestoreSelectedStudents,
                                icon: const Icon(Icons.restore),
                                label: const Text('Restaurer'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    const SizedBox(height: 20),
                    FutureBuilder<List<Student>>(
                      future: _getFilteredAndSortedStudentsAsync(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final filteredStudents = snapshot.data!;
                        if (filteredStudents.isEmpty) {
                          return _buildEmptyState();
                        }
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredStudents.length,
                            itemBuilder: (context, index) {
                              final student = filteredStudents[index];
                              return _buildModernStudentCard(
                                student,
                                selectionMode: _selectionMode,
                                selected: _selectedStudentIds.contains(
                                  student.id,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildModernSectionTitle(
                      'Bulletins archivés',
                      Icons.picture_as_pdf_rounded,
                    ),
                    FutureBuilder<_ArchivedBulletinsView>(
                      future: _loadArchivedBulletinsView(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final view = snapshot.data!;
                        if (view.reportCards.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Aucun bulletin archivé pour cette classe/année.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }
                        final terms =
                            view.reportCards
                                .map((e) => (e['term'] ?? '').toString())
                                .where((e) => e.trim().isNotEmpty)
                                .toSet()
                                .toList()
                              ..sort();
                        final selectedTerm =
                            (_selectedArchivedBulletinTerm != null &&
                                terms.contains(_selectedArchivedBulletinTerm))
                            ? _selectedArchivedBulletinTerm!
                            : terms.first;
                        final forTerm =
                            view.reportCards
                                .where(
                                  (e) =>
                                      (e['term'] ?? '').toString() ==
                                      selectedTerm,
                                )
                                .toList()
                              ..sort((a, b) {
                                final avgA =
                                    (a['moyenne_generale'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final avgB =
                                    (b['moyenne_generale'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                return avgB.compareTo(avgA);
                              });

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  DropdownButton<String>(
                                    value: selectedTerm,
                                    items: terms
                                        .map(
                                          (t) => DropdownMenuItem(
                                            value: t,
                                            child: Text(t),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(
                                        () => _selectedArchivedBulletinTerm = v,
                                      );
                                    },
                                  ),
                                  Text(
                                    '${forTerm.length} bulletin(s)',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color
                                          ?.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: forTerm.isEmpty
                                        ? null
                                        : () => _exportArchivedBulletinsZip(
                                            term: selectedTerm,
                                            reportCardsForTerm: forTerm,
                                            variant: 'standard',
                                          ),
                                    icon: const Icon(Icons.archive_outlined),
                                    label: const Text('Exporter ZIP'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: forTerm.isEmpty
                                        ? null
                                        : () => _exportArchivedBulletinsZip(
                                            term: selectedTerm,
                                            reportCardsForTerm: forTerm,
                                            variant: 'compact',
                                          ),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                    label: const Text('Exporter ZIP compact'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: forTerm.isEmpty
                                        ? null
                                        : () => _exportArchivedBulletinsZip(
                                            term: selectedTerm,
                                            reportCardsForTerm: forTerm,
                                            variant: 'ultra',
                                          ),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                    label: const Text(
                                      'Exporter ZIP ultra compact',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: forTerm.isEmpty
                                        ? null
                                        : () => _exportArchivedBulletinsZip(
                                            term: selectedTerm,
                                            reportCardsForTerm: forTerm,
                                            variant: 'custom',
                                          ),
                                    icon: const Icon(Icons.settings),
                                    label: const Text('Exporter ZIP custom'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: forTerm.isEmpty
                                        ? null
                                        : () =>
                                              _exportClassDeliberationMinutesPdf(
                                                term: selectedTerm,
                                                reportCardsForTerm: forTerm,
                                              ),
                                    icon: const Icon(
                                      Icons.description_outlined,
                                    ),
                                    label: const Text('PV de délibération'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                      foregroundColor: Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Élève')),
                                    DataColumn(label: Text('Moyenne')),
                                    DataColumn(label: Text('Mention')),
                                    DataColumn(label: Text('Décision (arch.)')),
                                    DataColumn(label: Text('Décision (sim.)')),
                                  ],
                                  rows: forTerm.map((rc) {
                                    final studentId = (rc['studentId'] ?? '')
                                        .toString();
                                    final student =
                                        view.studentsById[studentId];
                                    final avg =
                                        rc['moyenne_generale']?.toDouble() ??
                                        0.0;
                                    final mention = (rc['mention'] ?? '')
                                        .toString();
                                    final decision = (rc['decision'] ?? '')
                                        .toString();
                                    final proposed =
                                        _proposedDecisionForAverage(avg);
                                    final name = student != null
                                        ? _displayStudentName(student)
                                        : studentId;
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          Row(
                                            children: [
                                              Flexible(child: Text(name)),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                tooltip: 'Télécharger PDF',
                                                icon: const Icon(
                                                  Icons.picture_as_pdf,
                                                ),
                                                onPressed: student == null
                                                    ? null
                                                    : () async {
                                                        if (!SafeModeService
                                                            .instance
                                                            .isActionAllowed()) {
                                                          _showModernSnackBar(
                                                            SafeModeService
                                                                .instance
                                                                .getBlockedActionMessage(),
                                                            isError: true,
                                                          );
                                                          return;
                                                        }
                                                        final directoryPath =
                                                            await FilePicker
                                                                .platform
                                                                .getDirectoryPath(
                                                                  dialogTitle:
                                                                      'Choisir le dossier de sauvegarde',
                                                                );
                                                        if (directoryPath ==
                                                            null) {
                                                          return;
                                                        }
                                                        final pdfBytes =
                                                            await _generateArchivedReportCardPdf(
                                                              student: student,
                                                              reportCard: rc,
                                                            );
                                                        final safeName = student
                                                            .name
                                                            .replaceAll(
                                                              ' ',
                                                              '_',
                                                            );
                                                        final fileName =
                                                            'Bulletin_${safeName}_${selectedTerm}_${rc['academicYear'] ?? ''}.pdf';
                                                        final file = File(
                                                          '$directoryPath/$fileName',
                                                        );
                                                        await file.writeAsBytes(
                                                          pdfBytes,
                                                          flush: true,
                                                        );
                                                        try {
                                                          await OpenFile.open(
                                                            file.path,
                                                          );
                                                        } catch (_) {}
                                                      },
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Télécharger PDF compact',
                                                icon: const Icon(
                                                  Icons.picture_as_pdf_outlined,
                                                ),
                                                onPressed: student == null
                                                    ? null
                                                    : () async {
                                                        if (!SafeModeService
                                                            .instance
                                                            .isActionAllowed()) {
                                                          _showModernSnackBar(
                                                            SafeModeService
                                                                .instance
                                                                .getBlockedActionMessage(),
                                                            isError: true,
                                                          );
                                                          return;
                                                        }
                                                        final directoryPath =
                                                            await FilePicker
                                                                .platform
                                                                .getDirectoryPath(
                                                                  dialogTitle:
                                                                      'Choisir le dossier de sauvegarde',
                                                                );
                                                        if (directoryPath ==
                                                            null) {
                                                          return;
                                                        }
                                                        final pdfBytes =
                                                            await _generateArchivedReportCardPdfCompact(
                                                              student: student,
                                                              reportCard: rc,
                                                            );
                                                        final safeName = student
                                                            .name
                                                            .replaceAll(
                                                              ' ',
                                                              '_',
                                                            );
                                                        final fileName =
                                                            'Bulletin_${safeName}_${selectedTerm}_${rc['academicYear'] ?? ''}_compact.pdf';
                                                        final file = File(
                                                          '$directoryPath/$fileName',
                                                        );
                                                        await file.writeAsBytes(
                                                          pdfBytes,
                                                          flush: true,
                                                        );
                                                        try {
                                                          await OpenFile.open(
                                                            file.path,
                                                          );
                                                        } catch (_) {}
                                                      },
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Télécharger PDF ultra compact',
                                                icon: const Icon(
                                                  Icons.picture_as_pdf_outlined,
                                                ),
                                                onPressed: student == null
                                                    ? null
                                                    : () async {
                                                        if (!SafeModeService
                                                            .instance
                                                            .isActionAllowed()) {
                                                          _showModernSnackBar(
                                                            SafeModeService
                                                                .instance
                                                                .getBlockedActionMessage(),
                                                            isError: true,
                                                          );
                                                          return;
                                                        }
                                                        final directoryPath =
                                                            await FilePicker
                                                                .platform
                                                                .getDirectoryPath(
                                                                  dialogTitle:
                                                                      'Choisir le dossier de sauvegarde',
                                                                );
                                                        if (directoryPath ==
                                                            null) {
                                                          return;
                                                        }
                                                        final pdfBytes =
                                                            await _generateArchivedReportCardPdfUltraCompact(
                                                              student: student,
                                                              reportCard: rc,
                                                            );
                                                        final safeName = student
                                                            .name
                                                            .replaceAll(
                                                              ' ',
                                                              '_',
                                                            );
                                                        final fileName =
                                                            'Bulletin_${safeName}_${selectedTerm}_${rc['academicYear'] ?? ''}_ultra_compact.pdf';
                                                        final file = File(
                                                          '$directoryPath/$fileName',
                                                        );
                                                        await file.writeAsBytes(
                                                          pdfBytes,
                                                          flush: true,
                                                        );
                                                        try {
                                                          await OpenFile.open(
                                                            file.path,
                                                          );
                                                        } catch (_) {}
                                                      },
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Télécharger PDF custom',
                                                icon: const Icon(
                                                  Icons.settings,
                                                ),
                                                onPressed: student == null
                                                    ? null
                                                    : () async {
                                                        if (!SafeModeService
                                                            .instance
                                                            .isActionAllowed()) {
                                                          _showModernSnackBar(
                                                            SafeModeService
                                                                .instance
                                                                .getBlockedActionMessage(),
                                                            isError: true,
                                                          );
                                                          return;
                                                        }
                                                        // Demander l'orientation
                                                        final orientation =
                                                            await showDialog<
                                                              String
                                                            >(
                                                              context: context,
                                                              builder: (context) => AlertDialog(
                                                                title: const Text(
                                                                  'Orientation du PDF',
                                                                ),
                                                                content: Column(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    ListTile(
                                                                      title: const Text(
                                                                        'Portrait',
                                                                      ),
                                                                      leading:
                                                                          const Icon(
                                                                            Icons.stay_current_portrait,
                                                                          ),
                                                                      onTap: () =>
                                                                          Navigator.of(
                                                                            context,
                                                                          ).pop(
                                                                            'portrait',
                                                                          ),
                                                                    ),
                                                                    ListTile(
                                                                      title: const Text(
                                                                        'Paysage',
                                                                      ),
                                                                      leading:
                                                                          const Icon(
                                                                            Icons.stay_current_landscape,
                                                                          ),
                                                                      onTap: () =>
                                                                          Navigator.of(
                                                                            context,
                                                                          ).pop(
                                                                            'landscape',
                                                                          ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ) ??
                                                            'portrait';
                                                        final bool isLandscape =
                                                            orientation ==
                                                            'landscape';

                                                        // Demander le format
                                                        final formatChoice =
                                                            await showDialog<
                                                              String
                                                            >(
                                                              context: context,
                                                              builder: (context) => AlertDialog(
                                                                title: const Text(
                                                                  'Format du PDF',
                                                                ),
                                                                content: Column(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    ListTile(
                                                                      title: const Text(
                                                                        'Format long (A4 standard)',
                                                                      ),
                                                                      subtitle:
                                                                          const Text(
                                                                            'Dimensions standard A4',
                                                                          ),
                                                                      leading:
                                                                          const Icon(
                                                                            Icons.description,
                                                                          ),
                                                                      onTap: () =>
                                                                          Navigator.of(
                                                                            context,
                                                                          ).pop(
                                                                            'long',
                                                                          ),
                                                                    ),
                                                                    ListTile(
                                                                      title: const Text(
                                                                        'Format court (compact)',
                                                                      ),
                                                                      subtitle:
                                                                          const Text(
                                                                            'Dimensions réduites',
                                                                          ),
                                                                      leading:
                                                                          const Icon(
                                                                            Icons.view_compact,
                                                                          ),
                                                                      onTap: () =>
                                                                          Navigator.of(
                                                                            context,
                                                                          ).pop(
                                                                            'short',
                                                                          ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ) ??
                                                            'long';
                                                        final bool
                                                        useLongFormat =
                                                            formatChoice ==
                                                            'long';

                                                        final directoryPath =
                                                            await FilePicker
                                                                .platform
                                                                .getDirectoryPath(
                                                                  dialogTitle:
                                                                      'Choisir le dossier de sauvegarde',
                                                                );
                                                        if (directoryPath ==
                                                            null) {
                                                          return;
                                                        }
                                                        final pdfBytes =
                                                            await _generateArchivedReportCardPdfCustom(
                                                              student: student,
                                                              reportCard: rc,
                                                              isLandscape:
                                                                  isLandscape,
                                                              useLongFormat:
                                                                  useLongFormat,
                                                            );
                                                        final safeName = student
                                                            .name
                                                            .replaceAll(
                                                              ' ',
                                                              '_',
                                                            );
                                                        final fileName =
                                                            'Bulletin_${safeName}_${selectedTerm}_${rc['academicYear'] ?? ''}_custom.pdf';
                                                        final file = File(
                                                          '$directoryPath/$fileName',
                                                        );
                                                        await file.writeAsBytes(
                                                          pdfBytes,
                                                          flush: true,
                                                        );
                                                        try {
                                                          await OpenFile.open(
                                                            file.path,
                                                          );
                                                        } catch (_) {}
                                                      },
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(Text(avg.toStringAsFixed(2))),
                                        DataCell(Text(mention)),
                                        DataCell(Text(decision)),
                                        DataCell(Text(proposed)),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildModernSectionTitle(
                      'Matières de la classe',
                      Icons.book,
                    ),
                    FutureBuilder<List<Course>>(
                      future: _dbService.getCoursesForClass(
                        _nameController.text,
                        _yearController.text,
                      ),
                      builder: (context, snapshot) {
                        final List<Course> classCourses = snapshot.data ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (classCourses.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  'Aucune matière associée à cette classe.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ...classCourses.map(
                              (course) => ListTile(
                                title: Text(course.name),
                                subtitle:
                                    course.description != null &&
                                        course.description!.isNotEmpty
                                    ? Text(course.description!)
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        color: Colors.blue,
                                      ),
                                      tooltip: 'Modifier cette matière',
                                      onPressed: () async {
                                        final nameController =
                                            TextEditingController(
                                              text: course.name,
                                            );
                                        final descController =
                                            TextEditingController(
                                              text: course.description ?? '',
                                            );
                                        await showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Modifier la matière'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                TextField(
                                                  controller: nameController,
                                                  decoration: InputDecoration(
                                                    labelText: 'Nom',
                                                  ),
                                                ),
                                                TextField(
                                                  controller: descController,
                                                  decoration: InputDecoration(
                                                    labelText: 'Description',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                                child: Text('Annuler'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  final newName = nameController
                                                      .text
                                                      .trim();
                                                  final newDesc = descController
                                                      .text
                                                      .trim();
                                                  if (newName.isEmpty) return;
                                                  final updated = Course(
                                                    id: course.id,
                                                    name: newName,
                                                    description:
                                                        newDesc.isNotEmpty
                                                        ? newDesc
                                                        : null,
                                                  );
                                                  await _dbService.updateCourse(
                                                    course.id,
                                                    updated,
                                                  );
                                                  Navigator.of(context).pop();
                                                  setState(() {});
                                                },
                                                child: Text('Enregistrer'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      tooltip: 'Retirer cette matière',
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).cardColor,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            title: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: const [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Color(0xFFE11D48),
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Retirer la matière ?',
                                                  style: TextStyle(
                                                    color: Color(0xFFE11D48),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            content: Text(
                                              'Voulez-vous retirer "${course.name}" de cette classe ?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Annuler'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFE11D48,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Retirer'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await _dbService
                                              .removeCourseFromClass(
                                                _nameController.text,
                                                _yearController.text,
                                                course.id,
                                              );
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              icon: Icon(Icons.add_outlined),
                              label: Text('Ajouter des matières'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () async {
                                final allCourses = await _dbService
                                    .getCourses();
                                final classCourseIds = classCourses
                                    .map((c) => c.id)
                                    .toSet();
                                final availableCourses = allCourses
                                    .where(
                                      (c) => !classCourseIds.contains(c.id),
                                    )
                                    .toList();
                                if (availableCourses.isEmpty) {
                                  // Utiliser un simple AlertDialog car on est dans un CustomDialog sans Scaffold
                                  await showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Information'),
                                      content: const Text(
                                        'Aucune matière disponible à ajouter.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }
                                final Map<String, bool> selected = {
                                  for (final course in availableCourses)
                                    course.id: false,
                                };
                                await showDialog(
                                  context: context,
                                  builder: (context) => StatefulBuilder(
                                    builder: (context, setStateDialog) =>
                                        AlertDialog(
                                          title: Text(
                                            'Ajouter des matières à la classe',
                                          ),
                                          content: SizedBox(
                                            width: 350,
                                            child: ListView(
                                              shrinkWrap: true,
                                              children: availableCourses
                                                  .map(
                                                    (
                                                      course,
                                                    ) => CheckboxListTile(
                                                      value:
                                                          selected[course.id],
                                                      title: Text(course.name),
                                                      subtitle:
                                                          course.description !=
                                                                  null &&
                                                              course
                                                                  .description!
                                                                  .isNotEmpty
                                                          ? Text(
                                                              course
                                                                  .description!,
                                                            )
                                                          : null,
                                                      onChanged: (val) {
                                                        setStateDialog(
                                                          () =>
                                                              selected[course
                                                                      .id] =
                                                                  val ?? false,
                                                        );
                                                      },
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: Text('Annuler'),
                                            ),
                                            ElevatedButton(
                                              onPressed:
                                                  selected.values.any((v) => v)
                                                  ? () async {
                                                      for (final entry
                                                          in selected.entries) {
                                                        if (entry.value) {
                                                          await _dbService
                                                              .addCourseToClass(
                                                                _nameController
                                                                    .text,
                                                                _yearController
                                                                    .text,
                                                                entry.key,
                                                              );
                                                        }
                                                      }
                                                      Navigator.of(
                                                        context,
                                                      ).pop();
                                                      setState(() {});
                                                    }
                                                  : null,
                                              child: Text('Ajouter'),
                                            ),
                                          ],
                                        ),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildModernSectionTitle(
                      'Pondération des matières (cette classe uniquement)',
                      Icons.tune,
                    ),
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
                          Row(
                            children: [
                              Icon(
                                Icons.tune,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Définissez le coefficient de chaque matière. Aucune somme imposée (pondération libre).',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Text(
                                  'Somme: ${_sumCoeffs.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FutureBuilder<List<Course>>(
                            future: _dbService.getCoursesForClass(
                              _nameController.text,
                              _yearController.text,
                            ),
                            builder: (context, snapshot) {
                              final subs = snapshot.data ?? _classSubjects;
                              if (subs.isEmpty) {
                                return Text(
                                  'Aucune matière pour ${_nameController.text}.',
                                );
                              }
                              return Column(
                                children: [
                                  Table(
                                    border: TableBorder.all(
                                      color: Colors.blue.shade100,
                                    ),
                                    columnWidths: const {
                                      0: FlexColumnWidth(3),
                                      1: FlexColumnWidth(1),
                                    },
                                    children: [
                                      TableRow(
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                        ),
                                        children: const [
                                          Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Text(
                                              'Matière',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Text(
                                              'Coeff.',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      ...subs.map((c) {
                                        final ctrl =
                                            _coeffCtrls[c.id] ??
                                            TextEditingController();
                                        if (!_coeffCtrls.containsKey(c.id)) {
                                          _coeffCtrls[c.id] = ctrl;
                                        }
                                        return TableRow(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(c.name),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: TextField(
                                                controller: ctrl,
                                                decoration:
                                                    const InputDecoration(
                                                      isDense: true,
                                                      border:
                                                          OutlineInputBorder(),
                                                      hintText: 'ex: 2',
                                                    ),
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                onChanged: (_) =>
                                                    _recomputeSum(),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: _saveCoefficients,
                                        icon: const Icon(Icons.save),
                                        label: const Text('Enregistrer'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: _loadClassSubjectsAndCoeffs,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Recharger'),
                                      ),
                                    ],
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
            ),
          ),
        ),
      ),
      fields: const [],
      onSubmit: () {
        if (!_isLoading) _saveClass();
      },
      actions: [
        // Delete class
        OutlinedButton(
          onPressed: _isLoading
              ? null
              : () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Supprimer la classe ?'),
                      content: Text(
                        'Voulez-vous vraiment supprimer la classe "${_nameController.text}" ?\nCette action est irréversible.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE53E3E),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Supprimer'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      setState(() => _isLoading = true);
                      // Préserver les données pour permettre l'annulation
                      final deleted = Class(
                        name: _nameController.text,
                        academicYear: _yearController.text,
                        level: _selectedLevel,
                        titulaire: _titulaireController.text.isNotEmpty
                            ? _titulaireController.text
                            : null,
                        fraisEcole: _fraisEcoleController.text.isNotEmpty
                            ? double.tryParse(_fraisEcoleController.text)
                            : null,
                        fraisCotisationParallele:
                            _fraisCotisationParalleleController.text.isNotEmpty
                            ? double.tryParse(
                                _fraisCotisationParalleleController.text,
                              )
                            : null,
                      );
                      await _dbService.deleteClassByName(
                        _nameController.text,
                        _yearController.text,
                      );
                      setState(() => _isLoading = false);
                      showRootSnackBar(
                        SnackBar(
                          content: const Text('Classe supprimée'),
                          action: SnackBarAction(
                            label: 'Annuler',
                            onPressed: () async {
                              try {
                                await _dbService.insertClass(deleted);
                                showRootSnackBar(
                                  const SnackBar(
                                    content: Text('Suppression annulée'),
                                  ),
                                );
                              } catch (e) {
                                showRootSnackBar(
                                  SnackBar(
                                    content: Text('Annulation impossible: $e'),
                                  ),
                                );
                              }
                            },
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      if (mounted) Navigator.of(context).pop();
                    } catch (e) {
                      setState(() => _isLoading = false);
                      await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Impossible de supprimer'),
                          content: Text(e.toString()),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: Color(0xFFE53E3E)),
            foregroundColor: const Color(0xFFE53E3E),
          ),
          child: const Text(
            'Supprimer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        OutlinedButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: const Text(
            'Fermer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveClass,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3182CE),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Enregistrer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Future<void> _exportSubjectGradesTemplateExcel(
    String subjectName,
    String selectedTerm,
    int devCount,
    int compCount,
  ) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Génération du modèle Excel [$subjectName]...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final workbook = xls.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Matiere_${subjectName.replaceAll(' ', '_')}';

      final headerStyle = workbook.styles.add('headerSubjectStyle');
      headerStyle.bold = true;
      headerStyle.backColor = '#E5F2FF';
      headerStyle.hAlign = xls.HAlignType.center;
      headerStyle.vAlign = xls.VAlignType.center;

      int col = 1;
      void setHeader(int c, String text) {
        final range = sheet.getRangeByIndex(1, c);
        range.setText(text);
        range.cellStyle = headerStyle;
        sheet.autoFitColumn(c);
      }

      // Colonnes d'identification et infos élèves
      final int idCol = col;
      setHeader(col++, 'ID_Eleve');
      final int matriculeCol = col;
      setHeader(col++, 'Matricule');
      final int nameCol = col;
      setHeader(col++, 'Nom et Prénom(s)');
      final int classCol = col;
      setHeader(col++, 'Classe');
      final int yearCol = col;
      setHeader(col++, 'Annee');
      final int periodCol = col;
      setHeader(col++, 'Periode');
      final int sexCol = col;
      setHeader(col++, 'Sexe');
      final int statusCol = col;
      setHeader(col++, 'Statut');
      // Notes de classe (3 cellules), moyenne, et note de composition
      final int note1Col = col;
      setHeader(col++, 'Notes de classe');
      final int note2Col = col;
      setHeader(col++, '');
      final int note3Col = col;
      setHeader(col++, '');
      final int avgClassCol = col;
      setHeader(col++, 'Moyenne Classe');
      final int compNoteCol = col;
      setHeader(col++, 'Note Composition');
      // Colonnes dynamiques Devoir(s) (valeurs uniquement)
      final List<int> devoirCols = [];
      for (int i = 0; i < devCount; i++) {
        final String label = devCount == 1 ? 'Devoir' : 'Devoir ${i + 1}';
        final dCol = col++;
        setHeader(dCol, '$label [$subjectName]');
        devoirCols.add(dCol);
      }
      // Colonnes dynamiques Composition(s) (valeurs uniquement)
      final List<int> compCols = [];
      for (int i = 0; i < compCount; i++) {
        final String label = compCount == 1
            ? 'Composition'
            : 'Composition ${i + 1}';
        final cCol = col++;
        setHeader(cCol, '$label [$subjectName]');
        compCols.add(cCol);
      }
      // Fusionner l'entête des 3 colonnes de notes de classe
      try {
        final mergeRange = sheet.getRangeByIndex(1, note1Col, 1, note3Col);
        mergeRange.merge();
        mergeRange.cellStyle = headerStyle;
        sheet.autoFitColumn(note1Col);
      } catch (_) {}
      // Observations en dernière colonne
      final int obsCol = col;
      setHeader(col++, 'Observations');

      // Conserver compat: aucun préremplissage devoir/composition

      final studentsSorted = _sortedStudentsForExport();
      for (int i = 0; i < studentsSorted.length; i++) {
        final row = i + 2;
        final s = studentsSorted[i];
        // Identifiants et infos
        sheet.getRangeByIndex(row, idCol).setText(s.id);
        sheet.getRangeByIndex(row, matriculeCol).setText(s.matricule ?? '');
        sheet
            .getRangeByIndex(row, nameCol)
            .setText('${s.lastName} ${s.firstName}'.trim());
        sheet.getRangeByIndex(row, classCol).setText(_nameController.text);
        sheet.getRangeByIndex(row, yearCol).setText(_yearController.text);
        sheet.getRangeByIndex(row, periodCol).setText(selectedTerm);
        sheet.getRangeByIndex(row, sexCol).setText(s.gender);
        sheet.getRangeByIndex(row, statusCol).setText(s.status);
        // Notes de classe et moyennes (saisie libre)
        sheet.getRangeByIndex(row, note1Col).setText('');
        sheet.getRangeByIndex(row, note2Col).setText('');
        sheet.getRangeByIndex(row, note3Col).setText('');
        sheet.getRangeByIndex(row, avgClassCol).setText('');
        sheet.getRangeByIndex(row, compNoteCol).setText('');

        // Notes: aucune préremplissage pour devoir/comp: saisie utilisateur
        // Observations (dernière colonne)
        sheet.getRangeByIndex(row, obsCol).setText('');
      }

      final lastRow =
          (studentsSorted.isNotEmpty ? studentsSorted.length : 1) + 1;
      // Validation 0-20 sur colonnes de notes (devoirs + compositions + notes de classe + moyenne + comp. note)
      final List<int> gradeCols = [
        ...devoirCols,
        ...compCols,
        note1Col,
        note2Col,
        note3Col,
        avgClassCol,
        compNoteCol,
      ];
      for (final colIndex in gradeCols) {
        try {
          final dv = sheet
              .getRangeByIndex(2, colIndex, lastRow, colIndex)
              .dataValidation;
          (dv as dynamic).allowType = 2; // decimal
          try {
            (dv as dynamic).operator = 6;
          } catch (_) {
            try {
              (dv as dynamic).compareOperator = 6;
            } catch (_) {}
          }
          (dv as dynamic).firstFormula = '0';
          (dv as dynamic).secondFormula = '20';
          (dv as dynamic).promptBoxTitle = 'Validation';
          (dv as dynamic).promptBoxText = 'Entrez une note entre 0 et 20';
          (dv as dynamic).showPromptBox = true;
        } catch (_) {}
      }

      try {
        (sheet as dynamic).freezePanes(2, 1);
      } catch (_) {}
      for (int c = 1; c <= col; c++) {
        sheet.autoFitColumn(c);
      }

      // Masquer les colonnes de métadonnées (ID, Classe, Annee, Periode)
      try {
        (sheet as dynamic).hideColumn(idCol);
      } catch (_) {
        try {
          sheet.getRangeByIndex(1, idCol, 1, idCol).columnWidth = 0;
        } catch (_) {}
      }
      try {
        (sheet as dynamic).hideColumn(classCol);
      } catch (_) {
        try {
          sheet.getRangeByIndex(1, classCol, 1, classCol).columnWidth = 0;
        } catch (_) {}
      }
      try {
        (sheet as dynamic).hideColumn(yearCol);
      } catch (_) {
        try {
          sheet.getRangeByIndex(1, yearCol, 1, yearCol).columnWidth = 0;
        } catch (_) {}
      }
      try {
        (sheet as dynamic).hideColumn(periodCol);
      } catch (_) {
        try {
          sheet.getRangeByIndex(1, periodCol, 1, periodCol).columnWidth = 0;
        } catch (_) {}
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;

      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final safeSubject = subjectName.replaceAll(' ', '_');
      final fileName =
          'modele_notes_${_nameController.text}_${safeSubject}_${_yearController.text}_${selectedTerm.replaceAll(' ', '_')}_$formattedDate.xlsx';
      final file = File('$dirPath/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modèle Excel [$subjectName] généré : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur génération modèle Excel [$subjectName] : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _exportSubjectGradesTemplatePdf(
    String subjectName,
    String selectedTerm,
    int devCount,
    int compCount,
  ) async {
    try {
      final pdf = pw.Document();
      final title = 'RELEVE DE NOTES DE CLASSE';
      final className = _nameController.text;
      final year = _yearController.text;
      // Footer date (dd/MM/yyyy) + pagination
      final _nowFooter = DateTime.now();
      final _footerDate =
          '${_nowFooter.day.toString().padLeft(2, '0')}/'
          '${_nowFooter.month.toString().padLeft(2, '0')}/'
          '${_nowFooter.year}';

      // Charger coefficient matière et enseignant assigné
      final subjectCoeffs = await _dbService.getClassSubjectCoefficients(
        className,
        year,
      );
      final double coeffMatiere = subjectCoeffs[subjectName] ?? 1;
      String teacherName = (_titulaireController.text).trim();
      try {
        final courses = await _dbService.getCoursesForClass(className, year);
        final subj = courses.firstWhere(
          (c) => c.name == subjectName,
          orElse: () => Course.empty(),
        );
        if (subj.id.isNotEmpty) {
          final assigned = await _dbService.getTeacherNameByCourseForClass(
            className: className,
            academicYear: year,
          );
          final name = assigned[subj.id];
          if (name != null && name.isNotEmpty) {
            teacherName = name;
          }
        }
      } catch (_) {}

      // Charger infos établissement et préparer thème (filigrane)
      final SchoolInfo? schoolInfo = await _dbService.getSchoolInfo();
      final prefs = await SharedPreferences.getInstance();
      final adminCivility = (prefs.getString('school_admin_civility') ?? 'M.')
          .trim();
      final classRow = await _dbService.getClassByName(
        className,
        academicYear: year,
      );
      final String niveau = (classRow?.level?.trim().isNotEmpty ?? false)
          ? classRow!.level!.trim()
          : (prefs.getString('school_level') ?? '').trim();
      final bool isComplexe = (prefs.getString('school_level') ?? '')
          .toLowerCase()
          .contains('complexe');
      String directorName = (schoolInfo?.director ?? '').trim();
      String civility = adminCivility;
      if (isComplexe && schoolInfo != null) {
        final n = niveau.toLowerCase();
        if (n.contains('primaire') || n.contains('maternelle')) {
          directorName = (schoolInfo.directorPrimary ?? directorName).trim();
          civility = (schoolInfo.civilityPrimary ?? civility).trim();
        } else if (n.contains('coll')) {
          directorName = (schoolInfo.directorCollege ?? directorName).trim();
          civility = (schoolInfo.civilityCollege ?? civility).trim();
        } else if (n.contains('lyc')) {
          directorName = (schoolInfo.directorLycee ?? directorName).trim();
          civility = (schoolInfo.civilityLycee ?? civility).trim();
        } else if (n.contains('univ')) {
          directorName = (schoolInfo.directorUniversity ?? directorName).trim();
          civility = (schoolInfo.civilityUniversity ?? civility).trim();
        }
      }
      final directorDisplayName = directorName.isEmpty
          ? ''
          : (civility.isNotEmpty ? '$civility $directorName' : directorName);
      final PdfPageFormat _pageFormat = PdfPageFormat.a4;
      final pw.PageTheme _pageTheme = pw.PageTheme(
        pageFormat: _pageFormat,
        margin: const pw.EdgeInsets.all(24),
        buildBackground:
            (schoolInfo != null &&
                schoolInfo.logoPath != null &&
                File(schoolInfo.logoPath!).existsSync())
            ? (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Opacity(
                  opacity: 0.06,
                  child: pw.Image(
                    pw.MemoryImage(
                      File(schoolInfo.logoPath!).readAsBytesSync(),
                    ),
                    fit: pw.BoxFit.cover,
                  ),
                ),
              )
            : null,
      );

      final studentsSorted = _sortedStudentsForExport();

      pw.Widget buildHeader() {
        final left = (schoolInfo?.ministry ?? '').trim();
        final rightTop = (schoolInfo?.republic ?? '').trim();
        final rightBottom = (schoolInfo?.republicMotto ?? '').trim();
        final schoolName = (schoolInfo?.name ?? '').trim().toUpperCase();
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (left.isNotEmpty)
                        pw.Text(
                          left.toUpperCase(),
                          style: pw.TextStyle(fontSize: 8),
                        ),
                      if ((schoolInfo?.educationDirection ?? '').isNotEmpty)
                        pw.Text(
                          (schoolInfo?.educationDirection ?? '').toUpperCase(),
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      if ((schoolInfo?.inspection ?? '').isNotEmpty)
                        pw.Text(
                          (schoolInfo?.inspection ?? '').toUpperCase(),
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (rightTop.isNotEmpty)
                        pw.Text(
                          rightTop.toUpperCase(),
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      if (rightBottom.isNotEmpty)
                        pw.Text(
                          rightBottom.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            if (schoolInfo != null &&
                (schoolInfo.logoPath ?? '').isNotEmpty &&
                File(schoolInfo.logoPath!).existsSync())
              pw.Center(
                child: pw.Container(
                  height: 40,
                  width: 40,
                  child: pw.Image(
                    pw.MemoryImage(
                      File(schoolInfo.logoPath!).readAsBytesSync(),
                    ),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                schoolName.isNotEmpty ? schoolName : 'FEUILLE DE NOTES',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: PdfColors.blueGrey300),
          ],
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageTheme: _pageTheme,
          header: (context) {
            if (context.pageNumber != 1) return pw.SizedBox();
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                buildHeader(),
                pw.SizedBox(height: 6),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text('Classe: $className\nAnnée: $year'),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Text(
                        'Matière: $subjectName\nProfesseur: $teacherName',
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Coefficient matière: ${coeffMatiere.toStringAsFixed(2)}',
                    ),
                    pw.Text('Sur: 20    Période: $selectedTerm'),
                  ],
                ),
                pw.SizedBox(height: 10),
              ],
            );
          },
          footer: (context) => pw.Column(
            children: [
              pw.Container(height: 0.8, color: PdfColors.blueGrey300),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Généré le: ' + _footerDate,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber}/${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
          build: (context) {
            // Entêtes: N°, Matricule, Nom et Prénom(s), Sexe, Statut, (3 colonnes sans texte pour notes de classe),
            // Moyenne de classe, Note composition, puis colonnes dynamiques et Observations en dernière colonne
            final headers = <String>[
              '', // N°
              '', // Matricule
              '', // Nom et Prénom(s)
              '', // Sexe
              '', // Statut
              '', // Notes de classe (col 1)
              '', // Notes de classe (col 2)
              '', // Notes de classe (col 3)
              '', // Moyenne Classe
              '', // Note Composition
            ];
            // (Colonnes Devoir/Composition supprimées à la demande)
            headers.add(''); // Observations
            final rows = <List<String>>[];
            for (int i = 0; i < studentsSorted.length; i++) {
              final s = studentsSorted[i];
              final row = <String>[
                (i + 1).toString(),
                (s.matricule ?? ''),
                '${s.lastName} ${s.firstName}'.trim(),
                s.gender,
                s.status,
                '', // Note Classe 1
                '', // Note Classe 2
                '', // Note Classe 3
                '', // Moyenne Classe
                '', // Note Composition
              ];
              // (Pas de colonnes Devoir/Composition)
              row.add(''); // Observations (à compléter) en dernière colonne
              rows.add(row);
            }

            // Définir des largeurs flexibles pour aligner un label au-dessus des 3 colonnes de notes de classe
            final List<int> columnFlex = []
              ..addAll([
                6,
                9,
                28,
                8,
                10,
              ]) // N°, Matricule, Nom (élargi), Sexe, Statut
              ..addAll([9, 9, 9]) // 3 colonnes de notes de classe
              ..addAll([10, 10]) // Moyenne classe, Note composition
              ..add(16); // Observations

            final columnWidths = <int, pw.TableColumnWidth>{
              for (int i = 0; i < headers.length; i++)
                i: pw.FlexColumnWidth(columnFlex[i].toDouble()),
            };
            const headerBg = PdfColors.blue100;
            const headerBorder = PdfColors.blue200;
            pw.Widget _topHeaderCell(
              String text, {
              bool isFirst = false,
              bool isLast = false,
              bool isGroup = false,
            }) {
              return pw.Container(
                height: 22,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: headerBg,
                  border: pw.Border.all(color: headerBorder, width: 0.8),
                  borderRadius: pw.BorderRadius.only(
                    topLeft: isFirst
                        ? const pw.Radius.circular(6)
                        : pw.Radius.zero,
                    topRight: isLast
                        ? const pw.Radius.circular(6)
                        : pw.Radius.zero,
                  ),
                ),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  text,
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              );
            }

            final int groupFlex = columnFlex[5] + columnFlex[6] + columnFlex[7];
            return [
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: columnFlex[0],
                    child: _topHeaderCell('N°', isFirst: true),
                  ),
                  pw.Expanded(
                    flex: columnFlex[1],
                    child: _topHeaderCell('Matricule'),
                  ),
                  pw.Expanded(
                    flex: columnFlex[2],
                    child: _topHeaderCell('Nom et Prénom(s)'),
                  ),
                  pw.Expanded(
                    flex: columnFlex[3],
                    child: _topHeaderCell('Sexe'),
                  ),
                  pw.Expanded(
                    flex: columnFlex[4],
                    child: _topHeaderCell('Statut'),
                  ),
                  pw.Expanded(
                    flex: groupFlex,
                    child: _topHeaderCell('Notes de classe', isGroup: true),
                  ),
                  pw.Expanded(
                    flex: columnFlex[8],
                    child: _topHeaderCell('Moyenne Classe'),
                  ),
                  pw.Expanded(
                    flex: columnFlex[9],
                    child: _topHeaderCell('Note Composition'),
                  ),
                  pw.Expanded(
                    flex: columnFlex[10],
                    child: _topHeaderCell('Observations', isLast: true),
                  ),
                ],
              ),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.blue100),
                columnWidths: columnWidths,
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                    children: [
                      for (final h in headers)
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 3,
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            h,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 8,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final r in rows)
                    pw.TableRow(
                      children: [
                        for (final c in r)
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 3,
                              horizontal: 3,
                            ),
                            alignment: pw.Alignment.centerLeft,
                            child: pw.Text(
                              c,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Text('Observations générales :'),
              pw.SizedBox(height: 6),
              pw.Container(height: 0.8, color: PdfColors.blueGrey300),
              pw.SizedBox(height: 6),
              pw.Container(height: 0.8, color: PdfColors.blueGrey300),
              pw.SizedBox(height: 18),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Fait à: ______________________'),
                  pw.Text('Le: ____ / ____ / ______'),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Text("Signature et nom de l'enseignant"),
                      pw.SizedBox(height: 28),
                      pw.Container(
                        width: 200,
                        height: 0.8,
                        color: PdfColors.blueGrey300,
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text("Signature et nom du Chef d'établissement"),
                      if (directorDisplayName.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          directorDisplayName,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                      pw.SizedBox(
                        height: directorDisplayName.isNotEmpty ? 22 : 28,
                      ),
                      pw.Container(
                        width: 220,
                        height: 0.8,
                        color: PdfColors.blueGrey300,
                      ),
                    ],
                  ),
                ],
              ),
            ];
          },
        ),
      );

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final safeSubject = subjectName.replaceAll(' ', '_');
      final fileName =
          'modele_notes_${_nameController.text}_${safeSubject}_${_yearController.text}_$formattedDate.pdf';
      final file = File('$dirPath/$fileName');
      await file.writeAsBytes(await pdf.save());
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modèle PDF [$subjectName] généré : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur génération modèle PDF [$subjectName] : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showSubjectTemplateDialog() async {
    final subjects = await _dbService.getCoursesForClass(
      _nameController.text,
      _yearController.text,
    );
    if (subjects.isEmpty) {
      _showModernSnackBar(
        "Aucune matière n'est associée à cette classe",
        isError: true,
      );
      return;
    }
    String selected = subjects.first.name;
    String mode = 'Trimestre';
    List<String> terms = ['Trimestre 1', 'Trimestre 2', 'Trimestre 3'];
    String term = terms.first;
    int devCount = 1;
    int compCount = 1;
    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Modèle par matière'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choisissez une matière :'),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: selected,
                    isExpanded: true,
                    items: subjects
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.name,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => selected = v ?? selected),
                  ),
                  const SizedBox(height: 12),
                  const Text('Période :'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: mode,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'Trimestre',
                              child: Text('Trimestre'),
                            ),
                            DropdownMenuItem(
                              value: 'Semestre',
                              child: Text('Semestre'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              mode = v;
                              terms = v == 'Trimestre'
                                  ? [
                                      'Trimestre 1',
                                      'Trimestre 2',
                                      'Trimestre 3',
                                    ]
                                  : ['Semestre 1', 'Semestre 2'];
                              term = terms.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: term,
                          isExpanded: true,
                          items: terms
                              .map(
                                (t) => DropdownMenuItem<String>(
                                  value: t,
                                  child: Text(t),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => term = v ?? term),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Nombre de colonnes par type :'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Text('Devoirs: '),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: devCount,
                              items: [1, 2, 3, 4, 5]
                                  .map(
                                    (n) => DropdownMenuItem<int>(
                                      value: n,
                                      child: Text(n.toString()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => devCount = v ?? devCount),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            const Text('Compositions: '),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: compCount,
                              items: [1, 2, 3, 4, 5]
                                  .map(
                                    (n) => DropdownMenuItem<int>(
                                      value: n,
                                      child: Text(n.toString()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => compCount = v ?? compCount),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _exportSubjectGradesTemplatePdf(
                      selected,
                      term,
                      devCount,
                      compCount,
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _exportSubjectGradesTemplateExcel(
                      selected,
                      term,
                      devCount,
                      compCount,
                    );
                  },
                  icon: const Icon(Icons.table_view),
                  label: const Text('Excel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildStatsAndFilter() {
    return FutureBuilder<List<double>>(
      future: _getStatsForStudents(),
      builder: (context, snapshot) {
        final int nbPayes = snapshot.hasData ? snapshot.data![0].toInt() : 0;
        final int nbAttente = snapshot.hasData ? snapshot.data![1].toInt() : 0;
        final int total = nbPayes + nbAttente;
        final double percent = total > 0 ? (nbPayes / total * 100) : 0;
        return Row(
          children: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Payé : $nbPayes',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'En attente : $nbAttente',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              'Paiement global : ${percent.toStringAsFixed(1)}%',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            DropdownButton<String>(
              value: _studentStatusFilter,
              items: const [
                DropdownMenuItem(value: 'Tous', child: Text('Tous')),
                DropdownMenuItem(value: 'Payé', child: Text('Payé')),
                DropdownMenuItem(
                  value: 'En attente',
                  child: Text('En attente'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _studentStatusFilter = value!),
            ),
          ],
        );
      },
    );
  }

  Future<List<double>> _getStatsForStudents() async {
    int nbPayes = 0;
    int nbAttente = 0;
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    for (final s in _students) {
      final totalPaid = await _dbService.getTotalPaidForStudent(s.id);
      if (montantMax > 0 && totalPaid >= montantMax) {
        nbPayes++;
      } else {
        nbAttente++;
      }
    }
    return [nbPayes.toDouble(), nbAttente.toDouble()];
  }

  void _exportStudentsPdf() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final studentsList = _students.map((student) {
        final classe = widget.classe;
        return {'student': student, 'classe': classe};
      }).toList();

      final pdfBytes = await PdfService.exportStudentsListPdf(
        students: studentsList,
      );
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé

      // Nom de fichier plus descriptif avec date formatée
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final fileName =
          'liste_eleves_${widget.classe.name}_${formattedDate}.pdf';
      final file = File('$dirPath/$fileName');

      await file.writeAsBytes(pdfBytes);

      // Ouvrir automatiquement le fichier
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF réussi : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur export PDF élèves : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export PDF : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _exportStudentIdCards() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Génération des cartes scolaires...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final result = await StudentIdCardService(dbService: _dbService)
          .exportStudentIdCardsPdf(
            students: _students,
            academicYear: _yearController.text,
            className: _nameController.text,
            dialogTitle: 'Choisissez un dossier de sauvegarde',
          );

      if (result.directoryResult.usedFallback &&
          result.directoryResult.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.directoryResult.errorMessage!}\nDossier: ${result.directoryResult.path}',
            ),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      await OpenFile.open(result.file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cartes générées: ${result.file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(result.file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur génération cartes scolaires: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _exportStudentsExcel() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final studentsList = _students.map((student) {
        final classe = widget.classe;
        return {'student': student, 'classe': classe};
      }).toList();

      // Trie par nom
      studentsList.sort(
        (a, b) => _displayStudentName((a['student'] as Student))
            .toLowerCase()
            .compareTo(
              _displayStudentName((b['student'] as Student)).toLowerCase(),
            ),
      );

      final excel = Excel.createExcel();
      final sheet = excel['Élèves'];

      // En-têtes avec formatage
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.blue50,
        fontColorHex: ExcelColor.blue900,
      );

      final headers = [
        'ID',
        'Nom et Prénom(s)',
        'Date de Naissance',
        'Lieu de Naissance',
        'Genre',
        'Adresse',
        'Contact',
        'Email',
        'Contact d\'Urgence',
        'Tuteur',
        'Contact Tuteur',
        'Statut',
        'Infos Médicales',
        'Matricule',
      ];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // Data
      for (var i = 0; i < studentsList.length; i++) {
        final student = studentsList[i]['student'] as Student;
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue(
          student.id,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = TextCellValue(
          '${student.lastName} ${student.firstName}'.trim(),
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
            .value = TextCellValue(
          student.dateOfBirth,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
            .value = TextCellValue(
          student.placeOfBirth ?? '',
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1))
            .value = TextCellValue(
          student.gender,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1))
            .value = TextCellValue(
          student.address,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: i + 1))
            .value = TextCellValue(
          student.contactNumber,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: i + 1))
            .value = TextCellValue(
          student.email,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: i + 1))
            .value = TextCellValue(
          student.emergencyContact,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: i + 1))
            .value = TextCellValue(
          student.guardianName,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: i + 1))
            .value = TextCellValue(
          student.guardianContact,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: i + 1))
            .value = TextCellValue(
          student.status,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: i + 1))
            .value = TextCellValue(
          student.medicalInfo ?? '',
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: i + 1))
            .value = TextCellValue(
          student.matricule ?? '',
        );
      }

      // Ajuster la largeur des colonnes
      for (int i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(i, 15);
      }
      // Élargir la colonne Nom et Prénom(s)
      sheet.setColumnWidth(1, 25);

      final bytes = excel.encode()!;
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé

      // Nom de fichier plus descriptif avec date formatée
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final fileName =
          'liste_eleves_${widget.classe.name}_${formattedDate}.xlsx';
      final file = File('$dirPath/$fileName');

      await file.writeAsBytes(bytes);

      // Ouvrir automatiquement le fichier
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel réussi : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur export Excel élèves : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Excel : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _exportStudentsWord() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Word en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé

      final docx = await _generateStudentsDocx();

      // Nom de fichier plus descriptif avec date formatée
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final fileName = 'liste_eleves_${widget.classe.name}_$formattedDate.docx';
      final file = File('$dirPath/$fileName');

      await file.writeAsBytes(docx);

      // Ouvrir automatiquement le fichier
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Word réussi : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur export Word élèves : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Word : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _exportStudentProfilesPdf() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Génération des fiches profil en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé

      // Générer une fiche profil pour chaque élève
      for (int i = 0; i < _students.length; i++) {
        final student = _students[i];
        final pdfBytes = await PdfService.exportStudentProfilePdf(
          student: student,
          classe: widget.classe,
        );

        // Nom de fichier avec le nom de l'élève
        final fileName =
            'fiche_profil_${'${student.firstName}_${student.lastName}'.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('$dirPath/$fileName');

        await file.writeAsBytes(pdfBytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_students.length} fiches profil générées avec succès dans : $dirPath',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print('Erreur export fiches profil : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur génération des fiches profil : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<List<int>> _generateStudentsDocx() async {
    try {
      final bytes = await DefaultAssetBundle.of(
        context,
      ).load('assets/empty.docx');
      final docx = await DocxTemplate.fromBytes(bytes.buffer.asUint8List());

      // Construire une liste modifiable (évite les erreurs "unmodifiable list")
      final List<Student> sortedStudents = List<Student>.from(_students);
      sortedStudents.sort(
        (a, b) => _displayStudentName(
          a,
        ).toLowerCase().compareTo(_displayStudentName(b).toLowerCase()),
      );

      final classe = widget.classe;
      final List<Map<String, String>> rows = [];
      for (int i = 0; i < sortedStudents.length; i++) {
        final student = sortedStudents[i];
        rows.add({
          'numero': (i + 1).toString(),
          'nom': student.lastName,
          'prenom': student.firstName,
          'sexe': student.gender == 'M' ? 'Garçon' : 'Fille',
          'classe': student.className,
          'annee': classe.academicYear,
          'date_naissance': student.dateOfBirth,
          'adresse': student.address,
          'contact': student.contactNumber,
          'email': student.email,
          'tuteur': student.guardianName,
          'contact_tuteur': student.guardianContact,
        });
      }

      final content = Content();
      content.add(
        TableContent(
          'eleves',
          rows
              .map(
                (r) => RowContent()
                  ..add(TextContent('numero', r['numero'] ?? ''))
                  ..add(TextContent('nom', r['nom'] ?? ''))
                  ..add(TextContent('prenom', r['prenom'] ?? ''))
                  ..add(TextContent('sexe', r['sexe'] ?? ''))
                  ..add(TextContent('classe', r['classe'] ?? ''))
                  ..add(TextContent('annee', r['annee'] ?? ''))
                  ..add(
                    TextContent('date_naissance', r['date_naissance'] ?? ''),
                  )
                  ..add(TextContent('adresse', r['adresse'] ?? ''))
                  ..add(TextContent('contact', r['contact'] ?? ''))
                  ..add(TextContent('email', r['email'] ?? ''))
                  ..add(TextContent('tuteur', r['tuteur'] ?? ''))
                  ..add(
                    TextContent('contact_tuteur', r['contact_tuteur'] ?? ''),
                  ),
              )
              .toList(growable: true),
        ),
      );

      final generated = await docx.generate(content);
      if (generated == null) {
        throw Exception('Échec de la génération du document Word');
      }
      return List<int>.from(generated);
    } catch (e, st) {
      print('Erreur asset Word élèves : $e\n$st');
      rethrow;
    }
  }

  Future<void> _exportGradesTemplateExcel() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Génération du modèle Excel en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      // Récupération des matières pour la classe
      final List<Course> classSubjects = await _dbService.getCoursesForClass(
        _nameController.text,
        _yearController.text,
      );
      if (classSubjects.isEmpty) {
        _showModernSnackBar(
          "Aucune matière n'est associée à cette classe",
          isError: true,
        );
        return;
      }

      final workbook = xls.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Modèle';

      // Styles de base
      final headerStyle = workbook.styles.add('headerStyle');
      headerStyle.bold = true;
      headerStyle.backColor = '#E5F2FF';
      headerStyle.hAlign = xls.HAlignType.center;
      headerStyle.vAlign = xls.VAlignType.center;

      // En-têtes fixes
      int col = 1;
      void setHeader(int c, String text) {
        final range = sheet.getRangeByIndex(1, c);
        range.setText(text);
        range.cellStyle = headerStyle;
        sheet.autoFitColumn(c);
      }

      setHeader(col++, 'ID_Eleve');
      setHeader(col++, 'Nom');
      setHeader(col++, 'Classe');
      setHeader(col++, 'Annee');
      setHeader(col++, 'Periode');
      // Champs assiduité & conduite (généraux)
      final absJustCol = col++;
      setHeader(absJustCol, 'Abs Justifiees');
      final absInjCol = col++;
      setHeader(absInjCol, 'Abs Injustifiees');
      final retardsCol = col++;
      setHeader(retardsCol, 'Retards');
      final presenceCol = col++;
      setHeader(presenceCol, 'Presence (%)');
      final conduiteCol = col++;
      setHeader(conduiteCol, 'Conduite');
      // Champs de synthèse bulletin
      final apprGenCol = col++;
      setHeader(apprGenCol, 'Appreciation Generale');
      final decisionCol = col++;
      setHeader(decisionCol, 'Decision');
      final recommandCol = col++;
      setHeader(recommandCol, 'Recommandations');
      final forcesCol = col++;
      setHeader(forcesCol, 'Forces');
      final pointsDevCol = col++;
      setHeader(pointsDevCol, 'Points a Developper');
      final sanctionsCol = col++;
      setHeader(sanctionsCol, 'Sanctions');

      // Pour chaque matière, on ajoute des colonnes
      // Devoir/Composition + Coeff + Sur + Prof + App + MoyClasse
      final List<_SubjectColumnMeta> subjectColumns = [];
      for (final subject in classSubjects) {
        final subjectName = subject.name;
        final devoirCol = col++;
        setHeader(devoirCol, 'Devoir [$subjectName]');
        final coeffDevCol = col++;
        setHeader(coeffDevCol, 'Coeff Devoir [$subjectName]');
        final surDevCol = col++;
        setHeader(surDevCol, 'Sur Devoir [$subjectName]');

        final compoCol = col++;
        setHeader(compoCol, 'Composition [$subjectName]');
        final coeffCompCol = col++;
        setHeader(coeffCompCol, 'Coeff Composition [$subjectName]');
        final surCompCol = col++;
        setHeader(surCompCol, 'Sur Composition [$subjectName]');

        final profCol = col++;
        setHeader(profCol, 'Prof [$subjectName]');
        final appCol = col++;
        setHeader(appCol, 'App [$subjectName]');
        final moyClasseCol = col++;
        setHeader(moyClasseCol, 'MoyClasse [$subjectName]');

        subjectColumns.add(
          _SubjectColumnMeta(
            name: subjectName,
            devoirCol: devoirCol,
            coeffDevoirCol: coeffDevCol,
            surDevoirCol: surDevCol,
            compoCol: compoCol,
            coeffCompoCol: coeffCompCol,
            surCompoCol: surCompCol,
            profCol: profCol,
            appCol: appCol,
            moyClasseCol: moyClasseCol,
          ),
        );
      }

      // Charger les coefficients de matières définis au niveau de la classe
      final Map<String, double> subjectCoeffs = await _dbService
          .getClassSubjectCoefficients(
            _nameController.text,
            _yearController.text,
          );

      // Remplir les lignes élèves
      final studentsSorted = _sortedStudentsForExport();
      for (int i = 0; i < studentsSorted.length; i++) {
        final row = i + 2; // 1 = header
        final s = studentsSorted[i];
        sheet.getRangeByIndex(row, 1).setText(s.id);
        sheet.getRangeByIndex(row, 2).setText(s.name);
        sheet.getRangeByIndex(row, 3).setText(_nameController.text);
        sheet.getRangeByIndex(row, 4).setText(_yearController.text);
        sheet.getRangeByIndex(row, 5).setText('Trimestre 1');

        // Valeurs par défaut pour assiduité
        sheet.getRangeByIndex(row, absJustCol).setNumber(0);
        sheet.getRangeByIndex(row, absInjCol).setNumber(0);
        sheet.getRangeByIndex(row, retardsCol).setNumber(0);
        sheet.getRangeByIndex(row, presenceCol).setNumber(0);
        sheet.getRangeByIndex(row, conduiteCol).setText('');
        sheet.getRangeByIndex(row, apprGenCol).setText('');
        sheet.getRangeByIndex(row, decisionCol).setText('');
        sheet.getRangeByIndex(row, recommandCol).setText('');
        sheet.getRangeByIndex(row, forcesCol).setText('');
        sheet.getRangeByIndex(row, pointsDevCol).setText('');
        sheet.getRangeByIndex(row, sanctionsCol).setText('');

        // Valeurs par défaut pour coeff (matière) et "sur"
        for (final meta in subjectColumns) {
          final double coeffMatiere = subjectCoeffs[meta.name] ?? 1;
          sheet
              .getRangeByIndex(row, meta.coeffDevoirCol)
              .setNumber(coeffMatiere);
          sheet.getRangeByIndex(row, meta.surDevoirCol).setNumber(20);
          sheet
              .getRangeByIndex(row, meta.coeffCompoCol)
              .setNumber(coeffMatiere);
          sheet.getRangeByIndex(row, meta.surCompoCol).setNumber(20);
        }
      }

      // Validation des données (0-20) sur colonnes de notes
      int lastRow = studentsSorted.length + 1;
      // Validations assiduité
      try {
        final absJRange = sheet.getRangeByIndex(
          2,
          absJustCol,
          lastRow,
          absJustCol,
        );
        final absIRange = sheet.getRangeByIndex(
          2,
          absInjCol,
          lastRow,
          absInjCol,
        );
        final retRange = sheet.getRangeByIndex(
          2,
          retardsCol,
          lastRow,
          retardsCol,
        );
        final presRange = sheet.getRangeByIndex(
          2,
          presenceCol,
          lastRow,
          presenceCol,
        );
        for (final r in [absJRange, absIRange, retRange]) {
          final dv = r.dataValidation;
          try {
            (dv as dynamic).allowType = 2;
          } catch (_) {}
          try {
            (dv as dynamic).operator = 6;
          } catch (_) {
            try {
              (dv as dynamic).compareOperator = 6;
            } catch (_) {}
          }
          try {
            (dv as dynamic).firstFormula = '0';
            (dv as dynamic).secondFormula = '999';
          } catch (_) {}
          try {
            (dv as dynamic).promptBoxTitle = 'Validation';
            (dv as dynamic).promptBoxText = 'Entrez un entier >= 0';
            (dv as dynamic).showPromptBox = true;
          } catch (_) {}
        }
        final dvp = presRange.dataValidation;
        try {
          (dvp as dynamic).allowType = 2;
        } catch (_) {}
        try {
          (dvp as dynamic).operator = 6;
        } catch (_) {
          try {
            (dvp as dynamic).compareOperator = 6;
          } catch (_) {}
        }
        try {
          (dvp as dynamic).firstFormula = '0';
          (dvp as dynamic).secondFormula = '100';
        } catch (_) {}
        try {
          (dvp as dynamic).promptBoxTitle = 'Validation';
          (dvp as dynamic).promptBoxText = '0 à 100';
          (dvp as dynamic).showPromptBox = true;
        } catch (_) {}
      } catch (_) {}

      for (final meta in subjectColumns) {
        final dvRange = sheet.getRangeByIndex(
          2,
          meta.devoirCol,
          lastRow,
          meta.devoirCol,
        );
        final compRange = sheet.getRangeByIndex(
          2,
          meta.compoCol,
          lastRow,
          meta.compoCol,
        );

        try {
          final dv = dvRange.dataValidation;
          // use dynamic to avoid enum references
          (dv as dynamic).allowType = 2; // decimal
          try {
            (dv as dynamic).operator = 6; // between
          } catch (_) {
            try {
              (dv as dynamic).compareOperator = 6; // between
            } catch (_) {}
          }
          (dv as dynamic).firstFormula = '0';
          (dv as dynamic).secondFormula = '20';
          (dv as dynamic).promptBoxTitle = 'Validation';
          (dv as dynamic).promptBoxText = 'Entrez une note entre 0 et 20';
          (dv as dynamic).showPromptBox = true;
        } catch (_) {}

        try {
          final cv = compRange.dataValidation;
          (cv as dynamic).allowType = 2; // decimal
          try {
            (cv as dynamic).operator = 6; // between
          } catch (_) {
            try {
              (cv as dynamic).compareOperator = 6; // between
            } catch (_) {}
          }
          (cv as dynamic).firstFormula = '0';
          (cv as dynamic).secondFormula = '20';
          (cv as dynamic).promptBoxTitle = 'Validation';
          (cv as dynamic).promptBoxText = 'Entrez une note entre 0 et 20';
          (cv as dynamic).showPromptBox = true;
        } catch (_) {}
      }

      // Figer la première ligne et auto-fit (protect against API differences)
      try {
        (sheet as dynamic).freezePanes(2, 1);
      } catch (_) {}
      for (int c = 1; c <= col; c++) {
        sheet.autoFitColumn(c);
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;

      // Nom de fichier plus descriptif avec date formatée
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final fileName =
          'modele_notes_${_nameController.text}_${_yearController.text}_$formattedDate.xlsx';
      final file = File('$dirPath/$fileName');

      await file.writeAsBytes(bytes, flush: true);

      // Ouvrir automatiquement le fichier
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modèle Excel généré : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur génération modèle Excel : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur génération du modèle : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

String _formatIsoToDisplay(String iso) {
  if (iso.isEmpty) return 'Non renseigné';
  try {
    final d = DateTime.parse(iso);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  } catch (_) {
    return iso;
  }
}

String _calculateAgeFromIso(String iso) {
  if (iso.isEmpty) return 'Non renseigné';
  try {
    final birth = DateTime.parse(iso);
    final now = DateTime.now();
    int age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return '$age ans';
  } catch (_) {
    return 'Non renseigné';
  }
}

class _SubjectColumnMeta {
  final String name;
  final int devoirCol;
  final int coeffDevoirCol;
  final int surDevoirCol;
  final int compoCol;
  final int coeffCompoCol;
  final int surCompoCol;
  final int profCol;
  final int appCol;
  final int moyClasseCol;

  _SubjectColumnMeta({
    required this.name,
    required this.devoirCol,
    required this.coeffDevoirCol,
    required this.surDevoirCol,
    required this.compoCol,
    required this.coeffCompoCol,
    required this.surCompoCol,
    required this.profCol,
    required this.appCol,
    required this.moyClasseCol,
  });
}

class _ArchivedBulletinsView {
  final List<Map<String, dynamic>> reportCards;
  final Map<String, Student> studentsById;

  const _ArchivedBulletinsView({
    required this.reportCards,
    required this.studentsById,
  });
}
