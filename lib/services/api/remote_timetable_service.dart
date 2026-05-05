import 'dart:convert';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/services/api/api_client.dart';

class RemoteTimetableService {
  RemoteTimetableService._internal();
  static final RemoteTimetableService instance = RemoteTimetableService._internal();

  Future<List<Map<String, dynamic>>> listEntries({
    String? className,
    String? academicYear,
  }) async {
    final queryParams = <String, String>{};
    if (className != null) queryParams['className'] = className;
    if (academicYear != null) queryParams['academicYear'] = academicYear;

    final uri = Uri.parse('/api/timetable').replace(queryParameters: queryParams);
    final response = await ApiClient.instance.get(uri.toString());

    if (response.statusCode == 200) {
      final List<dynamic> decoded = jsonDecode(response.body);
      return decoded.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to list timetable entries: ${response.statusCode}');
  }

  Future<void> bulkUpsert(List<TimetableEntry> entries) async {
    final body = {
      'entries': entries.map((e) => {
        'id': e.remoteId ?? e.id?.toString(),
        'subject': e.subject,
        'teacher': e.teacher,
        'className': e.className,
        'academicYear': e.academicYear,
        'dayOfWeek': e.dayOfWeek,
        'startTime': e.startTime,
        'endTime': e.endTime,
        'room': e.room,
      }).toList(),
    };

    final response = await ApiClient.instance.post(
      '/api/timetable/bulk',
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to bulk upsert timetable: ${response.statusCode}');
    }
  }

  Future<void> deleteEntry(String remoteId) async {
    final response = await ApiClient.instance.delete('/api/timetable/$remoteId');
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete timetable entry: ${response.statusCode}');
    }
  }
}
