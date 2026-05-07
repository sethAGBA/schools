import 'dart:convert';
import 'package:school_manager/services/api/api_client.dart';

class RemoteMockExamsService {
  RemoteMockExamsService._();
  static final RemoteMockExamsService instance = RemoteMockExamsService._();

  Future<List<Map<String, dynamic>>> getSessions() async {
    final response = await ApiClient.instance.get('/api/mock-exams/sessions');
    if (response.statusCode == 200) {
      final List<dynamic> decoded = jsonDecode(response.body);
      return decoded.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load mock exam sessions');
  }

  Future<void> syncSessions(List<Map<String, dynamic>> sessions) async {
    final response = await ApiClient.instance.post(
      '/api/mock-exams/sessions/sync',
      body: sessions,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to sync mock exam sessions');
    }
  }

  Future<void> deleteSession(String name) async {
    final response = await ApiClient.instance.delete('/api/mock-exams/sessions/$name');
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete mock exam session');
    }
  }

  Future<Map<String, dynamic>> bulkUpsertGrades(List<Map<String, dynamic>> grades) async {
    final response = await ApiClient.instance.post(
      '/api/mock-exams/grades/bulk',
      body: grades,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to sync mock exam grades');
  }
}
