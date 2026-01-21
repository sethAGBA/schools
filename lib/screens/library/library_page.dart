import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:school_manager/models/library_book.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/library/library_data.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:uuid/uuid.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    this.data,
    this.initialAcademicYear,
    this.enableTicketGeneration = true,
  });

  final LibraryData? data;
  final String? initialAcademicYear;
  final bool enableTicketGeneration;

  static const Key addBookButtonKey = Key('library_add_book');
  static const Key searchFieldKey = Key('library_search');
  static const Key tabBooksKey = Key('library_tab_books');
  static const Key tabLoansKey = Key('library_tab_loans');
  static const Key tabHistoryKey = Key('library_tab_history');
  static const Key loansListKey = Key('library_loans_list');
  static const Key multiBorrowButtonKey = Key('library_multi_borrow');
  static const Key multiBorrowConfirmButtonKey = Key(
    'library_multi_borrow_confirm',
  );

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final LibraryData _data;

  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  bool _printingTicket = false;
  String _academicYear = '2024-2025';
  String _query = '';
  List<LibraryBook> _books = const [];
  List<Map<String, dynamic>> _activeLoans = const [];
  List<Map<String, dynamic>> _allLoans = const [];
  List<LibraryBook> _booksByLastUpdate = const [];

  Future<String> _persistCoverImage({
    required String sourcePath,
    Uint8List? bytes,
    Stream<List<int>>? readStream,
    String? fileName,
    required String bookId,
  }) async {
    final src = sourcePath.trim();
    if (src.isEmpty && (bytes == null || bytes.isEmpty) && readStream == null) {
      return '';
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'library_covers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ext = (fileName ?? '').trim().isNotEmpty
        ? p.extension(fileName!.trim())
        : p.extension(src);
    final safeExt = ext.isEmpty ? '.png' : ext;
    final dest = p.join(dir.path, '$bookId$safeExt');

    if (bytes != null && bytes.isNotEmpty) {
      await File(dest).writeAsBytes(bytes, flush: true);
      return dest;
    }
    if (readStream != null) {
      final out = File(dest);
      if (!await out.parent.exists()) {
        await out.parent.create(recursive: true);
      }
      final sink = out.openWrite();
      try {
        await sink.addStream(readStream);
      } finally {
        await sink.flush();
        await sink.close();
      }
      return dest;
    }

    if (src.isEmpty) return '';
    if (p.equals(src, dest)) return dest;
    // Avoid trying to read arbitrary external paths if the picker didn't provide bytes/stream.
    if (!src.startsWith(docs.path)) {
      throw Exception(
        'Accès au fichier refusé. Veuillez re-sélectionner l\'image via le sélecteur (et non un chemin externe).',
      );
    }
    final data = await File(src).readAsBytes();
    await File(dest).writeAsBytes(data, flush: true);
    return dest;
  }

  @override
  void initState() {
    super.initState();
    _data = widget.data ?? DatabaseLibraryData();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final year = widget.initialAcademicYear ?? await getCurrentAcademicYear();
    if (!mounted) return;
    setState(() => _academicYear = year);
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final books = await _data.getBooks(query: _query);
      final loans = await _data.getLoansView(onlyActive: true);
      final allLoans = await _data.getLoansView(onlyActive: false);
      final booksByUpdate = await _data.getBooksByLastUpdate();
      if (!mounted) return;
      setState(() {
        _books = books;
        _activeLoans = loans;
        _allLoans = allLoans;
        _booksByLastUpdate = booksByUpdate;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  Future<void> _openBookForm({LibraryBook? existing}) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }

    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final authorCtrl = TextEditingController(text: existing?.author ?? '');
    final isbnCtrl = TextEditingController(text: existing?.isbn ?? '');
    final categoryCtrl = TextEditingController(text: existing?.category ?? '');
    final yearCtrl = TextEditingController(
      text: existing?.publishedYear?.toString() ?? '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final copiesCtrl = TextEditingController(
      text: (existing?.totalCopies ?? 1).toString(),
    );
    var coverImagePath = (existing?.coverImagePath ?? '').trim();
    Uint8List? coverImageBytes;
    Stream<List<int>>? coverImageStream;
    String? coverImageName;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                ),
                child: const Icon(Icons.menu_book, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  existing == null ? 'Ajouter un livre' : 'Modifier le livre',
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).cardColor.withOpacity(0.6),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 64,
                            height: 64,
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.12),
                            child:
                                (coverImageBytes != null &&
                                    coverImageBytes!.isNotEmpty)
                                ? Image.memory(
                                    coverImageBytes!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image_outlined),
                                  )
                                : (coverImagePath.isNotEmpty
                                      ? Image.file(
                                          File(coverImagePath),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                Icons.broken_image_outlined,
                                              ),
                                        )
                                      : const Icon(Icons.image_outlined)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Photo de couverture (optionnel)',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Choisir'),
                                    onPressed: () async {
                                      final res = await FilePicker.platform
                                          .pickFiles(
                                            type: FileType.image,
                                            withData: true,
                                            withReadStream: true,
                                          );
                                      final file = res?.files.single;
                                      if (file == null) return;
                                      final path = file.path;
                                      final bytes = file.bytes;
                                      final stream = file.readStream;
                                      if ((bytes == null || bytes.isEmpty) &&
                                          stream == null &&
                                          (path == null || path.isEmpty)) {
                                        showSnackBar(
                                          context,
                                          'Impossible d\'accéder au fichier sélectionné. Essayez un autre fichier.',
                                          isError: true,
                                        );
                                        return;
                                      }
                                      debugPrint(
                                        '[Library] Book form: selected coverImagePath=$path',
                                      );
                                      setDialogState(() {
                                        coverImagePath = (path ?? '').trim();
                                        coverImageBytes = bytes;
                                        coverImageStream = stream;
                                        coverImageName = file.name;
                                      });
                                    },
                                  ),
                                  if (coverImagePath.isNotEmpty ||
                                      coverImageBytes != null ||
                                      coverImageStream != null)
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Retirer'),
                                      onPressed: () {
                                        debugPrint(
                                          '[Library] Book form: removed coverImagePath',
                                        );
                                        setDialogState(() {
                                          coverImagePath = '';
                                          coverImageBytes = null;
                                          coverImageStream = null;
                                          coverImageName = null;
                                        });
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('library_book_title'),
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titre *',
                      prefixIcon: Icon(Icons.title),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('library_book_author'),
                    controller: authorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Auteur *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: isbnCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ISBN',
                            prefixIcon: Icon(Icons.qr_code_2),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: categoryCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Catégorie',
                            prefixIcon: Icon(Icons.category_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: yearCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Année',
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const Key('library_book_copies'),
                          controller: copiesCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Exemplaires *',
                            prefixIcon: Icon(Icons.copy_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton.icon(
              key: const Key('library_book_save'),
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final author = authorCtrl.text.trim();
                final copies = int.tryParse(copiesCtrl.text.trim()) ?? 0;
                debugPrint(
                  '[Library] Book form: submit title="$title" author="$author" copies=$copies',
                );
                if (title.isEmpty || author.isEmpty || copies <= 0) {
                  showSnackBar(
                    context,
                    'Veuillez renseigner titre, auteur et exemplaires (> 0).',
                    isError: true,
                  );
                  return;
                }

                final publishedYear = int.tryParse(yearCtrl.text.trim());
                final now = DateTime.now().toIso8601String();
                final id = existing?.id ?? const Uuid().v4();
                final base = existing;

                final totalCopies = copies;
                final availableCopies = base == null
                    ? copies
                    : () {
                        final delta = totalCopies - base.totalCopies;
                        final next = base.availableCopies + delta;
                        if (next < 0) return 0;
                        if (next > totalCopies) return totalCopies;
                        return next;
                      }();

                final book = LibraryBook(
                  id: id,
                  title: title,
                  author: author,
                  coverImagePath: null,
                  isbn: isbnCtrl.text.trim().isEmpty
                      ? null
                      : isbnCtrl.text.trim(),
                  category: categoryCtrl.text.trim().isEmpty
                      ? null
                      : categoryCtrl.text.trim(),
                  publishedYear: publishedYear,
                  totalCopies: totalCopies,
                  availableCopies: availableCopies,
                  notes: notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim(),
                  createdAt: base?.createdAt ?? now,
                  updatedAt: now,
                );

                try {
                  debugPrint(
                    '[Library] Book form: saving book id=$id cover=${coverImagePath.isNotEmpty}',
                  );
                  String? finalCover;
                  if (coverImagePath.isNotEmpty ||
                      (coverImageBytes != null &&
                          coverImageBytes!.isNotEmpty) ||
                      coverImageStream != null) {
                    try {
                      finalCover = await _persistCoverImage(
                        sourcePath: coverImagePath,
                        bytes: coverImageBytes,
                        readStream: coverImageStream,
                        fileName: coverImageName,
                        bookId: id,
                      );
                      debugPrint(
                        '[Library] Book form: persisted cover to $finalCover',
                      );
                    } catch (e) {
                      debugPrint('[Library] Book form: cover copy error=$e');
                      showSnackBar(
                        context,
                        'Impossible d\'enregistrer la couverture: $e',
                        isError: true,
                      );
                      return;
                    }
                  }
                  await _data.upsertBook(
                    book.copyWith(
                      coverImagePath: (finalCover ?? '').trim().isEmpty
                          ? null
                          : finalCover,
                    ),
                  );
                  if (!mounted) return;
                  debugPrint('[Library] Book form: saved book id=$id');
                  Navigator.pop(ctx, true);
                } catch (e) {
                  debugPrint('[Library] Book form: save error=$e');
                  showSnackBar(context, 'Erreur: $e', isError: true);
                }
              },
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _load();
    }
  }

  Future<void> _confirmDeleteBook(LibraryBook book) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le livre ?'),
        content: Text(
          'Supprimer “${book.title}” ?\n\n'
          'Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _data.deleteBook(book.id);
      if (!mounted) return;
      showSnackBar(context, 'Livre supprimé.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  Future<void> _borrowBook(LibraryBook book) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    if (book.availableCopies <= 0) {
      showSnackBar(context, 'Aucun exemplaire disponible.', isError: true);
      return;
    }

    final students = await _data.getStudents(academicYear: _academicYear);
    students.sort((a, b) => a.name.compareTo(b.name));
    Student? selected;
    var studentQuery = '';
    final dueCtrl = TextEditingController(
      text: DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.now().add(const Duration(days: 14))),
    );
    String? createdBatchId;
    String? createdStudentName;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = students.where((s) {
            final q = studentQuery.trim().toLowerCase();
            if (q.isEmpty) return true;
            return s.name.toLowerCase().contains(q) ||
                s.id.toLowerCase().contains(q) ||
                s.className.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                  ),
                  child: const Icon(
                    Icons.assignment_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Emprunter un livre')),
              ],
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(book.title),
                      subtitle: Text(book.author),
                      trailing: Chip(
                        label: Text(
                          '${book.availableCopies}/${book.totalCopies}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('library_borrow_student_search'),
                      decoration: const InputDecoration(
                        labelText: 'Rechercher un élève',
                        hintText: 'Nom, ID, classe…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setDialogState(() => studentQuery = v),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.35),
                        ),
                      ),
                      child: filtered.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Aucun élève trouvé.'),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final s = filtered[i];
                                final isSelected = selected?.id == s.id;
                                return ListTile(
                                  key: Key('library_borrow_student_${s.id}'),
                                  title: Text(s.name),
                                  subtitle: Text('${s.className} • ${s.id}'),
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF10B981),
                                        )
                                      : const Icon(Icons.circle_outlined),
                                  onTap: () =>
                                      setDialogState(() => selected = s),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('library_borrow_due'),
                      controller: dueCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Date de retour prévue (YYYY-MM-DD)',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                key: const Key('library_borrow_confirm'),
                icon: const Icon(Icons.arrow_forward),
                onPressed: () async {
                  if (selected == null) {
                    showSnackBar(
                      context,
                      'Veuillez sélectionner un élève.',
                      isError: true,
                    );
                    return;
                  }
                  final due = DateTime.tryParse(dueCtrl.text.trim());
                  if (due == null) {
                    showSnackBar(
                      context,
                      'Date invalide. Exemple: 2025-01-31',
                      isError: true,
                    );
                    return;
                  }
                  try {
                    String? recordedBy;
                    try {
                      final user = await AuthService.instance.getCurrentUser();
                      recordedBy = user?.displayName ?? user?.username;
                    } catch (_) {}
                    debugPrint(
                      '[Library] Borrow form: book=${book.id} student=${selected!.id} due=${due.toIso8601String()}',
                    );
                    final batchId = await _data.createLoanBatch(
                      studentId: selected!.id,
                      bookIds: [book.id],
                      dueDate: due,
                      recordedBy: recordedBy,
                    );
                    if (!mounted) return;
                    createdBatchId = batchId;
                    createdStudentName = selected!.name;
                    debugPrint('[Library] Borrow form: created batch=$batchId');
                    Navigator.pop(ctx, true);
                  } catch (e) {
                    debugPrint('[Library] Borrow form: error=$e');
                    showSnackBar(context, 'Erreur: $e', isError: true);
                  }
                },
                label: const Text('Emprunter'),
              ),
            ],
          );
        },
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dueCtrl.dispose();
    });

    if (ok == true) {
      await _load();
      if (widget.enableTicketGeneration &&
          (createdBatchId ?? '').trim().isNotEmpty) {
        await _saveAndOpenTicket(
          batchId: createdBatchId!,
          studentName: createdStudentName,
        );
      }
    }
  }

  Future<void> _openMultiBorrowDialog() async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    final students = await _data.getStudents(academicYear: _academicYear);
    students.sort((a, b) => a.name.compareTo(b.name));

    final dueCtrl = TextEditingController(
      text: DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.now().add(const Duration(days: 14))),
    );
    var studentQuery = '';
    Student? selectedStudent;
    var bookQuery = '';
    final selectedBookIds = <String>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final studentsFiltered = students.where((s) {
            final q = studentQuery.trim().toLowerCase();
            if (q.isEmpty) return true;
            return s.name.toLowerCase().contains(q) ||
                s.id.toLowerCase().contains(q) ||
                s.className.toLowerCase().contains(q);
          }).toList();
          final booksFiltered = _books.where((b) {
            final q = bookQuery.trim().toLowerCase();
            if (q.isEmpty) return true;
            return b.title.toLowerCase().contains(q) ||
                b.author.toLowerCase().contains(q) ||
                (b.isbn ?? '').toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            title: const Text('Emprunt multiple'),
            content: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('library_multi_borrow_student_search'),
                      decoration: const InputDecoration(
                        labelText: 'Rechercher un élève',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setDialogState(() => studentQuery = v),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.35),
                        ),
                      ),
                      child: studentsFiltered.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Aucun élève trouvé.'),
                              ),
                            )
                          : ListView.builder(
                              itemCount: studentsFiltered.length,
                              itemBuilder: (context, i) {
                                final s = studentsFiltered[i];
                                final isSelected = selectedStudent?.id == s.id;
                                return ListTile(
                                  key: Key(
                                    'library_multi_borrow_student_${s.id}',
                                  ),
                                  title: Text(s.name),
                                  subtitle: Text('${s.className} • ${s.id}'),
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF10B981),
                                        )
                                      : const Icon(Icons.circle_outlined),
                                  onTap: () =>
                                      setDialogState(() => selectedStudent = s),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('library_multi_borrow_book_search'),
                      decoration: const InputDecoration(
                        labelText: 'Rechercher des livres',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setDialogState(() => bookQuery = v),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.35),
                        ),
                      ),
                      child: booksFiltered.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Aucun livre trouvé.'),
                              ),
                            )
                          : ListView.builder(
                              itemCount: booksFiltered.length,
                              itemBuilder: (context, i) {
                                final b = booksFiltered[i];
                                final disabled = b.availableCopies <= 0;
                                final checked = selectedBookIds.contains(b.id);
                                return CheckboxListTile(
                                  key: Key('library_multi_borrow_book_${b.id}'),
                                  value: checked,
                                  onChanged: disabled
                                      ? null
                                      : (v) {
                                          setDialogState(() {
                                            if (v == true) {
                                              selectedBookIds.add(b.id);
                                            } else {
                                              selectedBookIds.remove(b.id);
                                            }
                                          });
                                        },
                                  title: Text(b.title),
                                  subtitle: Text(
                                    '${b.author} • dispo: ${b.availableCopies}/${b.totalCopies}',
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('library_multi_borrow_due'),
                      controller: dueCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Date de retour prévue (YYYY-MM-DD)',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sélection: ${selectedBookIds.length} livre(s)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                key: LibraryPage.multiBorrowConfirmButtonKey,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Valider & Ticket'),
                onPressed: () async {
                  if (selectedStudent == null) {
                    showSnackBar(
                      context,
                      'Veuillez sélectionner un élève.',
                      isError: true,
                    );
                    return;
                  }
                  if (selectedBookIds.isEmpty) {
                    showSnackBar(
                      context,
                      'Veuillez sélectionner au moins un livre.',
                      isError: true,
                    );
                    return;
                  }
                  final due = DateTime.tryParse(dueCtrl.text.trim());
                  if (due == null) {
                    showSnackBar(
                      context,
                      'Date invalide. Exemple: 2025-01-31',
                      isError: true,
                    );
                    return;
                  }
                  try {
                    String? recordedBy;
                    try {
                      final user = await AuthService.instance.getCurrentUser();
                      recordedBy = user?.displayName ?? user?.username;
                    } catch (_) {}
                    final batchId = await _data.createLoanBatch(
                      studentId: selectedStudent!.id,
                      bookIds: selectedBookIds.toList(),
                      dueDate: due,
                      recordedBy: recordedBy,
                    );
                    if (!mounted) return;
                    Navigator.pop(ctx, true);
                    await _load();
                    if (widget.enableTicketGeneration) {
                      await _saveAndOpenTicket(
                        batchId: batchId,
                        studentName: selectedStudent!.name,
                      );
                    }
                  } catch (e) {
                    showSnackBar(context, 'Erreur: $e', isError: true);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dueCtrl.dispose();
    });
    if (ok == true) {
      // already reloaded
    }
  }

  Future<void> _saveAndOpenTicket({
    required String batchId,
    String? studentName,
  }) async {
    final id = batchId.trim();
    if (id.isEmpty) return;
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    if (!widget.enableTicketGeneration) return;
    if (_printingTicket) return;

    setState(() => _printingTicket = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Préparation du ticket...'),
        content: Row(
          children: const [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Veuillez patienter.')),
          ],
        ),
      ),
    );

    try {
      debugPrint(
        '[Library] Ticket: generate batchId=$id student="${(studentName ?? '').trim()}"',
      );
      final pdfBytes = await PdfService.generateLibraryTicketPdf(batchId: id);

      final directoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisir le dossier de sauvegarde',
      );
      if (directoryPath == null) return;

      final safeStudentName = (studentName ?? '').trim().isEmpty
          ? 'Eleve'
          : studentName!.trim().replaceAll(' ', '_');
      final fileName = 'Ticket_Bibliotheque_${safeStudentName}_$id.pdf'
          .replaceAll('/', '_');
      final file = File('$directoryPath/$fileName');
      debugPrint('[Library] Ticket: saving path=${file.path}');
      await file.writeAsBytes(pdfBytes, flush: true);
      if (!mounted) return;
      showSnackBar(context, 'Ticket enregistré dans $directoryPath');
      try {
        debugPrint('[Library] Ticket: opening path=${file.path}');
        await OpenFile.open(file.path);
      } catch (_) {}
    } catch (e) {
      debugPrint('[Library] Ticket: error=$e');
      if (mounted) {
        showSnackBar(
          context,
          'Impossible d\'enregistrer le ticket: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        setState(() => _printingTicket = false);
      }
    }
  }

  Future<void> _reprintTicket(String batchId, {String? studentName}) async {
    await _saveAndOpenTicket(batchId: batchId, studentName: studentName);
  }

  Future<void> _returnLoan(Map<String, dynamic> row) async {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return;
    }
    final loanId = (row['loanId'] as num?)?.toInt();
    if (loanId == null) return;

    final bookTitle = (row['bookTitle'] as String?) ?? 'Livre';
    final studentName = (row['studentName'] as String?) ?? 'Élève';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirmer le retour')),
          ],
        ),
        content: Text(
          'Confirmer le retour de “$bookTitle”\n'
          'pour “$studentName” ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            key: Key('library_return_confirm_$loanId'),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirmer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _data.returnLoan(loanId: loanId);
      if (!mounted) return;
      showSnackBar(context, 'Livre retourné.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: isDarkMode ? Colors.black : Colors.grey[100],
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkMode
                  ? const [
                      Color(0xFF0F0F23),
                      Color(0xFF1A1A2E),
                      Color(0xFF16213E),
                    ]
                  : const [
                      Color(0xFFF8FAFC),
                      Color(0xFFE2E8F0),
                      Color(0xFFF1F5F9),
                    ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildHeader(context, isDesktop: isDesktop),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: theme.cardColor,
                            boxShadow: [
                              BoxShadow(
                                color: theme.shadowColor.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Column(
                              children: [
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final narrow = constraints.maxWidth < 760;
                                    final tabBar = TabBar(
                                      indicator: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF6366F1),
                                            Color(0xFF8B5CF6),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF6366F1,
                                            ).withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      indicatorSize: TabBarIndicatorSize.tab,
                                      dividerColor: Colors.transparent,
                                      labelColor: Colors.white,
                                      unselectedLabelColor:
                                          theme.textTheme.bodyMedium?.color,
                                      labelStyle: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      unselectedLabelStyle: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                      tabs: const [
                                        Tab(
                                          key: LibraryPage.tabBooksKey,
                                          text: 'Livres',
                                          icon: Icon(Icons.menu_book),
                                        ),
                                        Tab(
                                          key: LibraryPage.tabLoansKey,
                                          text: 'Emprunts',
                                          icon: Icon(Icons.assignment_outlined),
                                        ),
                                        Tab(
                                          key: LibraryPage.tabHistoryKey,
                                          text: 'Historique',
                                          icon: Icon(Icons.history),
                                        ),
                                      ],
                                    );

                                    final addButton = ElevatedButton.icon(
                                      key: LibraryPage.addBookButtonKey,
                                      onPressed: () => _openBookForm(),
                                      icon: const Icon(
                                        Icons.add,
                                        color: Colors.white,
                                      ),
                                      label: Text(narrow ? '' : 'Ajouter'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF6366F1,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: narrow ? 12 : 16,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    );

                                    return Container(
                                      margin: const EdgeInsets.only(
                                        top: 16,
                                        left: 16,
                                        right: 16,
                                        bottom: 0,
                                      ),
                                      child: narrow
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    color: theme.cardColor,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: theme.shadowColor
                                                            .withOpacity(0.1),
                                                        blurRadius: 10,
                                                        offset: const Offset(
                                                          0,
                                                          2,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: tabBar,
                                                ),
                                                const SizedBox(height: 8),
                                                Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: addButton,
                                                ),
                                              ],
                                            )
                                          : Row(
                                              children: [
                                                Expanded(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      color: theme.cardColor,
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: theme
                                                              .shadowColor
                                                              .withOpacity(0.1),
                                                          blurRadius: 10,
                                                          offset: const Offset(
                                                            0,
                                                            2,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    child: tabBar,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                addButton,
                                              ],
                                            ),
                                    );
                                  },
                                ),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      _buildBooksTab(context),
                                      _buildLoansTab(context),
                                      _buildHistoryTab(context),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isDesktop}) {
    final theme = Theme.of(context);
    final bookCount = _books.length;
    final loanCount = _activeLoans.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        Widget iconBox(IconData icon) => Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: theme.iconTheme.color, size: 20),
        );

        final headline = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.local_library_outlined,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gestion de la Bibliothèque',
                          style: TextStyle(
                            fontSize: isDesktop ? 32 : 24,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ajoutez des livres, gérez les emprunts et suivez les retours.',
                          style: TextStyle(
                            fontSize: isDesktop ? 16 : 14,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.7),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            iconBox(Icons.notifications_outlined),
          ],
        );

        final kpis = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!_loading) Chip(label: Text('$bookCount livre(s)')),
            if (!_loading) Chip(label: Text('$loanCount emprunt(s)')),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.dividerColor.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.local_library_outlined,
                        color: Colors.white,
                        size: isDesktop ? 32 : 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gestion de la Bibliothèque',
                            style: TextStyle(
                              fontSize: isDesktop ? 32 : 24,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ajoutez des livres, gérez les emprunts et suivez les retours.',
                            style: TextStyle(
                              fontSize: isDesktop ? 16 : 14,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.7),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    iconBox(Icons.notifications_outlined),
                  ],
                ),
              ] else ...[
                headline,
              ],
              const SizedBox(height: 12),
              kpis,
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: LibraryPage.searchFieldKey,
                      controller: _searchController,
                      onChanged: (value) async {
                        _query = value;
                        await _load();
                      },
                      decoration: InputDecoration(
                        hintText: 'Rechercher (titre, auteur, ISBN)',
                        hintStyle: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.6,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: theme.iconTheme.color,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 16,
                        ),
                      ),
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      tooltip: 'Rafraîchir',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBooksTab(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _books.isEmpty
          ? Center(
              child: Text(
                'Aucun livre.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ),
            )
          : ListView.separated(
              itemCount: _books.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final b = _books[i];
                final subtitleParts = <String>[
                  b.author,
                  if ((b.category ?? '').trim().isNotEmpty) b.category!.trim(),
                  if ((b.isbn ?? '').trim().isNotEmpty) 'ISBN: ${b.isbn}',
                ];
                final cover = (b.coverImagePath ?? '').trim();
                return Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.35),
                    ),
                  ),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 44,
                        height: 44,
                        color: theme.dividerColor.withOpacity(0.12),
                        child: cover.isEmpty
                            ? const Icon(Icons.image_outlined, size: 18)
                            : Image.file(
                                File(cover),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  size: 18,
                                ),
                              ),
                      ),
                    ),
                    title: Text(
                      b.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(subtitleParts.join(' • ')),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text('${b.availableCopies}/${b.totalCopies}'),
                        ),
                        IconButton(
                          tooltip: 'Emprunter',
                          onPressed: () => _borrowBook(b),
                          icon: const Icon(Icons.assignment_outlined),
                        ),
                        IconButton(
                          tooltip: 'Modifier',
                          onPressed: () => _openBookForm(existing: b),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          onPressed: () => _confirmDeleteBook(b),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildLoansTab(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Emprunts actifs',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton.icon(
                key: LibraryPage.multiBorrowButtonKey,
                onPressed: _openMultiBorrowDialog,
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Emprunt multiple'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _activeLoans.isEmpty
                ? Center(
                    child: Text(
                      'Aucun emprunt actif.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.7,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    key: LibraryPage.loansListKey,
                    itemCount: _activeLoans.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = _activeLoans[i];
                      final batchId = (r['batchId'] as String?) ?? '';
                      final loanId = (r['loanId'] as num?)?.toInt();
                      final due = DateTime.tryParse(
                        (r['dueDate'] as String?) ?? '',
                      );
                      final overdue = due != null && due.isBefore(now);
                      final bookTitle = (r['bookTitle'] as String?) ?? 'Livre';
                      final studentName =
                          (r['studentName'] as String?) ?? 'Élève';
                      final cls = (r['studentClassName'] as String?) ?? '';
                      return Container(
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: overdue
                                ? Colors.red.withOpacity(0.5)
                                : theme.dividerColor.withOpacity(0.35),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            overdue
                                ? Icons.warning_amber_rounded
                                : Icons.assignment_outlined,
                            color: overdue ? Colors.red : null,
                          ),
                          title: Text(
                            bookTitle,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '$studentName${cls.trim().isEmpty ? '' : ' — $cls'}'
                            '${due == null ? '' : ' • Retour: ${DateFormat('dd/MM/yyyy').format(due)}'}',
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              if (widget.enableTicketGeneration)
                                IconButton(
                                  key: Key(
                                    'library_reprint_ticket_${r['loanId']}',
                                  ),
                                  tooltip: 'Réimprimer le ticket',
                                  onPressed: loanId == null
                                      ? null
                                      : () async {
                                          final ensured =
                                              batchId.trim().isNotEmpty
                                              ? batchId
                                              : await _data.ensureLoanBatch(
                                                  loanId: loanId,
                                                );
                                          if (!mounted) return;
                                          await _reprintTicket(
                                            ensured,
                                            studentName: studentName,
                                          );
                                        },
                                  icon: const Icon(Icons.receipt_long),
                                ),
                              ElevatedButton.icon(
                                key: Key('library_return_${r['loanId']}'),
                                onPressed: () => _returnLoan(r),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Retour'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(BuildContext context) {
    final theme = Theme.of(context);
    final returned =
        _allLoans.where((r) => (r['status'] as String?) != 'borrowed').toList()
          ..sort((a, b) {
            final ar =
                DateTime.tryParse((a['returnDate'] as String?) ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final br =
                DateTime.tryParse((b['returnDate'] as String?) ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return br.compareTo(ar);
          });

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text(
            'Historique des emprunts',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          returned.isEmpty
              ? Text(
                  'Aucun emprunt terminé.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: returned.length.clamp(0, 50),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = returned[i];
                    final batchId = (r['batchId'] as String?) ?? '';
                    final loanId = (r['loanId'] as num?)?.toInt();
                    final bookTitle = (r['bookTitle'] as String?) ?? 'Livre';
                    final studentName =
                        (r['studentName'] as String?) ?? 'Élève';
                    final cls = (r['studentClassName'] as String?) ?? '';
                    final loan = DateTime.tryParse(
                      (r['loanDate'] as String?) ?? '',
                    );
                    final due = DateTime.tryParse(
                      (r['dueDate'] as String?) ?? '',
                    );
                    final ret = DateTime.tryParse(
                      (r['returnDate'] as String?) ?? '',
                    );
                    final dates = <String>[
                      if (loan != null)
                        'Emprunt: ${DateFormat('dd/MM/yyyy').format(loan)}',
                      if (due != null)
                        'Prévu: ${DateFormat('dd/MM/yyyy').format(due)}',
                      if (ret != null)
                        'Retour: ${DateFormat('dd/MM/yyyy').format(ret)}',
                    ];
                    return Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.35),
                        ),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(
                          bookTitle,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '$studentName${cls.trim().isEmpty ? '' : ' — $cls'}\n${dates.join(' • ')}',
                        ),
                        trailing: widget.enableTicketGeneration
                            ? IconButton(
                                tooltip: 'Ticket',
                                onPressed: loanId == null
                                    ? null
                                    : () async {
                                        final ensured =
                                            batchId.trim().isNotEmpty
                                            ? batchId
                                            : await _data.ensureLoanBatch(
                                                loanId: loanId,
                                              );
                                        if (!mounted) return;
                                        await _reprintTicket(
                                          ensured,
                                          studentName: studentName,
                                        );
                                      },
                                icon: const Icon(Icons.receipt_long),
                              )
                            : null,
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
          const SizedBox(height: 20),
          Text(
            'Historique des livres',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _booksByLastUpdate.isEmpty
              ? Text(
                  'Aucun livre.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _booksByLastUpdate.length.clamp(0, 50),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final b = _booksByLastUpdate[i];
                    final updated = DateTime.tryParse(b.updatedAt);
                    final created = DateTime.tryParse(b.createdAt);
                    final subtitle = <String>[
                      b.author,
                      if (created != null)
                        'Créé: ${DateFormat('dd/MM/yyyy').format(created)}',
                      if (updated != null)
                        'MAJ: ${DateFormat('dd/MM/yyyy').format(updated)}',
                    ].join(' • ');
                    final cover = (b.coverImagePath ?? '').trim();
                    return Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.35),
                        ),
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 40,
                            height: 40,
                            color: theme.dividerColor.withOpacity(0.12),
                            child: cover.isEmpty
                                ? const Icon(Icons.image_outlined, size: 18)
                                : Image.file(
                                    File(cover),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image_outlined,
                                      size: 18,
                                    ),
                                  ),
                          ),
                        ),
                        title: Text(
                          b.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(subtitle),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
