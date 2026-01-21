import 'package:flutter/material.dart';
import 'package:school_manager/models/grade.dart';
import 'dart:typed_data';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/student_document.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/report_card_custom_export_service.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:school_manager/models/class.dart';
// import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:school_manager/utils/snackbar.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:csv/csv.dart';
import 'package:printing/printing.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/services/safe_mode_service.dart';

class StudentProfilePage extends StatefulWidget {
  final Student student;

  const StudentProfilePage({Key? key, required this.student}) : super(key: key);

  @override
  _StudentProfilePageState createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _dbService = DatabaseService();
  late Student _student;
  List<Payment> _payments = [];
  List<Map<String, dynamic>> _reportCards = [];
  List<StudentDocument> _documents = [];
  List<Map<String, dynamic>> _attendanceEvents = [];
  List<Map<String, dynamic>> _sanctionEvents = [];
  List<Map<String, dynamic>> _auditLogs = [];
  int? _disciplineDays; // null = tout
  bool _isLoading = true;

  String _fmtArchivedDate(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.trim().isEmpty) return '';
    try {
      DateTime? d;
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
        d = DateTime.tryParse(s);
      } else if (RegExp(r'^\d{2}/\d{2}/\d{4}').hasMatch(s)) {
        final parts = s.split('/');
        d = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
      if (d != null) return DateFormat('dd/MM/yyyy').format(d);
      return s;
    } catch (_) {
      return s;
    }
  }

  String _fmtAuditTimestamp(dynamic v) {
    if (v == null) return '';
    final s = v.toString().trim();
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  String _auditCategoryLabel(String raw) {
    final v = raw.trim().toLowerCase();
    const map = {
      'student': 'Élève',
      'payment': 'Paiement',
      'report_card': 'Bulletin',
      'discipline': 'Discipline',
      'library': 'Bibliothèque',
      'auth': 'Authentification',
      'settings': 'Paramètres',
      'user': 'Utilisateur',
      'staff': 'Personnel',
      'inventory': 'Inventaire',
      'expense': 'Dépense',
      'signature': 'Signature',
    };
    return map[v] ?? raw;
  }

  String _auditActionLabel(String raw) {
    final v = raw.trim().toLowerCase();
    const map = {
      // Student
      'insert_student': 'Création de la fiche élève',
      'update_student': 'Modification de la fiche élève',
      'soft_delete_student': 'Mise à la corbeille',
      'restore_student': 'Restauration depuis la corbeille',
      'delete_student_deep': 'Suppression définitive',
      'update_student_documents': 'Mise à jour des documents',
      'export_student_id_card_pdf': 'Export carte élève (PDF)',
      // Payments
      'add_payment': 'Enregistrement d’un paiement',
      'update_payment': 'Modification d’un paiement',
      'delete_payment': 'Suppression d’un paiement',
      'cancel_payment': 'Annulation d’un paiement',
      'cancel_payment_reason': 'Modification du motif d’annulation',
      'export_payment_receipt_pdf': 'Export reçu (PDF)',
      // Report cards
      'export_report_card_pdf': 'Export bulletin (PDF)',
      // Discipline
      'add_attendance': 'Ajout assiduité',
      'update_attendance': 'Modification assiduité',
      'delete_attendance': 'Suppression assiduité',
      'add_sanction': 'Ajout sanction',
      'update_sanction': 'Modification sanction',
      'delete_sanction': 'Suppression sanction',
      // Import/export (if present)
      'import_students': 'Import élèves',
      'export_students_csv': 'Export élèves (CSV)',
      'export_students_excel': 'Export élèves (Excel)',
    };
    return map[v] ?? raw;
  }

  @override
  void initState() {
    super.initState();
    _student = widget.student;
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final refreshed = await _dbService.getStudentById(widget.student.id);
    final payments = await _dbService.getPaymentsForStudent(widget.student.id);
    final reportCards = await _dbService.getArchivedReportCardsForStudent(
      widget.student.id,
    );
    final attendance = await _dbService.getAttendanceEventsForStudent(
      widget.student.id,
    );
    final sanctions = await _dbService.getSanctionEventsForStudent(
      widget.student.id,
    );
    final audit = await _dbService.getAuditLogsForStudent(
      studentId: widget.student.id,
    );
    setState(() {
      _student = refreshed ?? widget.student;
      _documents = List<StudentDocument>.from(_student.documents);
      _payments = payments;
      _reportCards = reportCards;
      _attendanceEvents = attendance;
      _sanctionEvents = sanctions;
      _auditLogs = audit;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme, // Ensure the dialog inherits the current theme
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.1),
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Custom AppBar-like header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Profil de ${_student.name}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        PopupMenuButton<String>(
                          tooltip: 'Actions élève',
                          onSelected: (value) async {
                            switch (value) {
                              case 'trash':
                                await _moveStudentToTrash();
                                break;
                              case 'restore':
                                await _restoreStudent();
                                break;
                              case 'refresh':
                                await _loadData();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            if (!_student.isDeleted)
                              const PopupMenuItem(
                                value: 'trash',
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Mettre à la corbeille'),
                                ),
                              ),
                            if (_student.isDeleted)
                              const PopupMenuItem(
                                value: 'restore',
                                child: ListTile(
                                  leading: Icon(Icons.restore),
                                  title: Text('Restaurer'),
                                ),
                              ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'refresh',
                              child: ListTile(
                                leading: Icon(Icons.refresh),
                                title: Text('Actualiser'),
                              ),
                            ),
                          ],
                          icon: Icon(
                            Icons.more_vert,
                            color: theme.iconTheme.color,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: theme.iconTheme.color),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // TabBar
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelPadding: EdgeInsets.zero,
                    labelColor: theme.textTheme.bodyMedium?.color,
                    unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                    indicatorColor: Colors.transparent,
                    indicator: const BoxDecoration(),
                    tabs: [
                      _buildHeaderTab(
                        theme,
                        index: 0,
                        icon: Icons.person,
                        label: 'Infos',
                      ),
                      _buildHeaderTab(
                        theme,
                        index: 1,
                        icon: Icons.payment,
                        label: 'Paiements',
                      ),
                      _buildHeaderTab(
                        theme,
                        index: 2,
                        icon: Icons.article,
                        label: 'Bulletins',
                      ),
                      _buildHeaderTab(
                        theme,
                        index: 3,
                        icon: Icons.attach_file,
                        label: 'Documents',
                      ),
                      _buildHeaderTab(
                        theme,
                        index: 4,
                        icon: Icons.rule_folder_outlined,
                        label: 'Discipline',
                      ),
                      _buildHeaderTab(
                        theme,
                        index: 5,
                        icon: Icons.history,
                        label: 'Journal',
                      ),
                    ],
                  ),
                ),
              ),
              // TabBarView
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildInfoTab(),
                          _buildPaymentsTab(),
                          _buildReportCardsTab(),
                          _buildDocumentsTab(),
                          _buildDisciplineTab(),
                          _buildJournalTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.withOpacity(0.02),
            Colors.blue.withOpacity(0.05),
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enhanced Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.1),
                    theme.colorScheme.secondary.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  // Enhanced Avatar with Status
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.secondary,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: theme.scaffoldBackgroundColor,
                          child: Text(
                            widget.student.name.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.student.name,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'ID: ${widget.student.id}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.student.matricule != null &&
                          widget.student.matricule!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: theme.colorScheme.secondary.withOpacity(
                                0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            'Matricule: ${widget.student.matricule}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Né(e) le ${_formatDate(widget.student.dateOfBirth)} • ${_calculateAge(widget.student.dateOfBirth)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(
                        0.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatusChip(
                        '${widget.student.className}',
                        Icons.class_,
                        theme,
                      ),
                      const SizedBox(width: 12),
                      _buildStatusChip(
                        widget.student.gender == 'M' ? 'Garçon' : 'Fille',
                        widget.student.gender == 'M'
                            ? Icons.male
                            : Icons.female,
                        theme,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _exportStudentIdCardPdf,
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Carte élève (PDF)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualiser'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Enhanced Information Sections
            _buildInfoSection('Informations Personnelles', [
              _buildInfoCard(
                'Numéro de Matricule',
                widget.student.matricule ?? 'Non attribué',
                Icons.badge,
                theme,
              ),
              _buildInfoCard(
                'Date de Naissance',
                _formatDate(widget.student.dateOfBirth),
                Icons.cake,
                theme,
              ),
              _buildInfoCard(
                'Lieu de Naissance',
                widget.student.placeOfBirth ?? 'Non renseigné',
                Icons.location_city,
                theme,
              ),
              _buildInfoCard(
                'Âge',
                _calculateAge(widget.student.dateOfBirth),
                Icons.calendar_today,
                theme,
              ),
              _buildInfoCard(
                'Genre',
                widget.student.gender == 'M' ? 'Garçon' : 'Fille',
                widget.student.gender == 'M' ? Icons.male : Icons.female,
                theme,
              ),
              _buildInfoCard(
                'Statut',
                widget.student.status,
                Icons.person_pin,
                theme,
              ),
              _buildInfoCard(
                'Adresse',
                widget.student.address,
                Icons.location_on,
                theme,
              ),
            ], theme),

            const SizedBox(height: 24),

            _buildInfoSection('Informations de Contact', [
              _buildInfoCard(
                'Téléphone',
                widget.student.contactNumber,
                Icons.phone,
                theme,
              ),
              _buildInfoCard('Email', widget.student.email, Icons.email, theme),
              _buildInfoCard(
                'Contact d\'urgence',
                widget.student.emergencyContact,
                Icons.emergency,
                theme,
              ),
            ], theme),

            const SizedBox(height: 24),

            _buildInfoSection('Informations Familiales', [
              _buildInfoCard(
                'Nom du Tuteur',
                widget.student.guardianName,
                Icons.person,
                theme,
              ),
              _buildInfoCard(
                'Contact du Tuteur',
                widget.student.guardianContact,
                Icons.phone,
                theme,
              ),
            ], theme),

            const SizedBox(height: 24),

            _buildInfoSection('Informations Académiques', [
              _buildInfoCard(
                'Classe Actuelle',
                widget.student.className,
                Icons.school,
                theme,
              ),
              _buildInfoCard(
                'Année d\'inscription',
                _getEnrollmentYear(),
                Icons.calendar_month,
                theme,
              ),
              if (widget.student.medicalInfo != null &&
                  widget.student.medicalInfo!.isNotEmpty)
                _buildInfoCard(
                  'Informations Médicales',
                  widget.student.medicalInfo!,
                  Icons.medical_services,
                  theme,
                ),
            ], theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderTab(
    ThemeData theme, {
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _tabController.index == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              )
            : null,
        color: selected ? null : theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : theme.dividerColor.withOpacity(0.6),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: selected ? Colors.white : theme.iconTheme.color,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: selected
                  ? Colors.white
                  : theme.textTheme.bodyMedium?.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    if (dateString.isEmpty) return 'Non renseigné';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateString; // Retourner la chaîne originale si le parsing échoue
    }
  }

  String _calculateAge(String dateString) {
    if (dateString.isEmpty) return 'Non renseigné';
    try {
      final birthDate = DateTime.parse(dateString);
      final now = DateTime.now();
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      return '$age ans';
    } catch (e) {
      return 'Non renseigné';
    }
  }

  String _getEnrollmentYear() {
    // Supposons que l'année d'inscription soit l'année courante ou l'année académique
    final now = DateTime.now();
    return '${now.year}-${now.year + 1}';
  }

  Widget _buildStatusChip(String text, IconData icon, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.secondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> cards, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: cards),
      ],
    );
  }

  Widget _buildInfoCard(
    String label,
    String value,
    IconData icon,
    ThemeData theme,
  ) {
    return Container(
      width: (MediaQuery.of(context).size.width - 72) / 2, // Responsive width
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value.isNotEmpty ? value : 'Non renseigné',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: value.isNotEmpty
                  ? theme.textTheme.bodyMedium?.color
                  : theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _moveStudentToTrash() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mettre à la corbeille ?'),
        content: const Text(
          'L’élève sera masqué des listes (suppression logique) et pourra être restauré.',
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
            child: const Text('Corbeille'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _dbService.softDeleteStudents(studentIds: [_student.id]);
    await _loadData();
    showRootSnackBar(
      const SnackBar(
        content: Text('Élève placé dans la corbeille.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _restoreStudent() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await _dbService.restoreStudents(studentIds: [_student.id]);
    await _loadData();
    showRootSnackBar(
      const SnackBar(
        content: Text('Élève restauré.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _exportStudentIdCardPdf() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final schoolInfo = await loadSchoolInfo();
    final pdfBytes = await PdfService.generateStudentIdCardsPdf(
      schoolInfo: schoolInfo,
      academicYear: _student.academicYear,
      students: [_student],
      className: _student.className,
      compact: true,
      includeQrCode: true,
      includeBarcode: true,
    );

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Carte élève',
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(ctx).pop('print'),
                icon: const Icon(Icons.print),
                label: const Text('Imprimer'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ctx).pop('save'),
                icon: const Icon(Icons.save_alt),
                label: const Text('Enregistrer (PDF)'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;

    if (action == 'print') {
      try {
        await Printing.layoutPdf(
          onLayout: (_) async => Uint8List.fromList(pdfBytes),
        );
        try {
          final u = await AuthService.instance.getCurrentUser();
          await _dbService.logAudit(
            category: 'student',
            action: 'print_student_id_card',
            username: u?.username,
            details:
                'student=${_student.id} class=${_student.className} year=${_student.academicYear}',
          );
        } catch (_) {}
      } catch (e) {
        showRootSnackBar(
          SnackBar(
            content: Text("Impression indisponible: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directoryPath == null) return;

    final fileName =
        'Carte_Eleve_${_student.name.replaceAll(' ', '_')}_${_student.academicYear}.pdf';
    final file = File('$directoryPath/$fileName');
    await file.writeAsBytes(pdfBytes);
    showRootSnackBar(
      SnackBar(
        content: Text('Carte enregistrée dans $directoryPath'),
        backgroundColor: Colors.green,
      ),
    );
    try {
      await OpenFile.open(file.path);
    } catch (_) {}
    try {
      final u = await AuthService.instance.getCurrentUser();
      await _dbService.logAudit(
        category: 'student',
        action: 'export_student_id_card_pdf',
        username: u?.username,
        details:
            'student=${_student.id} class=${_student.className} year=${_student.academicYear} file=$fileName',
      );
    } catch (_) {}
  }

  Future<void> _addDocuments() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final appDir = await getApplicationDocumentsDirectory();
    final studentDir = Directory(
      '${appDir.path}/student_documents/${_student.id}',
    );
    if (!await studentDir.exists()) {
      await studentDir.create(recursive: true);
    }

    final now = DateTime.now();
    final uuid = const Uuid();
    final newDocs = <StudentDocument>[];

    for (final f in result.files) {
      final srcPath = f.path;
      if (srcPath == null || srcPath.trim().isEmpty) continue;
      final src = File(srcPath);
      if (!await src.exists()) continue;

      final baseName = f.name.trim().isEmpty
          ? src.uri.pathSegments.last
          : f.name.trim();
      final safeName = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final uniqueName = '${now.millisecondsSinceEpoch}_$safeName';
      final destPath = '${studentDir.path}/$uniqueName';

      try {
        await src.copy(destPath);
        newDocs.add(
          StudentDocument(
            id: uuid.v4(),
            name: baseName,
            path: destPath,
            mimeType: null,
            addedAt: now,
          ),
        );
      } catch (e) {
        debugPrint('[StudentProfilePage] add document failed: $e');
      }
    }

    if (newDocs.isEmpty) return;
    final updated = [..._documents, ...newDocs];
    await _dbService.updateStudentDocuments(
      studentId: _student.id,
      documents: updated,
    );
    setState(() => _documents = updated);
  }

  Future<void> _openDocument(StudentDocument doc) async {
    final path = doc.path.trim();
    if (path.isEmpty) return;
    if (!File(path).existsSync()) {
      showRootSnackBar(
        const SnackBar(
          content: Text('Fichier introuvable.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await OpenFile.open(path);
  }

  Future<void> _renameDocument(StudentDocument doc) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final controller = TextEditingController(text: doc.name);
    final newName = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nom du document',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    final updated = _documents
        .map(
          (d) => d.id == doc.id
              ? StudentDocument(
                  id: d.id,
                  name: newName.trim(),
                  path: d.path,
                  mimeType: d.mimeType,
                  addedAt: d.addedAt,
                )
              : d,
        )
        .toList();
    await _dbService.updateStudentDocuments(
      studentId: _student.id,
      documents: updated,
    );
    setState(() => _documents = updated);
  }

  Future<void> _removeDocument(StudentDocument doc) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le document ?'),
        content: Text('Supprimer "${doc.name}" ?'),
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

    try {
      final file = File(doc.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    final updated = _documents.where((d) => d.id != doc.id).toList();
    await _dbService.updateStudentDocuments(
      studentId: _student.id,
      documents: updated,
    );
    setState(() => _documents = updated);
  }

  Widget _buildDocumentsTab() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.indigo.withOpacity(0.02),
            Colors.indigo.withOpacity(0.05),
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_documents.length} document(s)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _addDocuments,
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _documents.isEmpty
                ? Center(
                    child: Text(
                      'Aucun document.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.6,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _documents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final d = _documents[index];
                      final addedLabel = d.addedAt.millisecondsSinceEpoch == 0
                          ? ''
                          : 'Ajouté le ${DateFormat('dd/MM/yyyy').format(d.addedAt)}';
                      final exists = File(d.path).existsSync();
                      return Container(
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.3),
                          ),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(
                            d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: addedLabel.isEmpty
                              ? null
                              : Text(
                                  exists
                                      ? addedLabel
                                      : '$addedLabel • Introuvable',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: exists
                                        ? theme.textTheme.bodySmall?.color
                                        : Colors.red,
                                  ),
                                ),
                          onTap: exists ? () => _openDocument(d) : null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              switch (value) {
                                case 'open':
                                  await _openDocument(d);
                                  break;
                                case 'rename':
                                  await _renameDocument(d);
                                  break;
                                case 'delete':
                                  await _removeDocument(d);
                                  break;
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'open',
                                enabled: exists,
                                child: const ListTile(
                                  leading: Icon(Icons.open_in_new),
                                  title: Text('Ouvrir'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('Renommer'),
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Supprimer'),
                                ),
                              ),
                            ],
                            icon: const Icon(Icons.more_vert),
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

  Widget _buildDisciplineTab() {
    final theme = Theme.of(context);
    List<Map<String, dynamic>> filteredAttendance = _attendanceEvents;
    List<Map<String, dynamic>> filteredSanctions = _sanctionEvents;
    if (_disciplineDays != null) {
      final threshold = DateTime.now().subtract(
        Duration(days: _disciplineDays!),
      );
      bool isAfter(Map<String, dynamic> e) {
        final raw = (e['date'] ?? '').toString();
        final d = DateTime.tryParse(raw);
        if (d == null) return true;
        return d.isAfter(threshold);
      }

      filteredAttendance = filteredAttendance.where(isAfter).toList();
      filteredSanctions = filteredSanctions.where(isAfter).toList();
    }
    final total = filteredAttendance.length + filteredSanctions.length;
    final attByType = <String, int>{};
    int totalMinutes = 0;
    int unjustifiedCount = 0;
    for (final e in filteredAttendance) {
      final t = (e['type'] ?? '').toString();
      attByType[t] = (attByType[t] ?? 0) + 1;
      totalMinutes +=
          (e['minutes'] as int?) ?? int.tryParse('${e['minutes']}') ?? 0;
      final justified = (e['justified']?.toString() == '1');
      if (!justified) unjustifiedCount++;
    }
    final sancByType = <String, int>{};
    for (final e in filteredSanctions) {
      final t = (e['type'] ?? '').toString();
      sancByType[t] = (sancByType[t] ?? 0) + 1;
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.red.withOpacity(0.02), Colors.red.withOpacity(0.05)],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('30j'),
                selected: _disciplineDays == 30,
                onSelected: (_) => setState(() => _disciplineDays = 30),
              ),
              FilterChip(
                label: const Text('90j'),
                selected: _disciplineDays == 90,
                onSelected: (_) => setState(() => _disciplineDays = 90),
              ),
              FilterChip(
                label: const Text('Tout'),
                selected: _disciplineDays == null,
                onSelected: (_) => setState(() => _disciplineDays = null),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _addAttendanceEventDialog,
                icon: const Icon(Icons.add),
                label: const Text('Assiduité'),
              ),
              ElevatedButton.icon(
                onPressed: _addSanctionEventDialog,
                icon: const Icon(Icons.add),
                label: const Text('Sanction'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
              OutlinedButton.icon(
                onPressed: _exportDisciplineCsv,
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Exporter'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Aucun événement (selon le filtre).',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                  ),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _buildDisciplineStat(
                    theme,
                    title: 'Assiduité',
                    value: '${filteredAttendance.length}',
                    subtitle:
                        'Minutes: $totalMinutes • Non justifié: $unjustifiedCount',
                    icon: Icons.access_time,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDisciplineStat(
                    theme,
                    title: 'Sanctions',
                    value: '${filteredSanctions.length}',
                    subtitle: sancByType.entries
                        .take(2)
                        .map((e) => '${e.key}:${e.value}')
                        .join(' • '),
                    icon: Icons.gavel_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Assiduité',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (filteredAttendance.isEmpty)
              Text(
                'Aucun événement d’assiduité.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ...filteredAttendance
                  .take(100)
                  .map((e) => _buildAttendanceTile(e))
                  .toList(),
            const SizedBox(height: 16),
            Text(
              'Sanctions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (filteredSanctions.isEmpty)
              Text('Aucune sanction.', style: theme.textTheme.bodyMedium)
            else
              ...filteredSanctions
                  .take(100)
                  .map((e) => _buildSanctionTile(e))
                  .toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildDisciplineStat(
    ThemeData theme, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle.trim().isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTile(Map<String, dynamic> e) {
    final theme = Theme.of(context);
    final date = _fmtArchivedDate(e['date']);
    final type = (e['type'] ?? '').toString();
    final minutes = e['minutes']?.toString() ?? '0';
    final justified = (e['justified']?.toString() == '1');
    final id = int.tryParse('${e['id']}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: Icon(
          Icons.access_time,
          color: justified ? Colors.green : Colors.orange,
        ),
        title: Text('$type • $date'),
        subtitle: Text(
          'Minutes: $minutes • ${justified ? 'Justifié' : 'Non justifié'}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (id == null) return;
            if (value == 'edit') {
              await _editAttendanceEventDialog(e);
            } else if (value == 'delete') {
              await _deleteAttendanceEvent(id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Modifier'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Supprimer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSanctionTile(Map<String, dynamic> e) {
    final theme = Theme.of(context);
    final date = _fmtArchivedDate(e['date']);
    final type = (e['type'] ?? '').toString();
    final desc = (e['description'] ?? '').toString();
    final id = int.tryParse('${e['id']}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: const Icon(Icons.gavel_outlined, color: Colors.red),
        title: Text('$type • $date'),
        subtitle: Text(desc),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (id == null) return;
            if (value == 'edit') {
              await _editSanctionEventDialog(e);
            } else if (value == 'delete') {
              await _deleteSanctionEvent(id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Modifier'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Supprimer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAttendanceEventDialog() async {
    await _showAttendanceDialog();
  }

  Future<void> _editAttendanceEventDialog(Map<String, dynamic> e) async {
    await _showAttendanceDialog(existing: e);
  }

  Future<void> _showAttendanceDialog({Map<String, dynamic>? existing}) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final id = existing == null ? null : int.tryParse('${existing['id']}');
    DateTime date =
        DateTime.tryParse('${existing?['date'] ?? ''}') ?? DateTime.now();
    String type = (existing?['type'] ?? 'Retard').toString();
    final minutesController = TextEditingController(
      text: (existing?['minutes']?.toString() ?? '0'),
    );
    bool justified = (existing?['justified']?.toString() == '1');
    final reasonController = TextEditingController(
      text: (existing?['reason']?.toString() ?? ''),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null ? 'Ajouter assiduité' : 'Modifier assiduité',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Date: ${DateFormat('dd/MM/yyyy').format(date)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => date = picked);
                        }
                      },
                      child: const Text('Choisir'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Retard', child: Text('Retard')),
                    DropdownMenuItem(value: 'Absence', child: Text('Absence')),
                    DropdownMenuItem(value: 'Sortie', child: Text('Sortie')),
                  ],
                  onChanged: (v) => setState(() => type = v ?? 'Retard'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: minutesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: justified,
                  onChanged: (v) => setState(() => justified = v),
                  title: const Text('Justifié'),
                ),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Motif (optionnel)',
                    border: OutlineInputBorder(),
                  ),
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
              child: Text(existing == null ? 'Ajouter' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final minutes = int.tryParse(minutesController.text.trim()) ?? 0;
    final user = await AuthService.instance.getCurrentUser();
    if (existing == null) {
      await _dbService.insertAttendanceEvent(
        studentId: _student.id,
        academicYear: _student.academicYear,
        className: _student.className,
        date: date,
        type: type,
        minutes: minutes,
        justified: justified,
        reason: reasonController.text.trim(),
        recordedBy: user?.username,
      );
    } else if (id != null) {
      await _dbService.updateAttendanceEvent(
        id: id,
        date: date,
        type: type,
        minutes: minutes,
        justified: justified,
        reason: reasonController.text.trim(),
        recordedBy: user?.username,
      );
    }
    await _loadData();
  }

  Future<void> _deleteAttendanceEvent(int id) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Supprimer cet événement d’assiduité ?'),
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
    await _dbService.deleteAttendanceEvent(id: id);
    await _loadData();
  }

  Future<void> _addSanctionEventDialog() async {
    await _showSanctionDialog();
  }

  Future<void> _editSanctionEventDialog(Map<String, dynamic> e) async {
    await _showSanctionDialog(existing: e);
  }

  Future<void> _showSanctionDialog({Map<String, dynamic>? existing}) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final id = existing == null ? null : int.tryParse('${existing['id']}');
    DateTime date =
        DateTime.tryParse('${existing?['date'] ?? ''}') ?? DateTime.now();
    String type = (existing?['type'] ?? 'Avertissement').toString();
    final descriptionController = TextEditingController(
      text: (existing?['description']?.toString() ?? ''),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null ? 'Ajouter sanction' : 'Modifier sanction',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Date: ${DateFormat('dd/MM/yyyy').format(date)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => date = picked);
                        }
                      },
                      child: const Text('Choisir'),
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Avertissement',
                      child: Text('Avertissement'),
                    ),
                    DropdownMenuItem(value: 'Blâme', child: Text('Blâme')),
                    DropdownMenuItem(
                      value: 'Exclusion',
                      child: Text('Exclusion'),
                    ),
                  ],
                  onChanged: (v) => setState(() => type = v ?? 'Avertissement'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
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
              child: Text(existing == null ? 'Ajouter' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final user = await AuthService.instance.getCurrentUser();
    if (existing == null) {
      await _dbService.insertSanctionEvent(
        studentId: _student.id,
        academicYear: _student.academicYear,
        className: _student.className,
        date: date,
        type: type,
        description: descriptionController.text.trim(),
        recordedBy: user?.username,
      );
    } else if (id != null) {
      await _dbService.updateSanctionEvent(
        id: id,
        date: date,
        type: type,
        description: descriptionController.text.trim(),
        recordedBy: user?.username,
      );
    }
    await _loadData();
  }

  Future<void> _deleteSanctionEvent(int id) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showRootSnackBar(
        SnackBar(
          content: Text(SafeModeService.instance.getBlockedActionMessage()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Supprimer cette sanction ?'),
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
    await _dbService.deleteSanctionEvent(id: id);
    await _loadData();
  }

  Future<void> _exportDisciplineCsv() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(
      '$dir/discipline_${_student.name.replaceAll(' ', '_')}_$ts.csv',
    );

    final rows = <List<dynamic>>[
      ['kind', 'date', 'type', 'minutes', 'justified', 'description', 'reason'],
    ];
    for (final e in _attendanceEvents) {
      rows.add([
        'attendance',
        _fmtArchivedDate(e['date']),
        e['type'] ?? '',
        e['minutes'] ?? 0,
        e['justified'] ?? 0,
        '',
        e['reason'] ?? '',
      ]);
    }
    for (final e in _sanctionEvents) {
      rows.add([
        'sanction',
        _fmtArchivedDate(e['date']),
        e['type'] ?? '',
        '',
        '',
        e['description'] ?? '',
        '',
      ]);
    }
    final csv = const ListToCsvConverter().convert(rows);
    await file.writeAsString(csv);
    showRootSnackBar(
      SnackBar(
        content: Text('Exporté: ${file.path.split('/').last}'),
        backgroundColor: Colors.green,
      ),
    );
    try {
      await OpenFile.open(file.path);
    } catch (_) {}
  }

  Widget _buildJournalTab() {
    final theme = Theme.of(context);
    final logs = _auditLogs;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey.withOpacity(0.02),
            Colors.grey.withOpacity(0.05),
          ],
        ),
      ),
      child: logs.isEmpty
          ? Center(
              child: Text(
                'Aucun événement dans le journal.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final l = logs[index];
                final ts = _fmtAuditTimestamp(l['timestamp']);
                final categoryRaw = (l['category'] ?? '').toString();
                final actionRaw = (l['action'] ?? '').toString();
                final category = _auditCategoryLabel(categoryRaw);
                final action = _auditActionLabel(actionRaw);
                final details = (l['details'] ?? '').toString();
                final username = (l['username'] ?? '').toString();
                final ok = (l['success']?.toString() ?? '1') != '0';
                return Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.3),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      ok ? Icons.check_circle_outline : Icons.error_outline,
                      color: ok ? Colors.green : Colors.red,
                    ),
                    title: Text('$category — $action'),
                    subtitle: Text(
                      [
                        if (ts.isNotEmpty) ts,
                        if (username.isNotEmpty) 'Par $username',
                        ok ? 'Statut: Succès' : 'Statut: Échec',
                        if (details.trim().isNotEmpty) details,
                      ].where((s) => s.toString().trim().isNotEmpty).join('\n'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildPaymentsTab() {
    final theme = Theme.of(context);
    if (_payments.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.green.withOpacity(0.02),
              Colors.green.withOpacity(0.05),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.payment_outlined,
                size: 64,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Aucun paiement trouvé',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Les paiements de cet élève apparaîtront ici',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Calculate total paid
    final totalPaid = _payments
        .where((p) => !p.isCancelled)
        .fold(0.0, (sum, item) => sum + item.amount);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.green.withOpacity(0.02),
            Colors.green.withOpacity(0.05),
          ],
        ),
      ),
      child: Column(
        children: [
          // Summary Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withOpacity(0.1),
                  theme.colorScheme.secondary.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total des Paiements',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.7,
                          ),
                        ),
                      ),
                      Text(
                        '${totalPaid.toStringAsFixed(0)} FCFA',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${_payments.where((p) => !p.isCancelled).length} paiements',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Payments List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _payments.length,
              itemBuilder: (context, index) {
                final payment = _payments[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: payment.isCancelled
                          ? Colors.red.withOpacity(0.3)
                          : theme.dividerColor.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: payment.isCancelled
                                    ? Colors.red.withOpacity(0.1)
                                    : theme.colorScheme.primary.withOpacity(
                                        0.1,
                                      ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                payment.isCancelled
                                    ? Icons.cancel
                                    : Icons.receipt_long,
                                color: payment.isCancelled
                                    ? Colors.red
                                    : theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Paiement du ${payment.date.substring(0, 10)}',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${payment.amount} FCFA',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (payment.isCancelled)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.red.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  'Annulé',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (payment.comment != null &&
                            payment.comment!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary.withOpacity(
                                0.05,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.secondary.withOpacity(
                                  0.2,
                                ),
                              ),
                            ),
                            child: Text(
                              'Commentaire: ${payment.comment}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                        ],
                        if (payment.isCancelled &&
                            payment.cancelledAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Annulé le: ${payment.cancelledAt!.substring(0, 10)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                final studentClass = await _dbService
                                    .getClassByName(widget.student.className);
                                if (studentClass != null) {
                                  final allPayments = await _dbService
                                      .getPaymentsForStudent(widget.student.id);
                                  final totalPaid = allPayments
                                      .where((p) => !p.isCancelled)
                                      .fold(
                                        0.0,
                                        (sum, item) => sum + item.amount,
                                      );
                                  final totalDue =
                                      (studentClass.fraisEcole ?? 0) +
                                      (studentClass.fraisCotisationParallele ??
                                          0);
                                  final schoolInfo = await loadSchoolInfo();
                                  final pdfBytes =
                                      await PdfService.generatePaymentReceiptPdf(
                                        currentPayment: payment,
                                        allPayments: allPayments,
                                        student: widget.student,
                                        schoolInfo: schoolInfo,
                                        studentClass: studentClass,
                                        totalPaid: totalPaid,
                                        totalDue: totalDue,
                                      );

                                  String? directoryPath = await FilePicker
                                      .platform
                                      .getDirectoryPath(
                                        dialogTitle:
                                            'Choisir le dossier de sauvegarde',
                                      );
                                  if (directoryPath != null) {
                                    final fileName =
                                        'Recu_Paiement_${widget.student.name.replaceAll(' ', '_')}_${payment.date.substring(0, 10)}.pdf';
                                    final file = File(
                                      '$directoryPath/$fileName',
                                    );
                                    await file.writeAsBytes(pdfBytes);
                                    showRootSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Reçu enregistré dans $directoryPath',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: Icon(Icons.picture_as_pdf, size: 18),
                              label: Text('Télécharger PDF'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Future<void> _exportArchivedReportCard({
    required Map<String, dynamic> reportCard,
    required List<double?> moyennesParPeriode,
    required List<String> allTerms,
    required String variant,
  }) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    final info = await loadSchoolInfo();
    final className =
        reportCard['className']?.toString() ?? widget.student.className;
    final academicYear = reportCard['academicYear']?.toString();
    final studentClass = await _dbService.getClassByName(
      className,
      academicYear: academicYear,
    );
    if (studentClass == null) return;

    final archivedGrades = await _dbService.getArchivedGrades(
      academicYear: reportCard['academicYear'],
      className: reportCard['className'],
      studentId: reportCard['studentId'],
    );

    final subjectApps = await _dbService.database.then(
      (db) => db.query(
        'subject_appreciation_archive',
        where: 'report_card_id = ?',
        whereArgs: [reportCard['id']],
      ),
    );

    final Map<String, String> professeurs = {};
    final Map<String, String> appreciations = {};
    final Map<String, String> moyennesClasse = {};

    for (final app in subjectApps) {
      final p = (app['professeur'] ?? '').toString().trim();
      final a = (app['appreciation'] ?? '').toString().trim();
      final m = (app['moyenne_classe'] ?? '').toString().trim();
      professeurs[app['subject'] as String] = p.isNotEmpty ? p : '-';
      appreciations[app['subject'] as String] = a.isNotEmpty ? a : '-';
      moyennesClasse[app['subject'] as String] = m.isNotEmpty ? m : '-';
    }

    bool isExAequo = (reportCard['exaequo'] is int)
        ? (reportCard['exaequo'] as int) == 1
        : (reportCard['exaequo'] == true);
    try {
      if (!isExAequo) {
        final allArchived = await _dbService.getArchivedGrades(
          academicYear: reportCard['academicYear'],
          className: reportCard['className'],
        );
        final term = (reportCard['term'] as String?) ?? '';
        final Map<String, Map<String, double>> sums = {};
        for (final g in allArchived.where((g) => g.term == term)) {
          final s = sums.putIfAbsent(g.studentId, () => {'n': 0.0, 'c': 0.0});
          if (g.maxValue > 0 && g.coefficient > 0) {
            s['n'] =
                (s['n'] ?? 0) + ((g.value / g.maxValue) * 20) * g.coefficient;
            s['c'] = (s['c'] ?? 0) + g.coefficient;
          }
        }
        final List<double> avgs = sums.entries
            .map(
              (e) => (e.value['c'] ?? 0) > 0
                  ? (e.value['n']! / e.value['c']!)
                  : 0.0,
            )
            .toList();
        final double myAvg = reportCard['moyenne_generale']?.toDouble() ?? 0.0;
        const double eps = 0.001;
        final int ties = avgs.where((m) => (m - myAvg).abs() < eps).length;
        isExAequo = ties > 1;
      }
    } catch (_) {}

    List<int> pdfBytes;
    if (variant == 'custom') {
      // Demander l'orientation
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
      final bool isLandscape = orientation == 'landscape';

      // Demander le format
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
      final bool useLongFormat = formatChoice == 'long';

      final prefs = await SharedPreferences.getInstance();
      final footerNote = prefs.getString('report_card_footer_note') ?? '';
      final adminCivility = prefs.getString('school_admin_civility') ?? 'M.';
      pdfBytes =
          await ReportCardCustomExportService.generateReportCardCustomPdf(
            student: widget.student,
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
            periodLabel:
                reportCard['term']?.toString().contains('Semestre') == true
                ? 'Semestre'
                : 'Trimestre',
            appreciationGenerale: reportCard['appreciation_generale'] ?? '',
            mention: reportCard['mention'] ?? '',
            decision: reportCard['decision'] ?? '',
            decisionAutomatique: '',
            conduite: reportCard['conduite'] ?? '',
            recommandations: reportCard['recommandations'] ?? '',
            forces: reportCard['forces'] ?? '',
            pointsADevelopper: reportCard['points_a_developper'] ?? '',
            sanctions: reportCard['sanctions'] ?? '',
            attendanceJustifiee:
                (reportCard['attendance_justifiee'] ?? 0) as int,
            attendanceInjustifiee:
                (reportCard['attendance_injustifiee'] ?? 0) as int,
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
            academicYear: reportCard['academicYear'] ?? '',
            term: reportCard['term'] ?? '',
            className: reportCard['className'] ?? widget.student.className,
            selectedTerm: reportCard['term'] ?? '',
            faitA: reportCard['fait_a'] ?? '',
            leDate: reportCard['le_date'] ?? '',
            titulaireName: studentClass.titulaire ?? '',
            directorName: info.director,
            titulaireCivility: 'M.',
            directorCivility: adminCivility,
            footerNote: footerNote,
            isLandscape: isLandscape,
            useLongFormat: useLongFormat,
            duplicata: true,
          );
    } else if (variant == 'compact') {
      pdfBytes = await PdfService.generateReportCardPdfCompact(
        student: widget.student,
        schoolInfo: info,
        grades: archivedGrades,
        professeurs: professeurs,
        appreciations: appreciations,
        moyennesClasse: moyennesClasse,
        appreciationGenerale: reportCard['appreciation_generale'] ?? '',
        decision: reportCard['decision'] ?? '',
        recommandations: reportCard['recommandations'] ?? '',
        forces: reportCard['forces'] ?? '',
        pointsADevelopper: reportCard['points_a_developper'] ?? '',
        sanctions: reportCard['sanctions'] ?? '',
        attendanceJustifiee: (reportCard['attendance_justifiee'] ?? 0) as int,
        attendanceInjustifiee:
            (reportCard['attendance_injustifiee'] ?? 0) as int,
        retards: (reportCard['retards'] ?? 0) as int,
        presencePercent: (reportCard['presence_percent'] ?? 0.0) is int
            ? (reportCard['presence_percent'] as int).toDouble()
            : (reportCard['presence_percent'] ?? 0.0) as double,
        conduite: reportCard['conduite'] ?? '',
        telEtab: info.telephone ?? '',
        mailEtab: info.email ?? '',
        webEtab: info.website ?? '',
        titulaire: studentClass.titulaire ?? '',
        subjects: archivedGrades.map((e) => e.subject).toSet().toList(),
        moyennesParPeriode: moyennesParPeriode,
        moyenneGenerale: reportCard['moyenne_generale']?.toDouble() ?? 0.0,
        rang: reportCard['rang'] ?? 0,
        exaequo: isExAequo,
        nbEleves: reportCard['nb_eleves'] ?? 0,
        mention: reportCard['mention'] ?? '',
        allTerms: allTerms,
        periodLabel: reportCard['term']?.toString().contains('Semestre') == true
            ? 'Semestre'
            : 'Trimestre',
        selectedTerm: reportCard['term'] ?? '',
        academicYear: reportCard['academicYear'] ?? '',
        faitA: reportCard['fait_a'] ?? '',
        leDate: reportCard['le_date'] ?? '',
        isLandscape: false,
        niveau: studentClass.level ?? '',
        moyenneGeneraleDeLaClasse:
            reportCard['moyenne_generale_classe']?.toDouble() ?? 0.0,
        moyenneLaPlusForte:
            reportCard['moyenne_la_plus_forte']?.toDouble() ?? 0.0,
        moyenneLaPlusFaible:
            reportCard['moyenne_la_plus_faible']?.toDouble() ?? 0.0,
        moyenneAnnuelle: reportCard['moyenne_annuelle']?.toDouble() ?? 0.0,
        duplicata: true,
      );
    } else if (variant == 'ultra') {
      pdfBytes = await PdfService.generateReportCardPdfUltraCompact(
        student: widget.student,
        schoolInfo: info,
        grades: archivedGrades,
        professeurs: professeurs,
        appreciations: appreciations,
        moyennesClasse: moyennesClasse,
        appreciationGenerale: reportCard['appreciation_generale'] ?? '',
        decision: reportCard['decision'] ?? '',
        recommandations: reportCard['recommandations'] ?? '',
        forces: reportCard['forces'] ?? '',
        pointsADevelopper: reportCard['points_a_developper'] ?? '',
        sanctions: reportCard['sanctions'] ?? '',
        attendanceJustifiee: (reportCard['attendance_justifiee'] ?? 0) as int,
        attendanceInjustifiee:
            (reportCard['attendance_injustifiee'] ?? 0) as int,
        retards: (reportCard['retards'] ?? 0) as int,
        presencePercent: (reportCard['presence_percent'] ?? 0.0) is int
            ? (reportCard['presence_percent'] as int).toDouble()
            : (reportCard['presence_percent'] ?? 0.0) as double,
        conduite: reportCard['conduite'] ?? '',
        telEtab: info.telephone ?? '',
        mailEtab: info.email ?? '',
        webEtab: info.website ?? '',
        titulaire: studentClass.titulaire ?? '',
        subjects: archivedGrades.map((e) => e.subject).toSet().toList(),
        moyennesParPeriode: moyennesParPeriode,
        moyenneGenerale: reportCard['moyenne_generale']?.toDouble() ?? 0.0,
        rang: reportCard['rang'] ?? 0,
        exaequo: isExAequo,
        nbEleves: reportCard['nb_eleves'] ?? 0,
        mention: reportCard['mention'] ?? '',
        allTerms: allTerms,
        periodLabel: reportCard['term']?.toString().contains('Semestre') == true
            ? 'Semestre'
            : 'Trimestre',
        selectedTerm: reportCard['term'] ?? '',
        academicYear: reportCard['academicYear'] ?? '',
        faitA: reportCard['fait_a'] ?? '',
        leDate: reportCard['le_date'] ?? '',
        isLandscape: false,
        niveau: studentClass.level ?? '',
        moyenneGeneraleDeLaClasse:
            reportCard['moyenne_generale_classe']?.toDouble() ?? 0.0,
        moyenneLaPlusForte:
            reportCard['moyenne_la_plus_forte']?.toDouble() ?? 0.0,
        moyenneLaPlusFaible:
            reportCard['moyenne_la_plus_faible']?.toDouble() ?? 0.0,
        moyenneAnnuelle: reportCard['moyenne_annuelle']?.toDouble() ?? 0.0,
        duplicata: true,
      );
    } else {
      pdfBytes = await PdfService.generateReportCardPdf(
        student: widget.student,
        schoolInfo: info,
        grades: archivedGrades,
        professeurs: professeurs,
        appreciations: appreciations,
        moyennesClasse: moyennesClasse,
        appreciationGenerale: reportCard['appreciation_generale'] ?? '',
        decision: reportCard['decision'] ?? '',
        recommandations: reportCard['recommandations'] ?? '',
        forces: reportCard['forces'] ?? '',
        pointsADevelopper: reportCard['points_a_developper'] ?? '',
        sanctions: reportCard['sanctions'] ?? '',
        attendanceJustifiee: (reportCard['attendance_justifiee'] ?? 0) as int,
        attendanceInjustifiee:
            (reportCard['attendance_injustifiee'] ?? 0) as int,
        retards: (reportCard['retards'] ?? 0) as int,
        presencePercent: (reportCard['presence_percent'] ?? 0.0) is int
            ? (reportCard['presence_percent'] as int).toDouble()
            : (reportCard['presence_percent'] ?? 0.0) as double,
        conduite: reportCard['conduite'] ?? '',
        telEtab: info.telephone ?? '',
        mailEtab: info.email ?? '',
        webEtab: info.website ?? '',
        titulaire: studentClass.titulaire ?? '',
        subjects: archivedGrades.map((e) => e.subject).toSet().toList(),
        moyennesParPeriode: moyennesParPeriode,
        moyenneGenerale: reportCard['moyenne_generale']?.toDouble() ?? 0.0,
        rang: reportCard['rang'] ?? 0,
        exaequo: isExAequo,
        nbEleves: reportCard['nb_eleves'] ?? 0,
        mention: reportCard['mention'] ?? '',
        allTerms: allTerms,
        periodLabel: reportCard['term']?.toString().contains('Semestre') == true
            ? 'Semestre'
            : 'Trimestre',
        selectedTerm: reportCard['term'] ?? '',
        academicYear: reportCard['academicYear'] ?? '',
        faitA: reportCard['fait_a'] ?? '',
        leDate: reportCard['le_date'] ?? '',
        isLandscape: false,
        niveau: studentClass.level ?? '',
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

    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directoryPath != null) {
      final suffix = variant == 'compact'
          ? '_compact'
          : variant == 'ultra'
          ? '_ultra_compact'
          : variant == 'custom'
          ? '_custom'
          : '';
      final fileName =
          'Bulletin_${widget.student.name.replaceAll(' ', '_')}_${reportCard['term'] ?? ''}_${reportCard['academicYear'] ?? ''}$suffix.pdf';
      final file = File('$directoryPath/$fileName');
      await file.writeAsBytes(pdfBytes);
      showRootSnackBar(
        SnackBar(
          content: Text(
            variant == 'compact'
                ? 'Bulletin compact enregistré dans $directoryPath'
                : variant == 'ultra'
                ? 'Bulletin ultra compact enregistré dans $directoryPath'
                : variant == 'custom'
                ? 'Bulletin custom enregistré dans $directoryPath'
                : 'Bulletin enregistré dans $directoryPath',
          ),
          backgroundColor: Colors.green,
        ),
      );
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'report_card',
          action: variant == 'compact'
              ? 'export_report_card_pdf_compact'
              : variant == 'ultra'
              ? 'export_report_card_pdf_ultra_compact'
              : variant == 'custom'
              ? 'export_report_card_pdf_custom'
              : 'export_report_card_pdf',
          username: u?.username,
          details:
              'student=${widget.student.id} class=${reportCard['className'] ?? ''} year=${reportCard['academicYear'] ?? ''} term=${reportCard['term'] ?? ''} file=$fileName',
        );
      } catch (_) {}
    }
  }

  Widget _buildReportCardsTab() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.orange.withOpacity(0.02),
            Colors.orange.withOpacity(0.05),
          ],
        ),
      ),
      child: _reportCards.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 64,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucun bulletin archivé',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(
                        0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Les bulletins archivés de cet élève apparaîtront ici',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(
                        0.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reportCards.length,
              itemBuilder: (context, index) {
                final reportCard = _reportCards[index];
                // Decode moyennes_par_periode and all_terms from JSON string
                final List<double?> moyennesParPeriode =
                    (reportCard['moyennes_par_periode'] as String)
                        .replaceAll('[', '')
                        .replaceAll(']', '')
                        .split(',')
                        .map((e) => double.tryParse(e.trim()))
                        .toList();
                final List<String> allTerms =
                    (reportCard['all_terms'] as String)
                        .replaceAll('[', '')
                        .replaceAll(']', '')
                        .split(',')
                        .map((e) => e.trim())
                        .toList();

                final moyenneGenerale =
                    reportCard['moyenne_generale']?.toDouble() ?? 0.0;
                final mention = reportCard['mention'] ?? '';

                // Determine color based on grade
                Color gradeColor = Colors.grey;
                if (moyenneGenerale >= 16) {
                  gradeColor = Colors.green;
                } else if (moyenneGenerale >= 14) {
                  gradeColor = Colors.blue;
                } else if (moyenneGenerale >= 12) {
                  gradeColor = Colors.orange;
                } else if (moyenneGenerale >= 10) {
                  gradeColor = Colors.red;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: gradeColor.withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // En-tête administratif (snapshot depuis l'archive)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((reportCard['school_ministry'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      (reportCard['school_ministry'] as String)
                                          .toUpperCase(),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  if ((reportCard['school_inspection'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      'Inspection: ${reportCard['school_inspection']}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    ((reportCard['school_republic'] ??
                                                'RÉPUBLIQUE')
                                            as String)
                                        .toUpperCase(),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if ((reportCard['school_republic_motto'] ??
                                          '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      reportCard['school_republic_motto'],
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                  if ((reportCard['school_education_direction'] ??
                                          '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      "Direction de l'enseignement: ${reportCard['school_education_direction']}",
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Bloc élève snapshot
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Nom: ${widget.student.name}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Date de naissance: ${_fmtArchivedDate(reportCard['student_dob'])}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Statut: ${reportCard['student_status'] ?? ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (((reportCard['student_photo_path'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty) &&
                            File(
                              (reportCard['student_photo_path'] as String),
                            ).existsSync())
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.dividerColor.withOpacity(0.3),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.file(
                                File(
                                  reportCard['student_photo_path'] as String,
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: gradeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.school,
                                color: gradeColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bulletin ${reportCard['term']} - ${reportCard['academicYear']}',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color:
                                              theme.textTheme.bodyLarge?.color,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Classe: ${reportCard['className']}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.textTheme.bodyMedium?.color
                                          ?.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: gradeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: gradeColor.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                mention.isNotEmpty ? mention : 'Sans mention',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: gradeColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (((reportCard['exaequo'] is int) &&
                                    (reportCard['exaequo'] as int) == 1) ||
                                reportCard['exaequo'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.amber.withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  'ex æquo',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.amber.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Grade Summary (fallback compute if archive values are 0)
                        FutureBuilder<Map<String, dynamic>>(
                          future: () async {
                            num avg =
                                (reportCard['moyenne_generale'] as num?) ?? 0;
                            num rank = (reportCard['rang'] as num?) ?? 0;
                            num nb = (reportCard['nb_eleves'] as num?) ?? 0;
                            bool isExAequo = (reportCard['exaequo'] is int)
                                ? (reportCard['exaequo'] as int) == 1
                                : (reportCard['exaequo'] == true);
                            // Fallback: use stored per-period averages if available
                            if (avg == 0) {
                              try {
                                final term =
                                    reportCard['term'] as String? ?? '';
                                final all = allTerms;
                                final idx = all.indexOf(term);
                                if (idx >= 0 &&
                                    idx < moyennesParPeriode.length &&
                                    moyennesParPeriode[idx] != null) {
                                  avg = (moyennesParPeriode[idx] as double);
                                }
                              } catch (_) {}
                            }
                            // Fallback: compute rank/nb from archived grades for this class/year/term
                            if (rank == 0 ||
                                nb == 0 ||
                                avg == 0 ||
                                !isExAequo) {
                              try {
                                final className =
                                    reportCard['className'] as String? ?? '';
                                final academicYear =
                                    reportCard['academicYear'] as String? ?? '';
                                final archived = await _dbService
                                    .getArchivedGrades(
                                      academicYear: academicYear,
                                      className: className,
                                    );
                                final term =
                                    (reportCard['term'] as String?) ?? '';
                                final subjectWeightsById = await _dbService
                                    .getClassCourseCoefficientsById(
                                      className,
                                      academicYear,
                                    );
                                final subjectWeightsByName = await _dbService
                                    .getClassSubjectCoefficients(
                                      className,
                                      academicYear,
                                    );

                                double computeAverageOn20(List<Grade> grades) {
                                  double total = 0.0;
                                  double totalCoeff = 0.0;
                                  for (final g in grades) {
                                    if (g.maxValue > 0 && g.coefficient > 0) {
                                      total +=
                                          ((g.value / g.maxValue) * 20) *
                                          g.coefficient;
                                      totalCoeff += g.coefficient;
                                    }
                                  }
                                  return totalCoeff > 0
                                      ? (total / totalCoeff)
                                      : 0.0;
                                }

                                double sumCoefficients(List<Grade> grades) {
                                  double totalCoeff = 0.0;
                                  for (final g in grades) {
                                    if (g.maxValue > 0 && g.coefficient > 0) {
                                      totalCoeff += g.coefficient;
                                    }
                                  }
                                  return totalCoeff;
                                }

                                double computeWeightedAverageForStudent(
                                  String studentId,
                                ) {
                                  final studentGrades = archived
                                      .where(
                                        (g) =>
                                            g.studentId == studentId &&
                                            g.term == term,
                                      )
                                      .toList();
                                  if (studentGrades.isEmpty) return 0.0;
                                  final Map<String, List<Grade>> bySubject = {};
                                  for (final g in studentGrades) {
                                    final key = g.subjectId.trim().isNotEmpty
                                        ? g.subjectId
                                        : g.subject;
                                    bySubject.putIfAbsent(key, () => []).add(g);
                                  }
                                  double sumPoints = 0.0;
                                  double sumWeights = 0.0;
                                  bySubject.forEach((_, list) {
                                    final average = computeAverageOn20(list);
                                    final subjectId = list.first.subjectId
                                        .trim();
                                    final subjectName = list.first.subject;
                                    double? weight = subjectId.isNotEmpty
                                        ? subjectWeightsById[subjectId]
                                        : null;
                                    weight ??=
                                        subjectWeightsByName[subjectName];
                                    weight ??= sumCoefficients(list);
                                    if (weight > 0) {
                                      sumPoints += average * weight;
                                      sumWeights += weight;
                                    }
                                  });
                                  return sumWeights > 0
                                      ? (sumPoints / sumWeights)
                                      : 0.0;
                                }

                                final classStudents = await _dbService
                                    .getStudentsByClassAndClassYear(
                                      className,
                                      academicYear,
                                    );
                                final studentIds = classStudents.isNotEmpty
                                    ? classStudents.map((s) => s.id).toList()
                                    : archived
                                          .map((g) => g.studentId)
                                          .toSet()
                                          .toList();

                                final List<MapEntry<String, double>> avgs = [];
                                for (final sid in studentIds) {
                                  avgs.add(
                                    MapEntry(
                                      sid,
                                      computeWeightedAverageForStudent(sid),
                                    ),
                                  );
                                }
                                avgs.sort((a, b) => b.value.compareTo(a.value));
                                nb = avgs.length;
                                final sid = reportCard['studentId'] as String?;
                                final self = avgs.firstWhere(
                                  (e) => e.key == sid,
                                  orElse: () => const MapEntry('', 0.0),
                                );
                                final double myAvg = self.value;
                                const double eps = 0.001;
                                // Rang ex æquo: 1 + nombre d'élèves avec une moyenne strictement supérieure
                                rank =
                                    1 +
                                    avgs
                                        .where((e) => (e.value - myAvg) > eps)
                                        .length;
                                // Ex æquo si d'autres élèves ont la même moyenne (tolérance eps)
                                isExAequo =
                                    avgs
                                        .where(
                                          (e) => (e.value - myAvg).abs() < eps,
                                        )
                                        .length >
                                    1;
                                if (avg == 0 && myAvg > 0) avg = myAvg;
                              } catch (_) {}
                            }
                            return {
                              'avg': avg,
                              'rank': rank,
                              'nb': nb,
                              'exaequo': isExAequo,
                            };
                          }(),
                          builder: (context, snap) {
                            final num avg =
                                snap.data?['avg'] ??
                                (reportCard['moyenne_generale'] as num? ?? 0);
                            final num rank =
                                snap.data?['rank'] ??
                                (reportCard['rang'] as num? ?? 0);
                            final num nb =
                                snap.data?['nb'] ??
                                (reportCard['nb_eleves'] as num? ?? 0);
                            final bool exaequo =
                                (snap.data?['exaequo'] as bool?) ??
                                ((reportCard['exaequo'] is int)
                                    ? (reportCard['exaequo'] as int) == 1
                                    : (reportCard['exaequo'] == true));
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    gradeColor.withOpacity(0.1),
                                    gradeColor.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: gradeColor.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          'Moyenne Générale',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                                    ?.withOpacity(0.7),
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          avg.toStringAsFixed(2),
                                          style: theme.textTheme.headlineMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: gradeColor,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 40,
                                    color: gradeColor.withOpacity(0.3),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          'Rang',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                                    ?.withOpacity(0.7),
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          exaequo
                                              ? '${rank.toInt()} (ex æquo) / ${nb.toInt()}'
                                              : '${rank.toInt()} / ${nb.toInt()}',
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: theme
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // Statistics Grid
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildStatCard(
                              'Moyenne Classe',
                              '${reportCard['moyenne_generale_classe']?.toStringAsFixed(2) ?? '-'}',
                              Icons.group,
                              theme,
                            ),
                            _buildStatCard(
                              'Plus Forte',
                              '${reportCard['moyenne_la_plus_forte']?.toStringAsFixed(2) ?? '-'}',
                              Icons.trending_up,
                              theme,
                            ),
                            _buildStatCard(
                              'Plus Faible',
                              '${reportCard['moyenne_la_plus_faible']?.toStringAsFixed(2) ?? '-'}',
                              Icons.trending_down,
                              theme,
                            ),
                            _buildStatCard(
                              'Moyenne Annuelle',
                              '${reportCard['moyenne_annuelle']?.toStringAsFixed(2) ?? '-'}',
                              Icons.calendar_today,
                              theme,
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Download Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                await _exportArchivedReportCard(
                                  reportCard: reportCard,
                                  moyennesParPeriode: moyennesParPeriode,
                                  allTerms: allTerms,
                                  variant: 'standard',
                                );
                              },
                              icon: Icon(Icons.picture_as_pdf, size: 18),
                              label: Text('Télécharger PDF'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                await _exportArchivedReportCard(
                                  reportCard: reportCard,
                                  moyennesParPeriode: moyennesParPeriode,
                                  allTerms: allTerms,
                                  variant: 'compact',
                                );
                              },
                              icon: Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 18,
                              ),
                              label: Text('Télécharger PDF compact'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                await _exportArchivedReportCard(
                                  reportCard: reportCard,
                                  moyennesParPeriode: moyennesParPeriode,
                                  allTerms: allTerms,
                                  variant: 'ultra',
                                );
                              },
                              icon: Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 18,
                              ),
                              label: Text('Télécharger PDF ultra compact'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                await _exportArchivedReportCard(
                                  reportCard: reportCard,
                                  moyennesParPeriode: moyennesParPeriode,
                                  allTerms: allTerms,
                                  variant: 'custom',
                                );
                              },
                              icon: Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 18,
                              ),
                              label: Text('Télécharger PDF custom'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    ThemeData theme,
  ) {
    return Container(
      width: (MediaQuery.of(context).size.width - 100) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
