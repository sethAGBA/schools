class FinanceBudget {
  final int? id;
  final String academicYear;
  final String category;
  final String? className;
  final double plannedAmount;
  final String updatedAt;
  final String? updatedBy;

  FinanceBudget({
    this.id,
    required this.academicYear,
    required this.category,
    this.className,
    required this.plannedAmount,
    required this.updatedAt,
    this.updatedBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'academicYear': academicYear,
      'category': category,
      'className': className,
      'plannedAmount': plannedAmount,
      'updatedAt': updatedAt,
      'updatedBy': updatedBy,
    };
  }

  factory FinanceBudget.fromMap(Map<String, dynamic> map) {
    return FinanceBudget(
      id: (map['id'] as num?)?.toInt(),
      academicYear: map['academicYear']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      className: (map['className'] as String?)?.trim().isNotEmpty == true
          ? map['className']?.toString()
          : null,
      plannedAmount: (map['plannedAmount'] as num?)?.toDouble() ?? 0.0,
      updatedAt: map['updatedAt']?.toString() ?? '',
      updatedBy: map['updatedBy']?.toString(),
    );
  }
}

