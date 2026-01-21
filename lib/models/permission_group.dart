import 'dart:convert';

class PermissionGroup {
  final int? id;
  final String name;
  final String permissionsJson;
  final String createdAt;
  final String updatedAt;
  final String? updatedBy;

  PermissionGroup({
    this.id,
    required this.name,
    required this.permissionsJson,
    required this.createdAt,
    required this.updatedAt,
    this.updatedBy,
  });

  List<String> decodePermissions() {
    final raw = permissionsJson.trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'permissionsJson': permissionsJson,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'updatedBy': updatedBy,
    };
  }

  factory PermissionGroup.fromMap(Map<String, dynamic> map) {
    return PermissionGroup(
      id: (map['id'] as num?)?.toInt(),
      name: map['name']?.toString() ?? '',
      permissionsJson: map['permissionsJson']?.toString() ?? '[]',
      createdAt: map['createdAt']?.toString() ?? '',
      updatedAt: map['updatedAt']?.toString() ?? '',
      updatedBy: map['updatedBy']?.toString(),
    );
  }
}

