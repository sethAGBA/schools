import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';
import '../widgets/stats_card.dart';
import '../widgets/activity_item.dart';
import '../widgets/quick_action.dart';
import 'package:school_manager/utils/date_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_manager/services/license_service.dart';
import 'package:school_manager/screens/students/student_profile_page.dart';

ValueNotifier<String> academicYearNotifier = ValueNotifier<String>('2024-2025');

Future<void> refreshAcademicYear() async {
  final prefs = await SharedPreferences.getInstance();
  academicYearNotifier.value = prefs.getString('academic_year') ?? '2024-2025';
}

class DashboardHome extends StatefulWidget {
  final Function(int) onNavigate;

  const DashboardHome({required this.onNavigate, Key? key}) : super(key: key);

  @override
  _DashboardHomeState createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  final DatabaseService _dbService = DatabaseService();
  int _studentCount = 0;
  int _staffCount = 0;
  int _classCount = 0;
  double _totalRevenue = 0.0;
  double _expectedRevenue = 0.0;
  double _remainingRevenue = 0.0;
  List<ActivityItem> _recentActivities = [];
  List<FlSpot> _enrollmentSpots = [];
  List<String> _enrollmentMonths = []; // New: to store month labels
  List<_UnpaidClassSummary> _topUnpaidClasses = [];
  List<_UnpaidStudentSummary> _topUnpaidStudents = [];
  int _overdueLoansCount = 0;
  List<_OverdueLoanSummary> _overdueLoansPreview = [];
  List<_DueItem> _dueSoonItems = [];
  int _recentSanctionsCount = 0;
  bool _isLoading = true;

