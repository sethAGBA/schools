import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/students/re_enrollment_data.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReEnrollmentDecisionType { admitted, underConditions, repeat, unknown }

class _ReEnrollmentRow {
  _ReEnrollmentRow({
    required this.student,
    required this.decisionText,
    required this.annualAverage,
    required this.decisionType,
    required this.destinationClassName,
    required this.isSelected,
    required this.isManualDecision,
  });

  final Student student;
  final String decisionText;
  final double? annualAverage;
  final ReEnrollmentDecisionType decisionType;
  final String? destinationClassName;
  final bool isSelected;
  final bool isManualDecision;

  _ReEnrollmentRow copyWith({
    String? decisionText,
    double? annualAverage,
    ReEnrollmentDecisionType? decisionType,
    String? destinationClassName,
    bool? isSelected,
    bool? isManualDecision,
  }) {
    return _ReEnrollmentRow(
      student: student,
      decisionText: decisionText ?? this.decisionText,
      annualAverage: annualAverage ?? this.annualAverage,
      decisionType: decisionType ?? this.decisionType,
      destinationClassName: destinationClassName ?? this.destinationClassName,
      isSelected: isSelected ?? this.isSelected,
      isManualDecision: isManualDecision ?? this.isManualDecision,
    );
  }
}

class ReEnrollmentDialog extends StatefulWidget {
  static const Key targetYearFieldKey = Key('re_enroll_target_year');
  static const Key loadClassesButtonKey = Key('re_enroll_load_classes');
  static const Key admittedTargetDropdownKey = Key('re_enroll_target_class');
  static const Key repeatTargetDropdownKey = Key('re_enroll_repeat_class');
  static const Key applyButtonKey = Key('re_enroll_apply');
  static const Key actionsMenuKey = Key('re_enroll_actions_menu');
  static const Key confirmApplyButtonKey = Key('re_enroll_confirm_apply');

  const ReEnrollmentDialog({
    required this.sourceClass,
    required this.students,
    this.data,
    Key? key,
  }) : super(key: key);

  final Class sourceClass;
  final List<Student> students;
  final ReEnrollmentData? data;

  @override
  State<ReEnrollmentDialog> createState() => _ReEnrollmentDialogState();
}

class _ReEnrollmentDialogState extends State<ReEnrollmentDialog> {
  late final ReEnrollmentData _data;

  bool _isLoading = true;
  bool _isApplying = false;
  bool _useAutoIfManualEmpty = true;
  String _searchQuery = '';

  late final TextEditingController _targetYearController;

  List<Class> _classesTargetYear = const [];
  String? _targetClassName;
  String? _repeatClassName;

