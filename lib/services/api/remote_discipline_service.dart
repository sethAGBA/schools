import 'dart:convert';
import 'package:school_manager/services/api/api_client.dart';
import 'package:school_manager/services/api/remote_students_service.dart';

class RemoteDisciplineService {
  RemoteDisciplineService._();
  static final RemoteDisciplineService instance = RemoteDisciplineService._();

  Future<List<Map<String, dynamic>>> listAttendance({
    String? studentId,
    String? academicYear,
    String? className,
  }) async {
    final query = <String>[];
    if (studentId != null) query.add('studentId=${Uri.encodeQueryComponent(studentId)}');
    if (academicYear != null) query.add('academicYear=${Uri.encodeQueryComponent(academicYear)}');
    if (className != null) query.add('className=${Uri.encodeQueryComponent(className)}');

    final suffix = query.isEmpty ? '' : '?${query.join('&')}';

    final response = await ApiClient.instance.get('/api/discipline/attendance$suffix');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Chargement de l\'assiduité échoué.');
    }

    final List<dynamic> decoded = jsonDecode(response.body);
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> bulkUpsertAttendance(List<Map<String, dynamic>> events) async {
    final response = await ApiClient.instance.post(
      '/api/discipline/attendance/bulk',
      body: {'events': events},
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Enregistrement de l\'assiduité échoué.');
    }
  }

  Future<void> deleteAttendance(String id) async {
    final response = await ApiClient.instance.delete('/api/discipline/attendance/$id');
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Suppression de l\'événement d\'assiduité échouée.');
    }
  }

  Future<List<Map<String, dynamic>>> listSanctions({
    String? studentId,
    String? academicYear,
    String? className,
  }) async {
    final query = <String>[];
    if (studentId != null) query.add('studentId=${Uri.encodeQueryComponent(studentId)}');
    if (academicYear != null) query.add('academicYear=${Uri.encodeQueryComponent(academicYear)}');
    if (className != null) query.add('className=${Uri.encodeQueryComponent(className)}');

    final suffix = query.isEmpty ? '' : '?${query.join('&')}';

    final response = await ApiClient.instance.get('/api/discipline/sanctions$suffix');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Chargement des sanctions échoué.');
    }

    final List<dynamic> decoded = jsonDecode(response.body);
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> bulkUpsertSanctions(List<Map<String, dynamic>> events) async {
    final response = await ApiClient.instance.post(
      '/api/discipline/sanctions/bulk',
      body: {'events': events},
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Enregistrement des sanctions échoué.');
    }
  }

  Future<void> deleteSanction(String id) async {
    final response = await ApiClient.instance.delete('/api/discipline/sanctions/$id');
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Suppression de la sanction échouée.');
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
