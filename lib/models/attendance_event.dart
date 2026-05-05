class AttendanceEvent {
  final int? id;
  final String studentId;
  final String academicYear;
  final String className;
  final String date; // ISO8601
  final String type; // absence | retard
  final int minutes;
  final bool justified;
  final String? reason;
  final String? recordedBy;
  final String? remoteId;

  AttendanceEvent({
    this.id,
    required this.studentId,
    required this.academicYear,
    required this.className,
    required this.date,
    required this.type,
    required this.minutes,
    required this.justified,
    this.reason,
    this.recordedBy,
    this.remoteId,
  });

  AttendanceEvent copyWith({
    int? id,
    String? studentId,
    String? academicYear,
    String? className,
    String? date,
    String? type,
    int? minutes,
    bool? justified,
    String? reason,
    String? recordedBy,
    String? remoteId,
  }) {
    return AttendanceEvent(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      academicYear: academicYear ?? this.academicYear,
      className: className ?? this.className,
      date: date ?? this.date,
      type: type ?? this.type,
      minutes: minutes ?? this.minutes,
      justified: justified ?? this.justified,
      reason: reason ?? this.reason,
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
        'minutes': minutes,
        'justified': justified ? 1 : 0,
        'reason': reason,
        'recordedBy': recordedBy,
        'remote_id': remoteId,
      };

  factory AttendanceEvent.fromMap(Map<String, dynamic> m) {
    final rawId = m['id'];
    return AttendanceEvent(
      id: rawId is int ? rawId : null,
      studentId: m['studentId'] ?? '',
      academicYear: m['academicYear'] ?? '',
      className: m['className'] ?? '',
      date: m['date'] ?? '',
      type: m['type'] ?? '',
      minutes: (m['minutes'] as num?)?.toInt() ?? 0,
      justified: m['justified'] == 1 || m['justified'] == true,
      reason: m['reason'],
      recordedBy: m['recordedBy'],
      remoteId: (rawId is String) ? rawId : m['remote_id'],
    );
  }
}
