import 'dart:convert';
import 'package:school_manager/models/expense.dart';
import 'package:school_manager/services/api/remote_expense_service.dart';
import 'package:school_manager/services/database_service.dart';

class ExpenseSyncResult {
  final bool usedOfflineFallback;
  final Object? remoteError;

  ExpenseSyncResult({this.usedOfflineFallback = false, this.remoteError});
}

class ExpenseSyncService {
  ExpenseSyncService._();
  static final ExpenseSyncService instance = ExpenseSyncService._();

  Future<ExpenseSyncResult> upsertExpense(Expense expense) async {
    try {
      await RemoteExpenseService.instance.bulkUpsertExpenses([expense.toMap()]);
      return ExpenseSyncResult(usedOfflineFallback: false);
    } catch (e) {
      if (expense.id != null) {
        await DatabaseService().enqueuePendingSync(
          entity: 'expense',
          entityId: expense.id.toString(),
          operation: 'upsert',
          payloadJson: jsonEncode(expense.toMap()),
        );
      }
      return ExpenseSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<ExpenseSyncResult> deleteExpense(Expense expense) async {
    try {
      if (expense.remoteId != null) {
        await RemoteExpenseService.instance.deleteExpense(expense.remoteId!);
      }
      return ExpenseSyncResult(usedOfflineFallback: false);
    } catch (e) {
      if (expense.id != null) {
        await DatabaseService().enqueuePendingSync(
          entity: 'expense',
          entityId: expense.id.toString(),
          operation: 'delete',
          payloadJson: jsonEncode({'remoteId': expense.remoteId, 'id': expense.id}),
        );
      }
      return ExpenseSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<({int processed, int succeeded, int failed})> syncPending() async {
    final rows = await DatabaseService().getPendingSync(entity: 'expense', limit: 200);
    if (rows.isEmpty) return (processed: 0, succeeded: 0, failed: 0);

    int processed = 0;
    int succeeded = 0;
    int failed = 0;

    final List<Map<String, dynamic>> batch = [];
    final List<int> rowIds = [];

    for (final r in rows) {
      processed++;
      try {
        final payload = jsonDecode(r['payloadJson']) as Map<String, dynamic>;
        batch.add(payload);
        rowIds.add(r['id'] as int);
      } catch (e) {
        failed++;
        await DatabaseService().markPendingSyncFailure(r['id'] as int, e.toString());
      }
    }

    if (batch.isNotEmpty) {
      try {
        await RemoteExpenseService.instance.bulkUpsertExpenses(batch);
        for (final id in rowIds) {
          await DatabaseService().deletePendingSync(id);
        }
        succeeded += batch.length;
      } catch (e) {
        failed += batch.length;
        for (final id in rowIds) {
          await DatabaseService().markPendingSyncFailure(id, e.toString());
        }
      }
    }

    // Process deletes individually
    final deleteRows = await DatabaseService().getPendingSync(entity: 'expense', operation: 'delete', limit: 50);
    for (final r in deleteRows) {
      processed++;
      try {
        final payload = jsonDecode(r['payloadJson']) as Map<String, dynamic>;
        final remoteId = payload['remoteId'] as String?;
        if (remoteId != null) {
          await RemoteExpenseService.instance.deleteExpense(remoteId);
        }
        await DatabaseService().deletePendingSync(r['id'] as int);
        succeeded++;
      } catch (e) {
        failed++;
        await DatabaseService().markPendingSyncFailure(r['id'] as int, e.toString());
      }
    }

    return (processed: processed, succeeded: succeeded, failed: failed);
  }
}
