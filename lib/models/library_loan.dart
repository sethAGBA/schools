class LibraryLoan {
  final int? id;
  final String? batchId;
  final String bookId;
  final String studentId;
  final String loanDate;
  final String dueDate;
  final String? returnDate;
  final String status; // borrowed, returned, lost
  final String? recordedBy;

  const LibraryLoan({
    this.id,
    this.batchId,
    required this.bookId,
    required this.studentId,
    required this.loanDate,
    required this.dueDate,
    this.returnDate,
    required this.status,
    this.recordedBy,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'batchId': batchId,
      'bookId': bookId,
      'studentId': studentId,
      'loanDate': loanDate,
      'dueDate': dueDate,
      'returnDate': returnDate,
      'status': status,
      'recordedBy': recordedBy,
    };
  }

  factory LibraryLoan.fromMap(Map<String, dynamic> map) {
    return LibraryLoan(
      id: (map['id'] as num?)?.toInt(),
      batchId: map['batchId'] as String?,
      bookId: (map['bookId'] as String?) ?? '',
      studentId: (map['studentId'] as String?) ?? '',
      loanDate: (map['loanDate'] as String?) ?? '',
      dueDate: (map['dueDate'] as String?) ?? '',
      returnDate: map['returnDate'] as String?,
      status: (map['status'] as String?) ?? 'borrowed',
      recordedBy: map['recordedBy'] as String?,
    );
  }
}
