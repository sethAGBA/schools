import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';

import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/statistics_pdf_service.dart';
import 'package:school_manager/services/statistics_excel_service.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/services/pdf_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({Key? key}) : super(key: key);

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _db = DatabaseService();
  final StatisticsPdfService _pdfService = StatisticsPdfService();
  final StatisticsExcelService _excelService = StatisticsExcelService();

  String _selectedYear = '';
  List<String> _availableYears = [];

  // Filters
  String? _selectedClass;
  List<String> _availableClasses = [];
  String? _selectedTerm;
  final List<String> _availableTerms = [
    'Trimestre 1',
    'Trimestre 2',
    'Trimestre 3',
    'Semestre 1',
    'Semestre 2',
  ];
  int _rankLimit = 5;
  final List<int> _availableLimits = [5, 10, 20];

  bool _isLoading = false;

  Map<String, dynamic> _academicStats = {};
  Map<String, dynamic> _disciplineStats = {};
  Map<String, dynamic> _demographicStats = {};
  Map<String, dynamic> _financeStats = {};
  Map<String, dynamic> _advancedAcademicStats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    _selectedYear = await getCurrentAcademicYear();
    _availableYears = [_selectedYear, '2023-2024', '2022-2023'];
    await _loadClasses(); // Fetch classes
    await _refreshStats();
  }

  Future<void> _loadClasses() async {
    final classes = await _db.getClassesByYear(_selectedYear);
    if (mounted) {
      setState(() {
        _availableClasses = classes.map((c) => c.name).toList()..sort();
      });
    }
  }

  Future<void> _refreshStats() async {
    setState(() => _isLoading = true);
    try {
      final academic = await _db.getGlobalAcademicStats(_selectedYear);
      final discipline = await _db.getDisciplineStats(_selectedYear);
      final demo = await _db.getDemographicStats(_selectedYear);
      final finance = await _db.getFinanceStats(_selectedYear);
      final advanced = await _db.getAdvancedAcademicStats(
        _selectedYear,
        className: _selectedClass,
        term: _selectedTerm,
        limit: _rankLimit,
      );

      if (mounted) {
        setState(() {
          _academicStats = academic;
          _disciplineStats = discipline;
          _demographicStats = demo;
          _financeStats = finance;
          _advancedAcademicStats = advanced;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, isDarkMode, isDesktop),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildStatsContent(context, theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDarkMode, bool isDesktop) {
    final theme = Theme.of(context);
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
                      Icons.analytics,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tableau de Bord Statistique',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Visualisez les performances académiques, disciplinaires, démographiques et financières.',
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
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
    );
  }

  // Removed _buildExportButton from here as it's now internal to tabs

  Future<void> _exportTabPdf(int index) async {
    setState(() => _isLoading = true);
    try {
      if (!SafeModeService.instance.isActionAllowed()) {
        _showModernSnackBar(
          SafeModeService.instance.getBlockedActionMessage(),
          isError: true,
        );
        return;
      }

      final directoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisir le dossier de sauvegarde',
      );

      if (directoryPath == null) {
        setState(() => _isLoading = false);
        return;
      }

      Uint8List? pdfBytes;
      String fileName = '';

      switch (index) {
        case 0:
          pdfBytes = await _pdfService.exportAcademicReport(
            stats: _advancedAcademicStats,
            year: _selectedYear,
            className: _selectedClass,
            term: _selectedTerm,
          );
          fileName =
              'Rapport_Academique_${_selectedYear}_${_selectedClass ?? "Tous"}.pdf';
          break;
        case 1:
          pdfBytes = await _pdfService.exportDisciplineReport(
            stats: _disciplineStats,
            year: _selectedYear,
          );
          fileName = 'Rapport_Discipline_${_selectedYear}.pdf';
          break;
        case 2:
          pdfBytes = await _pdfService.exportDemographicReport(
            stats: _demographicStats,
            year: _selectedYear,
          );
          fileName = 'Rapport_Demographique_${_selectedYear}.pdf';
          break;
        case 3:
          pdfBytes = await _pdfService.exportFinanceReport(
            stats: _financeStats,
            year: _selectedYear,
          );
          fileName = 'Rapport_Financier_${_selectedYear}.pdf';
          break;
      }

      if (pdfBytes != null) {
        final safeFileName = PdfService.sanitizeFileName(fileName);
        final file = File('$directoryPath/$safeFileName');
        await PdfService.ensureParentDirectory(file);
        await file.writeAsBytes(pdfBytes, flush: true);
        _showModernSnackBar('Rapport enregistré : $safeFileName');
        try {
          await OpenFile.open(file.path);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Erreur export PDF: $e');
      if (mounted) {
        _showModernSnackBar('Erreur lors de l\'export PDF: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportTabExcel(int index) async {
    setState(() => _isLoading = true);
    try {
      if (!SafeModeService.instance.isActionAllowed()) {
        _showModernSnackBar(
          SafeModeService.instance.getBlockedActionMessage(),
          isError: true,
        );
        return;
      }

      final directoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisir le dossier de sauvegarde',
      );

      if (directoryPath == null) {
        setState(() => _isLoading = false);
        return;
      }

      Uint8List? excelBytes;
      String fileName = '';

      switch (index) {
        case 0:
          excelBytes = await _excelService.generateAcademicExcel(
            stats: _advancedAcademicStats,
            academicYear: _selectedYear,
          );
          fileName =
              'Stats_Academiques_${_selectedYear}_${_selectedClass ?? "Tous"}.xlsx';
          break;
        case 1:
          excelBytes = await _excelService.generateDisciplineExcel(
            stats: _disciplineStats,
            academicYear: _selectedYear,
          );
          fileName = 'Stats_Discipline_${_selectedYear}.xlsx';
          break;
        case 2:
          excelBytes = await _excelService.generateDemographicExcel(
            stats: _demographicStats,
            academicYear: _selectedYear,
          );
          fileName = 'Stats_Demographie_${_selectedYear}.xlsx';
          break;
        case 3:
          excelBytes = await _excelService.generateFinanceExcel(
            stats: _financeStats,
            academicYear: _selectedYear,
          );
          fileName = 'Stats_Finance_${_selectedYear}.xlsx';
          break;
      }

      if (excelBytes != null) {
        final safeFileName = PdfService.sanitizeFileName(fileName);
        final file = File('$directoryPath/$safeFileName');
        await PdfService.ensureParentDirectory(file);
        await file.writeAsBytes(excelBytes, flush: true);
        _showModernSnackBar('Rapport Excel enregistré : $safeFileName');
        try {
          await OpenFile.open(file.path);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Erreur export Excel: $e');
      if (mounted) {
        _showModernSnackBar(
          'Erreur lors de l\'export Excel: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTabExportButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildStatsContent(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // TabBar Styled
            Container(
              margin: const EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: 0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: theme.cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(text: 'Académique', icon: Icon(Icons.school, size: 20)),
                    Tab(text: 'Discipline', icon: Icon(Icons.gavel, size: 20)),
                    Tab(
                      text: 'Démographie',
                      icon: Icon(Icons.people, size: 20),
                    ),
                    Tab(
                      text: 'Finances',
                      icon: Icon(Icons.attach_money, size: 20),
                    ),
                  ],
                ),
              ),
            ),

            // Filters Row (Year, Class, Period, Limit)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Year Selector
                    _buildFilterDropdown(
                      hint: 'Année',
                      value: _availableYears.contains(_selectedYear)
                          ? _selectedYear
                          : null,
                      items: _availableYears,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedYear = val);
                          _refreshStats();
                        }
                      },
                    ),
                    const SizedBox(width: 12),

                    // Class Selector
                    _buildFilterDropdown(
                      hint: 'Classe (Toutes)',
                      value: _availableClasses.contains(_selectedClass)
                          ? _selectedClass
                          : null,
                      items: _availableClasses,
                      onChanged: (val) {
                        setState(() => _selectedClass = val);
                        _refreshStats();
                      },
                      showClear: true,
                    ),
                    const SizedBox(width: 12),

                    // Term Selector
                    _buildFilterDropdown(
                      hint: 'Période (Toutes)',
                      value: _availableTerms.contains(_selectedTerm)
                          ? _selectedTerm
                          : null,
                      items: _availableTerms,
                      onChanged: (val) {
                        setState(() => _selectedTerm = val);
                        _refreshStats();
                      },
                      showClear: true,
                    ),
                    const SizedBox(width: 12),

                    // Rank Limit Selector
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Text('Top:', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 8),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _rankLimit,
                              isDense: true,
                              icon: const Icon(Icons.arrow_drop_down, size: 20),
                              items: _availableLimits.map((l) {
                                return DropdownMenuItem(
                                  value: l,
                                  child: Text(l.toString()),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _rankLimit = val);
                                  _refreshStats();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAcademicTab(),
                  _buildDisciplineTab(),
                  _buildDemographicTab(),
                  _buildFinanceTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcademicTab() {
    // Advanced Stats are more comprehensive
    final successRate =
        (_advancedAcademicStats['globalSuccessRate'] as num?)?.toDouble() ??
        0.0;
    final globalAvg =
        (_advancedAcademicStats['globalAverage'] as num?)?.toDouble() ?? 0.0;
    final prevGlobalAvg =
        (_advancedAcademicStats['previousGlobalAverage'] as num?)?.toDouble();

    final topStudents =
        _advancedAcademicStats['topStudents'] as List<dynamic>? ?? [];
    final bottomStudents =
        _advancedAcademicStats['bottomStudents'] as List<dynamic>? ?? [];
    final subjectStats =
        _advancedAcademicStats['subjectStats'] as List<dynamic>? ?? [];
    final dist = (_academicStats['distribution'] as Map?) ?? {};
    final classAvgs =
        (_academicStats['classAverages'] as Map?)?.cast<String, double>() ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTabExportButton(
                  label: 'Exporter PDF',
                  icon: Icons.picture_as_pdf,
                  color: const Color(0xFF6366F1),
                  onPressed: () => _exportTabPdf(0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTabExportButton(
                  label: 'Exporter Excel',
                  icon: Icons.table_view,
                  color: Colors.green,
                  onPressed: () => _exportTabExcel(0),
                ),
              ),
            ],
          ),
          _buildSectionHeader(
            title: 'Vue d\'ensemble',
            subtitle: 'Aperçu des performances globales',
            icon: Icons.analytics,
          ),
          // KPI Row
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Moyenne Générale',
                  value: globalAvg.toStringAsFixed(2),
                  color: Colors.blue,
                  icon: Icons.analytics,
                  comparisonValue: prevGlobalAvg,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Réussite',
                  value: '${successRate.toStringAsFixed(1)}%',
                  subtitle:
                      '${_advancedAcademicStats['totalSuccess'] ?? 0} élèves',
                  color: Colors.green,
                  icon: Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Échec',
                  value:
                      '${(_advancedAcademicStats['globalFailureRate'] as num? ?? 0.0).toDouble().toStringAsFixed(1)}%',
                  subtitle:
                      '${_advancedAcademicStats['totalFailure'] ?? 0} élèves',
                  color: Colors.red,
                  icon: Icons.error_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Detailed Breakdowns (Gender & Status)
          const Text(
            '📊 Détails par Sexe et Statut',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gender Breakdown
              Expanded(
                child: _buildBreakdownSection(
                  title: 'Par Sexe',
                  stats: (_advancedAcademicStats['genderStats'] as Map?) ?? {},
                  icon: Icons.wc,
                ),
              ),
              const SizedBox(width: 16),
              // Status Breakdown
              Expanded(
                child: _buildBreakdownSection(
                  title: 'Par Statut',
                  stats: (_advancedAcademicStats['statusStats'] as Map?) ?? {},
                  icon: Icons.badge_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildGradeDistributionChart(
            _advancedAcademicStats['gradeDistribution'] ?? {},
          ),
          const SizedBox(height: 32),
          _buildSectionHeader(
            title: 'Performance par Classe',
            subtitle: 'Réussite et effectifs par classe',
            icon: Icons.class_outlined,
          ),
          const SizedBox(height: 24),

          // Top & Bottom Students
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏆 Top $_rankLimit Élèves',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...topStudents.map((s) => _buildStudentRankItem(s, true)),
                    if (topStudents.isEmpty) const Text('Aucune donnée'),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚠️ En Difficulté (Bottom $_rankLimit)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...bottomStudents.map(
                      (s) => _buildStudentRankItem(s, false),
                    ),
                    if (bottomStudents.isEmpty) const Text('Aucune donnée'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          const Text(
            'Répartition des Moyennes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: dist.entries.map((e) {
                  final val = (e.value as num).toDouble();
                  final color = _getColorForRange(e.key);
                  return PieChartSectionData(
                    color: color,
                    value: val,
                    title: '${e.key}\n${val.toInt()}',
                    radius: 60,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Performance par Matière',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (subjectStats.isNotEmpty)
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 22,
                  barGroups: subjectStats.asMap().entries.map((e) {
                    final index = e.key;
                    final data = e.value;
                    final avg = (data['average'] as num).toDouble();
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: avg,
                          color: avg >= 10 ? Colors.blueAccent : Colors.orange,
                          width: 12,
                          borderRadius: BorderRadius.circular(4),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 20,
                            color: Colors.grey.withOpacity(0.1),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        getTitlesWidget: (val, meta) {
                          final index = val.toInt();
                          if (index >= 0 && index < subjectStats.length) {
                            final name =
                                subjectStats[index]['subject'] as String;
                            // Truncate if too long
                            final shortName = name.length > 8
                                ? '${name.substring(0, 8)}...'
                                : name;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: Text(
                                  shortName,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                ),
              ),
            )
          else
            const Text('Pas de données par matière'),

          const SizedBox(height: 32),
          const Text(
            '📈 Succès et Échec par Classe',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildClassPassRateList(),
          const SizedBox(height: 32),

          const Text(
            '📋 Tableau Récapitulatif Détaillé',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildIntersectionalTable(),
          const SizedBox(height: 32),

          const Text(
            'Moyenne par Classe',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 20,
                barGroups: classAvgs.entries.map((e) {
                  return BarChartGroupData(
                    x: e.key.hashCode,
                    barRods: [
                      BarChartRodData(
                        toY: e.value,
                        color: Colors.indigo,
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        // Récupération approximative du nom via le hashcode
                        final entry = classAvgs.entries.firstWhere(
                          (e) => e.key.hashCode == val.toInt(),
                          orElse: () => MapEntry('', 0),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
              ),
            ),
          ),
          _buildClassAverageChart(classAvgs),
        ],
      ),
    );
  }

  Widget _buildClassPassRateList() {
    final classStats = (_advancedAcademicStats['classStats'] as Map?) ?? {};
    if (classStats.isEmpty) return const Text('Aucune donnée par classe');

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800
            ? 3
            : (constraints.maxWidth > 500 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.5,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: classStats.length,
          itemBuilder: (context, index) {
            final entry = classStats.entries.elementAt(index);
            final className = entry.key;
            final data = (entry.value as Map).cast<String, int>();
            final success = data['success'] ?? 0;
            final total = data['total'] ?? 1;
            final rate = (success / total) * 100;
            final color = rate >= 50 ? Colors.green : Colors.red;

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
                ),
                border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          className,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${rate.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '$success / $total élèves admis',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: rate / 100,
                      minHeight: 8,
                      backgroundColor: color.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIntersectionalTable() {
    final stats =
        _advancedAcademicStats['intersectionalStats'] as List<dynamic>? ?? [];
    if (stats.isEmpty) return const Text('Aucune donnée détaillée');

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 56,
            dataRowHeight: 60,
            horizontalMargin: 24,
            columnSpacing: 32,
            headingRowColor: MaterialStateProperty.all(
              Theme.of(context).primaryColor.withOpacity(0.05),
            ),
            columns: const [
              DataColumn(
                label: Text(
                  'CLASSE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              DataColumn(
                label: Text(
                  'STATUT',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              DataColumn(
                label: Text(
                  'GENRE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              DataColumn(
                label: Text(
                  'EFFECTIF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              DataColumn(
                label: Text(
                  'RÉUSSITE (%)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
            rows: stats.map((s) {
              final total = s['total'] as int;
              final success = s['success'] as int;
              final rate = total > 0 ? (success / total) * 100 : 0.0;
              final color = rate >= 50 ? Colors.green : Colors.red;

              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      s['class'] ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        s['status'] ?? '-',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(s['gender'] ?? '-')),
                  DataCell(
                    Text(
                      total.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${rate.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildClassAverageChart(Map<String, double> classAvgs) {
    return SizedBox(
      height: 300,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 20,
          barGroups: classAvgs.entries.map((e) {
            return BarChartGroupData(
              x: e.key.hashCode,
              barRods: [
                BarChartRodData(
                  toY: e.value,
                  color: Colors.indigo,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final entry = classAvgs.entries.firstWhere(
                    (e) => e.key.hashCode == val.toInt(),
                    orElse: () => MapEntry('', 0),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 30),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentRankItem(dynamic s, bool isTop) {
    final name = s['name'];
    final className = s['className'];
    final avg = (s['average'] as num).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isTop
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTop
              ? Colors.green.withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                className,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                avg.toStringAsFixed(2),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isTop ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDisciplineTab() {
    final absMonth =
        (_disciplineStats['absencesByMonth'] as Map?)
            ?.cast<String, dynamic>() ??
        {};
    final sanctionsClass =
        (_disciplineStats['sanctionsByClass'] as Map?)
            ?.cast<String, dynamic>() ??
        {};

    // Trier les mois
    final sortedMonths = absMonth.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTabExportButton(
                  label: 'Exporter PDF',
                  icon: Icons.picture_as_pdf,
                  color: Colors.red,
                  onPressed: () => _exportTabPdf(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTabExportButton(
                  label: 'Exporter Excel',
                  icon: Icons.table_view,
                  color: Colors.green,
                  onPressed: () => _exportTabExcel(1),
                ),
              ),
            ],
          ),
          _buildSectionHeader(
            title: 'Analyse Disciplinaire',
            subtitle: 'Suivi des absences et sanctions',
            icon: Icons.gavel_rounded,
          ),
          const SizedBox(height: 24),
          const Text(
            'Absences par Mois',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final index = val.toInt();
                        if (index >= 0 && index < sortedMonths.length) {
                          return Text(
                            sortedMonths[index],
                            style: const TextStyle(fontSize: 10),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: sortedMonths.asMap().entries.map((e) {
                      return FlSpot(
                        e.key.toDouble(),
                        (absMonth[e.value] as num).toDouble(),
                      );
                    }).toList(),
                    isCurved: true,
                    color: Colors.red,
                    barWidth: 4,
                    dotData: FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Sanctions par Classe',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Similaire BarChart pour sanctions...
          _buildSimpleBarChart(sanctionsClass, Colors.orange),
          const SizedBox(height: 32),
          const Text(
            '🕵️ Élèves les plus absents (Top 10)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if ((_disciplineStats['topAbsentStudents'] as List?)?.isNotEmpty ??
              false)
            ...(_disciplineStats['topAbsentStudents'] as List).map((s) {
              final name = s['name'];
              final className = s['className'];
              final count = s['count'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.withOpacity(0.1),
                    child: Text(
                      count.toString(),
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(className),
                  trailing: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                  ),
                ),
              );
            })
          else
            const Center(child: Text('Aucune absence enregistrée')),
        ],
      ),
    );
  }

  Widget _buildDemographicTab() {
    final gender =
        (_demographicStats['gender'] as Map?)?.cast<String, dynamic>() ?? {};
    final age = (_demographicStats['age'] as Map?)?.cast<String, int>() ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTabExportButton(
                  label: 'Exporter PDF',
                  icon: Icons.picture_as_pdf,
                  color: const Color(0xFF14B8A6),
                  onPressed: () => _exportTabPdf(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTabExportButton(
                  label: 'Exporter Excel',
                  icon: Icons.table_view,
                  color: Colors.green,
                  onPressed: () => _exportTabExcel(2),
                ),
              ),
            ],
          ),
          _buildSectionHeader(
            title: 'Démographie des élèves',
            subtitle: 'Répartition par genre et par âge',
            icon: Icons.wc,
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Répartition Garçons / Filles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: PieChart(
              PieChartData(
                sections: gender.entries.map((e) {
                  return PieChartSectionData(
                    value: (e.value as num).toDouble(),
                    title: '${e.key}\\n${e.value}',
                    color: e.key.toString().toLowerCase().startsWith('f')
                        ? Colors.pink
                        : Colors.blue,
                    radius: 80,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'Répartition G/F',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sections: gender.entries.map((e) {
                            return PieChartSectionData(
                              value: (e.value as num).toDouble(),
                              title: '${e.key}\n${e.value}',
                              color:
                                  e.key.toString().toLowerCase().startsWith('f')
                                  ? Colors.pink
                                  : Colors.blue,
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'Nouveaux / Anciens',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sections:
                              ((_demographicStats['status'] as Map?) ?? {})
                                  .entries
                                  .map((e) {
                                    return PieChartSectionData(
                                      value: (e.value as num).toDouble(),
                                      title: '${e.key}\n${e.value}',
                                      color: e.key == 'Nouveau'
                                          ? Colors.teal
                                          : Colors.amber,
                                      radius: 60,
                                      titleStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    );
                                  })
                                  .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Pyramide des Âges',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildSimpleBarChart(age.map((k, v) => MapEntry(k, v)), Colors.teal),
          _buildSimpleBarChart(
            age.map((k, v) => MapEntry(k, v)),
            Colors.indigo,
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceTab() {
    final totalIncome = (_financeStats['totalIncome'] as num?)?.toDouble() ?? 0.0;
    final totalExpense = (_financeStats['totalExpense'] as num?)?.toDouble() ?? 0.0;
    final balance = (_financeStats['balance'] as num?)?.toDouble() ?? 0.0;
    final incomeByMonth =
        (_financeStats['incomeByMonth'] as Map?)?.cast<String, dynamic>() ?? {};
    final expenseByMonth =
        (_financeStats['expenseByMonth'] as Map?)?.cast<String, dynamic>() ??
        {};
    final expenseByCategory =
        (_financeStats['expenseByCategory'] as Map?)?.cast<String, dynamic>() ??
        {};

    // Merge months for display
    final allMonths = {...incomeByMonth.keys, ...expenseByMonth.keys}.toList()
      ..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTabExportButton(
                  label: 'Exporter PDF',
                  icon: Icons.picture_as_pdf,
                  color: const Color(0xFF10B981),
                  onPressed: () => _exportTabPdf(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTabExportButton(
                  label: 'Exporter Excel',
                  icon: Icons.table_view,
                  color: Colors.green,
                  onPressed: () => _exportTabExcel(3),
                ),
              ),
            ],
          ),
          _buildSectionHeader(
            title: 'Analyse Financière',
            subtitle: 'Revenus, dépenses et solde net',
            icon: Icons.payments_outlined,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Encaissements',
                  value: '${totalIncome.toStringAsFixed(0)} FCFA',
                  color: Colors.green,
                  icon: Icons.attach_money,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Dépenses',
                  value: '${totalExpense.toStringAsFixed(0)} FCFA',
                  color: Colors.red,
                  icon: Icons.money_off,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSummaryCard(
            title: 'Solde Net',
            value: '${balance.toStringAsFixed(0)} FCFA',
            color: balance >= 0 ? Colors.blue : Colors.red,
            icon: Icons.account_balance,
          ),
          const SizedBox(height: 32),
          const Text(
            'Évolution Mensuelle',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final index = val.toInt();
                        if (index >= 0 && index < allMonths.length) {
                          return Text(
                            allMonths[index],
                            style: const TextStyle(fontSize: 10),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: allMonths.asMap().entries.map((e) {
                      final month = e.value; // ex: "01"
                      final val = (incomeByMonth[month] as num? ?? 0.0)
                          .toDouble();
                      return FlSpot(e.key.toDouble(), val);
                    }).toList(),
                    color: Colors.green,
                    barWidth: 3,
                    isCurved: true,
                    dotData: FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: allMonths.asMap().entries.map((e) {
                      final month = e.value;
                      final val = (expenseByMonth[month] as num? ?? 0.0)
                          .toDouble();
                      return FlSpot(e.key.toDouble(), val);
                    }).toList(),
                    color: Colors.red,
                    barWidth: 3,
                    isCurved: true,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Dépenses par Catégorie',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: expenseByCategory.entries.map((e) {
                  final val = (e.value as num).toDouble();
                  // Génère une couleur unique basée sur le hash de la clé
                  final color = Colors
                      .primaries[e.key.hashCode % Colors.primaries.length];
                  return PieChartSectionData(
                    color: color,
                    value: val,
                    title: '${e.key}\n${val.toInt()}',
                    radius: 70,
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleBarChart(Map<String, dynamic> data, Color color) {
    if (data.isEmpty)
      return const SizedBox(
        height: 50,
        child: Center(child: Text('Pas de données')),
      );

    // Convertir Map<String, dynamic> en liste exploitable avec index
    final entries = data.entries.toList();

    return SizedBox(
      height: 300,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY:
              (data.values.map((e) => (e as num).toDouble()).reduce(max) *
              1.2), // Echelle dynamique
          barGroups: entries.asMap().entries.map((e) {
            final index = e.key;
            final val = (e.value.value as num).toDouble();
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: val,
                  color: color,
                  width: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final index = val.toInt();
                  if (index >= 0 && index < entries.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        entries[index].key,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 30),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
        ),
      ),
    );
  }

  double max(double a, double b) => a > b ? a : b;

  Color _getColorForRange(String range) {
    switch (range) {
      case '<10':
        return Colors.red;
      case '10-12':
        return Colors.orange;
      case '12-14':
        return Colors.yellow.shade700;
      case '14-16':
        return Colors.lightGreen;
      case '>16':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    double? comparisonValue,
    String? subtitle,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    double? comparisonValue,
  }) {
    double? diff;
    if (comparisonValue != null) {
      final current = double.tryParse(value.replaceAll('%', '')) ?? 0.0;
      diff = current - comparisonValue;
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.1), width: 1),
      ),
      child: Stack(
        children: [
          // Background accent
          Positioned(
            right: -20,
            top: -20,
            child: CircleAvatar(
              radius: 40,
              backgroundColor: color.withOpacity(0.05),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    if (diff != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (diff >= 0 ? Colors.green : Colors.red)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              diff >= 0
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              size: 14,
                              color: diff >= 0 ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: diff >= 0 ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: color,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    bool showClear = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<T>(
              value: value,
              isDense: true,
              hint: Text(
                hint,
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color,
                  fontSize: 13,
                ),
              ),
              icon: Icon(
                Icons.arrow_drop_down,
                color: theme.iconTheme.color,
                size: 20,
              ),
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
                fontSize: 13,
              ),
              items: items.map((item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(item.toString()),
                );
              }).toList(),
              onChanged: onChanged,
            ),
            if (showClear && value != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => onChanged(null),
                child: Icon(Icons.close, size: 16, color: theme.hintColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownSection({
    required String title,
    required Map stats,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    if (stats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
        ),
        child: Text(
          'Aucune donnée pour $title',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: theme.primaryColor),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...stats.entries.map((e) {
              final category = e.key;
              final data = (e.value as Map).cast<String, int>();
              final success = data['success'] ?? 0;
              final total = data['total'] ?? 1;
              final rate = (success / total) * 100;
              final color = rate >= 50 ? Colors.green : Colors.red;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          category,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${rate.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 14,
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Stack(
                      children: [
                        Container(
                          height: 6,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: theme.dividerColor.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          height: 6,
                          width:
                              (MediaQuery.of(context).size.width /
                                  (MediaQuery.of(context).size.width > 800
                                      ? 6
                                      : 2)) *
                              (rate / 100),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color, color.withOpacity(0.6)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$success admis sur $total',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.primaryColor, size: 24),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: theme.textTheme.bodySmall?.color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGradeDistributionChart(Map<String, dynamic> distribution) {
    if (distribution.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final labels = [
      '[0-5[',
      '[5-10[',
      '[10-12[',
      '[12-14[',
      '[14-16[',
      '[16-20]',
    ];
    final counts = labels.map((l) => (distribution[l] ?? 0) as int).toList();
    final int total = counts.fold(0, (a, b) => a + b);

    final colors = [
      Colors.red.shade400,
      Colors.orange.shade400,
      Colors.amber.shade600,
      Colors.lightGreen.shade500,
      Colors.green.shade600,
      Colors.teal.shade600,
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bar_chart,
                  size: 20,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Répartition Générale des Notes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(labels.length, (index) {
                final count = counts[index];
                final ratio = total > 0 ? count / total : 0.0;
                final barColor = colors[index];

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: barColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: (ratio * 140).clamp(4.0, 140.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [barColor, barColor.withOpacity(0.7)],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: barColor.withOpacity(0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      FittedBox(
                        child: Text(
                          labels[index],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  void _showModernSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
