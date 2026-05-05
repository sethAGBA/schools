import 'dart:convert';
import 'package:school_manager/services/api/api_client.dart';
import 'package:school_manager/services/api/remote_students_service.dart';

class RemoteFinanceService {
  RemoteFinanceService._();
  static final RemoteFinanceService instance = RemoteFinanceService._();

  Future<List<Map<String, dynamic>>> listPayments({
    String? studentId,
    String? className,
    String? academicYear,
  }) async {
    final query = <String>[];
    if (studentId != null) query.add('studentId=${Uri.encodeQueryComponent(studentId)}');
    if (className != null) query.add('className=${Uri.encodeQueryComponent(className)}');
    if (academicYear != null) query.add('academicYear=${Uri.encodeQueryComponent(academicYear)}');
    
    final suffix = query.isEmpty ? '' : '?${query.join('&')}';

    final response = await ApiClient.instance.get('/api/finance/payments$suffix');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Chargement des paiements échoué.');
    }

    final List<dynamic> decoded = jsonDecode(response.body);
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> bulkUpsertPayments(List<Map<String, dynamic>> payments) async {
    final response = await ApiClient.instance.post(
      '/api/finance/payments/bulk',
      body: {'payments': payments},
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Enregistrement des paiements échoué.');
    }
  }

  Future<void> deletePayment(String remoteId) async {
    final response = await ApiClient.instance.delete('/api/finance/payments/$remoteId');
    if (response.statusCode != 204 && response.statusCode != 200 && response.statusCode != 404) {
      throw _toApiException(response, fallback: 'Suppression du paiement échouée.');
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
    return RemoteApiException(statusCode: response.statusCode as int, message: message);
  }
}
