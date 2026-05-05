import 'dart:convert';
import 'package:school_manager/services/api/api_client.dart';
import 'package:school_manager/services/api/remote_students_service.dart';

class RemoteAcademicsService {
  RemoteAcademicsService._();
  static final RemoteAcademicsService instance = RemoteAcademicsService._();

  // --- Classes ---

  Future<List<Map<String, dynamic>>> listClasses({
    String? academicYear,
    String? level,
  }) async {
    final query = <String>[];
    if (academicYear != null) query.add('academicYear=${Uri.encodeQueryComponent(academicYear)}');
    if (level != null) query.add('level=${Uri.encodeQueryComponent(level)}');
    final suffix = query.isEmpty ? '' : '?${query.join('&')}';

    final response = await ApiClient.instance.get('/api/academics/classes$suffix');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Chargement des classes échoué.');
    }

    final List<dynamic> decoded = jsonDecode(response.body);
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> createClass(Map<String, dynamic> data) async {
    final response = await ApiClient.instance.post(
      '/api/academics/classes',
      body: data,
    );
    if (response.statusCode != 201) {
      throw _toApiException(response, fallback: 'Création de la classe échouée.');
    }
  }

  // --- Subjects ---

  Future<List<Map<String, dynamic>>> listSubjects(String classId) async {
    final response = await ApiClient.instance.get('/api/academics/subjects?classId=${Uri.encodeQueryComponent(classId)}');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Chargement des matières échoué.');
    }

    final List<dynamic> decoded = jsonDecode(response.body);
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> createSubject(Map<String, dynamic> data) async {
    final response = await ApiClient.instance.post(
      '/api/academics/subjects',
      body: data,
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Création de la matière échouée.');
    }
  }

  // --- Grades ---

  Future<List<Map<String, dynamic>>> listGrades({
    String? studentId,
    String? subjectId,
    String? period,
  }) async {
    final query = <String>[];
    if (studentId != null) query.add('studentId=${Uri.encodeQueryComponent(studentId)}');
    if (subjectId != null) query.add('subjectId=${Uri.encodeQueryComponent(subjectId)}');
    if (period != null) query.add('period=${Uri.encodeQueryComponent(period)}');
    final suffix = query.isEmpty ? '' : '?${query.join('&')}';

    final response = await ApiClient.instance.get('/api/academics/grades$suffix');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Chargement des notes échoué.');
    }

    final List<dynamic> decoded = jsonDecode(response.body);
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> bulkUpsertGrades(List<Map<String, dynamic>> grades) async {
    final response = await ApiClient.instance.post(
      '/api/academics/grades/bulk',
      body: {'grades': grades},
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Enregistrement des notes échoué.');
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
