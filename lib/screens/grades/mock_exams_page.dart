import 'package:flutter/material.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:school_manager/main.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/screens/dashboard_home.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/mock_exams_sync_service.dart';
import 'package:school_manager/services/mock_exam_pdf_service.dart';
import 'package:school_manager/services/api/remote_mock_exams_service.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:printing/printing.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as ex show Excel;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

class MockExamsPage extends StatefulWidget {
  const MockExamsPage({super.key});

  @override
  _MockExamsPageState createState() => _MockExamsPageState();
}

class _MockExamsPageState extends State<MockExamsPage> {
  final DatabaseService _dbService = DatabaseService();
  
  List<Class> classes = [];
  List<Course> subjects = [];
  List<Student> students = [];
  List<Grade> grades = [];
  List<Grade> sessionGrades = []; // All grades for this session across all subjects
  
  String? selectedClass;
  String? selectedAcademicYear;
  String? selectedSubject;
  String? selectedSession;
  
  bool isLoading = true;
  bool isGridView = false;
  final TextEditingController searchController = TextEditingController();
  String _searchQuery = '';

  // Subject coefficients for weighted average
  Map<String, double> _subjectCoefficients = {};

  // Controllers for Grid view to avoid jumping
  final Map<String, TextEditingController> _gridControllers = {};

  // Debouncing for auto-save
  final Map<String, Timer> _gradeDebouncers = {};

  final ScrollController _horizontalScrollController = ScrollController();

  List<String> sessions = [];

  @override
  void initState() {
    super.initState();
    selectedAcademicYear = academicYearNotifier.value;
    _loadAllData();
    academicYearNotifier.addListener(_onAcademicYearChanged);
    MockExamsSyncService.instance.addListener(_onSyncStatusChanged);
  }

