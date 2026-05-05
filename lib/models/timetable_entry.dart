class TimetableEntry {
  final int? id;
  final String subject;
  final String teacher;
  final String className;
  final String academicYear;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final String room;
  final String? remoteId;

  TimetableEntry({
    this.id,
    required this.subject,
    required this.teacher,
    required this.className,
    required this.academicYear,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.room,
    this.remoteId,
  });

  factory TimetableEntry.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    return TimetableEntry(
      id: rawId is int ? rawId : null,
      subject: map['subject'] ?? '',
      teacher: map['teacher'] ?? '',
      className: map['className'] ?? '',
      academicYear: map['academicYear'] ?? '',
      dayOfWeek: map['dayOfWeek'] ?? '',
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'] ?? '',
      room: map['room'] ?? '',
      remoteId: rawId is String ? rawId : map['remote_id'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'subject': subject,
      'teacher': teacher,
      'className': className,
      'academicYear': academicYear,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'room': room,
      'remote_id': remoteId,
    };
  }
}
