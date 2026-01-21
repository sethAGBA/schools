import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/discipline/discipline_data.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/utils/snackbar.dart';

class DisciplinePage extends StatefulWidget {
  const DisciplinePage({super.key, this.data, this.initialAcademicYear});

  final DisciplineData? data;
  final String? initialAcademicYear;

  static const Key tabAttendanceKey = Key('discipline_tab_attendance');
  static const Key tabSanctionsKey = Key('discipline_tab_sanctions');
  static const Key tabHistoryKey = Key('discipline_tab_history');

  static const Key addAttendanceKey = Key('discipline_add_attendance');
  static const Key addSanctionKey = Key('discipline_add_sanction');
  static const Key refreshKey = Key('discipline_refresh');

  @override
  State<DisciplinePage> createState() => _DisciplinePageState();
}

class _DisciplinePageState extends State<DisciplinePage> {
  late final DisciplineData _data;

  bool _loading = true;
  bool _printingDocument = false;
  String _academicYear = '';
  String? _selectedClassName;
  Student? _selectedStudent;

  List<String> _classNames = const [];
  List<Student> _students = const [];
  List<Map<String, dynamic>> _attendanceTotals = const [];
  List<Map<String, dynamic>> _attendanceEvents = const [];
  List<Map<String, dynamic>> _sanctionEvents = const [];

  @override
  void initState() {
    super.initState();
    _data = widget.data ?? DatabaseDisciplineData();
    _init();
  }

  Future<void> _init() async {
    final year = widget.initialAcademicYear ?? await getCurrentAcademicYear();
    if (!mounted) return;
    setState(() => _academicYear = year);
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final classNames = await _data.getClassNames(academicYear: _academicYear);
      final students = await _data.getStudents(academicYear: _academicYear);
      students.sort((a, b) => a.name.compareTo(b.name));

      final totals = await _data.getAttendanceTotals(
        academicYear: _academicYear,
        className: _selectedClassName,
        studentId: _selectedStudent?.id,
      );
      final attendance = await _data.getAttendanceEvents(
        academicYear: _academicYear,
        className: _selectedClassName,
        studentId: _selectedStudent?.id,
      );
      final sanctions = await _data.getSanctionEvents(
        academicYear: _academicYear,
        className: _selectedClassName,
        studentId: _selectedStudent?.id,
      );

      if (!mounted) return;
      setState(() {
        _classNames = classNames;
        _students = students;
        _attendanceTotals = totals;
        _attendanceEvents = attendance;
        _sanctionEvents = sanctions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  String _formatMinutes(int minutes) {
    final m = minutes < 0 ? 0 : minutes;
    final h = m ~/ 60;
    final mm = m % 60;
    return '${h}h${mm.toString().padLeft(2, '0')}';
  }

  Future<String?> _resolveRecordedBy() async {
    try {
      final user = await AuthService.instance.getCurrentUser();
      return user?.displayName ?? user?.username;
    } catch (_) {
      return null;
    }
  }

  Future<Student?> _pickStudentDialog() async {
    final queryCtrl = TextEditingController();
    var query = '';
    Student? selected;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) {
          final filtered = _students.where((s) {
            if (_selectedClassName != null &&
                _selectedClassName!.trim().isNotEmpty &&
                s.className != _selectedClassName) {
              return false;
            }
            final q = query.trim().toLowerCase();
            if (q.isEmpty) return true;
            return s.name.toLowerCase().contains(q) ||
                s.id.toLowerCase().contains(q) ||
                s.className.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            title: const Text('Sélectionner un élève'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: queryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rechercher',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setSB(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withOpacity(0.35),
                      ),
                    ),
                    child: filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('Aucun élève trouvé.'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final s = filtered[i];
                              final isSelected = selected?.id == s.id;
                              return ListTile(
                                title: Text(s.name),
                                subtitle: Text('${s.className} • ${s.id}'),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Color(0xFF10B981),
                                      )
                                    : const Icon(Icons.circle_outlined),
                                onTap: () => setSB(() => selected = s),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Choisir'),
              ),
            ],
          );
        },
      ),
    );

