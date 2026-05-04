import 'dart:convert';

import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/api/api_client.dart';

class RemoteApiException implements Exception {
  const RemoteApiException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'RemoteApiException($statusCode): $message';
}

class RemoteStudentsService {
  RemoteStudentsService._();
  static final RemoteStudentsService instance = RemoteStudentsService._();

  static const int defaultPageSize = 50;

  Future<void> createStudent(Student s) async {
    final response = await ApiClient.instance.post(
      '/api/students',
      body: _toCreateUpdatePayload(s),
    );
    if (response.statusCode != 201) {
      throw _toApiException(response, fallback: 'Création élève échouée.');
    }
  }

  Future<void> updateStudent(Student s) async {
    final response = await ApiClient.instance.put(
      '/api/students/${Uri.encodeComponent(s.id)}',
      body: _toCreateUpdatePayload(s),
    );
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Mise à jour élève échouée.');
    }
  }

  Future<void> deleteStudent(String id) async {
    final response = await ApiClient.instance.delete(
      '/api/students/${Uri.encodeComponent(id)}',
    );
    if (response.statusCode != 204) {
      throw _toApiException(response, fallback: 'Suppression élève échouée.');
    }
  }

  Future<RemoteStudentsPageResult> listStudents({
    String? className,
    String? academicYear,
    String? search,
    int page = 1,
    int pageSize = defaultPageSize,
  }) async {
    final query = <String>[];
    if (className != null && className.trim().isNotEmpty) {
      query.add('className=${Uri.encodeQueryComponent(className.trim())}');
    }
    if (academicYear != null && academicYear.trim().isNotEmpty) {
      query.add('academicYear=${Uri.encodeQueryComponent(academicYear.trim())}');
    }
    if (search != null && search.trim().isNotEmpty) {
      query.add('search=${Uri.encodeQueryComponent(search.trim())}');
    }
    query.add('page=${page < 1 ? 1 : page}');
    query.add('pageSize=${pageSize < 1 ? defaultPageSize : pageSize}');
    final suffix = query.isEmpty ? '' : '?${query.join('&')}';

    final response = await ApiClient.instance.get('/api/students$suffix');
    if (response.statusCode != 200) {
      throw _toApiException(response, fallback: 'Chargement des élèves échoué.');
    }

    final decoded = jsonDecode(response.body);
    final dynamic rawItems = decoded is Map<String, dynamic>
        ? (decoded['items'] ?? const <dynamic>[])
        : decoded;
    final items = (rawItems as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(_studentFromApi)
        .toList();

    if (decoded is Map<String, dynamic>) {
      return RemoteStudentsPageResult(
        items: items,
        total: (decoded['total'] as num?)?.toInt() ?? items.length,
        page: (decoded['page'] as num?)?.toInt() ?? page,
        pageSize: (decoded['pageSize'] as num?)?.toInt() ?? pageSize,
      );
    }

    return RemoteStudentsPageResult(
      items: items,
      total: items.length,
      page: page,
      pageSize: pageSize,
    );
  }

  Student _studentFromApi(Map<String, dynamic> json) {
    String toDateOnly(String? value) {
      if (value == null || value.isEmpty) return '';
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return value;
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '${parsed.year}-$m-$d';
    }

    return Student(
      id: json['id']?.toString() ?? '',
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      dateOfBirth: toDateOnly(json['dateOfBirth']?.toString()),
      address: json['address']?.toString() ?? '',
      gender: json['gender']?.toString() ?? '',
      contactNumber: json['contactNumber']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      emergencyContact: '',
      guardianName: json['guardianName']?.toString() ?? '',
      guardianContact: json['guardianContact']?.toString() ?? '',
      className: json['className']?.toString() ?? '',
      academicYear: json['academicYear']?.toString() ?? '',
      enrollmentDate: toDateOnly(json['createdAtUtc']?.toString()),
      status: (json['isActive'] == true) ? 'Actif' : 'Inactif',
      medicalInfo: null,
      photoPath: null,
      matricule: null,
      placeOfBirth: null,
      documents: const [],
      isDeleted: (json['isActive'] == false),
      deletedAt: null,
      typeInscription: 'Réinscription',
    );
  }

  Map<String, dynamic> _toCreateUpdatePayload(Student s) {
    DateTime parseIsoOrDdMm(String v) {
      final iso = DateTime.tryParse(v);
      if (iso != null) return iso;
      final parts = v.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]) ?? 1;
        final m = int.tryParse(parts[1]) ?? 1;
        final y = int.tryParse(parts[2]) ?? 2000;
        return DateTime(y, m, d);
      }
      return DateTime(2000, 1, 1);
    }

    final dob = parseIsoOrDdMm(s.dateOfBirth);

    return <String, dynamic>{
      'firstName': s.firstName.trim(),
      'lastName': s.lastName.trim(),
      'dateOfBirth': DateTime(dob.year, dob.month, dob.day).toIso8601String(),
      'gender': s.gender.trim(),
      'className': s.className.trim(),
      'academicYear': s.academicYear.trim(),
      'guardianName': s.guardianName.trim(),
      'guardianContact': s.guardianContact.trim(),
      'contactNumber': s.contactNumber.trim(),
      'email': s.email.trim().isEmpty ? null : s.email.trim(),
      'address': s.address.trim().isEmpty ? null : s.address.trim(),
    };
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

class RemoteStudentsPageResult {
  const RemoteStudentsPageResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<Student> items;
  final int total;
  final int page;
  final int pageSize;
}
