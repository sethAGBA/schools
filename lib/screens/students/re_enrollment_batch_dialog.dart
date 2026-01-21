import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/students/re_enrollment_data.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _DecisionType { admitted, underConditions, repeat, unknown }

class _ClassMappingRow {
  _ClassMappingRow({
    required this.sourceClass,
    required this.studentCount,
    required this.isSelected,
    required this.admittedTargetClassName,
    required this.repeatTargetClassName,
  });

  final Class sourceClass;
  final int studentCount;
  final bool isSelected;
  final String? admittedTargetClassName;
  final String? repeatTargetClassName;

  _ClassMappingRow copyWith({
    int? studentCount,
    bool? isSelected,
    String? admittedTargetClassName,
    String? repeatTargetClassName,
  }) {
    return _ClassMappingRow(
      sourceClass: sourceClass,
      studentCount: studentCount ?? this.studentCount,
      isSelected: isSelected ?? this.isSelected,
      admittedTargetClassName:
          admittedTargetClassName ?? this.admittedTargetClassName,
      repeatTargetClassName:
          repeatTargetClassName ?? this.repeatTargetClassName,
    );
  }
}

class ReEnrollmentBatchDialog extends StatefulWidget {
  static const Key targetYearFieldKey = Key('re_enroll_batch_target_year');
  static const Key reloadButtonKey = Key('re_enroll_batch_reload');
  static const Key applyButtonKey = Key('re_enroll_batch_apply');
  static const Key confirmApplyButtonKey = Key('re_enroll_batch_confirm_apply');

  const ReEnrollmentBatchDialog({this.data, Key? key}) : super(key: key);

  final ReEnrollmentData? data;

  @override
  State<ReEnrollmentBatchDialog> createState() =>
      _ReEnrollmentBatchDialogState();
}

class _ReEnrollmentBatchDialogState extends State<ReEnrollmentBatchDialog> {
  late final ReEnrollmentData _data;

  bool _isLoading = true;
  bool _isApplying = false;
  bool _useAutoIfManualEmpty = true;
  bool _unknownTreatAsRepeat = false;

  String _sourceYear = '2024-2025';
  late final TextEditingController _targetYearController;

  List<Class> _targetYearClasses = const [];
  List<_ClassMappingRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _data = widget.data ?? DatabaseReEnrollmentData();
    _targetYearController = TextEditingController(text: '2025-2026');
    _init();
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

  String _mappingPrefKeyForSourceClass(String className) =>
      're_enroll_mapping_target_$className';

  Key _admittedKeyForClass(String className) =>
      Key('re_enroll_batch_target_$className');
  Key _repeatKeyForClass(String className) =>
      Key('re_enroll_batch_repeat_$className');

  String _normalizeDecision(String value) => value.trim().toLowerCase();

  _DecisionType _decisionTypeFromText(String decision) {
    final d = _normalizeDecision(decision);
    if (d.isEmpty) return _DecisionType.unknown;
    if (d.contains('sous conditions')) return _DecisionType.underConditions;
    if (d.contains('redouble')) return _DecisionType.repeat;
    if (d.contains('admis')) return _DecisionType.admitted;
    return _DecisionType.unknown;
  }

  Future<String> _computeAutomaticDecision({
    required String className,
    required String academicYear,
    required double annualAverage,
    required Map<String, Map<String, double>> cache,
  }) async {
    cache.putIfAbsent('$className::$academicYear', () => <String, double>{});
    var thresholds = cache['$className::$academicYear']!;
    if (thresholds.isEmpty) {
      thresholds = await _data.getClassPassingThresholds(
        className,
        academicYear,
      );
      cache['$className::$academicYear'] = thresholds;
    }
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

  Future<void> _init() async {
    setState(() => _isLoading = true);
    final currentYear = await getCurrentAcademicYear();
    _sourceYear = currentYear;
    _targetYearController.text = _suggestNextYear(currentYear);
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final targetYear = _targetYearController.text.trim();

    final classes = await _data.getClasses();
    final sourceClasses =
        classes.where((c) => c.academicYear == _sourceYear).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final targetClasses =
        classes.where((c) => c.academicYear == targetYear).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    _targetYearClasses = targetClasses;
    final targetNames = targetClasses.map((c) => c.name).toSet();

    final prefs = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 1),
    );
    final List<_ClassMappingRow> rows = [];
    for (final cls in sourceClasses) {
      final count = (await _data.getStudentsByClassAndClassYear(
        cls.name,
        cls.academicYear,
      )).length;
      final defaultRepeat = targetNames.contains(cls.name) ? cls.name : null;
      final savedTarget = prefs.getString(
        _mappingPrefKeyForSourceClass(cls.name),
      );
      final admittedTarget =
          (savedTarget != null && targetNames.contains(savedTarget))
          ? savedTarget
          : null;
      rows.add(
        _ClassMappingRow(
          sourceClass: cls,
          studentCount: count,
          isSelected: count > 0,
          admittedTargetClassName: admittedTarget,
          repeatTargetClassName: defaultRepeat,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _isLoading = false;
    });
  }

