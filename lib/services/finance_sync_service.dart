import 'dart:convert';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/services/api/remote_finance_service.dart';
import 'package:school_manager/services/database_service.dart';

class FinanceSyncResult {
  final bool usedOfflineFallback;
  final Object? remoteError;

  FinanceSyncResult({this.usedOfflineFallback = false, this.remoteError});
}

class FinanceSyncService {
  FinanceSyncService._();
  static final FinanceSyncService instance = FinanceSyncService._();

  Future<FinanceSyncResult> upsertPayment(Payment payment) async {
    try {
      await RemoteFinanceService.instance.bulkUpsertPayments([payment.toMap()]);
      return FinanceSyncResult(usedOfflineFallback: false);
    } catch (e) {
      if (payment.id != null) {
        await DatabaseService().enqueuePendingSync(
          entity: 'payment',
          entityId: payment.id.toString(),
          operation: 'upsert',
          payloadJson: jsonEncode(payment.toMap()),
        );
      }
      return FinanceSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<FinanceSyncResult> deletePayment(Payment payment) async {
    try {
      if (payment.remoteId != null) {
        await RemoteFinanceService.instance.deletePayment(payment.remoteId!);
      }
      return FinanceSyncResult(usedOfflineFallback: false);
    } catch (e) {
      if (payment.id != null) {
        await DatabaseService().enqueuePendingSync(
          entity: 'payment',
          entityId: payment.id.toString(),
          operation: 'delete',
          payloadJson: jsonEncode({'remoteId': payment.remoteId, 'id': payment.id}),
        );
      }
      return FinanceSyncResult(usedOfflineFallback: true, remoteError: e);
    }
  }

  Future<({int processed, int succeeded, int failed})> syncPending() async {
    final rows = await DatabaseService().getPendingSync(entity: 'payment', limit: 200);
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
        await RemoteFinanceService.instance.bulkUpsertPayments(batch);
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

    // Process deletes individually for now
    final deleteRows = await DatabaseService().getPendingSync(entity: 'payment', operation: 'delete', limit: 50);
    for (final r in deleteRows) {
      processed++;
      try {
        final payload = jsonDecode(r['payloadJson']) as Map<String, dynamic>;
        final remoteId = payload['remoteId'] as String?;
        if (remoteId != null) {
          await RemoteFinanceService.instance.deletePayment(remoteId);
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
