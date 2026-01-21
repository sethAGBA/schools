import 'dart:convert';

class StudentDocument {
  final String id;
  final String name;
  final String path;
  final String? mimeType;
  final DateTime addedAt;

  const StudentDocument({
    required this.id,
    required this.name,
    required this.path,
    required this.addedAt,
    this.mimeType,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'mimeType': mimeType,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  static StudentDocument fromJson(Map<String, dynamic> json) {
    final addedAtRaw = (json['addedAt'] as String?) ?? '';
    final addedAt = DateTime.tryParse(addedAtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return StudentDocument(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      path: (json['path'] as String?) ?? '',
      mimeType: json['mimeType'] as String?,
      addedAt: addedAt,
    );
  }

  static List<StudentDocument> decodeList(String? raw) {
    if (raw == null) return const [];
    final s = raw.trim();
    if (s.isEmpty) return const [];
    try {
      final decoded = jsonDecode(s);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => StudentDocument.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String encodeList(List<StudentDocument> docs) {
    return jsonEncode(docs.map((d) => d.toJson()).toList());
  }
}

