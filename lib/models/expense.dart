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
  });

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
      );
}
