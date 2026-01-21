class LibraryBook {
  final String id;
  final String title;
  final String author;
  final String? coverImagePath;
  final String? isbn;
  final String? category;
  final int? publishedYear;
  final int totalCopies;
  final int availableCopies;
  final String createdAt;
  final String updatedAt;
  final String? notes;

  const LibraryBook({
    required this.id,
    required this.title,
    required this.author,
    this.coverImagePath,
    this.isbn,
    this.category,
    this.publishedYear,
    required this.totalCopies,
    required this.availableCopies,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  LibraryBook copyWith({
    String? id,
    String? title,
    String? author,
    String? coverImagePath,
    String? isbn,
    String? category,
    int? publishedYear,
    int? totalCopies,
    int? availableCopies,
    String? createdAt,
    String? updatedAt,
    String? notes,
  }) {
    return LibraryBook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      isbn: isbn ?? this.isbn,
      category: category ?? this.category,
      publishedYear: publishedYear ?? this.publishedYear,
      totalCopies: totalCopies ?? this.totalCopies,
      availableCopies: availableCopies ?? this.availableCopies,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'coverImagePath': coverImagePath,
      'isbn': isbn,
      'category': category,
      'publishedYear': publishedYear,
      'totalCopies': totalCopies,
      'availableCopies': availableCopies,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'notes': notes,
    };
  }

  factory LibraryBook.fromMap(Map<String, dynamic> map) {
    return LibraryBook(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? '',
      author: (map['author'] as String?) ?? '',
      coverImagePath: map['coverImagePath'] as String?,
      isbn: map['isbn'] as String?,
      category: map['category'] as String?,
      publishedYear: (map['publishedYear'] as num?)?.toInt(),
      totalCopies: (map['totalCopies'] as num?)?.toInt() ?? 0,
      availableCopies: (map['availableCopies'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] as String?) ?? '',
      updatedAt: (map['updatedAt'] as String?) ?? '',
      notes: map['notes'] as String?,
    );
  }
}
