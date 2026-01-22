import 'package:flutter/material.dart';
import 'package:school_manager/main.dart';
import 'package:school_manager/utils/snackbar.dart';
// import 'package:school_manager/services/auth_service.dart'; // Unused
import 'package:school_manager/widgets/safe_mode_indicator.dart';
import 'dart:math';

class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final bool isDarkMode;
  final Function(bool) onThemeToggle;
  final AnimationController animationController;
  final String? currentRole;
  final Set<String>? currentPermissions;
  final Set<int>? allowedIndices;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;

  Sidebar({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.animationController,
    this.currentRole,
    this.currentPermissions,
    this.allowedIndices,
    this.isCollapsed = false,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isCollapsed ? 80 : 280,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode
              ? [Color(0xFF1E3A8A), Color(0xFF3B82F6)]
              : [Color(0xFF60A5FA), Color(0xFF93C5FD)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 8 : 24,
              vertical: 24,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: animationController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: animationController.value * 2 * pi,
                          child: Icon(
                            Icons.school,
                            size: isCollapsed ? 32 : 40,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    if (!isCollapsed) ...[
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'École Manager',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                          overflow: TextOverflow.clip,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ],
                ),
                if (!isCollapsed) ...[
                  SizedBox(height: 16),
                  const SafeModeIndicator(),
                ],
                if (isCollapsed) SizedBox(height: 16),
                IconButton(
                  onPressed: onToggleCollapse,
                  icon: Icon(
                    isCollapsed
                        ? Icons.keyboard_double_arrow_right
                        : Icons.keyboard_double_arrow_left,
                    color: Colors.white70,
                  ),
                  tooltip: isCollapsed ? 'Agrandir' : 'Réduire',
                ),
              ],
            ),
          ),
          Divider(color: Theme.of(context).dividerColor),
          if (!isCollapsed) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Container(
                width: 280, // Force sufficient width for layout
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        isDarkMode ? 'Mode Sombre' : 'Mode Clair',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.fade,
                        maxLines: 1,
                      ),
                    ),
                    Switch(
                      value: isDarkMode,
                      onChanged: onThemeToggle,
                      activeColor: Colors.blue[300],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            IconButton(
              onPressed: () => onThemeToggle(!isDarkMode),
              icon: Icon(
                isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: Colors.white,
              ),
              tooltip: isDarkMode ? 'Mode Clair' : 'Mode Sombre',
            ),
          ],
          Divider(color: Theme.of(context).dividerColor),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  _buildMenuItem(
                    context,
                    0,
                    Icons.dashboard,
                    'Tableau de bord',
                  ),
                  _buildMenuItem(context, 1, Icons.people, 'Élèves & Classes'),
                  _buildMenuItem(context, 2, Icons.person, 'Personnel'),
                  _buildMenuItem(context, 3, Icons.grade, 'Notes & Bulletins'),
                  _buildMenuItem(context, 4, Icons.payment, 'Paiements'),
                  if ((currentRole ?? '') == 'admin' ||
                      (currentPermissions?.contains('view_users') ?? false))
                    _buildMenuItem(
                      context,
                      6,
                      Icons.admin_panel_settings,
                      'Utilisateurs',
                    ),
                  _buildMenuItem(
                    context,
                    7,
                    Icons.calendar_today,
                    'Emplois du Temps',
                  ),
                  _buildMenuItem(context, 9, Icons.book, 'Matières'),
                  _buildMenuItem(
                    context,
                    14,
                    Icons.local_library_outlined,
                    'Bibliothèque',
                  ),
                  _buildMenuItem(
                    context,
                    15,
                    Icons.rule_folder_outlined,
                    'Discipline',
                  ),
                  _buildMenuItem(
                    context,
                    13,
                    Icons.draw_outlined,
                    'Signatures & Cachets',
                  ),
                  _buildMenuItem(
                    context,
                    10,
                    Icons.storefront,
                    'Finance & Matériel',
                  ),
                  _buildMenuItem(context, 11, Icons.receipt_long, 'Audits'),
                  if ((currentRole ?? '') == 'admin' ||
                      (currentPermissions?.contains('manage_safe_mode') ??
                          false))
                    _buildMenuItem(
                      context,
                      12,
                      Icons.security,
                      'Mode coffre fort',
                    ),
                  _buildMenuItem(
                    context,
                    16, // Index unique pour stats
                    Icons.analytics,
                    'Statistiques',
                  ),
                  // Place Paramètres as the penultimate item (just above logout)
                  _buildMenuItem(context, 5, Icons.settings, 'Paramètres'),
                  const SizedBox(height: 12),
                  if (!isCollapsed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(
                        color: Colors.white.withOpacity(0.5),
                        thickness: 1.6,
                      ),
                    ),
                  const SizedBox(height: 8),
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    padding: EdgeInsets.symmetric(
                      horizontal: isCollapsed ? 8 : 16,
                    ),
                    child: Tooltip(
                      message: 'Terminer la session',
                      waitDuration: Duration(milliseconds: 400),
                      child: ElevatedButton(
                        onPressed: () async {
                          final theme = Theme.of(context);
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: theme
                                  .cardColor, // Use captured theme's card color
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ), // Consistent shape
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Color(0xFFE11D48),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Déconnexion',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE11D48),
                                    ),
                                  ),
                                ],
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.exit_to_app,
                                      size: 40,
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Voulez-vous vraiment vous déconnecter ?\nVotre session en cours sera terminée.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                Row(
                                  // Use Row for buttons
                                  mainAxisAlignment: MainAxisAlignment
                                      .spaceEvenly, // Distribute buttons evenly
                                  children: [
                                    OutlinedButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: theme.dividerColor,
                                        ),
                                      ),
                                      child: const Text(
                                        'Annuler',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'Se déconnecter',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            // ignore: use_build_context_synchronously
                            await _handleLogout(context);
                          }
                        },
                        child: isCollapsed
                            ? const Icon(
                                Icons.logout_rounded,
                                color: Colors.white,
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.logout_rounded),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Se déconnecter',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(
                            0xFFE11D48,
                          ), // red accent for danger
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    int index,
    IconData icon,
    String title,
  ) {
    bool isSelected = selectedIndex == index;
    final bool isAllowed =
        allowedIndices == null || allowedIndices!.contains(index);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 8 : 16,
        vertical: 6,
      ),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Material(
          // Material added for inkwell effect consistency
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (!isAllowed) {
                showRootSnackBar(
                  const SnackBar(content: Text('Accès refusé pour cet écran')),
                );
                return;
              }
              onItemSelected(index);
            },
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              // Adjust padding inside the item
              padding: EdgeInsets.symmetric(
                vertical: 12,
                horizontal: isCollapsed ? 0 : 16,
              ),
              child: isCollapsed
                  ? Center(
                      // Centered icon when collapsed
                      child: Tooltip(
                        message: title,
                        child: Icon(
                          icon,
                          color: isAllowed
                              ? (isSelected ? Colors.white : Colors.white70)
                              : Colors.white24,
                          size: 24,
                        ),
                      ),
                    )
                  : Row(
                      // Row with icon and text when expanded
                      children: [
                        Icon(
                          icon,
                          color: isAllowed
                              ? (isSelected ? Colors.white : Colors.white70)
                              : Colors.white24,
                          size: 28,
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: isAllowed
                                  ? (isSelected ? Colors.white : Colors.white70)
                                  : Colors.white24,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _handleLogout(BuildContext context) async {
  // Ensure any dialogs/menus are closed
  // Close any open dialogs/popups gracefully
  while (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
  await performGlobalLogout(context);
}