  List<_ReEnrollmentRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _data = widget.data ?? DatabaseReEnrollmentData();
    _targetYearController = TextEditingController(
      text: _suggestNextYear(widget.sourceClass.academicYear),
    );
    _load();
  }

  @override
  void dispose() {
    _targetYearController.dispose();
    super.dispose();
  }

  String _suggestNextYear(String current) {
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

  String _normalizeDecision(String value) => value.trim().toLowerCase();

  String _mappingPrefKeyForSourceClass(String className) =>
      're_enroll_mapping_target_$className';

  ReEnrollmentDecisionType _decisionTypeFromText(String decision) {
    final d = _normalizeDecision(decision);
    if (d.isEmpty) return ReEnrollmentDecisionType.unknown;
    if (d.contains('sous conditions'))
      return ReEnrollmentDecisionType.underConditions;
    if (d.contains('redouble')) return ReEnrollmentDecisionType.repeat;
    if (d.contains('admis')) return ReEnrollmentDecisionType.admitted;
    return ReEnrollmentDecisionType.unknown;
  }

  Future<_ReEnrollmentRow> _buildRow(Student student) async {
    final preferred = await _data.getPreferredReportCardForStudent(
      studentId: student.id,
      className: widget.sourceClass.name,
      academicYear: widget.sourceClass.academicYear,
    );

    final String manualDecision =
        (preferred?['decision'] as String?)?.trim() ?? '';
    final double? annualAverage = (preferred?['moyenne_annuelle'] as num?)
        ?.toDouble();

    String decisionText = manualDecision;
    bool isManual = manualDecision.isNotEmpty;
    if (decisionText.isEmpty && _useAutoIfManualEmpty) {
      final avg = annualAverage;
      if (avg != null) {
        decisionText = await _computeAutomaticDecision(avg);
        isManual = false;
      }
    }

    final decisionType = _decisionTypeFromText(decisionText);

    final String? destination;
    if (decisionType == ReEnrollmentDecisionType.admitted) {
      destination = _targetClassName;
    } else if (decisionType == ReEnrollmentDecisionType.underConditions ||
        decisionType == ReEnrollmentDecisionType.repeat) {
      destination = _repeatClassName;
    } else {
      destination = null;
    }

    return _ReEnrollmentRow(
      student: student,
      decisionText: decisionText,
      annualAverage: annualAverage,
      decisionType: decisionType,
      destinationClassName: destination,
      isSelected: true,
      isManualDecision: isManual,
    );
  }

  Future<String> _computeAutomaticDecision(double annualAverage) async {
    final thresholds = await _data.getClassPassingThresholds(
      widget.sourceClass.name,
      widget.sourceClass.academicYear,
    );
    if (annualAverage >= (thresholds['felicitations'] ?? 16.0)) {
      return 'Admis en classe supérieure avec félicitations';
    }
    if (annualAverage >= (thresholds['encouragements'] ?? 14.0)) {
      return 'Admis en classe supérieure avec encouragements';
    }
    if (annualAverage >= (thresholds['admission'] ?? 12.0)) {
      return 'Admis en classe supérieure';
    }
    if (annualAverage >= (thresholds['avertissement'] ?? 10.0)) {
      return 'Admis en classe supérieure avec avertissement';
    }
    if (annualAverage >= (thresholds['conditions'] ?? 8.0)) {
      return 'Admis en classe supérieure sous conditions';
    }
    return 'Redouble la classe';
  }

  Future<void> _loadTargetYearClasses() async {
    final year = _targetYearController.text.trim();
    final classes = await _data.getClasses();
    final targetClasses = classes.where((c) => c.academicYear == year).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    setState(() => _classesTargetYear = targetClasses);

    final currentTarget = _targetClassName;
    final currentRepeat = _repeatClassName;
    final names = targetClasses.map((c) => c.name).toSet();
    final defaultRepeat = names.contains(widget.sourceClass.name)
        ? widget.sourceClass.name
        : null;

    // Load last-used mapping (ex: CE1 -> CE2) if it exists in the target year.
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 1),
      );
      final savedTarget = prefs.getString(
        _mappingPrefKeyForSourceClass(widget.sourceClass.name),
      );
      if (_targetClassName == null &&
          savedTarget != null &&
          savedTarget.trim().isNotEmpty &&
          names.contains(savedTarget.trim())) {
        _targetClassName = savedTarget.trim();
      }
    } catch (_) {}

    setState(() {
      if (currentTarget != null && !names.contains(currentTarget)) {
        _targetClassName = null;
      }
      if (currentRepeat != null && !names.contains(currentRepeat)) {
        _repeatClassName = defaultRepeat;
      }
      _repeatClassName ??= defaultRepeat;
    });
  }

  Future<void> _recomputeRowsDestinations() async {
    final updated = _rows.map((r) {
      String? destination;
      if (r.decisionType == ReEnrollmentDecisionType.admitted) {
        destination = _targetClassName;
      } else if (r.decisionType == ReEnrollmentDecisionType.underConditions ||
          r.decisionType == ReEnrollmentDecisionType.repeat) {
        destination = _repeatClassName;
      } else {
        destination = null;
      }
      return r.copyWith(destinationClassName: destination);
    }).toList();
    setState(() => _rows = updated);
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    await _loadTargetYearClasses();

    final List<_ReEnrollmentRow> rows = [];
    for (final s in widget.students) {
      rows.add(await _buildRow(s));
    }
    setState(() {
      _rows = rows;
      _isLoading = false;
    });
  }

  List<_ReEnrollmentRow> get _filteredRows {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final name = '${r.student.firstName} ${r.student.lastName}'.toLowerCase();
      return name.contains(q) || r.student.id.toLowerCase().contains(q);
    }).toList();
  }

  bool get _canApply {
    if (_isApplying) return false;
    final year = _targetYearController.text.trim();
    if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(year)) return false;
    if (year == widget.sourceClass.academicYear) return false;
    if (_targetClassName == null) return false;
    if (_repeatClassName == null) return false;
    final anySelected = _rows.any((r) => r.isSelected);
    if (!anySelected) return false;
    final hasMissingDestination = _rows
        .where((r) => r.isSelected)
        .any((r) => (r.destinationClassName ?? '').trim().isEmpty);
    return !hasMissingDestination;
  }

  Future<bool?> _promptArchiveBeforeApply({
    required int reportCardsCount,
    required String academicYear,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomDialog(
        title: 'Archivage recommandé',
        showCloseIcon: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
              ),
              child: Row(
                children: const [
                  Icon(Icons.archive_outlined, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Avant de déplacer les élèves',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Des bulletins existent pour ${widget.sourceClass.name} ($reportCardsCount enregistrement(s)).',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Après la réinscription, les élèves changent d\'année/classe. Pour conserver un historique consultable, il est recommandé d\'archiver les bulletins/notes de l\'année $academicYear avant de continuer.',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Voulez-vous archiver maintenant ?',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuer sans archiver'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.archive),
            label: const Text('Archiver et continuer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _archiveYearWithProgress(String year) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text('Archivage de l\'année $year en cours...')),
          ],
        ),
      ),
    );
    try {
      await _data.archiveReportCardsForYear(year);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Student _withEnrollment(
    Student s, {
    required String year,
    required String className,
  }) {
    return Student(
      id: s.id,
      firstName: s.firstName,
      lastName: s.lastName,
      dateOfBirth: s.dateOfBirth,
      placeOfBirth: s.placeOfBirth,
      address: s.address,
      gender: s.gender,
      contactNumber: s.contactNumber,
      email: s.email,
      emergencyContact: s.emergencyContact,
      guardianName: s.guardianName,
      guardianContact: s.guardianContact,
      className: className,
      academicYear: year,
      enrollmentDate: s.enrollmentDate,
      status: s.status,
      medicalInfo: s.medicalInfo,
      photoPath: s.photoPath,
      matricule: s.matricule,
    );
  }

  Future<void> _apply() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    if (!_canApply) return;

    final year = _targetYearController.text.trim();

    final reportCardsCount = await _data.countReportCardsForClassYear(
      className: widget.sourceClass.name,
      academicYear: widget.sourceClass.academicYear,
    );
    if (reportCardsCount > 0) {
      final choice = await _promptArchiveBeforeApply(
        reportCardsCount: reportCardsCount,
        academicYear: widget.sourceClass.academicYear,
      );
      if (choice == null) return;
      if (choice == true) {
        try {
          await _archiveYearWithProgress(widget.sourceClass.academicYear);
        } catch (e) {
          if (!mounted) return;
          showSnackBar(
            context,
            'Erreur lors de l\'archivage: $e',
            isError: true,
          );
          return;
        }
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la réinscription'),
        content: Text(
          'Vous allez modifier ${_rows.where((r) => r.isSelected).length} élève(s).\n\n'
          'Année cible: $year\n'
          'Classe cible (admis): $_targetClassName\n'
          'Classe redoublement: $_repeatClassName',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            key: ReEnrollmentDialog.confirmApplyButtonKey,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isApplying = true);
    try {
      final batchId = DateTime.now().millisecondsSinceEpoch.toString();
      for (final r in _rows.where((x) => x.isSelected)) {
        final dest = r.destinationClassName?.trim() ?? '';
        if (dest.isEmpty) continue;
        final updated = _withEnrollment(r.student, year: year, className: dest);
        await _data.updateStudent(r.student.id, updated);
      }
      try {
        await _data.logAudit(
          category: 're_enrollment',
          action: 'apply',
          details:
              'batch=$batchId source=${widget.sourceClass.name}@${widget.sourceClass.academicYear} targetYear=$year admittedTarget=$_targetClassName repeatTarget=$_repeatClassName count=${_rows.where((r) => r.isSelected).length}',
          success: true,
        );
      } catch (_) {}
      if (!mounted) return;
      showSnackBar(context, 'Réinscription appliquée avec succès.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showSnackBar(
        context,
        'Erreur lors de la réinscription: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetYear = _targetYearController.text.trim();
    final selectedCount = _rows.where((r) => r.isSelected).length;

    return CustomDialog(
      title:
          'Réinscription — ${widget.sourceClass.name} (${widget.sourceClass.academicYear})',
      showCloseIcon: !_isApplying,
      content: SizedBox(
        width: math.min(900, MediaQuery.of(context).size.width * 0.95),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Année cible & règles',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: ReEnrollmentDialog.targetYearFieldKey,
                          controller: _targetYearController,
                          enabled: !_isApplying,
                          decoration: const InputDecoration(
                            labelText: 'Année cible',
                            hintText: 'ex: 2025-2026',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) async {
                            await _loadTargetYearClasses();
                            await _recomputeRowsDestinations();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        key: ReEnrollmentDialog.loadClassesButtonKey,
                        onPressed: _isApplying
                            ? null
                            : () async {
                                await _loadTargetYearClasses();
                                await _recomputeRowsDestinations();
                              },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Charger classes'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ReEnrollmentDialog.admittedTargetDropdownKey,
                          value: _targetClassName,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Classe cible (admis)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _classesTargetYear
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.name,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                          onChanged: _isApplying
                              ? null
                              : (v) async {
                                  setState(() => _targetClassName = v);
                                  try {
                                    final prefs =
                                        await SharedPreferences.getInstance()
                                            .timeout(
                                              const Duration(seconds: 1),
                                            );
                                    if (v != null && v.trim().isNotEmpty) {
                                      await prefs.setString(
                                        _mappingPrefKeyForSourceClass(
                                          widget.sourceClass.name,
                                        ),
                                        v.trim(),
                                      );
                                    }
                                  } catch (_) {}
                                  await _recomputeRowsDestinations();
                                },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ReEnrollmentDialog.repeatTargetDropdownKey,
                          value: _repeatClassName,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Classe redoublement (défaut)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _classesTargetYear
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.name,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                          onChanged: _isApplying
                              ? null
                              : (v) async {
                                  setState(() => _repeatClassName = v);
                                  await _recomputeRowsDestinations();
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Si décision vide → décision automatique',
                    ),
                    subtitle: const Text(
                      'Utilise la moyenne annuelle si disponible (fin d\'année recommandée).',
                    ),
                    value: _useAutoIfManualEmpty,
                    onChanged: _isApplying
                        ? null
                        : (v) async {
                            setState(() => _useAutoIfManualEmpty = v);
                            await _load();
                          },
                  ),
                  if (_classesTargetYear.isEmpty && targetYear.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Aucune classe trouvée pour $targetYear. Créez d\'abord les classes de l\'année cible.',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              enabled: !_isApplying,
              decoration: const InputDecoration(
                hintText: 'Rechercher un élève (nom ou ID)...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.builder(
                  itemCount: _filteredRows.length,
                  itemBuilder: (context, index) {
                    final r = _filteredRows[index];
                    final decisionColor = switch (r.decisionType) {
                      ReEnrollmentDecisionType.admitted => const Color(
                        0xFF10B981,
                      ),
                      ReEnrollmentDecisionType.underConditions => const Color(
                        0xFFF59E0B,
                      ),
                      ReEnrollmentDecisionType.repeat => const Color(
                        0xFFE11D48,
                      ),
                      ReEnrollmentDecisionType.unknown => Colors.grey,
                    };

                    final subtitle = [
                      if (r.annualAverage != null)
                        'Moyenne annuelle: ${r.annualAverage!.toStringAsFixed(2)}',
                      if (r.decisionText.trim().isNotEmpty)
                        'Décision: ${r.decisionText}${r.isManualDecision ? '' : ' (auto)'}',
                      if ((r.destinationClassName ?? '').trim().isNotEmpty)
                        'Destination: ${r.destinationClassName}',
                      if ((r.destinationClassName ?? '').trim().isEmpty)
                        'Destination: à définir',
                    ].join(' • ');

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.dividerColor.withOpacity(0.2),
                        ),
                      ),
                      child: ListTile(
                        enabled: !_isApplying,
                        leading: Checkbox(
                          value: r.isSelected,
                          onChanged: _isApplying
                              ? null
                              : (v) {
                                  final updated = _rows.map((row) {
                                    if (row.student.id != r.student.id)
                                      return row;
                                    return row.copyWith(isSelected: v ?? false);
                                  }).toList();
                                  setState(() => _rows = updated);
                                },
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${r.student.firstName} ${r.student.lastName}'
                                    .trim(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: decisionColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: decisionColor.withOpacity(0.35),
                                ),
                              ),
                              child: Text(
                                switch (r.decisionType) {
                                  ReEnrollmentDecisionType.admitted => 'Admis',
                                  ReEnrollmentDecisionType.underConditions =>
                                    'Sous conditions',
                                  ReEnrollmentDecisionType.repeat => 'Redouble',
                                  ReEnrollmentDecisionType.unknown => 'Inconnu',
                                },
                                style: TextStyle(
                                  color: decisionColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            value: (r.destinationClassName ?? '').trim().isEmpty
                                ? null
                                : r.destinationClassName,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Destination',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _classesTargetYear
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.name,
                                    child: Text(c.name),
                                  ),
                                )
                                .toList(),
                            onChanged: _isApplying
                                ? null
                                : (v) {
                                    final updated = _rows.map((row) {
                                      if (row.student.id != r.student.id)
                                        return row;
                                      return row.copyWith(
                                        destinationClassName: v,
                                      );
                                    }).toList();
                                    setState(() => _rows = updated);
                                  },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$selectedCount sélectionné(s)',
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isApplying
                          ? null
                          : () {
                              final allSelected = _rows.every(
                                (r) => r.isSelected,
                              );
                              setState(() {
                                _rows = _rows
                                    .map(
                                      (r) =>
                                          r.copyWith(isSelected: !allSelected),
                                    )
                                    .toList();
                              });
                            },
                      child: const Text('Tout sélectionner'),
                    ),
                    PopupMenuButton<String>(
                      key: ReEnrollmentDialog.actionsMenuKey,
                      enabled: !_isApplying,
                      tooltip: 'Actions',
                      onSelected: (value) async {
                        final selected = _rows
                            .where((r) => r.isSelected)
                            .toList();
                        if (selected.isEmpty) return;
                        if (value == 'apply_rules') {
                          await _recomputeRowsDestinations();
                          return;
                        }
                        if (value == 'force_promote') {
                          final dest = _targetClassName;
                          if (dest == null || dest.trim().isEmpty) return;
                          setState(() {
                            _rows = _rows
                                .map(
                                  (r) => r.isSelected
                                      ? r.copyWith(destinationClassName: dest)
                                      : r,
                                )
                                .toList();
                          });
                          return;
                        }
                        if (value == 'force_repeat') {
                          final dest = _repeatClassName;
                          if (dest == null || dest.trim().isEmpty) return;
                          setState(() {
                            _rows = _rows
                                .map(
                                  (r) => r.isSelected
                                      ? r.copyWith(destinationClassName: dest)
                                      : r,
                                )
                                .toList();
                          });
                          return;
                        }
                        if (value == 'clear_destination') {
                          setState(() {
                            _rows = _rows
                                .map(
                                  (r) => r.isSelected
                                      ? r.copyWith(destinationClassName: null)
                                      : r,
                                )
                                .toList();
                          });
                          return;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'apply_rules',
                          child: Text('Appliquer les règles'),
                        ),
                        PopupMenuItem(
                          value: 'force_promote',
                          child: Text('Forcer passage'),
                        ),
                        PopupMenuItem(
                          value: 'force_repeat',
                          child: Text('Forcer redoublement'),
                        ),
                        PopupMenuItem(
                          value: 'clear_destination',
                          child: Text('Effacer destinations'),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune,
                              size: 18,
                              color: Theme.of(context).iconTheme.color,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Actions',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      key: ReEnrollmentDialog.applyButtonKey,
                      onPressed: _canApply ? _apply : null,
                      icon: _isApplying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_isApplying ? 'Application...' : 'Appliquer'),
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
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isApplying
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
