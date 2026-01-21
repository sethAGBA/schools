import 'package:flutter/material.dart';
import 'package:school_manager/screens/dashboard_home.dart';
import 'dart:convert';
import 'dart:io';

import 'package:school_manager/constants/colors.dart';
import 'package:school_manager/constants/sizes.dart';
import 'package:school_manager/constants/strings.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/screens/students/class_details_page.dart';
import 'package:school_manager/screens/students/widgets/chart_card.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:school_manager/screens/students/widgets/student_registration_form.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/students/student_profile_page.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/student_id_card_service.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/screens/students/re_enrollment_batch_dialog.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:uuid/uuid.dart';

class StudentsPage extends StatefulWidget {
  @override
  _StudentsPageState createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  final DatabaseService _dbService = DatabaseService();
  final GlobalKey<PopupMenuButtonState<String>> _importExportMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  Map<String, int> _classDistribution = {};
  Map<String, int> _academicYearDistribution = {};
  List<Map<String, dynamic>> _tableData = [];
  List<Student> _allStudents = []; // Store all students for search
  List<Class> _allClasses = [];

  // Filtres sélectionnés
  String? _selectedClassFilter;
  String? _selectedGenderFilter;
  String? _selectedYearFilter;
  String? _selectedLevelFilter;

  String _classKey(Class cls) => '${cls.name}:::${cls.academicYear}';
  String _classLabel(Class cls) => '${cls.name} (${cls.academicYear})';
  String _normalizeLevel(String? level) {
    final v = (level ?? '').trim();
    return v.isNotEmpty ? v : 'Non défini';
  }
  Class? _classFromKey(String? key, List<Class> classes) {
    if (key == null) return null;
    final parts = key.split(':::');
    if (parts.length != 2) return null;
    final name = parts.first;
    final year = parts.last;
    for (final cls in classes) {
      if (cls.name == name && cls.academicYear == year) {
        return cls;
      }
    }
    return null;
  }

  String _searchQuery = '';
  String _currentAcademicYear = '2024-2025';
  bool _showStudentView = false; // Toggle between class view and student view

  bool _importing = false;
  bool _exporting = false;
  String _visibilityFilter = 'active'; // 'active' | 'deleted' | 'all'
  bool _selectionMode = false;
  final Set<String> _selectedStudentIds = <String>{};

  @override
  void initState() {
    super.initState();
    academicYearNotifier.addListener(_onAcademicYearChanged);
    getCurrentAcademicYear().then((year) {
      setState(() {
        _currentAcademicYear = year;
        if (_selectedYearFilter == null) {
          _selectedYearFilter = year;
        }
      });
      _loadData();
    });
  }

  void _onAcademicYearChanged() {
    setState(() {
      _currentAcademicYear = academicYearNotifier.value;
      _selectedYearFilter = academicYearNotifier.value;
    });
    _loadData();
  }

