import 'package:flutter/material.dart';
import 'package:school_manager/widgets/confirm_dialog.dart';
import 'package:intl/intl.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:uuid/uuid.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/teacher_assignment.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:excel/excel.dart' hide Border;
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/auth_service.dart';

class _TeacherAssignmentDraft {
  final String courseId;
  final String courseName;
  final String className;
  final String academicYear;

  _TeacherAssignmentDraft({
    required this.courseId,
    required this.courseName,
    required this.className,
    required this.academicYear,
  });
}

class StaffPage extends StatefulWidget {
  const StaffPage({Key? key}) : super(key: key);

  @override
  _StaffPageState createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final TextEditingController _searchController = TextEditingController();
  late FocusNode _searchFocusNode;
  String _selectedTab = 'Tout le Personnel';
  String _searchQuery = '';
  String _selectedRoleTab = 'Tout le Personnel';
  final List<String> _roleTabs = [
    'Tout le Personnel',
    'Personnel Enseignant',
    'Personnel Administratif',
  ];

  final DatabaseService _dbService = DatabaseService();
  List<Staff> _staffList = [];
  bool _isLoading = true;
  List<Course> _allCourses = [];
  int _currentPage = 0;
  static const int _rowsPerPage = 7;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();
    _searchFocusNode = FocusNode();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadStaff();
    _loadCourses();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    final staff = await _dbService.getStaff();
    setState(() {
      _staffList = staff;
      _isLoading = false;
    });
  }

  Future<void> _loadCourses() async {
    final courses = await _dbService.getCourses();
    setState(() {
      _allCourses = courses;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final isTablet =
        MediaQuery.of(context).size.width > 600 &&
        MediaQuery.of(context).size.width <= 900;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(context, isDarkMode, isDesktop),
              // Boutons d'action
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _showAddCourseDialog,
                      icon: Icon(Icons.add, color: Colors.white),
                      label: Text(
                        'Ajouter un cours',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _exportStaffToPdf(),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Exporter PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _exportStaffToExcel(),
                      icon: const Icon(Icons.grid_on),
                      label: const Text('Exporter Excel'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                  ],
                ),
              ),
              // Tabs
              // Search
              // Table/cards
              Expanded(
                child: _buildStaffTable(context, isDesktop, isTablet, theme),
              ),
              // Bouton d'ajout membre
              Padding(
                padding: const EdgeInsets.all(24),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FloatingActionButton.extended(
                    onPressed: () => _showAddEditStaffDialog(null),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Ajouter un membre'),
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                  ),
                ),
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
                      Icons.group,
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
                        'Gestion du Personnel',
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
                        'Gérez le personnel enseignant et administratif, assignez les cours et surveillez la présence.',
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
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Rechercher par nom ou ID du personnel...',
              hintStyle: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffTable(
    BuildContext context,
    bool isDesktop,
    bool isTablet,
    ThemeData theme,
  ) {
    final filtered = _staffList.where((staff) {
      final query = _searchQuery;
      final tab = _selectedRoleTab;
      bool matchRole = true;
      if (tab == 'Personnel Enseignant') {
        matchRole = staff.typeRole == 'Professeur';
      } else if (tab == 'Personnel Administratif') {
        matchRole = staff.typeRole == 'Administration';
      }
      if (query.isEmpty) return matchRole;
      return matchRole &&
          (staff.name.toLowerCase().contains(query) ||
              staff.id.toLowerCase().contains(query));
    }).toList();
    final totalPages = (filtered.length / _rowsPerPage).ceil();
    final start = _currentPage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, filtered.length);
    final paginated = filtered.sublist(start, end);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (isDesktop) _buildDesktopTable(paginated, theme),
                if (isTablet) _buildTabletTable(paginated, theme),
                if (!isDesktop && !isTablet)
                  _buildMobileCards(paginated, theme),
              ],
            ),
          ),
        ),
        if (totalPages > 1)
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
                Text('Page ${_currentPage + 1} / $totalPages'),
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
    );
  }

  Widget _buildDesktopTable(List<Staff> staffData, ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 1100),
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(
            Color(0xFF6366F1).withOpacity(0.08),
          ),
          dataRowColor: MaterialStateProperty.all(Colors.transparent),
          columns: [
            DataColumn(
              label: Text(
                'Nom',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Rôle',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Classes',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Cours',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Actions',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          rows: staffData.map((staff) {
            return DataRow(
              cells: [
                DataCell(
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Color(0xFF6366F1),
                        backgroundImage:
                            staff.photoPath != null &&
                                staff.photoPath!.isNotEmpty
                            ? FileImage(File(staff.photoPath!))
                            : null,
                        child:
                            staff.photoPath == null || staff.photoPath!.isEmpty
                            ? Text(
                                _getInitials(staff.name),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                      ),
                      SizedBox(width: 8),
                      Text(
                        staff.name,
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Color(0xFF6366F1).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      staff.role,
                      style: TextStyle(
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 180,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 6,
                        children: staff.classes
                            .map(
                              (c) => Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Color(0xFF6366F1).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  c,
                                  style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 180,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 6,
                        children: staff.courses
                            .map(
                              (c) => Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Color(0xFF6366F1).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  c,
                                  style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
                DataCell(_buildActionsMenu(staff)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTabletTable(List<Staff> staffData, ThemeData theme) {
    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: staffData.length,
      itemBuilder: (context, index) {
        final staff = staffData[index];
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.name,
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      staff.role,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  staff.department,
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color,
                    fontSize: 12,
                  ),
                ),
              ),
              _buildStatusChip(staff.status),
              SizedBox(width: 8),
              _buildActionButton(staff),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileCards(List<Staff> staffData, ThemeData theme) {
    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: staffData.length,
      itemBuilder: (context, index) {
        final staff = staffData[index];
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: Color(0xFF6366F1),
              backgroundImage:
                  staff.photoPath != null && staff.photoPath!.isNotEmpty
                  ? FileImage(File(staff.photoPath!))
                  : null,
              child: staff.photoPath == null || staff.photoPath!.isEmpty
                  ? Text(
                      _getInitials(staff.name),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            title: Text(
              staff.name,
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              staff.role,
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            trailing: _buildStatusChip(staff.status),
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInfoRow('Département', staff.department, theme),
                    _buildInfoRow(
                      'Cours Assignés',
                      staff.courses.join(', '),
                      theme,
                    ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildActionButton(staff),
                        ElevatedButton.icon(
                          onPressed: () => _showAddEditStaffDialog(staff),
                          icon: Icon(Icons.edit, size: 16),
                          label: Text('Modifier'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.bold,
              ),
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

  Widget _buildStatusChip(String status) {
    Color gradientStart;
    Color gradientEnd;
    IconData icon;
    switch (status.toLowerCase()) {
      case 'actif':
        gradientStart = const Color(0xFF10B981);
        gradientEnd = const Color(0xFF34D399);
        icon = Icons.check_circle;
        break;
      case 'en congé':
        gradientStart = const Color(0xFFF59E0B);
        gradientEnd = const Color(0xFFFBBF24);
        icon = Icons.pause_circle;
        break;
      default:
        gradientStart = const Color(0xFFE53E3E);
        gradientEnd = const Color(0xFFF87171);
        icon = Icons.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white, semanticLabel: status),
          const SizedBox(width: 4),
          Text(
            status,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(Staff staff) {
    return ElevatedButton.icon(
      onPressed: () => _showStaffDetailsDialog(staff),
      icon: Icon(Icons.visibility, size: 16),
      label: Text('Détails'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.cyan,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildActionsMenu(Staff staff) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'details') {
          _showStaffDetailsDialog(staff);
        } else if (value == 'edit') {
          _showAddEditStaffDialog(staff);
        } else if (value == 'export') {
          _exportIndividualStaff(staff);
        } else if (value == 'delete') {
          final confirm = await showDangerConfirmDialog(
            context,
            title: 'Supprimer ce membre ?',
            message:
                '“${staff.name}” sera supprimé. Cette action est irréversible.',
          );
          if (confirm == true) {
            try {
              await _dbService.deleteStaff(staff.id);
              await _loadStaff();
              // Notification de succès pour la suppression
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Personnel supprimé avec succès !'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            } catch (e) {
              // Notification d'erreur pour la suppression
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Erreur lors de la suppression : ${e.toString()}',
                    ),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            }
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'details', child: Text('Détails')),
        PopupMenuItem(value: 'edit', child: Text('Modifier')),
        PopupMenuItem(value: 'export', child: Text('Exporter')),
        PopupMenuItem(
          value: 'delete',
          child: Text('Supprimer', style: TextStyle(color: Colors.red)),
        ),
      ],
      icon: Icon(Icons.more_vert, color: Color(0xFF6366F1)),
    );
  }

  String _displayStaffName(Staff staff) {
    final last = (staff.lastName ?? '').trim();
    final first = (staff.firstName ?? '').trim();
    if (last.isNotEmpty || first.isNotEmpty) {
      return [last, first].where((e) => e.isNotEmpty).join(' ');
    }
    return staff.name.trim();
  }

  Future<void> _showStaffDetailsDialog(Staff staff) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StaffDetailsDialog(
        staff: staff,
        dbService: _dbService,
        displayStaffName: _displayStaffName,
        onEdit: () async {
          Navigator.of(ctx).pop();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          _showAddEditStaffDialog(staff);
        },
        onChanged: () async {
          await _loadStaff();
        },
      ),
    );
  }

  void _showAddCourseDialog() {
    final _formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.book, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text(
              'Ajouter un cours',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomFormField(
                controller: nameController,
                labelText: 'Nom du cours',
                hintText: 'Ex: Mathématiques',
                validator: (v) =>
                    v == null || v.isEmpty ? 'Champ requis' : null,
              ),
              CustomFormField(
                controller: descController,
                labelText: 'Description (optionnelle)',
                hintText: 'Ex: Cours de base, avancé...',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                final name = nameController.text.trim();
                final desc = descController.text.trim();
                if (_allCourses.where((c) => c.name == name).isEmpty) {
                  final course = Course(
                    id: const Uuid().v4(),
                    name: name,
                    description: desc.isNotEmpty ? desc : null,
                  );
                  await _dbService.insertCourse(course);
                  await _loadCourses();
                  Navigator.of(context).pop();
                  // Utiliser une alerte simple car on peut ne pas avoir de Scaffold ici
                  await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Succès'),
                      content: const Text('Cours ajouté !'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                } else {
                  await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Information'),
                      content: const Text('Ce cours existe déjà.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            child: Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  void _showAddEditStaffDialog(Staff? staff) async {
    final isEdit = staff != null;
    final _formKey = GlobalKey<FormState>();

    // Controllers pour les informations personnelles
    final nameController = TextEditingController(text: staff?.name ?? '');
    final firstNameController = TextEditingController(
      text: staff?.firstName ?? '',
    );
    final lastNameController = TextEditingController(
      text: staff?.lastName ?? '',
    );

    // Fonction pour mettre à jour le nom complet automatiquement
    void updateFullName() {
      final firstName = firstNameController.text.trim();
      final lastName = lastNameController.text.trim();
      if (firstName.isNotEmpty && lastName.isNotEmpty) {
        nameController.text = '$firstName $lastName';
      } else if (firstName.isNotEmpty) {
        nameController.text = firstName;
      } else if (lastName.isNotEmpty) {
        nameController.text = lastName;
      } else {
        nameController.text = '';
      }
    }

    // Ajouter des listeners pour la mise à jour automatique
    firstNameController.addListener(updateFullName);
    lastNameController.addListener(updateFullName);

    // Initialiser le nom complet si on est en mode édition
    if (isEdit && staff != null) {
      updateFullName();
    }
    final phoneController = TextEditingController(text: staff?.phone ?? '');
    final emailController = TextEditingController(text: staff?.email ?? '');
    final birthPlaceController = TextEditingController(
      text: staff?.birthPlace ?? '',
    );
    final nationalityController = TextEditingController(
      text: staff?.nationality ?? '',
    );
    final addressController = TextEditingController(text: staff?.address ?? '');

    // Controllers pour les informations administratives
    final matriculeController = TextEditingController(
      text: staff?.matricule ?? '',
    );
    final idNumberController = TextEditingController(
      text: staff?.idNumber ?? '',
    );
    final socialSecurityController = TextEditingController(
      text: staff?.socialSecurityNumber ?? '',
    );
    final numberOfChildrenController = TextEditingController(
      text: staff?.numberOfChildren?.toString() ?? '',
    );

    // Controllers pour les informations professionnelles
    String? selectedRole = staff?.typeRole ?? null;
    final roleDescriptionController = TextEditingController(
      text:
          staff != null &&
              staff.role != 'Professeur' &&
              staff.role != 'Administration'
          ? staff.role
          : '',
    );
    final departmentController = TextEditingController(
      text: staff?.department ?? '',
    );
    final highestDegreeController = TextEditingController(
      text: staff?.highestDegree ?? '',
    );
    final specialtyController = TextEditingController(
      text: staff?.specialty ?? '',
    );
    final experienceYearsController = TextEditingController(
      text: staff?.experienceYears?.toString() ?? '',
    );
    final previousInstitutionController = TextEditingController(
      text: staff?.previousInstitution ?? '',
    );
    final qualificationsController = TextEditingController(
      text: staff?.qualifications ?? '',
    );

    // Controllers pour les informations contractuelles
    final baseSalaryController = TextEditingController(
      text: staff?.baseSalary?.toString() ?? '',
    );
    final weeklyHoursController = TextEditingController(
      text: staff?.weeklyHours?.toString() ?? '',
    );
    final supervisorController = TextEditingController(
      text: staff?.supervisor ?? '',
    );

    // Variables d'état
    String? gender = staff?.gender;
    DateTime? birthDate = staff?.birthDate;
    String? maritalStatus = staff?.maritalStatus;
    String? region = staff?.region;
    List<String> selectedLevels = List<String>.from(staff?.levels ?? []);
    String? contractType = staff?.contractType;
    DateTime? retirementDate = staff?.retirementDate;
    String? photoPath = staff?.photoPath;
    List<String> documents = List<String>.from(staff?.documents ?? []);

    final statusList = ['Actif', 'En congé', 'Inactif'];
    String status = staff?.status ?? 'Actif';
    DateTime hireDate = staff?.hireDate ?? DateTime.now();
    List<_TeacherAssignmentDraft> assignmentDrafts = [];
    List<Course> allCourses = List<Course>.from(_allCourses);
    List<Class> allClasses = [];
    bool loadingClasses = true;
    bool didInitAssignments = false;
    String? selectedAssignmentClassKey;
    Course? selectedAssignmentCourse;
    String currentAcademicYear = '';
    String classKey(Class cls) => '${cls.name}|${cls.academicYear}';
    final roleList = [
      'Professeur',
      'Instituteur',
      'Surveillant',
      'Administration',
    ];
    final genderList = ['Masculin', 'Féminin'];
    final maritalStatusList = [
      'Célibataire',
      'Marié(e)',
      'Divorcé(e)',
      'Veuf/Veuve',
    ];
    final regionList = ['Kara', 'Maritime', 'Plateaux', 'Centrale', 'Savanes'];
    final contractTypeList = ['CDI', 'CDD', 'Vacataire', 'Permanent'];
    final levelList = [
      'Maternelle',
      'CP',
      'CE1',
      'CE2',
      'CM1',
      'CM2',
      '6ème',
      '5ème',
      '4ème',
      '3ème',
      '2nde',
      '1ère',
      'Tle',
    ];
    Future<void> doSubmit() async {
      if (_formKey.currentState!.validate()) {
        try {
          final derivedCourses = assignmentDrafts.isEmpty && staff != null
              ? List<String>.from(staff!.courses)
              : assignmentDrafts.map((a) => a.courseName).toSet().toList();
          final derivedClasses = assignmentDrafts.isEmpty && staff != null
              ? List<String>.from(staff!.classes)
              : assignmentDrafts.map((a) => a.className).toSet().toList();
          final newStaff = Staff(
            id: staff?.id ?? const Uuid().v4(),
            name: nameController.text.trim(),
            role: roleDescriptionController.text.trim(),
            typeRole: selectedRole ?? 'Administration',
            department: departmentController.text.trim(),
            phone: phoneController.text.trim(),
            email: emailController.text.trim(),
            qualifications: qualificationsController.text.trim(),
            courses: derivedCourses,
            classes: derivedClasses,
            status: status,
            hireDate: hireDate,
            // Informations personnelles
            firstName: firstNameController.text.trim().isNotEmpty
                ? firstNameController.text.trim()
                : null,
            lastName: lastNameController.text.trim().isNotEmpty
                ? lastNameController.text.trim()
                : null,
            gender: gender,
            birthDate: birthDate,
            birthPlace: birthPlaceController.text.trim().isNotEmpty
                ? birthPlaceController.text.trim()
                : null,
            nationality: nationalityController.text.trim().isNotEmpty
                ? nationalityController.text.trim()
                : null,
            address: addressController.text.trim().isNotEmpty
                ? addressController.text.trim()
                : null,
            photoPath: photoPath,
            // Informations administratives
            matricule: matriculeController.text.trim().isNotEmpty
                ? matriculeController.text.trim()
                : null,
            idNumber: idNumberController.text.trim().isNotEmpty
                ? idNumberController.text.trim()
                : null,
            socialSecurityNumber:
                socialSecurityController.text.trim().isNotEmpty
                ? socialSecurityController.text.trim()
                : null,
            maritalStatus: maritalStatus,
            numberOfChildren: numberOfChildrenController.text.trim().isNotEmpty
                ? int.tryParse(numberOfChildrenController.text.trim())
                : null,
            // Informations professionnelles
            region: region,
            levels: selectedLevels.isNotEmpty ? selectedLevels : null,
            highestDegree: highestDegreeController.text.trim().isNotEmpty
                ? highestDegreeController.text.trim()
                : null,
            specialty: specialtyController.text.trim().isNotEmpty
                ? specialtyController.text.trim()
                : null,
            experienceYears: experienceYearsController.text.trim().isNotEmpty
                ? int.tryParse(experienceYearsController.text.trim())
                : null,
            previousInstitution:
                previousInstitutionController.text.trim().isNotEmpty
                ? previousInstitutionController.text.trim()
                : null,
            // Informations contractuelles
            contractType: contractType,
            baseSalary: baseSalaryController.text.trim().isNotEmpty
                ? double.tryParse(baseSalaryController.text.trim())
                : null,
            weeklyHours: weeklyHoursController.text.trim().isNotEmpty
                ? int.tryParse(weeklyHoursController.text.trim())
                : null,
            supervisor: supervisorController.text.trim().isNotEmpty
                ? supervisorController.text.trim()
                : null,
            retirementDate: retirementDate,
            // Documents
            documents: documents.isNotEmpty ? documents : null,
          );
          if (isEdit) {
            await _dbService.updateStaff(newStaff.id, newStaff);
            // Notification de succès pour la modification
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Personnel modifié avec succès !'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          } else {
            await _dbService.insertStaff(newStaff);
            // Notification de succès pour l'ajout
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Personnel ajouté avec succès !'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
          if (currentAcademicYear.isNotEmpty) {
            final assignments = assignmentDrafts
                .map(
                  (a) => TeacherAssignment(
                    id: const Uuid().v4(),
                    teacherId: newStaff.id,
                    courseId: a.courseId,
                    className: a.className,
                    academicYear: a.academicYear,
                  ),
                )
                .toList();
            await _dbService.replaceTeacherAssignmentsForTeacherYear(
              teacherId: newStaff.id,
              academicYear: currentAcademicYear,
              assignments: assignments,
            );
          }
          await _loadStaff();
          if (context.mounted) Navigator.of(context).pop();
        } catch (e) {
          // Notification d'erreur
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erreur lors de la sauvegarde : ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }

    await showDialog(
      context: context,
      builder: (context) {
        if (!didInitAssignments) {
          didInitAssignments = true;
          _dbService.getClasses().then((classes) async {
            final currentYear = await getCurrentAcademicYear();
            currentAcademicYear = currentYear;
            allClasses = classes
                .where((c) => c.academicYear == currentYear)
                .toList();
            if (staff != null && staff.id.isNotEmpty) {
              final existingAssignments = await _dbService
                  .getTeacherAssignmentsForTeacher(
                    staff.id,
                    academicYear: currentYear,
                  );
              final courseById = {for (final c in allCourses) c.id: c};
              assignmentDrafts = existingAssignments
                  .map(
                    (a) => _TeacherAssignmentDraft(
                      courseId: a.courseId,
                      courseName: courseById[a.courseId]?.name ?? a.courseId,
                      className: a.className,
                      academicYear: a.academicYear,
                    ),
                  )
                  .toList();
            }
            loadingClasses = false;
            (context as Element).markNeedsBuild();
          });
        }
        return StatefulBuilder(
          builder: (context, setState) {
            return CustomDialog(
              title: isEdit ? 'Modifier le membre' : 'Ajouter un membre',
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section Photo et Nom principal
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFF6366F1).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Color(0xFF6366F1).withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Photo upload section
                            GestureDetector(
                              onTap: () => _showPhotoPicker(
                                setState,
                                photoPath,
                                (newPath) =>
                                    setState(() => photoPath = newPath),
                              ),
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Color(0xFF6366F1).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(40),
                                  border: Border.all(
                                    color: Color(0xFF6366F1),
                                    width: 2,
                                  ),
                                ),
                                child: photoPath != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(40),
                                        child: Image.file(
                                          File(photoPath!),
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Icon(
                                                    Icons.person,
                                                    size: 40,
                                                    color: Color(0xFF6366F1),
                                                  ),
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.camera_alt,
                                            color: Color(0xFF6366F1),
                                            size: 24,
                                          ),
                                          Text(
                                            'Photo',
                                            style: TextStyle(
                                              color: Color(0xFF6366F1),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            SizedBox(width: 16),
                            // Name field
                            Expanded(
                              child: CustomFormField(
                                controller: nameController,
                                labelText: 'Nom complet',
                                hintText: 'Entrez le nom complet',
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Champ requis'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),

                      // Section 1: Informations personnelles
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '🔹 Informations personnelles',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  controller: firstNameController,
                                  labelText: 'Prénoms',
                                  hintText: 'Entrez les prénoms',
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  controller: lastNameController,
                                  labelText: 'Nom de famille',
                                  hintText: 'Entrez le nom de famille',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  isDropdown: true,
                                  labelText: 'Sexe',
                                  dropdownItems: genderList,
                                  dropdownValue: gender,
                                  onDropdownChanged: (val) =>
                                      setState(() => gender = val),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: birthDate ?? DateTime(1990),
                                      firstDate: DateTime(1950),
                                      lastDate: DateTime.now(),
                                    );
                                    if (picked != null)
                                      setState(() => birthDate = picked);
                                  },
                                  child: AbsorbPointer(
                                    child: CustomFormField(
                                      controller: TextEditingController(
                                        text: birthDate != null
                                            ? DateFormat(
                                                'dd/MM/yyyy',
                                              ).format(birthDate!)
                                            : '',
                                      ),
                                      labelText: 'Date de naissance',
                                      hintText: 'Sélectionnez la date',
                                      readOnly: true,
                                      suffixIcon: Icons.calendar_today,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  controller: birthPlaceController,
                                  labelText: 'Lieu de naissance',
                                  hintText: 'Ex: Lomé, Togo',
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  controller: nationalityController,
                                  labelText: 'Nationalité',
                                  hintText: 'Ex: Togolaise',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          CustomFormField(
                            controller: addressController,
                            labelText: 'Adresse complète',
                            hintText: 'Ville, quartier, pays',
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  controller: phoneController,
                                  labelText: 'Téléphone',
                                  hintText: 'Ex: +228 90 00 00 00',
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Champ requis'
                                      : null,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  controller: emailController,
                                  labelText: 'Email',
                                  hintText: 'exemple@ecole.fr',
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Champ requis';
                                    if (!RegExp(
                                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                    ).hasMatch(v)) {
                                      return 'Email invalide';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 20),

                      // Section 2: Informations administratives
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '🔹 Informations administratives',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  controller: matriculeController,
                                  labelText: 'Matricule enseignant',
                                  hintText: 'Ex: MAT001234',
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  controller: idNumberController,
                                  labelText: 'Numéro CNI / Passeport',
                                  hintText: 'Ex: 1234567890',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  controller: socialSecurityController,
                                  labelText: 'Numéro de sécurité sociale',
                                  hintText: 'Si applicable',
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  isDropdown: true,
                                  labelText: 'Situation matrimoniale',
                                  dropdownItems: maritalStatusList,
                                  dropdownValue: maritalStatus,
                                  onDropdownChanged: (val) =>
                                      setState(() => maritalStatus = val),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          CustomFormField(
                            controller: numberOfChildrenController,
                            labelText: 'Nombre d\'enfants (optionnel)',
                            hintText: 'Ex: 2',
                          ),
                        ],
                      ),
                      SizedBox(height: 20),

                      // Section 3: Informations professionnelles
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '🔹 Informations professionnelles',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  isDropdown: true,
                                  labelText: 'Poste occupé',
                                  dropdownItems: roleList,
                                  dropdownValue: selectedRole,
                                  onDropdownChanged: (val) =>
                                      setState(() => selectedRole = val),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Champ requis'
                                      : null,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  isDropdown: true,
                                  labelText: 'Région d\'affectation',
                                  dropdownItems: regionList,
                                  dropdownValue: region,
                                  onDropdownChanged: (val) =>
                                      setState(() => region = val),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          if (selectedRole == 'Professeur')
                            CustomFormField(
                              controller: roleDescriptionController,
                              labelText: 'Professeur de…',
                              hintText: 'Ex: Professeur de Sciences',
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Champ requis'
                                  : null,
                            ),
                          if (selectedRole == 'Instituteur')
                            CustomFormField(
                              controller: roleDescriptionController,
                              labelText: 'Instituteur de…',
                              hintText: 'Ex: Instituteur de CM2',
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Champ requis'
                                  : null,
                            ),
                          if (selectedRole == 'Surveillant')
                            CustomFormField(
                              controller: roleDescriptionController,
                              labelText: 'Surveillant de…',
                              hintText: 'Ex: Surveillant général',
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Champ requis'
                                  : null,
                            ),
                          if (selectedRole == 'Administration')
                            CustomFormField(
                              controller: roleDescriptionController,
                              labelText: 'Fonction administrative',
                              hintText: 'Ex: Directeur, Secrétaire, Comptable…',
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Champ requis'
                                  : null,
                            ),
                          SizedBox(height: 12),
                          CustomFormField(
                            controller: departmentController,
                            labelText: 'Département / Matière(s) enseignée(s)',
                            hintText: 'Ex: Mathématiques, Sciences Physiques',
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Niveau(x) enseigné(s)',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: levelList
                                .map(
                                  (level) => FilterChip(
                                    label: Text(level),
                                    selected: selectedLevels.contains(level),
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          selectedLevels.add(level);
                                        } else {
                                          selectedLevels.remove(level);
                                        }
                                      });
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  controller: highestDegreeController,
                                  labelText: 'Diplôme le plus élevé',
                                  hintText: 'Ex: Master, Licence, BAC+5',
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  controller: specialtyController,
                                  labelText: 'Spécialité / Domaine',
                                  hintText: 'Ex: Mathématiques, Physique',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  controller: experienceYearsController,
                                  labelText:
                                      'Expérience professionnelle (années)',
                                  hintText: 'Ex: 5',
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  controller: previousInstitutionController,
                                  labelText: 'Ancienne école / Institution',
                                  hintText: 'Ex: Lycée de Lomé',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          CustomFormField(
                            controller: qualificationsController,
                            labelText: 'Qualifications supplémentaires',
                            hintText: 'Formations, certifications...',
                          ),
                        ],
                      ),
                      SizedBox(height: 20),

                      // Section 4: Informations contractuelles
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '🔹 Informations contractuelles et ancienneté',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  isDropdown: true,
                                  labelText: 'Statut',
                                  dropdownItems: statusList,
                                  dropdownValue: status,
                                  onDropdownChanged: (val) =>
                                      setState(() => status = val ?? 'Actif'),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  isDropdown: true,
                                  labelText: 'Type de contrat',
                                  dropdownItems: contractTypeList,
                                  dropdownValue: contractType,
                                  onDropdownChanged: (val) =>
                                      setState(() => contractType = val),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: hireDate,
                                      firstDate: DateTime(1980),
                                      lastDate: DateTime.now(),
                                    );
                                    if (picked != null)
                                      setState(() => hireDate = picked);
                                  },
                                  child: AbsorbPointer(
                                    child: CustomFormField(
                                      controller: TextEditingController(
                                        text: DateFormat(
                                          'dd/MM/yyyy',
                                        ).format(hireDate),
                                      ),
                                      labelText: "Date d'embauche",
                                      hintText: 'Sélectionnez la date',
                                      readOnly: true,
                                      suffixIcon: Icons.calendar_today,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          retirementDate ?? DateTime(2030),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime(2050),
                                    );
                                    if (picked != null)
                                      setState(() => retirementDate = picked);
                                  },
                                  child: AbsorbPointer(
                                    child: CustomFormField(
                                      controller: TextEditingController(
                                        text: retirementDate != null
                                            ? DateFormat(
                                                'dd/MM/yyyy',
                                              ).format(retirementDate!)
                                            : '',
                                      ),
                                      labelText: 'Date de départ à la retraite',
                                      hintText: 'Prévisionnelle',
                                      readOnly: true,
                                      suffixIcon: Icons.calendar_today,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: CustomFormField(
                                  controller: baseSalaryController,
                                  labelText: 'Salaire de base',
                                  hintText: 'Ex: 150000',
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: CustomFormField(
                                  controller: weeklyHoursController,
                                  labelText: 'Heures de cours hebdomadaires',
                                  hintText: 'Ex: 20',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          CustomFormField(
                            controller: supervisorController,
                            labelText: 'Responsable hiérarchique',
                            hintText: 'Ex: Directeur des études',
                          ),
                        ],
                      ),
                      SizedBox(height: 20),

                      // Section 5: Documents
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '🔹 Documents à joindre',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            'Documents à joindre',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children:
                                [
                                      'Copie pièce d\'identité',
                                      'Diplômes / Attestations',
                                      'CV',
                                      'Photo d\'identité',
                                      'Certificat médical',
                                    ]
                                    .map(
                                      (doc) => FilterChip(
                                        label: Text(doc),
                                        selected: documents.contains(doc),
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              documents.add(doc);
                                            } else {
                                              documents.remove(doc);
                                            }
                                          });
                                        },
                                      ),
                                    )
                                    .toList(),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),

                      // Section 6: Cours et Classes
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '🔹 Affectations',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            'Affectations matière + classe',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          SizedBox(height: 8),
                          loadingClasses
                              ? Center(child: CircularProgressIndicator())
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      value: selectedAssignmentClassKey,
                                      decoration: InputDecoration(
                                        labelText:
                                            'Classe (${currentAcademicYear.isEmpty ? 'année en cours' : currentAcademicYear})',
                                      ),
                                      items: allClasses
                                          .map(
                                            (cls) => DropdownMenuItem<String>(
                                              value: classKey(cls),
                                              child: Text(
                                                '${cls.name} (${cls.academicYear})',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          selectedAssignmentClassKey = value;
                                        });
                                      },
                                    ),
                                    SizedBox(height: 12),
                                    DropdownButtonFormField<Course>(
                                      value: selectedAssignmentCourse,
                                      decoration: InputDecoration(
                                        labelText: 'Matière',
                                      ),
                                      items: allCourses
                                          .map(
                                            (course) =>
                                                DropdownMenuItem<Course>(
                                                  value: course,
                                                  child: Text(course.name),
                                                ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          selectedAssignmentCourse = value;
                                        });
                                      },
                                    ),
                                    SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.add),
                                        label: Text('Ajouter l\'affectation'),
                                        onPressed: () {
                                          final messenger =
                                              ScaffoldMessenger.of(
                                                this.context,
                                              );
                                          debugPrint(
                                            '[StaffPage] Add assignment click: classKey=$selectedAssignmentClassKey course=${selectedAssignmentCourse?.id}',
                                          );
                                          final clsKey =
                                              selectedAssignmentClassKey;
                                          final course =
                                              selectedAssignmentCourse;
                                          if (clsKey == null ||
                                              course == null) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Sélectionnez une classe et une matière.',
                                                ),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                            return;
                                          }
                                          final cls = allClasses.firstWhere(
                                            (c) => classKey(c) == clsKey,
                                            orElse: () => Class.empty(),
                                          );
                                          if (cls.name.isEmpty) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Classe introuvable.',
                                                ),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                            return;
                                          }
                                          final exists = assignmentDrafts.any(
                                            (a) =>
                                                a.className == cls.name &&
                                                a.academicYear ==
                                                    cls.academicYear &&
                                                a.courseId == course.id,
                                          );
                                          if (exists) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Cette affectation existe déjà.',
                                                ),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                            return;
                                          }
                                          setState(() {
                                            assignmentDrafts.add(
                                              _TeacherAssignmentDraft(
                                                courseId: course.id,
                                                courseName: course.name,
                                                className: cls.name,
                                                academicYear: cls.academicYear,
                                              ),
                                            );
                                          });
                                          debugPrint(
                                            '[StaffPage] assignmentDrafts=${assignmentDrafts.length}',
                                          );
                                        },
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    if (assignmentDrafts.isEmpty)
                                      Text(
                                        'Aucune affectation définie.',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                        ),
                                      )
                                    else
                                      Column(
                                        children: assignmentDrafts
                                            .map(
                                              (a) => ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(
                                                  '${a.className} • ${a.courseName}',
                                                ),
                                                subtitle: Text(a.academicYear),
                                                trailing: IconButton(
                                                  icon: Icon(Icons.delete),
                                                  onPressed: () {
                                                    showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text(
                                                          'Supprimer l\'affectation ?',
                                                        ),
                                                        content: Text(
                                                          'Voulez-vous retirer "${a.courseName}" de ${a.className} (${a.academicYear}) ?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(false),
                                                            child: const Text(
                                                              'Annuler',
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  ctx,
                                                                ).pop(true),
                                                            child: const Text(
                                                              'Supprimer',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ).then((confirmed) {
                                                      if (confirmed == true) {
                                                        setState(() {
                                                          assignmentDrafts
                                                              .remove(a);
                                                        });
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                  ],
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              onSubmit: () async => doSubmit(),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                if (isEdit)
                  TextButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Supprimer ce membre ?'),
                          content: const Text('Cette action est irréversible.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Annuler'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('Supprimer'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _dbService.deleteStaff(staff!.id);
                        await _loadStaff();
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                    child: const Text(
                      'Supprimer',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () async => doSubmit(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isEdit ? 'Modifier' : 'Ajouter'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPhotoPicker(
    StateSetter setState,
    String? currentPhotoPath,
    Function(String?) updatePhotoPath,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sélectionner une photo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt),
              title: Text('Prendre une photo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.camera, setState, updatePhotoPath);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('Choisir depuis la galerie'),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(
                  ImageSource.gallery,
                  setState,
                  updatePhotoPath,
                );
              },
            ),
            if (currentPhotoPath != null)
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Supprimer la photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  updatePhotoPath(null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(
    ImageSource source,
    StateSetter setState,
    Function(String?) updatePhotoPath,
  ) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        // Sauvegarder l'image dans le dossier de l'application
        final String fileName =
            'staff_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String staffPhotosDir = path.join(appDir.path, 'staff_photos');

        // Créer le dossier s'il n'existe pas
        await Directory(staffPhotosDir).create(recursive: true);

        final String newPath = path.join(staffPhotosDir, fileName);
        final File newFile = await File(image.path).copy(newPath);

        updatePhotoPath(newFile.path);

        // Afficher un message de succès
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Photo sélectionnée avec succès'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Erreur lors de la sélection de la photo: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sélection de la photo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportStaffToPdf() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) {
      // Notification d'annulation
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export annulé'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Charger les informations de l'école
    final schoolInfo = await _dbService.getSchoolInfo();
    if (schoolInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informations de l\'école non disponibles. Veuillez configurer les informations de l\'école dans les paramètres.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String currentAcademicYear = await getCurrentAcademicYear();
    final filteredStaff = _staffList.where((staff) {
      final query = _searchQuery;
      final tab = _selectedRoleTab;
      bool matchRole = true;
      if (tab == 'Personnel Enseignant') {
        matchRole = staff.typeRole == 'Professeur';
      } else if (tab == 'Personnel Administratif') {
        matchRole = staff.typeRole == 'Administration';
      }
      if (query.isEmpty) return matchRole;
      return matchRole &&
          (staff.name.toLowerCase().contains(query) ||
              staff.id.toLowerCase().contains(query));
    }).toList();

    final bytes = await PdfService.generateStaffPdf(
      schoolInfo: schoolInfo,
      academicYear: currentAcademicYear,
      staffList: filteredStaff,
      title: 'Liste du Personnel - Année $currentAcademicYear',
    );

    final fileName =
        'liste_du_personnel_${currentAcademicYear.replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(bytes);
    OpenFile.open(file.path);

    // Notification de succès
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF réussi ! Fichier sauvegardé : $fileName'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _exportIndividualStaff(Staff staff) async {
    // Afficher un dialog pour choisir le format d'export
    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Exporter ${staff.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.picture_as_pdf, color: Colors.red),
              title: Text('Exporter en PDF'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: Icon(Icons.grid_on, color: Colors.green),
              title: Text('Exporter en Excel'),
              onTap: () => Navigator.pop(context, 'excel'),
            ),
          ],
        ),
      ),
    );

    if (format == null) return;

    if (format == 'pdf') {
      await _exportIndividualStaffToPdf(staff);
    } else if (format == 'excel') {
      await _exportIndividualStaffToExcel(staff);
    }
  }

  Future<void> _exportIndividualStaffToPdf(Staff staff) async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) {
      // Notification d'annulation
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export annulé'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Charger les informations de l'école
    final schoolInfo = await _dbService.getSchoolInfo();
    if (schoolInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informations de l\'école non disponibles. Veuillez configurer les informations de l\'école dans les paramètres.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String currentAcademicYear = await getCurrentAcademicYear();

    final bytes = await PdfService.generateIndividualStaffPdf(
      schoolInfo: schoolInfo,
      academicYear: currentAcademicYear,
      staff: staff,
      title: 'Fiche individuelle - ${staff.name}',
    );

    final fileName =
        'fiche_${staff.name.replaceAll(' ', '_')}_${currentAcademicYear.replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(bytes);
    OpenFile.open(file.path);

    // Notification de succès
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fiche PDF de ${staff.name} exportée avec succès !'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _exportIndividualStaffToExcel(Staff staff) async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) {
      // Notification d'annulation
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export annulé'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Fiche Individuelle'];

    // Headers
    sheetObject.appendRow([
      TextCellValue('Informations'),
      TextCellValue('Détails'),
    ]);

    // Données du professeur
    final data = [
      ['Nom complet', staff.name],
      ['Prénoms', staff.firstName ?? ''],
      ['Nom de famille', staff.lastName ?? ''],
      ['Sexe', staff.gender ?? ''],
      [
        'Date de naissance',
        staff.birthDate != null
            ? DateFormat('dd/MM/yyyy').format(staff.birthDate!)
            : '',
      ],
      ['Lieu de naissance', staff.birthPlace ?? ''],
      ['Nationalité', staff.nationality ?? ''],
      ['Adresse', staff.address ?? ''],
      ['Téléphone', staff.phone],
      ['Email', staff.email],
      ['Poste', staff.typeRole],
      ['Rôle détaillé', staff.role],
      ['Région', staff.region ?? ''],
      ['Département', staff.department],
      ['Niveaux enseignés', staff.levels?.join(', ') ?? ''],
      ['Diplôme', staff.highestDegree ?? ''],
      ['Spécialité', staff.specialty ?? ''],
      ['Expérience (années)', staff.experienceYears?.toString() ?? ''],
      ['Ancienne école', staff.previousInstitution ?? ''],
      ['Qualifications', staff.qualifications],
      ['Matricule', staff.matricule ?? ''],
      ['CNI/Passeport', staff.idNumber ?? ''],
      ['Sécurité sociale', staff.socialSecurityNumber ?? ''],
      ['Situation matrimoniale', staff.maritalStatus ?? ''],
      ['Nombre d\'enfants', staff.numberOfChildren?.toString() ?? ''],
      ['Statut', staff.status],
      ['Type de contrat', staff.contractType ?? ''],
      ['Date d\'embauche', DateFormat('dd/MM/yyyy').format(staff.hireDate)],
      ['Salaire de base', staff.baseSalary?.toString() ?? ''],
      ['Heures hebdomadaires', staff.weeklyHours?.toString() ?? ''],
      ['Responsable', staff.supervisor ?? ''],
      [
        'Date de retraite',
        staff.retirementDate != null
            ? DateFormat('dd/MM/yyyy').format(staff.retirementDate!)
            : '',
      ],
      ['Cours assignés', staff.courses.join(', ')],
      ['Classes assignées', staff.classes.join(', ')],
      ['Documents', staff.documents?.join(', ') ?? ''],
    ];

    for (var row in data) {
      sheetObject.appendRow([TextCellValue(row[0]), TextCellValue(row[1])]);
    }

    final String currentAcademicYear = await getCurrentAcademicYear();
    final fileName =
        'fiche_${staff.name.replaceAll(' ', '_')}_${currentAcademicYear.replaceAll('/', '_')}.xlsx';
    final file = File('$directory/$fileName');
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
      OpenFile.open(file.path);

      // Notification de succès
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fiche Excel de ${staff.name} exportée avec succès !',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Notification d'erreur
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'export Excel de ${staff.name}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _exportStaffToExcel() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) {
      // Notification d'annulation
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export annulé'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Personnel'];

    // Headers
    sheetObject.appendRow([
      TextCellValue('Nom'),
      TextCellValue('Prénoms'),
      TextCellValue('Nom de famille'),
      TextCellValue('Sexe'),
      TextCellValue('Date de naissance'),
      TextCellValue('Lieu de naissance'),
      TextCellValue('Nationalité'),
      TextCellValue('Adresse'),
      TextCellValue('Téléphone'),
      TextCellValue('Email'),
      TextCellValue('Poste'),
      TextCellValue('Rôle détaillé'),
      TextCellValue('Région'),
      TextCellValue('Département'),
      TextCellValue('Niveaux enseignés'),
      TextCellValue('Diplôme'),
      TextCellValue('Spécialité'),
      TextCellValue('Expérience (années)'),
      TextCellValue('Ancienne école'),
      TextCellValue('Qualifications'),
      TextCellValue('Matricule'),
      TextCellValue('CNI/Passeport'),
      TextCellValue('Sécurité sociale'),
      TextCellValue('Situation matrimoniale'),
      TextCellValue('Nombre d\'enfants'),
      TextCellValue('Statut'),
      TextCellValue('Type de contrat'),
      TextCellValue('Date d\'embauche'),
      TextCellValue('Salaire de base'),
      TextCellValue('Heures hebdomadaires'),
      TextCellValue('Responsable'),
      TextCellValue('Date de retraite'),
      TextCellValue('Cours assignés'),
      TextCellValue('Classes assignées'),
      TextCellValue('Documents'),
    ]);

    // Add data rows
    final filteredStaff = _staffList.where((staff) {
      final query = _searchQuery;
      final tab = _selectedRoleTab;
      bool matchRole = true;
      if (tab == 'Personnel Enseignant') {
        matchRole = staff.typeRole == 'Professeur';
      } else if (tab == 'Personnel Administratif') {
        matchRole = staff.typeRole == 'Administration';
      }
      if (query.isEmpty) return matchRole;
      return matchRole &&
          (staff.name.toLowerCase().contains(query) ||
              staff.id.toLowerCase().contains(query));
    }).toList();

    for (var staff in filteredStaff) {
      sheetObject.appendRow([
        TextCellValue(staff.name),
        TextCellValue(staff.firstName ?? ''),
        TextCellValue(staff.lastName ?? ''),
        TextCellValue(staff.gender ?? ''),
        TextCellValue(
          staff.birthDate != null
              ? DateFormat('dd/MM/yyyy').format(staff.birthDate!)
              : '',
        ),
        TextCellValue(staff.birthPlace ?? ''),
        TextCellValue(staff.nationality ?? ''),
        TextCellValue(staff.address ?? ''),
        TextCellValue(staff.phone),
        TextCellValue(staff.email),
        TextCellValue(staff.typeRole),
        TextCellValue(staff.role),
        TextCellValue(staff.region ?? ''),
        TextCellValue(staff.department),
        TextCellValue(staff.levels?.join(', ') ?? ''),
        TextCellValue(staff.highestDegree ?? ''),
        TextCellValue(staff.specialty ?? ''),
        TextCellValue(staff.experienceYears?.toString() ?? ''),
        TextCellValue(staff.previousInstitution ?? ''),
        TextCellValue(staff.qualifications),
        TextCellValue(staff.matricule ?? ''),
        TextCellValue(staff.idNumber ?? ''),
        TextCellValue(staff.socialSecurityNumber ?? ''),
        TextCellValue(staff.maritalStatus ?? ''),
        TextCellValue(staff.numberOfChildren?.toString() ?? ''),
        TextCellValue(staff.status),
        TextCellValue(staff.contractType ?? ''),
        TextCellValue(DateFormat('dd/MM/yyyy').format(staff.hireDate)),
        TextCellValue(staff.baseSalary?.toString() ?? ''),
        TextCellValue(staff.weeklyHours?.toString() ?? ''),
        TextCellValue(staff.supervisor ?? ''),
        TextCellValue(
          staff.retirementDate != null
              ? DateFormat('dd/MM/yyyy').format(staff.retirementDate!)
              : '',
        ),
        TextCellValue(staff.courses.join(', ')),
        TextCellValue(staff.classes.join(', ')),
        TextCellValue(staff.documents?.join(', ') ?? ''),
      ]);
    }

    final String currentAcademicYear = await getCurrentAcademicYear();
    final fileName =
        'liste_du_personnel_${currentAcademicYear.replaceAll('/', '_')}.xlsx';
    final file = File('$directory/$fileName');
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
      OpenFile.open(file.path);

      // Notification de succès
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Export Excel réussi ! Fichier sauvegardé : $fileName',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Notification d'erreur
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'export Excel'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((n) => n.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String initials = parts.map((n) => n[0]).join();
    if (initials.length > 2) initials = initials.substring(0, 2);
    return initials.toUpperCase();
  }

  Future<void> refreshStaffFromOutside() async {
    await _loadStaff();
  }
}

class _StaffDetailsDialog extends StatefulWidget {
  const _StaffDetailsDialog({
    required this.staff,
    required this.dbService,
    required this.displayStaffName,
    required this.onEdit,
    required this.onChanged,
  });

  final Staff staff;
  final DatabaseService dbService;
  final String Function(Staff) displayStaffName;
  final Future<void> Function() onEdit;
  final Future<void> Function() onChanged;

  @override
  State<_StaffDetailsDialog> createState() => _StaffDetailsDialogState();
}

class _StaffDetailsDialogState extends State<_StaffDetailsDialog>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late Staff _staff;
  List<String> _documents = [];
  List<Map<String, dynamic>> _absences = [];
  List<Map<String, dynamic>> _auditLogs = [];
  List<Map<String, dynamic>> _timetableEntries = [];
  String _currentAcademicYear = '2024-2025';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _staff = widget.staff;
    _documents = List<String>.from(_staff.documents ?? const []);
    _tabController = TabController(length: 5, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final year = await getCurrentAcademicYear();
    final staffList = await widget.dbService.getStaff();
    final refreshed = staffList.firstWhere(
      (s) => s.id == widget.staff.id,
      orElse: () => widget.staff,
    );
    final absences = await widget.dbService.getStaffAbsences(
      staffId: widget.staff.id,
    );
    final audit = await widget.dbService.getAuditLogsForStaff(
      staffId: widget.staff.id,
    );
    final db = await widget.dbService.database;
    final tt = await db.query(
      'timetable_entries',
      where: 'teacher = ? AND academicYear = ?',
      whereArgs: [refreshed.name, year],
      orderBy: 'dayOfWeek ASC, startTime ASC',
    );
    if (!mounted) return;
    setState(() {
      _currentAcademicYear = year;
      _staff = refreshed;
      _documents = List<String>.from(refreshed.documents ?? const []);
      _absences = absences;
      _auditLogs = audit;
      _timetableEntries = tt;
      _loading = false;
    });
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '-';
    final s = iso.trim();
    if (s.isEmpty) return '-';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    return DateFormat('dd/MM/yyyy').format(d);
  }

  String _fmtDateTime(String? iso) {
    if (iso == null) return '';
    final s = iso.trim();
    if (s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  Future<void> _addDocuments() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    final docsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(
      path.join(docsDir.path, 'staff_documents', _staff.id),
    );
    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

    final newDocs = List<String>.from(_documents);
    for (final f in result.files) {
      if (f.path == null) continue;
      final src = File(f.path!);
      if (!src.existsSync()) continue;
      final baseName = path.basename(f.path!);
      var destPath = path.join(targetDir.path, baseName);
      if (File(destPath).existsSync()) {
        final stem = path.basenameWithoutExtension(baseName);
        final ext = path.extension(baseName);
        destPath = path.join(
          targetDir.path,
          '${stem}_${DateTime.now().millisecondsSinceEpoch}$ext',
        );
      }
      await src.copy(destPath);
      newDocs.add(destPath);
    }

    String? by;
    try {
      final u = await AuthService.instance.getCurrentUser();
      by = u?.displayName ?? u?.username;
    } catch (_) {}

    await widget.dbService.updateStaffDocuments(
      staffId: _staff.id,
      documents: newDocs,
      updatedBy: by,
    );
    await widget.onChanged();
    await _loadAll();
  }

  Future<void> _renameDocument(String filePath) async {
    final file = File(filePath);
    final dir = file.parent.path;
    final oldName = path.basename(filePath);
    final controller = TextEditingController(text: oldName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le document'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nouveau nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newName = controller.text.trim();
    if (newName.isEmpty || newName == oldName) return;
    final newPath = path.join(dir, newName);
    try {
      if (file.existsSync()) {
        await file.rename(newPath);
      }
      final next = _documents.map((p) => p == filePath ? newPath : p).toList();
      await widget.dbService.updateStaffDocuments(
        staffId: _staff.id,
        documents: next,
      );
      await widget.onChanged();
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _removeDocument(String filePath) async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Supprimer le document ?',
      message: 'Ce document sera retiré de la fiche personnel.',
    );
    if (ok != true) return;
    final next = List<String>.from(_documents)..remove(filePath);
    await widget.dbService.updateStaffDocuments(
      staffId: _staff.id,
      documents: next,
    );
    try {
      final f = File(filePath);
      if (f.existsSync()) {
        await f.delete();
      }
    } catch (_) {}
    await widget.onChanged();
    await _loadAll();
  }

  Future<void> _openDocument(String filePath) async {
    try {
      await OpenFile.open(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Impossible d’ouvrir: $e')));
    }
  }

  Future<void> _showAbsenceDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final types = ['Absence', 'Congé', 'Maladie', 'Mission'];
    final statuses = ['Prévu', 'Approuvé', 'Annulé'];
    String type = (existing?['type'] ?? types.first).toString();
    String status = (existing?['status'] ?? statuses.first).toString();
    DateTime start =
        DateTime.tryParse(existing?['startDate']?.toString() ?? '') ??
        DateTime.now();
    DateTime end =
        DateTime.tryParse(existing?['endDate']?.toString() ?? '') ?? start;
    final reasonCtrl = TextEditingController(
      text: (existing?['reason'] ?? '').toString(),
    );

    Future<void> pickStart(StateSetter setState) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: start,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      setState(() {
        start = picked;
        if (end.isBefore(start)) end = start;
      });
    }

    Future<void> pickEnd(StateSetter setState) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: end,
        firstDate: start,
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      setState(() => end = picked);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEdit ? 'Modifier' : 'Ajouter'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: types
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => type = v ?? type),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: statuses
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => status = v ?? status),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => pickStart(setState),
                      child: Text(
                        'Début: ${DateFormat('dd/MM/yyyy').format(start)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => pickEnd(setState),
                      child: Text(
                        'Fin: ${DateFormat('dd/MM/yyyy').format(end)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motif (optionnel)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    String? by;
    try {
      final u = await AuthService.instance.getCurrentUser();
      by = u?.displayName ?? u?.username;
    } catch (_) {}

    if (!isEdit) {
      await widget.dbService.insertStaffAbsence(
        staffId: _staff.id,
        type: type,
        startDate: start.toIso8601String(),
        endDate: end.toIso8601String(),
        status: status,
        reason: reasonCtrl.text.trim().isNotEmpty
            ? reasonCtrl.text.trim()
            : null,
        recordedBy: by,
      );
    } else {
      await widget.dbService.updateStaffAbsence(
        id: existing!['id'] as int,
        staffId: _staff.id,
        type: type,
        startDate: start.toIso8601String(),
        endDate: end.toIso8601String(),
        status: status,
        reason: reasonCtrl.text.trim().isNotEmpty
            ? reasonCtrl.text.trim()
            : null,
        recordedBy: by,
      );
    }
    await widget.onChanged();
    await _loadAll();
  }

  Future<void> _deleteAbsence(Map<String, dynamic> e) async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Supprimer ?',
      message: 'Cet enregistrement sera supprimé.',
    );
    if (ok != true) return;
    await widget.dbService.deleteStaffAbsence(
      id: e['id'] as int,
      staffId: _staff.id,
    );
    await widget.onChanged();
    await _loadAll();
  }

  Map<String, int> _workloadMinutesByDay() {
    final m = <String, int>{};
    for (final e in _timetableEntries) {
      final day = (e['dayOfWeek'] ?? '').toString();
      final start = (e['startTime'] ?? '').toString();
      final end = (e['endTime'] ?? '').toString();
      final minutes = (_timeToMinutes(end) - _timeToMinutes(start)).clamp(
        0,
        24 * 60,
      );
      m[day] = (m[day] ?? 0) + minutes;
    }
    return m;
  }

  int _workloadMinutesTotal() {
    return _workloadMinutesByDay().values.fold<int>(0, (a, b) => a + b);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: MediaQuery.of(context).size.width > 1000
            ? 1000
            : MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF6366F1),
                    backgroundImage:
                        _staff.photoPath != null && _staff.photoPath!.isNotEmpty
                        ? FileImage(File(_staff.photoPath!))
                        : null,
                    child:
                        (_staff.photoPath == null || _staff.photoPath!.isEmpty)
                        ? Text(
                            _staff.name.trim().isNotEmpty
                                ? _staff.name.trim()[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.displayStaffName(_staff),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_staff.typeRole} • ${_staff.role.isNotEmpty ? _staff.role : '—'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualiser',
                    onPressed: _loadAll,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Modifier',
                    onPressed: () async => widget.onEdit(),
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Infos'),
                Tab(text: 'Documents'),
                Tab(text: 'Absences'),
                Tab(text: 'Charge horaire'),
                Tab(text: 'Historique'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildInfosTab(theme),
                        _buildDocumentsTab(theme),
                        _buildAbsencesTab(theme),
                        _buildWorkloadTab(theme),
                        _buildHistoryTab(theme),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value.isNotEmpty ? value : '-')),
        ],
      ),
    );
  }

  Widget _buildInfosTab(ThemeData theme) {
    final levels = (_staff.levels ?? const []).join(', ');
    final courses = _staff.courses.join(', ');
    final classes = _staff.classes.join(', ');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Identité', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _kv('ID', _staff.id, theme),
          _kv('Nom', widget.displayStaffName(_staff), theme),
          _kv('Sexe', (_staff.gender ?? '').toString(), theme),
          _kv(
            'Né(e) le',
            _staff.birthDate == null
                ? '-'
                : DateFormat('dd/MM/yyyy').format(_staff.birthDate!),
            theme,
          ),
          _kv('Lieu de naissance', (_staff.birthPlace ?? '').toString(), theme),
          _kv('Nationalité', (_staff.nationality ?? '').toString(), theme),
          _kv('Adresse', (_staff.address ?? '').toString(), theme),
          const SizedBox(height: 16),
          Text('Contact', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _kv('Téléphone', _staff.phone, theme),
          _kv('Email', _staff.email, theme),
          const SizedBox(height: 16),
          Text('Professionnel', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _kv('Type', _staff.typeRole, theme),
          _kv('Poste/Rôle', _staff.role, theme),
          _kv('Département', _staff.department, theme),
          _kv('Statut', _staff.status, theme),
          _kv(
            'Date embauche',
            DateFormat('dd/MM/yyyy').format(_staff.hireDate),
            theme,
          ),
          _kv('Classes', classes, theme),
          _kv('Cours', courses, theme),
          _kv('Niveaux', levels, theme),
          const SizedBox(height: 16),
          Text('Diplômes & expérience', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _kv('Diplôme', (_staff.highestDegree ?? '').toString(), theme),
          _kv('Spécialité', (_staff.specialty ?? '').toString(), theme),
          _kv(
            'Années expérience',
            (_staff.experienceYears?.toString() ?? ''),
            theme,
          ),
          _kv(
            'Ancienne institution',
            (_staff.previousInstitution ?? '').toString(),
            theme,
          ),
          _kv('Qualifications', _staff.qualifications, theme),
          const SizedBox(height: 16),
          Text('Contrat', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _kv('Type contrat', (_staff.contractType ?? '').toString(), theme),
          _kv(
            'Salaire base',
            _staff.baseSalary == null
                ? ''
                : _staff.baseSalary!.toStringAsFixed(0),
            theme,
          ),
          _kv(
            'Heures/sem prévues',
            (_staff.weeklyHours?.toString() ?? ''),
            theme,
          ),
          _kv('Supérieur', (_staff.supervisor ?? '').toString(), theme),
          _kv(
            'Retraite',
            _staff.retirementDate == null
                ? ''
                : DateFormat('dd/MM/yyyy').format(_staff.retirementDate!),
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Documents', style: theme.textTheme.titleMedium),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _addDocuments,
                icon: const Icon(Icons.attach_file),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_documents.isEmpty)
            Text(
              'Aucun document.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _documents.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = _documents[index];
                  final exists = File(p).existsSync();
                  return ListTile(
                    leading: Icon(
                      exists ? Icons.description : Icons.warning_amber_rounded,
                      color: exists ? theme.colorScheme.primary : Colors.orange,
                    ),
                    title: Text(path.basename(p)),
                    subtitle: Text(exists ? p : 'Fichier introuvable'),
                    onTap: exists ? () => _openDocument(p) : null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'open') _openDocument(p);
                        if (v == 'rename') _renameDocument(p);
                        if (v == 'delete') _removeDocument(p);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'open', child: Text('Ouvrir')),
                        PopupMenuItem(value: 'rename', child: Text('Renommer')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Supprimer'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAbsencesTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text('Absences & congés', style: theme.textTheme.titleMedium),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showAbsenceDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_absences.isEmpty)
            Text(
              'Aucun enregistrement.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _absences.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final e = _absences[index];
                  final type = (e['type'] ?? '').toString();
                  final status = (e['status'] ?? '').toString();
                  final start = _fmtDate(e['startDate']?.toString());
                  final end = _fmtDate(e['endDate']?.toString());
                  final reason = (e['reason'] ?? '').toString();
                  return ListTile(
                    leading: const Icon(Icons.event_busy),
                    title: Text('$type • $status'),
                    subtitle: Text(
                      '$start → $end${reason.trim().isNotEmpty ? '\n$reason' : ''}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'Modifier',
                          onPressed: () => _showAbsenceDialog(existing: e),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          onPressed: () => _deleteAbsence(e),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkloadTab(ThemeData theme) {
    final totalMinutes = _workloadMinutesTotal();
    final totalHours = totalMinutes / 60.0;
    final expected = _staff.weeklyHours;
    final delta = expected == null ? null : totalHours - expected;
    final byDay = _workloadMinutesByDay();
    final entries = List<Map<String, dynamic>>.from(_timetableEntries);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Année: $_currentAcademicYear',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total hebdomadaire: ${totalHours.toStringAsFixed(1)} h',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (expected != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Prévu: $expected h • Écart: ${delta!.toStringAsFixed(1)} h',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: delta >= 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                ...byDay.entries.map((e) {
                  final h = e.value / 60.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${e.key}: ${h.toStringAsFixed(1)} h'),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Détails (EDT)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(
              'Aucune séance trouvée dans l’EDT.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            )
          else
            ...entries.map((e) {
              final day = (e['dayOfWeek'] ?? '').toString();
              final start = (e['startTime'] ?? '').toString();
              final end = (e['endTime'] ?? '').toString();
              final cls = (e['className'] ?? '').toString();
              final subject = (e['subject'] ?? '').toString();
              return Card(
                child: ListTile(
                  title: Text('$day • $start-$end'),
                  subtitle: Text('$cls • $subject'),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(ThemeData theme) {
    String labelAction(String raw) {
      final v = raw.trim().toLowerCase();
      const map = {
        'insert_staff': 'Création de la fiche',
        'update_staff': 'Modification de la fiche',
        'delete_staff': 'Suppression de la fiche',
        'update_staff_documents': 'Mise à jour des documents',
        'add_staff_absence': 'Ajout absence/congé',
        'update_staff_absence': 'Modification absence/congé',
        'delete_staff_absence': 'Suppression absence/congé',
      };
      return map[v] ?? raw;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: _auditLogs.isEmpty
          ? Text(
              'Aucun historique.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            )
          : ListView.separated(
              itemCount: _auditLogs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = _auditLogs[index];
                final ts = _fmtDateTime(e['timestamp']?.toString());
                final user = (e['username'] ?? '').toString();
                final action = labelAction((e['action'] ?? '').toString());
                final details = (e['details'] ?? '').toString();
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(action),
                  subtitle: Text(
                    '${ts.isNotEmpty ? ts : ''}${user.isNotEmpty ? ' • $user' : ''}${details.isNotEmpty ? '\n$details' : ''}',
                  ),
                );
              },
            ),
    );
  }
}
