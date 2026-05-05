import 'package:intl/intl.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/license_service.dart';

class UnpaidStudentSummary {
  final String studentId;
  final String studentName;
  final String className;
  final double expected;
  final double paid;
  final double remaining;
  final Student student;

  UnpaidStudentSummary({
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.expected,
    required this.paid,
    required this.remaining,
    required this.student,
  });
}

class DueItem {
  final DateTime date;
  final String title;
  final String subtitle;
  final DueKind kind;

  DueItem({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.kind,
  });
}

enum DueKind { library, license }

class OverdueLoanSummary {
  final int loanId;
  final String studentName;
  final String className;
  final String bookTitle;
  final DateTime dueDate;

  OverdueLoanSummary({
    required this.loanId,
    required this.studentName,
    required this.className,
    required this.bookTitle,
    required this.dueDate,
  });
}

class NotificationAlerts {
  final double remainingRevenue;
  final List<UnpaidStudentSummary> topUnpaidStudents;
  final List<DueItem> dueSoonItems;
  final int overdueLoansCount;
  final List<OverdueLoanSummary> overdueLoansPreview;
  final int recentSanctionsCount;

  NotificationAlerts({
    required this.remainingRevenue,
    required this.topUnpaidStudents,
    required this.dueSoonItems,
    required this.overdueLoansCount,
    required this.overdueLoansPreview,
    required this.recentSanctionsCount,
  });
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final DatabaseService _dbService = DatabaseService();

  Future<NotificationAlerts> fetchAlerts(String currentYear) async {
    final students = await _dbService.getStudents(academicYear: currentYear);
    final allClasses = await _dbService.getClasses();
    final classes = allClasses.where((c) => c.academicYear == currentYear).toList();
    final payments = await _dbService.getAllPayments();

    final studentIdsThisYear = students.map((s) => s.id).toSet();
    final totalRevenue = payments
        .where((p) => studentIdsThisYear.contains(p.studentId) && !p.isCancelled)
        .fold<double>(0.0, (sum, item) => sum + item.amount);

    double expectedTotal = 0.0;
    final Map<String, int> studentCountByClass = {};
    for (final s in students) {
      studentCountByClass[s.className] = (studentCountByClass[s.className] ?? 0) + 1;
    }

    final Map<String, double> unitFeeByClass = {};
    for (final c in classes) {
      final fee = (c.ecolage ?? 0.0) + (c.fraisCotisationParallele ?? 0.0);
      unitFeeByClass[c.name] = fee;
      expectedTotal += fee * (studentCountByClass[c.name] ?? 0);
    }

    final Map<String, double> paidByStudent = {};
    for (final p in payments.where((p) => p.classAcademicYear == currentYear && !p.isCancelled)) {
      paidByStudent[p.studentId] = (paidByStudent[p.studentId] ?? 0.0) + p.amount;
    }

    final unpaidStudents = <UnpaidStudentSummary>[];
    for (final s in students) {
      final expected = unitFeeByClass[s.className] ?? 0.0;
      if (expected <= 0) continue;
      final paid = paidByStudent[s.id] ?? 0.0;
      final remaining = (expected - paid) < 0 ? 0.0 : (expected - paid);
      if (remaining <= 0) continue;
      unpaidStudents.add(UnpaidStudentSummary(
        studentId: s.id,
        studentName: s.name,
        className: s.className,
        expected: expected,
        paid: paid,
        remaining: remaining,
        student: s,
      ));
    }
    unpaidStudents.sort((a, b) => b.remaining.compareTo(a.remaining));

    // Library
    int overdueCount = 0;
    final overduePreview = <OverdueLoanSummary>[];
    final dueSoon = <DueItem>[];
    try {
      final loans = await _dbService.getLibraryLoansView(onlyActive: true);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final soonCutoff = today.add(const Duration(days: 7));
      for (final row in loans) {
        if ((row['studentAcademicYear'] as String?) != currentYear) continue;
        final dueRaw = row['dueDate']?.toString();
        if (dueRaw == null || dueRaw.trim().isEmpty) continue;
        final due = DateTime.tryParse(dueRaw);
        if (due == null) continue;
        final normalizedDue = DateTime(due.year, due.month, due.day);
        if (normalizedDue.isBefore(today)) {
          overdueCount++;
          if (overduePreview.length < 5) {
            overduePreview.add(OverdueLoanSummary(
              loanId: (row['loanId'] as int?) ?? 0,
              studentName: row['studentName'] ?? 'Inconnu',
              className: row['studentClassName'] ?? '',
              bookTitle: row['bookTitle'] ?? '',
              dueDate: normalizedDue,
            ));
          }
        } else if (!normalizedDue.isAfter(soonCutoff)) {
          dueSoon.add(DueItem(
            date: normalizedDue,
            title: 'Retour livre',
            subtitle: '${row['studentName']} • ${row['bookTitle']}',
            kind: DueKind.library,
          ));
        }
      }
    } catch (_) {}

    // License
    try {
      final st = await LicenseService.instance.getStatus();
      if (st.isActive && st.expiry != null) {
        final days = st.daysRemaining;
        if (days <= 14 && days >= 0) {
          dueSoon.add(DueItem(
            date: DateTime(st.expiry!.year, st.expiry!.month, st.expiry!.day),
            title: 'Licence',
            subtitle: 'Expire dans $days jour(s)',
            kind: DueKind.license,
          ));
        }
      }
    } catch (_) {}
    dueSoon.sort((a, b) => a.date.compareTo(b.date));

    // Discipline
    int sanctions7d = 0;
    try {
      final list = await _dbService.getSanctionEvents(academicYear: currentYear);
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      for (final row in list) {
        final dt = DateTime.tryParse(row['date']?.toString() ?? '');
        if (dt != null && dt.isAfter(cutoff)) sanctions7d++;
      }
    } catch (_) {}

    return NotificationAlerts(
      remainingRevenue: (expectedTotal - totalRevenue).clamp(0, 1e15),
      topUnpaidStudents: unpaidStudents,
      dueSoonItems: dueSoon,
      overdueLoansCount: overdueCount,
      overdueLoansPreview: overduePreview,
      recentSanctionsCount: sanctions7d,
    );
  }
}
