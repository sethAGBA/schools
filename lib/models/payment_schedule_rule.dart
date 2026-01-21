import 'dart:convert';

class PaymentScheduleInstallment {
  final String label;
  final String dueDate; // ISO-8601 date or datetime
  final double fraction; // 0..1

  const PaymentScheduleInstallment({
    required this.label,
    required this.dueDate,
    required this.fraction,
  });

  Map<String, dynamic> toJson() {
    return {'label': label, 'dueDate': dueDate, 'fraction': fraction};
  }

  factory PaymentScheduleInstallment.fromJson(Map<String, dynamic> json) {
    return PaymentScheduleInstallment(
      label: (json['label'] as String?) ?? '',
      dueDate: (json['dueDate'] as String?) ?? '',
      fraction: (json['fraction'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PaymentScheduleRule {
  final String classAcademicYear;
  final String? className; // null = global year default
  final String scheduleJson;
  final String updatedAt;
  final String? updatedBy;

  const PaymentScheduleRule({
    required this.classAcademicYear,
    required this.className,
    required this.scheduleJson,
    required this.updatedAt,
    required this.updatedBy,
  });

  List<PaymentScheduleInstallment> decodeInstallments() {
    final raw = scheduleJson.trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => PaymentScheduleInstallment.fromJson(
                Map<String, dynamic>.from(m),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'classAcademicYear': classAcademicYear,
      'className': className,
      'scheduleJson': scheduleJson,
      'updatedAt': updatedAt,
      'updatedBy': updatedBy,
    };
  }

  factory PaymentScheduleRule.fromMap(Map<String, dynamic> map) {
    return PaymentScheduleRule(
      classAcademicYear: map['classAcademicYear']?.toString() ?? '',
      className: (map['className'] as String?)?.trim().isNotEmpty == true
          ? map['className']?.toString()
          : null,
      scheduleJson: map['scheduleJson']?.toString() ?? '[]',
      updatedAt: map['updatedAt']?.toString() ?? '',
      updatedBy: map['updatedBy']?.toString(),
    );
  }
}

