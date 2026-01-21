class ExpenseAttachment {
  final int? id;
  final int expenseId;
  final String academicYear;
  final String fileName;
  final String filePath;
  final int? sizeBytes;
  final String createdAt;
  final String? createdBy;

  ExpenseAttachment({
    this.id,
    required this.expenseId,
    required this.academicYear,
    required this.fileName,
    required this.filePath,
    this.sizeBytes,
    required this.createdAt,
    this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'expenseId': expenseId,
      'academicYear': academicYear,
      'fileName': fileName,
      'filePath': filePath,
      'sizeBytes': sizeBytes,
      'createdAt': createdAt,
      'createdBy': createdBy,
    };
  }

  factory ExpenseAttachment.fromMap(Map<String, dynamic> map) {
    return ExpenseAttachment(
      id: (map['id'] as num?)?.toInt(),
      expenseId: (map['expenseId'] as num?)?.toInt() ?? 0,
      academicYear: map['academicYear']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      filePath: map['filePath']?.toString() ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      createdAt: map['createdAt']?.toString() ?? '',
      createdBy: map['createdBy']?.toString(),
    );
  }
}

