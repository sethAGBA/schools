class PaymentAttachment {
  final int? id;
  final int paymentId;
  final String studentId;
  final String classAcademicYear;
  final String fileName;
  final String filePath;
  final int? sizeBytes;
  final String createdAt;
  final String? createdBy;

  PaymentAttachment({
    this.id,
    required this.paymentId,
    required this.studentId,
    required this.classAcademicYear,
    required this.fileName,
    required this.filePath,
    this.sizeBytes,
    required this.createdAt,
    this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'paymentId': paymentId,
      'studentId': studentId,
      'classAcademicYear': classAcademicYear,
      'fileName': fileName,
      'filePath': filePath,
      'sizeBytes': sizeBytes,
      'createdAt': createdAt,
      'createdBy': createdBy,
    };
  }

  factory PaymentAttachment.fromMap(Map<String, dynamic> map) {
    return PaymentAttachment(
      id: map['id'] as int?,
      paymentId: (map['paymentId'] as num?)?.toInt() ?? 0,
      studentId: map['studentId']?.toString() ?? '',
      classAcademicYear: map['classAcademicYear']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      filePath: map['filePath']?.toString() ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      createdAt: map['createdAt']?.toString() ?? '',
      createdBy: map['createdBy']?.toString(),
    );
  }
}

