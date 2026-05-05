import 'dart:convert';
import 'package:school_manager/services/api/api_client.dart';
import 'package:school_manager/services/api/remote_students_service.dart';

class RemoteExpenseService {
  RemoteExpenseService._();
  static final RemoteExpenseService instance = RemoteExpenseService._();

  Future<List<Map<String, dynamic>>> listExpenses({
    String? category,
    String? academicYear,
    String? className,
  }) async {
    final query = <String>[];
    if (category != null) query.add('category=${Uri.encodeQueryComponent(category)}');
    if (academicYear != null) query.add('academicYear=${Uri.encodeQueryComponent(academicYear)}');
    if (className != null) query.add('className=${Uri.encodeQueryComponent(className)}');

    final suffix = query.isEmpty ? '' : '?${query.join('&')}';

    final response = await ApiClient.instance.get('/api/finance/expenses$suffix');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Chargement des dépenses échoué.');
    }

    final List<dynamic> decoded = jsonDecode(response.body);
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> bulkUpsertExpenses(List<Map<String, dynamic>> expenses) async {
    final response = await ApiClient.instance.post(
      '/api/finance/expenses/bulk',
      body: {'expenses': expenses},
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Enregistrement des dépenses échoué.');
    }
  }

  Future<void> deleteExpense(String remoteId) async {
    final response = await ApiClient.instance.delete('/api/finance/expenses/$remoteId');
    if (response.statusCode != 204 && response.statusCode != 200 && response.statusCode != 404) {
      throw _toApiException(response, fallback: 'Suppression de la dépense échouée.');
    }
  }

  RemoteApiException _toApiException(
    dynamic response, {
    required String fallback,
  }) {
    String message = fallback;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final maybeError = decoded['error']?.toString().trim();
        if (maybeError != null && maybeError.isNotEmpty) {
          message = maybeError;
        }
      }
    } catch (_) {}
    return RemoteApiException(
      statusCode: response.statusCode as int,
      message: message,
    );
  }
}
