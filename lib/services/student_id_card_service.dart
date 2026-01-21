import 'dart:io';

import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/utils/directory_helper.dart';

class StudentIdCardExportResult {
  StudentIdCardExportResult({
    required this.file,
    required this.directoryResult,
    required this.schoolInfo,
  });

  final File file;
  final DirectorySelectionResult directoryResult;
  final SchoolInfo schoolInfo;
}

class StudentIdCardService {
  StudentIdCardService({DatabaseService? dbService})
    : _dbService = dbService ?? DatabaseService();

  final DatabaseService _dbService;

  Future<StudentIdCardExportResult> exportStudentIdCardsPdf({
    required List<Student> students,
    required String academicYear,
    String? className,
    bool compact = true,
    String? dialogTitle,
    String? outputDirectory,
  }) async {
    final SchoolInfo? schoolInfo = await _dbService.getSchoolInfo();
    if (schoolInfo == null) {
      throw Exception("Informations de l'établissement introuvables");
    }

    final pdfBytes = await PdfService.generateStudentIdCardsPdf(
      schoolInfo: schoolInfo,
      academicYear: academicYear,
      students: students,
      className: className,
      compact: compact,
    );

    final DirectorySelectionResult dirResult =
        outputDirectory != null && outputDirectory.trim().isNotEmpty
        ? DirectorySelectionResult(path: outputDirectory.trim())
        : await DirectoryHelper.pickDirectory(dialogTitle: dialogTitle);

    if (!dirResult.hasPath) {
      throw Exception('Aucun dossier de sauvegarde sélectionné');
    }

    final now = DateTime.now();
    final formattedDate =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    final safeClassName = (className ?? '')
        .trim()
        .replaceAll(RegExp(r'[^\w\- ]+'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final fileName = safeClassName.isNotEmpty
        ? 'cartes_scolaires_${safeClassName}_$formattedDate.pdf'
        : 'cartes_scolaires_$formattedDate.pdf';

    final file = File('${dirResult.path}/$fileName');
    await file.writeAsBytes(pdfBytes);

    return StudentIdCardExportResult(
      file: file,
      directoryResult: dirResult,
      schoolInfo: schoolInfo,
    );
  }
}
