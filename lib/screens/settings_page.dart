import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive_io.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:school_manager/screens/dashboard_home.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/license_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Controllers pour les informations de l'école
  final _etablissementController = TextEditingController();
  final _adresseController = TextEditingController();
  final _bpController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _siteWebController = TextEditingController();
  final _mottoController = TextEditingController();
  final _directeurController = TextEditingController();
  final _directeurPrimaireController = TextEditingController();
  final _directeurCollegeController = TextEditingController();
  final _directeurLyceeController = TextEditingController();
  final _directeurUniversityController = TextEditingController();
  final _codeEtablissementController = TextEditingController();
  final _niveauScolaireController = TextEditingController();
  final _searchController = TextEditingController();
  final _academicYearController = TextEditingController();
  final _ministryController = TextEditingController();
  final _republicMottoController = TextEditingController();
  final _republicController = TextEditingController();
  final _educationDirectionController = TextEditingController();
  final _inspectionController = TextEditingController();
  final _reportFooterController = TextEditingController();

  // Focus nodes pour l'accessibilité
  late FocusNode _etablissementFocusNode;
  late FocusNode _adresseFocusNode;
  late FocusNode _bpFocusNode;
  late FocusNode _telephoneFocusNode;
  late FocusNode _emailFocusNode;
  late FocusNode _siteWebFocusNode;
  late FocusNode _mottoFocusNode;
  late FocusNode _directeurFocusNode;
  late FocusNode _directeurPrimaireFocusNode;
  late FocusNode _directeurCollegeFocusNode;
  late FocusNode _directeurLyceeFocusNode;
  late FocusNode _directeurUniversityFocusNode;
  late FocusNode _codeEtablissementFocusNode;
  late FocusNode _searchFocusNode;
  late FocusNode _ministryFocusNode;
  late FocusNode _republicMottoFocusNode;
  late FocusNode _republicFocusNode;
  late FocusNode _educationDirectionFocusNode;
  late FocusNode _inspectionFocusNode;
  late FocusNode _reportFooterFocusNode;

  String? _logoPath;
  String? _flagPath;
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;
  bool _biometricEnabled = false;
  String _selectedLanguage = 'Français';
  String _academicYear = '2024-2025';
  List<String> _availableYears = [];
  String _searchQuery = '';
  String _adminCivility = 'M.';
  String _adminCivilityPrimary = 'M.';
  String _adminCivilityCollege = 'M.';
  String _adminCivilityLycee = 'M.';
  String _adminCivilityUniversity = 'M.';

  final List<String> _languages = ['Français', 'English', 'العربية', 'Español'];
  final List<String> _civilites = ['M.', 'Mme', 'Dr.', 'Révérend', 'RP.'];
  final List<String> _niveauxScolaires = [
    'Maternelle',
    'Primaire',
    'Collège',
    'Lycée',
    'Université',
    'Complexe scolaire',
  ];

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

    _etablissementFocusNode = FocusNode();
    _adresseFocusNode = FocusNode();
    _bpFocusNode = FocusNode();
    _telephoneFocusNode = FocusNode();
    _emailFocusNode = FocusNode();
    _siteWebFocusNode = FocusNode();
    _mottoFocusNode = FocusNode();
    _directeurFocusNode = FocusNode();
    _directeurPrimaireFocusNode = FocusNode();
    _directeurCollegeFocusNode = FocusNode();
    _directeurLyceeFocusNode = FocusNode();
    _directeurUniversityFocusNode = FocusNode();
    _codeEtablissementFocusNode = FocusNode();
    _searchFocusNode = FocusNode();
    _ministryFocusNode = FocusNode();
    _republicMottoFocusNode = FocusNode();
    _republicFocusNode = FocusNode();
    _educationDirectionFocusNode = FocusNode();
    _inspectionFocusNode = FocusNode();
    _reportFooterFocusNode = FocusNode();

    _loadSchoolSettings();
    _academicYearController.text = _academicYear;
    _loadAvailableYears();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _etablissementController.dispose();
    _adresseController.dispose();
    _bpController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _siteWebController.dispose();
    _mottoController.dispose();
    _directeurController.dispose();
    _directeurPrimaireController.dispose();
    _directeurCollegeController.dispose();
    _directeurLyceeController.dispose();
    _directeurUniversityController.dispose();
    _codeEtablissementController.dispose();
    _niveauScolaireController.dispose();
    _searchController.dispose();
    _ministryController.dispose();
    _republicMottoController.dispose();
    _republicController.dispose();
    _educationDirectionController.dispose();
    _inspectionController.dispose();
    _reportFooterController.dispose();

    _etablissementFocusNode.dispose();
    _adresseFocusNode.dispose();
    _bpFocusNode.dispose();
    _telephoneFocusNode.dispose();
    _emailFocusNode.dispose();
    _siteWebFocusNode.dispose();
    _mottoFocusNode.dispose();
    _directeurFocusNode.dispose();
    _directeurPrimaireFocusNode.dispose();
    _directeurCollegeFocusNode.dispose();
    _directeurLyceeFocusNode.dispose();
    _directeurUniversityFocusNode.dispose();
    _codeEtablissementFocusNode.dispose();
    _searchFocusNode.dispose();
    _ministryFocusNode.dispose();
    _republicMottoFocusNode.dispose();
    _republicFocusNode.dispose();
    _educationDirectionFocusNode.dispose();
    _inspectionFocusNode.dispose();
    _reportFooterFocusNode.dispose();
    _academicYearController.dispose();
    super.dispose();
  }

  Future<void> _loadSchoolSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _etablissementController.text = prefs.getString('school_name') ?? '';
      _adresseController.text = prefs.getString('school_address') ?? '';
      _bpController.text = prefs.getString('school_bp') ?? '';
      _telephoneController.text = prefs.getString('school_phone') ?? '';
      _emailController.text = prefs.getString('school_email') ?? '';
      _siteWebController.text = prefs.getString('school_website') ?? '';
      _mottoController.text = prefs.getString('school_motto') ?? '';
      _directeurController.text = prefs.getString('school_director') ?? '';
      _directeurPrimaireController.text =
          prefs.getString('school_director_primary') ?? '';
      _directeurCollegeController.text =
          prefs.getString('school_director_college') ?? '';
      _directeurLyceeController.text =
          prefs.getString('school_director_lycee') ?? '';
      _directeurUniversityController.text =
          prefs.getString('school_director_university') ?? '';
      _codeEtablissementController.text = prefs.getString('school_code') ?? '';
      _niveauScolaireController.text =
          prefs.getString('school_level') ?? 'Primaire';
      _ministryController.text = prefs.getString('school_ministry') ?? '';
      _republicMottoController.text =
          prefs.getString('school_republic_motto') ?? '';
      _republicController.text = prefs.getString('school_republic') ?? '';
      _educationDirectionController.text =
          prefs.getString('school_education_direction') ?? '';
      _inspectionController.text = prefs.getString('school_inspection') ?? '';
      _reportFooterController.text =
          prefs.getString('report_card_footer_note') ??
          PdfService.defaultReportFooterNote;
      _logoPath = prefs.getString('school_logo');
      _flagPath = prefs.getString('school_flag');
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _notificationsEnabled = prefs.getBool('notifications') ?? true;
      _biometricEnabled = prefs.getBool('biometric') ?? false;
      _selectedLanguage = prefs.getString('language') ?? 'Français';
      _academicYear = prefs.getString('academic_year') ?? '2024-2025';
      _academicYearController.text = _academicYear;

      // Load civilities with migration logic
      String fixCiv(String? val) => (val == 'RP' ? 'RP.' : (val ?? 'M.'));

      _adminCivility = fixCiv(prefs.getString('school_admin_civility'));
      _adminCivilityPrimary = fixCiv(
        prefs.getString('school_civility_primary'),
      );
      _adminCivilityCollege = fixCiv(
        prefs.getString('school_civility_college'),
      );
      _adminCivilityLycee = fixCiv(prefs.getString('school_civility_lycee'));
      _adminCivilityUniversity = fixCiv(
        prefs.getString('school_civility_university'),
      );
    });
  }

  Future<void> _loadAvailableYears() async {
    try {
      final classes = await DatabaseService().getClasses();
      final years = <String>{};
      for (final c in classes) {
        if (c.academicYear.isNotEmpty) years.add(c.academicYear);
      }
      years.add(_academicYear);
      final sorted = years.toList()..sort((a, b) => b.compareTo(a));
      if (mounted) setState(() => _availableYears = sorted);
    } catch (_) {}
  }

  Future<void> _saveSchoolSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('school_name', _etablissementController.text.trim());
    await prefs.setString('school_address', _adresseController.text.trim());
    await prefs.setString('school_bp', _bpController.text.trim());
    await prefs.setString('school_phone', _telephoneController.text.trim());
    await prefs.setString('school_email', _emailController.text.trim());
    await prefs.setString('school_website', _siteWebController.text.trim());
    await prefs.setString('school_motto', _mottoController.text.trim());
    await prefs.setString('school_republic', _republicController.text.trim());
    await prefs.setString('school_director', _directeurController.text.trim());
    await prefs.setString(
      'school_director_primary',
      _directeurPrimaireController.text.trim(),
    );
    await prefs.setString(
      'school_director_college',
      _directeurCollegeController.text.trim(),
    );
    await prefs.setString(
      'school_director_lycee',
      _directeurLyceeController.text.trim(),
    );
    await prefs.setString(
      'school_director_university',
      _directeurUniversityController.text.trim(),
    );
    await prefs.setString('school_civility_primary', _adminCivilityPrimary);
    await prefs.setString('school_civility_college', _adminCivilityCollege);
    await prefs.setString('school_civility_lycee', _adminCivilityLycee);
    await prefs.setString(
      'school_civility_university',
      _adminCivilityUniversity,
    );
    await prefs.setString(
      'school_code',
      _codeEtablissementController.text.trim(),
    );
    await prefs.setString(
      'school_level',
      _niveauScolaireController.text.trim(),
    );
    await prefs.setString('school_ministry', _ministryController.text.trim());
    await prefs.setString(
      'school_republic_motto',
      _republicMottoController.text.trim(),
    );
    await prefs.setString(
      'school_education_direction',
      _educationDirectionController.text.trim(),
    );
    await prefs.setString(
      'school_inspection',
      _inspectionController.text.trim(),
    );
    await prefs.setString(
      'report_card_footer_note',
      _reportFooterController.text.trim(),
    );
    await prefs.setBool('dark_mode', _isDarkMode);
    await prefs.setBool('notifications', _notificationsEnabled);
    await prefs.setBool('biometric', _biometricEnabled);
    await prefs.setString('language', _selectedLanguage);
    await prefs.setString('school_admin_civility', _adminCivility);

    if (_logoPath != null) {
      await prefs.setString('school_logo', _logoPath!);
    }
    if (_flagPath != null) {
      await prefs.setString('school_flag', _flagPath!);
    }

    // Keep DB in sync so PDFs reliably load logo and school details
    try {
      final info = SchoolInfo(
        name: _etablissementController.text.trim(),
        address: _adresseController.text.trim(),
        bp: _bpController.text.trim(),
        director: _directeurController.text.trim(),
        directorPrimary: _directeurPrimaireController.text.trim(),
        directorCollege: _directeurCollegeController.text.trim(),
        directorLycee: _directeurLyceeController.text.trim(),
        directorUniversity: _directeurUniversityController.text.trim(),
        civilityPrimary: _adminCivilityPrimary,
        civilityCollege: _adminCivilityCollege,
        civilityLycee: _adminCivilityLycee,
        civilityUniversity: _adminCivilityUniversity,
        logoPath: _logoPath,
        flagPath: _flagPath,
        telephone: _telephoneController.text.trim(),
        email: _emailController.text.trim(),
        website: _siteWebController.text.trim(),
        motto: _mottoController.text.trim(),
        republic: _republicController.text.trim(),
        ministry: _ministryController.text.trim(),
        republicMotto: _republicMottoController.text.trim(),
        educationDirection: _educationDirectionController.text.trim(),
        inspection: _inspectionController.text.trim(),
      );
      await DatabaseService().insertSchoolInfo(info);
    } catch (_) {}

    await _requestAcademicYearChange(
      _academicYearController.text.trim(),
      showSuccessSnackBar: false,
    );
    if (mounted) {
      _showModernSnackBar(
        'Configuration de l\'école sauvegardée avec succès !',
      );
    }
    // Audit: paramètres mis à jour
    try {
      final u = await AuthService.instance.getCurrentUser();
      await DatabaseService().logAudit(
        category: 'settings',
        action: 'update_settings',
        username: u?.username,
        details:
            'name=${_etablissementController.text.trim()} email=${_emailController.text.trim()} year=${academicYearNotifier.value}',
      );
    } catch (_) {}
  }

  Future<void> _applyAcademicYear(String year) async {
    await _requestAcademicYearChange(year, showSuccessSnackBar: true);
  }

  Future<int> _countClassesForAcademicYear(String academicYear) async {
    try {
      final classes = await DatabaseService().getClasses();
      return classes.where((c) => c.academicYear == academicYear).length;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> _confirmArchiveBeforeYearChange({
    required String currentYear,
    required String nextYear,
    required int classCount,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomDialog(
        title: 'Changer d\'année',
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
                children: [
                  const Icon(Icons.archive_outlined, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Archivage avant changement',
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
              'Vous allez passer de $currentYear à $nextYear.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.class_outlined,
                      color: Color(0xFF6366F1),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$classCount classe(s) liée(s) à l\'année $currentYear',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Pour éviter toute perte et garder l\'historique, l\'application peut archiver les bulletins/notes de l\'année en cours avant de continuer.',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.4,
              ),
            ),
          ],
        ),
        showCloseIcon: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Annuler',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.archive),
            label: const Text('Archiver et changer'),
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
    return result == true;
  }

  Future<void> _runYearArchive(String year) async {
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
      await DatabaseService().archiveReportCardsForYear(year);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _requestAcademicYearChange(
    String year, {
    required bool showSuccessSnackBar,
  }) async {
    final nextYear = year.trim();
    if (nextYear.isEmpty) {
      _showModernSnackBar(
        'Veuillez saisir une année académique.',
        isError: true,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final currentYear = (prefs.getString('academic_year') ?? '2024-2025')
        .trim();

    if (nextYear == currentYear) {
      if (mounted) {
        setState(() {
          _academicYear = currentYear;
          _academicYearController.text = currentYear;
        });
      }
      return;
    }

    final classCount = await _countClassesForAcademicYear(currentYear);
    if (classCount > 0) {
      final shouldArchive = await _confirmArchiveBeforeYearChange(
        currentYear: currentYear,
        nextYear: nextYear,
        classCount: classCount,
      );
      if (!shouldArchive) {
        if (mounted) {
          setState(() {
            _academicYear = currentYear;
            _academicYearController.text = currentYear;
          });
          _showModernSnackBar('Changement d\'année annulé.');
        }
        return;
      }

      try {
        await _runYearArchive(currentYear);
      } catch (e) {
        _showModernSnackBar('Erreur lors de l\'archivage : $e', isError: true);
        return;
      }
    }

    await prefs.setString('academic_year', nextYear);
    academicYearNotifier.value = nextYear;

    if (mounted) {
      setState(() {
        _academicYear = nextYear;
        _academicYearController.text = nextYear;
        if (!_availableYears.contains(nextYear)) {
          _availableYears = [nextYear, ..._availableYears];
        }
      });
    }

    if (showSuccessSnackBar) {
      _showModernSnackBar('Année changée à $nextYear');
    }
  }

  Future<void> _promptAddYear() async {
    final controller = TextEditingController(
      text: _suggestNextYear(_academicYear),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter une année'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'ex: 2025-2026'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final value = controller.text.trim();
      final valid = RegExp(r'^\d{4}-\d{4}$').hasMatch(value);
      if (!valid) {
        _showModernSnackBar(
          'Format invalide. Utilisez 2025-2026.',
          isError: true,
        );
        return;
      }
      setState(() {
        if (!_availableYears.contains(value)) {
          _availableYears = [value, ..._availableYears];
        }
      });
      await _applyAcademicYear(value);
    }
  }

  String _suggestNextYear(String current) {
    try {
      final parts = current.split('-');
      final start = int.parse(parts.first);
      final end = int.parse(parts.last);
      return '${start + 1}-${end + 1}';
    } catch (_) {
      final now = DateTime.now().year;
      return '$now-${now + 1}';
    }
  }

  Future<String?> _saveLogo(File logo) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logosDir = Directory('${directory.path}/logos');
      if (!await logosDir.exists()) {
        await logosDir.create(recursive: true);
      }
      final extension = logo.path.split('.').last;
      final logoPath = '${logosDir.path}/logo_ecole.$extension';
      final logoFile = File(logoPath);
      await logoFile.create(recursive: true);
      await logo.copy(logoPath);
      return logoPath;
    } catch (e) {
      print('Erreur lors de la sauvegarde du logo: $e');
      if (mounted) {
        _showModernSnackBar('Impossible d\'enregistrer le logo', isError: true);
      }
      return null;
    }
  }

  Future<String?> _pickImagePathWithFallback({
    required String contextLabel,
  }) async {
    try {
      print('[SettingsPage] Ouverture FilePicker pour $contextLabel');
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) {
        print(
          '[SettingsPage] FilePicker fermé sans sélection pour $contextLabel',
        );
        if (Platform.isMacOS && mounted) {
          print(
            '[SettingsPage] macOS détecté -> demande d\'un chemin manuel pour $contextLabel',
          );
          return await _promptManualImagePath(
            title: 'Importer un $contextLabel',
            helperText:
                'Impossible d\'ouvrir la fenêtre de sélection. Entrez le chemin complet du fichier image (ex: /Users/.../image.png).',
          );
        }
        return null;
      }
      print('[SettingsPage] Fichier sélectionné pour $contextLabel : $path');
      return path;
    } catch (e) {
      print('[SettingsPage] Erreur ouverture sélecteur $contextLabel : $e');
      if (!mounted) return null;
      return await _promptManualImagePath(
        title: 'Importer un $contextLabel',
        helperText:
            'Impossible d\'ouvrir la fenêtre de sélection. Entrez le chemin complet du fichier image (ex: /Users/.../mon_image.png).',
      );
    }
  }

  Future<String?> _promptManualImagePath({
    required String title,
    required String helperText,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(helperText),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Chemin du fichier',
                hintText: '/Users/vous/Images/logo.png',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) {
      print('[SettingsPage] Aucun chemin saisi pour $title');
      return null;
    }
    print('[SettingsPage] Chemin saisi pour $title : ${result.trim()}');
    return result.trim();
  }

  Future<void> _pickLogo() async {
    final selectedPath = await _pickImagePathWithFallback(contextLabel: 'logo');
    if (selectedPath == null) return;
    final selectedFile = File(selectedPath);
    if (!await selectedFile.exists()) {
      if (mounted) {
        _showModernSnackBar(
          'Fichier introuvable: $selectedPath',
          isError: true,
        );
      }
      return;
    }
    final savedPath = await _saveLogo(selectedFile);
    if (savedPath != null) {
      setState(() {
        _logoPath = savedPath;
      });
      // Evict old cached image and force reload for the same file path
      try {
        await FileImage(File(savedPath)).evict();
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('school_logo', savedPath);
      if (mounted) {
        _showModernSnackBar('Logo modifié avec succès !');
      }
    }
  }

  Future<void> _removeLogo() async {
    if (_logoPath != null) {
      final file = File(_logoPath!);
      if (await file.exists()) {
        await file.delete();
      }
      setState(() {
        _logoPath = null;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('school_logo');
      if (mounted) {
        _showModernSnackBar('Logo supprimé.');
      }
    }
  }

  Future<String?> _saveFlag(File file) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final flagDir = Directory('${appDir.path}/school_flags');
      if (!await flagDir.exists()) {
        await flagDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'flag_$timestamp${file.path.substring(file.path.lastIndexOf('.'))}';
      final savedFile = await file.copy('${flagDir.path}/$fileName');
      return savedFile.path;
    } catch (e) {
      print('Erreur lors de la sauvegarde du drapeau: $e');
      if (mounted) {
        _showModernSnackBar(
          'Impossible d\'enregistrer le drapeau',
          isError: true,
        );
      }
      return null;
    }
  }

  Future<void> _pickFlag() async {
    final selectedPath = await _pickImagePathWithFallback(
      contextLabel: 'drapeau',
    );
    if (selectedPath == null) return;
    final selectedFile = File(selectedPath);
    if (!await selectedFile.exists()) {
      if (mounted) {
        _showModernSnackBar(
          'Fichier introuvable: $selectedPath',
          isError: true,
        );
      }
      return;
    }
    final savedPath = await _saveFlag(selectedFile);
    if (savedPath != null) {
      setState(() {
        _flagPath = savedPath;
      });
      try {
        await FileImage(File(savedPath)).evict();
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('school_flag', savedPath);
      if (mounted) {
        _showModernSnackBar('Drapeau modifié avec succès !');
      }
    }
  }

  Future<void> _removeFlag() async {
    if (_flagPath != null) {
      final file = File(_flagPath!);
      if (await file.exists()) {
        await file.delete();
      }
      setState(() {
        _flagPath = null;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('school_flag');
      if (mounted) {
        _showModernSnackBar('Drapeau supprimé.');
      }
    }
  }

  Future<void> _backupDatabase(BuildContext context) async {
    try {
      final dbDir = await getDatabasesPath();
      final dbPath = '$dbDir/ecole_manager.db';
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        _showModernSnackBar('Base de données non trouvée.', isError: true);
        return;
      }
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupPath = '$dirPath/school_backup_$timestamp.db';
      await dbFile.copy(backupPath);
      _showModernSnackBar('Sauvegarde créée : ${backupPath.split('/').last}');
    } catch (e) {
      _showModernSnackBar('Erreur lors de la sauvegarde : $e', isError: true);
    }
  }

  Future<void> _restoreDatabase(BuildContext context) async {
    final reallyRestore = await _showModernConfirmationDialog(
      'Restaurer la base de données',
      'Cette action remplacera toutes les données actuelles. Voulez-vous continuer ? (Une sauvegarde est recommandée avant)',
    );
    if (!reallyRestore) return;
    try {
      // Fermer la base avant de restaurer
      await DatabaseService().closeDatabase();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: 'Sélectionnez le fichier .db à restaurer',
      );
      if (result == null || result.files.single.path == null) return;
      final pickedFile = File(result.files.single.path!);
      final dbDir = await getDatabasesPath();
      final dbPath = '$dbDir/ecole_manager.db';
      print('[SettingsPage] Restauration de la base à : $dbPath');
      // Supprimer l'ancien fichier avant de copier
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      await pickedFile.copy(dbPath);
      _showModernSnackBar(
        'Restauration réussie. Veuillez redémarrer l\'application.',
      );
    } catch (e) {
      _showModernSnackBar('Erreur lors de la restauration : $e', isError: true);
    }
  }

  Future<void> _exportData({
    required Map<String, bool> tables,
    required String format,
  }) async {
    try {
      final db = DatabaseService();
      final List<Student> students = tables['Élèves'] == true
          ? await db.getStudents()
          : [];
      final List<Class> classes = tables['Classes'] == true
          ? await db.getClasses()
          : [];
      final List<Payment> payments = tables['Paiements'] == true
          ? await db.getAllPayments()
          : [];
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final List<String> generatedFiles = [];
      final List<File> filesToZip = [];
      // PDF
      if (format == 'PDF' || format == 'ZIP') {
        if (students.isNotEmpty) {
          final pdfBytes = await PdfService.exportStudentsListPdf(
            students: students
                .map((s) => {'student': s, 'classe': null})
                .toList(),
          );
          final file = File(
            '$dirPath/export_eleves_${DateTime.now().millisecondsSinceEpoch}.pdf',
          );
          await file.writeAsBytes(pdfBytes);
          generatedFiles.add(file.path);
          if (format == 'ZIP') filesToZip.add(file);
        }
        if (classes.isNotEmpty) {
          // Génération PDF classes (simple)
          final pdf = await PdfService.exportClassesListPdf(classes: classes);
          final file = File(
            '$dirPath/export_classes_${DateTime.now().millisecondsSinceEpoch}.pdf',
          );
          await file.writeAsBytes(pdf);
          generatedFiles.add(file.path);
          if (format == 'ZIP') filesToZip.add(file);
        }
        if (payments.isNotEmpty) {
          final rows = payments
              .map(
                (p) => {
                  'student': students.firstWhere(
                    (s) => s.id == p.studentId,
                    orElse: () => Student.empty(),
                  ),
                  'payment': p,
                  'classe': classes.firstWhere(
                    (c) => c.name == p.className,
                    orElse: () => Class.empty(),
                  ),
                  'totalPaid': p.amount,
                },
              )
              .toList();
          final pdfBytes = await PdfService.exportPaymentsListPdf(rows: rows);
          final file = File(
            '$dirPath/export_paiements_${DateTime.now().millisecondsSinceEpoch}.pdf',
          );
          await file.writeAsBytes(pdfBytes);
          generatedFiles.add(file.path);
          if (format == 'ZIP') filesToZip.add(file);
        }
      }
      // CSV
      if (format == 'CSV' || format == 'ZIP') {
        if (students.isNotEmpty) {
          final csvRows = [
            [
              'ID',
              'Nom',
              'Date de naissance',
              'Adresse',
              'Sexe',
              'Contact',
              'Email',
              'Contact urgence',
              'Tuteur',
              'Contact tuteur',
              'Classe',
              'Infos médicales',
              'Photo',
            ],
            ...students.map(
              (s) => [
                s.id,
                '${s.firstName} ${s.lastName}'.trim(),
                s.dateOfBirth,
                s.address,
                s.gender,
                s.contactNumber,
                s.email,
                s.emergencyContact,
                s.guardianName,
                s.guardianContact,
                s.className,
                s.medicalInfo ?? '',
                s.photoPath ?? '',
              ],
            ),
          ];
          final csvStr = const ListToCsvConverter().convert(csvRows);
          final file = File(
            '$dirPath/export_eleves_${DateTime.now().millisecondsSinceEpoch}.csv',
          );
          await file.writeAsString(csvStr);
          generatedFiles.add(file.path);
          if (format == 'ZIP') filesToZip.add(file);
        }
        if (classes.isNotEmpty) {
          final csvRows = [
            [
              'Nom',
              'Année',
              'Titulaire',
              'Frais école',
              'Frais cotisation parallèle',
            ],
            ...classes.map(
              (c) => [
                c.name,
                c.academicYear,
                c.titulaire ?? '',
                c.fraisEcole ?? '',
                c.fraisCotisationParallele ?? '',
              ],
            ),
          ];
          final csvStr = const ListToCsvConverter().convert(csvRows);
          final file = File(
            '$dirPath/export_classes_${DateTime.now().millisecondsSinceEpoch}.csv',
          );
          await file.writeAsString(csvStr);
          generatedFiles.add(file.path);
          if (format == 'ZIP') filesToZip.add(file);
        }
        if (payments.isNotEmpty) {
          final csvRows = [
            [
              'ID',
              'Élève',
              'Classe',
              'Montant',
              'Date',
              'Commentaire',
              'Annulé',
              'Date annulation',
            ],
            ...payments.map(
              (p) => [
                p.id,
                p.studentId,
                p.className,
                p.amount,
                p.date,
                p.comment ?? '',
                p.isCancelled ? 'Oui' : 'Non',
                p.cancelledAt ?? '',
              ],
            ),
          ];
          final csvStr = const ListToCsvConverter().convert(csvRows);
          final file = File(
            '$dirPath/export_paiements_${DateTime.now().millisecondsSinceEpoch}.csv',
          );
          await file.writeAsString(csvStr);
          generatedFiles.add(file.path);
          if (format == 'ZIP') filesToZip.add(file);
        }
      }
      // ZIP
      if (format == 'ZIP' && filesToZip.isNotEmpty) {
        final encoder = ZipFileEncoder();
        final zipPath =
            '$dirPath/export_donnees_${DateTime.now().millisecondsSinceEpoch}.zip';
        encoder.create(zipPath);
        for (final file in filesToZip) {
          encoder.addFile(file);
        }
        encoder.close();
        generatedFiles.add(zipPath);
      }
      _showModernSnackBar(
        'Export réussi :\n${generatedFiles.map((e) => e.split('/').last).join(', ')}',
      );
    } catch (e) {
      _showModernSnackBar('Erreur export : $e', isError: true);
    }
  }

  Future<void> _showLicenseDialog() async {
    final status = await LicenseService.instance.getStatus();
    final keyController = TextEditingController(text: status.key ?? '');

    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    String statusLabel(LicenseStatus st) {
      if (st.isActive) return 'Active';
      if (st.isExpired) return 'Expirée';
      return 'Incomplète';
    }

    String _formatKeyForDisplay(String raw, {required bool masked}) {
      if (raw.isEmpty) return '—';
      String _groupKey(String s) {
        final n = s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
        final buf = StringBuffer();
        for (int i = 0; i < n.length; i++) {
          if (i > 0 && i % 4 == 0) buf.write('-');
          buf.write(n[i]);
        }
        return buf.toString();
      }

      final grouped = _groupKey(raw);
      if (!masked) return grouped;
      final parts = grouped.split('-');
      if (parts.length <= 2) {
        if (raw.length <= 6) return '•••';
        return raw.substring(0, 3) + '••••••' + raw.substring(raw.length - 3);
      }
      final first = parts.first;
      final last = parts.last;
      final middle = List.generate(parts.length - 2, (_) => '••••');
      return ([first, ...middle, last]).join('-');
    }

    bool showKey = false;
    bool inputReveal = false;
    Timer? revealTimer;
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) => CustomDialog(
            title: 'Licence',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF34D399)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.vpn_key_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FutureBuilder<LicenseStatus>(
                              future: LicenseService.instance.getStatus(),
                              builder: (context, snap) {
                                final st = snap.data ?? status;
                                final label = statusLabel(st);
                                final days = st.daysRemaining;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Statut: $label',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Clé: ${_formatKeyForDisplay(st.key ?? '', masked: !showKey)}',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium?.color,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: showKey
                                              ? 'Masquer'
                                              : 'Afficher',
                                          onPressed: () async {
                                            if (!showKey) {
                                              final p = TextEditingController();
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx2) => AlertDialog(
                                                  title: const Text(
                                                    'Mot de passe SupAdmin',
                                                  ),
                                                  content: TextField(
                                                    controller: p,
                                                    obscureText: true,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText:
                                                              'Mot de passe',
                                                        ),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            ctx2,
                                                          ).pop(false),
                                                      child: const Text(
                                                        'Annuler',
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () async {
                                                        final valid =
                                                            await LicenseService
                                                                .instance
                                                                .verifySupAdmin(
                                                                  p.text,
                                                                );
                                                        Navigator.of(
                                                          ctx2,
                                                        ).pop(valid);
                                                      },
                                                      child: const Text(
                                                        'Valider',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok == true) {
                                                setState(() => showKey = true);
                                                // Arm timeout 2 minutes
                                                revealTimer?.cancel();
                                                revealTimer = Timer(
                                                  const Duration(minutes: 1),
                                                  () {
                                                    showKey = false;
                                                    (context as Element)
                                                        .markNeedsBuild();
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Affichage sensible masqué (timeout)',
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                );
                                              } else {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Mot de passe SupAdmin incorrect',
                                                    ),
                                                  ),
                                                );
                                              }
                                            } else {
                                              setState(() => showKey = false);
                                              revealTimer?.cancel();
                                            }
                                          },
                                          icon: Icon(
                                            showKey
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            size: 18,
                                            color: Theme.of(
                                              context,
                                            ).iconTheme.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (st.registeredAt != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Enregistrée le: ${fmt(st.registeredAt!)}',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      'Expiration: ${st.expiry != null ? fmt(st.expiry!) : '—'}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Jours restants: ${st.isActive ? days : (st.isExpired ? 0 : '—')}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<bool>(
                              future: LicenseService.instance.allKeysUsed(),
                              builder: (context, snap) {
                                if (snap.data == true) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF10B981,
                                      ).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF10B981,
                                        ).withOpacity(0.3),
                                      ),
                                    ),
                                    child: const Text(
                                      'Lot de 12 licences consommé — application débloquée',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'Powered by ACTe',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color?.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Key field
                TextField(
                  controller: keyController,
                  obscureText: !inputReveal,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Clé de licence',
                    prefixIcon: const Icon(Icons.vpn_key),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      tooltip: inputReveal ? 'Masquer' : 'Afficher (SupAdmin)',
                      icon: Icon(
                        inputReveal ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () async {
                        if (!inputReveal) {
                          final p = TextEditingController();
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx2) => AlertDialog(
                              title: const Text('Mot de passe SupAdmin'),
                              content: TextField(
                                controller: p,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Mot de passe',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx2).pop(false),
                                  child: const Text('Annuler'),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    final valid = await LicenseService.instance
                                        .verifySupAdmin(p.text);
                                    Navigator.of(ctx2).pop(valid);
                                  },
                                  child: const Text('Valider'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            setState(() => inputReveal = true);
                            revealTimer?.cancel();
                            revealTimer = Timer(const Duration(minutes: 1), () {
                              inputReveal = false;
                              (context as Element).markNeedsBuild();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Affichage sensible masqué (timeout)',
                                  ),
                                ),
                              );
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Mot de passe SupAdmin incorrect',
                                ),
                              ),
                            );
                          }
                        } else {
                          setState(() => inputReveal = false);
                          revealTimer?.cancel();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Info: la validité est 12 mois à partir de l'enregistrement
                const SizedBox(height: 12),
                Text(
                  'La licence est valable 12 mois à partir de la date d\'enregistrement.',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withOpacity(0.8),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Fermer',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final st = await LicenseService.instance.getStatus();
                  final controller = TextEditingController();
                  String normalize(String s) =>
                      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                  await showDialog(
                    context: context,
                    builder: (ctx) {
                      return StatefulBuilder(
                        builder: (context, setState) => CustomDialog(
                          title: 'Confirmer la suppression',
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pour supprimer la licence, saisissez la clé actuelle pour confirmer.\nLa clé restera marquée comme utilisée.',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.color,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: controller,
                                decoration: InputDecoration(
                                  labelText: 'Clé de licence',
                                  prefixIcon: const Icon(Icons.vpn_key),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(
                                'Annuler',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                final input = normalize(controller.text);
                                final current = normalize(st.key ?? '');
                                if (input.isEmpty || input != current) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Clé de licence incorrecte',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.of(context).pop();
                                await LicenseService.instance.clearLicense();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Licence supprimée'),
                                    ),
                                  );
                                }
                                setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE53E3E),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Supprimer'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Supprimer',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final key = keyController.text.trim();
                  if (key.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Veuillez saisir la clé de licence'),
                      ),
                    );
                    return;
                  }
                  try {
                    await LicenseService.instance.saveLicense(key: key);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Licence enregistrée')),
                    );
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Enregistrer'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showExportStatisticsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final academicYearController = TextEditingController(
          text: _academicYearController.text.trim().isNotEmpty
              ? _academicYearController.text.trim()
              : _academicYear,
        );
        return StatefulBuilder(
          builder: (context, setState) => CustomDialog(
            title: 'Exporter les statistiques (PDF)',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Année académique',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: academicYearController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'ex: 2024-2025',
                    isDense: true,
                  ),
                ),
              ],
            ),
            fields: const [],
            onSubmit: () async {
              Navigator.of(context).pop();
              await _exportStatistics(
                academicYear: academicYearController.text.trim().isEmpty
                    ? _academicYear
                    : academicYearController.text.trim(),
              );
            },
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _exportStatistics(
                    academicYear: academicYearController.text.trim().isEmpty
                        ? _academicYear
                        : academicYearController.text.trim(),
                  );
                },
                child: const Text('Exporter en PDF'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportStatistics({required String academicYear}) async {
    try {
      final db = DatabaseService();
      final info = await loadSchoolInfo();
      final students = await db.getStudents();
      final staff = await db.getStaff();
      final classes = await db.getClasses();
      final payments = await db.getAllPayments();
      final monthlyEnrollment = await db.getMonthlyEnrollmentData();
      final classDistribution = await db.getClassDistribution();

      final totalRevenue = payments.fold<double>(
        0.0,
        (sum, p) => sum + (p.amount),
      );
      final bytes = await PdfService.exportStatisticsPdf(
        schoolInfo: info,
        academicYear: academicYear,
        totalStudents: students.length,
        totalStaff: staff.length,
        totalClasses: classes.length,
        totalRevenue: totalRevenue,
        monthlyEnrollment: monthlyEnrollment,
        classDistribution: classDistribution,
      );

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final file = File(
        '$dirPath/statistiques_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(bytes);
      _showModernSnackBar(
        'Statistiques exportées: ${file.path.split('/').last}',
      );
    } catch (e) {
      _showModernSnackBar('Erreur export statistiques: $e', isError: true);
    }
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String exportFormat = 'PDF';
        final Map<String, bool> tables = {
          'Élèves': true,
          'Classes': false,
          'Paiements': false,
        };
        return StatefulBuilder(
          builder: (context, setState) => CustomDialog(
            title: 'Exporter les données',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Que souhaitez-vous exporter ?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...tables.keys.map(
                  (key) => CheckboxListTile(
                    value: tables[key],
                    onChanged: (val) =>
                        setState(() => tables[key] = val ?? false),
                    title: Text(key),
                  ),
                ),
                Divider(),
                Text(
                  'Format d\'export',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                RadioListTile<String>(
                  value: 'PDF',
                  groupValue: exportFormat,
                  onChanged: (val) => setState(() => exportFormat = val!),
                  title: Text('PDF'),
                ),
                RadioListTile<String>(
                  value: 'CSV',
                  groupValue: exportFormat,
                  onChanged: (val) => setState(() => exportFormat = val!),
                  title: Text('CSV'),
                ),
                RadioListTile<String>(
                  value: 'ZIP',
                  groupValue: exportFormat,
                  onChanged: (val) => setState(() => exportFormat = val!),
                  title: Text('ZIP (tous les fichiers)'),
                ),
              ],
            ),
            fields: const [],
            onSubmit: () {
              Navigator.of(context).pop();
              _exportData(tables: tables, format: exportFormat);
            },
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _exportData(tables: tables, format: exportFormat);
                },
                child: const Text('Exporter'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showModernSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 24,
              semanticLabel: isError ? 'Erreur' : 'Succès',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError
            ? const Color(0xFFE53E3E)
            : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        elevation: 6,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _showModernConfirmationDialog(
    String title,
    String content,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => CustomDialog(
            title: title,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53E3E).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 40,
                    color: Color(0xFFE53E3E),
                    semanticLabel: 'Attention',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  content,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    height: 1.5,
                  ),
                ),
              ],
            ),
            fields: const [],
            onSubmit: () => Navigator.of(context).pop(true),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: const Text(
                  'Annuler',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53E3E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Confirmer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildModernSectionTitle(String title, IconData icon) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: primary, semanticLabel: title),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(
          height: 1,
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ],
    );
  }

  Widget _buildModernSectionCard({
    required String title,
    required List<Widget> children,
    required IconData icon,
  }) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildModernSectionTitle(title, icon),
                        const SizedBox(height: 16),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Duplicate search field removed; header search remains the single source.

  Widget _buildModernTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    int maxLines = 1,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: prefixIcon != null
              ? Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(prefixIcon, color: Colors.white, size: 20),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
          filled: true,
          fillColor: Theme.of(context).cardColor.withOpacity(0.5),
          labelStyle: TextStyle(
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  InputDecoration _buildModernDropdownDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
      ),
      filled: true,
      fillColor: Theme.of(context).cardColor.withOpacity(0.5),
    );
  }

  Widget _buildModernActionButton({
    required String label,
    required VoidCallback onPressed,
    required IconData icon,
    required Color gradientStart,
    required Color gradientEnd,
    String? tooltip,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      child: Tooltip(
        message: tooltip ?? label,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
              if (states.contains(MaterialState.disabled)) {
                return Colors.grey.withOpacity(0.5);
              }
              return Colors.transparent; // Use gradient container
            }),
            foregroundColor: MaterialStateProperty.all(Colors.white),
            overlayColor: MaterialStateProperty.all(
              Colors.white.withOpacity(0.1),
            ),
            shadowColor: MaterialStateProperty.all(
              gradientStart.withOpacity(0.3),
            ),
            elevation: MaterialStateProperty.resolveWith<double>((states) {
              return states.contains(MaterialState.hovered) ? 4 : 2;
            }),
            shape: MaterialStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            padding: MaterialStateProperty.all(
              const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            ),
            minimumSize: MaterialStateProperty.all(
              const Size(double.infinity, 56),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [gradientStart, gradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: gradientStart.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: Colors.white, semanticLabel: label),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
              semanticLabel: title,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF6366F1),
            activeTrackColor: const Color(0xFF6366F1).withOpacity(0.5),
            inactiveThumbColor: Colors.grey[400],
            inactiveTrackColor: Colors.grey[200],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final bool isComplexe = _niveauScolaireController.text
        .toLowerCase()
        .contains('complexe');

    // Filter sections based on search query
    final sections =
        [
          {
            'title': 'Informations de l\'établissement',
            'icon': Icons.account_balance,
            'children': [
              _buildModernTextField(
                controller: _etablissementController,
                focusNode: _etablissementFocusNode,
                label: 'Nom de l\'établissement',
                prefixIcon: Icons.account_balance,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    _codeEtablissementFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _codeEtablissementController,
                focusNode: _codeEtablissementFocusNode,
                label: 'Code établissement',
                prefixIcon: Icons.tag,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _directeurFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _directeurController,
                focusNode: _directeurFocusNode,
                label: 'Nom du directeur/directrice',
                prefixIcon: Icons.person,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => isComplexe
                    ? _directeurPrimaireFocusNode.requestFocus()
                    : _adresseFocusNode.requestFocus(),
              ),
              if (isComplexe) ...[
                DropdownButtonFormField<String>(
                  value: _adminCivilityPrimary.isEmpty
                      ? 'M.'
                      : _adminCivilityPrimary,
                  decoration: _buildModernDropdownDecoration(
                    'Civilité (Primaire)',
                    Icons.badge,
                  ),
                  items: _civilites
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => _adminCivilityPrimary = value ?? 'M.');
                  },
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  controller: _directeurPrimaireController,
                  focusNode: _directeurPrimaireFocusNode,
                  label: 'Chef d\'établissement (Primaire)',
                  prefixIcon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      _directeurCollegeFocusNode.requestFocus(),
                ),
                DropdownButtonFormField<String>(
                  value: _adminCivilityCollege.isEmpty
                      ? 'M.'
                      : _adminCivilityCollege,
                  decoration: _buildModernDropdownDecoration(
                    'Civilité (Collège)',
                    Icons.badge,
                  ),
                  items: _civilites
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => _adminCivilityCollege = value ?? 'M.');
                  },
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  controller: _directeurCollegeController,
                  focusNode: _directeurCollegeFocusNode,
                  label: 'Chef d\'établissement (Collège)',
                  prefixIcon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      _directeurLyceeFocusNode.requestFocus(),
                ),
                DropdownButtonFormField<String>(
                  value: _adminCivilityLycee.isEmpty
                      ? 'M.'
                      : _adminCivilityLycee,
                  decoration: _buildModernDropdownDecoration(
                    'Civilité (Lycée)',
                    Icons.badge,
                  ),
                  items: _civilites
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => _adminCivilityLycee = value ?? 'M.');
                  },
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  controller: _directeurLyceeController,
                  focusNode: _directeurLyceeFocusNode,
                  label: 'Chef d\'établissement (Lycée)',
                  prefixIcon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      _directeurUniversityFocusNode.requestFocus(),
                ),
                DropdownButtonFormField<String>(
                  value: _adminCivilityUniversity.isEmpty
                      ? 'M.'
                      : _adminCivilityUniversity,
                  decoration: _buildModernDropdownDecoration(
                    'Civilité (Université)',
                    Icons.badge,
                  ),
                  items: _civilites
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => _adminCivilityUniversity = value ?? 'M.');
                  },
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  controller: _directeurUniversityController,
                  focusNode: _directeurUniversityFocusNode,
                  label: 'Chef d\'établissement (Université)',
                  prefixIcon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _adresseFocusNode.requestFocus(),
                ),
              ],
              _buildModernTextField(
                controller: _mottoController,
                focusNode: _mottoFocusNode,
                label: 'Devise de l\'établissement ',
                prefixIcon: Icons.format_quote,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _adresseFocusNode.requestFocus(),
              ),
              DropdownButtonFormField<String>(
                value: _niveauScolaireController.text.isEmpty
                    ? 'Primaire'
                    : _niveauScolaireController.text,
                decoration: _buildModernDropdownDecoration(
                  'Niveau scolaire',
                  Icons.school,
                ),
                items: _niveauxScolaires.map((niveau) {
                  return DropdownMenuItem(value: niveau, child: Text(niveau));
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _niveauScolaireController.text = value ?? 'Primaire';
                  });
                },
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _adminCivility.isEmpty ? 'M.' : _adminCivility,
                decoration: _buildModernDropdownDecoration(
                  'Civilité du chef d\'établissement',
                  Icons.badge,
                ),
                items: _civilites
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _adminCivility = value ?? 'M.';
                  });
                },
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _ministryController,
                focusNode: _ministryFocusNode,
                label: 'Ministère',
                prefixIcon: Icons.account_balance,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _republicFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _republicController,
                focusNode: _republicFocusNode,
                label: 'République (ex: REPUBLIQUE TOGOLAISE)',
                prefixIcon: Icons.flag_circle,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _republicMottoFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _republicMottoController,
                focusNode: _republicMottoFocusNode,
                label: 'Devise de la République',
                prefixIcon: Icons.flag,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    _educationDirectionFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _educationDirectionController,
                focusNode: _educationDirectionFocusNode,
                label: 'Direction de l\'enseignement',
                prefixIcon: Icons.school,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _inspectionFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _inspectionController,
                focusNode: _inspectionFocusNode,
                label: 'Inspection',
                prefixIcon: Icons.admin_panel_settings,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _bpFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _bpController,
                focusNode: _bpFocusNode,
                label: 'BP',
                prefixIcon: Icons.local_post_office,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _adresseFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _adresseController,
                focusNode: _adresseFocusNode,
                label: 'Adresse complète',
                prefixIcon: Icons.location_on,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _telephoneFocusNode.requestFocus(),
              ),
            ],
            'keywords': [
              'établissement',
              'adresse',
              'bp',
              'code',
              'directeur',
              'niveau',
              'ministère',
              'devise',
              'république',
              'direction',
              'enseignement',
              'inspection',
            ],
          },
          {
            'title': 'Informations de contact',
            'icon': Icons.contact_phone,
            'children': [
              _buildModernTextField(
                controller: _telephoneController,
                focusNode: _telephoneFocusNode,
                label: 'Téléphone',
                prefixIcon: Icons.phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _emailFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                label: 'Email officiel',
                prefixIcon: Icons.email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _siteWebFocusNode.requestFocus(),
              ),
              _buildModernTextField(
                controller: _siteWebController,
                focusNode: _siteWebFocusNode,
                label: 'Site web',
                prefixIcon: Icons.web,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
              ),
            ],
            'keywords': ['contact', 'téléphone', 'email', 'site web'],
          },
          {
            'title': 'Bulletins et PDF',
            'icon': Icons.picture_as_pdf_outlined,
            'children': [
              _buildModernTextField(
                controller: _reportFooterController,
                focusNode: _reportFooterFocusNode,
                label: 'Note de pied de page du bulletin',
                prefixIcon: Icons.description_outlined,
                maxLines: 2,
                textInputAction: TextInputAction.newline,
              ),
            ],
            'keywords': ['bulletin', 'pdf', 'pied de page', 'note', 'export'],
          },
          {
            'title': 'Paramètres de l\'application',
            'icon': Icons.settings,
            'children': [
              _buildModernSwitch(
                title: 'Notifications',
                subtitle: 'Recevoir les notifications push',
                value: _notificationsEnabled,
                icon: Icons.notifications,
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                },
              ),
              _buildModernSwitch(
                title: 'Authentification a double facteur',
                subtitle: 'connection à 2 niveau ',
                value: _biometricEnabled,
                icon: Icons.fingerprint,
                onChanged: (value) {
                  setState(() {
                    _biometricEnabled = value;
                  });
                },
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).shadowColor.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.language,
                        color: Colors.white,
                        size: 20,
                        semanticLabel: 'Langue',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Langue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          Text(
                            'Langue de l\'interface',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    DropdownButton<String>(
                      value: _selectedLanguage,
                      underline: const SizedBox(),
                      items: _languages.map((lang) {
                        return DropdownMenuItem(value: lang, child: Text(lang));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedLanguage = value ?? 'Français';
                        });
                      },
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ],
                ),
              ),
              // Bouton de licence déplacé vers la section "À propos"
            ],
            'keywords': [
              'application',
              'notifications',
              'biométrique',
              'langue',
            ],
          },
          {
            'title': 'Année académique',
            'icon': Icons.calendar_today,
            'children': [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).shadowColor.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.school_outlined,
                        color: Colors.white,
                        size: 20,
                        semanticLabel: 'Année académique',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Année en cours',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          if (_availableYears.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Années disponibles',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _availableYears.map((y) {
                                final selected = y == _academicYear;
                                return ChoiceChip(
                                  label: Text(y),
                                  selected: selected,
                                  onSelected: (_) => _applyAcademicYear(y),
                                  selectedColor: const Color(
                                    0xFF6366F1,
                                  ).withOpacity(0.15),
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? const Color(0xFF6366F1)
                                        : Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _academicYearController,
                            decoration: const InputDecoration(
                              labelText: 'Année scolaire',
                              hintText: 'ex: 2024-2025',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6366F1),
                            ),
                            onChanged: (val) {
                              setState(() {
                                _academicYear = val;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final year = _academicYearController.text
                                      .trim();
                                  if (year.isEmpty) {
                                    _showModernSnackBar(
                                      'Veuillez saisir une année académique.',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  await DatabaseService()
                                      .archiveReportCardsForYear(year);
                                  _showModernSnackBar(
                                    'Tous les bulletins et notes de l\'année $year ont été archivés.',
                                  );
                                },
                                icon: const Icon(Icons.archive),
                                label: const Text('Archiver toute l\'année'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _promptAddYear,
                                icon: const Icon(Icons.add),
                                label: const Text('Ajouter une année'),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  final year =
                                      _academicYearController.text
                                          .trim()
                                          .isNotEmpty
                                      ? _academicYearController.text.trim()
                                      : _academicYear;
                                  _applyAcademicYear(year);
                                },
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Définir comme actuelle'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
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
            ],
            'keywords': ['année', 'académique'],
          },
          {
            'title': 'Gestion des données',
            'icon': Icons.storage,
            'children': [
              _buildModernActionButton(
                label: 'Sauvegarder la base de données',
                icon: Icons.backup,
                onPressed: () => _backupDatabase(context),
                gradientStart: const Color(0xFF3B82F6),
                gradientEnd: const Color(0xFF60A5FA),
                tooltip: 'Créer une sauvegarde de la base de données',
              ),
              _buildModernActionButton(
                label: 'Restaurer la base de données',
                icon: Icons.restore,
                onPressed: () => _restoreDatabase(context),
                gradientStart: const Color(0xFFF59E0B),
                gradientEnd: const Color(0xFFFBBF24),
                tooltip: 'Restaurer une sauvegarde précédente',
              ),
              _buildModernActionButton(
                label: 'Exporter les données',
                icon: Icons.file_download,
                onPressed: _showExportDialog,
                gradientStart: const Color(0xFF10B981),
                gradientEnd: const Color(0xFF34D399),
                tooltip: 'Exporter toutes les données',
              ),
              _buildModernActionButton(
                label: 'Exporter les statistiques (PDF)',
                icon: Icons.insights,
                onPressed: _showExportStatisticsDialog,
                gradientStart: const Color(0xFF0EA5E9),
                gradientEnd: const Color(0xFF38BDF8),
                tooltip: 'Télécharger les statistiques en PDF',
              ),
            ],
            'keywords': ['données', 'sauvegarde', 'restauration', 'export'],
          },
          // {
          //   'title': 'Sécurité',
          //   'icon': Icons.security,
          //   'children': [
          //     _buildModernActionButton(
          //             label: 'Changer le mot de passe administrateur',
          //             icon: Icons.lock_reset,
          //             onPressed: () {
          //         _showModernSnackBar('Changement de mot de passe bientôt disponible.', isError: true);
          //             },
          //       gradientStart: const Color(0xFF7C3AED),
          //       gradientEnd: const Color(0xFF9F7AEA),
          //       tooltip: 'Modifier le mot de passe admin (bientôt disponible)',
          //           ),
          //     _buildModernActionButton(
          //             label: 'Gestion des utilisateurs',
          //             icon: Icons.admin_panel_settings,
          //             onPressed: () {
          //               Navigator.of(context).push(
          //                 MaterialPageRoute(builder: (_) => const UsersManagementPage()),
          //               );
          //             },
          //       gradientStart: const Color(0xFF1E40AF),
          //       gradientEnd: const Color(0xFF3B82F6),
          //       tooltip: 'Créer / supprimer des comptes, activer 2FA',
          //           ),
          //         ],
          //   'keywords': ['sécurité', 'mot de passe', 'permissions'],
          // },
          {
            'title': 'À propos',
            'icon': Icons.info,
            'children': [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).shadowColor.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).shadowColor.withOpacity(0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.school,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'École Management System',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.titleLarge?.color,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '© 2025 Cabinet ACTe',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildAboutPill('Version', '2.1.0 (100)'),
                              _buildAboutPill('Licence', 'Propriétaire'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Divider(
                            height: 1,
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.2),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              SizedBox(
                                width: 320,
                                child: _buildAboutInfoRow(
                                  Icons.apartment,
                                  'Éditeur',
                                  'cabinet ACTe',
                                ),
                              ),
                              SizedBox(
                                width: 320,
                                child: _buildAboutInfoRow(
                                  Icons.language,
                                  'Site web',
                                  'https://www.cabinetacte.com',
                                ),
                              ),
                              SizedBox(
                                width: 320,
                                child: _buildAboutInfoRow(
                                  Icons.email_outlined,
                                  'Email support',
                                  'cabinetactetg@gmail.com',
                                ),
                              ),
                              SizedBox(
                                width: 320,
                                child: _buildAboutInfoRow(
                                  Icons.phone,
                                  'Téléphone',
                                  '+228 92 21 75 64 / +228 90 57 9946',
                                ),
                              ),
                              SizedBox(
                                width: 320,
                                child: _buildAboutInfoRow(
                                  Icons.privacy_tip_outlined,
                                  'Confidentialité',
                                  'Voir la politique',
                                ),
                              ),
                              SizedBox(
                                width: 320,
                                child: _buildAboutInfoRow(
                                  Icons.rule_folder_outlined,
                                  "Conditions d'utilisation",
                                  'Voir les conditions',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            const url = 'https://www.cabinetacte.com';
                            Clipboard.setData(const ClipboardData(text: url));
                            _showModernSnackBar(
                              'Lien du site copié dans le presse-papiers',
                            );
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Visiter le site'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            const email = 'cabinetactetg@gmail.com';
                            Clipboard.setData(const ClipboardData(text: email));
                            _showModernSnackBar('Adresse support copiée');
                          },
                          icon: const Icon(Icons.support_agent),
                          label: const Text('Contacter le support'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _showLicenseDialog,
                          icon: const Icon(Icons.vpn_key_rounded),
                          label: const Text('Voir la licence'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0EA5E9),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            'keywords': ['à propos', 'version', 'école', 'support', 'licence'],
          },
        ].where((section) {
          if (_searchQuery.isEmpty) return true;
          final query = _searchQuery.toLowerCase();
          return section['title'].toString().toLowerCase().contains(query) ||
              (section['keywords'] as List<String>).any(
                (keyword) => keyword.toLowerCase().contains(query),
              );
        }).toList();

    // Build sections and place "À propos" at the very bottom
    final aboutSectionIndex = sections.indexWhere(
      (s) => s['title'] == 'À propos',
    );
    Map<String, dynamic>? aboutSection;
    if (aboutSectionIndex != -1) {
      aboutSection = sections[aboutSectionIndex];
      sections.removeAt(aboutSectionIndex);
    }

    return Scaffold(
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
              _buildHeader(context, isDarkMode, isDesktop),
              // Search field moved to header only; remove duplicate below
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final maxWidth = constraints.maxWidth;
                              final cardWidth = isDesktop
                                  ? (maxWidth - 16) / 2
                                  : maxWidth;
                              return Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildMediaCard(
                                      title: "Logo de l'établissement",
                                      subtitle: 'Touchez pour modifier',
                                      gradientStart: const Color(0xFF6366F1),
                                      gradientEnd: const Color(0xFF8B5CF6),
                                      height: 140,
                                      semanticLabel: "Logo de l'établissement",
                                      imagePath: _logoPath,
                                      placeholderIcon: Icons.school,
                                      onPick: _pickLogo,
                                      removeLabel: 'Supprimer le logo',
                                      isCircle: true,
                                      imageFit: BoxFit.contain,
                                      onRemove: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).cardColor,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            title: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: const [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Color(0xFFE11D48),
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Supprimer le logo ?',
                                                  style: TextStyle(
                                                    color: Color(0xFFE11D48),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            content: const Text(
                                              'Cette action est irréversible.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Annuler'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFE11D48,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Supprimer'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await _removeLogo();
                                        }
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildMediaCard(
                                      title: 'Drapeau du pays',
                                      subtitle: 'Touchez pour modifier',
                                      gradientStart: const Color(0xFF059669),
                                      gradientEnd: const Color(0xFF10B981),
                                      height: 100,
                                      semanticLabel: 'Drapeau du pays',
                                      imagePath: _flagPath,
                                      placeholderIcon: Icons.flag,
                                      onPick: _pickFlag,
                                      removeLabel: 'Supprimer le drapeau',
                                      imageFit: BoxFit.cover,
                                      onRemove: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).cardColor,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            title: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: const [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Color(0xFFE11D48),
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Supprimer le drapeau ?',
                                                  style: TextStyle(
                                                    color: Color(0xFFE11D48),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            content: const Text(
                                              'Cette action est irréversible.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Annuler'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFE11D48,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Supprimer'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await _removeFlag();
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          // Settings sections (without "À propos")
                          ...sections.map(
                            (section) => _buildModernSectionCard(
                              title: section['title'] as String,
                              icon: section['icon'] as IconData,
                              children: section['children'] as List<Widget>,
                            ),
                          ),
                          // Save button
                          _buildModernActionButton(
                            label: 'Enregistrer les modifications',
                            icon: Icons.save,
                            onPressed: _saveSchoolSettings,
                            gradientStart: const Color(0xFF6366F1),
                            gradientEnd: const Color(0xFF8B5CF6),
                            tooltip: 'Sauvegarder tous les paramètres',
                          ),
                          if (aboutSection != null)
                            _buildModernSectionCard(
                              title: aboutSection['title'] as String,
                              icon: aboutSection['icon'] as IconData,
                              children:
                                  aboutSection['children'] as List<Widget>,
                            ),
                        ],
                      ),
                    ),
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
                      Icons.settings,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paramètres',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Configurez les informations de l\'établissement et les préférences de l\'application.',
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
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Rechercher un paramètre...',
              prefixIcon: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.search, color: theme.colorScheme.primary),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.dividerColor.withOpacity(0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: theme.cardColor.withOpacity(0.6),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 16,
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaCard({
    required String title,
    required String subtitle,
    required Color gradientStart,
    required Color gradientEnd,
    required double height,
    required String semanticLabel,
    required String? imagePath,
    required IconData placeholderIcon,
    required VoidCallback onPick,
    required String removeLabel,
    VoidCallback? onRemove,
    bool isCircle = false,
    BoxFit imageFit = BoxFit.cover,
  }) {
    final hasImage = imagePath != null && File(imagePath!).existsSync();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.titleMedium?.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onPick,
            child: Container(
              width: double.infinity,
              height: height,
              decoration: BoxDecoration(
                shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isCircle ? null : BorderRadius.circular(14),
                gradient: LinearGradient(colors: [gradientStart, gradientEnd]),
                boxShadow: [
                  BoxShadow(
                    color: gradientStart.withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: isCircle
                    ? BorderRadius.circular(999)
                    : BorderRadius.circular(14),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.18),
                              Colors.black.withOpacity(0.12),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.cardColor.withOpacity(0.35),
                            borderRadius: isCircle
                                ? BorderRadius.circular(999)
                                : BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: hasImage
                                ? (isCircle
                                      ? ClipOval(
                                          child: Image.file(
                                            File(imagePath!),
                                            key: ValueKey(imagePath),
                                            fit: imageFit,
                                          ),
                                        )
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Image.file(
                                            File(imagePath!),
                                            key: ValueKey(imagePath),
                                            fit: imageFit,
                                          ),
                                        ))
                                : Column(
                                    key: const ValueKey('placeholder'),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        placeholderIcon,
                                        color: Colors.white,
                                        size: 44,
                                        semanticLabel: semanticLabel,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Aperçu',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.edit, color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'Modifier',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasImage && onRemove != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: Text(
                  removeLabel,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAboutInfoRow(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    final color = Theme.of(context).textTheme.bodyMedium?.color;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      subtitle: Text(value, style: TextStyle(color: color)),
      onTap: onTap,
      dense: true,
    );
  }

  Widget _buildAboutPill(String label, String value) {
    final color = Theme.of(context).textTheme.bodyMedium?.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: color, fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
