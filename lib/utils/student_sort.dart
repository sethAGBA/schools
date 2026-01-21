import 'package:school_manager/models/student.dart';

String normalizeForSort(String input) {
  var value = input.trim().toLowerCase();

  // Basic latin diacritics folding (good enough for French names).
  const replacements = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'æ': 'ae',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'œ': 'oe',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
  };

  for (final entry in replacements.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }

  value = value.replaceAll(RegExp(r'\s+'), ' ');
  return value;
}

int compareStudentsByName(Student a, Student b) {
  final aLast = a.lastName.trim();
  final bLast = b.lastName.trim();
  final aFirst = a.firstName.trim();
  final bFirst = b.firstName.trim();

  final aLastKey = normalizeForSort(aLast.isNotEmpty ? aLast : a.name);
  final bLastKey = normalizeForSort(bLast.isNotEmpty ? bLast : b.name);
  final byLast = aLastKey.compareTo(bLastKey);
  if (byLast != 0) return byLast;

  final byFirst =
      normalizeForSort(aFirst).compareTo(normalizeForSort(bFirst));
  if (byFirst != 0) return byFirst;

  return a.id.compareTo(b.id);
}

