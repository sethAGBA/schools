import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/student.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentIdCardTemplate {
  const StudentIdCardTemplate._();

  static Future<List<int>> generate({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required List<Student> students,
    String? className,
    bool compact = true,
    bool includeQrCode = true,
    bool includeBarcode = true,
  }) async {
    final pdf = pw.Document();

    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      final regularData = await rootBundle.load(
        'assets/fonts/nunito/Nunito-Regular.ttf',
      );
      final boldData = await rootBundle.load(
        'assets/fonts/nunito/Nunito-Bold.ttf',
      );
      fontRegular = pw.Font.ttf(regularData);
      fontBold = pw.Font.ttf(boldData);
    } catch (_) {
      fontRegular = await pw.Font.helvetica();
      fontBold = await pw.Font.helveticaBold();
    }

    final primary = PdfColor.fromHex('#111827');
    final accent = PdfColor.fromHex('#2563EB');
    final border = PdfColor.fromHex('#E5E7EB');

    final prefs = await SharedPreferences.getInstance();
    final schoolLevel = (prefs.getString('school_level') ?? '').trim();
    final adminCivility = (prefs.getString('school_admin_civility') ?? 'M.')
        .trim();
    final lowerLevel = schoolLevel.toLowerCase();
    final isLycee =
        lowerLevel.contains('lycée') || lowerLevel.contains('lycee');
    final isFemale = adminCivility.toLowerCase().startsWith('mme');
    final adminTitle = isLycee
        ? (isFemale ? 'Proviseure' : 'Proviseur')
        : (isFemale ? 'Directrice' : 'Directeur');
    final directorName = schoolInfo.director.trim();
    final adminArticle = isFemale ? 'la' : 'le';
    final adminSignedWord = isFemale ? 'soussignée' : 'soussigné';

    const cardPadding = 8.0;
    final cardWidth = compact ? 185.0 : 270.0;
    final cardHeight = compact ? 185.0 : 190.0;
    final cardInnerWidth = cardWidth - (cardPadding * 2);
    final logoSize = compact ? 22.0 : 30.0;
    final flagSize = compact ? 22.0 : 30.0;
    final photoBoxWidth = compact ? 46.0 : 60.0;
    final photoBoxHeight = compact ? 78.0 : 70.0;
    final infoBoxHeight = photoBoxHeight;
    final gutterWidth = compact ? 6.0 : 8.0;
    final infoBoxWidth = cardInnerWidth - photoBoxWidth - gutterWidth;
    final infoLabelWidth = compact ? 40.0 : 34.0;
    final infoValueWidth = infoBoxWidth - infoLabelWidth;
    final titleFontSize = compact ? 8.2 : 10.0;
    final subtitleFontSize = compact ? 6.0 : 7.0;
    final infoFontSize = compact ? 5.6 : 6.8;
    final attestationFontSize = compact ? 5.6 : 6.0;

    String formatDate(String isoDate) {
      if (isoDate.isEmpty) return '';
      try {
        final d = DateTime.parse(isoDate);
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      } catch (_) {
        return isoDate;
      }
    }

    String displayLastName(Student student) {
      final last = student.lastName.trim();
      if (last.isNotEmpty) return last;
      final full = student.name.trim();
      if (full.isNotEmpty) {
        final parts = full.split(RegExp(r'\s+'));
        if (parts.length > 1) return parts.last;
        return parts.first;
      }
      return '[Nom]';
    }

    String displayFirstName(Student student) {
      final first = student.firstName.trim();
      if (first.isNotEmpty) return first;
      final full = student.name.trim();
      if (full.isNotEmpty) {
        final parts = full.split(RegExp(r'\s+'));
        if (parts.length > 1) {
          return parts.sublist(0, parts.length - 1).join(' ');
        }
        return parts.first;
      }
      return '[Prénom]';
    }

    String displayValue(String value, String placeholder) {
      final v = value.trim();
      return v.isNotEmpty ? v : placeholder;
    }

    String truncate(String value, int maxChars) {
      final v = value.trim();
      if (v.length <= maxChars) return v;
      if (maxChars <= 1) return '…';
      return '${v.substring(0, maxChars - 1)}…';
    }

    pw.MemoryImage? logoImage;
    if (schoolInfo.logoPath != null &&
        File(schoolInfo.logoPath!).existsSync()) {
      logoImage = pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync());
    }

    pw.MemoryImage? flagImage;
    if (schoolInfo.flagPath != null &&
        File(schoolInfo.flagPath!).existsSync()) {
      flagImage = pw.MemoryImage(File(schoolInfo.flagPath!).readAsBytesSync());
    }

    List<pw.Widget> buildCardsChunk(List<Student> chunk) {
      return chunk.map((student) {
        try {
          print(
            'PDF Student debug -> id=${student.id} firstName="${student.firstName}" lastName="${student.lastName}" name="${student.name}" class="${student.className}" photoPath="${student.photoPath}" matricule="${student.matricule}" guardianName="${student.guardianName}" guardianContact="${student.guardianContact}"',
          );
        } catch (_) {}

        final hasPhoto =
            student.photoPath != null &&
            student.photoPath!.isNotEmpty &&
            File(student.photoPath!).existsSync();
        pw.MemoryImage? photo;
        if (hasPhoto) {
          photo = pw.MemoryImage(File(student.photoPath!).readAsBytesSync());
        }

        final birthPlace = (student.placeOfBirth ?? '').trim();
        final hasBirthPlace = birthPlace.isNotEmpty;
        final hasBirthDate = student.dateOfBirth.trim().isNotEmpty;
        final normalizedClassName = (className ?? '').trim();
        final studentClassName = normalizedClassName.isNotEmpty
            ? normalizedClassName
            : displayValue(student.className, '[Classe]');

        final guardianPhone = student.guardianContact.trim();
        final guardianPhoneDisplay = guardianPhone.isNotEmpty
            ? guardianPhone
            : (compact ? '________________' : '________________________');
        final guardianLabel = displayValue(
          student.guardianName,
          'Tuteur non renseigné',
        );
        final schoolName = displayValue(
          schoolInfo.name,
          'Établissement scolaire',
        );

        pw.Widget infoLine(String label, String value) => pw.Padding(
          padding: pw.EdgeInsets.only(bottom: compact ? 1 : 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: infoLabelWidth,
                child: pw.Text(
                  '$label:',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: infoFontSize,
                    color: primary,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
              pw.SizedBox(
                width: infoValueWidth,
                child: pw.Text(
                  value,
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: infoFontSize,
                    color: primary,
                  ),
                  softWrap: true,
                  maxLines: compact ? 1 : 2,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ],
          ),
        );

        final sexValue = switch (student.gender.trim().toUpperCase()) {
          'M' => compact ? 'M' : 'Masculin',
          'F' => compact ? 'F' : 'Féminin',
          _ => '',
        };

        final directorNameDisplay = directorName.isNotEmpty
            ? directorName
            : (compact ? '____________________' : '__________________________');

        return pw.Container(
          width: cardWidth,
          height: cardHeight,
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: border, width: 1),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          padding: pw.EdgeInsets.all(cardPadding),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: border, width: 0.5),
                      ),
                      child: pw.ClipRRect(
                        verticalRadius: 6,
                        horizontalRadius: 6,
                        child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                      ),
                    )
                  else
                    pw.Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: border, width: 0.5),
                      ),
                    ),
                  pw.SizedBox(width: compact ? 4 : 6),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if ((schoolInfo.republic ?? '').isNotEmpty)
                          pw.Text(
                            (schoolInfo.republic ?? '').toUpperCase(),
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: compact ? 7.2 : 8.5,
                              color: primary,
                            ),
                          ),
                        pw.Text(
                          truncate(schoolName, compact ? 40 : 60),
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: compact ? 7.6 : 9,
                            color: primary,
                          ),
                          textAlign: pw.TextAlign.center,
                          maxLines: 2,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ],
                    ),
                  ),
                  if (flagImage != null)
                    pw.Container(
                      width: flagSize,
                      height: flagSize,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: border, width: 0.5),
                      ),
                      child: pw.ClipRRect(
                        verticalRadius: 6,
                        horizontalRadius: 6,
                        child: pw.Image(flagImage, fit: pw.BoxFit.cover),
                      ),
                    )
                  else
                    pw.SizedBox(width: flagSize),
                ],
              ),
              pw.SizedBox(height: compact ? 3 : 4),
              pw.Center(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'CARTE SCOLAIRE',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: titleFontSize,
                        color: accent,
                      ),
                    ),
                    pw.Text(
                      'Année scolaire: ${academicYear.isNotEmpty ? academicYear : '[Année]'}',
                      style: pw.TextStyle(
                        font: fontRegular,
                        fontSize: subtitleFontSize,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Divider(color: border, height: compact ? 7 : 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: infoBoxWidth,
                    height: infoBoxHeight,
                    padding: pw.EdgeInsets.all(compact ? 4 : 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(
                        color: PdfColors.grey200,
                        width: 0.5,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        infoLine(
                          'Nom',
                          truncate(displayLastName(student), compact ? 22 : 40),
                        ),
                        infoLine(
                          'Prénom',
                          truncate(
                            displayFirstName(student),
                            compact ? 22 : 40,
                          ),
                        ),
                        infoLine('Sexe', truncate(sexValue, compact ? 1 : 12)),
                        if (compact)
                          infoLine(
                            'Né(e)',
                            truncate(
                              [
                                if (hasBirthDate)
                                  formatDate(student.dateOfBirth),
                                if (hasBirthPlace) 'à $birthPlace',
                              ].join(' '),
                              28,
                            ),
                          )
                        else ...[
                          infoLine(
                            'Né(e) le',
                            hasBirthDate ? formatDate(student.dateOfBirth) : '',
                          ),
                          infoLine('À', truncate(birthPlace, 32)),
                        ],
                        infoLine(
                          'Classe',
                          truncate(studentClassName, compact ? 16 : 30),
                        ),
                        infoLine(
                          compact ? 'Mat.' : 'Matricule',
                          truncate(
                            (student.matricule ?? '').trim(),
                            compact ? 14 : 26,
                          ),
                        ),
                        infoLine(
                          compact ? 'Contact tuteur' : 'Contact du tuteur',
                          truncate(guardianPhoneDisplay, compact ? 16 : 32),
                        ),
                        if (!compact) ...[
                          infoLine('Tuteur', truncate(guardianLabel, 40)),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(width: gutterWidth),
                  pw.Container(
                    width: photoBoxWidth,
                    height: photoBoxHeight,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: border, width: 0.5),
                    ),
                    child: hasPhoto
                        ? pw.ClipRRect(
                            verticalRadius: 6,
                            horizontalRadius: 6,
                            child: pw.Image(photo!, fit: pw.BoxFit.cover),
                          )
                        : pw.Center(
                            child: pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              children: [
                                pw.Text(
                                  'PHOTO',
                                  style: pw.TextStyle(
                                    font: fontRegular,
                                    fontSize: compact ? 6 : 7,
                                    color: PdfColors.grey500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
              pw.SizedBox(height: compact ? 3 : 6),
              if (includeQrCode || includeBarcode)
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (includeBarcode)
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.code128(),
                              data: (student.matricule ?? '').trim().isNotEmpty
                                  ? (student.matricule ?? '').trim()
                                  : student.id,
                              width: cardInnerWidth - (includeQrCode ? 48 : 0),
                              height: compact ? 14 : 18,
                              drawText: false,
                            ),
                            pw.SizedBox(height: 1),
                            pw.Text(
                              (student.matricule ?? '').trim().isNotEmpty
                                  ? 'Matricule: ${(student.matricule ?? '').trim()}'
                                  : 'ID: ${student.id}',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: compact ? 5.2 : 6.0,
                                color: PdfColors.grey700,
                              ),
                              maxLines: 1,
                              overflow: pw.TextOverflow.clip,
                            ),
                            pw.Text(
                              compact
                                  ? 'Tuteur: ${truncate(guardianPhoneDisplay, 18)}'
                                  : 'Contact du tuteur: ${truncate(guardianPhoneDisplay, 40)}',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: compact ? 5.0 : 5.8,
                                color: PdfColors.grey700,
                              ),
                              maxLines: 1,
                              overflow: pw.TextOverflow.clip,
                            ),
                          ],
                        ),
                      ),
                    if (includeQrCode) ...[
                      pw.SizedBox(width: compact ? 6 : 8),
                      pw.Container(
                        width: compact ? 34 : 42,
                        height: compact ? 34 : 42,
                        padding: const pw.EdgeInsets.all(2),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          border: pw.Border.all(color: border, width: 0.5),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data:
                              'studentId=${student.id};name=${student.name};class=$studentClassName;year=$academicYear',
                          drawText: false,
                        ),
                      ),
                    ],
                  ],
                ),
              if (includeQrCode || includeBarcode)
                pw.SizedBox(height: compact ? 3 : 6),
              pw.Container(
                width: cardInnerWidth,
                height: compact ? 18 : null,
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 2,
                  horizontal: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  compact
                      ? "Je $adminSignedWord, $adminCivility $adminArticle $adminTitle $directorNameDisplay, atteste de l'exactitude des informations ci-dessus."
                      : "Je $adminSignedWord, $adminCivility $adminArticle $adminTitle ${directorName.isNotEmpty ? directorName : directorNameDisplay}, atteste de l'exactitude des informations ci-dessus.",
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: attestationFontSize,
                    color: PdfColors.grey700,
                  ),
                  maxLines: compact ? 2 : 3,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ],
          ),
        );
      }).toList();
    }

    final cardsPerRow = compact ? 3 : 2;
    const rowsPerPage = 4;
    final cardsPerPage = cardsPerRow * rowsPerPage;

    for (int i = 0; i < students.length; i += cardsPerPage) {
      final pageStudents = students.sublist(
        i,
        (i + cardsPerPage > students.length)
            ? students.length
            : i + cardsPerPage,
      );

      final rows = <pw.Widget>[];
      for (int r = 0; r < rowsPerPage; r++) {
        final start = r * cardsPerRow;
        final end = start + cardsPerRow;
        final rowStudents = pageStudents.sublist(
          start < pageStudents.length ? start : pageStudents.length,
          end < pageStudents.length ? end : pageStudents.length,
        );

        if (rowStudents.isEmpty) break;
        rows.add(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              ...buildCardsChunk(rowStudents),
              if (rowStudents.length < cardsPerRow)
                ...List.generate(
                  cardsPerRow - rowStudents.length,
                  (_) => pw.SizedBox(width: cardWidth),
                ),
            ],
          ),
        );
        if (r < rowsPerPage - 1) {
          rows.add(pw.SizedBox(height: compact ? 8 : 10));
        }
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(compact ? 18 : 24),
          build: (context) => pw.Column(children: rows),
        ),
      );
    }

    return pdf.save();
  }
}