  @override
  void dispose() {
    academicYearNotifier.removeListener(_onAcademicYearChanged);
    MockExamsSyncService.instance.removeListener(_onSyncStatusChanged);
    for (final timer in _gradeDebouncers.values) {
      timer.cancel();
    }
    searchController.dispose();
    for (final controller in _gridControllers.values) {
      controller.dispose();
    }
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onAcademicYearChanged() {
    if (mounted) {
      setState(() {
        selectedAcademicYear = academicYearNotifier.value;
      });
      _loadAllData();
    }
  }

  void _onSyncStatusChanged() {
    if (mounted) {
      _loadAllData(forceLocal: true); // Refresh UI from local DB after sync
    }
  }

  Future<void> _loadAllData({bool forceLocal = false}) async {
    setState(() => isLoading = true);
    classes = await _dbService.getClasses();
    
    sessions = await MockExamsSyncService.instance.loadSessions(forceRemote: !forceLocal && sessions.isEmpty);
    if (sessions.isNotEmpty && (selectedSession == null || !sessions.contains(selectedSession))) {
      selectedSession = sessions.first;
    }
    
    if (classes.isNotEmpty) {
      // Find classes for current academic year
      final yearClasses = classes.where((c) => c.academicYear == selectedAcademicYear).toList();
      if (yearClasses.isNotEmpty) {
        selectedClass ??= yearClasses.first.name;
      } else {
        selectedClass ??= classes.first.name;
      }
    }

    await _onFilterChanged();
    setState(() => isLoading = false);
  }

  TextEditingController _getController(Student student, Course subject, Grade grade, bool hasGrade) {
    final String key = '${student.id}_${subject.id}';
    if (!_gridControllers.containsKey(key)) {
      // If grade value is 0 and it has never been saved (no real ID), show empty
      final String initialText = (hasGrade && grade.id != null) ? grade.value.toString() : '';
      _gridControllers[key] = TextEditingController(text: initialText);
    }
    return _gridControllers[key]!;
  }

  void _clearGridControllers() {
    for (final controller in _gridControllers.values) {
      controller.dispose();
    }
    _gridControllers.clear();
  }

  Future<void> _onFilterChanged() async {
    if (selectedClass != null) {
      // Clear old controllers when context changes
      _clearGridControllers();
      
      final year = selectedAcademicYear ?? academicYearNotifier.value;
      subjects = await _dbService.getCoursesForClass(selectedClass!, year);
      students = await _dbService.getStudentsByClassAndClassYear(selectedClass!, year);
      
      // Load coefficients for this class/year
      final settings = await _dbService.getClassCourseSettings(
        className: selectedClass!,
        academicYear: year,
      );
      _subjectCoefficients = {
        for (final s in settings) s['id'].toString(): (s['coefficient'] as num?)?.toDouble() ?? 1.0
      };
      
      if (subjects.isNotEmpty) {
        selectedSubject ??= subjects.first.name;
      } else {
        selectedSubject = null;
      }
      
      await _loadSessionStats();
      await _loadGrades();
    }
  }

  Future<void> _loadSessionStats() async {
    if (selectedClass != null && selectedSession != null) {
      final year = selectedAcademicYear ?? academicYearNotifier.value;
      final allSessionGrades = await _dbService.getAllGradesForPeriod(
        className: selectedClass!,
        academicYear: year,
        term: selectedSession!,
      );
      
      setState(() {
        sessionGrades = allSessionGrades.where((g) => g.type == 'Examen Blanc').toList();
      });
    }
  }

  Future<void> _loadGrades() async {
    if (selectedClass != null && selectedSubject != null && selectedSession != null) {
      final year = selectedAcademicYear ?? academicYearNotifier.value;
      final course = subjects.firstWhere((c) => c.name == selectedSubject, orElse: () => Course.empty());
      
      // Fetch all grades of type 'Examen Blanc' for this class/year/subject/session
      final allGrades = await _dbService.getAllGradesForPeriod(
        className: selectedClass!,
        academicYear: year,
        term: selectedSession!, // Use session as the period/term identifier
      );
      
      setState(() {
        grades = allGrades.where((g) => g.type == 'Examen Blanc' && g.subject == selectedSubject).toList();
      });
    }
  }

  Grade? _getGradeForStudent(String studentId) {
    try {
      return grades.firstWhere((g) => g.studentId == studentId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveGrade(Student student, String value) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(context, SafeModeService.instance.getBlockedActionMessage(), isError: true);
      return;
    }

    final double? note = double.tryParse(value);
    if (note == null || note < 0 || note > 20) return;

    final year = selectedAcademicYear ?? academicYearNotifier.value;
    final course = subjects.firstWhere((c) => c.name == selectedSubject, orElse: () => Course.empty());
    
    final existing = _getGradeForStudent(student.id);
    
    final newGrade = Grade(
      id: existing?.id,
      studentId: student.id,
      className: selectedClass!,
      academicYear: year,
      subjectId: course.id,
      subject: selectedSubject!,
      term: selectedSession!,
      value: note,
      label: selectedSession!,
      type: 'Examen Blanc',
      coefficient: _subjectCoefficients[course.id] ?? 1.0,
      maxValue: 20.0,
    );

    // Hybrid save
    await MockExamsSyncService.instance.saveGrade(
      studentId: student.id,
      subjectId: course.id,
      session: selectedSession!,
      value: note,
    );

    if (existing == null) {
      await _dbService.insertGrade(newGrade);
    } else {
      await _dbService.updateGrade(newGrade);
    }
    
    await _loadSessionStats();
    await _loadGrades();
  }

  void _debounceSave(Student student, String value) {
    if (_gradeDebouncers.containsKey(student.id)) {
      _gradeDebouncers[student.id]!.cancel();
    }
    _gradeDebouncers[student.id] = Timer(const Duration(milliseconds: 500), () {
      _saveGrade(student, value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: Column(
                children: [
                  _buildModernHeader(theme, isDark),
                  const SizedBox(height: 32),
                  _buildFilterCard(theme, isDark),
                  const SizedBox(height: 24),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    _buildKpiRow(theme, isDark),
                    const SizedBox(height: 24),
                    _buildTopStudents(theme, isDark),
                    const SizedBox(height: 24),
                    if (selectedClass == null || (selectedSubject == null && !isGridView))
                      _buildEmptyState(theme, 'Veuillez sélectionner une classe' + (isGridView ? '.' : ' et une matière.'))
                    else if (isGridView)
                      _buildGridView(theme, isDark)
                    else
                      _buildGradeTable(theme, isDark),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 25,
            offset: const Offset(0, 10),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.assignment_turned_in,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Examens Blancs',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Analyse et gestion des sessions d\'examens',
                        style: TextStyle(
                          fontSize: 15,
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(isGridView ? Icons.view_list : Icons.grid_on, color: theme.colorScheme.primary),
                    onPressed: () => setState(() => isGridView = !isGridView),
                    tooltip: isGridView ? 'Vue par matière' : 'Vue grille globale',
                  ),
                  IconButton(
                    icon: Icon(Icons.sync, color: theme.colorScheme.primary),
                    onPressed: () => MockExamsSyncService.instance.syncAll(),
                    tooltip: 'Synchroniser avec le cloud',
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (MockExamsSyncService.instance.isSyncing)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                          )
                        else
                          Icon(
                            MockExamsSyncService.instance.dataSource.contains('Cloud') 
                                ? Icons.cloud_done_outlined 
                                : Icons.storage_outlined,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          'Source : ${MockExamsSyncService.instance.dataSource}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.refresh, color: theme.colorScheme.primary),
                    onPressed: () => _loadAllData(forceLocal: true),
                    tooltip: 'Rafraîchir localement',
                  ),
                  const SizedBox(width: 4),
                  _buildExcelActionsMenu(theme),
                  const SizedBox(width: 8),
                  _buildPdfActionsMenu(theme),
                  const SizedBox(width: 20),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      color: theme.iconTheme.color?.withOpacity(0.8) ?? theme.textTheme.bodyMedium?.color,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Rechercher un élève par nom...',
              hintStyle: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
              ),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color?.withOpacity(0.6)),
              filled: true,
              fillColor: isDark ? Colors.black.withOpacity(0.2) : theme.scaffoldBackgroundColor.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5), width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
            ),
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ],
      ),
    );
  }



