import 'package:school_manager/models/library_book.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';

abstract class LibraryData {
  Future<List<LibraryBook>> getBooks({String? query});
  Future<List<LibraryBook>> getBooksByLastUpdate();
  Future<void> upsertBook(LibraryBook book);
  Future<void> deleteBook(String bookId);

  Future<List<Student>> getStudents({String? academicYear});

  Future<String> createLoanBatch({
    required String studentId,
    required List<String> bookIds,
    required DateTime dueDate,
    String? recordedBy,
  });

  Future<String> ensureLoanBatch({required int loanId});

  Future<void> borrowBook({
    required String bookId,
    required String studentId,
    required DateTime dueDate,
    String? recordedBy,
  });
  Future<void> returnLoan({required int loanId});

  Future<List<Map<String, dynamic>>> getLoansView({bool onlyActive = true});
}

class DatabaseLibraryData implements LibraryData {
  final DatabaseService _db;
  DatabaseLibraryData([DatabaseService? db]) : _db = db ?? DatabaseService();

  @override
  Future<List<LibraryBook>> getBooks({String? query}) =>
      _db.getLibraryBooks(query: query);

  @override
  Future<List<LibraryBook>> getBooksByLastUpdate() =>
      _db.getLibraryBooksByLastUpdate();

  @override
  Future<void> upsertBook(LibraryBook book) => _db.upsertLibraryBook(book);

  @override
  Future<void> deleteBook(String bookId) => _db.deleteLibraryBook(bookId);

  @override
  Future<List<Student>> getStudents({String? academicYear}) =>
      _db.getStudents(academicYear: academicYear);

  @override
  Future<String> createLoanBatch({
    required String studentId,
    required List<String> bookIds,
    required DateTime dueDate,
    String? recordedBy,
  }) => _db.createLibraryLoanBatch(
    studentId: studentId,
    bookIds: bookIds,
    dueDate: dueDate,
    recordedBy: recordedBy,
  );

  @override
  Future<String> ensureLoanBatch({required int loanId}) =>
      _db.ensureLibraryLoanBatchForLoan(loanId: loanId);

  @override
  Future<void> borrowBook({
    required String bookId,
    required String studentId,
    required DateTime dueDate,
    String? recordedBy,
  }) => _db.borrowLibraryBook(
    bookId: bookId,
    studentId: studentId,
    dueDate: dueDate,
    recordedBy: recordedBy,
  );

  @override
  Future<void> returnLoan({required int loanId}) =>
      _db.returnLibraryLoan(loanId: loanId);

  @override
  Future<List<Map<String, dynamic>>> getLoansView({bool onlyActive = true}) =>
      _db.getLibraryLoansView(onlyActive: onlyActive);
}
