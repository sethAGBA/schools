import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:school_manager/models/user.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/permission_group.dart';
import 'package:school_manager/models/user_session.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/permission_service.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:school_manager/widgets/confirm_dialog.dart';
import 'package:school_manager/constants/colors.dart';
import 'package:school_manager/constants/sizes.dart';

class UsersManagementPage extends StatefulWidget {
  const UsersManagementPage({super.key});

  @override
  State<UsersManagementPage> createState() => _UsersManagementPageState();
}

class _UsersManagementPageState extends State<UsersManagementPage> {
  List<AppUser> _users = [];
  List<PermissionGroup> _permissionGroups = [];
  List<Staff> _staff = [];
  bool _loading = true;
  AppUser? _current;
  String? _filterRole;

  final Map<String, String> _permissionTranslations = {
    'view_dashboard': 'Voir le tableau de bord',
    'view_students': 'Voir les élèves',
    'view_staff': 'Voir le personnel',
    'view_grades': 'Voir les notes',
    'view_payments': 'Voir les paiements',
    'view_settings': 'Voir les paramètres',
    'view_users': 'Voir les utilisateurs',
    'manage_users': 'Gérer les utilisateurs',
    'manage_permissions': 'Gérer les permissions',
    'view_timetables': 'Voir les emplois du temps',
    'view_license': 'Voir la licence',
    'view_subjects': 'Voir les matières',
    'view_finance_inventory': 'Voir les finances et inventaires',
    'manage_safe_mode': 'Gérer le mode coffre fort',
    'view_audit_log': 'Voir les audits', // rétrocompatibilité libellé
    'view_audits': 'Voir les audits',
    'view_signatures': 'Voir Signatures & Cachets',
    'view_library': 'Voir la bibliothèque',
    'view_discipline': 'Voir le suivi de discipline',
  };

  List<AppUser> get _filteredUsers {
    if (_filterRole == null) return _users;
    return _users.where((u) => u.role == _filterRole).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseService().getAllUserRows();
    final groups = await DatabaseService().getPermissionGroups();
    final staff = await DatabaseService().getStaff();
    final me = await AuthService.instance.getCurrentUser();
    setState(() {
      _users = rows.map(AppUser.fromMap).toList();
      _permissionGroups = groups;
      _staff = staff..sort((a, b) => a.name.compareTo(b.name));
      _loading = false;
      _current = me;
    });
  }