  Widget _buildKpiRow(ThemeData theme, bool isDark) {
    if (students.isEmpty) return const SizedBox.shrink();

    // Statistics for the CURRENT SUBJECT
    final currentSubjectGrades = grades;
    final subjectAvg = currentSubjectGrades.isEmpty 
        ? 0.0 
        : currentSubjectGrades.map((g) => g.value).reduce((a, b) => a + b) / currentSubjectGrades.length;
    
    final subjectSuccessCount = currentSubjectGrades.where((g) => g.value >= 10).length;
    final subjectSuccessRate = currentSubjectGrades.isEmpty ? 0.0 : (subjectSuccessCount / currentSubjectGrades.length) * 100;

    // Statistics for the GLOBAL SESSION (weighted average of all grades)
    double globalAvg = 0.0;
    if (sessionGrades.isNotEmpty) {
      double totalWeightedValue = 0;
      double totalCoefficients = 0;
      for (final g in sessionGrades) {
        totalWeightedValue += (g.value * g.coefficient);
        totalCoefficients += g.coefficient;
      }
      globalAvg = totalCoefficients > 0 ? totalWeightedValue / totalCoefficients : 0.0;
    }

    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            theme,
            'Moyenne Matière',
            '${subjectAvg.toStringAsFixed(2)} / 20',
            Icons.bar_chart,
            [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKpiCard(
            theme,
            'Taux Réussite',
            '${subjectSuccessRate.toStringAsFixed(1)} %',
            Icons.check_circle,
            [const Color(0xFF10B981), const Color(0xFF059669)],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKpiCard(
            theme,
            'Moyenne Session',
            '${globalAvg.toStringAsFixed(2)}',
            Icons.analytics,
            [const Color(0xFFF59E0B), const Color(0xFFD97706)],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(ThemeData theme, String label, String value, IconData icon, List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors[0].withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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

  Widget _buildFilterCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    'Classe',
                    selectedClass,
                    classes.map((c) => c.name).toList(),
                    (val) {
                      setState(() {
                        selectedClass = val;
                        selectedSubject = null;
                      });
                      _onFilterChanged();
                    },
                    Icons.class_,
                    theme,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          'Session',
                          selectedSession,
                          sessions,
                          (val) {
                            if (val != null) {
                              setState(() => selectedSession = val);
                              _loadGrades();
                            }
                          },
                          Icons.event_note,
                          theme,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.settings, color: theme.colorScheme.primary),
                        onPressed: _showSessionManagementDialog,
                        tooltip: 'Gérer les sessions',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8), // Replaced 16 to account for icon button
                Expanded(
                  child: _buildDropdown(
                    'Matière',
                    selectedSubject,
                    subjects.map((c) => c.name).toList(),
                    (val) {
                      setState(() => selectedSubject = val);
                      _loadGrades();
                    },
                    Icons.book,
                    theme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String? value, List<String> items, Function(String?) onChanged, IconData icon, ThemeData theme) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: theme.colorScheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: onChanged,
    );
  }

  void _showSessionManagementDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Gérer les Sessions d\'Examen'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sessions.isEmpty)
                      const Text('Aucune session définie.')
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: sessions.length,
                          itemBuilder: (context, index) {
                            final session = sessions[index];
                            return ListTile(
                              title: Text(session, style: const TextStyle(fontWeight: FontWeight.w500)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                                    onPressed: () {
                                      _showEditSessionDialog(session, setDialogState);
                                    },
                                    tooltip: 'Renommer',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () async {
                                      final isUsed = await _dbService.isMockExamSessionUsed(session);
                                      if (isUsed) {
                                        showSnackBar(context, 'Impossible de supprimer cette session car des notes y sont associées.', isError: true);
                                      } else {
                                        await _dbService.deleteMockExamSession(session);
                                        // Optional: notify cloud of deletion if desired
                                        try {
                                          await RemoteMockExamsService.instance.deleteSession(session);
                                        } catch (_) {}
                                        
                                        final freshList = await MockExamsSyncService.instance.loadSessions(forceRemote: false);
                                        setDialogState(() => sessions = freshList);
                                        setState(() {
                                          this.sessions = freshList;
                                          if (selectedSession == session) {
                                            selectedSession = freshList.isNotEmpty ? freshList.first : null;
                                            _loadAllData();
                                          }
                                        });
                                      }
                                    },
                                    tooltip: 'Supprimer',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const Divider(),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une session'),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        _showAddSessionDialog(setDialogState);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _showAddSessionDialog(void Function(void Function()) setDialogState) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Ajouter une session'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Nom de la session',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  await _dbService.addMockExamSession(text);
                  await MockExamsSyncService.instance.saveSession(text);
                  
                  final freshList = await MockExamsSyncService.instance.loadSessions(forceRemote: false);
                  setDialogState(() => sessions = freshList);
                  setState(() {
                    this.sessions = freshList;
                    if (selectedSession == null) {
                      selectedSession = freshList.first;
                      _loadAllData();
                    }
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Ajouter'),
            ),
          ],
        );
      },
    );
  }

