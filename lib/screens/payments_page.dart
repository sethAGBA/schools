import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:docx_template/docx_template.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/payment_adjustment.dart';
import 'package:school_manager/models/payment_attachment.dart';
import 'package:school_manager/models/payment_schedule_rule.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/screens/dashboard_home.dart';
// import removed: grades page not needed here
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:open_file/open_file.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/screens/students/student_profile_page.dart';
// import removed: duplicate and unused
import 'package:school_manager/services/auth_service.dart';

class PaymentsPage extends StatefulWidget {
  @override
  _PaymentsPageState createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final DatabaseService _dbService = DatabaseService();
  List<Payment> _payments = [];
  Map<String, Student> _studentsById = {};
  Map<String, Class> _classesByName = {};
  bool _isLoading = true;
  int _currentPage = 0;
  static const int _rowsPerPage = 10;
  String? _selectedClassFilter;
  String? _selectedYearFilter;
  String? _selectedGenderFilter;
  int _currentTab = 0;
  List<Payment> _cancelledPayments = [];
  Map<String, List<PaymentAdjustment>> _adjustmentsByStudentId = {};
  PaymentScheduleRule? _globalScheduleRule;
  Map<String, PaymentScheduleRule?> _scheduleRuleByClass = {};
  List<String> _years = [];

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

  Future<void> _cancelPaymentWithReasonFlow(
    Payment payment, {
    BuildContext? popAfterSuccess,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    final id = payment.id;
    if (id == null) {
      showSnackBar(context, 'Paiement invalide (id manquant).', isError: true);
      return;
    }

    final motifCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CustomDialog(
        title: 'Motif d\'annulation',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Veuillez saisir un motif pour annuler ce paiement. Cette action est irréversible.',
            ),
            const SizedBox(height: 12),
            CustomFormField(
              controller: motifCtrl,
              labelText: 'Motif',
              hintText: 'Ex: erreur de saisie, remboursement, etc.',
              isTextArea: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Motif requis' : null,
            ),
          ],
        ),
        fields: const [],
        onSubmit: () => Navigator.of(dialogContext).pop(true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );

    final reason = motifCtrl.text.trim();
    if (ok != true) return;
    if (reason.isEmpty) {
      showSnackBar(context, 'Motif obligatoire pour annuler.', isError: true);
      return;
    }

    String? by;
    try {
      final user = await AuthService.instance.getCurrentUser();
      by = user?.displayName ?? user?.username;
    } catch (_) {}