    queryCtrl.dispose();
    if (ok == true) return selected;
    return null;
  }

  String _documentTitleForEvent({required String kind, required String type}) {
    final t = type.trim().toLowerCase();
    if (kind == 'attendance') {
      if (t == 'retard') return 'Justificatif de retard';
      return 'Justificatif d\'absence';
    }
    if (t == 'exclusion') return 'Billet d\'exclusion';
    return 'Avis de sanction';
  }

  Future<void> _saveAndOpenDisciplineDocument({
    required String documentTitle,
    required String academicYear,
    required String studentName,
    required String studentId,
    required String className,
    required DateTime eventDate,
    String? eventType,
    int? minutes,
    bool? justified,
    String? description,
    String? documentNumber,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    if (_printingDocument) return;
    setState(() => _printingDocument = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Préparation du document...'),
        content: Row(
          children: const [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Veuillez patienter.')),
          ],
        ),
      ),
    );

    try {
      final responsable = await _resolveRecordedBy();
      debugPrint(
        '[Discipline] Document: generate title="${documentTitle.trim()}" student="${studentName.trim()}"',
      );
      final pdfBytes = await PdfService.generateDisciplineDocumentPdf(
        documentTitle: documentTitle,
        academicYear: academicYear,
        studentName: studentName,
        studentId: studentId,
        className: className,
        eventDate: eventDate,
        eventType: eventType,
        minutes: minutes,
        justified: justified,
        description: description,
        responsable: responsable,
        documentNumber: documentNumber,
      );

      final directoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisir le dossier de sauvegarde',
      );
      if (directoryPath == null) return;

      final safeStudentName = studentName.trim().isEmpty
          ? 'Eleve'
          : studentName.trim().replaceAll(' ', '_');
      final safeTitle = documentTitle.trim().isEmpty
          ? 'Document'
          : documentTitle.trim().replaceAll(' ', '_');
      final safeDate = DateFormat('yyyyMMdd').format(eventDate);
      final fileName =
          '${safeTitle}_${safeStudentName}_$safeDate${(documentNumber ?? '').trim().isEmpty ? '' : '_${documentNumber!.trim()}'}'
              .replaceAll('/', '_')
              .replaceAll('\\', '_')
              .replaceAll(':', '_');

      final file = File('$directoryPath/$fileName.pdf');
      debugPrint('[Discipline] Document: saving path=${file.path}');
      await file.writeAsBytes(pdfBytes, flush: true);
      if (!mounted) return;
      showSnackBar(context, 'Document enregistré dans $directoryPath');
      try {
        debugPrint('[Discipline] Document: opening path=${file.path}');
        await OpenFile.open(file.path);
      } catch (_) {}
    } catch (e) {
      debugPrint('[Discipline] Document: error=$e');
      if (mounted) {
        showSnackBar(
          context,
          'Impossible d\'enregistrer le document: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        setState(() => _printingDocument = false);
      }
    }
  }

  Future<void> _openAttendanceForm({String initialType = 'absence'}) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    var type = initialType;
    final dateCtrl = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final minutesCtrl = TextEditingController(
      text: type == 'retard' ? '10' : '0',
    );
    bool justified = false;
    final reasonCtrl = TextEditingController();
    Student? student = _selectedStudent;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) {
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                  ),
                  child: const Icon(Icons.event_note, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Absence / Retard')),
              ],
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(student?.name ?? 'Aucun élève sélectionné'),
                      subtitle: Text(
                        student == null
                            ? 'Choisissez un élève'
                            : '${student!.className} • ${student!.id}',
                      ),
                      trailing: OutlinedButton.icon(
                        onPressed: () async {
                          final s = await _pickStudentDialog();
                          if (s == null) return;
                          setSB(() => student = s);
                        },
                        icon: const Icon(Icons.person_search),
                        label: const Text('Élève'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'absence',
                          child: Text('Absence'),
                        ),
                        DropdownMenuItem(
                          value: 'retard',
                          child: Text('Retard'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setSB(() {
                          type = v;
                          if (type == 'retard' &&
                              (int.tryParse(minutesCtrl.text.trim()) ?? 0) ==
                                  0) {
                            minutesCtrl.text = '10';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Date (YYYY-MM-DD)',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: minutesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: type == 'retard'
                            ? 'Minutes de retard'
                            : 'Durée (minutes)',
                        prefixIcon: const Icon(Icons.timer_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Justifiée'),
                      value: justified,
                      onChanged: (v) => setSB(() => justified = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Motif / Note',
                        prefixIcon: Icon(Icons.notes_outlined),
                        border: OutlineInputBorder(),
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
              ElevatedButton.icon(
                key: DisciplinePage.addAttendanceKey,
                onPressed: () => Navigator.pop(ctx, 'save'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Enregistrer'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'save_print'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Document'),
              ),
            ],
          );
        },
      ),
    );

    if (action == 'save' || action == 'save_print') {
      if (student == null) {
        showSnackBar(context, 'Veuillez sélectionner un élève.', isError: true);
        return;
      }
      final dt = DateTime.tryParse(dateCtrl.text.trim());
      if (dt == null) {
        showSnackBar(context, 'Date invalide.', isError: true);
        return;
      }
      final minutes = int.tryParse(minutesCtrl.text.trim()) ?? 0;
      if (type == 'retard' && minutes <= 0) {
        showSnackBar(context, 'Minutes de retard invalides.', isError: true);
        return;
      }
      final by = await _resolveRecordedBy();
      final id = await _data.addAttendanceEvent(
        studentId: student!.id,
        academicYear: _academicYear,
        className: student!.className,
        date: dt,
        type: type,
        minutes: minutes,
        justified: justified,
        reason: reasonCtrl.text.trim(),
        recordedBy: by,
      );
      await _load();
      showSnackBar(context, 'Enregistré.');

      if (action == 'save_print') {
        final title = _documentTitleForEvent(kind: 'attendance', type: type);
        final num = 'DIS-${DateTime.now().year}-$id';
        await _saveAndOpenDisciplineDocument(
          documentTitle: title,
          academicYear: _academicYear,
          studentName: student!.name,
          studentId: student!.id,
          className: student!.className,
          eventDate: dt,
          eventType: type,
          minutes: minutes,
          justified: justified,
          description: reasonCtrl.text.trim(),
          documentNumber: num,
        );
      }
    }

    dateCtrl.dispose();
    minutesCtrl.dispose();
    reasonCtrl.dispose();
  }

  Future<void> _openSanctionForm() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    var type = 'avertissement';
    final dateCtrl = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final descCtrl = TextEditingController();
    Student? student = _selectedStudent;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) {
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                  ),
                  child: const Icon(Icons.gavel, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Sanction / Avertissement')),
              ],
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(student?.name ?? 'Aucun élève sélectionné'),
                      subtitle: Text(
                        student == null
                            ? 'Choisissez un élève'
                            : '${student!.className} • ${student!.id}',
                      ),
                      trailing: OutlinedButton.icon(
                        onPressed: () async {
                          final s = await _pickStudentDialog();
                          if (s == null) return;
                          setSB(() => student = s);
                        },
                        icon: const Icon(Icons.person_search),
                        label: const Text('Élève'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'avertissement',
                          child: Text('Avertissement'),
                        ),
                        DropdownMenuItem(value: 'blame', child: Text('Blâme')),
                        DropdownMenuItem(
                          value: 'exclusion',
                          child: Text('Exclusion'),
                        ),
                        DropdownMenuItem(value: 'autre', child: Text('Autre')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setSB(() => type = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Date (YYYY-MM-DD)',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(Icons.notes_outlined),
                        border: OutlineInputBorder(),
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
              ElevatedButton.icon(
                key: DisciplinePage.addSanctionKey,
                onPressed: () => Navigator.pop(ctx, 'save'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Enregistrer'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'save_print'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Document'),
              ),
            ],
          );
        },
      ),
    );

    if (action == 'save' || action == 'save_print') {
      if (student == null) {
        showSnackBar(context, 'Veuillez sélectionner un élève.', isError: true);
        return;
      }
      final dt = DateTime.tryParse(dateCtrl.text.trim());
      if (dt == null) {
        showSnackBar(context, 'Date invalide.', isError: true);
        return;
      }
      if (descCtrl.text.trim().isEmpty) {
        showSnackBar(
          context,
          'Veuillez saisir une description.',
          isError: true,
        );
        return;
      }
      final by = await _resolveRecordedBy();
      final id = await _data.addSanctionEvent(
        studentId: student!.id,
        academicYear: _academicYear,
        className: student!.className,
        date: dt,
        type: type,
        description: descCtrl.text.trim(),
        recordedBy: by,
      );
      await _load();
      showSnackBar(context, 'Enregistré.');

      if (action == 'save_print') {
        final title = _documentTitleForEvent(kind: 'sanction', type: type);
        final num = 'DIS-${DateTime.now().year}-$id';
        await _saveAndOpenDisciplineDocument(
          documentTitle: title,
          academicYear: _academicYear,
          studentName: student!.name,
          studentId: student!.id,
          className: student!.className,
          eventDate: dt,
          eventType: type,
          description: descCtrl.text.trim(),
          documentNumber: num,
        );
      }
    }

    dateCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _confirmDelete({
    required String title,
    required String content,
    required Future<void> Function() onDelete,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await onDelete();
    await _load();
    if (mounted) showSnackBar(context, 'Supprimé.');
  }

  Widget _buildHeader(BuildContext context, {required bool isDesktop}) {
    final theme = Theme.of(context);
    final absences = _attendanceEvents
        .where((e) => e['type'] == 'absence')
        .length;
    final retards = _attendanceEvents
        .where((e) => e['type'] == 'retard')
        .length;
    final sanctions = _sanctionEvents.length;

    Widget iconBox(IconData icon) => Container(
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
      child: Icon(icon, color: theme.iconTheme.color, size: 20),
    );

    final headline = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
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
                  Icons.rule_folder_outlined,
                  color: Colors.white,
                  size: isDesktop ? 32 : 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suivi de la discipline',
                      style: TextStyle(
                        fontSize: isDesktop ? 32 : 24,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gérez les absences, retards, sanctions et avertissements.',
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
              ),
            ],
          ),
        ),
        iconBox(Icons.notifications_outlined),
      ],
    );

    final kpis = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!_loading) Chip(label: Text('Absences: $absences')),
        if (!_loading) Chip(label: Text('Retards: $retards')),
        if (!_loading) Chip(label: Text('Sanctions: $sanctions')),
      ],
    );

    final filters = Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedClassName,
            decoration: InputDecoration(
              labelText: 'Classe',
              border: const OutlineInputBorder(),
              hintStyle: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Toutes'),
              ),
              ..._classNames.map(
                (c) => DropdownMenuItem(value: c, child: Text(c)),
              ),
            ],
            onChanged: (v) async {
              setState(() {
                _selectedClassName = v;
                if (_selectedStudent != null &&
                    v != null &&
                    v.trim().isNotEmpty &&
                    _selectedStudent!.className != v) {
                  _selectedStudent = null;
                }
              });
              await _load();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () async {
              final s = await _pickStudentDialog();
              if (s == null) return;
              setState(() => _selectedStudent = s);
              await _load();
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Élève',
                border: const OutlineInputBorder(),
                hintStyle: TextStyle(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedStudent?.name ?? 'Tous',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_selectedStudent != null)
                    IconButton(
                      tooltip: 'Retirer',
                      onPressed: () async {
                        setState(() => _selectedStudent = null);
                        await _load();
                      },
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            key: DisciplinePage.refreshKey,
            tooltip: 'Rafraîchir',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
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
              if (compact) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            Icons.rule_folder_outlined,
                            color: Colors.white,
                            size: isDesktop ? 32 : 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Suivi de la discipline',
                                style: TextStyle(
                                  fontSize: isDesktop ? 32 : 24,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.bodyLarge?.color,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Gérez les absences, retards, sanctions et avertissements.',
                                style: TextStyle(
                                  fontSize: isDesktop ? 16 : 14,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.7),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        iconBox(Icons.notifications_outlined),
                      ],
                    ),
                  ],
                ),
              ] else ...[
                headline,
              ],
              const SizedBox(height: 12),
              kpis,
              const SizedBox(height: 12),
              filters,
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttendanceTab(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Absences & retards',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openAttendanceForm(initialType: 'absence'),
                icon: const Icon(Icons.person_off_outlined),
                label: const Text('Ajouter absence'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _openAttendanceForm(initialType: 'retard'),
                icon: const Icon(Icons.alarm_outlined),
                label: const Text('Ajouter retard'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cumul par élève',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                _attendanceTotals.isEmpty
                    ? Text(
                        'Aucun cumul (aucun enregistrement).',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.7,
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 140,
                        child: ListView.separated(
                          itemCount: _attendanceTotals.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final t = _attendanceTotals[i];
                            final studentName =
                                (t['studentName'] as String?) ?? '';
                            final cls = (t['className'] as String?) ?? '';
                            final absMin =
                                (t['absenceMinutes'] as num?)?.toInt() ?? 0;
                            final retMin =
                                (t['retardMinutes'] as num?)?.toInt() ?? 0;
                            final absCount =
                                (t['absenceCount'] as num?)?.toInt() ?? 0;
                            final retCount =
                                (t['retardCount'] as num?)?.toInt() ?? 0;

                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                studentName.isEmpty ? 'Élève' : studentName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${cls.trim().isEmpty ? '-' : cls.trim()} • '
                                'Absences: ${_formatMinutes(absMin)} ($absCount) • '
                                'Retards: ${_formatMinutes(retMin)} ($retCount)',
                              ),
                            );
                          },
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _attendanceEvents.isEmpty
                ? Center(
                    child: Text(
                      'Aucun enregistrement.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.7,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _attendanceEvents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final e = _attendanceEvents[i];
                      final id = (e['id'] as num?)?.toInt();
                      final type = (e['type'] as String?) ?? 'absence';
                      final date = DateTime.tryParse(
                        (e['date'] as String?) ?? '',
                      );
                      final minutes = (e['minutes'] as num?)?.toInt() ?? 0;
                      final justified = (e['justified'] as num?)?.toInt() == 1;
                      final studentName = (e['studentName'] as String?) ?? '';
                      final cls = (e['className'] as String?) ?? '';
                      final reason = (e['reason'] as String?) ?? '';

                      final isRetard = type == 'retard';
                      final title = isRetard ? 'Retard' : 'Absence';
                      final subtitleParts = <String>[
                        if (studentName.trim().isNotEmpty) studentName.trim(),
                        if (cls.trim().isNotEmpty) cls.trim(),
                        if (date != null) DateFormat('dd/MM/yyyy').format(date),
                        if (isRetard && minutes > 0) '$minutes min',
                        if (!isRetard && minutes > 0) '$minutes min',
                        if (justified) 'Justifiée',
                        if (reason.trim().isNotEmpty) reason.trim(),
                      ];

                      return Container(
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.35),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            isRetard ? Icons.alarm : Icons.person_off_outlined,
                            color: isRetard ? Colors.orange : Colors.redAccent,
                          ),
                          title: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(subtitleParts.join(' • ')),
                          trailing: IconButton(
                            tooltip: 'Supprimer',
                            onPressed: id == null
                                ? null
                                : () => _confirmDelete(
                                    title: 'Supprimer ?',
                                    content: 'Supprimer cet enregistrement ?',
                                    onDelete: () =>
                                        _data.deleteAttendanceEvent(id: id),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSanctionsTab(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sanctions & avertissements',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _openSanctionForm,
                icon: const Icon(Icons.gavel),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _sanctionEvents.isEmpty
                ? Center(
                    child: Text(
                      'Aucune sanction.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.7,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _sanctionEvents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final e = _sanctionEvents[i];
                      final id = (e['id'] as num?)?.toInt();
                      final type = (e['type'] as String?) ?? '';
                      final date = DateTime.tryParse(
                        (e['date'] as String?) ?? '',
                      );
                      final studentName = (e['studentName'] as String?) ?? '';
                      final cls = (e['className'] as String?) ?? '';
                      final desc = (e['description'] as String?) ?? '';

                      final subtitleParts = <String>[
                        if (studentName.trim().isNotEmpty) studentName.trim(),
                        if (cls.trim().isNotEmpty) cls.trim(),
                        if (date != null) DateFormat('dd/MM/yyyy').format(date),
                        if (desc.trim().isNotEmpty) desc.trim(),
                      ];

                      return Container(
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.35),
                          ),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.gavel),
                          title: Text(
                            type.isEmpty ? 'Sanction' : type,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(subtitleParts.join(' • ')),
                          trailing: IconButton(
                            tooltip: 'Supprimer',
                            onPressed: id == null
                                ? null
                                : () => _confirmDelete(
                                    title: 'Supprimer ?',
                                    content: 'Supprimer cette sanction ?',
                                    onDelete: () =>
                                        _data.deleteSanctionEvent(id: id),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(BuildContext context) {
    final theme = Theme.of(context);
    final all =
        <Map<String, dynamic>>[
          ..._attendanceEvents.map((e) => {...e, '_kind': 'attendance'}),
          ..._sanctionEvents.map((e) => {...e, '_kind': 'sanction'}),
        ]..sort((a, b) {
          final ad =
              DateTime.tryParse((a['date'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd =
              DateTime.tryParse((b['date'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        });

    return Padding(
      padding: const EdgeInsets.all(16),
      child: all.isEmpty
          ? Center(
              child: Text(
                'Aucun historique.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ),
            )
          : ListView.separated(
              itemCount: all.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = all[i];
                final kind = (e['_kind'] as String?) ?? '';
                final isSanction = kind == 'sanction';
                final type = (e['type'] as String?) ?? '';
                final studentName = (e['studentName'] as String?) ?? '';
                final cls = (e['className'] as String?) ?? '';
                final date = DateTime.tryParse((e['date'] as String?) ?? '');
                final desc = isSanction
                    ? (e['description'] as String?) ?? ''
                    : (e['reason'] as String?) ?? '';
                final minutes = (e['minutes'] as num?)?.toInt() ?? 0;

                final subtitleParts = <String>[
                  if (studentName.trim().isNotEmpty) studentName.trim(),
                  if (cls.trim().isNotEmpty) cls.trim(),
                  if (date != null) DateFormat('dd/MM/yyyy').format(date),
                  if (!isSanction && minutes > 0) '$minutes min',
                  if (desc.trim().isNotEmpty) desc.trim(),
                ];

                return Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.35),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      isSanction ? Icons.gavel : Icons.event_note,
                      color: isSanction ? Colors.deepOrange : null,
                    ),
                    title: Text(
                      type.isEmpty
                          ? (isSanction ? 'Sanction' : 'Événement')
                          : type,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(subtitleParts.join(' • ')),
                    trailing: IconButton(
                      tooltip: 'Document',
                      onPressed: () async {
                        final kind = isSanction ? 'sanction' : 'attendance';
                        final docTitle = _documentTitleForEvent(
                          kind: kind,
                          type: type,
                        );
                        final studentName =
                            (e['studentName'] as String?) ?? 'Élève';
                        final studentId = (e['studentId'] as String?) ?? '';
                        final className = (e['className'] as String?) ?? '';
                        final dt = DateTime.tryParse(
                          (e['date'] as String?) ?? '',
                        );
                        if (dt == null) {
                          showSnackBar(
                            context,
                            'Date invalide.',
                            isError: true,
                          );
                          return;
                        }
                        final id = (e['id'] as num?)?.toInt() ?? 0;
                        final docNumber = id <= 0
                            ? null
                            : 'DIS-${DateTime.now().year}-$id';
                        final justifiedValue = e.containsKey('justified')
                            ? ((e['justified'] as num?)?.toInt() == 1)
                            : null;
                        await _saveAndOpenDisciplineDocument(
                          documentTitle: docTitle,
                          academicYear: _academicYear,
                          studentName: studentName,
                          studentId: studentId,
                          className: className,
                          eventDate: dt,
                          eventType: type,
                          minutes: (e['minutes'] as num?)?.toInt(),
                          justified: justifiedValue,
                          description: isSanction
                              ? (e['description'] as String?) ?? ''
                              : (e['reason'] as String?) ?? '',
                          documentNumber: docNumber,
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: isDarkMode ? Colors.black : Colors.grey[100],
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkMode
                  ? const [
                      Color(0xFF0F0F23),
                      Color(0xFF1A1A2E),
                      Color(0xFF16213E),
                    ]
                  : const [
                      Color(0xFFF8FAFC),
                      Color(0xFFE2E8F0),
                      Color(0xFFF1F5F9),
                    ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                _buildHeader(context, isDesktop: isDesktop),
                const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
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
                                Container(
                                  margin: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: theme.cardColor,
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.shadowColor.withOpacity(
                                          0.1,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: TabBar(
                                    indicator: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF6366F1),
                                          Color(0xFF8B5CF6),
                                        ],
                                      ),
                                    ),
                                    indicatorSize: TabBarIndicatorSize.tab,
                                    dividerColor: Colors.transparent,
                                    labelColor: Colors.white,
                                    unselectedLabelColor:
                                        theme.textTheme.bodyMedium?.color,
                                    tabs: const [
                                      Tab(
                                        key: DisciplinePage.tabAttendanceKey,
                                        text: 'Assiduité',
                                        icon: Icon(Icons.event_note),
                                      ),
                                      Tab(
                                        key: DisciplinePage.tabSanctionsKey,
                                        text: 'Sanctions',
                                        icon: Icon(Icons.gavel),
                                      ),
                                      Tab(
                                        key: DisciplinePage.tabHistoryKey,
                                        text: 'Historique',
                                        icon: Icon(Icons.history),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      _buildAttendanceTab(context),
                                      _buildSanctionsTab(context),
                                      _buildHistoryTab(context),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                if (!isDesktop) const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