  @override
  void dispose() {
    academicYearNotifier.removeListener(_onAcademicYearChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    final classDist = await _dbService.getClassDistribution();
    final yearDist = await _dbService.getAcademicYearDistribution();
    final bool includeDeleted = _visibilityFilter == 'all';
    final bool onlyDeleted = _visibilityFilter == 'deleted';
    final students = await _dbService.getStudents(
      includeDeleted: includeDeleted || onlyDeleted,
      onlyDeleted: onlyDeleted,
    );
    final classes = await _dbService.getClasses();

    // Store all students for search functionality
    setState(() {
      _allStudents = students;
      _allClasses = classes;
      if (_visibilityFilter != 'active') {
        // When viewing deleted/all, student selection mode is more useful; keep selection.
      } else {
        // Prune selection for students no longer visible.
        _selectedStudentIds.removeWhere(
          (id) => !students.any((s) => s.id == id),
        );
      }
    });

    final tableData = classes.map((cls) {
      final key = _classKey(cls);
      final label = _classLabel(cls);
      // Compter uniquement les élèves de l'année académique de la classe
      final filteredStudents = students
          .where(
            (s) =>
                s.className == cls.name && s.academicYear == cls.academicYear,
          )
          .toList();
      final studentCount = filteredStudents.length;
      final boys = filteredStudents.where((s) => s.gender == 'M').length;
      final girls = filteredStudents.where((s) => s.gender == 'F').length;
      final level = _normalizeLevel(cls.level);
      return {
        'classKey': key,
        'classLabel': label,
        'className': cls.name,
        'total': studentCount.toString(),
        'boys': boys.toString(),
        'girls': girls.toString(),
        'year': cls.academicYear,
        'level': level,
      };
    }).toList();

    setState(() {
      _classDistribution = classDist;
      _academicYearDistribution = yearDist;
      _tableData = tableData;
      if (_selectedClassFilter != null) {
        final exists = tableData.any(
          (row) => row['classKey'] == _selectedClassFilter,
        );
        if (!exists) {
          _selectedClassFilter = null;
        }
      }
    });
  }

  List<Map<String, dynamic>> get _filteredTableData {
    return _tableData.where((data) {
      final matchClass =
          _selectedClassFilter == null ||
          data['classKey'] == _selectedClassFilter;
      final matchYear =
          _selectedYearFilter == null || data['year'] == _selectedYearFilter;
      final matchLevel =
          _selectedLevelFilter == null ||
          data['level'] == _selectedLevelFilter;
      if (_selectedGenderFilter != null) {
        if (_selectedGenderFilter == 'M' && data['boys'] == '0') return false;
        if (_selectedGenderFilter == 'F' && data['girls'] == '0') return false;
      }

      // Enhanced search: include student names
      final matchSearch = _searchQuery.isEmpty || _matchesSearchQuery(data);

      return matchClass && matchYear && matchLevel && matchSearch;
    }).toList();
  }

  bool _isSearchingByStudentName(String query) {
    if (query.isEmpty) return false;

    final lowerQuery = query.toLowerCase();

    // Check if query matches any student name
    final matchingStudents = _allStudents
        .where((student) => student.name.toLowerCase().contains(lowerQuery))
        .toList();

    // If we found students and the query doesn't match class names, show student view
    if (matchingStudents.isNotEmpty) {
      // Check if query also matches class names
      final matchingClasses = _tableData.where((data) {
        final classLabel = (data['classLabel'] as String).toLowerCase();
        final year = data['year'].toLowerCase();
        return classLabel.contains(lowerQuery) || year.contains(lowerQuery);
      }).toList();

      // If no class matches, definitely show student view
      if (matchingClasses.isEmpty) {
        return true;
      }

      // If both students and classes match, prefer student view for personal names
      // (assuming personal names are more specific than class names)
      return true;
    }

    return false;
  }

  bool _matchesSearchQuery(Map<String, dynamic> data) {
    if (_searchQuery.isEmpty) return true;

    final query = _searchQuery.toLowerCase();

    // Search in class name and year
    final classLabel = (data['classLabel'] as String).toLowerCase();
    final year = data['year'].toLowerCase();

    if (classLabel.contains(query) || year.contains(query)) {
      return true;
    }

    // Search in student names for this class
    final className = data['className'] as String;
    final classYear = data['year'] as String;

    final studentsInClass = _allStudents
        .where(
          (student) =>
              student.className == className &&
              student.academicYear == classYear,
        )
        .toList();

    return studentsInClass.any(
      (student) => student.name.toLowerCase().contains(query),
    );
  }

  String _normalizeDupPart(String v) {
    return v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _studentDupKey({
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String contactNumber,
  }) {
    return [
      _normalizeDupPart(firstName),
      _normalizeDupPart(lastName),
      _normalizeDupPart(dateOfBirth),
      _normalizeDupPart(contactNumber),
    ].join('|');
  }

  ({String className, String academicYear})? _selectedClassAndYearFromFilter() {
    final key = _selectedClassFilter;
    if (key == null) return null;
    final parts = key.split(':::');
    if (parts.length != 2) return null;
    return (className: parts[0], academicYear: parts[1]);
  }

  List<Student> _studentsMatchingCurrentFilters() {
    final selectedYear = _selectedYearFilter;
    final selectedGender = _selectedGenderFilter;
    final classAndYear = _selectedClassAndYearFromFilter();
    final query = _searchQuery.trim().toLowerCase();
    final levelByClass = <String, String>{
      for (final c in _allClasses)
        '${c.name}:::${c.academicYear}': _normalizeLevel(c.level),
    };

    return _allStudents.where((s) {
      if (_visibilityFilter == 'active' && s.isDeleted) return false;
      if (_visibilityFilter == 'deleted' && !s.isDeleted) return false;
      if (selectedYear != null && selectedYear.isNotEmpty) {
        if (s.academicYear != selectedYear) return false;
      }
      if (selectedGender != null && selectedGender.isNotEmpty) {
        if (s.gender != selectedGender) return false;
      }
      if (classAndYear != null) {
        if (s.className != classAndYear.className) return false;
        if (s.academicYear != classAndYear.academicYear) return false;
      }
      if (_selectedLevelFilter != null &&
          _selectedLevelFilter!.isNotEmpty) {
        final key = '${s.className}:::${s.academicYear}';
        final level = levelByClass[key] ?? 'Non défini';
        if (level != _selectedLevelFilter) return false;
      }
      if (query.isNotEmpty) {
        final hay = [
          s.name,
          s.id,
          s.className,
          s.academicYear,
          s.contactNumber,
          s.guardianName,
        ].join(' ').toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportStudentsCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final students = _studentsMatchingCurrentFilters();
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return;

      final year = _selectedYearFilter ?? _currentAcademicYear;
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('$dir/eleves_${year}_$ts.csv');

      final rows = <List<dynamic>>[
        [
          'id',
          'matricule',
          'firstName',
          'lastName',
          'dateOfBirth',
          'placeOfBirth',
          'gender',
          'address',
          'contactNumber',
          'email',
          'emergencyContact',
          'guardianName',
          'guardianContact',
          'className',
          'academicYear',
          'enrollmentDate',
          'status',
          'medicalInfo',
        ],
        ...students.map((s) {
          return [
            s.id,
            s.matricule ?? '',
            s.firstName,
            s.lastName,
            s.dateOfBirth,
            s.placeOfBirth ?? '',
            s.gender,
            s.address,
            s.contactNumber,
            s.email,
            s.emergencyContact,
            s.guardianName,
            s.guardianContact,
            s.className,
            s.academicYear,
            s.enrollmentDate,
            s.status,
            s.medicalInfo ?? '',
          ];
        }),
      ];

      final csv = const ListToCsvConverter().convert(rows);
      await file.writeAsString(csv, encoding: utf8);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export CSV réussi: ${file.path.split('/').last}')),
      );
      await OpenFile.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur export CSV: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportStudentsExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final students = _studentsMatchingCurrentFilters();
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return;

      final year = _selectedYearFilter ?? _currentAcademicYear;
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('$dir/eleves_${year}_$ts.xlsx');

      final excel = ex.Excel.createExcel();
      final sheet = excel['Élèves'];
      sheet.appendRow([
        ex.TextCellValue('ID'),
        ex.TextCellValue('Matricule'),
        ex.TextCellValue('Prénom(s)'),
        ex.TextCellValue('Nom'),
        ex.TextCellValue('Date naissance'),
        ex.TextCellValue('Lieu naissance'),
        ex.TextCellValue('Sexe'),
        ex.TextCellValue('Adresse'),
        ex.TextCellValue('Téléphone'),
        ex.TextCellValue('Email'),
        ex.TextCellValue('Contact urgence'),
        ex.TextCellValue('Tuteur'),
        ex.TextCellValue('Téléphone tuteur'),
        ex.TextCellValue('Classe'),
        ex.TextCellValue('Année'),
        ex.TextCellValue('Date inscription'),
        ex.TextCellValue('Statut'),
        ex.TextCellValue('Info médicale'),
      ]);
      for (final s in students) {
        sheet.appendRow([
          ex.TextCellValue(s.id),
          ex.TextCellValue(s.matricule ?? ''),
          ex.TextCellValue(s.firstName),
          ex.TextCellValue(s.lastName),
          ex.TextCellValue(s.dateOfBirth),
          ex.TextCellValue(s.placeOfBirth ?? ''),
          ex.TextCellValue(s.gender),
          ex.TextCellValue(s.address),
          ex.TextCellValue(s.contactNumber),
          ex.TextCellValue(s.email),
          ex.TextCellValue(s.emergencyContact),
          ex.TextCellValue(s.guardianName),
          ex.TextCellValue(s.guardianContact),
          ex.TextCellValue(s.className),
          ex.TextCellValue(s.academicYear),
          ex.TextCellValue(s.enrollmentDate),
          ex.TextCellValue(s.status),
          ex.TextCellValue(s.medicalInfo ?? ''),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Impossible de générer le fichier Excel');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export Excel réussi: ${file.path.split('/').last}')),
      );
      await OpenFile.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur export Excel: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importStudents() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('Impossible de lire le fichier.');

      final import = await _parseImportFile(
        fileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => _StudentsImportDialog(
          import: import,
          onConfirmImport: (options) async {
            final toInsert = import.rows.where((r) {
              if (r.issues.isNotEmpty && options.skipInvalid) return false;
              if (!options.includeDuplicates &&
                  (r.isDuplicateExisting || r.isDuplicateInFile)) {
                return false;
              }
              return r.student != null;
            }).toList();

            int inserted = 0;
            for (final r in toInsert) {
              final st = r.student;
              if (st == null) continue;
              await _dbService.insertStudent(st);
              inserted += 1;
            }
            await _loadData();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Import terminé: $inserted élève(s) importé(s).')),
              );
            }
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur import: $e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<_StudentsImport> _parseImportFile({
    required String fileName,
    required List<int> bytes,
  }) async {
    final lower = fileName.toLowerCase();
    List<List<dynamic>> rawRows;
    if (lower.endsWith('.csv')) {
      final text = utf8.decode(bytes, allowMalformed: true);
      rawRows = const CsvToListConverter(
        fieldDelimiter: ',',
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(text);
    } else if (lower.endsWith('.xlsx')) {
      final excel = ex.Excel.decodeBytes(bytes);
      final table = excel.tables.values.isEmpty ? null : excel.tables.values.first;
      if (table == null) throw Exception('Classeur Excel vide.');
      rawRows = table.rows
          .map((r) => r.map((c) => c?.value).toList())
          .toList(growable: false);
    } else {
      throw Exception('Format non supporté: $fileName');
    }
    if (rawRows.isEmpty) throw Exception('Fichier vide.');

    final headerRow = rawRows.first.map((e) => (e ?? '').toString()).toList();
    final headerMap = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      final key = headerRow[i]
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (key.isEmpty) continue;
      headerMap[key] = i;
    }

    String cell(List<dynamic> row, String key) {
      final idx = headerMap[key];
      if (idx == null || idx < 0 || idx >= row.length) return '';
      return (row[idx] ?? '').toString().trim();
    }

    final yearDefault = _selectedYearFilter ?? _currentAcademicYear;
    final classDefault = _selectedClassAndYearFromFilter();
    final classesSet = _allClasses
        .map((c) => '${c.name}:::${c.academicYear}')
        .toSet();

    final existingDupKeys = _allStudents.map((s) {
      return _studentDupKey(
        firstName: s.firstName,
        lastName: s.lastName,
        dateOfBirth: s.dateOfBirth,
        contactNumber: s.contactNumber,
      );
    }).toSet();

    final seenInFile = <String>{};
    final rows = <_StudentsImportRow>[];
    final uuid = const Uuid();

    for (int r = 1; r < rawRows.length; r++) {
      final row = rawRows[r];
      final issues = <String>[];

      final id = cell(row, 'id').isNotEmpty ? cell(row, 'id') : uuid.v4();
      final matricule = cell(row, 'matricule');
      String firstName = cell(row, 'firstname');
      String lastName = cell(row, 'lastname');
      final name = cell(row, 'name');
      if ((firstName.isEmpty && lastName.isEmpty) && name.isNotEmpty) {
        final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        if (parts.length == 1) {
          firstName = parts.first;
          lastName = '';
        } else if (parts.length == 2) {
          firstName = parts.first;
          lastName = parts.last;
        } else if (parts.length > 2) {
          firstName = parts.sublist(0, parts.length - 1).join(' ');
          lastName = parts.last;
        }
      }
      if (firstName.isEmpty) issues.add('Prénom manquant');

      final dateOfBirth = cell(row, 'dateofbirth');
      if (dateOfBirth.isEmpty) issues.add('Date de naissance manquante');
      final placeOfBirth = cell(row, 'placeofbirth');
      final address = cell(row, 'address');
      if (address.isEmpty) issues.add('Adresse manquante');
      String gender = cell(row, 'gender');
      if (gender.isNotEmpty) {
        final g = gender.toUpperCase();
        if (g.startsWith('M')) gender = 'M';
        if (g.startsWith('F')) gender = 'F';
      }
      if (gender != 'M' && gender != 'F') issues.add('Sexe invalide (M/F)');

      final contactNumber = cell(row, 'contactnumber');
      if (contactNumber.isEmpty) issues.add('Téléphone manquant');
      final email = cell(row, 'email');
      final emergencyContact = cell(row, 'emergencycontact');
      if (emergencyContact.isEmpty) issues.add('Contact urgence manquant');
      final guardianName = cell(row, 'guardianname');
      if (guardianName.isEmpty) issues.add('Nom tuteur manquant');
      final guardianContact = cell(row, 'guardiancontact');
      if (guardianContact.isEmpty) issues.add('Téléphone tuteur manquant');

      String className = cell(row, 'classname');
      String academicYear = cell(row, 'academicyear');
      if (academicYear.isEmpty) academicYear = yearDefault;
      if (className.isEmpty && classDefault != null) {
        className = classDefault.className;
        academicYear = classDefault.academicYear;
      }
      if (className.isEmpty) issues.add('Classe manquante');
      final classKey = '$className:::$academicYear';
      if (className.isNotEmpty && !classesSet.contains(classKey)) {
        issues.add('Classe inconnue: $className ($academicYear)');
      }

      final enrollmentDate = cell(row, 'enrollmentdate').isNotEmpty
          ? cell(row, 'enrollmentdate')
          : DateTime.now().toIso8601String();
      final status = cell(row, 'status').isNotEmpty ? cell(row, 'status') : 'Nouveau';
      final medicalInfo = cell(row, 'medicalinfo');

      final dupKey = _studentDupKey(
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        contactNumber: contactNumber,
      );
      final isDupExisting = existingDupKeys.contains(dupKey);
      final isDupInFile = seenInFile.contains(dupKey);
      seenInFile.add(dupKey);

      Student? student;
      if (issues.isEmpty) {
        student = Student(
          id: id,
          firstName: firstName,
          lastName: lastName,
          dateOfBirth: dateOfBirth,
          placeOfBirth: placeOfBirth.isEmpty ? null : placeOfBirth,
          address: address,
          gender: gender,
          contactNumber: contactNumber,
          email: email,
          emergencyContact: emergencyContact,
          guardianName: guardianName,
          guardianContact: guardianContact,
          className: className,
          academicYear: academicYear,
          enrollmentDate: enrollmentDate,
          status: status,
          medicalInfo: medicalInfo.isEmpty ? null : medicalInfo,
          matricule: matricule.isEmpty ? null : matricule,
        );
      }

      rows.add(
        _StudentsImportRow(
          rowNumber: r + 1,
          isDuplicateExisting: isDupExisting,
          isDuplicateInFile: isDupInFile,
          issues: issues,
          student: student,
        ),
      );
    }

    return _StudentsImport(
      fileName: fileName,
      headers: headerRow,
      rows: rows,
    );
  }

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
    final list = _studentsMatchingCurrentFilters();
    setState(() {
      _selectionMode = true;
      _selectedStudentIds
        ..clear()
        ..addAll(list.map((s) => s.id));
    });
  }

  List<Student> _selectedStudents() {
    final ids = _selectedStudentIds;
    if (ids.isEmpty) return const [];
    final byId = {for (final s in _allStudents) s.id: s};
    final list = <Student>[];
    for (final id in ids) {
      final s = byId[id];
      if (s != null) list.add(s);
    }
    return list;
  }

  Future<void> _bulkDeleteSelectedStudents() async {
    final selected = _selectedStudents();
    if (selected.isEmpty) return;
    debugPrint(
      '[StudentsPage] bulk delete requested: count=${selected.length} ids=${selected.map((s) => s.id).take(10).join(",")}',
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
    debugPrint('[StudentsPage] bulk delete confirmed');
    await _dbService.softDeleteStudents(
      studentIds: selected.map((s) => s.id).toList(),
    );
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selected.length} élève(s) supprimé(s).')),
    );
    _setSelectionMode(false);
  }

  Future<void> _bulkRestoreSelectedStudents() async {
    final selected = _selectedStudents();
    if (selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer les élèves ?'),
        content: Text('Restaurer ${selected.length} élève(s) depuis la corbeille ?'),
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
    await _dbService.restoreStudents(
      studentIds: selected.map((s) => s.id).toList(),
    );
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selected.length} élève(s) restauré(s).')),
    );
    _setSelectionMode(false);
  }

  Future<void> _bulkChangeClassYear() async {
    final selected = _selectedStudents();
    if (selected.isEmpty) return;
    if (_allClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune classe disponible.')),
      );
      return;
    }
    String? selectedKey;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
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
                  items: (() {
                    final keys = _allClasses
                        .map((c) => '${c.name}:::${c.academicYear}')
                        .toSet()
                        .toList()
                      ..sort();
                    return keys.map((k) {
                      final parts = k.split(':::');
                      final label =
                          parts.length == 2 ? '${parts[0]} (${parts[1]})' : k;
                      return DropdownMenuItem(value: k, child: Text(label));
                    }).toList();
                  })(),
                  onChanged: (v) => setState(() => selectedKey = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Note: ceci met à jour la classe/année de la fiche élève. Les historiques (paiements/notes) ne sont pas modifiés.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
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
    await _dbService.updateStudentsClassAndYear(
      studentIds: selected.map((s) => s.id).toList(),
      className: parts[0],
      academicYear: parts[1],
    );
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Mise à jour effectuée (${selected.length}).')),
    );
    _setSelectionMode(false);
  }

  Future<void> _printStudentCardsSelected() async {
    final selected = _selectedStudents();
    if (selected.isEmpty) return;
    debugPrint(
      '[StudentsPage] export ID cards requested: count=${selected.length}',
    );
    final year = _selectedYearFilter ?? _currentAcademicYear;
    try {
      final result = await StudentIdCardService(dbService: _dbService)
          .exportStudentIdCardsPdf(
            students: selected,
            academicYear: year,
            compact: true,
            dialogTitle: 'Choisissez un dossier de sauvegarde',
          );
      await OpenFile.open(result.file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cartes générées: ${result.file.path}')),
      );
    } catch (e) {
      debugPrint('[StudentsPage] export ID cards error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  /*
  // Ancien générateur custom de cartes (conservé en commentaire)
  // remplacé par StudentIdCardService + StudentIdCardTemplate pour un rendu cohérent
  // et éviter les problèmes de contraste (texte invisible).
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            schoolNameForCards,
                            style: pw.TextStyle(
                              color: textMuted,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                          pw.Text(
                            'CARTE ELEVE',
                            style: pw.TextStyle(
                              color: textMuted,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(999),
                        border: pw.Border.all(color: border),
                      ),
                      child: pw.Text(
                        s.academicYear,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: textMuted,
                        ),
                      ),
                    ),
                    if (flag != null) ...[
                      pw.SizedBox(width: 8),
                      pw.Container(
                        width: 28,
                        height: 18,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(4),
                          border: pw.Border.all(color: border),
                          image: pw.DecorationImage(
                            image: flag!,
                            fit: pw.BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(10),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 54,
                      height: 54,
                      decoration: pw.BoxDecoration(
                        color: pillBg,
                        shape: pw.BoxShape.circle,
                        border: pw.Border.all(color: border),
                        image: photo == null
                            ? null
                            : pw.DecorationImage(
                                image: photo!,
                                fit: pw.BoxFit.cover,
                              ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    s.name,
                                    style: pw.TextStyle(
                                      fontSize: 12,
                                      fontWeight: pw.FontWeight.bold,
                                      color: textMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: pw.TextOverflow.clip,
                                  ),
                                  pw.SizedBox(height: 4),
                                  pw.Text(
                                    'Classe: ${s.className}',
                                    style: pw.TextStyle(
                                      fontSize: 10,
                                      color: textMuted,
                                    ),
                                  ),
                                  pw.SizedBox(height: 4),
                                  pw.Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      if (hasMatricule)
                                        pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: pw.BoxDecoration(
                                    color: pillBg,
                                    borderRadius: pw.BorderRadius.circular(999),
                                    border: pw.Border.all(color: border),
                                  ),
                                          child: pw.Text(
                                            'Matricule: $displayMatricule',
                                            style: pw.TextStyle(
                                              fontSize: 8,
                                              color: textMuted,
                                            ),
                                          ),
                                        ),
                                      pw.Container(
                                        padding: const pw.EdgeInsets.symmetric(
                                          horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: pillBg,
                                  borderRadius: pw.BorderRadius.circular(999),
                                  border: pw.Border.all(color: border),
                                ),
                                        child: pw.Text(
                                          'Ne le: $displayDob',
                                          style: pw.TextStyle(
                                            fontSize: 8,
                                            color: textMuted,
                                          ),
                                        ),
                                      ),
                                      pw.Container(
                                        padding: const pw.EdgeInsets.symmetric(
                                          horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: pillBg,
                                  borderRadius: pw.BorderRadius.circular(999),
                                  border: pw.Border.all(color: border),
                                ),
                                        child: pw.Text(
                                          'Lieu: $displayPlace',
                                          style: pw.TextStyle(
                                            fontSize: 8,
                                            color: textMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: pw.TextOverflow.clip,
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
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Contact: ${s.contactNumber.isNotEmpty ? s.contactNumber : '-'}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: textMuted,
                        ),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pdfTheme,
        build: (context) {
          final cards = students.map(cardFor).toList();
          return [
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map(
                    (c) => pw.SizedBox(
                      width: (PdfPageFormat.a4.width - 48 - 12) / 2,
                      child: c,
                    ),
                  )
                  .toList(),
            ),
          ];
        },
      ),
    );

    await file.writeAsBytes(await doc.save(), flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF généré: ${file.path.split('/').last}')),
    );
    await OpenFile.open(file.path);
  }

*/

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(AppSizes.padding),
          child: Container(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                SizedBox(height: AppSizes.padding),
                _buildActionButtons(context),
                SizedBox(height: AppSizes.padding),
                _buildFilters(context),
                SizedBox(height: AppSizes.padding),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_showStudentView) ...[
                          _buildChartsSection(context, constraints),
                          SizedBox(height: AppSizes.padding),
                          _buildDataTable(context),
                        ] else ...[
                          _buildStudentListView(context),
                        ],
                        SizedBox(height: AppSizes.padding),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
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
            mainAxisAlignment: MainAxisAlignment
                .spaceBetween, // To push notification icon to the end
            children: [
              Row(
                // This inner Row contains the icon, title, and description
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
                      Icons.people,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    // Title and description
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.studentsTitle,
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme
                              .textTheme
                              .bodyLarge
                              ?.color, // Use bodyLarge for title
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Gérez les informations des élèves, leurs classes et leurs performances académiques.',
                        style: TextStyle(
                          fontSize: isDesktop ? 16 : 14,
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.7,
                          ), // Use bodyMedium for description
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Notification icon back in place
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowDark.withOpacity(0.1),
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
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Rechercher par classe, année ou nom d\'élève...',
              hintStyle: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
            onChanged: (value) {
              final trimmedValue = value.trim();
              setState(() {
                _searchQuery = trimmedValue;
                // Switch to student view if searching by student name
                _showStudentView = _isSearchingByStudentName(trimmedValue);
              });
            },
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final classRows = List<Map<String, dynamic>>.from(_tableData);
    classRows.sort((a, b) {
      final aLevel = (a['level'] as String?)?.trim() ?? 'Non défini';
      final bLevel = (b['level'] as String?)?.trim() ?? 'Non défini';
      final ra = _levelRank(aLevel);
      final rb = _levelRank(bLevel);
      if (ra != rb) return ra.compareTo(rb);
      final al = (a['classLabel'] as String?) ?? '';
      final bl = (b['classLabel'] as String?) ?? '';
      return al.compareTo(bl);
    });
    final classMap = <String, String>{
      for (final row in classRows)
        row['classKey'] as String: row['classLabel'] as String,
    };
    final levels = classRows
        .map((r) => (r['level'] as String?)?.trim() ?? 'Non défini')
        .toSet()
        .toList()
      ..sort((a, b) {
        final ra = _levelRank(a);
        final rb = _levelRank(b);
        if (ra != rb) return ra.compareTo(rb);
        return a.compareTo(b);
      });
    final yearList = _tableData
        .map((e) => e['year'] as String)
        .toSet()
        .toList();
    return Wrap(
      spacing: AppSizes.smallSpacing,
      runSpacing: AppSizes.smallSpacing,
      children: [
        if (levels.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor!),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Niveaux',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyMedium!.color,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: _selectedLevelFilter == null,
                  selectedColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.15),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  labelStyle: TextStyle(
                    color: _selectedLevelFilter == null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).textTheme.bodyMedium!.color,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) =>
                      setState(() => _selectedLevelFilter = null),
                ),
                ...levels.map((level) {
                  final color = _levelColor(level);
                  final selected = _selectedLevelFilter == level;
                  return ChoiceChip(
                    label: Text(level),
                    selected: selected,
                    selectedColor: color.withOpacity(0.2),
                    backgroundColor: color.withOpacity(0.08),
                    labelStyle: TextStyle(
                      color: selected ? color : color.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedLevelFilter = level),
                  );
                }),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor!),
          ),
          child: ToggleButtons(
            isSelected: [_showStudentView == false, _showStudentView == true],
            onPressed: (index) {
              setState(() {
                _showStudentView = index == 1;
                _selectionMode = false;
                _selectedStudentIds.clear();
              });
            },
            borderRadius: BorderRadius.circular(8),
            constraints: const BoxConstraints(minHeight: 34, minWidth: 44),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(Icons.dashboard_outlined, size: 18),
                    SizedBox(width: 6),
                    Text('Classes'),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(Icons.people_alt_outlined, size: 18),
                    SizedBox(width: 6),
                    Text('Élèves'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor!),
          ),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _visibilityFilter,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Actifs')),
                  DropdownMenuItem(value: 'deleted', child: Text('Corbeille')),
                  DropdownMenuItem(value: 'all', child: Text('Tous')),
                ],
                onChanged: (value) {
                  final v = value ?? 'active';
                  setState(() {
                    _visibilityFilter = v;
                    if (v != 'active') {
                      _showStudentView = true;
                    }
                    _selectionMode = false;
                    _selectedStudentIds.clear();
                  });
                  _loadData();
                },
              dropdownColor: Theme.of(context).cardColor,
              iconEnabledColor: Theme.of(context).iconTheme.color,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium!.color,
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedClassFilter,
              hint: Text(
                AppStrings.classFilter,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium!.color,
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Toutes les classes',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium!.color,
                    ),
                  ),
                ),
                ...classMap.entries.map(
                  (entry) => DropdownMenuItem<String?>(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium!.color,
                      ),
                    ),
                  ),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _selectedClassFilter = value),
              dropdownColor: Theme.of(context).cardColor,
              iconEnabledColor: Theme.of(context).iconTheme.color,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium!.color,
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedGenderFilter,
              hint: Text(
                AppStrings.genderFilter,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium!.color,
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Tous',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium!.color,
                    ),
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'M',
                  child: Text(
                    'Garçons',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium!.color,
                    ),
                  ),
                ),
                DropdownMenuItem<String?>(
                  value: 'F',
                  child: Text(
                    'Filles',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium!.color,
                    ),
                  ),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _selectedGenderFilter = value),
              dropdownColor: Theme.of(context).cardColor,
              iconEnabledColor: Theme.of(context).iconTheme.color,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium!.color,
              ),
            ),
          ),
        ),
        ValueListenableBuilder<String>(
          valueListenable: academicYearNotifier,
          builder: (context, currentYear, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor!),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedYearFilter,
                  hint: Text(
                    AppStrings.yearFilter,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium!.color,
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Toutes les années',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyMedium!.color,
                        ),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: currentYear,
                      child: Text(
                        'Année courante ($currentYear)',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyMedium!.color,
                        ),
                      ),
                    ),
                    ...yearList
                        .where((y) => y != currentYear)
                        .map(
                          (y) => DropdownMenuItem<String?>(
                            value: y,
                            child: Text(
                              y,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyMedium!.color,
                              ),
                            ),
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedYearFilter = value),
                  dropdownColor: Theme.of(context).cardColor,
                  iconEnabledColor: Theme.of(context).iconTheme.color,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium!.color,
                  ),
                ),
              ),
            );
          },
        ),
        if (_selectedClassFilter != null ||
            _selectedGenderFilter != null ||
            _selectedYearFilter != null ||
            _selectedLevelFilter != null)
          TextButton.icon(
            onPressed: () => setState(() {
              _selectedClassFilter = null;
              _selectedGenderFilter = null;
              _selectedYearFilter = _currentAcademicYear;
              _selectedLevelFilter = null;
            }),
            icon: Icon(
              Icons.clear,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
            label: Text(
              'Réinitialiser',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium!.color,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChartsSection(BuildContext context, BoxConstraints constraints) {
    return constraints.maxWidth > 600
        ? Row(
            children: [
              Expanded(
                child: ChartCard(
                  title: AppStrings.classDistributionTitle,
                  total: _classDistribution.values
                      .fold(0, (a, b) => a + b)
                      .toString(),
                  percentage: _classDistribution.isEmpty ? '0%' : '+12%',
                  maxY:
                      (_classDistribution.values.isEmpty
                              ? 1
                              : _classDistribution.values.reduce(
                                  (a, b) => a > b ? a : b,
                                ))
                          .toDouble() +
                      10,
                  bottomTitles: _classDistribution.keys.toList(),
                  barValues: _classDistribution.values
                      .map((e) => e.toDouble())
                      .toList(),
                  aspectRatio: AppSizes.chartAspectRatio,
                ),
              ),
              SizedBox(width: AppSizes.spacing),
              Expanded(
                child: ChartCard(
                  title: AppStrings.academicYearTitle,
                  total: _academicYearDistribution.values
                      .fold(0, (a, b) => a + b)
                      .toString(),
                  percentage: _academicYearDistribution.isEmpty ? '0%' : '+5%',
                  maxY:
                      (_academicYearDistribution.values.isEmpty
                              ? 1
                              : _academicYearDistribution.values.reduce(
                                  (a, b) => a > b ? a : b,
                                ))
                          .toDouble() +
                      10,
                  bottomTitles: _academicYearDistribution.keys.toList(),
                  barValues: _academicYearDistribution.values
                      .map((e) => e.toDouble())
                      .toList(),
                  aspectRatio: AppSizes.chartAspectRatio,
                ),
              ),
            ],
          )
        : Column(
            children: [
              ChartCard(
                title: AppStrings.classDistributionTitle,
                total: _classDistribution.values
                    .fold(0, (a, b) => a + b)
                    .toString(),
                percentage: _classDistribution.isEmpty ? '0%' : '+12%',
                maxY:
                    (_classDistribution.values.isEmpty
                            ? 1
                            : _classDistribution.values.reduce(
                                (a, b) => a > b ? a : b,
                              ))
                        .toDouble() +
                    10,
                bottomTitles: _classDistribution.keys.toList(),
                barValues: _classDistribution.values
                    .map((e) => e.toDouble())
                    .toList(),
                aspectRatio: AppSizes.chartAspectRatio,
              ),
              SizedBox(height: AppSizes.spacing),
              ChartCard(
                title: AppStrings.academicYearTitle,
                total: _academicYearDistribution.values
                    .fold(0, (a, b) => a + b)
                    .toString(),
                percentage: _academicYearDistribution.isEmpty ? '0%' : '+5%',
                maxY:
                    (_academicYearDistribution.values.isEmpty
                            ? 1
                            : _academicYearDistribution.values.reduce(
                                (a, b) => a > b ? a : b,
                              ))
                        .toDouble() +
                    10,
                bottomTitles: _academicYearDistribution.keys.toList(),
                barValues: _academicYearDistribution.values
                    .map((e) => e.toDouble())
                    .toList(),
                aspectRatio: AppSizes.chartAspectRatio,
              ),
            ],
          );
  }

  Widget _buildDataTable(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final headerBg = theme.colorScheme.primary;
        final headerText = Colors.white;
        final rowAlt = theme.colorScheme.primary.withOpacity(0.05);
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final data in _filteredTableData) {
          final levelRaw = (data['level'] as String?)?.trim() ?? '';
          final level = levelRaw.isNotEmpty ? levelRaw : 'Non défini';
          grouped.putIfAbsent(level, () => []).add(data);
        }
        final orderedLevels = grouped.keys.toList()
          ..sort((a, b) {
            final ra = _levelRank(a);
            final rb = _levelRank(b);
            if (ra != rb) return ra.compareTo(rb);
            return a.compareTo(b);
          });
        final List<DataRow> rows = [];
        int stripeIndex = 0;
        for (final level in orderedLevels) {
          rows.add(
            DataRow(
              color: MaterialStateProperty.all(
                _levelColor(level).withOpacity(0.12),
              ),
              cells: [
                DataCell(
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _levelColor(level),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Niveau: $level',
                        style: TextStyle(
                          fontSize: 15.0,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const DataCell(SizedBox.shrink()),
                const DataCell(SizedBox.shrink()),
                const DataCell(SizedBox.shrink()),
                const DataCell(SizedBox.shrink()),
                const DataCell(SizedBox.shrink()),
              ],
            ),
          );
          for (final data in grouped[level] ?? const []) {
            final rowColor = stripeIndex.isEven ? null : rowAlt;
            stripeIndex++;
            rows.add(
              _buildRow(
                context,
                data['classKey'] as String,
                data['classLabel'] as String,
                data['total'],
                data['boys'],
                data['girls'],
                data['year'],
                rowColor: rowColor,
              ),
            );
          }
        }
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.dividerColor.withOpacity(0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowDark.withOpacity(0.2),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                // Make the table visually larger and more readable
                headingRowHeight: 60,
                dataRowMinHeight: 56,
                dataRowMaxHeight: 64,
                columnSpacing: 32,
                headingRowColor: MaterialStateProperty.all(headerBg),
                dividerThickness: 0.6,
                columns: [
                  DataColumn(
                    label: Text(
                      AppStrings.classLabel,
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                        color: headerText,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      AppStrings.totalStudentsLabel,
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                        color: headerText,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      AppStrings.boysLabel,
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                        color: headerText,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      AppStrings.girlsLabel,
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                        color: headerText,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      AppStrings.academicYearLabel,
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                        color: headerText,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      AppStrings.actionsLabel,
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.bold,
                        color: headerText,
                      ),
                    ),
                  ),
                ],
                rows: rows,
              ),
            ),
          ),
        );
      },
    );
  }

  int _levelRank(String level) {
    final n = level.trim().toLowerCase();
    if (n.contains('maternelle')) return 0;
    if (n.contains('primaire')) return 1;
    if (n.contains('coll')) return 2;
    if (n.contains('lyc')) return 3;
    if (n.contains('univ')) return 4;
    return 99;
  }

  Color _levelColor(String level) {
    final n = level.trim().toLowerCase();
    if (n.contains('maternelle')) return const Color(0xFFEF4444);
    if (n.contains('primaire')) return const Color(0xFF22C55E);
    if (n.contains('coll')) return const Color(0xFFF59E0B);
    if (n.contains('lyc')) return const Color(0xFF2563EB);
    if (n.contains('univ')) return const Color(0xFF14B8A6);
    return const Color(0xFF6B7280);
  }

  DataRow _buildRow(
    BuildContext context,
    String classKey,
    String classLabel,
    String total,
    String male,
    String female,
    String year,
    {Color? rowColor}
  ) {
    final keyParts = classKey.split(':::');
    final className = keyParts.isNotEmpty ? keyParts.first : classLabel;
    final classYear = keyParts.length > 1 ? keyParts.last : year;
    return DataRow(
      color: rowColor == null
          ? null
          : MaterialStateProperty.all(rowColor),
      cells: [
        DataCell(
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                classLabel,
                style: TextStyle(
                  fontSize: 15.0,
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
              ),
            ],
          ),
        ),
        DataCell(
          Text(
            total,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
        ),
        DataCell(
          Text(
            male,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
        ),
        DataCell(
          Text(
            female,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
        ),
        DataCell(
          Text(
            year,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
        ),
        DataCell(
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  final classes = await DatabaseService().getClasses();
                  final classObjFull =
                      _classFromKey(classKey, classes) ??
                      Class(
                        name: className,
                        academicYear: classYear,
                        titulaire: null,
                        fraisEcole: null,
                        fraisCotisationParallele: null,
                      );
                  final classStudents = await DatabaseService()
                      .getStudentsByClassAndClassYear(className, classYear);
                  await showDialog(
                    context: context,
                    builder: (context) => ClassDetailsPage(
                      classe: classObjFull,
                      students: classStudents,
                    ),
                  );
                  await _loadData();
                },
                child: Text(
                  AppStrings.viewDetails,
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyMedium!.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showEditStudentDialog(BuildContext context, Student student) {
    final GlobalKey<StudentRegistrationFormState> studentFormKey =
        GlobalKey<StudentRegistrationFormState>();

    showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: 'Modifier l\'élève',
        content: StudentRegistrationForm(
          key: studentFormKey,
          student: student, // Pass the existing student data
          onSubmit: () {
            _loadData();
            Navigator.pop(context);
            // Afficher une notification de succès
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Élève modifié avec succès!'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          },
        ),
        fields: const [],
        onSubmit: () {
          studentFormKey.currentState?.submitForm();
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => studentFormKey.currentState?.submitForm(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Modifier'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final GlobalKey<StudentRegistrationFormState> studentFormKey =
        GlobalKey<StudentRegistrationFormState>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: () {
            print('Ajouter un Élève button pressed');
            try {
              showDialog(
                context: context,
                builder: (context) => CustomDialog(
                  title: AppStrings.addStudent,
                  content: StudentRegistrationForm(
                    key: studentFormKey,
                    onSubmit: () {
                      print('Student form submitted');
                      _loadData();
                      Navigator.pop(context);
                      // Afficher une notification de succès
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Élève ajouté avec succès!'),
                            ],
                          ),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
                    },
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
                      onPressed: () =>
                          studentFormKey.currentState?.submitForm(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Ajouter'),
                    ),
                  ],
                ),
              );
            } catch (e) {
              print('Error opening student dialog: $e');
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            elevation: null,
          ),
          child: const Text(
            'Ajouter un élève',
            style: TextStyle(
              fontSize: AppSizes.textFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => _ClassDialog(onSubmit: () {}),
            );
            if (ok == true) {
              await _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Classe ajoutée avec succès!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.grey.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
          child: const Text(
            'Ajouter une classe',
            style: TextStyle(
              fontSize: AppSizes.textFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final didApply = await showDialog<bool>(
              context: context,
              builder: (_) => const ReEnrollmentBatchDialog(),
            );
            if (didApply == true) {
              await _loadData();
            }
          },
          icon: const Icon(Icons.how_to_reg, color: Colors.white),
          label: const Text(
            'Réinscription (toute l\'école)',
            style: TextStyle(
              fontSize: AppSizes.textFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: () async {
            setState(() {
              _visibilityFilter = 'deleted';
              _showStudentView = true;
              _selectionMode = false;
              _selectedStudentIds.clear();
            });
            await _loadData();
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Corbeille'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(width: 16),
        PopupMenuButton<String>(
          key: _importExportMenuKey,
          tooltip: 'Importer / Exporter',
          onSelected: (value) async {
            debugPrint('[StudentsPage] import/export selected: $value');
            switch (value) {
              case 'import':
                await _importStudents();
                break;
              case 'export_csv':
                await _exportStudentsCsv();
                break;
              case 'export_excel':
                await _exportStudentsExcel();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'import',
              child: Row(
                children: const [
                  Icon(Icons.file_upload_outlined),
                  SizedBox(width: 8),
                  Text('Importer (CSV/Excel)'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'export_csv',
              child: Row(
                children: const [
                  Icon(Icons.table_view_outlined),
                  SizedBox(width: 8),
                  Text('Exporter CSV'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'export_excel',
              child: Row(
                children: const [
                  Icon(Icons.grid_on_outlined),
                  SizedBox(width: 8),
                  Text('Exporter Excel'),
                ],
              ),
            ),
          ],
          child: ElevatedButton.icon(
            onPressed: _importing || _exporting
                ? () {
                    debugPrint(
                      '[StudentsPage] import/export pressed but busy (importing=$_importing exporting=$_exporting)',
                    );
                  }
                : () {
                    debugPrint('[StudentsPage] import/export pressed -> open menu');
                    _importExportMenuKey.currentState?.showButtonMenu();
                  },
            icon: _importing || _exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.import_export, color: Colors.white),
            label: Text(
              _importing
                  ? 'Import...'
                  : _exporting
                      ? 'Export...'
                      : 'Importer/Exporter',
              style: const TextStyle(
                fontSize: AppSizes.textFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentListView(BuildContext context) {
    final filteredStudents = _studentsMatchingCurrentFilters();
    final selectedCount = _selectedStudentIds.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.person_search,
                  color: Theme.of(context).primaryColor,
                ),
                SizedBox(width: 12),
                Text(
                  'Élèves trouvés (${filteredStudents.length})',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _setSelectionMode(!_selectionMode),
                  icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
                  label: Text(_selectionMode ? 'Quitter' : 'Sélection'),
                ),
                if (_selectionMode)
                  TextButton(
                    onPressed: filteredStudents.isEmpty
                        ? null
                        : () => _selectAllFilteredStudents(),
                    child: const Text('Tout sélectionner'),
                  ),
              ],
            ),
          ),
          if (_selectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$selectedCount sélectionné(s)',
                    style: TextStyle(
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withOpacity(0.8),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: selectedCount == 0 ? null : _bulkChangeClassYear,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Classe/Année'),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        selectedCount == 0 ? null : _printStudentCardsSelected,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Cartes PDF'),
                  ),
                  ElevatedButton.icon(
                    onPressed: selectedCount == 0 ? null : _bulkDeleteSelectedStudents,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  if (_visibilityFilter == 'deleted')
                    ElevatedButton.icon(
                      onPressed:
                          selectedCount == 0 ? null : _bulkRestoreSelectedStudents,
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
          if (filteredStudents.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Aucun élève (selon les filtres).',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium!.color,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: filteredStudents.length,
              itemBuilder: (context, index) {
                final student = filteredStudents[index];
                return _buildStudentCard(
                  context,
                  student,
                  selectionMode: _selectionMode,
                  selected: _selectedStudentIds.contains(student.id),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(
    BuildContext context,
    Student student, {
    required bool selectionMode,
    required bool selected,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: selectionMode && selected
            ? theme.primaryColor.withOpacity(0.06)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor!.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selectionMode
            ? () {
                _toggleSelectedStudent(student.id);
                debugPrint(
                  '[StudentsPage] toggle selected (tap): id=${student.id} selected=${_selectedStudentIds.contains(student.id)}',
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
          if (selectionMode)
            Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelectedStudent(student.id),
            ),
          // Student avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Icon(Icons.person, color: theme.primaryColor, size: 24),
          ),
          SizedBox(width: 16),

          // Student info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge!.color,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.class_,
                      size: 16,
                      color: theme.textTheme.bodyMedium!.color,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '${student.className} (${student.academicYear})',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium!.color,
                      ),
                    ),
                    if (student.isDeleted) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.red.withOpacity(0.35)),
                        ),
                        child: const Text(
                          'Supprimé',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      student.gender == 'M' ? Icons.male : Icons.female,
                      size: 16,
                      color: student.gender == 'M' ? Colors.blue : Colors.pink,
                    ),
                    SizedBox(width: 4),
                    Text(
                      student.gender == 'M' ? 'Garçon' : 'Fille',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium!.color,
                      ),
                    ),
                    SizedBox(width: 16),
                    Icon(
                      Icons.phone,
                      size: 16,
                      color: theme.textTheme.bodyMedium!.color,
                    ),
                    SizedBox(width: 4),
                    Text(
                      student.contactNumber.isNotEmpty
                          ? student.contactNumber
                          : 'Non renseigné',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium!.color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action buttons
          if (!selectionMode)
            Row(
              children: [
                IconButton(
                  onPressed: () async {
                    final classes = await DatabaseService().getClasses();
                    final classObj = classes.firstWhere(
                      (c) =>
                          c.name == student.className &&
                          c.academicYear == student.academicYear,
                      orElse: () => Class(
                        name: student.className,
                        academicYear: student.academicYear,
                        titulaire: null,
                        fraisEcole: null,
                        fraisCotisationParallele: null,
                      ),
                    );
                    final classStudents = await DatabaseService()
                        .getStudentsByClassAndClassYear(
                          student.className,
                          student.academicYear,
                        );
                    await showDialog(
                      context: context,
                      builder: (context) => ClassDetailsPage(
                        classe: classObj,
                        students: classStudents,
                      ),
                    );
                    await _loadData();
                  },
                  icon: Icon(Icons.visibility, color: theme.primaryColor),
                  tooltip: 'Voir la classe',
                ),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            StudentProfilePage(student: student),
                      ),
                    );
                  },
                  icon: Icon(Icons.person, color: theme.primaryColor),
                  tooltip: 'Voir le profil',
                ),
                IconButton(
                  onPressed: () {
                    _showEditStudentDialog(context, student);
                  },
                  icon: Icon(Icons.edit, color: theme.primaryColor),
                  tooltip: 'Modifier l\'élève',
                ),
              ],
            )
          else
            IconButton(
              tooltip: selected ? 'Désélectionner' : 'Sélectionner',
              onPressed: () => _toggleSelectedStudent(student.id),
              icon: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? const Color(0xFF10B981) : theme.iconTheme.color,
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassDialog extends StatefulWidget {
  final VoidCallback onSubmit;

  const _ClassDialog({required this.onSubmit});

  @override
  State<_ClassDialog> createState() => __ClassDialogState();
}

class __ClassDialogState extends State<_ClassDialog> {
  final _formKey = GlobalKey<FormState>();
  final classNameController = TextEditingController();
  final academicYearController = TextEditingController();
  final titulaireController = TextEditingController();
  final fraisEcoleController = TextEditingController();
  final fraisCotisationParalleleController = TextEditingController();
  final List<String> _levels = const [
    'Primaire',
    'Collège',
    'Lycée',
    'Université',
  ];
  String _selectedLevel = 'Primaire';
  final DatabaseService _dbService = DatabaseService();

  @override
  void initState() {
    super.initState();
    academicYearController.text = academicYearNotifier.value;
  }

  @override
  void dispose() {
    classNameController.dispose();
    academicYearController.dispose();
    titulaireController.dispose();
    fraisEcoleController.dispose();
    fraisCotisationParalleleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomDialog(
      title: AppStrings.addClass,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomFormField(
              controller: classNameController,
              labelText: AppStrings.classNameDialog,
              hintText: 'Enter le nom de la classe',
              validator: (value) => value!.isEmpty ? AppStrings.required : null,
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: academicYearController,
              labelText: AppStrings.academicYearDialog,
              hintText: 'Enter l\'année scolaire',
              validator: (value) => value!.isEmpty ? AppStrings.required : null,
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            DropdownButtonFormField<String>(
              value: _selectedLevel,
              decoration: const InputDecoration(
                labelText: 'Niveau scolaire',
                border: OutlineInputBorder(),
              ),
              items: _levels
                  .map((level) => DropdownMenuItem(
                        value: level,
                        child: Text(level),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedLevel = value);
              },
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: titulaireController,
              labelText: 'Titulaire',
              hintText: 'Nom du titulaire de la classe',
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: fraisEcoleController,
              labelText: 'Frais d\'école',
              hintText: 'Montant des frais d\'école',
              validator: (value) {
                if (value != null &&
                    value.isNotEmpty &&
                    double.tryParse(value) == null) {
                  return 'Veuillez entrer un montant valide';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: fraisCotisationParalleleController,
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
          ],
        ),
      ),
      fields: const [],
      onSubmit: () async {
        if (_formKey.currentState!.validate()) {
          try {
            final cls = Class(
              name: classNameController.text,
              academicYear: academicYearController.text,
              level: _selectedLevel,
              titulaire: titulaireController.text.isNotEmpty
                  ? titulaireController.text
                  : null,
              fraisEcole: fraisEcoleController.text.isNotEmpty
                  ? double.tryParse(fraisEcoleController.text)
                  : null,
              fraisCotisationParallele:
                  fraisCotisationParalleleController.text.isNotEmpty
                  ? double.tryParse(fraisCotisationParalleleController.text)
                  : null,
            );
            await _dbService.insertClass(cls);
            // Close dialog and notify parent for snackbar
            Navigator.pop(context, true);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors de l\'enregistrement: $e')),
            );
          }
        }
      },
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              try {
                final cls = Class(
                  name: classNameController.text,
                  academicYear: academicYearController.text,
                  level: _selectedLevel,
                  titulaire: titulaireController.text.isNotEmpty
                      ? titulaireController.text
                      : null,
                  fraisEcole: fraisEcoleController.text.isNotEmpty
                      ? double.tryParse(fraisEcoleController.text)
                      : null,
                  fraisCotisationParallele:
                      fraisCotisationParalleleController.text.isNotEmpty
                      ? double.tryParse(fraisCotisationParalleleController.text)
                      : null,
                );
                await _dbService.insertClass(cls);
                Navigator.pop(context, true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erreur lors de l\'enregistrement: $e'),
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _StudentsImport {
  final String fileName;
  final List<String> headers;
  final List<_StudentsImportRow> rows;
  const _StudentsImport({
    required this.fileName,
    required this.headers,
    required this.rows,
  });

  int get totalRows => rows.length;
  int get invalidRows => rows.where((r) => r.student == null).length;
  int get duplicateExisting =>
      rows.where((r) => r.isDuplicateExisting).length;
  int get duplicateInFile => rows.where((r) => r.isDuplicateInFile).length;
  int get readyRows =>
      rows.where((r) => r.student != null && r.issues.isEmpty).length;
}

class _StudentsImportRow {
  final int rowNumber; // 1-based in file
  final bool isDuplicateExisting;
  final bool isDuplicateInFile;
  final List<String> issues;
  final Student? student;
  const _StudentsImportRow({
    required this.rowNumber,
    required this.isDuplicateExisting,
    required this.isDuplicateInFile,
    required this.issues,
    required this.student,
  });
}

class _StudentsImportOptions {
  final bool includeDuplicates;
  final bool skipInvalid;
  const _StudentsImportOptions({
    required this.includeDuplicates,
    required this.skipInvalid,
  });
}

class _StudentsImportDialog extends StatefulWidget {
  final _StudentsImport import;
  final Future<void> Function(_StudentsImportOptions options) onConfirmImport;

  const _StudentsImportDialog({
    required this.import,
    required this.onConfirmImport,
  });

  @override
  State<_StudentsImportDialog> createState() => _StudentsImportDialogState();
}

class _StudentsImportDialogState extends State<_StudentsImportDialog> {
  bool _includeDuplicates = false;
  bool _skipInvalid = true;
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imp = widget.import;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF6366F1).withOpacity(0.16),
                      const Color(0xFF8B5CF6).withOpacity(0.10),
                    ],
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: theme.dividerColor.withOpacity(0.25),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.file_upload_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Importer des élèves',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            imp.fileName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.75),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: _running ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(
                            label: '${imp.totalRows} ligne(s)',
                            color: const Color(0xFF0EA5E9),
                          ),
                          _chip(
                            label: '${imp.readyRows} prête(s)',
                            color: const Color(0xFF10B981),
                          ),
                          _chip(
                            label: '${imp.invalidRows} invalide(s)',
                            color: const Color(0xFFEF4444),
                          ),
                          _chip(
                            label: '${imp.duplicateExisting} doublon(s) existants',
                            color: const Color(0xFFF59E0B),
                          ),
                          _chip(
                            label: '${imp.duplicateInFile} doublon(s) dans le fichier',
                            color: const Color(0xFFFBBF24),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _skipInvalid,
                              onChanged: _running
                                  ? null
                                  : (v) => setState(() => _skipInvalid = v),
                              title: const Text('Ignorer les lignes invalides'),
                              subtitle: const Text(
                                'Les lignes avec des champs manquants seront ignorées.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _includeDuplicates,
                              onChanged: _running
                                  ? null
                                  : (v) =>
                                      setState(() => _includeDuplicates = v),
                              title: const Text('Inclure les doublons'),
                              subtitle: const Text(
                                'Inclut les doublons détectés (risque de doublonner).',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.25),
                          ),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: imp.rows.length.clamp(0, 50),
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: theme.dividerColor.withOpacity(0.25),
                          ),
                          itemBuilder: (context, i) {
                            final r = imp.rows[i];
                            final st = r.student;
                            final isInvalid = st == null;
                            final isDup =
                                r.isDuplicateExisting || r.isDuplicateInFile;
                            final icon = isInvalid
                                ? Icons.error_outline
                                : isDup
                                    ? Icons.content_copy
                                    : Icons.check_circle_outline;
                            final color = isInvalid
                                ? const Color(0xFFEF4444)
                                : isDup
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF10B981);
                            final title = st == null
                                ? 'Ligne ${r.rowNumber}'
                                : '${st.name} • ${st.className}';
                            final subtitleParts = <String>[
                              if (!isInvalid) 'ID: ${st!.id}',
                              if (r.isDuplicateExisting) 'Doublon existant',
                              if (r.isDuplicateInFile) 'Doublon fichier',
                              if (r.issues.isNotEmpty) r.issues.join(' • '),
                            ];
                            return ListTile(
                              leading: Icon(icon, color: color),
                              title: Text(title),
                              subtitle: subtitleParts.isEmpty
                                  ? null
                                  : Text(
                                      subtitleParts.join(' • '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            );
                          },
                        ),
                      ),
                      if (imp.rows.length > 50)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Aperçu limité aux 50 premières lignes.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.textTheme.bodySmall?.color?.withOpacity(
                                0.7,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: theme.dividerColor.withOpacity(0.25)),
                  ),
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed:
                          _running ? null : () => Navigator.of(context).pop(),
                      child: const Text('Annuler'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _running
                          ? null
                          : () async {
                              setState(() => _running = true);
                              try {
                                await widget.onConfirmImport(
                                  _StudentsImportOptions(
                                    includeDuplicates: _includeDuplicates,
                                    skipInvalid: _skipInvalid,
                                  ),
                                );
                                if (mounted) Navigator.of(context).pop(true);
                              } finally {
                                if (mounted) setState(() => _running = false);
                              }
                            },
                      icon: _running
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_done),
                      label: Text(_running ? 'Import...' : 'Importer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
