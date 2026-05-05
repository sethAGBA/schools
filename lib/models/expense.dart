class Expense {
  final int? id;
  final String label;
  final String? category;
  final int? supplierId;
  final String? supplier;
  final double amount;
  final String date; // ISO8601
  final String? className;
  final String academicYear;
  final String? remoteId;

  Expense({
    this.id,
    required this.label,
    this.category,
    this.supplierId,
    required this.amount,
    required this.date,
    this.className,
    required this.academicYear,
    this.supplier,
    this.remoteId,
  });

  Expense copyWith({
    int? id,
    String? label,
    String? category,
    int? supplierId,
    String? supplier,
    double? amount,
    String? date,
    String? className,
    String? academicYear,
    String? remoteId,
  }) {
    return Expense(
      id: id ?? this.id,
      label: label ?? this.label,
      category: category ?? this.category,
      supplierId: supplierId ?? this.supplierId,
      supplier: supplier ?? this.supplier,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      className: className ?? this.className,
      academicYear: academicYear ?? this.academicYear,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'category': category,
        'supplierId': supplierId,
        'amount': amount,
        'date': date,
        'className': className,
        'academicYear': academicYear,
        'supplier': supplier,
        'remote_id': remoteId,
      };

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
        id: m['id'] as int?,
        label: m['label'] ?? '',
        category: m['category'],
        supplierId: (m['supplierId'] as num?)?.toInt(),
        amount: m['amount'] is int
            ? (m['amount'] as int).toDouble()
            : (m['amount'] as num).toDouble(),
        date: m['date'] ?? '',
        className: m['className'],
        academicYear: m['academicYear'] ?? '',
        supplier: m['supplier'],
        remoteId: m['id']?.toString() ?? m['remote_id']?.toString(),
      );
}