    await _dbService.cancelPaymentWithReason(id, reason, by: by);
    if (popAfterSuccess != null) Navigator.of(popAfterSuccess).pop();
    showSnackBar(context, 'Paiement annulé');
    await _fetchPayments();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index;
          _currentPage = 0;
        });
      }
    });
    academicYearNotifier.addListener(_onAcademicYearChanged);
    getCurrentAcademicYear().then((year) {
      setState(() {
        _selectedYearFilter = year;
      });
      _fetchPayments();
    });
  }

  void _onAcademicYearChanged() {
    setState(() {
      _selectedYearFilter = academicYearNotifier.value;
    });
    _fetchPayments();
  }

  String _resolveEffectiveAcademicYear({required String fallback}) {
    final selected = (_selectedYearFilter ?? '').trim();
    if (selected.isNotEmpty) return selected;
    final current = academicYearNotifier.value.trim();
    return current.isNotEmpty ? current : fallback;
  }

  Future<void> _fetchPayments() async {
    setState(() => _isLoading = true);

    final payments = await _dbService.getAllPayments();
    final students = await _dbService.getStudents();
    final classes = await _dbService.getClasses();
    final years = classes.map((c) => c.academicYear).toSet().toList()..sort();

    final currentAcademicYear = await getCurrentAcademicYear();
    final effectiveYear = _resolveEffectiveAcademicYear(
      fallback: currentAcademicYear,
    );

    // Load cancelled for the selected/effective year
    final cancelled = await _dbService.getCancelledPaymentsForYear(
      effectiveYear,
    );
    final adjustments = await _dbService.getPaymentAdjustmentsForYear(
      effectiveYear,
    );
    final globalScheduleRule = await _dbService.getPaymentScheduleRule(
      classAcademicYear: effectiveYear,
      className: null,
    );

    // Filtrer les classes pour l'année effective
    final filteredClasses = classes
        .where((c) => c.academicYear == effectiveYear)
        .toList();

    // Construire map name->Class pour l'année effective
    final classesByName = {for (var c in filteredClasses) c.name: c};

    // Filtrer les élèves pour l'année effective (évite de mélanger les années quand les noms de classe se répètent)
    final filteredStudents = students
        .where((s) => s.academicYear == effectiveYear)
        .toList();
    final studentsById = {for (var s in filteredStudents) s.id: s};

    // Filtrer les paiements pour l'année effective
    final filteredPayments = payments
        .where((p) => p.classAcademicYear == effectiveYear)
        .toList();

    // Si la classe sélectionnée n'existe plus dans l'année effective, la réinitialiser
    if (_selectedClassFilter != null &&
        !classesByName.containsKey(_selectedClassFilter)) {
      _selectedClassFilter = null;
    }

    setState(() {
      _payments = filteredPayments;
      _studentsById = studentsById;
      _classesByName = classesByName;
      _cancelledPayments = cancelled;
      _adjustmentsByStudentId = {};
      _globalScheduleRule = globalScheduleRule;
      _scheduleRuleByClass = {};
      _years = years;
      _isLoading = false;
      _currentPage = 0;
    });

    final adjByStudent = <String, List<PaymentAdjustment>>{};
    for (final a in adjustments) {
      adjByStudent.putIfAbsent(a.studentId, () => []).add(a);
    }
    if (!mounted) return;
    setState(() {
      _adjustmentsByStudentId = adjByStudent;
    });

    final scheduleByClass = <String, PaymentScheduleRule?>{};
    for (final className in classesByName.keys) {
      final r = await _dbService.getEffectivePaymentScheduleRule(
        classAcademicYear: effectiveYear,
        className: className,
      );
      scheduleByClass[className] = r;
    }
    if (!mounted) return;
    setState(() {
      _scheduleRuleByClass = scheduleByClass;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    academicYearNotifier.removeListener(_onAcademicYearChanged);
    super.dispose();
  }

  double _baseTotalDueForStudent(Student student) {
    final classe = _classesByName[student.className];
    return (classe?.fraisEcole ?? 0) + (classe?.fraisCotisationParallele ?? 0);
  }

  double _adjustedTotalDueForStudent(Student student) {
    final baseDue = _baseTotalDueForStudent(student);
    final adjustments = _adjustmentsByStudentId[student.id] ?? const [];
    double discounts = 0.0;
    double surcharges = 0.0;
    for (final a in adjustments) {
      final type = a.type.toLowerCase().trim();
      if (type == 'discount') discounts += a.amount;
      if (type == 'surcharge') surcharges += a.amount;
    }
    final due = baseDue + surcharges - discounts;
    return due < 0 ? 0.0 : due;
  }

  double _totalDiscountsForStudent(Student student) {
    final adjustments = _adjustmentsByStudentId[student.id] ?? const [];
    return adjustments
        .where((a) => a.type.toLowerCase().trim() == 'discount')
        .fold<double>(0.0, (s, a) => s + a.amount);
  }

  DateTime? _parseAnyDate(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // dd/MM/yyyy
    final parts = s.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  int? _academicYearStartYear(String year) {
    final m = RegExp(r'(\d{4})').firstMatch(year);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  List<PaymentScheduleInstallment> _defaultScheduleInstallments(
    String classAcademicYear,
  ) {
    final startYear =
        _academicYearStartYear(classAcademicYear) ?? DateTime.now().year;
    // Default: 3 trimesters, due 15 Oct / 15 Jan / 15 Apr
    return [
      PaymentScheduleInstallment(
        label: 'Trimestre 1',
        dueDate: DateTime(startYear, 10, 15).toIso8601String(),
        fraction: 1 / 3,
      ),
      PaymentScheduleInstallment(
        label: 'Trimestre 2',
        dueDate: DateTime(startYear + 1, 1, 15).toIso8601String(),
        fraction: 1 / 3,
      ),
      PaymentScheduleInstallment(
        label: 'Trimestre 3',
        dueDate: DateTime(startYear + 1, 4, 15).toIso8601String(),
        fraction: 1 / 3,
      ),
    ];
  }

  List<PaymentScheduleInstallment> _installmentsForStudent(Student student) {
    final year = student.academicYear;
    final rule = _scheduleRuleByClass[student.className] ?? _globalScheduleRule;
    final decoded = rule?.decodeInstallments() ?? const [];
    if (decoded.isNotEmpty) return decoded;
    return _defaultScheduleInstallments(year);
  }

  double _expectedPaidByDate(Student student, DateTime at) {
    final totalDue = _adjustedTotalDueForStudent(student);
    if (totalDue <= 0) return 0.0;
    final installments = _installmentsForStudent(student);
    double fractionSum = 0.0;
    for (final i in installments) {
      final due = _parseAnyDate(i.dueDate);
      if (due == null) continue;
      if (!due.isAfter(at)) {
        fractionSum += i.fraction;
      }
    }
    if (fractionSum < 0) fractionSum = 0;
    if (fractionSum > 1) fractionSum = 1;
    return totalDue * fractionSum;
  }

  double _arrearsByNow(Student student) {
    final now = DateTime.now();
    final expected = _expectedPaidByDate(student, now);
    final totalPaid = _payments
        .where((p) => p.studentId == student.id && !p.isCancelled)
        .fold<double>(0.0, (s, p) => s + p.amount);
    final arrears = expected - totalPaid;
    return arrears > 0 ? arrears : 0.0;
  }

  List<Map<String, dynamic>> _rowsForBaseFilters() {
    List<Map<String, dynamic>> rows = allRows;
    if (_selectedClassFilter != null) {
      rows = rows
          .where(
            (row) =>
                (row['student'] as Student).className == _selectedClassFilter,
          )
          .toList();
    }
    if (_selectedGenderFilter != null) {
      rows = rows
          .where(
            (row) =>
                (row['student'] as Student).gender == _selectedGenderFilter,
          )
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final name = _displayStudentName(student).toLowerCase();
        final classe = student.className.toLowerCase();
        return name.contains(_searchQuery.toLowerCase()) ||
            student.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            classe.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    return rows;
  }

  Future<void> _showRemindersDialog(ThemeData theme) async {
    final baseRows = _rowsForBaseFilters();
    final reminders =
        baseRows
            .map((row) {
              final student = row['student'] as Student;
              final totalPaid = _payments
                  .where((p) => p.studentId == student.id && !p.isCancelled)
                  .fold<double>(0.0, (s, p) => s + p.amount);
              final totalDue = _adjustedTotalDueForStudent(student);
              final expectedPaid = _expectedPaidByDate(student, DateTime.now());
              final arrears = expectedPaid - totalPaid;
              return {
                'student': student,
                'payment': row['payment'],
                'classe': _classesByName[student.className],
                'totalPaid': totalPaid,
                'totalDue': totalDue,
                'expectedPaid': expectedPaid,
                'arrears': arrears > 0 ? arrears : 0.0,
              };
            })
            .where((r) => ((r['arrears'] as double?) ?? 0.0) > 0)
            .toList()
          ..sort(
            (a, b) =>
                (b['arrears'] as double).compareTo(a['arrears'] as double),
          );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Relances (${reminders.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 820,
            child: reminders.isEmpty
                ? const Text('Aucune relance (aucun retard à date).')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: reminders.length,
                    itemBuilder: (context, i) {
                      final r = reminders[i];
                      final student = r['student'] as Student;
                      final arrears = (r['arrears'] as double?) ?? 0.0;
                      final expectedPaid =
                          (r['expectedPaid'] as double?) ?? 0.0;
                      final totalPaid = (r['totalPaid'] as double?) ?? 0.0;
                      return ListTile(
                        title: Text(
                          '${_displayStudentName(student)} - ${student.className}',
                        ),
                        subtitle: Text(
                          'Attendu: ${expectedPaid.toStringAsFixed(0)} | Payé: ${totalPaid.toStringAsFixed(0)} | Retard: ${arrears.toStringAsFixed(0)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.person_search),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) =>
                                  StudentProfilePage(student: student),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            ElevatedButton.icon(
              onPressed: reminders.isEmpty
                  ? null
                  : () async {
                      if (!SafeModeService.instance.isActionAllowed()) {
                        showSnackBar(
                          this.context,
                          SafeModeService.instance.getBlockedActionMessage(),
                          isError: true,
                        );
                        return;
                      }
                      final dirPath = await FilePicker.platform
                          .getDirectoryPath(
                            dialogTitle: 'Choisir un dossier de sauvegarde',
                          );
                      if (dirPath == null) return;
                      final bytes =
                          await PdfService.generatePaymentRemindersPdf(
                            rows: reminders,
                          );
                      final file = File(
                        '$dirPath/relances_paiements_${DateTime.now().millisecondsSinceEpoch}.pdf',
                      );
                      await file.writeAsBytes(bytes);
                      if (!mounted) return;
                      showSnackBar(
                        this.context,
                        'Relances exportées: ${file.path}',
                      );
                      try {
                        await OpenFile.open(file.path);
                      } catch (_) {}
                    },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Exporter PDF'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showScheduleDialog(ThemeData theme) async {
    final year = _selectedYearFilter ?? academicYearNotifier.value;
    final String effectiveYear = year.trim().isNotEmpty
        ? year.trim()
        : (await getCurrentAcademicYear());
    final String? selectedClass = _selectedClassFilter;
    bool forClass = selectedClass != null && selectedClass.trim().isNotEmpty;

    List<PaymentScheduleInstallment> currentInstallments() {
      if (forClass && selectedClass != null) {
        final r = _scheduleRuleByClass[selectedClass] ?? _globalScheduleRule;
        final decoded = r?.decodeInstallments() ?? const [];
        if (decoded.isNotEmpty) return decoded;
        return _defaultScheduleInstallments(effectiveYear);
      }
      final decoded = _globalScheduleRule?.decodeInstallments() ?? const [];
      return decoded.isNotEmpty
          ? decoded
          : _defaultScheduleInstallments(effectiveYear);
    }

    List<PaymentScheduleInstallment> installments = currentInstallments();
    final labelCtrls = <TextEditingController>[];
    final dateCtrls = <TextEditingController>[];
    final pctCtrls = <TextEditingController>[];

    void rebuildControllers() {
      for (final c in [...labelCtrls, ...dateCtrls, ...pctCtrls]) {
        c.dispose();
      }
      labelCtrls.clear();
      dateCtrls.clear();
      pctCtrls.clear();
      for (final i in installments) {
        labelCtrls.add(TextEditingController(text: i.label));
        final d = _parseAnyDate(i.dueDate);
        dateCtrls.add(
          TextEditingController(
            text: d != null ? DateFormat('dd/MM/yyyy').format(d) : i.dueDate,
          ),
        );
        pctCtrls.add(
          TextEditingController(text: (i.fraction * 100).toStringAsFixed(2)),
        );
      }
    }

    void genTrimestriel() {
      installments = _defaultScheduleInstallments(effectiveYear);
      rebuildControllers();
    }

    void genMensuel() {
      final startYear =
          _academicYearStartYear(effectiveYear) ?? DateTime.now().year;
      // Oct -> Jul (10 échéances)
      final months = <int>[10, 11, 12, 1, 2, 3, 4, 5, 6, 7];
      final fraction = 1 / months.length;
      installments = List.generate(months.length, (idx) {
        final m = months[idx];
        final y = (m >= 10) ? startYear : (startYear + 1);
        return PaymentScheduleInstallment(
          label: 'Mois ${idx + 1}',
          dueDate: DateTime(y, m, 15).toIso8601String(),
          fraction: fraction,
        );
      });
      rebuildControllers();
    }

    rebuildControllers();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Échéancier'),
              content: SizedBox(
                width: 900,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Année: $effectiveYear',
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        ),
                        if (selectedClass != null)
                          Row(
                            children: [
                              const Text('Spécifique à la classe'),
                              Switch(
                                value: forClass,
                                onChanged: (v) {
                                  setStateDialog(() {
                                    forClass = v;
                                    installments = currentInstallments();
                                    rebuildControllers();
                                  });
                                },
                              ),
                              if (forClass)
                                Text(
                                  selectedClass,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              setStateDialog(() => genTrimestriel()),
                          child: const Text('Générer trimestriel'),
                        ),
                        OutlinedButton(
                          onPressed: () => setStateDialog(() => genMensuel()),
                          child: const Text('Générer mensuel'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            setStateDialog(() {
                              installments = [];
                              rebuildControllers();
                            });
                          },
                          child: const Text('Vider'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (installments.isEmpty)
                      const Text('Aucune échéance (utilise le défaut).')
                    else
                      SizedBox(
                        height: 320,
                        child: ListView.builder(
                          itemCount: installments.length,
                          itemBuilder: (context, i) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: labelCtrls[i],
                                      decoration: const InputDecoration(
                                        labelText: 'Libellé',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: dateCtrls[i],
                                      decoration: const InputDecoration(
                                        labelText: 'Échéance (dd/MM/yyyy)',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: pctCtrls[i],
                                      decoration: const InputDecoration(
                                        labelText: '%',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () {
                                      setStateDialog(() {
                                        installments.removeAt(i);
                                        rebuildControllers();
                                      });
                                    },
                                    icon: const Icon(Icons.delete_outline),
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fermer'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!SafeModeService.instance.isActionAllowed()) {
                      showSnackBar(
                        this.context,
                        SafeModeService.instance.getBlockedActionMessage(),
                        isError: true,
                      );
                      return;
                    }

                    final cleaned = <Map<String, dynamic>>[];
                    double sumFrac = 0.0;
                    for (int i = 0; i < labelCtrls.length; i++) {
                      final label = labelCtrls[i].text.trim();
                      final dateRaw = dateCtrls[i].text.trim();
                      final pctRaw = pctCtrls[i].text.trim().replaceAll(
                        ',',
                        '.',
                      );
                      final pct = double.tryParse(pctRaw);
                      final due = _parseAnyDate(dateRaw);
                      if (label.isEmpty ||
                          due == null ||
                          pct == null ||
                          pct <= 0) {
                        continue;
                      }
                      final frac = pct / 100.0;
                      sumFrac += frac;
                      cleaned.add({
                        'label': label,
                        'dueDate': due.toIso8601String(),
                        'fraction': frac,
                      });
                    }
                    if (cleaned.isNotEmpty && sumFrac > 0) {
                      // Normalize if user entered >100%
                      if (sumFrac > 1.0) {
                        for (final m in cleaned) {
                          m['fraction'] = (m['fraction'] as double) / sumFrac;
                        }
                      }
                    }

                    String? by;
                    try {
                      final user = await AuthService.instance.getCurrentUser();
                      by = user?.displayName ?? user?.username;
                    } catch (_) {}

                    await _dbService.setPaymentScheduleRule(
                      classAcademicYear: effectiveYear,
                      className: forClass ? selectedClass : null,
                      scheduleJson: jsonEncode(cleaned),
                      updatedBy: by,
                    );
                    if (!mounted) return;
                    showSnackBar(this.context, 'Échéancier enregistré');
                    await _fetchPayments();
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

  List<Map<String, dynamic>> get allRows {
    // Associe chaque élève à son dernier paiement (ou null si aucun)
    final List<Map<String, dynamic>> rows = [];
    for (final student in _studentsById.values) {
      final studentPayments = _payments
          .where((p) => p.studentId == student.id && !p.isCancelled)
          .toList();
      Payment? lastPayment;
      if (studentPayments.isNotEmpty) {
        studentPayments.sort((a, b) => b.date.compareTo(a.date));
        lastPayment = studentPayments.first;
      }
      rows.add({'student': student, 'payment': lastPayment});
    }
    return rows;
  }

  List<Map<String, dynamic>> get filteredRows {
    List<Map<String, dynamic>> rows = allRows;
    if (_selectedClassFilter != null) {
      rows = rows
          .where(
            (row) =>
                (row['student'] as Student).className == _selectedClassFilter,
          )
          .toList();
    }
    // L'année est déjà appliquée au chargement (via _fetchPayments), donc pas de filtre multi-années ici.
    if (_selectedGenderFilter != null) {
      rows = rows
          .where(
            (row) =>
                (row['student'] as Student).gender == _selectedGenderFilter,
          )
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final name = _displayStudentName(student).toLowerCase();
        final classe = student.className.toLowerCase();
        return name.contains(_searchQuery.toLowerCase()) ||
            student.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            classe.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    // Filtrage par statut via tab
    if (_currentTab == 1) {
      // Impayés (aucun paiement)
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final studentPayments = _payments
            .where((p) => p.studentId == student.id && !p.isCancelled)
            .toList();
        return studentPayments.isEmpty;
      }).toList();
    } else if (_currentTab == 2) {
      // En attente (a payé partiellement, mais pas tout)
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final montantMax = _adjustedTotalDueForStudent(student);
        final studentPayments = _payments
            .where((p) => p.studentId == student.id && !p.isCancelled)
            .toList();
        final totalPaid = studentPayments.fold<double>(
          0,
          (sum, pay) => sum + pay.amount,
        );
        return studentPayments.isNotEmpty &&
            (montantMax == 0 || totalPaid < montantMax);
      }).toList();
    } else if (_currentTab == 3) {
      // Payés
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final montantMax = _adjustedTotalDueForStudent(student);
        final totalPaid = _payments
            .where((pay) => pay.studentId == student.id && !pay.isCancelled)
            .fold<double>(0, (sum, pay) => sum + pay.amount);
        return montantMax > 0 && totalPaid >= montantMax;
      }).toList();
    } else if (_currentTab == 4) {
      // Annulés: handled separately
    } else if (_currentTab == 5) {
      // Relances (en retard à date)
      rows = rows.where((row) {
        final student = row['student'] as Student;
        return _arrearsByNow(student) > 0;
      }).toList();
    }
    return rows;
  }

  List<Payment> get filteredCancelledPayments {
    return _cancelledPayments.where((p) {
      if (_selectedClassFilter != null && p.className != _selectedClassFilter) {
        return false;
      }
      final student = _studentsById[p.studentId];
      if (_selectedGenderFilter != null) {
        if (student == null) return false;
        if (student.gender != _selectedGenderFilter) return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = student != null ? _displayStudentName(student) : '';
        final matchesStudent =
            student != null &&
            (name.toLowerCase().contains(q) ||
                student.name.toLowerCase().contains(q));
        final matchesClass = p.className.toLowerCase().contains(q);
        return matchesStudent || matchesClass;
      }
      return true;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  List<Map<String, dynamic>> get _sortedRowsForUi {
    final rows = List<Map<String, dynamic>>.from(filteredRows);
    rows.sort(
      (a, b) => _compareStudentsByName(
        a['student'] as Student,
        b['student'] as Student,
      ),
    );
    return rows;
  }

  List<Map<String, dynamic>> get paginatedRows {
    final start = _currentPage * _rowsPerPage;
    final rows = _sortedRowsForUi;
    final end = (start + _rowsPerPage).clamp(0, rows.length);
    return rows.sublist(start, end);
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
                    ? Center(child: CircularProgressIndicator())
                    : _buildPaymentsTable(context, isDarkMode, theme),
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
                      Icons.payments,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des Paiements',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Gérez les frais de scolarité, générez des reçus et suivez les soldes impayés.',
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
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Rechercher par nom d\'étudiant ou classe',
              hintStyle: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsTable(
    BuildContext context,
    bool isDarkMode,
    ThemeData theme,
  ) {
    final showCancelledTab = _currentTab == 4;
    final showRemindersTab = _currentTab == 5;
    final totalPages = showCancelledTab
        ? 1
        : (filteredRows.length / _rowsPerPage).ceil();
    final classList = _classesByName.keys.toList()..sort();
    final yearList = _years.toList()..sort();
    final genderList = ['M', 'F'];
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // TabBar pour filtrer par statut
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
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF6366F1).withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 2),
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
                    Tab(text: 'Tous'),
                    Tab(text: 'Impayés'),
                    Tab(text: 'En attente'),
                    Tab(text: 'Payés'),
                    Tab(text: 'Annulés'),
                    Tab(text: 'Relances'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Filtre classe
                        DropdownButton<String?>(
                          value: _selectedClassFilter,
                          hint: Text(
                            'Classe',
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'Toutes les classes',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                            ...classList.map(
                              (c) => DropdownMenuItem<String?>(
                                value: c,
                                child: Text(
                                  c,
                                  style: TextStyle(
                                    color: theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedClassFilter = value),
                          dropdownColor: theme.cardColor,
                          iconEnabledColor: theme.iconTheme.color,
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        // Filtre année
                        ValueListenableBuilder<String>(
                          valueListenable: academicYearNotifier,
                          builder: (context, currentYear, _) {
                            return DropdownButton<String?>(
                              value: _selectedYearFilter,
                              hint: Text(
                                'Année',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(
                                    'Toutes les années',
                                    style: TextStyle(
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem<String?>(
                                  value: currentYear,
                                  child: Text(
                                    'Année courante ($currentYear)',
                                    style: TextStyle(
                                      color: theme.textTheme.bodyMedium?.color,
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
                                            color: theme
                                                .textTheme
                                                .bodyMedium
                                                ?.color,
                                          ),
                                        ),
                                      ),
                                    ),
                              ],
                              onChanged: (value) {
                                final newValue = value ?? currentYear;
                                setState(() => _selectedYearFilter = newValue);
                                _fetchPayments();
                              },
                              dropdownColor: theme.cardColor,
                              iconEnabledColor: theme.iconTheme.color,
                              style: TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                            );
                          },
                        ),
                        // Filtre sexe
                        DropdownButton<String?>(
                          value: _selectedGenderFilter,
                          hint: Text(
                            'Sexe',
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'Tous',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'M',
                              child: Text(
                                'Garçons',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'F',
                              child: Text(
                                'Filles',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedGenderFilter = value),
                          dropdownColor: theme.cardColor,
                          iconEnabledColor: theme.iconTheme.color,
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: showCancelledTab
                              ? null
                              : () => _showScheduleDialog(theme),
                          icon: const Icon(Icons.event_note),
                          label: const Text('Échéancier'),
                        ),
                        ElevatedButton.icon(
                          onPressed: showCancelledTab
                              ? null
                              : () => _showRemindersDialog(theme),
                          icon: const Icon(
                            Icons.notifications_active,
                            color: Colors.white,
                          ),
                          label: Text(
                            showRemindersTab ? 'Exporter relances' : 'Relances',
                          ),
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
                        ElevatedButton.icon(
                          onPressed: showCancelledTab
                              ? null
                              : () => _exportToPdf(theme),
                          icon: const Icon(
                            Icons.picture_as_pdf,
                            color: Colors.white,
                          ),
                          label: const Text('Exporter PDF'),
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
                          onPressed: showCancelledTab
                              ? null
                              : () => _exportToExcel(theme),
                          icon: const Icon(Icons.grid_on, color: Colors.white),
                          label: const Text('Exporter Excel'),
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
                          onPressed: showCancelledTab
                              ? null
                              : () => _exportToWord(theme),
                          icon: const Icon(
                            Icons.description,
                            color: Colors.white,
                          ),
                          label: const Text('Exporter Word'),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showCancelledTab) ...[
              _buildCancelledHeader(theme),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredCancelledPayments.length,
                  itemBuilder: (context, i) {
                    final pay = filteredCancelledPayments[i];
                    final student = _studentsById[pay.studentId];
                    return _buildCancelledRow(theme, student, pay);
                  },
                ),
              ),
            ] else ...[
              _buildTableHeader(isDarkMode, theme),
              Expanded(
                child: ListView.builder(
                  itemCount: paginatedRows.length,
                  itemBuilder: (context, index) {
                    final row = paginatedRows[index];
                    final student = row['student'] as Student;
                    final payment = row['payment'] as Payment?;
                    return _buildTableRowV2(
                      student,
                      payment,
                      isDarkMode,
                      theme,
                    );
                  },
                ),
              ),
            ],
            if (!showCancelledTab && totalPages > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left),
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage--)
                          : null,
                    ),
                    Text(
                      'Page ${_currentPage + 1} / $totalPages',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right),
                      onPressed: _currentPage < totalPages - 1
                          ? () => setState(() => _currentPage++)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(bool isDarkMode, ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('Nom de l\'Étudiant', flex: 3, theme: theme),
          _buildHeaderCell('Classe', flex: 2, theme: theme),
          _buildHeaderCell('Date de Paiement', flex: 2, theme: theme),
          _buildHeaderCell('Montant', flex: 2, theme: theme),
          _buildHeaderCell('Dû', flex: 2, theme: theme),
          _buildHeaderCell('Retard', flex: 2, theme: theme),
          _buildHeaderCell('Commentaire', flex: 3, theme: theme),
          _buildHeaderCell('Enregistré par', flex: 2, theme: theme),
          _buildHeaderCell('Statut', flex: 2, theme: theme),
          _buildHeaderCell('Action', flex: 2, theme: theme),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    String text, {
    int flex = 1,
    required ThemeData theme,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: theme.textTheme.bodyMedium?.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCancelledHeader(ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('Étudiant', flex: 3, theme: theme),
          _buildHeaderCell('Classe', flex: 2, theme: theme),
          _buildHeaderCell('Date', flex: 2, theme: theme),
          _buildHeaderCell('Montant', flex: 2, theme: theme),
          _buildHeaderCell('Motif', flex: 3, theme: theme),
          _buildHeaderCell('Annulé par', flex: 2, theme: theme),
        ],
      ),
    );
  }

  Widget _buildCancelledRow(ThemeData theme, Student? student, Payment p) {
    final studentName = student != null
        ? _displayStudentName(student)
        : p.studentId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          _buildCell(
            studentName,
            flex: 3,
            isName: true,
            isDarkMode: false,
            theme: theme,
          ),
          _buildCell(p.className, flex: 2, isDarkMode: false, theme: theme),
          _buildCell(
            p.date.substring(0, 10),
            flex: 2,
            isDarkMode: false,
            theme: theme,
          ),
          _buildCell(
            p.amount.toStringAsFixed(0),
            flex: 2,
            isDarkMode: false,
            theme: theme,
          ),
          _buildCell(
            p.cancelReason ?? '-',
            flex: 3,
            isDarkMode: false,
            theme: theme,
          ),
          _buildCell(
            p.cancelBy ?? '-',
            flex: 2,
            isDarkMode: false,
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildCell(
    String text, {
    int flex = 1,
    bool isName = false,
    required bool isDarkMode,
    required ThemeData theme,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isName ? FontWeight.w600 : FontWeight.w400,
          color: isName
              ? theme.textTheme.bodyLarge?.color
              : theme.textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  Widget _buildTableRowV2(
    Student student,
    Payment? p,
    bool isDarkMode,
    ThemeData theme,
  ) {
    final montantMax = _adjustedTotalDueForStudent(student);
    final totalPaid = _payments
        .where((pay) => pay.studentId == student.id && !pay.isCancelled)
        .fold<double>(0, (sum, pay) => sum + pay.amount);
    final bool isPaid = montantMax > 0 && totalPaid >= montantMax;
    final bool hasPayment = p != null;
    final arrears = _arrearsByNow(student);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _buildCell(
            _displayStudentName(student),
            flex: 3,
            isName: true,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            student.className,
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            hasPayment ? p!.date.replaceFirst('T', ' ').substring(0, 16) : '',
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            hasPayment ? '${p!.amount.toStringAsFixed(2)} FCFA' : '',
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            '${montantMax.toStringAsFixed(2)} FCFA',
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            arrears > 0 ? '${arrears.toStringAsFixed(2)} FCFA' : '-',
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            hasPayment ? (p!.comment ?? '') : '',
            flex: 3,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            hasPayment ? (p!.recordedBy ?? '-') : '',
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: isPaid
                      ? [Color(0xFF10B981), Color(0xFF059669)]
                      : (arrears > 0
                            ? [Color(0xFFF59E0B), Color(0xFFD97706)]
                            : [Color(0xFFEF4444), Color(0xFFDC2626)]),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isPaid
                                ? Color(0xFF10B981)
                                : (arrears > 0
                                      ? Color(0xFFF59E0B)
                                      : Color(0xFFEF4444)))
                            .withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                isPaid ? 'Payé' : (hasPayment ? 'En attente' : 'Impayé'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          _buildActionCellV2(student, p, isDarkMode, theme),
        ],
      ),
    );
  }

  Widget _buildActionCellV2(
    Student student,
    Payment? p,
    bool isDarkMode,
    ThemeData theme,
  ) {
    return Expanded(
      flex: 2,
      child: Align(
        alignment: Alignment.center,
        child: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
          onSelected: (value) async {
            if (value == 'view_recu' && p != null) {
              await _handleReceiptPdf(p, student, theme, saveOnly: false);
            } else if (value == 'save_recu' && p != null) {
              await _handleReceiptPdf(p, student, theme, saveOnly: true);
            } else if (value == 'view_ticket' && p != null) {
              await _handleTicketPdf(p, student, theme, saveOnly: false);
            } else if (value == 'save_ticket' && p != null) {
              await _handleTicketPdf(p, student, theme, saveOnly: true);
            } else if (value == 'attachments' && p != null) {
              await _showPaymentAttachmentsDialog(p, student, theme);
            } else if (value == 'cancel_payment' && p != null) {
              await _cancelPaymentWithReasonFlow(p);
            } else if (value == 'ajouter') {
              _showAddPaymentDialog(student, theme);
            } else if (value == 'details') {
              _showStudentDetailsDialog(student, theme);
            } else if (value == 'profile') {
              showDialog(
                context: context,
                builder: (context) => StudentProfilePage(student: student),
              );
            }
          },

          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view_recu',
              enabled: p != null,
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_rounded,
                    color: p != null ? theme.colorScheme.primary : Colors.grey,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voir reçu',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'save_recu',
              enabled: p != null,
              child: Row(
                children: [
                  Icon(
                    Icons.save_alt,
                    color: p != null ? theme.colorScheme.primary : Colors.grey,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Enregistrer reçu',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'view_ticket',
              enabled: p != null,
              child: Row(
                children: [
                  Icon(
                    Icons.confirmation_number_outlined,
                    color: p != null ? Colors.deepPurple : Colors.grey,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voir reçu (compact)',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'save_ticket',
              enabled: p != null,
              child: Row(
                children: [
                  Icon(
                    Icons.file_download_outlined,
                    color: p != null ? Colors.deepPurple : Colors.grey,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Enregistrer reçu (compact)',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'attachments',
              enabled: p != null && p.id != null,
              child: Row(
                children: [
                  Icon(
                    Icons.attach_file,
                    color: (p != null && p.id != null)
                        ? theme.colorScheme.primary
                        : Colors.grey,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Justificatifs',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'cancel_payment',
              enabled: p != null,
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    color: p != null ? Colors.red : Colors.grey,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Annuler paiement',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'ajouter',
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    color: theme.colorScheme.secondary,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Ajouter paiement',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.onSurface,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voir détails',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  Icon(
                    Icons.person_search,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voir profil élève',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
          ],
          color: theme.cardColor, // Set background color of the popup menu
        ),
      ),
    );
  }

  void _showAddPaymentDialog(Student student, ThemeData theme) async {
    final double montantMax = _adjustedTotalDueForStudent(student);
    if (montantMax == 0) {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Alerte',
          content: Text(
            'Veuillez renseigner un montant de frais d\'école ou de cotisation dans la fiche classe avant d\'enregistrer un paiement.',
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
          ],
        ),
      );
      return;
    }
    final montantController = TextEditingController(text: '0');
    final commentController = TextEditingController();
    final totalPaid = _payments
        .where((p) => p.studentId == student.id && !p.isCancelled)
        .fold<double>(0, (sum, pay) => sum + pay.amount);
    final reste = montantMax - totalPaid;
    final double totalDiscounts = _totalDiscountsForStudent(student);
    if (reste <= 0) {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Alerte',
          content: Text(
            'L\'élève a déjà tout payé pour cette classe.',
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
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
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total dû (ajusté) : ${montantMax.toStringAsFixed(2)} FCFA',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            Text(
              'Déjà payé : ${totalPaid.toStringAsFixed(2)} FCFA',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            if (totalDiscounts > 0)
              Text(
                'Remises : -${totalDiscounts.toStringAsFixed(2)} FCFA',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
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
          try {
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Paiement enregistré avec succès'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop();
            _fetchPayments();
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erreur lors de l\'enregistrement: $e'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Annuler',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final val = double.tryParse(montantController.text);
              if (val == null || val < 0) return;
              if (val > reste) {
                showMontantDepasseAlerte();
                return;
              }
              try {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Paiement enregistré avec succès'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.of(context).pop();
                _fetchPayments();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erreur lors de l\'enregistrement: $e'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            },
            child: const Text('Valider', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showStudentDetailsDialog(Student student, ThemeData theme) async {
    final double montantMax = _adjustedTotalDueForStudent(student);
    final totalPaid = _payments
        .where((p) => p.studentId == student.id && !p.isCancelled)
        .fold<double>(0, (sum, pay) => sum + pay.amount);
    final reste = montantMax - totalPaid;
    final status = (montantMax > 0 && totalPaid >= montantMax)
        ? 'Payé'
        : 'En attente';
    final payments = _payments.where((p) => p.studentId == student.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
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
              _buildDetailRow(
                'Nom complet',
                _displayStudentName(student),
                theme,
              ),
              _buildDetailRow('ID', student.id, theme),
              _buildDetailRow('Date de naissance', student.dateOfBirth, theme),
              _buildDetailRow(
                'Sexe',
                student.gender == 'M' ? 'Garçon' : 'Fille',
                theme,
              ),
              _buildDetailRow('Classe', student.className, theme),
              _buildDetailRow('Adresse', student.address, theme),
              _buildDetailRow('Contact', student.contactNumber, theme),
              _buildDetailRow('Email', student.email, theme),
              _buildDetailRow(
                'Contact d\'urgence',
                student.emergencyContact,
                theme,
              ),
              _buildDetailRow('Tuteur', student.guardianName, theme),
              _buildDetailRow('Contact tuteur', student.guardianContact, theme),
              if (student.medicalInfo != null &&
                  student.medicalInfo!.isNotEmpty)
                _buildDetailRow('Infos médicales', student.medicalInfo!, theme),
              const SizedBox(height: 16),
              Divider(color: theme.dividerColor),
              Text(
                'Paiement',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Montant dû',
                '${montantMax.toStringAsFixed(2)} FCFA',
                theme,
              ),
              if (_totalDiscountsForStudent(student) > 0)
                _buildDetailRow(
                  'Remises',
                  '-${_totalDiscountsForStudent(student).toStringAsFixed(2)} FCFA',
                  theme,
                ),
              _buildDetailRow(
                'Déjà payé',
                '${totalPaid.toStringAsFixed(2)} FCFA',
                theme,
              ),
              _buildDetailRow(
                'Reste à payer',
                reste <= 0 ? 'Payé' : '${reste.toStringAsFixed(2)} FCFA',
                theme,
              ),
              _buildDetailRow('Statut', status, theme),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.percent),
                  label: const Text('Ajouter une remise'),
                  onPressed: () async {
                    if (!SafeModeService.instance.isActionAllowed()) {
                      showSnackBar(
                        context,
                        SafeModeService.instance.getBlockedActionMessage(),
                        isError: true,
                      );
                      return;
                    }
                    final amountCtrl = TextEditingController();
                    final reasonCtrl = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => CustomDialog(
                        title: 'Remise',
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CustomFormField(
                              controller: amountCtrl,
                              labelText: 'Montant remise',
                              hintText: 'Ex: 5000',
                              suffixIcon: Icons.money_off,
                              validator: (v) {
                                final d = double.tryParse((v ?? '').trim());
                                if (d == null || d <= 0) {
                                  return 'Montant invalide';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            CustomFormField(
                              controller: reasonCtrl,
                              labelText: 'Motif',
                              hintText: 'Ex: bourse, réduction, etc.',
                              isTextArea: true,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Motif requis'
                                  : null,
                            ),
                          ],
                        ),
                        fields: const [],
                        onSubmit: () => Navigator.of(dialogContext).pop(true),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Annuler'),
                          ),
                          ElevatedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Valider'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    final amount = double.tryParse(amountCtrl.text.trim());
                    final reason = reasonCtrl.text.trim();
                    if (amount == null || amount <= 0 || reason.isEmpty) {
                      showSnackBar(
                        context,
                        'Montant et motif obligatoires.',
                        isError: true,
                      );
                      return;
                    }
                    String? by;
                    try {
                      final user = await AuthService.instance.getCurrentUser();
                      by = user?.displayName ?? user?.username;
                    } catch (_) {}
                    await _dbService.insertPaymentAdjustment(
                      PaymentAdjustment(
                        studentId: student.id,
                        className: student.className,
                        classAcademicYear: student.academicYear,
                        type: 'discount',
                        amount: amount,
                        reason: reason,
                        createdAt: DateTime.now().toIso8601String(),
                        createdBy: by,
                      ),
                    );
                    showSnackBar(context, 'Remise ajoutée');
                    await _fetchPayments();
                    Navigator.of(context).pop();
                    _showStudentDetailsDialog(student, theme);
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (payments.isNotEmpty) ...[
                Text(
                  'Historique des paiements',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                ...payments.map(
                  (p) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: theme.cardColor,
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
                              color: p.isCancelled
                                  ? Colors.grey
                                  : theme.textTheme.bodyLarge?.color,
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
                              color: p.isCancelled
                                  ? Colors.grey
                                  : theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                          if ((p.receiptNo ?? '').trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Reçu : ${p.receiptNo}',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if ((p.recordedBy ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Enregistré par : ${p.recordedBy}',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (p.comment != null && p.comment!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Commentaire : ${p.comment!}',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
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
                                  icon: Icon(
                                    Icons.attach_file,
                                    color: theme.colorScheme.primary,
                                  ),
                                  tooltip: 'Justificatifs',
                                  onPressed: () =>
                                      _showPaymentAttachmentsDialog(
                                        p,
                                        student,
                                        theme,
                                      ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.confirmation_number_outlined,
                                    color: Colors.deepPurple,
                                  ),
                                  tooltip: 'Voir le reçu (compact)',
                                  onPressed: () => _handleTicketPdf(
                                    p,
                                    student,
                                    theme,
                                    saveOnly: false,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.picture_as_pdf,
                                    color: Colors.blue,
                                  ),
                                  tooltip: 'Voir le reçu',
                                  onPressed: () => _handleReceiptPdf(
                                    p,
                                    student,
                                    theme,
                                    saveOnly: false,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.save_alt,
                                    color: Colors.blueGrey,
                                  ),
                                  tooltip: 'Enregistrer le reçu',
                                  onPressed: () => _handleReceiptPdf(
                                    p,
                                    student,
                                    theme,
                                    saveOnly: true,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.file_download_outlined,
                                    color: Colors.deepPurple,
                                  ),
                                  tooltip: 'Enregistrer le reçu (compact)',
                                  onPressed: () => _handleTicketPdf(
                                    p,
                                    student,
                                    theme,
                                    saveOnly: true,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Annuler ce paiement',
                                  onPressed: () async {
                                    await _cancelPaymentWithReasonFlow(
                                      p,
                                      popAfterSuccess: context,
                                    );
                                  },
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Aucun paiement enregistré.',
                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                ),
              ],
            ],
          ),
        ),
        fields: const [],
        onSubmit: () => Navigator.of(context).pop(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Fermer',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReceiptPdf(
    Payment p,
    Student? student,
    ThemeData theme, {
    bool saveOnly = false,
  }) async {
    // Respecter le mode coffre fort: afficher un SnackBar (comme dans GradesPage)
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    if (student == null) return;

    final classe = _classesByName[student.className];
    if (classe == null) return; // Should not happen

    final allPayments =
        _payments.where((p) => p.studentId == student.id).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final totalPaid = allPayments
        .where((p) => !p.isCancelled)
        .fold(0.0, (sum, item) => sum + item.amount);
    final totalDue =
        (classe.fraisEcole ?? 0) + (classe.fraisCotisationParallele ?? 0);

    final schoolInfo = await loadSchoolInfo();
    final pdfBytes = await PdfService.generatePaymentReceiptPdf(
      currentPayment: p,
      allPayments: allPayments,
      student: student,
      schoolInfo: schoolInfo,
      studentClass: classe,
      totalPaid: totalPaid,
      totalDue: totalDue,
    );

    if (saveOnly) {
      String? directoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisir le dossier de sauvegarde',
      );
      if (directoryPath != null) {
        final receiptNo = (p.receiptNo ?? '').trim().isNotEmpty
            ? p.receiptNo!.trim()
            : (p.id?.toString() ?? p.date.hashCode.toString());
        final fileName =
            'Recu_Paiement_${receiptNo}_${student.name.replaceAll(' ', '_')}_${p.date.substring(0, 10)}.pdf';
        final file = File('$directoryPath/$fileName');
        await file.writeAsBytes(pdfBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reçu enregistré dans $directoryPath'),
            backgroundColor: Colors.green,
          ),
        );
        // Ouvrir le PDF immédiatement
        try {
          await OpenFile.open(file.path);
        } catch (_) {}
      }
    } else {
      // Écrire le PDF dans un fichier temporaire et l'ouvrir
      final tmpDir = await getTemporaryDirectory();
      final receiptNo = (p.receiptNo ?? '').trim().isNotEmpty
          ? p.receiptNo!.trim()
          : (p.id?.toString() ?? p.date.hashCode.toString());
      final fileName =
          'Recu_Paiement_${receiptNo}_${student.name.replaceAll(' ', '_')}_${p.date.substring(0, 19).replaceAll(':', '-')}.pdf';
      final file = File('${tmpDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      try {
        await OpenFile.open(file.path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reçu PDF ouvert'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir le PDF'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleTicketPdf(
    Payment p,
    Student? student,
    ThemeData theme, {
    bool saveOnly = false,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    if (student == null) return;

    final classe = _classesByName[student.className];
    if (classe == null) return;

    final allPayments =
        _payments.where((p) => p.studentId == student.id).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final totalPaid = allPayments
        .where((p) => !p.isCancelled)
        .fold(0.0, (sum, item) => sum + item.amount);
    final totalDue =
        (classe.fraisEcole ?? 0) + (classe.fraisCotisationParallele ?? 0);

    final schoolInfo = await loadSchoolInfo();
    final pdfBytes = await PdfService.generatePaymentTicketPdf(
      currentPayment: p,
      allPayments: allPayments,
      student: student,
      schoolInfo: schoolInfo,
      studentClass: classe,
      totalPaid: totalPaid,
      totalDue: totalDue,
    );

    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directoryPath == null) return;

    final receiptNo = (p.receiptNo ?? '').trim().isNotEmpty
        ? p.receiptNo!.trim()
        : (p.id?.toString() ?? p.date.hashCode.toString());
    final fileName =
        'Ticket_Paiement_${receiptNo}_${student.name.replaceAll(' ', '_')}_${p.date.substring(0, 10)}.pdf';
    final file = File('$directoryPath/$fileName');
    await file.writeAsBytes(pdfBytes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ticket enregistré dans $directoryPath'),
        backgroundColor: Colors.green,
      ),
    );
    try {
      await OpenFile.open(file.path);
    } catch (_) {}
  }

  Future<String> _ensurePaymentAttachmentsDir({
    required String studentId,
    required String classAcademicYear,
    required int paymentId,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final dir = Directory(
      path.join(
        directory.path,
        'payment_attachments',
        classAcademicYear,
        studentId,
        paymentId.toString(),
      ),
    );
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _showPaymentAttachmentsDialog(
    Payment payment,
    Student student,
    ThemeData theme,
  ) async {
    final paymentId = payment.id;
    if (paymentId == null) {
      showSnackBar(context, 'Paiement invalide (id manquant).', isError: true);
      return;
    }
    final attachments = await _dbService.getPaymentAttachmentsForPayment(
      paymentId: paymentId,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Justificatifs - ${payment.receiptNo ?? paymentId}'),
          content: SizedBox(
            width: 760,
            child: attachments.isEmpty
                ? const Text('Aucun justificatif.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: attachments.length,
                    itemBuilder: (context, i) {
                      final a = attachments[i];
                      return ListTile(
                        leading: const Icon(Icons.attach_file),
                        title: Text(a.fileName),
                        subtitle: Text(a.filePath),
                        onTap: () async {
                          try {
                            await OpenFile.open(a.filePath);
                          } catch (e) {
                            showSnackBar(
                              this.context,
                              'Impossible d’ouvrir: $e',
                              isError: true,
                            );
                          }
                        },
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () async {
                            if (!SafeModeService.instance.isActionAllowed()) {
                              showSnackBar(
                                this.context,
                                SafeModeService.instance
                                    .getBlockedActionMessage(),
                                isError: true,
                              );
                              return;
                            }
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Supprimer ?'),
                                content: Text(
                                  'Confirmer la suppression de “${a.fileName}”.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Annuler'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
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
                            if (a.id != null) {
                              await _dbService.deletePaymentAttachment(
                                id: a.id!,
                              );
                            }
                            try {
                              final f = File(a.filePath);
                              if (f.existsSync()) await f.delete();
                            } catch (_) {}
                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                            await _showPaymentAttachmentsDialog(
                              payment,
                              student,
                              theme,
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
              onPressed: () async {
                if (!SafeModeService.instance.isActionAllowed()) {
                  showSnackBar(
                    this.context,
                    SafeModeService.instance.getBlockedActionMessage(),
                    isError: true,
                  );
                  return;
                }
                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: false,
                  type: FileType.custom,
                  allowedExtensions: [
                    'pdf',
                    'jpg',
                    'jpeg',
                    'png',
                    'doc',
                    'docx',
                    'xls',
                    'xlsx',
                  ],
                  withData: true,
                );
                if (result == null || result.files.isEmpty) return;
                final f = result.files.single;
                final name = f.name.trim();
                if (name.isEmpty) return;
                final destDir = await _ensurePaymentAttachmentsDir(
                  studentId: student.id,
                  classAcademicYear: student.academicYear,
                  paymentId: paymentId,
                );
                final uuid = const Uuid();
                final ext = path.extension(name);
                final base = path.basenameWithoutExtension(name);
                final safeBase = base
                    .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
                    .replaceAll(RegExp(r'_+'), '_');
                final outName =
                    '${DateTime.now().millisecondsSinceEpoch}_${uuid.v4()}_$safeBase$ext';
                final outPath = path.join(destDir, outName);
                if (f.path != null) {
                  await File(f.path!).copy(outPath);
                } else if (f.bytes != null) {
                  await File(outPath).writeAsBytes(f.bytes!, flush: true);
                } else {
                  return;
                }

                String? by;
                try {
                  final user = await AuthService.instance.getCurrentUser();
                  by = user?.displayName ?? user?.username;
                } catch (_) {}

                await _dbService.insertPaymentAttachment(
                  PaymentAttachment(
                    paymentId: paymentId,
                    studentId: student.id,
                    classAcademicYear: student.academicYear,
                    fileName: name,
                    filePath: outPath,
                    sizeBytes: f.size,
                    createdAt: DateTime.now().toIso8601String(),
                    createdBy: by,
                  ),
                );
                if (!mounted) return;
                Navigator.of(this.context).pop();
                await _showPaymentAttachmentsDialog(payment, student, theme);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label : ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          ),
        ],
      ),
    );
  }

  void _exportToPdf(ThemeData theme) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF en cours...'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
      final rows = filteredRows.map((row) {
        final student = row['student'] as Student;
        final payment = row['payment'] as Payment?;
        final classe = _classesByName[student.className];
        final totalPaid = _payments
            .where((pay) => pay.studentId == student.id && !pay.isCancelled)
            .fold<double>(0, (sum, pay) => sum + pay.amount);
        final totalDue = _adjustedTotalDueForStudent(student);
        final expectedPaid = _expectedPaidByDate(student, DateTime.now());
        final arrears = expectedPaid - totalPaid;
        return {
          'student': student,
          'payment': payment,
          'classe': classe,
          'totalPaid': totalPaid,
          'totalDue': totalDue,
          'expectedPaid': expectedPaid,
          'arrears': arrears > 0 ? arrears : 0.0,
        };
      }).toList();
      final pdfBytes = await PdfService.exportPaymentsListPdf(rows: rows);
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final file = File(
        '$dirPath/export_paiements_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(pdfBytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF réussi : ${file.path}'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
      // Ouvrir le PDF immédiatement
      try {
        await OpenFile.open(file.path);
      } catch (_) {}
    } catch (e) {
      print('Erreur export PDF : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export PDF : $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  void _exportToExcel(ThemeData theme) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel en cours...'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
      final excel = Excel.createExcel();
      final sheet = excel['Paiements'];
      // En-têtes
      sheet.appendRow([
        TextCellValue('Nom'),
        TextCellValue('Classe'),
        TextCellValue('Année'),
        TextCellValue('Montant dû'),
        TextCellValue('Total payé'),
        TextCellValue('Reste'),
        TextCellValue('Retard'),
        TextCellValue('Date'),
        TextCellValue('Reçu'),
        TextCellValue('Statut'),
        TextCellValue('Commentaire'),
      ]);
      for (final row in filteredRows) {
        final student = row['student'] as Student;
        final payment = row['payment'] as Payment?;
        final classe = _classesByName[student.className];
        final totalPaid = _payments
            .where((pay) => pay.studentId == student.id && !pay.isCancelled)
            .fold<double>(0, (sum, pay) => sum + pay.amount);
        final totalDue = _adjustedTotalDueForStudent(student);
        final expectedPaid = _expectedPaidByDate(student, DateTime.now());
        final arrears = expectedPaid - totalPaid;
        final double remaining = (totalDue - totalPaid) > 0
            ? (totalDue - totalPaid)
            : 0.0;
        String statut;
        if (totalDue > 0 && totalPaid >= totalDue) {
          statut = 'Payé';
        } else if (payment != null && totalPaid > 0) {
          statut = 'En attente';
        } else {
          statut = 'Impayé';
        }
        sheet.appendRow([
          TextCellValue(student.name),
          TextCellValue(student.className),
          TextCellValue(classe?.academicYear ?? ''),
          DoubleCellValue(totalDue),
          DoubleCellValue(totalPaid),
          DoubleCellValue(remaining),
          DoubleCellValue(arrears > 0 ? arrears : 0.0),
          payment != null
              ? TextCellValue(
                  payment.date.replaceFirst('T', ' ').substring(0, 16),
                )
              : TextCellValue(''),
          TextCellValue(payment?.receiptNo ?? ''),
          TextCellValue(statut),
          TextCellValue(payment?.comment ?? ''),
        ]);
      }
      final bytes = excel.encode()!;
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final file = File(
        '$dirPath/export_paiements_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel réussi : ${file.path}'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Erreur export Excel : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Excel : $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  void _exportToWord(ThemeData theme) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Word en cours...'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final docx = await _generatePaymentsDocx(theme);
      final file = File(
        '$dirPath/export_paiements_${DateTime.now().millisecondsSinceEpoch}.docx',
      );
      await file.writeAsBytes(docx);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Word réussi : ${file.path}'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Erreur export Word : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Word : $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  Future<List<int>> _generatePaymentsDocx(ThemeData theme) async {
    try {
      final bytes = await DefaultAssetBundle.of(
        context,
      ).load('assets/empty.docx');
      final docx = await DocxTemplate.fromBytes(bytes.buffer.asUint8List());

      // Créer une nouvelle liste modifiable
      final List<Map<String, String>> rows = [];

      for (final row in filteredRows) {
        final student = row['student'] as Student;
        final payment = row['payment'] as Payment?;
        final classe = _classesByName[student.className];
        final totalPaid = _payments
            .where((pay) => pay.studentId == student.id && !pay.isCancelled)
            .fold<double>(0, (sum, pay) => sum + pay.amount);
        final totalDue = _adjustedTotalDueForStudent(student);
        final remaining = (totalDue - totalPaid) > 0
            ? (totalDue - totalPaid)
            : 0.0;

        String statut;
        if (totalDue > 0 && totalPaid >= totalDue) {
          statut = 'Payé';
        } else if (payment != null && totalPaid > 0) {
          statut = 'En attente';
        } else {
          statut = 'Impayé';
        }

        // Ajouter les données dans un Map
        rows.add({
          'nom': student.name,
          'classe': student.className,
          'annee': classe?.academicYear ?? '',
          'montant_du': totalDue.toStringAsFixed(0),
          'total_paye': totalPaid.toStringAsFixed(0),
          'reste': remaining.toStringAsFixed(0),
          'recu': payment?.receiptNo ?? '',
          'montant': payment != null ? payment.amount.toStringAsFixed(0) : '',
          'date': payment != null
              ? payment.date.replaceFirst('T', ' ').substring(0, 16)
              : '',
          'statut': statut,
          'commentaire': payment?.comment ?? '',
        });
      }

      // Créer le contenu du document
      final content = Content();

      // Ajouter les données au template
      content.add(
        TableContent(
          'paiements',
          rows
              .map(
                (row) => RowContent()
                  ..add(TextContent('nom', row['nom'] ?? ''))
                  ..add(TextContent('classe', row['classe'] ?? ''))
                  ..add(TextContent('annee', row['annee'] ?? ''))
                  ..add(TextContent('montant', row['montant'] ?? ''))
                  ..add(TextContent('date', row['date'] ?? ''))
                  ..add(TextContent('statut', row['statut'] ?? ''))
                  ..add(TextContent('commentaire', row['commentaire'] ?? '')),
              )
              .toList(),
        ),
      );

      // Générer le document
      final generatedDoc = await docx.generate(content);
      if (generatedDoc == null) {
        throw Exception('Échec de la génération du document Word');
      }

      // Convertir en List<int> modifiable
      return List<int>.from(generatedDoc);
    } catch (e) {
      print('Erreur génération Word : $e');
      rethrow;
    }
  }
}