  bool get _canApply {
    if (_isApplying) return false;
    final targetYear = _targetYearController.text.trim();
    if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(targetYear)) return false;
    if (targetYear == _sourceYear) return false;
    final selected = _rows.where((r) => r.isSelected).toList();
    if (selected.isEmpty) return false;
    final hasMissing = selected.any(
      (r) =>
          (r.admittedTargetClassName ?? '').trim().isEmpty ||
          (r.repeatTargetClassName ?? '').trim().isEmpty,
    );
    return !hasMissing;
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
              '$reportCardsCount bulletin(s) détecté(s) pour $academicYear.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Après la réinscription, les élèves changent d\'année/classe. Pour conserver un historique consultable, il est recommandé d\'archiver les bulletins/notes avant de continuer.',
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

    final targetYear = _targetYearController.text.trim();

    final reportCardsCount = await _data.countReportCardsForAcademicYear(
      _sourceYear,
    );
    if (reportCardsCount > 0) {
      final choice = await _promptArchiveBeforeApply(
        reportCardsCount: reportCardsCount,
        academicYear: _sourceYear,
      );
      if (choice == null) return;
      if (choice == true) {
        try {
          await _archiveYearWithProgress(_sourceYear);
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

    final selected = _rows.where((r) => r.isSelected).toList();
    final totalStudents = selected.fold<int>(0, (s, r) => s + r.studentCount);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la réinscription'),
        content: Text(
          'Vous allez modifier $totalStudents élève(s) sur ${selected.length} classe(s).\n\n'
          'Année source: $_sourceYear\n'
          'Année cible: $targetYear',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            key: ReEnrollmentBatchDialog.confirmApplyButtonKey,
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
      final thresholdsCache = <String, Map<String, double>>{};

      int movedCount = 0;
      int unknownCount = 0;
      for (final row in selected) {
        final admittedTarget = row.admittedTargetClassName!.trim();
        final repeatTarget = row.repeatTargetClassName!.trim();
        final students = await _data.getStudentsByClassAndClassYear(
          row.sourceClass.name,
          _sourceYear,
        );
        for (final s in students) {
          final preferred = await _data.getPreferredReportCardForStudent(
            studentId: s.id,
            className: row.sourceClass.name,
            academicYear: _sourceYear,
          );

          final manualDecision =
              (preferred?['decision'] as String?)?.trim() ?? '';
          final annualAverage = (preferred?['moyenne_annuelle'] as num?)
              ?.toDouble();

          String decisionText = manualDecision;
          if (decisionText.isEmpty && _useAutoIfManualEmpty) {
            if (annualAverage != null) {
              decisionText = await _computeAutomaticDecision(
                className: row.sourceClass.name,
                academicYear: _sourceYear,
                annualAverage: annualAverage,
                cache: thresholdsCache,
              );
            }
          }

          final type = _decisionTypeFromText(decisionText);
          String destination;
          if (type == _DecisionType.admitted) {
            destination = admittedTarget;
          } else if (type == _DecisionType.underConditions ||
              type == _DecisionType.repeat) {
            destination = repeatTarget;
          } else {
            unknownCount += 1;
            if (_unknownTreatAsRepeat) {
              destination = repeatTarget;
            } else {
              continue;
            }
          }

          final updated = _withEnrollment(
            s,
            year: targetYear,
            className: destination,
          );
          await _data.updateStudent(s.id, updated);
          movedCount += 1;
        }
      }

      try {
        await _data.logAudit(
          category: 're_enrollment',
          action: 'batch_apply',
          details:
              'batch=$batchId sourceYear=$_sourceYear targetYear=$targetYear classes=${selected.length} moved=$movedCount unknown=$unknownCount',
          success: true,
        );
      } catch (_) {}

      if (!mounted) return;
      showSnackBar(context, 'Réinscription appliquée ($movedCount élève(s)).');
      Navigator.of(context, rootNavigator: true).pop(true);
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
      title: 'Réinscription — Toute l\'école',
      showCloseIcon: !_isApplying,
      content: SizedBox(
        width: math.min(980, MediaQuery.of(context).size.width * 0.95),
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
                    'Années & options',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Année source',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(
                            _sourceYear,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: ReEnrollmentBatchDialog.targetYearFieldKey,
                          controller: _targetYearController,
                          enabled: !_isApplying,
                          decoration: const InputDecoration(
                            labelText: 'Année cible',
                            hintText: 'ex: 2025-2026',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        key: ReEnrollmentBatchDialog.reloadButtonKey,
                        onPressed: _isApplying ? null : _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Recharger'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Si décision vide → décision automatique',
                    ),
                    value: _useAutoIfManualEmpty,
                    onChanged: _isApplying
                        ? null
                        : (v) => setState(() => _useAutoIfManualEmpty = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Décision inconnue → redoublement'),
                    subtitle: const Text(
                      'Si désactivé, les élèves sans décision seront ignorés.',
                    ),
                    value: _unknownTreatAsRepeat,
                    onChanged: _isApplying
                        ? null
                        : (v) => setState(() => _unknownTreatAsRepeat = v),
                  ),
                  if (targetYear.isNotEmpty && _targetYearClasses.isEmpty)
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
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 440),
                child: ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final r = _rows[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.dividerColor.withOpacity(0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Checkbox(
                              value: r.isSelected,
                              onChanged: _isApplying
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _rows = _rows
                                            .map(
                                              (x) =>
                                                  x.sourceClass.name ==
                                                      r.sourceClass.name
                                                  ? x.copyWith(
                                                      isSelected: v ?? false,
                                                    )
                                                  : x,
                                            )
                                            .toList();
                                      });
                                    },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.sourceClass.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${r.studentCount} élève(s)',
                                    style: TextStyle(
                                      color: theme.textTheme.bodyMedium?.color
                                          ?.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                key: _admittedKeyForClass(r.sourceClass.name),
                                value:
                                    (r.admittedTargetClassName ?? '')
                                        .trim()
                                        .isEmpty
                                    ? null
                                    : r.admittedTargetClassName,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Destination (admis)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _targetYearClasses
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
                                        setState(() {
                                          _rows = _rows
                                              .map(
                                                (x) =>
                                                    x.sourceClass.name ==
                                                        r.sourceClass.name
                                                    ? x.copyWith(
                                                        admittedTargetClassName:
                                                            v,
                                                      )
                                                    : x,
                                              )
                                              .toList();
                                        });
                                        try {
                                          final prefs =
                                              await SharedPreferences.getInstance()
                                                  .timeout(
                                                    const Duration(seconds: 1),
                                                  );
                                          if (v != null &&
                                              v.trim().isNotEmpty) {
                                            await prefs.setString(
                                              _mappingPrefKeyForSourceClass(
                                                r.sourceClass.name,
                                              ),
                                              v.trim(),
                                            );
                                          }
                                        } catch (_) {}
                                      },
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                key: _repeatKeyForClass(r.sourceClass.name),
                                value:
                                    (r.repeatTargetClassName ?? '')
                                        .trim()
                                        .isEmpty
                                    ? null
                                    : r.repeatTargetClassName,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Redoublement',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _targetYearClasses
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
                                        setState(() {
                                          _rows = _rows
                                              .map(
                                                (x) =>
                                                    x.sourceClass.name ==
                                                        r.sourceClass.name
                                                    ? x.copyWith(
                                                        repeatTargetClassName:
                                                            v,
                                                      )
                                                    : x,
                                              )
                                              .toList();
                                        });
                                      },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$selectedCount classe(s) sélectionnée(s)',
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
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
                    ElevatedButton.icon(
                      key: ReEnrollmentBatchDialog.applyButtonKey,
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
