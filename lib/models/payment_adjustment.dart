class PaymentAdjustment {
  final int? id;
  final String studentId;
  final String className;
  final String classAcademicYear;
  final String type; // 'discount' | 'surcharge'
  final double amount;
  final String? reason;
  final String createdAt;
  final String? createdBy;
  final bool isCancelled;
  final String? cancelledAt;
  final String? cancelReason;
  final String? cancelBy;

  PaymentAdjustment({
    this.id,
    required this.studentId,
    required this.className,
    required this.classAcademicYear,
    required this.type,
    required this.amount,
    this.reason,
    required this.createdAt,
    this.createdBy,
    this.isCancelled = false,
    this.cancelledAt,
    this.cancelReason,
    this.cancelBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'className': className,
      'classAcademicYear': classAcademicYear,
      'type': type,
      'amount': amount,
      'reason': reason,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'isCancelled': isCancelled ? 1 : 0,
      'cancelledAt': cancelledAt,
      'cancelReason': cancelReason,
      'cancelBy': cancelBy,
    };
  }

  factory PaymentAdjustment.fromMap(Map<String, dynamic> map) {
    final dynamic yearValue = map['classAcademicYear'] ?? map['academicYear'];
    return PaymentAdjustment(
      id: map['id'] as int?,
      studentId: map['studentId']?.toString() ?? '',
      className: map['className']?.toString() ?? '',
      classAcademicYear: yearValue is String
          ? yearValue
          : yearValue?.toString() ?? '',
      type: map['type']?.toString() ?? 'discount',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      reason: map['reason']?.toString(),
      createdAt: map['createdAt']?.toString() ?? '',
      createdBy: map['createdBy']?.toString(),
      isCancelled: (map['isCancelled'] as int? ?? 0) == 1,
      cancelledAt: map['cancelledAt']?.toString(),
      cancelReason: map['cancelReason']?.toString(),
      cancelBy: map['cancelBy']?.toString(),
    );
  }
}

