import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/category.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/teacher_assignment.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/widgets/confirm_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:school_manager/screens/categories_modal_content.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';

enum _SubjectsHeaderAction {
  importExcel,
  exportExcel,
  exportPdf,
  manageCategories,
  assignTeachers,
  classSettings,
}

enum _SubjectRowAction { edit, delete }

class SubjectsPage extends StatefulWidget {
  const SubjectsPage({Key? key}) : super(key: key);

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage>
    with TickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  List<Course> _courses = [];
  List<Category> _categories = [];
  bool _loading = true;
  late AnimationController _anim;
  late Animation<double> _fade;
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedCategoryId;
  // Gestion des sections repliées/dépliées
  final Set<String> _collapsedSections = <String>{};
  static const String _uncatKey = '_UNCAT_';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _load();
    _searchController.addListener(
      () =>
          setState(() => _query = _searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Initialiser les catégories par défaut si nécessaire
    await _db.initializeDefaultCategories();
    final courses = await _db.getCourses();
    final categories = await _db.getCategories();
    setState(() {
      _courses = courses;
      _categories = categories;
      _loading = false;
    });
    _anim.forward();
  }

  Future<void> _showCategoriesModal() async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: CategoriesModalContent(onCategoriesChanged: () => _load()),
        ),
      ),
    );
  }

  Future<void> _showTeacherAssignmentsDialog() async {
    final allClasses = await _db.getClasses();
    final allTeachers = await _db.getStaff();
    final teacherOptions = allTeachers
        .where((t) => t.typeRole == 'Professeur')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final years = allClasses.map((c) => c.academicYear).toSet().toList()
      ..sort();
    final currentYear = await getCurrentAcademicYear();
    String selectedYear =
        years.contains(currentYear)
            ? currentYear
            : (years.isNotEmpty ? years.first : '');
    String? selectedClassName;
    List<Course> classCourses = [];
    Map<String, String?> courseTeacherIds = {};
    Map<String, TeacherAssignment> existingByCourseId = {};
    bool didInit = false;
    bool loadingAssignments = false;

    Future<void> loadForSelection(StateSetter setStateSB) async {
      if (loadingAssignments) return;
      loadingAssignments = true;
      if (selectedClassName == null || selectedClassName!.isEmpty) {
        setStateSB(() {
          classCourses = [];
          courseTeacherIds = {};
          existingByCourseId = {};
        });
        loadingAssignments = false;
        return;
      }
      final courses =
          await _db.getCoursesForClass(selectedClassName!, selectedYear);
      final existing = await _db.getTeacherAssignmentsForClass(
        selectedClassName!,
        selectedYear,
      );
      final map = {
        for (final a in existing) a.courseId: a,
      };
      setStateSB(() {
        classCourses = courses;
        existingByCourseId = map;
        courseTeacherIds = {
          for (final c in courses) c.id: map[c.id]?.teacherId,
        };
      });
      loadingAssignments = false;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            final classesForYear = allClasses
                .where((c) => c.academicYear == selectedYear)
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            selectedClassName ??=
                classesForYear.isNotEmpty ? classesForYear.first.name : null;
            if (!didInit && selectedClassName != null) {
              didInit = true;
              loadForSelection(setStateSB);
            }
            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(
                    child: Text('Affecter les professeurs'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedYear.isNotEmpty ? selectedYear : null,
                        decoration: const InputDecoration(
                          labelText: 'Année académique',
                        ),
                        items: years
                            .map(
                              (y) => DropdownMenuItem(
                                value: y,
                                child: Text(y),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setStateSB(() {
                            selectedYear = value;
                            selectedClassName = null;
                            classCourses = [];
                            courseTeacherIds = {};
                            existingByCourseId = {};
                            didInit = false;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedClassName,
                        decoration: const InputDecoration(labelText: 'Classe'),
                        items: classesForYear
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.name,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setStateSB(() {
                            selectedClassName = value;
                          });
                          loadForSelection(setStateSB);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (selectedClassName == null ||
                          selectedClassName!.isEmpty)
                        const Text('Aucune classe disponible.'),
                      if (selectedClassName != null &&
                          classCourses.isEmpty)
                        const Text('Aucune matière associée à cette classe.'),
                      if (classCourses.isNotEmpty)
                        Column(
                          children: classCourses
                              .map(
                                (course) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(course.name),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child:
                                            DropdownButtonFormField<String?>(
                                          value: courseTeacherIds[course.id],
                                          decoration: const InputDecoration(
                                            labelText: 'Professeur',
                                          ),
                                          items: [
                                            const DropdownMenuItem<String?>(
                                              value: null,
                                              child: Text('Non assigné'),
                                            ),
                                            ...teacherOptions.map(
                                              (t) => DropdownMenuItem(
                                                value: t.id,
                                                child: Text(t.name),
                                              ),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            setStateSB(() {
                                              courseTeacherIds[course.id] =
                                                  value;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
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
                ElevatedButton(
                  onPressed: selectedClassName == null
                      ? null
                      : () async {
                          final className = selectedClassName!;
                          final assignments = <TeacherAssignment>[];
                          for (final course in classCourses) {
                            final teacherId =
                                (courseTeacherIds[course.id] ?? '').trim();
                            if (teacherId.isEmpty) continue;
                            final existing = existingByCourseId[course.id];
                            assignments.add(
                              TeacherAssignment(
                                id: existing?.id ?? const Uuid().v4(),
                                teacherId: teacherId,
                                courseId: course.id,
                                className: className,
                                academicYear: selectedYear,
                              ),
                            );
                          }
                          await _db.replaceTeacherAssignmentsForClassYear(
                            className: className,
                            academicYear: selectedYear,
                            assignments: assignments,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Affectations enregistrées.'),
                              ),
                            );
                          }
                          Navigator.of(context).pop();
                        },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportSubjectsToPdf() async {
    try {
      // Demander le répertoire de sauvegarde
      String? directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export annulé'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Obtenir les informations de l'école
      final schoolInfo = await _db.getSchoolInfo();
      if (schoolInfo == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur: Informations de l\'école non trouvées'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final currentAcademicYear = await getCurrentAcademicYear();

      // Générer le PDF
      final bytes = await PdfService.generateSubjectsPdf(
        schoolInfo: schoolInfo,
        academicYear: currentAcademicYear,
        courses: _courses,
        categories: _categories,
        title: 'Liste des Matières',
      );

      // Sauvegarder le fichier
      final fileName =
          'matieres_${currentAcademicYear.replaceAll('/', '_')}.pdf';
      final file = File('$directory/$fileName');
      await file.writeAsBytes(bytes);

      // Ouvrir le fichier
      OpenFile.open(file.path);

      // Notification de succès
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export PDF réussi ! Fichier sauvegardé : $fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Notification d'erreur
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'export PDF : $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _exportSubjectsToExcel() async {
    try {
      // Demander le répertoire de sauvegarde
      String? directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export annulé'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final currentAcademicYear = await getCurrentAcademicYear();

      // Créer le fichier Excel
      final excel = Excel.createExcel();
      final sheet = excel['Matières'];

      // Supprimer la feuille par défaut
      excel.delete('Sheet1');

      // En-tête
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('N°');
      sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
        'Matière',
      );
      sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue(
        'Catégorie',
      );
      sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue(
        'Description',
      );

      // Style de l'en-tête
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.blue50,
        fontColorHex: ExcelColor.blue900,
      );

      sheet.cell(CellIndex.indexByString('A1')).cellStyle = headerStyle;
      sheet.cell(CellIndex.indexByString('B1')).cellStyle = headerStyle;
      sheet.cell(CellIndex.indexByString('C1')).cellStyle = headerStyle;
      sheet.cell(CellIndex.indexByString('D1')).cellStyle = headerStyle;

      // Données des matières
      int rowIndex = 2;
      for (final course in _courses) {
        final category = _categories.firstWhere(
          (cat) => cat.id == course.categoryId,
          orElse: () => Category.empty(),
        );

        sheet.cell(CellIndex.indexByString('A$rowIndex')).value = TextCellValue(
          '${rowIndex - 1}',
        );
        sheet.cell(CellIndex.indexByString('B$rowIndex')).value = TextCellValue(
          course.name,
        );
        sheet.cell(CellIndex.indexByString('C$rowIndex')).value = TextCellValue(
          course.categoryId != null && category.id.isNotEmpty
              ? category.name
              : 'Non classée',
        );
        sheet.cell(CellIndex.indexByString('D$rowIndex')).value = TextCellValue(
          course.description ?? '',
        );

        rowIndex++;
      }

      // Ajuster la largeur des colonnes
      sheet.setColumnWidth(0, 8); // N°
      sheet.setColumnWidth(1, 25); // Matière
      sheet.setColumnWidth(2, 20); // Catégorie
      sheet.setColumnWidth(3, 35); // Description

      // Sauvegarder le fichier
      final fileName =
          'matieres_${currentAcademicYear.replaceAll('/', '_')}.xlsx';
      final file = File('$directory/$fileName');
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        OpenFile.open(file.path);

        // Notification de succès
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Export Excel réussi ! Fichier sauvegardé : $fileName',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('Erreur lors de la génération du fichier Excel');
      }
    } catch (e) {
      // Notification d'erreur
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'export Excel : $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _normalizeKey(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  double? _tryParseDouble(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  Future<void> _importSubjectsFromExcel() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: false,
      );
      if (res == null || res.files.isEmpty) return;

      final path = res.files.single.path;
      if (path == null || path.isEmpty) {
        throw Exception('Fichier invalide (chemin manquant)');
      }

      final bytes = await File(path).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final Sheet? sheet = excel.tables['Matières'] ??
          (excel.tables.values.isNotEmpty ? excel.tables.values.first : null);
      if (sheet == null) throw Exception('Aucune feuille trouvée');

      int? colName;
      int? colCategory;
      int? colDescription;

      final header = sheet.rows.isNotEmpty ? sheet.rows.first : null;
      if (header == null) throw Exception('Fichier Excel vide');

      for (int i = 0; i < header.length; i++) {
        final cell = header[i]?.value?.toString() ?? '';
        final h = _normalizeKey(cell);
        if (h == 'matière' || h == 'matiere' || h == 'subject' || h == 'name') {
          colName = i;
        } else if (h == 'catégorie' || h == 'categorie' || h == 'category') {
          colCategory = i;
        } else if (h == 'description' || h == 'desc') {
          colDescription = i;
        }
      }

      if (colName == null) {
        throw Exception('Colonne "Matière" introuvable (ligne 1)');
      }

      final existingByName = <String, Course>{};
      for (final c in _courses) {
        existingByName[_normalizeKey(c.name)] = c;
      }

      final categoriesByName = <String, Category>{};
      for (final cat in _categories) {
        categoriesByName[_normalizeKey(cat.name)] = cat;
      }

      final importedRows = <Map<String, String?>>[];
      int duplicatesInFile = 0;
      final seenNames = <String>{};

      for (int r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        final rawName = (row[colName!]?.value?.toString() ?? '').trim();
        if (rawName.isEmpty) continue;

        final nameKey = _normalizeKey(rawName);
        if (seenNames.contains(nameKey)) {
          duplicatesInFile++;
          continue;
        }
        seenNames.add(nameKey);

        final rawCategory = colCategory != null
            ? (row[colCategory!]?.value?.toString() ?? '').trim()
            : '';
        final rawDescription = colDescription != null
            ? (row[colDescription!]?.value?.toString() ?? '').trim()
            : '';

        importedRows.add({
          'name': rawName,
          'category': rawCategory.isEmpty ? null : rawCategory,
          'description': rawDescription.isEmpty ? null : rawDescription,
        });
      }

      int toInsert = 0;
      int toUpdate = 0;
      for (final row in importedRows) {
        final nameKey = _normalizeKey(row['name'] ?? '');
        if (existingByName.containsKey(nameKey)) {
          toUpdate++;
        } else {
          toInsert++;
        }
      }

      final choice = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Importer les matières'),
          content: Text(
            'Nouvelles: $toInsert\nDoublons (déjà existants): $toUpdate\nDoublons ignorés (dans le fichier): $duplicatesInFile\n\nVoulez-vous mettre à jour les doublons existants ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(null),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Ignorer doublons'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Mettre à jour doublons'),
            ),
          ],
        ),
      );
      if (choice == null) return;

      int inserted = 0;
      int updated = 0;
      int skipped = 0;
      int unknownCategories = 0;

      for (final row in importedRows) {
        final name = (row['name'] ?? '').trim();
        if (name.isEmpty) continue;

        final catName = row['category'];
        String? categoryId;
        if (catName != null && catName.trim().isNotEmpty) {
          final cat = categoriesByName[_normalizeKey(catName)];
          if (cat != null) {
            categoryId = cat.id;
          } else {
            unknownCategories++;
            categoryId = null;
          }
        }

        final desc = row['description'];
        final nameKey = _normalizeKey(name);
        final existing = existingByName[nameKey];
        if (existing == null) {
          final course = Course(
            id: const Uuid().v4(),
            name: name,
            description: desc,
            categoryId: categoryId,
          );
          await _db.insertCourse(course);
          inserted++;
        } else {
          if (!choice) {
            skipped++;
            continue;
          }
          final updatedCourse = existing.copyWith(
            name: name,
            description: desc,
            categoryId: categoryId,
          );
          await _db.updateCourse(existing.id, updatedCourse);
          updated++;
        }
      }

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import terminé: $inserted ajoutées, $updated mises à jour, $skipped ignorées'
            '${unknownCategories > 0 ? ' ($unknownCategories catégories inconnues)' : ''}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur import Excel : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showClassSettingsDialog() async {
    final classes = await _db.getClasses();
    final currentYear = await getCurrentAcademicYear();
    if (!mounted) return;

    final years =
        classes.map((c) => c.academicYear).toSet().toList()..sort((a, b) => b.compareTo(a));
    String selectedYear =
        years.contains(currentYear) ? currentYear : (years.isNotEmpty ? years.first : currentYear);
    String? selectedClassName;

    List<Class> classesForYear() {
      final list = classes.where((c) => c.academicYear == selectedYear).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return list;
    }

    final availableYears = years.isNotEmpty ? years : [currentYear];
    final initialClasses = classesForYear();
    if (initialClasses.isNotEmpty) {
      selectedClassName = initialClasses.first.name;
    }

    String? addCourseId;
    final coeffControllers = <String, TextEditingController>{};
    final hoursControllers = <String, TextEditingController>{};
    List<Map<String, dynamic>> settingsRows = [];
    final assignedCourseIds = <String>{};

    Future<void> loadSettings(StateSetter setState) async {
      if (selectedClassName == null) {
        setState(() {
          settingsRows = [];
          assignedCourseIds.clear();
        });
        return;
      }
      final rows = await _db.getClassCourseSettings(
        className: selectedClassName!,
        academicYear: selectedYear,
      );
      setState(() {
        settingsRows = rows;
        assignedCourseIds
          ..clear()
          ..addAll(rows.map((r) => r['id'] as String));
      });
    }

    try {
      if (selectedClassName != null) {
        settingsRows = await _db.getClassCourseSettings(
          className: selectedClassName!,
          academicYear: selectedYear,
        );
        assignedCourseIds
          ..clear()
          ..addAll(settingsRows.map((r) => r['id'] as String));
      }

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            final yearClasses = classesForYear();
            final addableCourses =
                _courses.where((c) => !assignedCourseIds.contains(c.id)).toList()
                  ..sort((a, b) => a.name.compareTo(b.name));

            Future<void> addMany() async {
              if (selectedClassName == null || addableCourses.isEmpty) return;
              final pickedIds = await _pickMultipleCoursesDialog(
                title: 'Ajouter des matières',
                courses: addableCourses,
              );
              if (pickedIds == null || pickedIds.isEmpty) return;
              for (final id in pickedIds) {
                await _db.addCourseToClass(selectedClassName!, selectedYear, id);
              }
              await loadSettings(setState);
            }
            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(
                    child: Text('Coefficients & volumes horaires (par classe)'),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              content: SizedBox(
                width: 900,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedYear,
                            decoration: const InputDecoration(
                              labelText: 'Année académique',
                              border: OutlineInputBorder(),
                            ),
                            items: availableYears
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(y),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) async {
                              if (v == null) return;
                              setState(() {
                                selectedYear = v;
                                final list = classesForYear();
                                selectedClassName =
                                    list.isNotEmpty ? list.first.name : null;
                                addCourseId = null;
                              });
                              await loadSettings(setState);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedClassName,
                            decoration: const InputDecoration(
                              labelText: 'Classe',
                              border: OutlineInputBorder(),
                            ),
                            items: yearClasses
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.name,
                                    child: Text(c.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) async {
                              setState(() {
                                selectedClassName = v;
                                addCourseId = null;
                              });
                              await loadSettings(setState);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: addCourseId,
                            hint: const Text('Sélectionner...'),
                            decoration: const InputDecoration(
                              labelText: 'Ajouter une matière',
                              border: OutlineInputBorder(),
                            ),
                            items: addableCourses
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (courseId) async {
                              if (courseId == null ||
                                  selectedClassName == null) {
                                return;
                              }
                              setState(() => addCourseId = courseId);
                              await _db.addCourseToClass(
                                selectedClassName!,
                                selectedYear,
                                courseId,
                              );
                              setState(() => addCourseId = null);
                              await loadSettings(setState);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: selectedClassName == null ||
                                  addableCourses.isEmpty
                              ? null
                              : addMany,
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Sélection multiple'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedClassName == null)
                      const Text('Aucune classe disponible pour cette année.')
                    else
                      Flexible(
                        child: settingsRows.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Aucune matière affectée à cette classe.',
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: settingsRows.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (ctx2, i) {
                                  final row = settingsRows[i];
                                  final course = Course.fromMap(row);
                                  final num? coeffNum = row['coefficient'] as num?;
                                  final num? hoursNum = row['weeklyHours'] as num?;
                                  final coeffCtrl = coeffControllers.putIfAbsent(
                                    course.id,
                                    () => TextEditingController(
                                      text: (coeffNum?.toDouble() ?? 1.0)
                                          .toString(),
                                    ),
                                  );
                                  final hoursCtrl = hoursControllers.putIfAbsent(
                                    course.id,
                                    () => TextEditingController(
                                      text: (hoursNum?.toDouble() ?? 0.0)
                                          .toString(),
                                    ),
                                  );
                                  return ListTile(
                                    title: Text(course.name),
                                    subtitle: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: coeffCtrl,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                            decoration: const InputDecoration(
                                              labelText: 'Coefficient',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextField(
                                            controller: hoursCtrl,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                            decoration: const InputDecoration(
                                              labelText: 'Volume hebdo (h)',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Wrap(
                                      spacing: 8,
                                      children: [
                                        IconButton(
                                          tooltip: 'Enregistrer',
                                          icon: const Icon(Icons.save_outlined),
                                          onPressed: () async {
                                            final coeff = _tryParseDouble(
                                              coeffCtrl.text,
                                            );
                                            final hours = _tryParseDouble(
                                              hoursCtrl.text,
                                            );
                                            if (coeff == null ||
                                                coeff <= 0 ||
                                                hours == null ||
                                                hours < 0) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Valeurs invalides (coef > 0, heures >= 0)',
                                                  ),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                              return;
                                            }
                                            await _db.upsertClassCourseSettings(
                                              className: selectedClassName!,
                                              academicYear: selectedYear,
                                              courseId: course.id,
                                              coefficient: coeff,
                                              weeklyHours: hours,
                                            );
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text('Enregistré'),
                                                backgroundColor: Colors.green,
                                                duration: Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                        ),
                                        IconButton(
                                          tooltip: 'Retirer',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () async {
                                            await _db.removeCourseFromClass(
                                              selectedClassName!,
                                              selectedYear,
                                              course.id,
                                            );
                                            coeffControllers.remove(course.id)?.dispose();
                                            hoursControllers.remove(course.id)?.dispose();
                                            await loadSettings(setState);
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Fermer'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      for (final c in coeffControllers.values) {
        c.dispose();
      }
      for (final c in hoursControllers.values) {
        c.dispose();
      }
    }
  }

  Future<Set<String>?> _pickMultipleCoursesDialog({
    required String title,
    required List<Course> courses,
  }) async {
    final searchCtrl = TextEditingController();
    String query = '';
    String? categoryFilter;
    final selected = <String>{};

    try {
      return await showDialog<Set<String>>(
        context: context,
        builder: (d) => StatefulBuilder(
          builder: (d, setState) {
            final filtered = courses.where((c) {
              final matchesQuery = query.isEmpty ||
                  c.name.toLowerCase().contains(query.toLowerCase());
              final matchesCategory = categoryFilter == null ||
                  (categoryFilter == _uncatKey
                      ? c.categoryId == null
                      : c.categoryId == categoryFilter);
              return matchesQuery && matchesCategory;
            }).toList()
              ..sort((a, b) => a.name.compareTo(b.name));

            final categoriesSorted = [..._categories]
              ..sort((a, b) => a.name.compareTo(b.name));

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 700,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Rechercher',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) =>
                                setState(() => query = v.trim()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 240,
                          child: DropdownButtonFormField<String>(
                            value: categoryFilter,
                            decoration: const InputDecoration(
                              labelText: 'Catégorie',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('Toutes'),
                              ),
                              const DropdownMenuItem<String>(
                                value: _uncatKey,
                                child: Text('Non classée'),
                              ),
                              ...categoriesSorted.map(
                                (cat) => DropdownMenuItem<String>(
                                  value: cat.id,
                                  child: Text(cat.name),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() => categoryFilter = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: filtered.isEmpty
                              ? null
                              : () => setState(() {
                                    for (final c in filtered) {
                                      selected.add(c.id);
                                    }
                                  }),
                          child: const Text('Tout sélectionner (filtré)'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => setState(selected.clear),
                          child: const Text('Tout désélectionner'),
                        ),
                        const Spacer(),
                        Text(
                          '${selected.length} sélectionnée(s)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Aucune matière'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final c = filtered[i];
                                final isSelected = selected.contains(c.id);
                                return CheckboxListTile(
                                  value: isSelected,
                                  title: Text(c.name),
                                  subtitle: (c.description ?? '').trim().isEmpty
                                      ? null
                                      : Text(c.description!),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      selected.add(c.id);
                                    } else {
                                      selected.remove(c.id);
                                    }
                                  }),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(d).pop(),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.of(d).pop(selected),
                  child: Text('Ajouter (${selected.length})'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      searchCtrl.dispose();
    }
  }

  Future<void> _showAddEditDialog({Course? course}) async {
    final isEdit = course != null;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: course?.name ?? '');
    final descController = TextEditingController(
      text: course?.description ?? '',
    );
    String? selectedCategoryId = course?.categoryId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => CustomDialog(
          title: isEdit ? 'Modifier la matière' : 'Ajouter une matière',
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomFormField(
                  controller: nameController,
                  labelText: 'Nom de la matière',
                  hintText: 'Ex: Mathématiques',
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                CustomFormField(
                  controller: descController,
                  labelText: 'Description (optionnelle)',
                  hintText: 'Ex: Tronc commun, avancé...',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Catégorie (optionnelle)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Aucune catégorie'),
                    ),
                    ..._categories.map(
                      (category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(
                                  int.parse(
                                    category.color.replaceFirst('#', '0xff'),
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(category.name),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => selectedCategoryId = value),
                ),
              ],
            ),
          ),
          onSubmit: null,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            if (isEdit)
              TextButton(
                onPressed: () async {
                  final confirm = await showDangerConfirmDialog(
                    context,
                    title: 'Supprimer la matière ?',
                    message: '“${course.name}” sera supprimée. Cette action est irréversible.',
                  );
                  if (confirm == true) {
                    await _db.deleteCourse(course.id);
                    await _load();
                    if (mounted) Navigator.of(context).pop();
                  }
                },
                child: const Text(
                  'Supprimer',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final name = nameController.text.trim();
                final desc = descController.text.trim();
                if (isEdit) {
                  final updated = Course(
                    id: course.id,
                    name: name,
                    description: desc.isNotEmpty ? desc : null,
                    categoryId: selectedCategoryId,
                  );
                  await _db.updateCourse(course.id, updated);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Matière "${name}" modifiée avec succès'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } else {
                  final exists = _courses.any(
                    (c) => c.name.toLowerCase() == name.toLowerCase(),
                  );
                  if (exists) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cette matière existe déjà.'),
                      ),
                    );
                    return;
                  }
                  final created = Course(
                    id: const Uuid().v4(),
                    name: name,
                    description: desc.isNotEmpty ? desc : null,
                    categoryId: selectedCategoryId,
                  );
                  await _db.insertCourse(created);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Matière "${name}" ajoutée avec succès'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
                await _load();
                if (mounted) Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              child: Text(isEdit ? 'Modifier' : 'Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final filtered = _courses.where((c) {
      final matchesQuery =
          _query.isEmpty || c.name.toLowerCase().contains(_query);
      final matchesCategory =
          _selectedCategoryId == null || c.categoryId == _selectedCategoryId;
      return matchesQuery && matchesCategory;
    }).toList();
    // Group by catégorie (incluant "Non classée")
    final Map<String?, List<Course>> grouped = {};
    for (final c in filtered) {
      grouped.putIfAbsent(c.categoryId, () => []).add(c);
    }
    // Ordre des sections: catégories dans l'ordre, puis Non classée si présente
    final List<String?> orderedGroupKeys = [];
    if (_selectedCategoryId != null) {
      if (grouped.containsKey(_selectedCategoryId))
        orderedGroupKeys.add(_selectedCategoryId);
    } else {
      for (final cat in _categories) {
        if (grouped.containsKey(cat.id)) orderedGroupKeys.add(cat.id);
      }
    }
    if (grouped.containsKey(null)) orderedGroupKeys.add(null);
    return FadeTransition(
      opacity: _fade,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme, isDesktop),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showAddEditDialog(),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'Ajouter une matière',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Filtrer par catégorie',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Toutes les catégories'),
                      ),
                      ..._categories.map(
                        (category) => DropdownMenuItem<String>(
                          value: category.id,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Color(
                                    int.parse(
                                      category.color.replaceFirst('#', '0xff'),
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(category.name),
                            ],
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedCategoryId = value),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    // Déplier toutes les sections visibles
                    setState(() => _collapsedSections.clear());
                  },
                  icon: const Icon(Icons.unfold_more),
                  label: const Text('Tout déplier'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    // Replier toutes les sections visibles (selon le filtre/recherche)
                    final keys = _courses
                        .where((c) {
                          final matchesQuery =
                              _query.isEmpty ||
                              c.name.toLowerCase().contains(_query);
                          final matchesCategory =
                              _selectedCategoryId == null ||
                              c.categoryId == _selectedCategoryId;
                          return matchesQuery && matchesCategory;
                        })
                        .map((c) => c.categoryId ?? _uncatKey)
                        .toSet();
                    setState(() {
                      _collapsedSections
                        ..clear()
                        ..addAll(keys);
                    });
                  },
                  icon: const Icon(Icons.unfold_less),
                  label: const Text('Tout replier'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.2),
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _query.isNotEmpty || _selectedCategoryId != null
                                  ? Icons.search_off
                                  : Icons.book_outlined,
                              size: 64,
                              color: theme.iconTheme.color?.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _query.isNotEmpty || _selectedCategoryId != null
                                  ? 'Aucune matière trouvée'
                                  : 'Aucune matière enregistrée',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: theme.textTheme.bodyLarge?.color
                                    ?.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _query.isNotEmpty || _selectedCategoryId != null
                                  ? 'Essayez de modifier vos critères de recherche'
                                  : 'Commencez par ajouter votre première matière',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () => _showAddEditDialog(),
                              icon: const Icon(Icons.add, color: Colors.white),
                              label: const Text(
                                'Ajouter une matière',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.2),
                        ),
                      ),
                      child: ListView.builder(
                        itemCount: orderedGroupKeys.length,
                        itemBuilder: (ctx, sidx) {
                          final key = orderedGroupKeys[sidx];
                          final List<Course> items = grouped[key] ?? [];
                          Category? cat;
                          bool hasCat = false;
                          if (key != null) {
                            cat = _categories.firstWhere(
                              (c) => c.id == key,
                              orElse: () => Category.empty(),
                            );
                            hasCat = cat.id.isNotEmpty;
                          }
                          final String sectionName = hasCat
                              ? cat!.name
                              : 'Non classée';
                          final Color sectionColor = hasCat
                              ? Color(
                                  int.parse(
                                    cat!.color.replaceFirst('#', '0xff'),
                                  ),
                                )
                              : Colors.blueGrey;
                          final String sectionKey = key ?? _uncatKey;
                          final bool isCollapsed = _collapsedSections.contains(
                            sectionKey,
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8.0,
                              horizontal: 8.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isCollapsed) {
                                        _collapsedSections.remove(sectionKey);
                                      } else {
                                        _collapsedSections.add(sectionKey);
                                      }
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: sectionColor,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$sectionName (${items.length})',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ),
                                      Icon(
                                        isCollapsed
                                            ? Icons.expand_more
                                            : Icons.expand_less,
                                        color: theme.iconTheme.color,
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isCollapsed) ...[
                                  const SizedBox(height: 8),
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) => Divider(
                                      color: theme.dividerColor.withOpacity(
                                        0.3,
                                      ),
                                      height: 1,
                                    ),
                                    itemBuilder: (ctx2, i) {
                                      final c = items[i];
                                      final hasCategory = hasCat;
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: hasCategory
                                              ? sectionColor
                                              : const Color(0xFF6366F1),
                                          child: const Icon(
                                            Icons.book,
                                            color: Colors.white,
                                          ),
                                        ),
                                        title: Text(
                                          c.name,
                                          style: TextStyle(
                                            color: theme
                                                .textTheme
                                                .bodyLarge
                                                ?.color,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (c.description != null &&
                                                c.description!.isNotEmpty)
                                              Text(
                                                c.description!,
                                                style: TextStyle(
                                                  color: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.color,
                                                ),
                                              ),
                                            if (hasCategory)
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: sectionColor,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            2,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    sectionName,
                                                    style: TextStyle(
                                                      color: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.color
                                                          ?.withOpacity(0.7),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                        trailing:
                                            PopupMenuButton<_SubjectRowAction>(
                                          onSelected: (action) async {
                                            if (action ==
                                                _SubjectRowAction.edit) {
                                              _showAddEditDialog(course: c);
                                              return;
                                            }
                                            if (action ==
                                                _SubjectRowAction.delete) {
                                              final confirm =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (d) => AlertDialog(
                                                  title: const Text(
                                                    'Supprimer la matière ?',
                                                  ),
                                                  content: const Text(
                                                    'Cette action est irréversible.',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(d).pop(
                                                        false,
                                                      ),
                                                      child: const Text(
                                                        'Annuler',
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () =>
                                                          Navigator.of(d).pop(
                                                        true,
                                                      ),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            Colors.red,
                                                        foregroundColor:
                                                            Colors.white,
                                                      ),
                                                      child: const Text(
                                                        'Supprimer',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                await _db.deleteCourse(c.id);
                                                await _load();
                                              }
                                            }
                                          },
                                          itemBuilder: (ctx) => const [
                                            PopupMenuItem(
                                              value: _SubjectRowAction.edit,
                                              child: ListTile(
                                                leading: Icon(
                                                  Icons.edit_outlined,
                                                  color: Color(0xFF6366F1),
                                                ),
                                                title: Text('Modifier'),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: _SubjectRowAction.delete,
                                              child: ListTile(
                                                leading: Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red,
                                                ),
                                                title: Text('Supprimer'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.all(24),
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.book,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des Matières',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Créez et gérez les matières avec leurs catégories personnalisables.',
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
                  PopupMenuButton<_SubjectsHeaderAction>(
                    tooltip: 'Actions',
                    onSelected: (action) {
                      switch (action) {
                        case _SubjectsHeaderAction.importExcel:
                          _importSubjectsFromExcel();
                          break;
                        case _SubjectsHeaderAction.exportExcel:
                          _exportSubjectsToExcel();
                          break;
                        case _SubjectsHeaderAction.exportPdf:
                          _exportSubjectsToPdf();
                          break;
                        case _SubjectsHeaderAction.manageCategories:
                          _showCategoriesModal();
                          break;
                        case _SubjectsHeaderAction.assignTeachers:
                          _showTeacherAssignmentsDialog();
                          break;
                        case _SubjectsHeaderAction.classSettings:
                          _showClassSettingsDialog();
                          break;
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(
                        value: _SubjectsHeaderAction.importExcel,
                        child: ListTile(
                          leading: Icon(Icons.upload_file),
                          title: Text('Importer Excel'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _SubjectsHeaderAction.exportExcel,
                        child: ListTile(
                          leading: Icon(Icons.table_chart),
                          title: Text('Exporter Excel'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _SubjectsHeaderAction.exportPdf,
                        child: ListTile(
                          leading: Icon(Icons.picture_as_pdf),
                          title: Text('Exporter PDF'),
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: _SubjectsHeaderAction.classSettings,
                        child: ListTile(
                          leading: Icon(Icons.tune),
                          title: Text('Coef & volumes (par classe)'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _SubjectsHeaderAction.assignTeachers,
                        child: ListTile(
                          leading: Icon(Icons.person_pin),
                          title: Text('Affecter professeurs'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _SubjectsHeaderAction.manageCategories,
                        child: ListTile(
                          leading: Icon(Icons.category),
                          title: Text('Catégories'),
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.more_horiz, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Actions',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Rechercher une matière...',
              hintStyle: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
              filled: true,
              fillColor: theme.cardColor,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 16,
              ),
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
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
