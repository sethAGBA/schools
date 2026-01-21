class EvaluationTemplate {
  final int? id;
  final String className;
  final String academicYear;
  final String subjectId;
  final String subject;
  final String type; // Devoir / Composition / ...
  final String label; // ex: "Devoir 1"
  final double maxValue;
  final double coefficient;
  final int orderIndex;

  const EvaluationTemplate({
    this.id,
    required this.className,
    required this.academicYear,
    required this.subjectId,
    required this.subject,
    required this.type,
    required this.label,
    required this.maxValue,
    required this.coefficient,
    required this.orderIndex,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'className': className,
    'academicYear': academicYear,
    'subjectId': subjectId,
    'subject': subject,
    'type': type,
    'label': label,
    'maxValue': maxValue,
    'coefficient': coefficient,
    'orderIndex': orderIndex,
  };

  static EvaluationTemplate fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic v, double fallback) {
      if (v == null) return fallback;
      if (v is int) return v.toDouble();
      if (v is double) return v;
      return double.tryParse(v.toString()) ?? fallback;
    }

    int toInt(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? fallback;
    }

    return EvaluationTemplate(
      id: map['id'] as int?,
      className: (map['className'] ?? '').toString(),
      academicYear: (map['academicYear'] ?? '').toString(),
      subjectId: (map['subjectId'] ?? '').toString(),
      subject: (map['subject'] ?? '').toString(),
      type: (map['type'] ?? 'Devoir').toString(),
      label: (map['label'] ?? '').toString(),
      maxValue: toDouble(map['maxValue'], 20.0),
      coefficient: toDouble(map['coefficient'], 1.0),
      orderIndex: toInt(map['orderIndex'], 0),
    );
  }
}