  void _showEditSessionDialog(String oldName, void Function(void Function()) setDialogState) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Renommer la session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Nouveau nom',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Note: Les notes associées à cette session seront mises à jour automatiquement.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isNotEmpty && text != oldName) {
                  await _dbService.renameMockExamSession(oldName, text);
                  final freshList = await _dbService.getMockExamSessions();
                  setDialogState(() => sessions = freshList);
                  setState(() {
                    this.sessions = freshList;
                    if (selectedSession == oldName) {
                      selectedSession = text;
                      _loadAllData();
                    }
                  });
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGradeTable(ThemeData theme, bool isDark) {
    final filteredStudents = students.where((s) {
      final name = '${s.lastName} ${s.firstName}'.toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    if (filteredStudents.isEmpty) {
      return _buildEmptyState(theme, 'Aucun élève trouvé.');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                 const Expanded(flex: 3, child: Text('Élève', style: TextStyle(fontWeight: FontWeight.bold))),
                 const Expanded(flex: 1, child: Text('Note (/20)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                 const Expanded(flex: 1, child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
               ],
             ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredStudents.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final student = filteredStudents[index];
              final grade = _getGradeForStudent(student.id);
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text('${student.lastName} ${student.firstName}'),
                    ),
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 45,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '-',
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          controller: TextEditingController(
                            text: grade != null ? grade.value.toString() : '',
                          )..selection = TextSelection.fromPosition(
                            TextPosition(offset: (grade != null ? grade.value.toString() : '').length),
                          ),
                          onChanged: (val) => _debounceSave(student, val),
                        ),
                      ),
                    ),
                     Expanded(
                       flex: 1,
                       child: Row(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: [
                           _buildGradeStatusIndicator(grade),
                           const SizedBox(width: 8),
                           IconButton(
                             icon: const Icon(Icons.edit_note, size: 20),
                             onPressed: () => _showStudentFocusDialog(student),
                             tooltip: 'Saisie multi-matières pour cet élève',
                             visualDensity: VisualDensity.compact,
                           ),
                           IconButton(
                             icon: const Icon(Icons.picture_as_pdf, size: 20),
                             onPressed: () => _printStudentResultSlip(student),
                             tooltip: 'Imprimer relevé de notes',
                             visualDensity: VisualDensity.compact,
                             color: Colors.red.withOpacity(0.7),
                           ),
                         ],
                       ),
                     ),
                   ],
                 ),
               );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGradeStatusIndicator(Grade? grade) {
    if (grade == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: const Text(
          'En attente',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      );
    }
    
    final isAbs = grade.value == 0;
    final color = grade.value >= 10 ? const Color(0xFF10B981) : (isAbs ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
    final icon = grade.value >= 10 ? Icons.check_circle : (isAbs ? Icons.cancel : Icons.info);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            grade.value >= 10 ? 'Admis' : (isAbs ? 'Absent' : 'Échoué'),
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(ThemeData theme, bool isDark) {
    final filteredStudents = students.where((s) {
      final name = '${s.lastName} ${s.firstName}'.toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    if (filteredStudents.isEmpty) {
      return _buildEmptyState(theme, 'Aucun élève trouvé.');
    }

    if (subjects.isEmpty) {
      return _buildEmptyState(theme, 'Aucune matière configurée pour cette classe.');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Scrollbar(
        controller: _horizontalScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        radius: const Radius.circular(8),
        thickness: 8,
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Container(
                width: 232 + (subjects.length * 100.0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 200,
                      child: const Text('Élève', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ...subjects.map((sub) => Container(
                      width: 100,
                      child: Text(
                        sub.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                  ],
                ),
              ),
              // Data Rows
              Container(
                height: 500, // Fixed height for scrolling
                width: 232 + (subjects.length * 100.0), // 200 + (subjects * 100) + 32 (padding)
                child: ListView.separated(
                  itemCount: filteredStudents.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final student = filteredStudents[index];
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 200,
                            child: Text('${student.lastName} ${student.firstName}', style: const TextStyle(fontSize: 13)),
                          ),
                          ...subjects.map((sub) {
                            final grade = sessionGrades.firstWhere(
                              (g) => g.studentId == student.id && g.subject == sub.name,
                              orElse: () => Grade(
                                studentId: student.id,
                                className: selectedClass!,
                                academicYear: selectedAcademicYear ?? academicYearNotifier.value,
                                subjectId: sub.id,
                                subject: sub.name,
                                term: selectedSession!,
                                value: 0,
                                type: 'Examen Blanc',
                              ),
                            );
                            
                            final hasGrade = sessionGrades.any((g) => g.studentId == student.id && g.subject == sub.name);
                            final controller = _getController(student, sub, grade, hasGrade);

                            return Container(
                              width: 100,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: TextField(
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '0.0',
                                  hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 11),
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: hasGrade ? (grade.value >= 10 ? Colors.green.withOpacity(0.05) : Colors.red.withOpacity(0.05)) : null,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                                controller: controller,
                                onTap: () {
                                  controller.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: controller.text.length,
                                  );
                                },
                                onChanged: (val) {
                                  _debounceSaveForSubject(student, sub, val);
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _debounceSaveForSubject(Student student, Course sub, String value) {
    final key = '${student.id}_${sub.id}';
    if (_gradeDebouncers.containsKey(key)) {
      _gradeDebouncers[key]!.cancel();
    }
    _gradeDebouncers[key] = Timer(const Duration(milliseconds: 500), () {
      _saveGradeForSubject(student, sub, value);
    });
  }

  Future<void> _saveGradeForSubject(Student student, Course sub, String value) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(context, SafeModeService.instance.getBlockedActionMessage(), isError: true);
      return;
    }

    final double? note = double.tryParse(value);
    if (note == null || note < 0 || note > 20) return;

    await _saveGradeForSubjectSilent(student, sub, note, selectedSession!);
    
    await _loadSessionStats();
    if (!isGridView) await _loadGrades();
  }

  void _showStudentFocusDialog(Student student) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            
            return AlertDialog(
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: Text(student.lastName[0], style: TextStyle(color: theme.colorScheme.primary)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${student.lastName} ${student.firstName}', style: const TextStyle(fontSize: 18)),
                        Text(selectedSession ?? '', style: TextStyle(fontSize: 12, color: theme.disabledColor)),
                      ],
                    ),
                  ),
                ],
              ),
              content: Container(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    children: subjects.map((sub) {
                      final grade = sessionGrades.firstWhere(
                        (g) => g.studentId == student.id && g.subject == sub.name,
                        orElse: () => Grade(studentId: '', className: '', academicYear: '', subjectId: '', subject: '', term: '', value: 0, type: ''),
                      );
                      
                      final hasGrade = grade.id != null;
                      final controller = _getController(student, sub, grade, hasGrade);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            Expanded(child: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w500))),
                            Container(
                              width: 80,
                              child: TextField(
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  hintText: '0.0',
                                  hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 11),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  fillColor: hasGrade && grade.id != null ? (grade.value >= 10 ? Colors.green.withOpacity(0.05) : Colors.red.withOpacity(0.05)) : null,
                                  filled: true,
                                ),
                                controller: controller,
                                onTap: () {
                                  controller.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: controller.text.length,
                                  );
                                },
                                onChanged: (val) async {
                                  _debounceSaveForSubject(student, sub, val);
                                  setDialogState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('/ 20', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // Refresh the page data after closing dialog to ensure table is sync
      _loadSessionStats();
      if (!isGridView) _loadGrades();
    });
  }

  Future<void> _exportGradesTemplate() async {
    if (selectedClass == null) {
      showSnackBar(context, 'Veuillez sélectionner une classe.', isError: true);
      return;
    }

    try {
      showSnackBar(context, 'Génération du modèle Excel...');
      
      final workbook = xls.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'MockExams';

      // Styles
      final headerStyle = workbook.styles.add('headerStyle');
      headerStyle.bold = true;
      headerStyle.backColor = '#E5F2FF';

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
      setHeader(col++, 'Session');
      
      for (final sub in subjects) {
        setHeader(col++, sub.name);
      }

      final year = selectedAcademicYear ?? academicYearNotifier.value;
      for (int i = 0; i < students.length; i++) {
        final row = i + 2;
        final s = students[i];
        sheet.getRangeByIndex(row, 1).setText(s.id);
        sheet.getRangeByIndex(row, 2).setText('${s.lastName} ${s.firstName}');
        sheet.getRangeByIndex(row, 3).setText(selectedClass!);
        sheet.getRangeByIndex(row, 4).setText(year);
        sheet.getRangeByIndex(row, 5).setText(selectedSession);
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'Model_Examen_Blanc_${selectedClass}_$selectedSession.xlsx';
      final path = '${directory.path}/$fileName';
      final file = File(path);
      await file.writeAsBytes(bytes);

      // Audit Log
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'mock_exam',
          action: 'export_excel_template',
          username: u?.username,
          details: 'class=$selectedClass session=$selectedSession file=$fileName',
        );
      } catch (_) {}

      showSnackBar(context, 'Modèle généré avec succès !');
      await OpenFile.open(path);
    } catch (e) {
      showSnackBar(context, 'Erreur lors de l\'export: $e', isError: true);
    }
  }

  Future<void> _importGradesFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (result == null || result.files.single.path == null) return;

      final bytes = await File(result.files.single.path!).readAsBytes();
      final excel = ex.Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first;

      if (sheet.rows.isEmpty) return;

      final headers = sheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();
      
      setState(() => isLoading = true);
      int importedCount = 0;

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final studentId = row[0]?.value?.toString();
        final session = row[4]?.value?.toString();

        if (studentId == null || session == null) continue;

        final student = students.firstWhere((s) => s.id == studentId, orElse: () => Student.empty());
        if (student.id.isEmpty) continue;

        for (int j = 5; j < headers.length; j++) {
          final subjectName = headers[j];
          final noteValue = row[j]?.value?.toString();
          
          if (noteValue != null && noteValue.isNotEmpty) {
            final double? note = double.tryParse(noteValue);
            if (note != null && note >= 0 && note <= 20) {
              final sub = subjects.firstWhere((s) => s.name == subjectName, orElse: () => Course.empty());
              if (sub.id.isNotEmpty) {
                await _saveGradeForSubjectSilent(student, sub, note, session);
                importedCount++;
              }
            }
          }
        }
      }

      await _loadSessionStats();
      if (!isGridView) await _loadGrades();
      setState(() => isLoading = false);
      
      // Audit Log
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'mock_exam',
          action: 'import_excel_grades',
          username: u?.username,
          details: 'class=$selectedClass session=$selectedSession count=$importedCount',
        );
      } catch (_) {}

      showSnackBar(context, '$importedCount notes importées avec succès !');
    } catch (e) {
      setState(() => isLoading = false);
      showSnackBar(context, 'Erreur lors de l\'import: $e', isError: true);
    }
  }

  Future<void> _saveGradeForSubjectSilent(Student student, Course sub, double note, String session) async {
    final year = selectedAcademicYear ?? academicYearNotifier.value;
    final existing = sessionGrades.firstWhere(
      (g) => g.studentId == student.id && g.subject == sub.name && g.term == session,
      orElse: () => Grade(studentId: '', className: '', academicYear: '', subjectId: '', subject: '', term: '', value: 0, type: ''),
    );
    
    final newGrade = Grade(
      id: existing.id,
      studentId: student.id,
      className: selectedClass!,
      academicYear: year,
      subjectId: sub.id,
      subject: sub.name,
      term: session,
      value: note,
      label: session,
      type: 'Examen Blanc',
      coefficient: _subjectCoefficients[sub.id] ?? 1.0,
      maxValue: 20.0,
    );

    if (existing.id == null) {
      await _dbService.insertGrade(newGrade);
    } else {
      await _dbService.updateGrade(newGrade);
    }
  }

  Future<void> _printSessionRankingPdf() async {
    if (students.isEmpty || selectedSession == null) {
      showSnackBar(context, 'Assurez-vous qu\'il y a des élèves dans cette classe.', isError: true);
      return;
    }

    try {
      showSnackBar(context, 'Génération du classement de la session...');
      
      final schoolInfo = await _dbService.getSchoolInfo() ?? SchoolInfo.empty();
      final year = selectedAcademicYear ?? academicYearNotifier.value;

      final pdfBytes = await MockExamPdfService.generateMockExamRankingPdf(
        students: students,
        sessionGrades: sessionGrades,
        session: selectedSession!,
        academicYear: year,
        schoolInfo: schoolInfo,
        className: selectedClass!,
        subjectCoefficients: _subjectCoefficients,
      );

      // Audit Log
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'mock_exam',
          action: 'print_session_ranking_pdf',
          username: u?.username,
          details: 'class=$selectedClass session=$selectedSession',
        );
      } catch (_) {}

      await Printing.layoutPdf(
        onLayout: (format) async => Uint8List.fromList(pdfBytes),
        name: 'Classement_$selectedClass\_$selectedSession.pdf',
      );
    } catch (e) {
      showSnackBar(context, 'Erreur lors de l\'impression: $e', isError: true);
    }
  }

  Future<void> _printSessionSynthesisPdf() async {
    if (students.isEmpty) return;

    final orientation = await _showOrientationDialog();
    if (orientation == null) return;
    final isLandscape = orientation == 'landscape';

    try {
      showSnackBar(context, 'Génération de la synthèse PDF...');
      
      final schoolInfo = await _dbService.getSchoolInfo() ?? SchoolInfo.empty();
      final year = selectedAcademicYear ?? academicYearNotifier.value;
      
      final pdfBytes = await MockExamPdfService.generateMockExamSynthesisPdf(
        students: students,
        sessionGrades: sessionGrades,
        subjects: subjects,
        session: selectedSession!,
        academicYear: year,
        schoolInfo: schoolInfo,
        className: selectedClass!,
        subjectCoefficients: _subjectCoefficients,
        isLandscape: isLandscape,
      );

      // Audit Log
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'mock_exam',
          action: 'print_synthesis_pdf',
          username: u?.username,
          details: 'class=$selectedClass session=$selectedSession orientation=$orientation',
        );
      } catch (_) {}

      await Printing.layoutPdf(
        onLayout: (format) async => Uint8List.fromList(pdfBytes),
        name: 'Synthese_$selectedClass\_$selectedSession.pdf',
      );
    } catch (e) {
      showSnackBar(context, 'Erreur lors de l\'impression: $e', isError: true);
    }
  }

  Future<void> _printStudentResultSlip(Student student) async {
    try {
      showSnackBar(context, 'Génération du relevé pour ${student.lastName}...');
      
      final schoolInfo = await _dbService.getSchoolInfo() ?? SchoolInfo.empty();
      final year = selectedAcademicYear ?? academicYearNotifier.value;
      
      final pdfBytes = await MockExamPdfService.generateMockExamResultSlipsPdf(
        students: [student],
        sessionGrades: sessionGrades,
        subjects: subjects,
        session: selectedSession!,
        academicYear: year,
        schoolInfo: schoolInfo,
        subjectCoefficients: _subjectCoefficients,
      );

      await Printing.layoutPdf(
        onLayout: (format) async => Uint8List.fromList(pdfBytes),
        name: 'Releve_${student.lastName}_$selectedSession.pdf',
      );
    } catch (e) {
      showSnackBar(context, 'Erreur lors de l\'impression: $e', isError: true);
    }
  }

  Future<void> _printAllResultSlips() async {
    if (students.isEmpty) return;

    final orientation = await _showOrientationDialog();
    if (orientation == null) return;
    final isLandscape = orientation == 'landscape';

    try {
      showSnackBar(context, 'Génération des relevés pour la classe...');
      
      final schoolInfo = await _dbService.getSchoolInfo() ?? SchoolInfo.empty();
      final year = selectedAcademicYear ?? academicYearNotifier.value;
      
      final pdfBytes = await MockExamPdfService.generateMockExamResultSlipsPdf(
        students: students,
        sessionGrades: sessionGrades,
        subjects: subjects,
        session: selectedSession!,
        academicYear: year,
        schoolInfo: schoolInfo,
        subjectCoefficients: _subjectCoefficients,
        isLandscape: isLandscape,
      );

      // Audit Log
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'mock_exam',
          action: 'print_all_slips_pdf',
          username: u?.username,
          details: 'class=$selectedClass session=$selectedSession count=${students.length} orientation=$orientation',
        );
      } catch (_) {}

      await Printing.layoutPdf(
        onLayout: (format) async => Uint8List.fromList(pdfBytes),
        name: 'Releves_$selectedClass\_$selectedSession.pdf',
      );
    } catch (e) {
      showSnackBar(context, 'Erreur lors de l\'impression: $e', isError: true);
    }
  }

  Widget _buildTopStudents(ThemeData theme, bool isDark) {
    if (sessionGrades.isEmpty || students.isEmpty) return const SizedBox.shrink();

    // Group grades by student and calculate average
    final Map<String, List<double>> studentGradesMap = {};
    for (final g in sessionGrades) {
      studentGradesMap.putIfAbsent(g.studentId, () => []).add(g.value);
    }

    final List<MapEntry<String, double>> studentAvgs = studentGradesMap.entries.map((entry) {
      final grades = sessionGrades.where((g) => g.studentId == entry.key);
      double weightedSum = 0;
      double coeffSum = 0;
      for (final g in grades) {
        final coeff = _subjectCoefficients[g.subjectId] ?? 1.0;
        weightedSum += (g.value * coeff);
        coeffSum += coeff;
      }
      final avg = coeffSum > 0 ? weightedSum / coeffSum : 0.0;
      return MapEntry(entry.key, avg);
    }).toList();

    studentAvgs.sort((a, b) => b.value.compareTo(a.value));
    final top3 = studentAvgs.take(3).toList();

    if (top3.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Text('Tableau d\'Honneur (Top 3 Session)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: top3.asMap().entries.map((entry) {
            final index = entry.key;
            final studentEntry = entry.value;
            final student = students.firstWhere((s) => s.id == studentEntry.key, orElse: () => Student.empty());
            
            final color = index == 0 ? Colors.amber[700]! : (index == 1 ? Colors.grey[600]! : Colors.brown[600]!);

            return Expanded(
              child: Card(
                elevation: 2,
                margin: EdgeInsets.only(right: index < top3.length - 1 ? 16 : 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${index + 1}', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${student.lastName} ${student.firstName}', 
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('${studentEntry.value.toStringAsFixed(2)} / 20', style: TextStyle(fontSize: 11, color: theme.disabledColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _printMockExamsZip() async {
    if (students.isEmpty) return;

    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(context, SafeModeService.instance.getBlockedActionMessage(), isError: true);
      return;
    }

    final orientation = await _showOrientationDialog();
    if (orientation == null) return;
    final isLandscape = orientation == 'landscape';

    try {
      showSnackBar(context, 'Génération de l\'archive ZIP en cours...');
      final archive = Archive();
      final schoolInfo = await _dbService.getSchoolInfo() ?? SchoolInfo.empty();
      final year = selectedAcademicYear ?? academicYearNotifier.value;

      for (final student in students) {
        final pdfBytes = await MockExamPdfService.generateMockExamResultSlipsPdf(
          students: [student],
          sessionGrades: sessionGrades,
          subjects: subjects,
          session: selectedSession!,
          academicYear: year,
          schoolInfo: schoolInfo,
          subjectCoefficients: _subjectCoefficients,
          isLandscape: isLandscape,
        );

        final safeName = '${student.lastName}_${student.firstName}'.replaceAll(' ', '_');
        final fileName = 'Releve_${safeName}_$selectedSession.pdf';
        archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));
      }

      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);
      if (zipBytes == null) throw Exception('Erreur encodage ZIP');

      final directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisir le dossier de sauvegarde',
      );
      
      if (directory != null) {
        final safeClass = PdfService.sanitizeFileName(selectedClass!);
        final zipFileName = 'Archive_Examens_${safeClass}_$selectedSession.zip';
        final file = File('$directory/$zipFileName');
        await file.writeAsBytes(zipBytes);

        // Audit Log
        try {
          final u = await AuthService.instance.getCurrentUser();
          await _dbService.logAudit(
            category: 'mock_exam',
            action: 'export_zip_slips',
            username: u?.username,
            details: 'class=$selectedClass session=$selectedSession count=${students.length} file=$zipFileName',
          );
        } catch (_) {}

        showSnackBar(context, 'Archive ZIP exportée dans $directory', isError: false);
      }
    } catch (e) {
      showSnackBar(context, 'Erreur lors de l\'export ZIP: $e', isError: true);
    }
  }

  Future<String?> _showOrientationDialog() async {
    return showDialog<String>(
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
    );
  }

  Widget _buildExcelActionsMenu(ThemeData theme) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'template') _exportGradesTemplate();
        if (val == 'import') _importGradesFromExcel();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'template',
          child: Row(children: [Icon(Icons.download, size: 20), SizedBox(width: 8), Text('Générer Modèle Excel')]),
        ),
        const PopupMenuItem(
          value: 'import',
          child: Row(children: [Icon(Icons.upload, size: 20), SizedBox(width: 8), Text('Importer depuis Excel')]),
        ),
      ],
      child: ElevatedButton.icon(
        onPressed: null, // Let the PopupMenuButton handle the click
        icon: const Icon(Icons.table_chart, size: 18),
        label: const Text('Actions Excel'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.withOpacity(0.1),
          foregroundColor: Colors.blue,
          disabledBackgroundColor: Colors.blue.withOpacity(0.1),
          disabledForegroundColor: Colors.blue,
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildPdfActionsMenu(ThemeData theme) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'ranking') _printSessionRankingPdf();
        if (val == 'synthesis') _printSessionSynthesisPdf();
        if (val == 'print_all') _printAllResultSlips();
        if (val == 'zip') _printMockExamsZip();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'ranking',
          child: Row(children: [Icon(Icons.format_list_numbered, size: 20, color: Colors.blue), SizedBox(width: 8), Text('Palmarès (Classement)')]),
        ),
        const PopupMenuItem(
          value: 'synthesis',
          child: Row(children: [Icon(Icons.summarize, size: 20, color: Colors.orange), SizedBox(width: 8), Text('Synthèse PDF (Tableau)')]),
        ),
        const PopupMenuItem(
          value: 'print_all',
          child: Row(children: [Icon(Icons.print, size: 20, color: Colors.purple), SizedBox(width: 8), Text('Imprimer tous les relevés')]),
        ),
        const PopupMenuItem(
          value: 'zip',
          child: Row(children: [Icon(Icons.folder_zip, size: 20, color: Colors.red), SizedBox(width: 8), Text('Exporter Archive ZIP')]),
        ),
      ],
      child: ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.picture_as_pdf, size: 18),
        label: const Text('Actions d\'Export'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.withOpacity(0.1),
          foregroundColor: Colors.orange,
          disabledBackgroundColor: Colors.orange.withOpacity(0.1),
          disabledForegroundColor: Colors.orange,
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 64, color: theme.disabledColor),
          const SizedBox(height: 16),
          Text(message, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
