class TeacherAssignment {
  final String id;
  final String teacherId;
  final String courseId;
  final String className;
  final String academicYear;
  final double? weeklyHours;

  TeacherAssignment({
    required this.id,
    required this.teacherId,
    required this.courseId,
    required this.className,
    required this.academicYear,
    this.weeklyHours,
  });

  factory TeacherAssignment.fromMap(Map<String, dynamic> map) {
    return TeacherAssignment(
      id: map['id'] ?? '',
      teacherId: map['teacherId'] ?? '',
      courseId: map['courseId'] ?? '',
      className: map['className'] ?? '',
      academicYear: map['academicYear'] ?? '',
      weeklyHours: map['weeklyHours'] != null
          ? (map['weeklyHours'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'teacherId': teacherId,
      'courseId': courseId,
      'className': className,
      'academicYear': academicYear,
      'weeklyHours': weeklyHours,
    };
  }
}
