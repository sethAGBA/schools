import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/models/library_book.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/library/library_data.dart';
import 'package:school_manager/screens/library/library_page.dart';

class FakeLibraryData implements LibraryData {
  final List<LibraryBook> _books = [];
  final List<Student> _students = [];
  int _loanSeq = 1;
  int _batchSeq = 1;
  final List<Map<String, dynamic>> _loans = [];

  @override
  Future<List<LibraryBook>> getBooks({String? query}) async {
    final q = (query ?? '').trim().toLowerCase();
    final list = List<LibraryBook>.from(_books);
    list.sort((a, b) => a.title.compareTo(b.title));
    if (q.isEmpty) return list;
    return list
        .where(
          (b) =>
              b.title.toLowerCase().contains(q) ||
              b.author.toLowerCase().contains(q) ||
              (b.isbn ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Future<List<LibraryBook>> getBooksByLastUpdate() async {
    final list = List<LibraryBook>.from(_books);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<void> upsertBook(LibraryBook book) async {
    _books.removeWhere((b) => b.id == book.id);
    _books.add(book);
  }

  @override
  Future<void> deleteBook(String bookId) async {
    final active = _loans.any(
      (l) => l['bookId'] == bookId && l['status'] == 'borrowed',
    );
    if (active) throw Exception('Des emprunts sont encore actifs.');
    _books.removeWhere((b) => b.id == bookId);
  }

  @override
  Future<List<Student>> getStudents({String? academicYear}) async => _students;

  @override
  Future<String> createLoanBatch({
    required String studentId,
    required List<String> bookIds,
    required DateTime dueDate,
    String? recordedBy,
  }) async {
    final batchId = 'BATCH${_batchSeq++}';
    for (final id in bookIds) {
      final bookIndex = _books.indexWhere((b) => b.id == id);
      if (bookIndex < 0) throw Exception('Livre introuvable.');
      final b = _books[bookIndex];
      if (b.availableCopies <= 0) {
        throw Exception('Aucun exemplaire disponible.');
      }
      _books[bookIndex] = b.copyWith(availableCopies: b.availableCopies - 1);

      final student = _students.firstWhere((s) => s.id == studentId);
      _loans.add({
        'loanId': _loanSeq++,
        'batchId': batchId,
        'status': 'borrowed',
        'loanDate': DateTime.now().toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'returnDate': null,
        'recordedBy': recordedBy,
        'bookId': b.id,
        'bookTitle': b.title,
        'bookAuthor': b.author,
        'studentId': student.id,
        'studentName': student.name,
        'studentClassName': student.className,
        'studentAcademicYear': student.academicYear,
      });
    }
    return batchId;
  }

  @override
  Future<String> ensureLoanBatch({required int loanId}) async {
    final idx = _loans.indexWhere((l) => l['loanId'] == loanId);
    if (idx < 0) throw Exception('Emprunt introuvable.');
    final loan = _loans[idx];
    final existing = (loan['batchId'] as String?) ?? '';
    if (existing.trim().isNotEmpty) return existing;
    final batchId = 'loan_$loanId';
    loan['batchId'] = batchId;
    return batchId;
  }

  @override
  Future<void> borrowBook({
    required String bookId,
    required String studentId,
    required DateTime dueDate,
    String? recordedBy,
  }) async {
    final bookIndex = _books.indexWhere((b) => b.id == bookId);
    if (bookIndex < 0) throw Exception('Livre introuvable.');
    final b = _books[bookIndex];
    if (b.availableCopies <= 0) throw Exception('Aucun exemplaire disponible.');
    _books[bookIndex] = b.copyWith(availableCopies: b.availableCopies - 1);

    final student = _students.firstWhere((s) => s.id == studentId);
    _loans.add({
      'loanId': _loanSeq++,
      'batchId': null,
      'status': 'borrowed',
      'loanDate': DateTime.now().toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'returnDate': null,
      'recordedBy': recordedBy,
      'bookId': b.id,
      'bookTitle': b.title,
      'bookAuthor': b.author,
      'studentId': student.id,
      'studentName': student.name,
      'studentClassName': student.className,
      'studentAcademicYear': student.academicYear,
    });
  }

  @override
  Future<void> returnLoan({required int loanId}) async {
    final idx = _loans.indexWhere((l) => l['loanId'] == loanId);
    if (idx < 0) return;
    final loan = _loans[idx];
    if (loan['status'] != 'borrowed') return;
    loan['status'] = 'returned';
    loan['returnDate'] = DateTime.now().toIso8601String();

    final bookId = loan['bookId'] as String;
    final bookIndex = _books.indexWhere((b) => b.id == bookId);
    if (bookIndex >= 0) {
      final b = _books[bookIndex];
      final next = (b.availableCopies + 1) > b.totalCopies
          ? b.totalCopies
          : (b.availableCopies + 1);
      _books[bookIndex] = b.copyWith(availableCopies: next);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getLoansView({
    bool onlyActive = true,
  }) async {
    final rows = List<Map<String, dynamic>>.from(_loans);
    if (!onlyActive) return rows;
    return rows.where((l) => l['status'] == 'borrowed').toList();
  }

  void seedStudent(Student student) => _students.add(student);
}

void main() {
  testWidgets('LibraryPage add book, borrow and return', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final fake = FakeLibraryData();
    fake.seedStudent(
      Student(
        id: 'S1',
        firstName: 'Jean',
        lastName: 'Dupont',
        dateOfBirth: '2015-01-01',
        address: 'Addr',
        gender: 'M',
        contactNumber: '000',
        email: 'j@example.com',
        emergencyContact: '000',
        guardianName: 'G',
        guardianContact: '000',
        className: 'CE1',
        academicYear: '2024-2025',
        enrollmentDate: '2024-09-01',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          data: fake,
          initialAcademicYear: '2024-2025',
          enableTicketGeneration: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gestion de la Bibliothèque'), findsOneWidget);

    await tester.tap(find.byKey(LibraryPage.addBookButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('library_book_title')),
      'Le Petit Prince',
    );
    await tester.enterText(
      find.byKey(const Key('library_book_author')),
      'Saint-Exupéry',
    );
    await tester.enterText(find.byKey(const Key('library_book_copies')), '2');
    await tester.tap(find.byKey(const Key('library_book_save')));
    await tester.pumpAndSettle();

    expect(find.text('Le Petit Prince'), findsOneWidget);

    final bookId = (await fake.getBooks()).single.id;
    await fake.createLoanBatch(
      studentId: 'S1',
      bookIds: [bookId],
      dueDate: DateTime.parse('2025-01-31'),
    );
    await tester.tap(find.byTooltip('Rafraîchir'));
    await tester.pumpAndSettle();

    final tabController = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    tabController.animateTo(1);
    await tester.pumpAndSettle();
    expect(find.text('Emprunts actifs'), findsOneWidget);

    final loansList = find.byKey(LibraryPage.loansListKey);
    expect(loansList, findsOneWidget);
    expect(
      find.descendant(of: loansList, matching: find.text('Le Petit Prince')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: loansList,
        matching: find.textContaining('Jean Dupont'),
      ),
      findsOneWidget,
    );

    final retourButton = find.byKey(const Key('library_return_1'));
    await tester.ensureVisible(retourButton);
    await tester.tap(retourButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_return_confirm_1')));
    await tester.pumpAndSettle();

    // Wait until the fake data reflects the return.
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final active = await fake.getLoansView(onlyActive: true);
      if (active.isEmpty) break;
    }
    expect(await fake.getLoansView(onlyActive: true), isEmpty);
    expect(find.widgetWithText(ElevatedButton, 'Retour'), findsNothing);
  });

  testWidgets('LibraryPage multi-borrow creates multiple loans', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final fake = FakeLibraryData();
    fake.seedStudent(
      Student(
        id: 'S1',
        firstName: 'Jean',
        lastName: 'Dupont',
        dateOfBirth: '2015-01-01',
        address: 'Addr',
        gender: 'M',
        contactNumber: '000',
        email: 'j@example.com',
        emergencyContact: '000',
        guardianName: 'G',
        guardianContact: '000',
        className: 'CE1',
        academicYear: '2024-2025',
        enrollmentDate: '2024-09-01',
      ),
    );
    final now = DateTime.now().toIso8601String();
    await fake.upsertBook(
      LibraryBook(
        id: 'B1',
        title: 'Livre A',
        author: 'Auteur A',
        totalCopies: 1,
        availableCopies: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await fake.upsertBook(
      LibraryBook(
        id: 'B2',
        title: 'Livre B',
        author: 'Auteur B',
        totalCopies: 1,
        availableCopies: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await fake.createLoanBatch(
      studentId: 'S1',
      bookIds: const ['B1', 'B2'],
      dueDate: DateTime.parse('2025-01-31'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          data: fake,
          initialAcademicYear: '2024-2025',
          enableTicketGeneration: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabController = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    tabController.animateTo(1);
    await tester.pumpAndSettle();
    expect(find.text('Emprunts actifs'), findsOneWidget);

    expect((await fake.getLoansView(onlyActive: true)).length, 2);
    final books = await fake.getBooks();
    expect(books.firstWhere((b) => b.id == 'B1').availableCopies, 0);
    expect(books.firstWhere((b) => b.id == 'B2').availableCopies, 0);
  });
}