  bool _ensureWriteAllowed() {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return false;
    }
    return true;
  }

  bool _isLocked(AppUser u) {
    final lockedUntil = (u.lockedUntil ?? '').trim();
    if (lockedUntil.isEmpty) return false;
    final until = DateTime.tryParse(lockedUntil);
    return until != null && until.isAfter(DateTime.now());
  }

  Future<void> _showResetPasswordDialog(AppUser user) async {
    final pwdCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscurePwd = true;
    bool obscureConfirm = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSB) => AlertDialog(
          title: Text('Réinitialiser mot de passe - ${user.username}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pwdCtrl,
                  obscureText: obscurePwd,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: obscurePwd ? 'Afficher' : 'Masquer',
                      onPressed: () =>
                          setStateSB(() => obscurePwd = !obscurePwd),
                      icon: Icon(
                        obscurePwd ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                    border: const OutlineInputBorder(),
                    helperText: 'Minimum 8 caractères',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: obscureConfirm,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: obscureConfirm ? 'Afficher' : 'Masquer',
                      onPressed: () =>
                          setStateSB(() => obscureConfirm = !obscureConfirm),
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                    border: const OutlineInputBorder(),
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
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (!_ensureWriteAllowed()) return;

    final pwd = pwdCtrl.text.trim();
    final confirm = confirmCtrl.text.trim();
    if (pwd.length < 8) {
      if (!mounted) return;
      showSnackBar(context, 'Mot de passe trop court (min 8).', isError: true);
      return;
    }
    if (pwd != confirm) {
      if (!mounted) return;
      showSnackBar(
        context,
        'Les mots de passe ne correspondent pas.',
        isError: true,
      );
      return;
    }

    await AuthService.instance.updateUser(
      username: user.username,
      newPassword: pwd,
    );
    if (!mounted) return;
    showSnackBar(context, 'Mot de passe mis à jour');
  }

  Future<void> _showUserActivityDialog(AppUser user) async {
    final logs = await DatabaseService().getAuditLogsForUser(
      username: user.username,
      limit: 300,
    );
    String fmtTs(String ts) {
      final s = ts.replaceFirst('T', ' ');
      return s.length >= 16 ? s.substring(0, 16) : s;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Journal d’activité - ${user.username}'),
        content: SizedBox(
          width: 900,
          child: logs.isEmpty
              ? const Text('Aucune activité trouvée.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = logs[i];
                    final ts = l['timestamp']?.toString() ?? '';
                    final cat = l['category']?.toString() ?? '';
                    final act = l['action']?.toString() ?? '';
                    final det = l['details']?.toString() ?? '';
                    final success = (l['success'] as int? ?? 1) == 1;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        success
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: success ? Colors.green : Colors.red,
                      ),
                      title: Text('$cat - $act'),
                      subtitle: Text('${fmtTs(ts)}\n$det'),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUserSessionsDialog(AppUser user) async {
    final sessions = await DatabaseService().getUserSessions(
      username: user.username,
      limit: 200,
    );
    final now = DateTime.now();
    String fmtTs(String ts) {
      final s = ts.replaceFirst('T', ' ');
      return s.length >= 16 ? s.substring(0, 16) : s;
    }

    bool isSessionActive(UserSession s) {
      if ((s.logoutAt ?? '').trim().isNotEmpty) return false;
      final last = DateTime.tryParse(s.lastSeenAt);
      if (last == null) return false;
      return now.difference(last).inMinutes <= 10;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sessions - ${user.username}'),
        content: SizedBox(
          width: 900,
          child: sessions.isEmpty
              ? const Text('Aucune session.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    final active = isSessionActive(s);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        active ? Icons.circle : Icons.circle_outlined,
                        color: active ? Colors.green : Colors.grey,
                        size: 14,
                      ),
                      title: Text('Login: ${fmtTs(s.loginAt)}'),
                      subtitle: Text(
                        'Dernière activité: ${fmtTs(s.lastSeenAt)}'
                        '${(s.logoutAt ?? '').trim().isEmpty ? '' : '\nLogout: ${fmtTs(s.logoutAt!)}'}',
                      ),
                      trailing:
                          (s.id != null && (s.logoutAt ?? '').trim().isEmpty)
                          ? TextButton(
                              onPressed: () async {
                                if (!_ensureWriteAllowed()) return;
                                await DatabaseService().endUserSession(s.id!);
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                await _showUserSessionsDialog(user);
                              },
                              child: const Text('Terminer'),
                            )
                          : null,
                      isThreeLine: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionGroupsDialog() async {
    Future<void> showEdit({PermissionGroup? existing}) async {
      final nameCtrl = TextEditingController(text: existing?.name ?? '');
      Set<String> selectedPerms = existing != null
          ? Set<String>.from(existing.decodePermissions())
          : <String>{};

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateSB) => AlertDialog(
            title: Text(
              existing == null ? 'Nouveau groupe' : 'Modifier groupe',
            ),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom du groupe',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Permissions',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in {
                          ...PermissionService.defaultAdminPermissions,
                          ...PermissionService.defaultStaffPermissions,
                          ...PermissionService.defaultTeacherPermissions,
                        })
                          FilterChip(
                            selected: selectedPerms.contains(p),
                            label: Text(_permissionTranslations[p] ?? p),
                            onSelected: (sel) => setStateSB(() {
                              if (sel) {
                                selectedPerms.add(p);
                              } else {
                                selectedPerms.remove(p);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      );

      if (ok != true) return;
      if (!_ensureWriteAllowed()) return;

      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        if (!mounted) return;
        showSnackBar(context, 'Nom du groupe requis.', isError: true);
        return;
      }

      String? by;
      try {
        by = (_current?.displayName.trim().isNotEmpty == true)
            ? _current!.displayName
            : _current?.username;
      } catch (_) {}

      await DatabaseService().upsertPermissionGroup(
        id: existing?.id,
        name: name,
        permissionsJson: PermissionService.encodePermissions(selectedPerms),
        updatedBy: by,
      );
      await _load();
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Groupes de permissions'),
        content: SizedBox(
          width: 820,
          child: _permissionGroups.isEmpty
              ? const Text('Aucun groupe.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _permissionGroups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final g = _permissionGroups[i];
                    return ListTile(
                      title: Text(g.name),
                      subtitle: Text(
                        '${g.decodePermissions().length} permission(s)',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Modifier',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await showEdit(existing: g);
                              await _showPermissionGroupsDialog();
                            },
                          ),
                          IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () async {
                              if (g.id == null) return;
                              if (!_ensureWriteAllowed()) return;
                              final confirm = await showDangerConfirmDialog(
                                context,
                                title: 'Supprimer le groupe',
                                message:
                                    'Supprimer “${g.name}” ? Cette action est irréversible.',
                              );
                              if (confirm == true) {
                                await DatabaseService().deletePermissionGroup(
                                  g.id!,
                                );
                                await _load();
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                await _showPermissionGroupsDialog();
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await showEdit();
              await _showPermissionGroupsDialog();
            },
            icon: const Icon(Icons.add),
            label: const Text('Nouveau'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showActiveSessionsDialog() async {
    final sessions = await DatabaseService().getUserSessions(
      onlyActive: true,
      limit: 300,
    );
    final now = DateTime.now();
    String fmtTs(String ts) {
      final s = ts.replaceFirst('T', ' ');
      return s.length >= 16 ? s.substring(0, 16) : s;
    }

    bool isActive(UserSession s) {
      if ((s.logoutAt ?? '').trim().isNotEmpty) return false;
      final last = DateTime.tryParse(s.lastSeenAt);
      if (last == null) return false;
      return now.difference(last).inMinutes <= 10;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sessions actives'),
        content: SizedBox(
          width: 900,
          child: sessions.isEmpty
              ? const Text('Aucune session active.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    final active = isActive(s);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        active ? Icons.circle : Icons.circle_outlined,
                        color: active ? Colors.green : Colors.grey,
                        size: 14,
                      ),
                      title: Text('${s.username} - Login: ${fmtTs(s.loginAt)}'),
                      subtitle: Text(
                        'Dernière activité: ${fmtTs(s.lastSeenAt)}',
                      ),
                      trailing:
                          (s.id != null && (s.logoutAt ?? '').trim().isEmpty)
                          ? TextButton(
                              onPressed: () async {
                                if (!_ensureWriteAllowed()) return;
                                await DatabaseService().endUserSession(s.id!);
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                await _showActiveSessionsDialog();
                              },
                              child: const Text('Terminer'),
                            )
                          : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateUserDialog() async {
    final usernameCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController();
    String role = 'staff';
    String? selectedStaffId;
    final passwordCtrl = TextEditingController();
    final passwordConfirmCtrl = TextEditingController();
    bool enable2FA = false;
    int? selectedGroupId;
    Set<String> selectedPerms = Set<String>.from(
      PermissionService.defaultForRole(role),
    );
    bool obscurePwd = true;
    bool obscureConfirm = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSB) => AlertDialog(
          title: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
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
                        Icons.person_add,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Créer un nouvel utilisateur'),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom d\'utilisateur',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom affiché',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.admin_panel_settings, size: 20),
                      const SizedBox(width: 8),
                      const Text('Rôle:'),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: role,
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Administrateur'),
                          ),
                          DropdownMenuItem(
                            value: 'staff',
                            child: Text('Personnel'),
                          ),
                          DropdownMenuItem(
                            value: 'prof',
                            child: Text('Professeur'),
                          ),
                          DropdownMenuItem(
                            value: 'viewer',
                            child: Text('Observateur'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setStateSB(() {
                            role = val;
                            // Reset linked staff when role changes (optional link).
                            selectedStaffId = null;
                            selectedGroupId = null;
                            selectedPerms = Set<String>.from(
                              PermissionService.defaultForRole(role),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: selectedStaffId,
                    decoration: InputDecoration(
                      labelText: role == 'prof'
                          ? 'Lier à un professeur (personnel)'
                          : 'Lier à une fiche personnel (optionnel)',
                      prefixIcon: const Icon(Icons.badge),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Aucun lien'),
                      ),
                      ..._staff
                          .where((s) {
                            if (role == 'prof')
                              return s.typeRole == 'Professeur';
                            if (role == 'staff')
                              return s.typeRole != 'Professeur';
                            return true;
                          })
                          .map(
                            (s) => DropdownMenuItem<String?>(
                              value: s.id,
                              child: Text('${s.name} (${s.typeRole})'),
                            ),
                          ),
                    ],
                    onChanged: (v) => setStateSB(() => selectedStaffId = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: selectedGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Groupe de permissions (optionnel)',
                      prefixIcon: Icon(Icons.group_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Aucun groupe'),
                      ),
                      ..._permissionGroups
                          .where((g) => g.id != null)
                          .map(
                            (g) => DropdownMenuItem<int?>(
                              value: g.id,
                              child: Text(g.name),
                            ),
                          ),
                    ],
                    onChanged: (id) {
                      setStateSB(() {
                        selectedGroupId = id;
                        final group = _permissionGroups
                            .where((g) => g.id == id)
                            .toList();
                        if (group.isNotEmpty) {
                          selectedPerms = Set<String>.from(
                            group.first.decodePermissions(),
                          );
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: obscurePwd,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: obscurePwd ? 'Afficher' : 'Masquer',
                        onPressed: () =>
                            setStateSB(() => obscurePwd = !obscurePwd),
                        icon: Icon(
                          obscurePwd ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                      helperText: 'Minimum 8 caractères',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordConfirmCtrl,
                    obscureText: obscureConfirm,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: 'Confirmer le mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: obscureConfirm ? 'Afficher' : 'Masquer',
                        onPressed: () =>
                            setStateSB(() => obscureConfirm = !obscureConfirm),
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Activer 2FA (TOTP)'),
                    subtitle: const Text('Authentification à deux facteurs'),
                    value: enable2FA,
                    onChanged: (v) => setStateSB(() => enable2FA = v),
                    secondary: const Icon(Icons.security),
                  ),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Permissions',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in {
                        ...PermissionService.defaultAdminPermissions,
                        ...PermissionService.defaultStaffPermissions,
                        ...PermissionService.defaultTeacherPermissions,
                      })
                        FilterChip(
                          selected: selectedPerms.contains(p),
                          label: Text(_permissionTranslations[p] ?? p),
                          onSelected: (sel) => setStateSB(() {
                            if (sel) {
                              selectedPerms.add(p);
                            } else {
                              selectedPerms.remove(p);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final username = usernameCtrl.text.trim();
      final displayName = displayNameCtrl.text.trim();
      final password = passwordCtrl.text.trim();
      final confirm = passwordConfirmCtrl.text.trim();
      if (role == 'prof' && selectedStaffId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pour un compte professeur, veuillez lier une fiche personnel.',
              ),
            ),
          );
        }
        return;
      }
      if (username.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Le nom d\'utilisateur est obligatoire.'),
            ),
          );
        }
        return;
      }
      if (password.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Le mot de passe est obligatoire.')),
          );
        }
        return;
      }
      if (password.length < 8) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Le mot de passe doit contenir au moins 8 caractères.',
              ),
            ),
          );
        }
        return;
      }
      if (password != confirm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Les mots de passe ne correspondent pas.'),
            ),
          );
        }
        return;
      }
      if (selectedStaffId != null) {
        final alreadyLinked = _users.any((u) => u.staffId == selectedStaffId);
        if (alreadyLinked) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Cette fiche personnel est déjà liée à un autre compte.',
                ),
              ),
            );
          }
          return;
        }
      }
      if (!_ensureWriteAllowed()) return;
      await AuthService.instance.createOrUpdateUser(
        username: username,
        displayName: displayName,
        role: role,
        password: password,
        enable2FA: enable2FA,
        permissions: selectedPerms,
        staffId: selectedStaffId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur créé avec succès.')),
        );
      }
    }
  }

  Future<void> _deleteUser(String username) async {
    // Prevent deleting the last admin
    final rows = await DatabaseService().getUserRowByUsername(username);
    if (rows != null) {
      final role = rows['role'] as String?;
      if (role == 'admin') {
        final adminsCount = await _countAdminsTotal();
        if (adminsCount <= 1) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Impossible de supprimer le dernier compte admin.',
                ),
              ),
            );
          }
          return;
        }
      }
    }

    final confirmed = await showDangerConfirmDialog(
      context,
      title: 'Supprimer l\'utilisateur',
      message:
          'Voulez-vous vraiment supprimer l\'utilisateur $username ? Cette action est irréversible.',
    );

    if (confirmed == true) {
      if (!_ensureWriteAllowed()) return;
      final userToDelete = _users.firstWhere(
        (u) => u.username == username,
      ); // Get the user object before deletion
      await DatabaseService().deleteUserByUsername(username);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Utilisateur $username supprimé avec succès.'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Annuler',
              onPressed: () async {
                // Re-insert the user
                await AuthService.instance.createOrUpdateUser(
                  username: userToDelete.username,
                  displayName: userToDelete.displayName,
                  role: userToDelete.role,
                  password:
                      '', // Password cannot be re-inserted directly, user will need to set a new one
                  enable2FA: userToDelete.isTwoFactorEnabled,
                  permissions: PermissionService.decodePermissions(
                    userToDelete.permissions,
                    role: userToDelete.role,
                  ),
                  secret2FA:
                      userToDelete.totpSecret, // Pass the original totpSecret
                  staffId: userToDelete.staffId,
                );
                await _load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Suppression annulée. L\'utilisateur a été restauré (le mot de passe peut nécessiter une réinitialisation).',
                      ),
                      backgroundColor: Colors.blue,
                    ),
                  );
                }
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _showEditUserDialog(AppUser user) async {
    final displayNameCtrl = TextEditingController(text: user.displayName);
    String role = user.role;
    String? selectedStaffId = user.staffId;
    final passwordCtrl = TextEditingController();
    final passwordConfirmCtrl = TextEditingController();
    bool enable2FA = user.isTwoFactorEnabled;
    int? selectedGroupId;
    Set<String> selectedPerms = Set<String>.from(
      PermissionService.decodePermissions(user.permissions, role: role),
    );
    bool obscurePwd = true;
    bool obscureConfirm = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSB) => AlertDialog(
          title: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
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
                        Icons.edit,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('Modifier ${user.username}'),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom affiché',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.admin_panel_settings, size: 20),
                      const SizedBox(width: 8),
                      const Text('Rôle:'),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: role,
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Administrateur'),
                          ),
                          DropdownMenuItem(
                            value: 'staff',
                            child: Text('Personnel'),
                          ),
                          DropdownMenuItem(
                            value: 'prof',
                            child: Text('Professeur'),
                          ),
                          DropdownMenuItem(
                            value: 'viewer',
                            child: Text('Observateur'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setStateSB(() {
                            role = val;
                            selectedGroupId = null;
                            selectedPerms = Set<String>.from(
                              PermissionService.defaultForRole(role),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: selectedStaffId,
                    decoration: InputDecoration(
                      labelText: role == 'prof'
                          ? 'Lier à un professeur (personnel)'
                          : 'Lier à une fiche personnel (optionnel)',
                      prefixIcon: const Icon(Icons.badge),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Aucun lien'),
                      ),
                      ..._staff
                          .where((s) {
                            if (role == 'prof')
                              return s.typeRole == 'Professeur';
                            if (role == 'staff')
                              return s.typeRole != 'Professeur';
                            return true;
                          })
                          .map(
                            (s) => DropdownMenuItem<String?>(
                              value: s.id,
                              child: Text('${s.name} (${s.typeRole})'),
                            ),
                          ),
                    ],
                    onChanged: (v) => setStateSB(() => selectedStaffId = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: selectedGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Groupe de permissions (optionnel)',
                      prefixIcon: Icon(Icons.group_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Aucun groupe'),
                      ),
                      ..._permissionGroups
                          .where((g) => g.id != null)
                          .map(
                            (g) => DropdownMenuItem<int?>(
                              value: g.id,
                              child: Text(g.name),
                            ),
                          ),
                    ],
                    onChanged: (id) {
                      setStateSB(() {
                        selectedGroupId = id;
                        final group = _permissionGroups
                            .where((g) => g.id == id)
                            .toList();
                        if (group.isNotEmpty) {
                          selectedPerms = Set<String>.from(
                            group.first.decodePermissions(),
                          );
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: obscurePwd,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText:
                          'Nouveau mot de passe (laisser vide pour conserver)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: obscurePwd ? 'Afficher' : 'Masquer',
                        onPressed: () =>
                            setStateSB(() => obscurePwd = !obscurePwd),
                        icon: Icon(
                          obscurePwd ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                      helperText:
                          'Laissez vide pour conserver le mot de passe actuel',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordConfirmCtrl,
                    obscureText: obscureConfirm,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: 'Confirmer le mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: obscureConfirm ? 'Afficher' : 'Masquer',
                        onPressed: () =>
                            setStateSB(() => obscureConfirm = !obscureConfirm),
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Activer 2FA (TOTP)'),
                    subtitle: const Text('Authentification à deux facteurs'),
                    value: enable2FA,
                    onChanged: (v) => setStateSB(() => enable2FA = v),
                    secondary: const Icon(Icons.security),
                  ),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Permissions',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in {
                        ...PermissionService.defaultAdminPermissions,
                        ...PermissionService.defaultStaffPermissions,
                        ...PermissionService.defaultTeacherPermissions,
                      })
                        FilterChip(
                          selected: selectedPerms.contains(p),
                          label: Text(_permissionTranslations[p] ?? p),
                          onSelected: (sel) => setStateSB(() {
                            if (sel) {
                              selectedPerms.add(p);
                            } else {
                              selectedPerms.remove(p);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final displayName = displayNameCtrl.text.trim();
      final newPwd = passwordCtrl.text.trim();
      final confirm = passwordConfirmCtrl.text.trim();
      // Prevent demoting the last admin
      if (user.role == 'admin' && role != 'admin') {
        final adminsCount = await _countAdminsTotal();
        if (adminsCount <= 1) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Impossible de rétrograder le dernier compte admin.',
                ),
              ),
            );
          }
          return;
        }
        final confirmDemote = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmation'),
            content: const Text(
              'Êtes-vous sûr de vouloir rétrograder cet administrateur ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        );
        if (confirmDemote != true) return;
      }
      if (newPwd.isNotEmpty) {
        if (newPwd.length < 8) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Le mot de passe doit contenir au moins 8 caractères.',
                ),
              ),
            );
          }
          return;
        }
        if (newPwd != confirm) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Les mots de passe ne correspondent pas.'),
              ),
            );
          }
          return;
        }
      }

      if (role == 'prof' && selectedStaffId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pour un compte professeur, veuillez lier une fiche personnel.',
              ),
            ),
          );
        }
        return;
      }
      if (selectedStaffId != null) {
        final alreadyLinked = _users.any(
          (u) => u.staffId == selectedStaffId && u.username != user.username,
        );
        if (alreadyLinked) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Cette fiche personnel est déjà liée à un autre compte.',
                ),
              ),
            );
          }
          return;
        }
      }

      if (!_ensureWriteAllowed()) return;
      await AuthService.instance.updateUser(
        username: user.username,
        displayName: displayName.isEmpty ? null : displayName,
        role: role,
        newPassword: newPwd.isEmpty ? null : newPwd,
        enable2FA: enable2FA,
        permissions: selectedPerms,
        staffId: selectedStaffId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur mis à jour avec succès.')),
        );
      }
    }
  }

  Future<int> _countAdmins() async {
    final rows = await DatabaseService().getAllUserRows();
    return rows
        .where((r) => (r['role'] as String?) == 'admin')
        .where((r) => (r['isActive'] as int? ?? 1) == 1)
        .length;
  }

  Future<int> _countAdminsTotal() async {
    final rows = await DatabaseService().getAllUserRows();
    return rows.where((r) => (r['role'] as String?) == 'admin').length;
  }

  @override
  Widget build(BuildContext context) {
    final perms = PermissionService.decodePermissions(
      _current?.permissions,
      role: _current?.role ?? 'staff',
    );
    final bool isAdmin = _current?.role == 'admin';
    final bool canManage = isAdmin || perms.contains('manage_users');
    final bool allowed = canManage || perms.contains('view_users');

    if (!allowed) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.color?.withOpacity(0.5),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Accès refusé',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Vous n\'avez pas les permissions nécessaires pour accéder à cette page.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          constraints: BoxConstraints(maxWidth: 960),
          margin: EdgeInsets.symmetric(horizontal: AppSizes.padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: AppSizes.padding),
              _buildHeader(context, isDesktop),
              SizedBox(height: AppSizes.padding),
              Expanded(
                child: SingleChildScrollView(child: _buildUsersList(context)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isDesktop) {
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
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des utilisateurs',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Gérez les comptes utilisateurs, leurs rôles et permissions.',
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
              Row(
                children: [
                  if (_current?.role == 'admin' ||
                      PermissionService.decodePermissions(
                        _current?.permissions,
                        role: _current?.role ?? 'staff',
                      ).contains('manage_users'))
                    ElevatedButton.icon(
                      onPressed: _showCreateUserDialog,
                      icon: Icon(Icons.add),
                      label: Text('Nouvel utilisateur'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  if (_current?.role == 'admin' ||
                      PermissionService.decodePermissions(
                        _current?.permissions,
                        role: _current?.role ?? 'staff',
                      ).contains('manage_users')) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _showPermissionGroupsDialog,
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Groupes'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _showActiveSessionsDialog,
                      icon: const Icon(Icons.login),
                      label: const Text('Sessions'),
                    ),
                  ],
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
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Filtre rôle
                DropdownButton<String?>(
                  value: _filterRole,
                  hint: Text(
                    'Rôle',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Tous les rôles',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'admin',
                      child: Text(
                        'Administrateurs',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'staff',
                      child: Text(
                        'Personnel',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'prof',
                      child: Text(
                        'Professeurs',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'viewer',
                      child: Text(
                        'Observateurs',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _filterRole = value),
                  dropdownColor: theme.cardColor,
                  iconEnabledColor: theme.iconTheme.color,
                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                ),
                const SizedBox(width: 16),
                // Bouton rafraîchir
                IconButton(
                  onPressed: _load,
                  icon: Icon(Icons.refresh, color: theme.iconTheme.color),
                  tooltip: 'Rafraîchir',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList(BuildContext context) {
    final theme = Theme.of(context);
    final perms = PermissionService.decodePermissions(
      _current?.permissions,
      role: _current?.role ?? 'staff',
    );
    final bool isAdmin = _current?.role == 'admin';
    final bool canManage = isAdmin || perms.contains('manage_users');

    if (_loading) {
      return Container(
        height: 400,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Utilisateurs (${_filteredUsers.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _filteredUsers.length,
            separatorBuilder: (_, __) => Divider(height: 1),
            itemBuilder: (ctx, i) {
              final u = _filteredUsers[i];
              final raw = (u.displayName.trim().isNotEmpty
                  ? u.displayName.trim()
                  : u.username.trim());
              final initial = raw.isNotEmpty
                  ? raw.substring(0, 1).toUpperCase()
                  : '?';
              final titleText = raw.isNotEmpty ? raw : 'Utilisateur';

              return Container(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  titleText,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ),
                              _buildRoleBadge(u.role),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            [
                              u.username,
                              if (u.isTwoFactorEnabled) '2FA activé',
                              if (!u.isActive) 'Désactivé',
                              if (_isLocked(u)) 'Verrouillé',
                            ].join(' - '),
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canManage) ...[
                      PopupMenuButton<String>(
                        tooltip: 'Actions',
                        icon: Icon(
                          Icons.more_vert,
                          color: theme.iconTheme.color,
                        ),
                        onSelected: (value) async {
                          final isMe = _current?.username == u.username;
                          if (value == 'edit') {
                            await _showEditUserDialog(u);
                          } else if (value == 'reset_password') {
                            await _showResetPasswordDialog(u);
                          } else if (value == 'toggle_active') {
                            if (isMe) return;
                            if (!_ensureWriteAllowed()) return;
                            if (u.role == 'admin' && u.isActive) {
                              final totalAdmins = await _countAdminsTotal();
                              final activeAdmins = await _countAdmins();
                              if (totalAdmins <= 1 || activeAdmins <= 1) {
                                if (!mounted) return;
                                showSnackBar(
                                  context,
                                  'Impossible de désactiver le dernier admin.',
                                  isError: true,
                                );
                                return;
                              }
                            }
                            String? by;
                            try {
                              by =
                                  (_current?.displayName.trim().isNotEmpty ==
                                      true)
                                  ? _current!.displayName
                                  : _current?.username;
                            } catch (_) {}
                            await DatabaseService().setUserActive(
                              username: u.username,
                              isActive: !u.isActive,
                              by: by,
                            );
                            await _load();
                          } else if (value == 'unlock') {
                            if (!_ensureWriteAllowed()) return;
                            String? by;
                            try {
                              by =
                                  (_current?.displayName.trim().isNotEmpty ==
                                      true)
                                  ? _current!.displayName
                                  : _current?.username;
                            } catch (_) {}
                            await DatabaseService().unlockUser(
                              username: u.username,
                              by: by,
                            );
                            await _load();
                          } else if (value == 'activity') {
                            await _showUserActivityDialog(u);
                          } else if (value == 'sessions') {
                            await _showUserSessionsDialog(u);
                          } else if (value == '2fa') {
                            final uri = await AuthService.instance
                                .getTotpProvisioningUri(u.username);
                            if (!mounted) return;
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Configurer 2FA'),
                                content: SizedBox(
                                  width: 320,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (uri != null && uri.isNotEmpty)
                                        QrImageView(
                                          data: uri,
                                          version: QrVersions.auto,
                                          size: 220.0,
                                        ),
                                      const SizedBox(height: 12),
                                      SelectableText(
                                        (uri == null)
                                            ? 'Aucun secret TOTP.'
                                            : 'Scannez ce lien dans Google Authenticator / Authy:\n\n$uri',
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Fermer'),
                                  ),
                                ],
                              ),
                            );
                          } else if (value == 'delete') {
                            if (isMe) return;
                            if (!_ensureWriteAllowed()) return;
                            if (u.role == 'admin') {
                              final totalAdmins = await _countAdminsTotal();
                              if (totalAdmins <= 1) {
                                if (!mounted) return;
                                showSnackBar(
                                  context,
                                  'Impossible de supprimer le dernier admin.',
                                  isError: true,
                                );
                                return;
                              }
                            }
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Theme.of(context).cardColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: Color(0xFFE11D48),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Supprimer cet utilisateur ?',
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
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Annuler'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE11D48),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Supprimer'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _deleteUser(u.username);
                            }
                          }
                        },
                        itemBuilder: (context) {
                          final isMe = _current?.username == u.username;
                          final locked = _isLocked(u);
                          return [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: const [
                                  Icon(Icons.edit_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Modifier'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'reset_password',
                              child: Row(
                                children: const [
                                  Icon(Icons.lock_reset, size: 18),
                                  SizedBox(width: 8),
                                  Text('Réinitialiser mot de passe'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle_active',
                              enabled: !isMe,
                              child: Row(
                                children: [
                                  Icon(
                                    u.isActive
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(u.isActive ? 'Désactiver' : 'Activer'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'unlock',
                              enabled: locked,
                              child: Row(
                                children: const [
                                  Icon(Icons.lock_open_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Déverrouiller'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'activity',
                              child: Row(
                                children: const [
                                  Icon(Icons.history, size: 18),
                                  SizedBox(width: 8),
                                  Text('Journal d’activité'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'sessions',
                              child: Row(
                                children: const [
                                  Icon(Icons.login, size: 18),
                                  SizedBox(width: 8),
                                  Text('Sessions'),
                                ],
                              ),
                            ),
                            if (u.isTwoFactorEnabled)
                              PopupMenuItem(
                                value: '2fa',
                                child: Row(
                                  children: const [
                                    Icon(Icons.key_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('Afficher 2FA'),
                                  ],
                                ),
                              ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'delete',
                              enabled: !isMe,
                              child: Row(
                                children: const [
                                  Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Supprimer'),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    Color color;
    String label;
    switch (role) {
      case 'admin':
        color = Colors.red;
        label = 'ADMIN';
        break;
      case 'staff':
        color = AppColors.primaryBlue;
        label = 'STAFF';
        break;
      case 'prof':
        color = AppColors.successGreen;
        label = 'PROF';
        break;
      case 'viewer':
        color = Colors.grey;
        label = 'VIEWER';
        break;
      default:
        color = Colors.grey;
        label = role.toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
