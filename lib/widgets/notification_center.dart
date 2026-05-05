import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/students/student_profile_page.dart';
import 'package:school_manager/services/notification_service.dart';
import 'package:school_manager/utils/academic_year.dart';

class NotificationBell extends StatelessWidget {
  final Function(int)? onNavigate;

  const NotificationBell({Key? key, this.onNavigate}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openNotificationsCenter(context),
        child: Icon(
          Icons.notifications_outlined,
          color: theme.iconTheme.color,
          size: 20,
        ),
      ),
    );
  }

  Future<void> _openNotificationsCenter(BuildContext context) async {
    final year = await getCurrentAcademicYear();
    final alerts = await NotificationService.instance.fetchAlerts(year);
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => NotificationCenterDialog(
        alerts: alerts,
        academicYear: year,
        onNavigate: onNavigate,
      ),
    );
  }
}

class NotificationCenterDialog extends StatelessWidget {
  final NotificationAlerts alerts;
  final String academicYear;
  final Function(int)? onNavigate;

  const NotificationCenterDialog({
    Key? key,
    required this.alerts,
    required this.academicYear,
    this.onNavigate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: 'FCFA',
      decimalDigits: 0,
    );

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
              _buildHeader(context, theme),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuickNav(context),
                      const SizedBox(height: 16),
                      _buildUnpaidSection(context, theme, fmt),
                      const SizedBox(height: 12),
                      _buildDueSection(context, theme),
                      const SizedBox(height: 12),
                      _buildLibrarySection(context, theme),
                      const SizedBox(height: 12),
                      _buildDisciplineSection(context, theme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6366F1).withOpacity(0.16),
            const Color(0xFF8B5CF6).withOpacity(0.10),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.25)),
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
            child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Centre de notifications',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Année $academicYear',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.75),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fermer',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickNav(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _navChip(context, icon: Icons.payment, label: 'Paiements', index: 4),
        _navChip(context, icon: Icons.local_library_outlined, label: 'Bibliothèque', index: 14),
        _navChip(context, icon: Icons.gavel_outlined, label: 'Discipline', index: 15),
      ],
    );
  }

  Widget _navChip(BuildContext context, {required IconData icon, required String label, required int index}) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: () {
        Navigator.of(context).pop();
        onNavigate?.call(index);
      },
    );
  }

  Widget _buildUnpaidSection(BuildContext context, ThemeData theme, NumberFormat fmt) {
    return _sectionCard(
      context,
      icon: Icons.account_balance_wallet_outlined,
      iconColor: const Color(0xFFF59E0B),
      title: 'Impayés',
      subtitle: 'Reste à encaisser: ${fmt.format(alerts.remainingRevenue)}',
      child: alerts.topUnpaidStudents.isEmpty
          ? Text('Aucun impayé.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)))
          : Column(
              children: alerts.topUnpaidStudents.take(10).map((s) => _tile(
                context,
                title: '${s.studentName} • ${s.className}',
                subtitle: 'Reste: ${fmt.format(s.remaining)}',
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showDialog(context: context, builder: (_) => StudentProfilePage(student: s.student));
                  },
                  child: const Text('Profil'),
                ),
              )).toList(),
            ),
    );
  }

  Widget _buildDueSection(BuildContext context, ThemeData theme) {
    return _sectionCard(
      context,
      icon: Icons.event_available_outlined,
      iconColor: const Color(0xFF0EA5E9),
      title: 'Échéances',
      subtitle: alerts.dueSoonItems.isEmpty ? 'Aucune échéance.' : '${alerts.dueSoonItems.length} échéance(s) proche(s)',
      child: Column(
        children: alerts.dueSoonItems.map((it) => _tile(
          context,
          leading: _dot(it.kind == DueKind.library ? Colors.green : Colors.blue),
          title: '${DateFormat('dd/MM/yyyy').format(it.date)} • ${it.title}',
          subtitle: it.subtitle,
        )).toList(),
      ),
    );
  }

  Widget _buildLibrarySection(BuildContext context, ThemeData theme) {
    return _sectionCard(
      context,
      icon: Icons.local_library_outlined,
      iconColor: const Color(0xFF10B981),
      title: 'Bibliothèque',
      subtitle: alerts.overdueLoansCount > 0 ? '${alerts.overdueLoansCount} retard(s)' : 'Aucun retard.',
      child: Column(
        children: alerts.overdueLoansPreview.map((l) => _tile(
          context,
          leading: const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
          title: l.studentName,
          subtitle: '${l.className} • ${l.bookTitle} • échéance ${DateFormat('dd/MM/yyyy').format(l.dueDate)}',
        )).toList(),
      ),
    );
  }

  Widget _buildDisciplineSection(BuildContext context, ThemeData theme) {
    return _sectionCard(
      context,
      icon: Icons.gavel_outlined,
      iconColor: const Color(0xFF8B5CF6),
      title: 'Discipline',
      subtitle: alerts.recentSanctionsCount > 0 ? '${alerts.recentSanctionsCount} sanction(s) récentes' : 'Rien à signaler.',
      child: const SizedBox.shrink(),
    );
  }

  Widget _sectionCard(BuildContext context, {required IconData icon, required Color iconColor, required String title, required String subtitle, required Widget child}) {
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
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
                  ],
                ),
              ),
            ],
          ),
          if (child is! SizedBox) ...[
            const SizedBox(height: 12),
            child,
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, {Widget? leading, required String title, required String subtitle, Widget? trailing}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