  List<_DashboardTodo> _todos = [];
  bool _showAllTodos = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    refreshAcademicYear();
    academicYearNotifier.addListener(_onYearChanged);
    _loadTodos();
    _loadDashboardData();
  }

  void _onYearChanged() {
    _loadDashboardData();
  }

  Future<void> _loadTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('dashboard_todos') ?? '[]';
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final list = decoded
          .whereType<Map>()
          .map((m) => _DashboardTodo.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      list.sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        final da = a.dueDate ?? DateTime.fromMillisecondsSinceEpoch(1 << 62);
        final db = b.dueDate ?? DateTime.fromMillisecondsSinceEpoch(1 << 62);
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
        return b.createdAt.compareTo(a.createdAt);
      });
      if (!mounted) return;
      setState(() => _todos = list);
    } catch (_) {}
  }

  Future<void> _saveTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_todos.map((t) => t.toJson()).toList());
      await prefs.setString('dashboard_todos', raw);
    } catch (_) {}
  }

  Future<void> _addTodoDialog() async {
    final titleCtrl = TextEditingController();
    DateTime? dueDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter une tâche'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titre',
                  hintText: 'Ex: Relancer les impayés',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dueDate == null
                          ? 'Échéance: aucune'
                          : 'Échéance: ${DateFormat('dd/MM/yyyy').format(dueDate!)}',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dueDate ?? now,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 3),
                      );
                      if (picked != null) setState(() => dueDate = picked);
                    },
                    icon: const Icon(Icons.event),
                    label: const Text('Choisir'),
                  ),
                  if (dueDate != null)
                    IconButton(
                      tooltip: 'Supprimer la date',
                      onPressed: () => setState(() => dueDate = null),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    final now = DateTime.now();
    final item = _DashboardTodo(
      id: '${now.microsecondsSinceEpoch}',
      title: title,
      dueDate: dueDate,
      done: false,
      createdAt: now,
    );
    if (!mounted) return;
    setState(() {
      _todos = [item, ..._todos];
    });
    await _saveTodos();
  }

  Future<void> _toggleTodo(String id) async {
    setState(() {
      _todos = _todos
          .map((t) => t.id == id ? t.copyWith(done: !t.done) : t)
          .toList();
    });
    await _saveTodos();
  }

  Future<void> _deleteTodo(String id) async {
    final todo = _todos.where((t) => t.id == id).cast<_DashboardTodo?>().firstWhere(
          (t) => t != null,
          orElse: () => null,
        );
    if (todo == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              const SizedBox(width: 8),
              const Text('Supprimer la tâche ?'),
              const Spacer(),
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(ctx).pop(false),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          content: Text(
            'Confirmer la suppression de :\n\n“${todo.title}”',
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    setState(() {
      _todos = _todos.where((t) => t.id != id).toList();
    });
    await _saveTodos();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final String currentYear = academicYearNotifier.value;
      final students = await _dbService.getStudents(academicYear: currentYear);
      final staff = await _dbService.getStaff();
      final allClasses = await _dbService.getClasses();
      final classes = allClasses
          .where((c) => c.academicYear == currentYear)
          .toList();
      final payments = await _dbService.getAllPayments();

      // Compter uniquement les paiements d'élèves de l'année en cours
      final studentIdsThisYear = students.map((s) => s.id).toSet();
      final totalRevenue = payments
          .where((p) => studentIdsThisYear.contains(p.studentId))
          .fold<double>(0, (sum, item) => sum + item.amount);

      // Fetch recent activities
      final recentPayments = (await _dbService.getRecentPayments(5))
          .where((p) => studentIdsThisYear.contains(p.studentId) && !p.isCancelled)
          .toList();
      final recentCancelled = (await _dbService.getRecentCancelledPayments(5))
          .where((p) => studentIdsThisYear.contains(p.studentId))
          .toList();

      // Filter staff by current academic year (hire date within academic year)
      final allRecentStaff = await _dbService.getRecentStaff(
        10,
      ); // Get more to filter
      final recentStaff = allRecentStaff
          .where((staff) {
            final hireYear = staff.hireDate.year;
            final academicYearStart = int.parse(currentYear.split('-')[0]);
            final academicYearEnd = int.parse(currentYear.split('-')[1]);
            return hireYear >= academicYearStart && hireYear <= academicYearEnd;
          })
          .take(3)
          .toList();

      final recentStudents = (await _dbService.getRecentStudents(
        3,
      )).where((s) => s.academicYear == currentYear).toList();

      List<ActivityItem> activities = [];
      for (var p in recentPayments) {
        final student = await _dbService.getStudentById(p.studentId);
        activities.add(
          ActivityItem(
            title: 'Paiement reçu',
            subtitle: 'Frais scolarité - ${student?.name ?? 'Inconnu'}',
            time: DateFormat('dd/MM/yyyy').format(DateTime.parse(p.date)),
            icon: Icons.payment,
            color: Color(0xFFF59E0B),
          ),
        );
      }
      for (var p in recentCancelled) {
        final student = await _dbService.getStudentById(p.studentId);
        final when = p.cancelledAt != null && p.cancelledAt!.trim().isNotEmpty
            ? DateTime.tryParse(p.cancelledAt!) ?? DateTime.parse(p.date)
            : DateTime.parse(p.date);
        final subtitleParts = <String>[
          student?.name ?? 'Inconnu',
          if ((p.cancelReason ?? '').isNotEmpty) 'Motif: ${p.cancelReason}',
          if ((p.cancelBy ?? '').isNotEmpty) 'Par: ${p.cancelBy}',
        ];
        activities.add(
          ActivityItem(
            title: 'Paiement annulé',
            subtitle: subtitleParts.join(' • '),
            time: DateFormat('dd/MM/yyyy').format(when),
            icon: Icons.cancel_outlined,
            color: Color(0xFFEF4444),
          ),
        );
      }
      for (var s in recentStaff) {
        activities.add(
          ActivityItem(
            title: 'Nouveau membre du personnel',
            subtitle: '${s.name} - ${s.role}',
            time: formatDdMmYyyy(
              s.hireDate,
            ), // Assuming hireDate is already DateTime
            icon: Icons.person_add,
            color: Color(0xFF10B981),
          ),
        );
      }
      for (var s in recentStudents) {
        activities.add(
          ActivityItem(
            title: 'Nouvel élève inscrit',
            subtitle: '${s.name} - ${s.className}',
            time: DateFormat(
              'dd/MM/yyyy',
            ).format(DateTime.parse(s.enrollmentDate)), // Use enrollmentDate
            icon: Icons.person_add,
            color: Color(0xFF3B82F6),
          ),
        );
      }

      // Sort activities by date (most recent first)
      activities.sort((a, b) {
        DateTime dateA = DateFormat('dd/MM/yyyy').parse(a.time);
        DateTime dateB = DateFormat('dd/MM/yyyy').parse(b.time);
        return dateB.compareTo(dateA);
      });

      // Alerts & KPIs (année en cours)
      double expectedTotal = 0.0;
      final Map<String, int> studentCountByClass = {};
      for (final s in students) {
        studentCountByClass[s.className] =
            (studentCountByClass[s.className] ?? 0) + 1;
      }

      final Map<String, double> expectedByClass = {};
      for (final c in classes) {
        final unitFee =
            (c.fraisEcole ?? 0.0) + (c.fraisCotisationParallele ?? 0.0);
        final cnt = studentCountByClass[c.name] ?? 0;
        final exp = unitFee * cnt;
        expectedByClass[c.name] = exp;
        expectedTotal += exp;
      }

      final Map<String, double> paidByClass = {};
      for (final p in payments.where(
        (p) => p.classAcademicYear == currentYear && !p.isCancelled,
      )) {
        paidByClass[p.className] = (paidByClass[p.className] ?? 0.0) + p.amount;
      }

      final unpaidClasses = <_UnpaidClassSummary>[];
      for (final c in classes) {
        final expected = expectedByClass[c.name] ?? 0.0;
        final paid = paidByClass[c.name] ?? 0.0;
        final remaining = (expected - paid) < 0 ? 0.0 : (expected - paid);
        if (remaining <= 0) continue;
        unpaidClasses.add(
          _UnpaidClassSummary(
            className: c.name,
            studentCount: studentCountByClass[c.name] ?? 0,
            expected: expected,
            paid: paid,
            remaining: remaining,
          ),
        );
      }
      unpaidClasses.sort((a, b) => b.remaining.compareTo(a.remaining));

      // Impayés détaillés par élève (top 10)
      final Map<String, double> unitFeeByClass = {};
      for (final c in classes) {
        unitFeeByClass[c.name] =
            (c.fraisEcole ?? 0.0) + (c.fraisCotisationParallele ?? 0.0);
      }
      final Map<String, double> paidByStudent = {};
      for (final p in payments.where(
        (p) => p.classAcademicYear == currentYear && !p.isCancelled,
      )) {
        paidByStudent[p.studentId] =
            (paidByStudent[p.studentId] ?? 0.0) + p.amount;
      }
      final unpaidStudents = <_UnpaidStudentSummary>[];
      for (final s in students) {
        final expected = unitFeeByClass[s.className] ?? 0.0;
        if (expected <= 0) continue;
        final paid = paidByStudent[s.id] ?? 0.0;
        final remaining = (expected - paid) < 0 ? 0.0 : (expected - paid);
        if (remaining <= 0) continue;
        unpaidStudents.add(
          _UnpaidStudentSummary(
            studentId: s.id,
            studentName: s.name,
            className: s.className,
            expected: expected,
            paid: paid,
            remaining: remaining,
            student: s,
          ),
        );
      }
      unpaidStudents.sort((a, b) => b.remaining.compareTo(a.remaining));

      // Bibliothèque: emprunts en retard (année en cours)
      int overdueCount = 0;
      final overduePreview = <_OverdueLoanSummary>[];
      final dueSoon = <_DueItem>[];
      try {
        final loans = await _dbService.getLibraryLoansView(onlyActive: true);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final soonCutoff = today.add(const Duration(days: 7));
        for (final row in loans) {
          final studentYear = (row['studentAcademicYear'] as String?) ?? '';
          if (studentYear != currentYear) continue;
          final dueRaw = row['dueDate']?.toString();
          if (dueRaw == null || dueRaw.trim().isEmpty) continue;
          final due = DateTime.tryParse(dueRaw);
          if (due == null) continue;
          final normalizedDue = DateTime(due.year, due.month, due.day);
          final studentName = (row['studentName'] as String?) ?? 'Inconnu';
          final className = (row['studentClassName'] as String?) ?? '';
          final bookTitle = (row['bookTitle'] as String?) ?? '';
          if (normalizedDue.isBefore(today)) {
            overdueCount += 1;
            if (overduePreview.length < 5) {
              overduePreview.add(
                _OverdueLoanSummary(
                  loanId: (row['loanId'] as int?) ?? 0,
                  studentName: studentName,
                  className: className,
                  bookTitle: bookTitle,
                  dueDate: normalizedDue,
                ),
              );
            }
          } else if (!normalizedDue.isAfter(soonCutoff)) {
            dueSoon.add(
              _DueItem(
                date: normalizedDue,
                title: 'Retour livre',
                subtitle:
                    '$studentName${className.trim().isEmpty ? '' : ' • $className'} • $bookTitle',
                kind: _DueKind.library,
              ),
            );
          }
        }
      } catch (_) {}

      // Licence: échéance proche (<= 14 jours)
      try {
        final st = await LicenseService.instance.getStatus();
        if (st.isActive && st.expiry != null) {
          final days = st.daysRemaining;
          if (days <= 14 && days >= 0) {
            final exp = st.expiry!;
            final d = DateTime(exp.year, exp.month, exp.day);
            dueSoon.add(
              _DueItem(
                date: d,
                title: 'Licence',
                subtitle: 'Expire dans ${days} jour(s)',
                kind: _DueKind.license,
              ),
            );
          }
        }
      } catch (_) {}

      dueSoon.sort((a, b) => a.date.compareTo(b.date));

      // Discipline: sanctions des 7 derniers jours (année en cours)
      int sanctions7d = 0;
      try {
        final list = await _dbService.getSanctionEvents(academicYear: currentYear);
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        for (final row in list) {
          final dateRaw = row['date']?.toString();
          if (dateRaw == null || dateRaw.trim().isEmpty) continue;
          final dt = DateTime.tryParse(dateRaw) ??
              DateTime.tryParse(dateRaw.replaceFirst(' ', 'T'));
          if (dt == null) continue;
          if (dt.isAfter(cutoff)) sanctions7d += 1;
        }
      } catch (_) {}

      // Fetch enrollment data for chart (année en cours uniquement)
      final Map<String, int> monthlyMap = {};
      for (final s in students) {
        if (s.enrollmentDate.trim().isEmpty) continue;
        final dt = DateTime.tryParse(s.enrollmentDate);
        if (dt == null) continue;
        final key = DateFormat('yyyy-MM').format(dt);
        monthlyMap[key] = (monthlyMap[key] ?? 0) + 1;
      }
      final monthlyEnrollment = monthlyMap.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      print("Monthly Enrollment Data ($currentYear): $monthlyEnrollment");
      List<FlSpot> spots = [];
      List<String> months = [];
      if (monthlyEnrollment.isNotEmpty) {
        for (int i = 0; i < monthlyEnrollment.length; i++) {
          spots.add(
            FlSpot(i.toDouble(), monthlyEnrollment[i].value.toDouble()),
          );
          months.add(monthlyEnrollment[i].key);
        }
      } else {
        // Fallback to static data if no real data is available
        spots = [
          FlSpot(0, 300),
          FlSpot(1, 320),
          FlSpot(2, 350),
          FlSpot(3, 400),
          FlSpot(4, 420),
          FlSpot(5, 450),
          FlSpot(6, 480),
          FlSpot(7, 500),
          FlSpot(8, 520),
          FlSpot(9, 540),
          FlSpot(10, 580),
          FlSpot(11, 600),
        ];
        months = [
          'Jan',
          'Fév',
          'Mar',
          'Avr',
          'Mai',
          'Juin',
          'Juil',
          'Août',
          'Sep',
          'Oct',
          'Nov',
          'Déc',
        ];
      }

      setState(() {
        _studentCount = students.length;
        _staffCount = staff.length;
        _classCount = classes.length;
        _totalRevenue = totalRevenue;
        _expectedRevenue = expectedTotal;
        _remainingRevenue = (expectedTotal - totalRevenue).clamp(0, 1e15);
        _recentActivities = activities.take(5).toList();
        _enrollmentSpots = spots;
        _enrollmentMonths = months;
        _topUnpaidClasses = unpaidClasses.take(5).toList();
        _topUnpaidStudents = unpaidStudents.take(10).toList();
        _overdueLoansCount = overdueCount;
        _overdueLoansPreview = overduePreview;
        _dueSoonItems = dueSoon.take(12).toList();
        _recentSanctionsCount = sanctions7d;
        _isLoading = false;
      });
    } catch (e) {
      // Handle error appropriately
      print("Error loading dashboard data: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    academicYearNotifier.removeListener(_onYearChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: 'FCFA',
      decimalDigits: 0,
    );
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
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
                                  colors: [
                                    Color(0xFF6366F1),
                                    Color(0xFF8B5CF6),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.dashboard,
                                color: Colors.white,
                                size: isDesktop ? 32 : 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tableau de Bord',
                                  style: TextStyle(
                                    fontSize: isDesktop ? 32 : 24,
                                    fontWeight: FontWeight.bold,
                                    color: theme.textTheme.bodyLarge?.color,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Gérez votre école avec style et efficacité',
                                  style: TextStyle(
                                    fontSize: isDesktop ? 16 : 14,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withOpacity(0.7),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // License status, Academic Year and Notification Icon
                        Row(
                          children: [
                            _buildLicenseStatusPill(theme),
                            SizedBox(width: 12),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF10B981),
                                    Color(0xFF34D399),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                  SizedBox(width: 8),
                                  ValueListenableBuilder<String>(
                                    valueListenable: academicYearNotifier,
                                    builder: (context, year, _) => Text(
                                      'Année $year',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: _openNotificationsCenter,
                                child: Icon(
                                  Icons.notifications_outlined,
                                  color: theme.iconTheme.color,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 32),

              // Stats Cards
              _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : ScaleTransition(
                      scale: _scaleAnimation,
                      child: constraints.maxWidth > 800
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Expanded(
                                  child: StatsCard(
                                    title: 'Total Élèves',
                                    value: '$_studentCount',
                                    icon: Icons.people,
                                    color: Color(0xFF3B82F6),
                                    subtitle: '',
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: StatsCard(
                                    title: 'Personnel',
                                    value: '$_staffCount',
                                    icon: Icons.person,
                                    color: Color(0xFF10B981),
                                    subtitle: '',
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: StatsCard(
                                    title: 'Classes',
                                    value: '$_classCount',
                                    icon: Icons.class_,
                                    color: Color(0xFFF59E0B),
                                    subtitle: '',
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: StatsCard(
                                    title: 'Revenus',
                                    value: currencyFormatter.format(
                                      _totalRevenue,
                                    ),
                                    icon: Icons.account_balance_wallet,
                                    color: Color(0xFFEF4444),
                                    subtitle: '',
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                StatsCard(
                                  title: 'Total Élèves',
                                  value: '$_studentCount',
                                  icon: Icons.people,
                                  color: Color(0xFF3B82F6),
                                  subtitle: '',
                                ),
                                SizedBox(height: 20),
                                StatsCard(
                                  title: 'Personnel',
                                  value: '$_staffCount',
                                  icon: Icons.person,
                                  color: Color(0xFF10B981),
                                  subtitle: '',
                                ),
                                SizedBox(height: 20),
                                StatsCard(
                                  title: 'Classes',
                                  value: '$_classCount',
                                  icon: Icons.class_,
                                  color: Color(0xFFF59E0B),
                                  subtitle: '',
                                ),
                                SizedBox(height: 20),
                                StatsCard(
                                  title: 'Revenus',
                                  value: currencyFormatter.format(
                                    _totalRevenue,
                                  ),
                                  icon: Icons.account_balance_wallet,
                                  color: Color(0xFFEF4444),
                                  subtitle: '',
                                ),
                              ],
                            ),
                    ),
              SizedBox(height: 32),

              // Charts and Recent Activity
              Expanded(
                child: SingleChildScrollView(
                  child: constraints.maxWidth > 600
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Chart
                            Expanded(
                              flex: 2,
                              child: Column(
                                children: [
                                  _buildChartCard(context),
                                  SizedBox(height: 20),
                                  _buildAlertsCard(
                                    context,
                                    currencyFormatter: currencyFormatter,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 20),
                            // Activities & Quick Actions
                            Expanded(
                              child: Column(
                                children: [
                                  _buildActivitiesCard(context),
                                  SizedBox(height: 20),
                                  _buildQuickActionsCard(context),
                                  SizedBox(height: 20),
                                  _buildAgendaCard(context),
                                  SizedBox(height: 20),
                                  _buildTodosCard(context),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildChartCard(context),
                            SizedBox(height: 20),
                            _buildActivitiesCard(context),
                            SizedBox(height: 20),
                            _buildQuickActionsCard(context),
                            SizedBox(height: 20),
                            _buildAlertsCard(
                              context,
                              currencyFormatter: currencyFormatter,
                            ),
                            SizedBox(height: 20),
                            _buildAgendaCard(context),
                            SizedBox(height: 20),
                            _buildTodosCard(context),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLicenseStatusPill(ThemeData theme) {
    return FutureBuilder<bool>(
      future: LicenseService.instance.allKeysUsed(),
      builder: (context, allSnap) {
        final allUsed = allSnap.data == true;
        return FutureBuilder<LicenseStatus>(
          future: LicenseService.instance.getStatus(),
          builder: (context, stSnap) {
            final st = stSnap.data;
            String text;
            Color start;
            Color end;
            if (allUsed) {
              text = 'Application débloquée';
              start = const Color(0xFF10B981);
              end = const Color(0xFF34D399);
            } else if (st?.isActive == true) {
              final days = st!.daysRemaining;
              text = 'Licence active • ${days}j restants';
              start = const Color(0xFF3B82F6);
              end = const Color(0xFF60A5FA);
            } else {
              text = 'Licence requise';
              start = const Color(0xFFF59E0B);
              end = const Color(0xFFFBBF24);
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [start, end]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: start.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.vpn_key_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
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

  Widget _buildChartCard(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Évolution des Inscriptions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1.6,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context).dividerColor!.withOpacity(0.5),
                    strokeWidth: 0.5,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Theme.of(context).dividerColor!.withOpacity(0.5),
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium!.color,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 &&
                            value.toInt() < _enrollmentMonths.length) {
                          return Text(
                            _enrollmentMonths[value.toInt()],
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium!.color,
                              fontSize: 12,
                            ),
                          );
                        }
                        return Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Theme.of(context).dividerColor!),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _enrollmentSpots,
                    isCurved: true,
                    color: Color(0xFF3B82F6),
                    barWidth: 4,
                    dotData: FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesCard(BuildContext context) {
    return Container(
      height: 320,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activités Récentes',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: _recentActivities.isEmpty
                    ? [Text('Aucune activité récente.')]
                    : _recentActivities,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actions Rapides',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: QuickAction(
                  title: 'Nouvel Élève',
                  icon: Icons.person_add,
                  color: Color(0xFF10B981),
                  onTap: () =>
                      widget.onNavigate(1), // Navigates to StudentsPage
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  title: 'Saisir Notes',
                  icon: Icons.edit,
                  color: Color(0xFF3B82F6),
                  onTap: () => widget.onNavigate(3), // Navigates to GradesPage
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: QuickAction(
                  title: 'Générer Bulletin',
                  icon: Icons.description,
                  color: Color(0xFFF59E0B),
                  onTap: () => widget.onNavigate(3), // Navigates to GradesPage
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  title: 'Emploi du Temps',
                  icon: Icons.schedule,
                  color: Color(0xFF8B5CF6),
                  onTap: () =>
                      widget.onNavigate(7), // Navigates to TimetablePage
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: QuickAction(
                  title: 'Paiements',
                  icon: Icons.payment,
                  color: Color(0xFF4CAF50),
                  onTap: () =>
                      widget.onNavigate(4), // Navigates to PaymentsPage
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  title: 'Ajouter Personnel',
                  icon: Icons.person_add_alt_1,
                  color: Color(0xFF60A5FA),
                  onTap: () => widget.onNavigate(2), // Navigates to StaffPage
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: QuickAction(
                  title: 'Annuler Paiement',
                  icon: Icons.cancel_outlined,
                  color: Color(0xFFEF4444),
                  onTap: () {
                    // Redirige vers la page Paiements où l\'annulation est disponible par élève
                    widget.onNavigate(4);
                    // Optionnel: un snack d\'aide peut être affiché après navigation par la page cible
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  title: 'Finance & Matériel',
                  icon: Icons.inventory_2_outlined,
                  color: Color(0xFFF59E0B),
                  onTap: () => widget.onNavigate(10), // Navigate to Finance & Inventory
                ),
              ),
            ],
          ),
        ], // Closing the Column
      ), // Closing the Container
    ); // Closing the Container
  }

  Widget _buildAgendaCard(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(
      7,
      (i) => today.add(Duration(days: i)),
    );
    int countFor(DateTime d) =>
        _dueSoonItems.where((it) => _sameDay(it.date, d)).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Échéances (7 jours)',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              TextButton.icon(
                onPressed: _openNotificationsCenter,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Détails'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final d = days[i];
                final c = countFor(d);
                final label = DateFormat('EEE dd', 'fr_FR').format(d);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.25),
                    ),
                    color: c > 0
                        ? const Color(0xFF0EA5E9).withOpacity(0.12)
                        : theme.scaffoldBackgroundColor.withOpacity(0.06),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c > 0
                              ? const Color(0xFF0EA5E9)
                              : theme.dividerColor.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$c',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (_dueSoonItems.isEmpty)
            Text(
              'Aucune échéance détectée.',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            )
          else
            Column(
              children: _dueSoonItems.take(5).map((it) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      _dueKindDot(it.kind),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${DateFormat('dd/MM').format(it.date)} • ${it.title} • ${it.subtitle}',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTodosCard(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final total = _todos.length;
    final doneCount = _todos.where((t) => t.done).length;
    final pendingCount = total - doneCount;

    final List<_DashboardTodo> list = _showAllTodos ? _todos : _todos.take(6).toList();
    final remainingCount = _todos.length - list.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'À faire',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _todoStatChip(
                        label: '$pendingCount en cours',
                        color: const Color(0xFF0EA5E9),
                      ),
                      const SizedBox(width: 8),
                      _todoStatChip(
                        label: '$doneCount terminée(s)',
                        color: const Color(0xFF10B981),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _addTodoDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter'),
                  ),
                  if (_todos.length > 6)
                    TextButton(
                      onPressed: () =>
                          setState(() => _showAllTodos = !_showAllTodos),
                      child: Text(_showAllTodos ? 'Réduire' : 'Tout voir'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : (doneCount / total),
                minHeight: 8,
                backgroundColor: theme.dividerColor.withOpacity(0.25),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF10B981),
                ),
              ),
            ),
          if (total > 0) const SizedBox(height: 12),
          if (_todos.isEmpty)
            Text(
              'Aucune tâche. Ajoutez-en une pour commencer.',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            )
          else
            Column(
              children: [
                ...list.map((t) {
                  final due = t.dueDate == null
                      ? null
                      : DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
                  final isOverdue = !t.done && due != null && due.isBefore(today);
                  final isDueSoon = !t.done &&
                      due != null &&
                      !isOverdue &&
                      due.isBefore(today.add(const Duration(days: 3)));

                  final Color accent = t.done
                      ? const Color(0xFF10B981)
                      : isOverdue
                          ? const Color(0xFFEF4444)
                          : isDueSoon
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF0EA5E9);

                  final dueLabel = due == null
                      ? 'Sans échéance'
                      : DateFormat('dd/MM/yyyy').format(due);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: t.done,
                          onChanged: (_) => _toggleTodo(t.id),
                          activeColor: const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: InkWell(
                            onTap: () => _toggleTodo(t.id),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  style: TextStyle(
                                    color: theme.textTheme.bodyLarge?.color,
                                    fontWeight: FontWeight.w600,
                                    decoration: t.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _todoPill(
                                      label: dueLabel,
                                      color: accent,
                                      icon: Icons.event,
                                    ),
                                    if (isOverdue)
                                      _todoPill(
                                        label: 'En retard',
                                        color: const Color(0xFFEF4444),
                                        icon: Icons.warning_amber_rounded,
                                      ),
                                    if (t.done)
                                      _todoPill(
                                        label: 'Terminé',
                                        color: const Color(0xFF10B981),
                                        icon: Icons.check_circle_outline,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Supprimer',
                          onPressed: () => _deleteTodo(t.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                }),
                if (!_showAllTodos && remainingCount > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '+$remainingCount autre(s) tâche(s)…',
                        style: TextStyle(
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _todoStatChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  Widget _todoPill({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.9),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsCard(
    BuildContext context, {
    required NumberFormat currencyFormatter,
  }) {
    final theme = Theme.of(context);
    final hasUnpaid = _remainingRevenue > 0 || _topUnpaidClasses.isNotEmpty;
    final hasOverdue = _overdueLoansCount > 0;
    final hasSanctions = _recentSanctionsCount > 0;
    final hasAny = hasUnpaid || hasOverdue || hasSanctions;

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Alertes & Suivi',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              TextButton.icon(
                onPressed: () => _loadDashboardData(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasAny)
            Text(
              'Aucune alerte pour le moment.',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
          if (hasAny) ...[
            _buildAlertRow(
              context,
              icon: Icons.account_balance_wallet_outlined,
              title: 'Impayés (estimation)',
              subtitle:
                  'Reste à encaisser: ${currencyFormatter.format(_remainingRevenue)} / ${currencyFormatter.format(_expectedRevenue)}',
              color: hasUnpaid
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF10B981),
              actionLabel: 'Voir paiements',
              onAction: () => widget.onNavigate(4),
            ),
            if (_topUnpaidStudents.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildAlertRow(
                context,
                icon: Icons.person_search_outlined,
                title: 'Top impayés par élève',
                subtitle:
                    'Top ${_topUnpaidStudents.length} (année ${academicYearNotifier.value})',
                color: const Color(0xFFF59E0B),
                actionLabel: 'Détails',
                onAction: _openUnpaidStudentsDialog,
              ),
            ],
            if (_topUnpaidClasses.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._topUnpaidClasses.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${c.className} • ${c.studentCount} élève(s)',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currencyFormatter.format(c.remaining),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => widget.onNavigate(10),
                  child: const Text('Voir Finance & Matériel'),
                ),
              ),
            ],
            const Divider(),
            _buildAlertRow(
              context,
              icon: Icons.local_library_outlined,
              title: 'Bibliothèque',
              subtitle: hasOverdue
                  ? '${_overdueLoansCount} emprunt(s) en retard'
                  : 'Aucun retard détecté',
              color: hasOverdue
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
              actionLabel: 'Voir bibliothèque',
              onAction: () => widget.onNavigate(14),
            ),
            if (_dueSoonItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildAlertRow(
                context,
                icon: Icons.event_available_outlined,
                title: 'Échéances proches',
                subtitle: '${_dueSoonItems.length} item(s) dans les 7 jours',
                color: const Color(0xFF0EA5E9),
                actionLabel: 'Voir',
                onAction: _openNotificationsCenter,
              ),
            ],
            if (_overdueLoansPreview.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._overdueLoansPreview.map((l) {
                final due = DateFormat('dd/MM/yyyy').format(l.dueDate);
                final subtitleParts = <String>[
                  if (l.className.trim().isNotEmpty) l.className,
                  if (l.bookTitle.trim().isNotEmpty) l.bookTitle,
                  'Échéance: $due',
                ];
                return Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${l.studentName} • ${subtitleParts.join(' • ')}',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const Divider(),
            _buildAlertRow(
              context,
              icon: Icons.gavel_outlined,
              title: 'Discipline',
              subtitle: _recentSanctionsCount > 0
                  ? '${_recentSanctionsCount} sanction(s) ces 7 derniers jours'
                  : 'Rien à signaler cette semaine',
              color: hasSanctions
                  ? const Color(0xFF8B5CF6)
                  : const Color(0xFF10B981),
              actionLabel: 'Voir discipline',
              onAction: () => widget.onNavigate(15),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Future<void> _openStudentProfile(StudentProfilePage page) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => page,
    );
  }

  Future<void> _openUnpaidStudentsDialog() async {
    final theme = Theme.of(context);
    final fmt = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: 'FCFA',
      decimalDigits: 0,
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Impayés par élève'),
        content: SizedBox(
          width: 640,
          child: _topUnpaidStudents.isEmpty
              ? const Text('Aucun impayé détecté.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _topUnpaidStudents.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: theme.dividerColor.withOpacity(0.35)),
                  itemBuilder: (context, i) {
                    final s = _topUnpaidStudents[i];
                    return ListTile(
                      title: Text('${s.studentName} • ${s.className}'),
                      subtitle: Text(
                        'Reste: ${fmt.format(s.remaining)} (Payé: ${fmt.format(s.paid)} / Attendu: ${fmt.format(s.expected)})',
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _openStudentProfile(
                            StudentProfilePage(student: s.student),
                          );
                        },
                        child: const Text('Profil'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onNavigate(4);
            },
            child: const Text('Aller aux paiements'),
          ),
        ],
      ),
    );
  }

  Future<void> _openNotificationsCenter() async {
    final fmt = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: 'FCFA',
      decimalDigits: 0,
    );

    await showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: theme.cardColor,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
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
                            Icons.notifications_outlined,
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
                                'Centre de notifications',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Année ${academicYearNotifier.value}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fermer',
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),

                  // Content
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
                              _navChip(
                                ctx,
                                icon: Icons.payment,
                                label: 'Paiements',
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  widget.onNavigate(4);
                                },
                              ),
                              _navChip(
                                ctx,
                                icon: Icons.local_library_outlined,
                                label: 'Bibliothèque',
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  widget.onNavigate(14);
                                },
                              ),
                              _navChip(
                                ctx,
                                icon: Icons.gavel_outlined,
                                label: 'Discipline',
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  widget.onNavigate(15);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          _buildNotificationSectionCard(
                            ctx,
                            icon: Icons.account_balance_wallet_outlined,
                            iconColor: const Color(0xFFF59E0B),
                            title: 'Impayés',
                            subtitle:
                                'Reste à encaisser (estimation): ${fmt.format(_remainingRevenue)}',
                            child: _topUnpaidStudents.isEmpty
                                ? Text(
                                    'Aucun impayé détecté.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.textTheme.bodyMedium?.color
                                          ?.withOpacity(0.7),
                                    ),
                                  )
                                : Column(
                                    children:
                                        _topUnpaidStudents.take(10).map((s) {
                                      return _notificationListTile(
                                        title: '${s.studentName} • ${s.className}',
                                        subtitle:
                                            'Reste: ${fmt.format(s.remaining)}',
                                        trailing: TextButton(
                                          onPressed: () async {
                                            Navigator.of(ctx).pop();
                                            await _openStudentProfile(
                                              StudentProfilePage(
                                                student: s.student,
                                              ),
                                            );
                                          },
                                          child: const Text('Profil'),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                          const SizedBox(height: 12),

                          _buildNotificationSectionCard(
                            ctx,
                            icon: Icons.event_available_outlined,
                            iconColor: const Color(0xFF0EA5E9),
                            title: 'Échéances',
                            subtitle: _dueSoonItems.isEmpty
                                ? 'Aucune échéance détectée.'
                                : '${_dueSoonItems.length} échéance(s) dans les 7 jours',
                            child: _dueSoonItems.isEmpty
                                ? const SizedBox.shrink()
                                : Column(
                                    children: _dueSoonItems.map((it) {
                                      return _notificationListTile(
                                        leading: _dueKindDot(it.kind),
                                        title:
                                            '${DateFormat('dd/MM/yyyy').format(it.date)} • ${it.title}',
                                        subtitle: it.subtitle,
                                      );
                                    }).toList(),
                                  ),
                          ),
                          const SizedBox(height: 12),

                          _buildNotificationSectionCard(
                            ctx,
                            icon: Icons.local_library_outlined,
                            iconColor: const Color(0xFF10B981),
                            title: 'Bibliothèque',
                            subtitle: _overdueLoansCount > 0
                                ? '${_overdueLoansCount} emprunt(s) en retard'
                                : 'Aucun retard détecté',
                            child: _overdueLoansPreview.isEmpty
                                ? const SizedBox.shrink()
                                : Column(
                                    children: _overdueLoansPreview.map((l) {
                                      return _notificationListTile(
                                        leading: const Icon(
                                          Icons.error_outline,
                                          color: Color(0xFFEF4444),
                                        ),
                                        title: l.studentName,
                                        subtitle:
                                            '${l.className} • ${l.bookTitle} • échéance ${DateFormat('dd/MM/yyyy').format(l.dueDate)}',
                                      );
                                    }).toList(),
                                  ),
                          ),
                          const SizedBox(height: 12),

                          _buildNotificationSectionCard(
                            ctx,
                            icon: Icons.gavel_outlined,
                            iconColor: const Color(0xFF8B5CF6),
                            title: 'Discipline',
                            subtitle: _recentSanctionsCount > 0
                                ? '${_recentSanctionsCount} sanction(s) ces 7 derniers jours'
                                : 'Rien à signaler cette semaine',
                            child: const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationSectionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.75,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (child is! SizedBox) ...[
            const SizedBox(height: 10),
            child,
          ],
        ],
      ),
    );
  }

  Widget _notificationListTile({
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: leading == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: leading,
            ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: trailing,
    );
  }

  Widget _navChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 18, color: theme.colorScheme.primary),
      label: Text(label),
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dueKindDot(_DueKind kind) {
    Color c;
    switch (kind) {
      case _DueKind.library:
        c = const Color(0xFF10B981);
        break;
      case _DueKind.license:
        c = const Color(0xFF3B82F6);
        break;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}

class _UnpaidClassSummary {
  final String className;
  final int studentCount;
  final double expected;
  final double paid;
  final double remaining;
  const _UnpaidClassSummary({
    required this.className,
    required this.studentCount,
    required this.expected,
    required this.paid,
    required this.remaining,
  });
}

class _OverdueLoanSummary {
  final int loanId;
  final String studentName;
  final String className;
  final String bookTitle;
  final DateTime dueDate;
  const _OverdueLoanSummary({
    required this.loanId,
    required this.studentName,
    required this.className,
    required this.bookTitle,
    required this.dueDate,
  });
}

enum _DueKind { library, license }

class _DueItem {
  final DateTime date;
  final String title;
  final String subtitle;
  final _DueKind kind;
  const _DueItem({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.kind,
  });
}

class _UnpaidStudentSummary {
  final String studentId;
  final String studentName;
  final String className;
  final double expected;
  final double paid;
  final double remaining;
  final Student student;
  const _UnpaidStudentSummary({
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.expected,
    required this.paid,
    required this.remaining,
    required this.student,
  });
}

class _DashboardTodo {
  final String id;
  final String title;
  final DateTime? dueDate;
  final bool done;
  final DateTime createdAt;

  const _DashboardTodo({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.done,
    required this.createdAt,
  });

  _DashboardTodo copyWith({
    String? id,
    String? title,
    DateTime? dueDate,
    bool? done,
    DateTime? createdAt,
  }) {
    return _DashboardTodo(
      id: id ?? this.id,
      title: title ?? this.title,
      dueDate: dueDate ?? this.dueDate,
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'dueDate': dueDate?.toIso8601String(),
      'done': done,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static _DashboardTodo fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? s) {
      if (s == null || s.trim().isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return _DashboardTodo(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      dueDate: parseDate(json['dueDate'] as String?),
      done: (json['done'] as bool?) ?? false,
      createdAt:
          parseDate(json['createdAt'] as String?) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
