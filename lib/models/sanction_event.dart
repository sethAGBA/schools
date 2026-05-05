class SanctionEvent {
  final int? id;
  final String studentId;
  final String academicYear;
  final String className;
  final String date; // ISO8601
  final String type; // avertissement | blame | exclusion | autre
  final String description;
  final String? recordedBy;
  final String? remoteId;

  SanctionEvent({
    this.id,
    required this.studentId,
    required this.academicYear,
    required this.className,
    required this.date,
    required this.type,
    required this.description,
    this.recordedBy,
    this.remoteId,
  });

  SanctionEvent copyWith({
    int? id,
    String? studentId,
    String? academicYear,
    String? className,
    String? date,
    String? type,
    String? description,
    String? recordedBy,
    String? remoteId,
  }) {
    return SanctionEvent(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      academicYear: academicYear ?? this.academicYear,
      className: className ?? this.className,
      date: date ?? this.date,
      type: type ?? this.type,
      description: description ?? this.description,
      recordedBy: recordedBy ?? this.recordedBy,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'studentId': studentId,
        'academicYear': academicYear,
        'className': className,
        'date': date,
        'type': type,
        'description': description,
        'recordedBy': recordedBy,
        'remote_id': remoteId,
      };

  factory SanctionEvent.fromMap(Map<String, dynamic> m) {
    final rawId = m['id'];
    return SanctionEvent(
      id: rawId is int ? rawId : null,
      studentId: m['studentId'] ?? '',
      academicYear: m['academicYear'] ?? '',
      className: m['className'] ?? '',
      date: m['date'] ?? '',
      type: m['type'] ?? '',
      description: m['description'] ?? '',
      recordedBy: m['recordedBy'],
      remoteId: (rawId is String) ? rawId : m['remote_id'],
    );
  }
}
