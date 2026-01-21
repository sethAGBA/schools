import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/category.dart';
import 'package:school_manager/models/signature.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/services/signature_pdf_service.dart';
import 'package:school_manager/services/student_id_card_template.dart';
import 'package:school_manager/services/report_card_pdf_service.dart';
import 'package:school_manager/services/report_card_compact_pdf_service.dart';
import 'package:school_manager/services/report_card_ultra_compact_pdf_service.dart';

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font symbols;

  const _PdfFonts({
    required this.regular,
    required this.bold,
    required this.symbols,
  });
}

class PdfService {
  static const defaultReportFooterNote =
      'NB: Il n\'est delivre qu\'un seul Bulletin. Delai de reclamation : 30 jours date de reception.';
  static _PdfFonts? _cachedPdfFonts;

  static Future<_PdfFonts> _loadPdfFonts() async {
    if (_cachedPdfFonts != null) return _cachedPdfFonts!;
    final regularData = await rootBundle.load(
      'assets/fonts/nunito/Nunito-Regular.ttf',
    );
    final boldData = await rootBundle.load(
      'assets/fonts/nunito/Nunito-Bold.ttf',
    );
    final symbolsData = await rootBundle.load(
      'assets/fonts/NotoSansSymbols2/NotoSansSymbols2-Regular.ttf',
    );
    _cachedPdfFonts = _PdfFonts(
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
      symbols: pw.Font.ttf(symbolsData),
    );
    return _cachedPdfFonts!;
  }

  /// Vérifie si l'action est autorisée (non bloquée par le mode coffre fort)
  static bool _isActionAllowed() {
    return SafeModeService.instance.isActionAllowed();
  }

  /// Normalise un champ texte pour l'affichage PDF (évite les cellules "vides").
  static String dashIfBlank(String? value, {String placeholder = '-'}) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? placeholder : v;
  }

  /// Affiche uniquement le nom (dernier token) d'un professeur.
  static String teacherSurname(String? value, {String placeholder = '-'}) {
    final v = (value ?? '').replaceAll(',', ' ').trim();
    if (v.isEmpty) return placeholder;
    final parts = v.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return placeholder;
    return parts.last;
  }

  static Future<String> _resolveReportFooterNote() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('report_card_footer_note')) {
      return prefs.getString('report_card_footer_note') ?? '';
    }
    return defaultReportFooterNote;
  }

  static Future<String> _resolveAdminCivility() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('school_admin_civility') ?? 'M.').trim();
  }

  static String _resolveDirectorNameForLevel(
    SchoolInfo schoolInfo,
    String level,
  ) {
    final n = level.trim().toLowerCase();
    String? candidate;
    if (n.contains('primaire') || n.contains('maternelle')) {
      candidate = schoolInfo.directorPrimary;
    } else if (n.contains('coll')) {
      candidate = schoolInfo.directorCollege;
    } else if (n.contains('lyc')) {
      candidate = schoolInfo.directorLycee;
    } else if (n.contains('univ')) {
      candidate = schoolInfo.directorUniversity;
    }
    final resolved = candidate?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return schoolInfo.director.trim();
  }

  static bool _isLyceeLevel(String level) {
    final n = level.trim().toLowerCase();
    return n.contains('lyc');
  }

  static Future<String> _resolveAdminCivilityForLevel(
    SchoolInfo schoolInfo,
    String level,
  ) async {
    final n = level.trim().toLowerCase();
    String? candidate;
    if (n.contains('primaire') || n.contains('maternelle')) {
      candidate = schoolInfo.civilityPrimary;
    } else if (n.contains('coll')) {
      candidate = schoolInfo.civilityCollege;
    } else if (n.contains('lyc')) {
      candidate = schoolInfo.civilityLycee;
    } else if (n.contains('univ')) {
      candidate = schoolInfo.civilityUniversity;
    }
    final resolved = candidate?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return _resolveAdminCivility();
  }

  /// Calcule une moyenne sur 20 pondérée par `Grade.coefficient`.
  ///
  /// Formule appliquée sur chaque note : `((value / maxValue) * 20) * coefficient`.
  /// Les notes avec `maxValue <= 0` ou `coefficient <= 0` sont ignorées.
  static double computeWeightedAverageOn20(List<Grade> grades) {
    double total = 0.0;
    double totalCoeff = 0.0;
    for (final g in grades) {
      if (g.maxValue > 0 && g.coefficient > 0) {
        total += ((g.value / g.maxValue) * 20) * g.coefficient;
        totalCoeff += g.coefficient;
      }
    }
    return totalCoeff > 0 ? (total / totalCoeff) : 0.0;
  }

  /// Lance une exception si l'action est bloquée par le mode coffre fort
  static void _checkSafeMode() {
    if (!_isActionAllowed()) {
      throw Exception(SafeModeService.instance.getBlockedActionMessage());
    }
  }

  /// Helper method pour formater les dates
  static String _formatDate(String dateString) {
    if (dateString.isEmpty) return 'Non renseigné';

    try {
      // Essayer de parser la date dans différents formats
      DateTime? date;

      // Format ISO (2024-01-15)
      if (dateString.contains('-') && dateString.length >= 10) {
        date = DateTime.tryParse(dateString);
      }
      // Format français (15/01/2024)
      else if (dateString.contains('/')) {
        final parts = dateString.split('/');
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final year = int.tryParse(parts[2]);
          if (day != null && month != null && year != null) {
            date = DateTime(year, month, day);
          }
        }
      }

      if (date != null) {
        return DateFormat('dd/MM/yyyy').format(date);
      }
    } catch (e) {
      // En cas d'erreur, retourner la chaîne originale
    }

    return dateString;
  }

  /// Génère un PDF de reçu de paiement et retourne les bytes (pour aperçu ou impression)
  static Future<List<int>> generatePaymentReceiptPdf({
    required Payment currentPayment,
    required List<Payment> allPayments,
    required Student student,
    required SchoolInfo schoolInfo,
    required Class studentClass,
    required double totalPaid,
    required double totalDue,
  }) async {
    _checkSafeMode(); // Vérifier le mode coffre fort
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0 FCFA', 'fr_FR');
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primaryColor = PdfColor.fromHex('#4F46E5');
    final secondaryColor = PdfColor.fromHex('#6B7280');
    final lightBgColor = PdfColor.fromHex('#F3F4F6');

    // Préparer le bloc signatures/cachet pour le reçu
    final signaturePdfService = SignaturePdfService();
    // Choix du rôle administratif pour le reçu
    String adminRole = (schoolInfo.paymentsAdminRole ?? '')
        .trim()
        .toLowerCase();
    final classLevel = studentClass.level?.trim() ?? '';
    if (adminRole.isEmpty && classLevel.isNotEmpty) {
      adminRole = _isLyceeLevel(classLevel) ? 'proviseur' : 'directeur';
    }
    if (adminRole.isEmpty) {
      // 1) Lire le niveau depuis les paramètres (SharedPreferences)
      try {
        final prefs = await SharedPreferences.getInstance();
        final schoolLevel = (prefs.getString('school_level') ?? '')
            .toLowerCase();
        if (schoolLevel.contains('complexe')) {
          final n = classLevel.toLowerCase();
          if (n.contains('primaire') || n.contains('maternelle')) {
            adminRole = 'directeur_primaire';
          } else if (n.contains('coll')) {
            adminRole = 'directeur_college';
          } else if (n.contains('lyc')) {
            adminRole = 'directeur_lycee';
          } else if (n.contains('univ')) {
            adminRole = 'directeur_universite';
          }
        } else if (schoolLevel.contains('lyc')) {
          adminRole = 'proviseur';
        }
      } catch (_) {}

      // 2) Heuristique sur le nom de la classe si toujours vide
      if (adminRole.isEmpty) {
        bool _isLycee(String n) {
          final s = n.toLowerCase();
          return s.contains('lyc') ||
              s.contains('lycée') ||
              s.contains('lycee') ||
              s.contains('seconde') ||
              s.contains('2nde') ||
              s.contains('première') ||
              s.contains('1ère') ||
              s.contains('1ere') ||
              s.contains('term') ||
              s.contains('terminal');
        }

        adminRole = _isLycee(studentClass.name) ? 'proviseur' : 'directeur';
      }
    }
    // Afficher toujours le nom (comme dans le bulletin). Pour l'instant, on utilise
    // le champ 'director' de SchoolInfo comme nom du signataire administratif.
    final adminCivility = await _resolveAdminCivilityForLevel(
      schoolInfo,
      classLevel,
    );
    final String directeurName = _resolveDirectorNameForLevel(
      schoolInfo,
      classLevel,
    );
    final String directeurDisplayName = directeurName.isEmpty
        ? ''
        : (adminCivility.isNotEmpty
              ? '$adminCivility $directeurName'
              : directeurName);

    final pw.Widget receiptSignatureBlock = await signaturePdfService
        .createReceiptSignatureBlock(
          adminRole: adminRole,
          directeur: directeurDisplayName,
          times: times,
          timesBold: timesBold,
          mainColor: primaryColor,
          secondaryColor: secondaryColor,
          baseFont: 10,
          spacing: 8,
        );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final double remainingBalance = totalDue - totalPaid;
          return pw.Stack(
            children: [
              if (schoolInfo.logoPath != null &&
                  File(schoolInfo.logoPath!).existsSync())
                pw.Positioned.fill(
                  child: pw.Center(
                    child: pw.Opacity(
                      opacity: 0.06,
                      child: pw.Image(
                        pw.MemoryImage(
                          File(schoolInfo.logoPath!).readAsBytesSync(),
                        ),
                        width: 400,
                      ),
                    ),
                  ),
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // En-tête administratif (Ministère / République / Devise + Inspection / Direction)
                  if (schoolInfo != null) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: ((schoolInfo.ministry ?? '').isNotEmpty)
                              ? pw.Text(
                                  (schoolInfo.ministry ?? '').toUpperCase(),
                                  style: pw.TextStyle(
                                    font: timesBold,
                                    fontSize: 10,
                                    color: PdfColors.blueGrey800,
                                  ),
                                )
                              : pw.SizedBox(),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text(
                                ((schoolInfo.republic ?? 'RÉPUBLIQUE')
                                    .toUpperCase()),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 10,
                                  color: PdfColors.blueGrey800,
                                ),
                              ),
                              if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(top: 2),
                                  child: pw.Text(
                                    schoolInfo.republicMotto!,
                                    style: pw.TextStyle(
                                      font: times,
                                      fontSize: 9,
                                      color: PdfColors.blueGrey700,
                                      fontStyle: pw.FontStyle.italic,
                                    ),
                                    textAlign: pw.TextAlign.right,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: ((schoolInfo.inspection ?? '').isNotEmpty)
                              ? pw.Text(
                                  'Inspection: ${schoolInfo.inspection}',
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 9,
                                    color: PdfColors.blueGrey700,
                                  ),
                                )
                              : pw.SizedBox(),
                        ),
                        pw.Expanded(
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child:
                                ((schoolInfo.educationDirection ?? '')
                                    .isNotEmpty)
                                ? pw.Text(
                                    "Direction de l'enseignement: ${schoolInfo.educationDirection}",
                                    style: pw.TextStyle(
                                      font: times,
                                      fontSize: 9,
                                      color: PdfColors.blueGrey700,
                                    ),
                                  )
                                : pw.SizedBox(),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                  ],
                  // --- En-tête ---
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: lightBgColor,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (schoolInfo.logoPath != null &&
                            File(schoolInfo.logoPath!).existsSync())
                          pw.Image(
                            pw.MemoryImage(
                              File(schoolInfo.logoPath!).readAsBytesSync(),
                            ),
                            height: 60,
                            width: 60,
                          ),
                        if (schoolInfo.logoPath != null) pw.SizedBox(width: 20),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                schoolInfo.name,
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 20,
                                  color: primaryColor,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                schoolInfo.address,
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: secondaryColor,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  if ((schoolInfo.email ?? '').isNotEmpty)
                                    pw.Text(
                                      'Email : ${schoolInfo.email}',
                                      style: pw.TextStyle(
                                        font: times,
                                        fontSize: 10,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  if ((schoolInfo.website ?? '').isNotEmpty)
                                    pw.Text(
                                      'Site web : ${schoolInfo.website}',
                                      style: pw.TextStyle(
                                        font: times,
                                        fontSize: 10,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  if ((schoolInfo.telephone ?? '').isNotEmpty)
                                    pw.Text(
                                      'Téléphone : ${schoolInfo.telephone}',
                                      style: pw.TextStyle(
                                        font: times,
                                        fontSize: 10,
                                        color: secondaryColor,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'REÇU DE PAIEMENT',
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'Reçu N°: ${(currentPayment.receiptNo ?? '').trim().isNotEmpty ? currentPayment.receiptNo : (currentPayment.id ?? currentPayment.date.hashCode)}',
                              style: pw.TextStyle(font: times, fontSize: 10),
                            ),
                            pw.Text(
                              'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(currentPayment.date))}',
                              style: pw.TextStyle(font: times, fontSize: 10),
                            ),
                            pw.Text(
                              'Année: ${studentClass.academicYear}',
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 30),

                  // --- Informations sur l'élève ---
                  pw.Text(
                    'Reçu de :',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 14,
                      color: primaryColor,
                    ),
                  ),
                  pw.Divider(color: lightBgColor, thickness: 2),
                  pw.SizedBox(height: 0),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          'Nom de l\'élève:',
                          style: pw.TextStyle(font: timesBold),
                        ),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          '${student.lastName} ${student.firstName}'.trim(),
                          style: pw.TextStyle(font: times),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          'Classe:',
                          style: pw.TextStyle(font: timesBold),
                        ),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          student.className,
                          style: pw.TextStyle(font: times),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 30),

                  // --- Détails du paiement actuel ---
                  pw.Text(
                    'Historique des transactions',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 14,
                      color: primaryColor,
                    ),
                  ),
                  pw.Table(
                    border: pw.TableBorder.all(color: lightBgColor, width: 1.5),
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: lightBgColor),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              'Date',
                              style: pw.TextStyle(font: timesBold),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              'Description',
                              style: pw.TextStyle(font: timesBold),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              'Montant',
                              style: pw.TextStyle(font: timesBold),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      ...allPayments.map(
                        (payment) => pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(DateTime.parse(payment.date)),
                                style: pw.TextStyle(font: times),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                payment.comment ??
                                    'Paiement frais de scolarité',
                                style: pw.TextStyle(font: times),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                formatter.format(payment.amount),
                                style: pw.TextStyle(font: times),
                                textAlign: pw.TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (currentPayment.isCancelled)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 8),
                      child: pw.Text(
                        'LE DERNIER PAIEMENT A ÉTÉ ANNULÉ',
                        style: pw.TextStyle(
                          font: timesBold,
                          color: PdfColors.red,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 14,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  pw.SizedBox(height: 30),

                  // --- Résumé financier ---
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: lightBgColor, width: 2),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Résumé Financier',
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 14,
                                color: primaryColor,
                              ),
                            ),
                            pw.SizedBox(height: 10),
                            _buildSummaryRow(
                              'Total des Frais de Scolarité:',
                              formatter.format(totalDue),
                              times,
                              timesBold,
                            ),
                            _buildSummaryRow(
                              'Montant Total Payé:',
                              formatter.format(totalPaid),
                              times,
                              timesBold,
                            ),
                          ],
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(12),
                          decoration: pw.BoxDecoration(
                            color: remainingBalance > 0
                                ? PdfColors.amber50
                                : PdfColors.green50,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(6),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                remainingBalance <= 0
                                    ? 'Statut'
                                    : 'Solde Restant',
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 12,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                remainingBalance <= 0
                                    ? 'Payé'
                                    : formatter.format(remainingBalance),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 18,
                                  fontWeight: pw.FontWeight.bold,
                                  color: remainingBalance > 0
                                      ? PdfColors.amber700
                                      : PdfColors.green700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Spacer(),

                  // --- Pied de page ---
                  pw.Divider(color: lightBgColor, thickness: 1),
                  // Bloc signatures & cachet (automatique)
                  receiptSignatureBlock,
                  pw.SizedBox(height: 8),
                  // Message de remerciement tout en bas
                  pw.Text(
                    'Merci pour votre paiement.',
                    style: pw.TextStyle(
                      font: times,
                      fontStyle: pw.FontStyle.italic,
                      color: secondaryColor,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static pw.Widget _buildSummaryRow(
    String title,
    String value,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
      child: pw.Row(
        children: [
          pw.Text(title, style: pw.TextStyle(font: font, fontSize: 11)),
          pw.SizedBox(width: 10),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Sauvegarde le PDF de reçu de paiement dans le dossier documents et retourne le fichier
  static Future<File> savePaymentReceiptPdf({
    required Payment currentPayment,
    required List<Payment> allPayments,
    required Student student,
    required SchoolInfo schoolInfo,
    required Class studentClass,
    required double totalPaid,
    required double totalDue,
  }) async {
    final bytes = await generatePaymentReceiptPdf(
      currentPayment: currentPayment,
      allPayments: allPayments,
      student: student,
      schoolInfo: schoolInfo,
      studentClass: studentClass,
      totalPaid: totalPaid,
      totalDue: totalDue,
    );
    final directory = await getApplicationDocumentsDirectory();
    final receiptId = (currentPayment.receiptNo ?? '').trim().isNotEmpty
        ? currentPayment.receiptNo!.trim()
        : (currentPayment.id?.toString() ??
              DateTime.now().millisecondsSinceEpoch.toString());
    final file = File(
      '${directory.path}/recu_paiement_${student.id}_$receiptId.pdf',
    );
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Génère un reçu de paiement (format compact) et retourne les bytes.
  static Future<List<int>> generatePaymentTicketPdf({
    required Payment currentPayment,
    required List<Payment> allPayments,
    required Student student,
    required SchoolInfo schoolInfo,
    required Class studentClass,
    required double totalPaid,
    required double totalDue,
  }) async {
    _checkSafeMode(); // Vérifier le mode coffre fort
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0 FCFA', 'fr_FR');
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primaryColor = PdfColor.fromHex('#4F46E5');
    final secondaryColor = PdfColor.fromHex('#6B7280');
    final lightBgColor = PdfColor.fromHex('#F3F4F6');

    final date = DateTime.tryParse(currentPayment.date) ?? DateTime.now();
    final remainingBalance = totalDue - totalPaid;
    final isPaid = remainingBalance <= 0;
    final receiptNumber = (currentPayment.receiptNo ?? '').trim().isNotEmpty
        ? currentPayment.receiptNo!.trim()
        : ((currentPayment.id?.toString().trim().isNotEmpty ?? false)
              ? currentPayment.id.toString()
              : currentPayment.date.hashCode.toString());

    final studentNameRaw = '${student.lastName} ${student.firstName}'.trim();
    final studentNameDisplay = dashIfBlank(studentNameRaw);
    final qrPayload = jsonEncode({
      'type': 'payment_receipt_compact',
      'school': schoolInfo.name,
      'student': studentNameRaw,
      'class': student.className,
      'year': student.academicYear,
      'receiptNo': receiptNumber,
      'amount': currentPayment.amount,
      'date': currentPayment.date,
    });

    final pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      190 * PdfPageFormat.mm,
      marginLeft: 6 * PdfPageFormat.mm,
      marginRight: 6 * PdfPageFormat.mm,
      marginTop: 6 * PdfPageFormat.mm,
      marginBottom: 6 * PdfPageFormat.mm,
    );

    pw.MemoryImage? logoImage;
    if (schoolInfo.logoPath != null &&
        schoolInfo.logoPath!.trim().isNotEmpty &&
        File(schoolInfo.logoPath!).existsSync()) {
      logoImage = pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync());
    }

    pw.Widget line() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Divider(color: PdfColors.grey400, thickness: 0.7),
    );

    pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              k,
              style: pw.TextStyle(
                font: times,
                fontSize: 9,
                color: secondaryColor,
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              v,
              style: pw.TextStyle(
                font: bold ? timesBold : times,
                fontSize: 9,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 6),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.7),
                  ),
                ),
                child: pw.Column(
                  children: [
                    if (logoImage != null)
                      pw.Container(
                        width: 28,
                        height: 28,
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(6),
                          border: pw.Border.all(
                            color: PdfColors.grey300,
                            width: 0.7,
                          ),
                        ),
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.ClipRRect(
                          horizontalRadius: 4,
                          verticalRadius: 4,
                          child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                        ),
                      ),
                    if (logoImage != null) pw.SizedBox(height: 6),
                    pw.Text(
                      dashIfBlank(schoolInfo.name).toUpperCase(),
                      style: pw.TextStyle(font: timesBold, fontSize: 11),
                      textAlign: pw.TextAlign.center,
                    ),
                    if ((schoolInfo.motto ?? '').trim().isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: pw.Text(
                          schoolInfo.motto!.trim(),
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 8,
                            color: secondaryColor,
                            fontStyle: pw.FontStyle.italic,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    if ((schoolInfo.address).trim().isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text(
                          schoolInfo.address.trim(),
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 8.5,
                            color: secondaryColor,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    if ((schoolInfo.telephone ?? '').trim().isNotEmpty ||
                        (schoolInfo.email ?? '').trim().isNotEmpty ||
                        (schoolInfo.website ?? '').trim().isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Wrap(
                          alignment: pw.WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            if ((schoolInfo.telephone ?? '').trim().isNotEmpty)
                              pw.Text(
                                'Tél: ${schoolInfo.telephone!.trim()}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 8,
                                  color: secondaryColor,
                                ),
                              ),
                            if ((schoolInfo.email ?? '').trim().isNotEmpty)
                              pw.Text(
                                schoolInfo.email!.trim(),
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 8,
                                  color: secondaryColor,
                                ),
                              ),
                            if ((schoolInfo.website ?? '').trim().isNotEmpty)
                              pw.Text(
                                schoolInfo.website!.trim(),
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 8,
                                  color: secondaryColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: pw.BoxDecoration(
                  color: lightBgColor,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'REÇU DE PAIEMENT',
                      style: pw.TextStyle(
                        font: timesBold,
                        fontSize: 11,
                        color: primaryColor,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(date),
                      style: pw.TextStyle(
                        font: times,
                        fontSize: 8.5,
                        color: secondaryColor,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),
              kv('Élève', studentNameDisplay, bold: true),
              kv('Classe', dashIfBlank(student.className)),
              kv('Année académique', dashIfBlank(student.academicYear)),
              kv('Reçu N°:', receiptNumber),
              line(),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: lightBgColor,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      formatter.format(currentPayment.amount),
                      style: pw.TextStyle(font: timesBold, fontSize: 13),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 6),
                    kv('Total dû', formatter.format(totalDue)),
                    kv('Total payé', formatter.format(totalPaid)),
                    if (!isPaid)
                      kv(
                        'Reste',
                        formatter.format(remainingBalance),
                        bold: remainingBalance > 0,
                      ),
                  ],
                ),
              ),
              if ((currentPayment.comment ?? '').trim().isNotEmpty) ...[
                line(),
                kv('Commentaire', dashIfBlank(currentPayment.comment)),
              ],
              line(),
              pw.Spacer(),
              if (isPaid) ...[
                pw.Center(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#DCFCE7'),
                      border: pw.Border.all(
                        color: PdfColor.fromHex('#16A34A'),
                        width: 1,
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      'PAYÉ',
                      style: pw.TextStyle(
                        font: timesBold,
                        fontSize: 11,
                        color: PdfColor.fromHex('#16A34A'),
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
                    borderRadius: pw.BorderRadius.circular(8),
                    color: PdfColors.white,
                  ),
                  child: pw.BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: qrPayload,
                    width: 62,
                    height: 62,
                    drawText: false,
                    color: PdfColors.black,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  'Merci.',
                  style: pw.TextStyle(font: timesBold, fontSize: 10),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Génère un PDF tabulaire de la liste des paiements (export)
  static Future<List<int>> exportPaymentsListPdf({
    required List<Map<String, dynamic>> rows,
  }) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0.00', 'fr_FR');
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final dbService = DatabaseService();
    final schoolInfo = await dbService.getSchoolInfo();
    final currentAcademicYear = await getCurrentAcademicYear();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // En-tête administratif (Ministère / République / Devise + Inspection / Direction)
            if (schoolInfo != null) ...[
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: ((schoolInfo!.ministry ?? '').isNotEmpty)
                        ? pw.Text(
                            (schoolInfo!.ministry ?? '').toUpperCase(),
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: 10,
                              color: PdfColors.blueGrey800,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          ((schoolInfo!.republic ?? 'RÉPUBLIQUE')
                              .toUpperCase()),
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: PdfColors.blueGrey800,
                          ),
                        ),
                        if ((schoolInfo!.republicMotto ?? '').isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: pw.Text(
                              schoolInfo!.republicMotto!,
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 9,
                                color: PdfColors.blueGrey700,
                                fontStyle: pw.FontStyle.italic,
                              ),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: ((schoolInfo!.inspection ?? '').isNotEmpty)
                        ? pw.Text(
                            'Inspection: ${schoolInfo!.inspection}',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: PdfColors.blueGrey700,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: ((schoolInfo!.educationDirection ?? '').isNotEmpty)
                          ? pw.Text(
                              "Direction de l'enseignement: ${schoolInfo!.educationDirection}",
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 9,
                                color: PdfColors.blueGrey700,
                              ),
                            )
                          : pw.SizedBox(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
            ],
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (schoolInfo?.logoPath != null &&
                      File(schoolInfo!.logoPath!).existsSync())
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(
                        pw.MemoryImage(
                          File(schoolInfo.logoPath!).readAsBytesSync(),
                        ),
                        width: 50,
                        height: 50,
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo?.name ?? 'Établissement',
                          style: pw.TextStyle(font: timesBold, fontSize: 16),
                        ),
                        pw.Text(
                          schoolInfo?.address ?? '',
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 10,
                            color: PdfColors.blueGrey800,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Année académique: $currentAcademicYear',
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 10,
                            color: PdfColors.blueGrey800,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        if ((schoolInfo?.email ?? '').isNotEmpty)
                          pw.Text(
                            'Email : ${schoolInfo!.email}',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 10,
                              color: PdfColors.blueGrey800,
                            ),
                          ),
                        if ((schoolInfo?.website ?? '').isNotEmpty)
                          pw.Text(
                            'Site web : ${schoolInfo!.website}',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 10,
                              color: PdfColors.blueGrey800,
                            ),
                          ),
                        if ((schoolInfo?.telephone ?? '').isNotEmpty)
                          pw.Text(
                            'Téléphone : ${schoolInfo!.telephone}',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 10,
                              color: PdfColors.blueGrey800,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Export des paiements',
              style: pw.TextStyle(
                font: timesBold,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              cellStyle: pw.TextStyle(font: times, fontSize: 11),
              headerStyle: pw.TextStyle(
                font: timesBold,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              headers: [
                'Nom',
                'Classe',
                'Année',
                'Montant dû',
                'Montant payé',
                'Reste',
                'Retard',
                'Date',
                'Statut',
                'Commentaire',
              ],
              data: rows.map((row) {
                final student = row['student'];
                final payment = row['payment'];
                final classe = row['classe'];
                final totalPaid = row['totalPaid'] ?? 0.0;
                final double montantMax =
                    (row['totalDue'] as num?)?.toDouble() ??
                    ((classe?.fraisEcole ?? 0) +
                        (classe?.fraisCotisationParallele ?? 0));
                final remaining = montantMax - totalPaid;
                final arrears = (row['arrears'] as num?)?.toDouble();
                String statut;
                if (montantMax > 0 && totalPaid >= montantMax) {
                  statut = 'Payé';
                } else if (payment != null && totalPaid > 0) {
                  statut = 'En attente';
                } else {
                  statut = 'Impayé';
                }
                return [
                  '${student.firstName} ${student.lastName}'.trim(),
                  student.className,
                  classe?.academicYear ?? '',
                  formatter.format(montantMax),
                  formatter.format(totalPaid),
                  formatter.format(remaining > 0 ? remaining : 0),
                  formatter.format((arrears ?? 0) > 0 ? arrears : 0),
                  payment != null
                      ? payment.date.replaceFirst('T', ' ').substring(0, 16)
                      : '',
                  statut,
                  payment?.comment ?? '',
                ];
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerLeft,
                8: pw.Alignment.center,
                9: pw.Alignment.centerLeft,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.1),
                4: const pw.FlexColumnWidth(1.1),
                5: const pw.FlexColumnWidth(1.1),
                6: const pw.FlexColumnWidth(1.1),
                7: const pw.FlexColumnWidth(1.3),
                8: const pw.FlexColumnWidth(1.0),
                9: const pw.FlexColumnWidth(2),
              },
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF de relances (reste dû à date) à partir d'une liste de lignes.
  ///
  /// Chaque ligne doit contenir au minimum:
  /// - student (Student)
  /// - classe (Class?)
  /// - totalDue (double)
  /// - totalPaid (double)
  /// - expectedPaid (double)
  /// - arrears (double)
  static Future<List<int>> generatePaymentRemindersPdf({
    required List<Map<String, dynamic>> rows,
  }) async {
    _checkSafeMode();
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final formatter = NumberFormat('#,##0 FCFA', 'fr_FR');
    final dbService = DatabaseService();
    final schoolInfo = await dbService.getSchoolInfo();
    final currentAcademicYear = await getCurrentAcademicYear();

    final String footerDate = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Généré le: $footerDate',
              style: pw.TextStyle(font: times, fontSize: 8),
            ),
            pw.Text(
              'Page ${context.pageNumber}/${context.pagesCount}',
              style: pw.TextStyle(font: times, fontSize: 8),
            ),
          ],
        ),
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (schoolInfo?.logoPath != null &&
                      File(schoolInfo!.logoPath!).existsSync())
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(
                        pw.MemoryImage(
                          File(schoolInfo.logoPath!).readAsBytesSync(),
                        ),
                        width: 42,
                        height: 42,
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo?.name ?? 'Établissement',
                          style: pw.TextStyle(font: timesBold, fontSize: 14),
                        ),
                        pw.Text(
                          schoolInfo?.address ?? '',
                          style: pw.TextStyle(font: times, fontSize: 9),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Année académique: $currentAcademicYear',
                          style: pw.TextStyle(font: times, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Relances de paiements (reste dû à date)',
              style: pw.TextStyle(
                font: timesBold,
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            ...rows.map((row) {
              final Student student = row['student'] as Student;
              final Class? classe = row['classe'] as Class?;
              final totalDue = (row['totalDue'] as num?)?.toDouble() ?? 0.0;
              final totalPaid = (row['totalPaid'] as num?)?.toDouble() ?? 0.0;
              final expectedPaid =
                  (row['expectedPaid'] as num?)?.toDouble() ?? 0.0;
              final arrears = (row['arrears'] as num?)?.toDouble() ?? 0.0;
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${student.lastName} ${student.firstName}'.trim(),
                      style: pw.TextStyle(font: timesBold, fontSize: 12),
                    ),
                    pw.Text(
                      'Classe: ${student.className}  -  Année: ${classe?.academicYear ?? student.academicYear}',
                      style: pw.TextStyle(font: times, fontSize: 9),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total dû: ${formatter.format(totalDue)}',
                          style: pw.TextStyle(font: times, fontSize: 10),
                        ),
                        pw.Text(
                          'Total payé: ${formatter.format(totalPaid)}',
                          style: pw.TextStyle(font: times, fontSize: 10),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Attendu à date: ${formatter.format(expectedPaid)}',
                          style: pw.TextStyle(font: times, fontSize: 10),
                        ),
                        pw.Text(
                          'Reste dû à date: ${formatter.format(arrears)}',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: PdfColors.orange800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Génère un PDF tabulaire de la liste des élèves d'une classe (export)
  static Future<List<int>> exportStudentsListPdf({
    required List<Map<String, dynamic>> students,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');
    final success = PdfColor.fromHex('#10B981');
    final warning = PdfColor.fromHex('#F59E0B');

    // Style de base avec fallback
    final baseTextStyle = pw.TextStyle(font: times, fontSize: 9);
    final baseBoldStyle = pw.TextStyle(
      font: timesBold,
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
    );

    // Trie par nom de famille puis prénom
    final sorted = List<Map<String, dynamic>>.from(students)
      ..sort((a, b) {
        final studentA = a['student'] as Student;
        final studentB = b['student'] as Student;
        final nameA = '${studentA.lastName} ${studentA.firstName}'.trim();
        final nameB = '${studentB.lastName} ${studentB.firstName}'.trim();
        return nameA.compareTo(nameB);
      });

    // Récupération des informations de l'école
    final dbService = DatabaseService();
    final schoolInfo = await dbService.getSchoolInfo();
    final currentAcademicYear = await getCurrentAcademicYear();

    final String footerDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          buildBackground:
              (schoolInfo?.logoPath != null &&
                  File(schoolInfo!.logoPath!).existsSync())
              ? (context) => pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Opacity(
                    opacity: 0.06,
                    child: pw.Image(
                      pw.MemoryImage(
                        File(schoolInfo.logoPath!).readAsBytesSync(),
                      ),
                      fit: pw.BoxFit.cover,
                    ),
                  ),
                )
              : null,
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Container(height: 0.8, color: PdfColors.blueGrey300),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Généré le: ' + footerDate,
                  style: pw.TextStyle(font: times, fontSize: 8),
                ),
                pw.Text(
                  'Page ' +
                      context.pageNumber.toString() +
                      '/' +
                      context.pagesCount.toString(),
                  style: pw.TextStyle(font: times, fontSize: 8),
                ),
              ],
            ),
          ],
        ),
        build: (context) {
          return [
            // En-tête administratif
            if (schoolInfo != null) ...[
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: ((schoolInfo!.ministry ?? '').isNotEmpty)
                        ? pw.Text(
                            (schoolInfo!.ministry ?? '').toUpperCase(),
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: 10,
                              color: primary,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          ((schoolInfo!.republic ?? 'RÉPUBLIQUE')
                              .toUpperCase()),
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: primary,
                          ),
                        ),
                        if ((schoolInfo!.republicMotto ?? '').isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: pw.Text(
                              schoolInfo!.republicMotto!,
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 9,
                                color: primary,
                                fontStyle: pw.FontStyle.italic,
                              ),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: ((schoolInfo!.inspection ?? '').isNotEmpty)
                        ? pw.Text(
                            'Inspection: ${schoolInfo!.inspection}',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: primary,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: ((schoolInfo!.educationDirection ?? '').isNotEmpty)
                          ? pw.Text(
                              "Direction de l'enseignement: ${schoolInfo!.educationDirection}",
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 9,
                                color: primary,
                              ),
                            )
                          : pw.SizedBox(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
            ],
            // En-tête harmonisé (comme le relevé de notes): logo centré + nom d'établissement en majuscules + séparateur
            if (schoolInfo != null) ...[
              if ((schoolInfo!.logoPath ?? '').isNotEmpty &&
                  File(schoolInfo!.logoPath!).existsSync())
                pw.Center(
                  child: pw.Container(
                    height: 40,
                    width: 40,
                    child: pw.Image(
                      pw.MemoryImage(
                        File(schoolInfo.logoPath!).readAsBytesSync(),
                      ),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  ((schoolInfo!.name ?? '')).toUpperCase(),
                  style: pw.TextStyle(
                    font: timesBold,
                    fontSize: 14,
                    color: primary,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColors.blueGrey300),
              pw.SizedBox(height: 8),
            ],

            // Titre principal
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 16,
              ),
              decoration: pw.BoxDecoration(
                color: accent,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'Liste des élèves de la classe de ${sorted.isNotEmpty ? sorted.first['classe']?.name ?? 'classe' : 'classe'}',
                style: pw.TextStyle(
                  font: timesBold,
                  fontSize: 14,
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 16),

            // Statistiques rapides
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text(
                        '${sorted.length}',
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 16,
                          color: accent,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Total élèves',
                        style: pw.TextStyle(
                          font: times,
                          fontSize: 10,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(width: 1, height: 30, color: PdfColors.grey400),
                  pw.Column(
                    children: [
                      pw.Text(
                        '${sorted.where((s) => s['student'].gender == 'M').length}',
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 16,
                          color: success,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Garçons',
                        style: pw.TextStyle(
                          font: times,
                          fontSize: 10,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(width: 1, height: 30, color: PdfColors.grey400),
                  pw.Column(
                    children: [
                      pw.Text(
                        '${sorted.where((s) => s['student'].gender == 'F').length}',
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 16,
                          color: warning,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Filles',
                        style: pw.TextStyle(
                          font: times,
                          fontSize: 10,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Tableau simplifié pour liste de présence (avec Matricule)
            pw.Table.fromTextArray(
              cellStyle: pw.TextStyle(font: times, fontSize: 11),
              headerStyle: pw.TextStyle(
                font: timesBold,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(
                color: accent,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              headers: [
                'N°',
                'Matricule',
                'Nom et Prénom(s)',
                'Sexe',
                'Statut',
                'Présence',
              ],
              data: List.generate(sorted.length, (i) {
                final student = sorted[i]['student'];

                // Prendre la première lettre du statut en majuscule
                String statusLetter = '';
                if (student.status != null && student.status!.isNotEmpty) {
                  statusLetter = student.status!.substring(0, 1).toUpperCase();
                }

                return [
                  (i + 1).toString(),
                  ((student.matricule ?? '').replaceAll(RegExp(r'[^0-9]'), '')),
                  '${student.lastName} ${student.firstName}'.trim(),
                  student.gender == 'M' ? 'M' : 'F',
                  statusLetter,
                  '', // Colonne vide pour cocher la présence
                ];
              }),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignments: {
                0: pw.Alignment.center, // N°
                1: pw.Alignment.centerLeft, // Matricule
                2: pw.Alignment.centerLeft, // Nom Prénom(s)
                3: pw.Alignment.center, // Sexe
                4: pw.Alignment.center, // Statut
                5: pw.Alignment.center, // Présence
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(0.8), // N°
                1: const pw.FlexColumnWidth(2.0), // Matricule
                2: const pw.FlexColumnWidth(4.6), // Nom Prénom(s)
                3: const pw.FlexColumnWidth(1.2), // Sexe
                4: const pw.FlexColumnWidth(1.5), // Statut
                5: const pw.FlexColumnWidth(3.0), // Présence
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              cellPadding: const pw.EdgeInsets.all(8),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF de fiche profil individuelle pour un élève
  static Future<List<int>> exportStudentProfilePdf({
    required Student student,
    required Class? classe,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');
    final success = PdfColor.fromHex('#10B981');

    // Récupération des informations de l'école
    final dbService = DatabaseService();
    final schoolInfo = await dbService.getSchoolInfo();
    final currentAcademicYear = await getCurrentAcademicYear();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Stack(
            children: [
              // Logo en filigrane en arrière-plan
              if (schoolInfo?.logoPath != null &&
                  File(schoolInfo!.logoPath!).existsSync())
                pw.Positioned.fill(
                  child: pw.Center(
                    child: pw.Opacity(
                      opacity: 0.06,
                      child: pw.Image(
                        pw.MemoryImage(
                          File(schoolInfo.logoPath!).readAsBytesSync(),
                        ),
                        width: 400,
                      ),
                    ),
                  ),
                ),
              // Contenu principal
              pw.Column(
                children: [
                  // En-tête administratif (Ministère / République / Devise + Inspection / Direction)
                  if (schoolInfo != null) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: ((schoolInfo!.ministry ?? '').isNotEmpty)
                              ? pw.Text(
                                  (schoolInfo!.ministry ?? '').toUpperCase(),
                                  style: pw.TextStyle(
                                    font: timesBold,
                                    fontSize: 10,
                                    color: primary,
                                  ),
                                )
                              : pw.SizedBox(),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text(
                                ((schoolInfo!.republic ?? 'RÉPUBLIQUE')
                                    .toUpperCase()),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                              if ((schoolInfo!.republicMotto ?? '').isNotEmpty)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(top: 2),
                                  child: pw.Text(
                                    schoolInfo!.republicMotto!,
                                    style: pw.TextStyle(
                                      font: times,
                                      fontSize: 9,
                                      color: primary,
                                      fontStyle: pw.FontStyle.italic,
                                    ),
                                    textAlign: pw.TextAlign.right,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: ((schoolInfo!.inspection ?? '').isNotEmpty)
                              ? pw.Text(
                                  'Inspection: ${schoolInfo!.inspection}',
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 9,
                                    color: primary,
                                  ),
                                )
                              : pw.SizedBox(),
                        ),
                        pw.Expanded(
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child:
                                ((schoolInfo!.educationDirection ?? '')
                                    .isNotEmpty)
                                ? pw.Text(
                                    "Direction de l'enseignement: ${schoolInfo!.educationDirection}",
                                    style: pw.TextStyle(
                                      font: times,
                                      fontSize: 9,
                                      color: primary,
                                    ),
                                  )
                                : pw.SizedBox(),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                  ],
                  // Header avec logo et informations de l'école
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: light,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: accent, width: 1),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (schoolInfo?.logoPath != null &&
                            File(schoolInfo!.logoPath!).existsSync())
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(right: 16),
                            child: pw.Image(
                              pw.MemoryImage(
                                File(schoolInfo.logoPath!).readAsBytesSync(),
                              ),
                              width: 60,
                              height: 60,
                            ),
                          ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                schoolInfo?.name ?? 'École',
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 20,
                                  color: accent,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                'Année académique: $currentAcademicYear',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  // Titre principal avec photo
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Row(
                      children: [
                        // Photo de l'élève
                        if (student.photoPath != null &&
                            student.photoPath!.isNotEmpty &&
                            File(student.photoPath!).existsSync())
                          pw.Container(
                            width: 80,
                            height: 80,
                            decoration: pw.BoxDecoration(
                              borderRadius: pw.BorderRadius.circular(8),
                              border: pw.Border.all(
                                color: PdfColors.white,
                                width: 2,
                              ),
                            ),
                            child: pw.ClipRRect(
                              child: pw.Image(
                                pw.MemoryImage(
                                  File(student.photoPath!).readAsBytesSync(),
                                ),
                                fit: pw.BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          pw.Container(
                            width: 80,
                            height: 80,
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex('#E5E7EB'),
                              borderRadius: pw.BorderRadius.circular(8),
                              border: pw.Border.all(
                                color: PdfColors.white,
                                width: 2,
                              ),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'PHOTO',
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 10,
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        pw.SizedBox(width: 16),
                        // Titre avec nom
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'FICHE ACADÉMIQUE',
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 16,
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                '${student.firstName} ${student.lastName}'
                                    .trim()
                                    .toUpperCase(),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 20,
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  // Informations personnelles
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColors.grey200, width: 1),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'INFORMATIONS PERSONNELLES',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 14,
                            color: accent,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow(
                                    'Nom complet',
                                    '${student.firstName} ${student.lastName}'
                                        .trim(),
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Matricule',
                                    student.matricule ?? 'Non renseigné',
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Sexe',
                                    student.gender == 'M'
                                        ? 'Masculin'
                                        : 'Féminin',
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Date de naissance',
                                    _formatDate(student.dateOfBirth),
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Lieu de naissance',
                                    student.placeOfBirth ?? 'Non renseigné',
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Statut',
                                    student.status,
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 20),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow(
                                    'Classe',
                                    student.className,
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Année académique',
                                    student.academicYear,
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Date d\'inscription',
                                    _formatDate(student.enrollmentDate),
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Contact',
                                    student.contactNumber,
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Email',
                                    student.email,
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Adresse
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColors.grey200, width: 1),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ADRESSE',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 14,
                            color: accent,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          student.address,
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 12,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Informations du tuteur
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColors.grey200, width: 1),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'INFORMATIONS DU TUTEUR',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 14,
                            color: accent,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow(
                                    'Nom du tuteur',
                                    student.guardianName,
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                  _buildInfoRow(
                                    'Contact tuteur',
                                    student.guardianContact,
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 20),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow(
                                    'Contact urgence',
                                    student.emergencyContact,
                                    times,
                                    timesBold,
                                    primary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Informations médicales
                  if (student.medicalInfo != null &&
                      student.medicalInfo!.isNotEmpty)
                    pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(
                          color: PdfColors.grey200,
                          width: 1,
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'INFORMATIONS MÉDICALES',
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: 14,
                              color: accent,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(
                            student.medicalInfo!,
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 12,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  /// Helper method pour construire une ligne d'information
  static pw.Widget _buildInfoRow(
    String label,
    String value,
    pw.Font font,
    pw.Font fontBold,
    PdfColor color,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 11,
                color: color,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: font, fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Génère un PDF tabulaire de la liste des classes (export)
  static Future<List<int>> exportClassesListPdf({
    required List<Class> classes,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final dbService = DatabaseService();
    final schoolInfo = await dbService.getSchoolInfo();
    final currentAcademicYear = await getCurrentAcademicYear();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (schoolInfo != null) ...[
              // En-tête administratif
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: ((schoolInfo!.ministry ?? '').isNotEmpty)
                        ? pw.Text(
                            (schoolInfo!.ministry ?? '').toUpperCase(),
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: 10,
                              color: PdfColors.blueGrey800,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          ((schoolInfo!.republic ?? 'RÉPUBLIQUE')
                              .toUpperCase()),
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: PdfColors.blueGrey800,
                          ),
                        ),
                        if ((schoolInfo!.republicMotto ?? '').isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: pw.Text(
                              schoolInfo!.republicMotto!,
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 9,
                                color: PdfColors.blueGrey700,
                                fontStyle: pw.FontStyle.italic,
                              ),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: ((schoolInfo!.inspection ?? '').isNotEmpty)
                        ? pw.Text(
                            'Inspection: ${schoolInfo!.inspection}',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: PdfColors.blueGrey700,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: ((schoolInfo!.educationDirection ?? '').isNotEmpty)
                          ? pw.Text(
                              "Direction de l'enseignement: ${schoolInfo!.educationDirection}",
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 9,
                                color: PdfColors.blueGrey700,
                              ),
                            )
                          : pw.SizedBox(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              // Header établissement
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (schoolInfo?.logoPath != null &&
                        File(schoolInfo!.logoPath!).existsSync())
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 12),
                        child: pw.Image(
                          pw.MemoryImage(
                            File(schoolInfo.logoPath!).readAsBytesSync(),
                          ),
                          width: 50,
                          height: 50,
                        ),
                      ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            schoolInfo?.name ?? 'Établissement',
                            style: pw.TextStyle(font: timesBold, fontSize: 16),
                          ),
                          pw.Text(
                            schoolInfo?.address ?? '',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 10,
                              color: PdfColors.blueGrey800,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Année académique: $currentAcademicYear',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 10,
                              color: PdfColors.blueGrey800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
            ],
            pw.Text(
              'Liste des classes',
              style: pw.TextStyle(
                font: timesBold,
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              cellStyle: pw.TextStyle(font: times, fontSize: 11),
              headerStyle: pw.TextStyle(
                font: timesBold,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              headers: [
                'Nom',
                'Année',
                'Titulaire',
                'Frais école',
                'Frais cotisation parallèle',
              ],
              data: classes
                  .map(
                    (c) => [
                      c.name,
                      c.academicYear,
                      c.titulaire ?? '',
                      c.fraisEcole?.toString() ?? '',
                      c.fraisCotisationParallele?.toString() ?? '',
                    ],
                  )
                  .toList(),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF fidèle du bulletin scolaire d'un élève
  static Future<List<int>> generateReportCardPdf({
    required Student student,
    required SchoolInfo schoolInfo,
    required List<Grade> grades,
    required Map<String, String> professeurs,
    required Map<String, String> appreciations,
    required Map<String, String> moyennesClasse,
    required String appreciationGenerale,
    required String decision,
    String recommandations = '',
    String forces = '',
    String pointsADevelopper = '',
    String sanctions = '',
    int attendanceJustifiee = 0,
    int attendanceInjustifiee = 0,
    int retards = 0,
    double presencePercent = 0.0,
    String conduite = '',
    required String telEtab,
    required String mailEtab,
    required String webEtab,
    String titulaire = '',
    required List<String> subjects,
    required List<double?> moyennesParPeriode,
    required double moyenneGenerale,
    required int rang,
    required int nbEleves,
    bool exaequo = false,
    required String mention,
    required List<String> allTerms,
    required String periodLabel,
    required String selectedTerm,
    required String academicYear,
    required String faitA,
    required String leDate,
    required bool isLandscape,
    String niveau = '',
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    double? moyenneAnnuelle,
    bool duplicata = false,
  }) async {
    final footerNote = await _resolveReportFooterNote();
    final adminCivility = await _resolveAdminCivilityForLevel(
      schoolInfo,
      niveau,
    );
    return ReportCardPdfService.generateReportCardPdf(
      student: student,
      schoolInfo: schoolInfo,
      grades: grades,
      professeurs: professeurs,
      appreciations: appreciations,
      moyennesClasse: moyennesClasse,
      appreciationGenerale: appreciationGenerale,
      decision: decision,
      recommandations: recommandations,
      forces: forces,
      pointsADevelopper: pointsADevelopper,
      sanctions: sanctions,
      attendanceJustifiee: attendanceJustifiee,
      attendanceInjustifiee: attendanceInjustifiee,
      retards: retards,
      presencePercent: presencePercent,
      conduite: conduite,
      telEtab: telEtab,
      mailEtab: mailEtab,
      webEtab: webEtab,
      titulaire: titulaire,
      subjects: subjects,
      moyennesParPeriode: moyennesParPeriode,
      moyenneGenerale: moyenneGenerale,
      rang: rang,
      nbEleves: nbEleves,
      exaequo: exaequo,
      mention: mention,
      allTerms: allTerms,
      periodLabel: periodLabel,
      selectedTerm: selectedTerm,
      academicYear: academicYear,
      faitA: faitA,
      leDate: leDate,
      isLandscape: isLandscape,
      niveau: niveau,
      moyenneGeneraleDeLaClasse: moyenneGeneraleDeLaClasse,
      moyenneLaPlusForte: moyenneLaPlusForte,
      moyenneLaPlusFaible: moyenneLaPlusFaible,
      moyenneAnnuelle: moyenneAnnuelle,
      duplicata: duplicata,
      footerNote: footerNote,
      adminCivility: adminCivility,
    );
  }

  /// Génère un PDF bulletin compact (une seule page)
  static Future<List<int>> generateReportCardPdfCompact({
    required Student student,
    required SchoolInfo schoolInfo,
    required List<Grade> grades,
    required Map<String, String> professeurs,
    required Map<String, String> appreciations,
    required Map<String, String> moyennesClasse,
    required String appreciationGenerale,
    required String decision,
    String recommandations = '',
    String forces = '',
    String pointsADevelopper = '',
    String sanctions = '',
    int attendanceJustifiee = 0,
    int attendanceInjustifiee = 0,
    int retards = 0,
    double presencePercent = 0.0,
    String conduite = '',
    required String telEtab,
    required String mailEtab,
    required String webEtab,
    String titulaire = '',
    required List<String> subjects,
    required List<double?> moyennesParPeriode,
    required double moyenneGenerale,
    required int rang,
    required int nbEleves,
    bool exaequo = false,
    required String mention,
    required List<String> allTerms,
    required String periodLabel,
    required String selectedTerm,
    required String academicYear,
    required String faitA,
    required String leDate,
    required bool isLandscape,
    String niveau = '',
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    double? moyenneAnnuelle,
    bool duplicata = false,
  }) async {
    final footerNote = await _resolveReportFooterNote();
    final adminCivility = await _resolveAdminCivilityForLevel(
      schoolInfo,
      niveau,
    );
    return ReportCardCompactPdfService.generateReportCardPdfCompact(
      student: student,
      schoolInfo: schoolInfo,
      grades: grades,
      professeurs: professeurs,
      appreciations: appreciations,
      moyennesClasse: moyennesClasse,
      appreciationGenerale: appreciationGenerale,
      decision: decision,
      recommandations: recommandations,
      forces: forces,
      pointsADevelopper: pointsADevelopper,
      sanctions: sanctions,
      attendanceJustifiee: attendanceJustifiee,
      attendanceInjustifiee: attendanceInjustifiee,
      retards: retards,
      presencePercent: presencePercent,
      conduite: conduite,
      telEtab: telEtab,
      mailEtab: mailEtab,
      webEtab: webEtab,
      titulaire: titulaire,
      subjects: subjects,
      moyennesParPeriode: moyennesParPeriode,
      moyenneGenerale: moyenneGenerale,
      rang: rang,
      nbEleves: nbEleves,
      exaequo: exaequo,
      mention: mention,
      allTerms: allTerms,
      periodLabel: periodLabel,
      selectedTerm: selectedTerm,
      academicYear: academicYear,
      faitA: faitA,
      leDate: leDate,
      isLandscape: isLandscape,
      niveau: niveau,
      moyenneGeneraleDeLaClasse: moyenneGeneraleDeLaClasse,
      moyenneLaPlusForte: moyenneLaPlusForte,
      moyenneLaPlusFaible: moyenneLaPlusFaible,
      moyenneAnnuelle: moyenneAnnuelle,
      duplicata: duplicata,
      footerNote: footerNote,
      adminCivility: adminCivility,
    );
  }

  /// Génère un PDF ultra compact du bulletin scolaire d'un élève
  static Future<List<int>> generateReportCardPdfUltraCompact({
    required Student student,
    required SchoolInfo schoolInfo,
    required List<Grade> grades,
    required Map<String, String> professeurs,
    required Map<String, String> appreciations,
    required Map<String, String> moyennesClasse,
    required String appreciationGenerale,
    required String decision,
    String recommandations = '',
    String forces = '',
    String pointsADevelopper = '',
    String sanctions = '',
    int attendanceJustifiee = 0,
    int attendanceInjustifiee = 0,
    int retards = 0,
    double presencePercent = 0.0,
    String conduite = '',
    required String telEtab,
    required String mailEtab,
    required String webEtab,
    String titulaire = '',
    required List<String> subjects,
    required List<double?> moyennesParPeriode,
    required double moyenneGenerale,
    required int rang,
    required int nbEleves,
    bool exaequo = false,
    required String mention,
    required List<String> allTerms,
    required String periodLabel,
    required String selectedTerm,
    required String academicYear,
    required String faitA,
    required String leDate,
    required bool isLandscape,
    String niveau = '',
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    double? moyenneAnnuelle,
    bool duplicata = false,
  }) async {
    final footerNote = await _resolveReportFooterNote();
    final adminCivility = await _resolveAdminCivilityForLevel(
      schoolInfo,
      niveau,
    );
    return ReportCardUltraCompactPdfService.generateReportCardPdfUltraCompact(
      student: student,
      schoolInfo: schoolInfo,
      grades: grades,
      professeurs: professeurs,
      appreciations: appreciations,
      moyennesClasse: moyennesClasse,
      appreciationGenerale: appreciationGenerale,
      decision: decision,
      recommandations: recommandations,
      forces: forces,
      pointsADevelopper: pointsADevelopper,
      sanctions: sanctions,
      attendanceJustifiee: attendanceJustifiee,
      attendanceInjustifiee: attendanceInjustifiee,
      retards: retards,
      presencePercent: presencePercent,
      conduite: conduite,
      telEtab: telEtab,
      mailEtab: mailEtab,
      webEtab: webEtab,
      titulaire: titulaire,
      subjects: subjects,
      moyennesParPeriode: moyennesParPeriode,
      moyenneGenerale: moyenneGenerale,
      rang: rang,
      nbEleves: nbEleves,
      exaequo: exaequo,
      mention: mention,
      allTerms: allTerms,
      periodLabel: periodLabel,
      selectedTerm: selectedTerm,
      academicYear: academicYear,
      faitA: faitA,
      leDate: leDate,
      isLandscape: isLandscape,
      niveau: niveau,
      moyenneGeneraleDeLaClasse: moyenneGeneraleDeLaClasse,
      moyenneLaPlusForte: moyenneLaPlusForte,
      moyenneLaPlusFaible: moyenneLaPlusFaible,
      moyenneAnnuelle: moyenneAnnuelle,
      duplicata: duplicata,
      footerNote: footerNote,
      adminCivility: adminCivility,
    );
  }

  /// Génère un PDF de l'emploi du temps
  static Future<List<int>> generateTimetablePdf({
    required SchoolInfo schoolInfo,
    required String academicYear, // The academic year for the timetable
    required List<String> daysOfWeek,
    required List<String> timeSlots,
    required List<TimetableEntry> timetableEntries,
    required String title,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Stack(
            children: [
              // Logo en filigrane en arrière-plan
              if (schoolInfo.logoPath != null &&
                  File(schoolInfo.logoPath!).existsSync())
                pw.Positioned.fill(
                  child: pw.Center(
                    child: pw.Opacity(
                      opacity: 0.06,
                      child: pw.Image(
                        pw.MemoryImage(
                          File(schoolInfo.logoPath!).readAsBytesSync(),
                        ),
                        width: 400,
                      ),
                    ),
                  ),
                ),
              // Contenu principal
              pw.Column(
                children: [
                  // En-tête administratif
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: ((schoolInfo.ministry ?? '').isNotEmpty)
                            ? pw.Text(
                                (schoolInfo.ministry ?? '').toUpperCase(),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              ((schoolInfo.republic ?? 'RÉPUBLIQUE')
                                  .toUpperCase()),
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 10,
                                color: primary,
                              ),
                            ),
                            if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Text(
                                  schoolInfo.republicMotto!,
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 9,
                                    color: primary,
                                    fontStyle: pw.FontStyle.italic,
                                  ),
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: ((schoolInfo.inspection ?? '').isNotEmpty)
                            ? pw.Text(
                                'Inspection: ${schoolInfo.inspection}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 9,
                                  color: primary,
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child:
                              ((schoolInfo.educationDirection ?? '').isNotEmpty)
                              ? pw.Text(
                                  "Direction de l'enseignement: ${schoolInfo.educationDirection}",
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 9,
                                    color: primary,
                                  ),
                                )
                              : pw.SizedBox(),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  // Header
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: light,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (schoolInfo.logoPath != null &&
                            File(schoolInfo.logoPath!).existsSync())
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(right: 12),
                            child: pw.Image(
                              pw.MemoryImage(
                                File(schoolInfo.logoPath!).readAsBytesSync(),
                              ),
                              width: 50,
                              height: 50,
                            ),
                          ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                schoolInfo.name,
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 18,
                                  color: accent,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                schoolInfo.address,
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Année académique: $academicYear  -  Généré le: ' +
                                    DateFormat(
                                      'dd/MM/yyyy HH:mm',
                                    ).format(DateTime.now()),
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              if ((schoolInfo.email ?? '').isNotEmpty)
                                pw.Text(
                                  'Email : ${schoolInfo.email}',
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 10,
                                    color: primary,
                                  ),
                                ),
                              if ((schoolInfo.website ?? '').isNotEmpty)
                                pw.Text(
                                  'Site web : ${schoolInfo.website}',
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 10,
                                    color: primary,
                                  ),
                                ),
                              if ((schoolInfo.telephone ?? '').isNotEmpty)
                                pw.Text(
                                  'Téléphone : ${schoolInfo.telephone}',
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 10,
                                    color: primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Title
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 20,
                      color: accent,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),

                  // Timetable Table with colored cells
                  (() {
                    PdfColor colorFor(String subject) {
                      final palette = [
                        PdfColor.fromHex('#1D4ED8'),
                        PdfColor.fromHex('#DB2777'),
                        PdfColor.fromHex('#D97706'),
                        PdfColor.fromHex('#059669'),
                        PdfColor.fromHex('#6D28D9'),
                        PdfColor.fromHex('#BE123C'),
                        PdfColor.fromHex('#0EA5E9'),
                        PdfColor.fromHex('#059669'),
                      ];
                      final code = subject.codeUnits.fold<int>(
                        0,
                        (a, b) => (a + b) % palette.length,
                      );
                      return palette[code];
                    }

                    PdfColor lightFor(String subject) {
                      final lightPalette = [
                        PdfColor.fromHex('#DBEAFE'),
                        PdfColor.fromHex('#FCE7F3'),
                        PdfColor.fromHex('#FEF3C7'),
                        PdfColor.fromHex('#D1FAE5'),
                        PdfColor.fromHex('#EDE9FE'),
                        PdfColor.fromHex('#FFE4E6'),
                        PdfColor.fromHex('#E0F2FE'),
                        PdfColor.fromHex('#D1FAE5'),
                      ];
                      final code = subject.codeUnits.fold<int>(
                        0,
                        (a, b) => (a + b) % lightPalette.length,
                      );
                      return lightPalette[code];
                    }

                    final columnWidths = <int, pw.TableColumnWidth>{};
                    for (int i = 0; i <= daysOfWeek.length; i++) {
                      columnWidths[i] = const pw.FlexColumnWidth();
                    }

                    return pw.Table(
                      border: pw.TableBorder.all(color: light, width: 1.2),
                      columnWidths: columnWidths,
                      children: [
                        // Header row
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey300,
                          ),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                'Heure',
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                            ...daysOfWeek.map(
                              (d) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(
                                  d,
                                  style: pw.TextStyle(
                                    font: timesBold,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Data rows
                        ...timeSlots.map((timeSlot) {
                          final parts = timeSlot.split(' - ');
                          final slotStart = parts.first;
                          return pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(
                                  timeSlot,
                                  style: pw.TextStyle(font: times, fontSize: 8),
                                ),
                              ),
                              ...daysOfWeek.map((day) {
                                final entry = timetableEntries.firstWhere(
                                  (e) =>
                                      e.dayOfWeek == day &&
                                      e.startTime == slotStart,
                                  orElse: () => TimetableEntry(
                                    subject: '',
                                    teacher: '',
                                    className: '',
                                    academicYear: '',
                                    dayOfWeek: '',
                                    startTime: '',
                                    endTime: '',
                                    room: '',
                                  ),
                                );
                                final has = entry.subject.isNotEmpty;
                                final bg = has
                                    ? lightFor(entry.subject)
                                    : PdfColors.white;
                                final borderCol = has
                                    ? colorFor(entry.subject)
                                    : light;
                                final text = has
                                    ? '${entry.subject}\n${entry.teacher}\n${entry.className}\n${entry.room}'
                                    : '';
                                return pw.Container(
                                  padding: const pw.EdgeInsets.all(4),
                                  decoration: pw.BoxDecoration(
                                    color: bg,
                                    border: pw.Border.all(
                                      color: borderCol,
                                      width: has ? 0.8 : 0.4,
                                    ),
                                  ),
                                  child: pw.Text(
                                    text,
                                    style: pw.TextStyle(
                                      font: times,
                                      fontSize: 8,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        }),
                      ],
                    );
                  })(),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<List<int>> exportStatisticsPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required int totalStudents,
    required int totalStaff,
    required int totalClasses,
    required double totalRevenue,
    required List<Map<String, dynamic>> monthlyEnrollment,
    required Map<String, int> classDistribution,
  }) async {
    final pdf = pw.Document();
    final fonts = await _loadPdfFonts();
    final times = fonts.regular;
    final timesBold = fonts.bold;
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    String formatMonth(String ym) {
      // Expects YYYY-MM
      try {
        final parts = ym.split('-');
        if (parts.length == 2) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final date = DateTime(year, month, 1);
          return DateFormat('MMM yyyy', 'fr_FR').format(date);
        }
      } catch (_) {}
      return ym;
    }

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: times, bold: timesBold),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            // En-tête administratif (Ministère / République / Devise + Inspection / Direction)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: ((schoolInfo.ministry ?? '').isNotEmpty)
                      ? pw.Text(
                          (schoolInfo.ministry ?? '').toUpperCase(),
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: primary,
                          ),
                        )
                      : pw.SizedBox(),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        ((schoolInfo.republic ?? 'RÉPUBLIQUE').toUpperCase()),
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 10,
                          color: primary,
                        ),
                      ),
                      if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(
                            schoolInfo.republicMotto!,
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: primary,
                              fontStyle: pw.FontStyle.italic,
                              fontFallback: [fonts.symbols],
                            ),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(
                  child: ((schoolInfo.inspection ?? '').isNotEmpty)
                      ? pw.Text(
                          'Inspection: ${schoolInfo.inspection}',
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 9,
                            color: primary,
                          ),
                        )
                      : pw.SizedBox(),
                ),
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: ((schoolInfo.educationDirection ?? '').isNotEmpty)
                        ? pw.Text(
                            "Direction de l'enseignement: ${schoolInfo.educationDirection}",
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: primary,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: light,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (schoolInfo.logoPath != null &&
                      File(schoolInfo.logoPath!).existsSync())
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(
                        pw.MemoryImage(
                          File(schoolInfo.logoPath!).readAsBytesSync(),
                        ),
                        width: 50,
                        height: 50,
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo.name,
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 18,
                            color: accent,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          schoolInfo.address,
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 10,
                            color: primary,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Année académique: $academicYear  -  Généré le: ' +
                              DateFormat(
                                'dd/MM/yyyy HH:mm',
                              ).format(DateTime.now()),
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 10,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Title
            pw.Text(
              'Rapport de Statistiques',
              style: pw.TextStyle(
                font: timesBold,
                fontSize: 20,
                color: accent,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),

            // KPI cards (as table)
            pw.Table(
              border: pw.TableBorder.all(color: light, width: 1.2),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Indicateur',
                        style: pw.TextStyle(font: timesBold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Valeur',
                        style: pw.TextStyle(font: timesBold),
                      ),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Total élèves',
                        style: pw.TextStyle(font: times),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '$totalStudents',
                        style: pw.TextStyle(font: timesBold),
                      ),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Personnel',
                        style: pw.TextStyle(font: times),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '$totalStaff',
                        style: pw.TextStyle(font: timesBold),
                      ),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Classes',
                        style: pw.TextStyle(font: times),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '$totalClasses',
                        style: pw.TextStyle(font: timesBold),
                      ),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Revenus (total)',
                        style: pw.TextStyle(font: times),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        NumberFormat.currency(
                          locale: 'fr_FR',
                          symbol: 'FCFA',
                          decimalDigits: 0,
                        ).format(totalRevenue),
                        style: pw.TextStyle(font: timesBold),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (monthlyEnrollment.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Inscriptions mensuelles',
                style: pw.TextStyle(
                  font: timesBold,
                  fontSize: 14,
                  color: accent,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: light, width: 1.0),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          'Mois',
                          style: pw.TextStyle(font: timesBold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          'Inscriptions',
                          style: pw.TextStyle(font: timesBold),
                        ),
                      ),
                    ],
                  ),
                  ...monthlyEnrollment.map(
                    (e) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            formatMonth((e['month'] ?? '').toString()),
                            style: pw.TextStyle(font: times),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            ((e['count'] ?? 0)).toString(),
                            style: pw.TextStyle(font: times),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            if (classDistribution.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Répartition des élèves par classe',
                style: pw.TextStyle(
                  font: timesBold,
                  fontSize: 14,
                  color: accent,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: light, width: 1.0),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          'Classe',
                          style: pw.TextStyle(font: timesBold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          'Effectif',
                          style: pw.TextStyle(font: timesBold),
                        ),
                      ),
                    ],
                  ),
                  ...classDistribution.entries.map(
                    (e) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            e.key,
                            style: pw.TextStyle(font: times),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            e.value.toString(),
                            style: pw.TextStyle(font: times),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ];
        },
      ),
    );
    return pdf.save();
  }

  static Future<List<int>> generateStaffPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required List<Staff> staffList,
    required String title,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      buildBackground:
          (schoolInfo.logoPath != null &&
              File(schoolInfo.logoPath!).existsSync())
          ? (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Opacity(
                opacity: 0.05,
                child: pw.Image(
                  pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                  fit: pw.BoxFit.cover,
                ),
              ),
            )
          : null,
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        build: (pw.Context context) {
          return [
            // En-tête administratif
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: ((schoolInfo.ministry ?? '').isNotEmpty)
                      ? pw.Text(
                          (schoolInfo.ministry ?? '').toUpperCase(),
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: primary,
                          ),
                        )
                      : pw.SizedBox(),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        ((schoolInfo.republic ?? 'RÉPUBLIQUE').toUpperCase()),
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 10,
                          color: primary,
                        ),
                      ),
                      if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(
                            schoolInfo.republicMotto!,
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: primary,
                              fontStyle: pw.FontStyle.italic,
                            ),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(
                  child: ((schoolInfo.inspection ?? '').isNotEmpty)
                      ? pw.Text(
                          'Inspection: ${schoolInfo.inspection}',
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 9,
                            color: primary,
                          ),
                        )
                      : pw.SizedBox(),
                ),
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: ((schoolInfo.educationDirection ?? '').isNotEmpty)
                        ? pw.Text(
                            "Direction de l'enseignement: ${schoolInfo.educationDirection}",
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: primary,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            // Header avec logo et informations de l'école
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (schoolInfo.logoPath != null &&
                        File(schoolInfo.logoPath!).existsSync())
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 16),
                        child: pw.Image(
                          pw.MemoryImage(
                            File(schoolInfo.logoPath!).readAsBytesSync(),
                          ),
                          height: 60,
                          width: 60,
                        ),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo.name,
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 18,
                            color: primary,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          schoolInfo.address ?? '',
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 10,
                            color: primary,
                          ),
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if ((schoolInfo.email ?? '').isNotEmpty)
                              pw.Text(
                                'Email : ${schoolInfo.email}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                            if ((schoolInfo.website ?? '').isNotEmpty)
                              pw.Text(
                                'Site web : ${schoolInfo.website}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                            if ((schoolInfo.telephone ?? '').isNotEmpty)
                              pw.Text(
                                'Téléphone : ${schoolInfo.telephone}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Année scolaire',
                      style: pw.TextStyle(
                        font: times,
                        fontSize: 10,
                        color: primary,
                      ),
                    ),
                    pw.Text(
                      academicYear,
                      style: pw.TextStyle(
                        font: timesBold,
                        fontSize: 12,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Title centré
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  font: timesBold,
                  fontSize: 24,
                  color: accent,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 16),

            // Tableau du personnel avec design amélioré
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Table(
                border: pw.TableBorder.all(color: light, width: 1.2),
                columnWidths: {
                  0: const pw.FixedColumnWidth(80), // Photo
                  1: const pw.FlexColumnWidth(2), // Nom
                  2: const pw.FlexColumnWidth(1.5), // Poste
                  3: const pw.FlexColumnWidth(1.5), // Contact
                  4: const pw.FlexColumnWidth(1), // Statut
                },
                children: [
                  // Headers
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: accent),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Photo',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Nom',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Poste',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Contact',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Statut',
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Data rows
                  ...staffList.map(
                    (staff) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Container(
                            width: 40,
                            height: 40,
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey200,
                              borderRadius: pw.BorderRadius.circular(20),
                            ),
                            child:
                                staff.photoPath != null &&
                                    staff.photoPath!.isNotEmpty
                                ? pw.Image(
                                    pw.MemoryImage(
                                      File(staff.photoPath!).readAsBytesSync(),
                                    ),
                                    fit: pw.BoxFit.cover,
                                  )
                                : pw.Center(
                                    child: pw.Text(
                                      _getInitials(staff.name),
                                      style: pw.TextStyle(
                                        font: timesBold,
                                        fontSize: 10,
                                        color: PdfColors.grey600,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                staff.name,
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 9,
                                ),
                              ),
                              if (staff.firstName != null &&
                                  staff.firstName!.isNotEmpty)
                                pw.Text(
                                  'Prénom: ${staff.firstName}',
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 7,
                                    color: PdfColors.grey600,
                                  ),
                                ),
                              if (staff.lastName != null &&
                                  staff.lastName!.isNotEmpty)
                                pw.Text(
                                  'Nom: ${staff.lastName}',
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 7,
                                    color: PdfColors.grey600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                staff.typeRole,
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 8,
                                ),
                              ),
                              pw.Text(
                                staff.role,
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 7,
                                  color: PdfColors.grey600,
                                ),
                              ),
                              if (staff.department.isNotEmpty)
                                pw.Text(
                                  staff.department,
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 7,
                                    color: PdfColors.grey600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                staff.phone,
                                style: pw.TextStyle(font: times, fontSize: 8),
                              ),
                              pw.Text(
                                staff.email,
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 7,
                                  color: PdfColors.grey600,
                                ),
                              ),
                              if (staff.address != null &&
                                  staff.address!.isNotEmpty)
                                pw.Text(
                                  staff.address!,
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 6,
                                    color: PdfColors.grey600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: pw.BoxDecoration(
                              color: _getStatusColor(staff.status),
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Text(
                              staff.status,
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 7,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Informations détaillées pour chaque membre du personnel
            ...staffList.map(
              (staff) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 16),
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: light, width: 1),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Détails - ${staff.name}',
                      style: pw.TextStyle(
                        font: timesBold,
                        fontSize: 16,
                        color: accent,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Table(
                      border: pw.TableBorder.all(color: light, width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(1.2),
                        1: const pw.FlexColumnWidth(2),
                      },
                      children: [
                        _buildInfoTableRow(
                          'Date d\'embauche',
                          DateFormat('dd/MM/yyyy').format(staff.hireDate),
                          times,
                          timesBold,
                        ),
                        if (staff.birthDate != null)
                          _buildInfoTableRow(
                            'Date de naissance',
                            DateFormat('dd/MM/yyyy').format(staff.birthDate!),
                            times,
                            timesBold,
                          ),
                        if (staff.gender != null)
                          _buildInfoTableRow(
                            'Sexe',
                            staff.gender!,
                            times,
                            timesBold,
                          ),
                        if (staff.nationality != null)
                          _buildInfoTableRow(
                            'Nationalité',
                            staff.nationality!,
                            times,
                            timesBold,
                          ),
                        if (staff.matricule != null)
                          _buildInfoTableRow(
                            'Matricule',
                            staff.matricule!,
                            times,
                            timesBold,
                          ),
                        if (staff.region != null)
                          _buildInfoTableRow(
                            'Région',
                            staff.region!,
                            times,
                            timesBold,
                          ),
                        if (staff.levels != null && staff.levels!.isNotEmpty)
                          _buildInfoTableRow(
                            'Niveaux enseignés',
                            staff.levels!.join(', '),
                            times,
                            timesBold,
                          ),
                        if (staff.highestDegree != null)
                          _buildInfoTableRow(
                            'Diplôme',
                            staff.highestDegree!,
                            times,
                            timesBold,
                          ),
                        if (staff.experienceYears != null)
                          _buildInfoTableRow(
                            'Expérience',
                            '${staff.experienceYears} années',
                            times,
                            timesBold,
                          ),
                        if (staff.courses.isNotEmpty)
                          _buildInfoTableRow(
                            'Cours assignés',
                            staff.courses.join(', '),
                            times,
                            timesBold,
                          ),
                        if (staff.classes.isNotEmpty)
                          _buildInfoTableRow(
                            'Classes assignées',
                            staff.classes.join(', '),
                            times,
                            timesBold,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  /// Génère des cartes scolaires (cartes d'identité élèves) en PDF pour une liste d'élèves
  /// Disposition: grille sur A4 (compact: 3 colonnes x 4 lignes) avec logo, nom école, photo, infos clés
  static Future<List<int>> generateStudentIdCardsPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required List<Student> students,
    String? className,
    bool compact = true,
    bool includeQrCode = true,
    bool includeBarcode = true,
  }) async {
    return StudentIdCardTemplate.generate(
      schoolInfo: schoolInfo,
      academicYear: academicYear,
      students: students,
      className: className,
      compact: compact,
      includeQrCode: includeQrCode,
      includeBarcode: includeBarcode,
    );
    /*
    final pdf = pw.Document();

    // Typographies
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
    final adminTitle = isLycee ? 'Proviseur' : 'Directeur';
    final directorName = schoolInfo.director.trim();

    // Layout compact par défaut: 3 colonnes x 4 lignes (12 cartes / page).
    // Largeurs fixes (pas de Expanded) pour éviter des zones blanches selon certains viewers.
    const cardPadding = 8.0;
    // En compact (3 colonnes), on élargit légèrement pour laisser de la place au texte d'attestation.
    final cardWidth = compact ? 185.0 : 270.0;
    // En compact, on augmente la hauteur pour garantir l'affichage de l'attestation.
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

    // Fonction helper pour formater une date ISO en dd/MM/yyyy
    String formatDate(String isoDate) {
      if (isoDate.isEmpty) return '';
      try {
        final d = DateTime.parse(isoDate);
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      } catch (_) {
        return isoDate;
      }
    }

    String displayLastName(Student s) {
      final last = s.lastName.trim();
      if (last.isNotEmpty) return last;
      final full = s.name.trim();
      if (full.isNotEmpty) {
        final parts = full.split(RegExp(r'\s+'));
        if (parts.length > 1) return parts.last;
        return parts.first;
      }
      return '[Nom]';
    }

    String displayFirstName(Student s) {
      final first = s.firstName.trim();
      if (first.isNotEmpty) return first;
      final full = s.name.trim();
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

    // Prépare images logo et drapeau si disponibles
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
      return chunk.map((s) {
        // Debug: afficher les champs importants pour vérifier les données
        try {
          // Utiliser print pour que les logs apparaissent dans la console Flutter
          print(
            'PDF Student debug -> id=${s.id} firstName="${s.firstName}" lastName="${s.lastName}" name="${s.name}" class="${s.className}" photoPath="${s.photoPath}" matricule="${s.matricule}" guardianName="${s.guardianName}" guardianContact="${s.guardianContact}"',
          );
        } catch (_) {}
        final hasPhoto =
            (s.photoPath != null &&
            s.photoPath!.isNotEmpty &&
            File(s.photoPath!).existsSync());
        pw.MemoryImage? photo;
        if (hasPhoto) {
          photo = pw.MemoryImage(File(s.photoPath!).readAsBytesSync());
        }
        final birthPlace = (s.placeOfBirth ?? '').trim();
        final hasBirthPlace = birthPlace.isNotEmpty;
        final hasBirthDate = s.dateOfBirth.trim().isNotEmpty;
        final studentClassName = (className != null && className!.isNotEmpty)
            ? className!
            : displayValue(s.className, '[Classe]');
        final guardianPhone = s.guardianContact.trim();
        final guardianPhoneDisplay = guardianPhone.isNotEmpty
            ? guardianPhone
            : (compact ? '________________' : '________________________');
        final guardianLabel = displayValue(
          s.guardianName,
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

        final sexValue = switch (s.gender.trim().toUpperCase()) {
          'M' => compact ? 'M' : 'Masculin',
          'F' => compact ? 'F' : 'Féminin',
          _ => '',
        };

        final directorNameDisplay = directorName.isNotEmpty
            ? directorName
            : (compact ? '____________________' : '__________________________');
        final emergencyPhone = s.emergencyContact.trim();
        final emergencyPhoneDisplay = emergencyPhone.isNotEmpty
            ? emergencyPhone
            : (compact ? '________________' : '________________________');
        final attestation = compact
            ? null
            : 'Je soussigné(e) $adminCivility $adminTitle, atteste que les informations ci-dessus sont exactes.';

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
                          truncate(displayLastName(s), compact ? 22 : 40),
                        ),
                        infoLine(
                          'Prénom',
                          truncate(displayFirstName(s), compact ? 22 : 40),
                        ),
                        infoLine('Sexe', truncate(sexValue, compact ? 1 : 12)),
                        if (compact)
                          infoLine(
                            'Né(e)',
                            truncate(
                              [
                                if (hasBirthDate) formatDate(s.dateOfBirth),
                                if (hasBirthPlace) 'à $birthPlace',
                              ].join(' '),
                              28,
                            ),
                          )
                        else ...[
                          infoLine(
                            'Né(e) le',
                            hasBirthDate ? formatDate(s.dateOfBirth) : '',
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
                            (s.matricule ?? '').trim(),
                            compact ? 14 : 26,
                          ),
                        ),
                        infoLine(
                          compact ? 'Contact tuteur' : 'Contact du tuteur',
                          truncate(guardianPhoneDisplay, compact ? 16 : 32),
                        ),
                        // infoLine(
                        //   compact ? 'Urg.' : 'Urgence',
                        //   truncate(emergencyPhoneDisplay, compact ? 16 : 32),
                        // ),
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
              pw.Container(
                width: cardInnerWidth,
                height: compact ? 32 : null,
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 2,
                  horizontal: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: compact
                    ? pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Je soussigné(e) $adminCivility $adminTitle,',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: attestationFontSize,
                              color: PdfColors.grey700,
                            ),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                          pw.Text(
                            directorNameDisplay,
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: attestationFontSize,
                              color: PdfColors.grey700,
                            ),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                          pw.Text(
                            'atteste exactitude des informations.',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: attestationFontSize,
                              color: PdfColors.grey700,
                            ),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                        ],
                      )
                    : pw.Text(
                        directorName.isNotEmpty
                            ? '$attestation\n$directorName'
                            : attestation ?? '',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: attestationFontSize,
                          color: PdfColors.grey700,
                        ),
                        maxLines: 4,
                        overflow: pw.TextOverflow.clip,
                      ),
              ),
              if (!compact) ...[
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if ((schoolInfo.address ?? '').isNotEmpty)
                        pw.Text(
                          truncate(schoolInfo.address!, 70),
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 6.2,
                            color: PdfColors.grey700,
                          ),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                        ),
                      if ((schoolInfo.telephone ?? '').isNotEmpty)
                        pw.Text(
                          'Tél établissement: ${schoolInfo.telephone}',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 6.2,
                            color: PdfColors.grey700,
                          ),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList();
    }

    // Découper les élèves en pages.
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

      // Construire la grille
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
    */
  }

  static pw.TableRow _buildInfoTableRow(
    String label,
    String value,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(
            label,
            style: pw.TextStyle(font: fontBold, fontSize: 8),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 8)),
        ),
      ],
    );
  }

  static String _getInitials(String name) {
    final parts = name.trim().split(' ').where((n) => n.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String initials = parts.map((n) => n[0]).join();
    if (initials.length > 2) initials = initials.substring(0, 2);
    return initials.toUpperCase();
  }

  static PdfColor _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'actif':
        return PdfColors.green;
      case 'en congé':
        return PdfColors.orange;
      default:
        return PdfColors.red;
    }
  }

  static Future<List<int>> generateIndividualStaffPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required Staff staff,
    required String title,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      buildBackground:
          (schoolInfo.logoPath != null &&
              File(schoolInfo.logoPath!).existsSync())
          ? (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Opacity(
                opacity: 0.05,
                child: pw.Image(
                  pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                  fit: pw.BoxFit.cover,
                ),
              ),
            )
          : null,
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        build: (pw.Context context) {
          return [
            // En-tête administratif (Ministère / République / Devise + Inspection / Direction)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: ((schoolInfo.ministry ?? '').isNotEmpty)
                      ? pw.Text(
                          (schoolInfo.ministry ?? '').toUpperCase(),
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 10,
                            color: primary,
                          ),
                        )
                      : pw.SizedBox(),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        ((schoolInfo.republic ?? 'RÉPUBLIQUE').toUpperCase()),
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 10,
                          color: primary,
                        ),
                      ),
                      if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(
                            schoolInfo.republicMotto!,
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: primary,
                              fontStyle: pw.FontStyle.italic,
                            ),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(
                  child: ((schoolInfo.inspection ?? '').isNotEmpty)
                      ? pw.Text(
                          'Inspection: ${schoolInfo.inspection}',
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 9,
                            color: primary,
                          ),
                        )
                      : pw.SizedBox(),
                ),
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: ((schoolInfo.educationDirection ?? '').isNotEmpty)
                        ? pw.Text(
                            "Direction de l'enseignement: ${schoolInfo.educationDirection}",
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 9,
                              color: primary,
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            // Header avec logo et informations de l'école
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (schoolInfo.logoPath != null &&
                        File(schoolInfo.logoPath!).existsSync())
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 16),
                        child: pw.Image(
                          pw.MemoryImage(
                            File(schoolInfo.logoPath!).readAsBytesSync(),
                          ),
                          height: 60,
                          width: 60,
                        ),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo.name,
                          style: pw.TextStyle(
                            font: timesBold,
                            fontSize: 18,
                            color: primary,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          schoolInfo.address ?? '',
                          style: pw.TextStyle(
                            font: times,
                            fontSize: 10,
                            color: primary,
                          ),
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if ((schoolInfo.email ?? '').isNotEmpty)
                              pw.Text(
                                'Email : ${schoolInfo.email}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                            if ((schoolInfo.website ?? '').isNotEmpty)
                              pw.Text(
                                'Site web : ${schoolInfo.website}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                            if ((schoolInfo.telephone ?? '').isNotEmpty)
                              pw.Text(
                                'Téléphone : ${schoolInfo.telephone}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Année scolaire',
                      style: pw.TextStyle(
                        font: times,
                        fontSize: 10,
                        color: primary,
                      ),
                    ),
                    pw.Text(
                      academicYear,
                      style: pw.TextStyle(
                        font: timesBold,
                        fontSize: 12,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Title centré
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  font: timesBold,
                  fontSize: 24,
                  color: accent,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 24),

            // Photo et informations principales centrées
            pw.Center(
              child: pw.Column(
                children: [
                  // Photo
                  pw.Container(
                    width: 150,
                    height: 150,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(75),
                      border: pw.Border.all(color: accent, width: 3),
                    ),
                    child:
                        staff.photoPath != null && staff.photoPath!.isNotEmpty
                        ? pw.Image(
                            pw.MemoryImage(
                              File(staff.photoPath!).readAsBytesSync(),
                            ),
                            fit: pw.BoxFit.cover,
                          )
                        : pw.Center(
                            child: pw.Text(
                              _getInitials(staff.name),
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 32,
                                color: PdfColors.grey600,
                              ),
                            ),
                          ),
                  ),
                  pw.SizedBox(height: 20),
                  // Informations principales
                  pw.Text(
                    staff.name,
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 28,
                      color: primary,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    staff.typeRole,
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 18,
                      color: accent,
                    ),
                  ),
                  pw.Text(
                    staff.role,
                    style: pw.TextStyle(
                      font: times,
                      fontSize: 16,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _getStatusColor(staff.status),
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Text(
                      staff.status,
                      style: pw.TextStyle(
                        font: timesBold,
                        fontSize: 12,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 32),

            // Informations détaillées avec design amélioré
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'Informations personnelles',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 18,
                      color: accent,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      _buildInfoTableRow(
                        'Nom complet',
                        staff.name,
                        times,
                        timesBold,
                      ),
                      if (staff.firstName != null &&
                          staff.firstName!.isNotEmpty)
                        _buildInfoTableRow(
                          'Prénoms',
                          staff.firstName!,
                          times,
                          timesBold,
                        ),
                      if (staff.lastName != null && staff.lastName!.isNotEmpty)
                        _buildInfoTableRow(
                          'Nom de famille',
                          staff.lastName!,
                          times,
                          timesBold,
                        ),
                      if (staff.gender != null)
                        _buildInfoTableRow(
                          'Sexe',
                          staff.gender!,
                          times,
                          timesBold,
                        ),
                      if (staff.birthDate != null)
                        _buildInfoTableRow(
                          'Date de naissance',
                          DateFormat('dd/MM/yyyy').format(staff.birthDate!),
                          times,
                          timesBold,
                        ),
                      if (staff.birthPlace != null)
                        _buildInfoTableRow(
                          'Lieu de naissance',
                          staff.birthPlace!,
                          times,
                          timesBold,
                        ),
                      if (staff.nationality != null)
                        _buildInfoTableRow(
                          'Nationalité',
                          staff.nationality!,
                          times,
                          timesBold,
                        ),
                      if (staff.address != null)
                        _buildInfoTableRow(
                          'Adresse',
                          staff.address!,
                          times,
                          timesBold,
                        ),
                      _buildInfoTableRow(
                        'Téléphone',
                        staff.phone,
                        times,
                        timesBold,
                      ),
                      _buildInfoTableRow(
                        'Email',
                        staff.email,
                        times,
                        timesBold,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Informations professionnelles
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'Informations professionnelles',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 18,
                      color: accent,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      _buildInfoTableRow(
                        'Poste',
                        staff.typeRole,
                        times,
                        timesBold,
                      ),
                      _buildInfoTableRow(
                        'Rôle détaillé',
                        staff.role,
                        times,
                        timesBold,
                      ),
                      if (staff.department.isNotEmpty)
                        _buildInfoTableRow(
                          'Département',
                          staff.department,
                          times,
                          timesBold,
                        ),
                      if (staff.region != null)
                        _buildInfoTableRow(
                          'Région',
                          staff.region!,
                          times,
                          timesBold,
                        ),
                      if (staff.levels != null && staff.levels!.isNotEmpty)
                        _buildInfoTableRow(
                          'Niveaux enseignés',
                          staff.levels!.join(', '),
                          times,
                          timesBold,
                        ),
                      if (staff.highestDegree != null)
                        _buildInfoTableRow(
                          'Diplôme',
                          staff.highestDegree!,
                          times,
                          timesBold,
                        ),
                      if (staff.specialty != null)
                        _buildInfoTableRow(
                          'Spécialité',
                          staff.specialty!,
                          times,
                          timesBold,
                        ),
                      if (staff.experienceYears != null)
                        _buildInfoTableRow(
                          'Expérience',
                          '${staff.experienceYears} années',
                          times,
                          timesBold,
                        ),
                      if (staff.previousInstitution != null)
                        _buildInfoTableRow(
                          'Ancienne école',
                          staff.previousInstitution!,
                          times,
                          timesBold,
                        ),
                      if (staff.qualifications.isNotEmpty)
                        _buildInfoTableRow(
                          'Qualifications',
                          staff.qualifications,
                          times,
                          timesBold,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Informations administratives
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'Informations administratives',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 18,
                      color: accent,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      if (staff.matricule != null)
                        _buildInfoTableRow(
                          'Matricule',
                          staff.matricule!,
                          times,
                          timesBold,
                        ),
                      if (staff.idNumber != null)
                        _buildInfoTableRow(
                          'CNI/Passeport',
                          staff.idNumber!,
                          times,
                          timesBold,
                        ),
                      if (staff.socialSecurityNumber != null)
                        _buildInfoTableRow(
                          'Sécurité sociale',
                          staff.socialSecurityNumber!,
                          times,
                          timesBold,
                        ),
                      if (staff.maritalStatus != null)
                        _buildInfoTableRow(
                          'Situation matrimoniale',
                          staff.maritalStatus!,
                          times,
                          timesBold,
                        ),
                      if (staff.numberOfChildren != null)
                        _buildInfoTableRow(
                          'Nombre d\'enfants',
                          staff.numberOfChildren.toString(),
                          times,
                          timesBold,
                        ),
                      _buildInfoTableRow(
                        'Statut',
                        staff.status,
                        times,
                        timesBold,
                      ),
                      if (staff.contractType != null)
                        _buildInfoTableRow(
                          'Type de contrat',
                          staff.contractType!,
                          times,
                          timesBold,
                        ),
                      _buildInfoTableRow(
                        'Date d\'embauche',
                        DateFormat('dd/MM/yyyy').format(staff.hireDate),
                        times,
                        timesBold,
                      ),
                      if (staff.baseSalary != null)
                        _buildInfoTableRow(
                          'Salaire de base',
                          '${staff.baseSalary} FCFA',
                          times,
                          timesBold,
                        ),
                      if (staff.weeklyHours != null)
                        _buildInfoTableRow(
                          'Heures hebdomadaires',
                          '${staff.weeklyHours} heures',
                          times,
                          timesBold,
                        ),
                      if (staff.supervisor != null)
                        _buildInfoTableRow(
                          'Responsable',
                          staff.supervisor!,
                          times,
                          timesBold,
                        ),
                      if (staff.retirementDate != null)
                        _buildInfoTableRow(
                          'Date de retraite',
                          DateFormat(
                            'dd/MM/yyyy',
                          ).format(staff.retirementDate!),
                          times,
                          timesBold,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Affectations
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'Affectations',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 18,
                      color: accent,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      if (staff.courses.isNotEmpty)
                        _buildInfoTableRow(
                          'Cours assignés',
                          staff.courses.join(', '),
                          times,
                          timesBold,
                        ),
                      if (staff.classes.isNotEmpty)
                        _buildInfoTableRow(
                          'Classes assignées',
                          staff.classes.join(', '),
                          times,
                          timesBold,
                        ),
                      if (staff.documents != null &&
                          staff.documents!.isNotEmpty)
                        _buildInfoTableRow(
                          'Documents',
                          staff.documents!.join(', '),
                          times,
                          timesBold,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF de la liste des matières avec leurs catégories
  static Future<List<int>> generateSubjectsPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required List<Course> courses,
    required List<Category> categories,
    required String title,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#4F46E5');
    final accent = PdfColor.fromHex('#8B5CF6');
    final light = PdfColor.fromHex('#E5E7EB');
    final lightBg = PdfColor.fromHex('#F9FAFB');

    final subjectsPageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      buildBackground: (context) {
        if (schoolInfo.logoPath != null &&
            File(schoolInfo.logoPath!).existsSync()) {
          return pw.Center(
            child: pw.Opacity(
              opacity: 0.06,
              child: pw.Image(
                pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                width: 400,
              ),
            ),
          );
        }
        return pw.SizedBox();
      },
    );
    pdf.addPage(
      pw.MultiPage(
        pageTheme: subjectsPageTheme,
        header: (context) {
          // En-tête de page léger (pas sur la 1ère page où un grand en-tête existe déjà)
          if (context.pageNumber == 1) return pw.SizedBox();
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: light, width: 0.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  schoolInfo.name,
                  style: pw.TextStyle(
                    font: timesBold,
                    fontSize: 10,
                    color: primary,
                  ),
                ),
                pw.Text(
                  '$title - $academicYear',
                  style: pw.TextStyle(
                    font: times,
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: light, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  DateFormat('dd/MM/yyyy').format(DateTime.now()),
                  style: pw.TextStyle(
                    font: times,
                    fontSize: 9,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} / ${context.pagesCount}',
                  style: pw.TextStyle(
                    font: times,
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // Contenu principal
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // En-tête administratif
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: ((schoolInfo.ministry ?? '').isNotEmpty)
                          ? pw.Text(
                              (schoolInfo.ministry ?? '').toUpperCase(),
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 10,
                                color: primary,
                              ),
                            )
                          : pw.SizedBox(),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            ((schoolInfo.republic ?? 'RÉPUBLIQUE')
                                .toUpperCase()),
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: 10,
                              color: primary,
                            ),
                          ),
                          if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 2),
                              child: pw.Text(
                                schoolInfo.republicMotto!,
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 9,
                                  color: primary,
                                  fontStyle: pw.FontStyle.italic,
                                ),
                                textAlign: pw.TextAlign.right,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: ((schoolInfo.inspection ?? '').isNotEmpty)
                          ? pw.Text(
                              'Inspection: ${schoolInfo.inspection}',
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 9,
                                color: primary,
                              ),
                            )
                          : pw.SizedBox(),
                    ),
                    pw.Expanded(
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child:
                            ((schoolInfo.educationDirection ?? '').isNotEmpty)
                            ? pw.Text(
                                "Direction de l'enseignement: ${schoolInfo.educationDirection}",
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 9,
                                  color: primary,
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                // En-tête centré (logo + nom + date)
                pw.Center(
                  child: pw.Column(
                    children: [
                      if (schoolInfo.logoPath != null &&
                          File(schoolInfo.logoPath!).existsSync())
                        pw.Container(
                          height: 46,
                          width: 46,
                          margin: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.Image(
                            pw.MemoryImage(
                              File(schoolInfo.logoPath!).readAsBytesSync(),
                            ),
                            fit: pw.BoxFit.contain,
                          ),
                        ),
                      pw.Text(
                        schoolInfo.name.toUpperCase(),
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 14,
                          color: primary,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Année académique: $academicYear  -  Généré le: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                        style: pw.TextStyle(
                          font: times,
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        title,
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 16,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 20),

                // Statistiques générales
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: lightBg,
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(color: light, width: 1),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Column(
                        children: [
                          pw.Text(
                            '${courses.length}',
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: 24,
                              color: primary,
                            ),
                          ),
                          pw.Text(
                            'Matières',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 12,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        children: [
                          pw.Text(
                            '${categories.length}',
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: 24,
                              color: accent,
                            ),
                          ),
                          pw.Text(
                            'Catégories',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 12,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        children: [
                          pw.Text(
                            '${courses.where((c) => c.categoryId != null).length}',
                            style: pw.TextStyle(
                              font: timesBold,
                              fontSize: 24,
                              color: PdfColor.fromHex('#10B981'),
                            ),
                          ),
                          pw.Text(
                            'Classées',
                            style: pw.TextStyle(
                              font: times,
                              fontSize: 12,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 12),
                // Sommaire des catégories
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(color: light, width: 1),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Sommaire des catégories',
                        style: pw.TextStyle(
                          font: timesBold,
                          fontSize: 12,
                          color: primary,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ...categories.map((cat) {
                            final color = PdfColor.fromHex(
                              cat.color.replaceFirst('#', ''),
                            );
                            final count = courses
                                .where((c) => c.categoryId == cat.id)
                                .length;
                            return pw.Link(
                              destination: 'cat_${cat.id}',
                              child: pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.white,
                                  borderRadius: pw.BorderRadius.circular(20),
                                  border: pw.Border.all(color: color, width: 1),
                                ),
                                child: pw.Row(
                                  children: [
                                    pw.Container(
                                      width: 8,
                                      height: 8,
                                      decoration: pw.BoxDecoration(
                                        color: color,
                                        borderRadius: pw.BorderRadius.circular(
                                          4,
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(width: 6),
                                    pw.Text(
                                      '${cat.name} ($count)',
                                      style: pw.TextStyle(
                                        font: times,
                                        fontSize: 10,
                                        color: PdfColors.grey800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                          if (courses
                              .where((c) => c.categoryId == null)
                              .isNotEmpty)
                            pw.Link(
                              destination: 'cat_uncat',
                              child: pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.white,
                                  borderRadius: pw.BorderRadius.circular(20),
                                  border: pw.Border.all(
                                    color: PdfColors.grey600,
                                    width: 1,
                                  ),
                                ),
                                child: pw.Row(
                                  children: [
                                    pw.Container(
                                      width: 8,
                                      height: 8,
                                      decoration: pw.BoxDecoration(
                                        color: PdfColors.grey600,
                                        borderRadius: pw.BorderRadius.circular(
                                          4,
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(width: 6),
                                    pw.Text(
                                      'Non classées (${courses.where((c) => c.categoryId == null).length})',
                                      style: pw.TextStyle(
                                        font: times,
                                        fontSize: 10,
                                        color: PdfColors.grey800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 16),

                // Liste des matières par catégorie
                ...categories.map((category) {
                  final categoryCourses = courses
                      .where((c) => c.categoryId == category.id)
                      .toList();
                  final categoryColor = PdfColor.fromHex(
                    category.color.replaceFirst('#', ''),
                  );

                  return pw.Anchor(
                    name: 'cat_${category.id}',
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 16),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // En-tête de catégorie
                          pw.Container(
                            padding: const pw.EdgeInsets.all(12),
                            decoration: pw.BoxDecoration(
                              color: categoryColor,
                              borderRadius: pw.BorderRadius.circular(8),
                            ),
                            child: pw.Row(
                              children: [
                                pw.Container(
                                  width: 20,
                                  height: 20,
                                  decoration: pw.BoxDecoration(
                                    color: PdfColors.white,
                                    borderRadius: pw.BorderRadius.circular(4),
                                  ),
                                  child: pw.Center(
                                    child: pw.Text(
                                      '${categoryCourses.length}',
                                      style: pw.TextStyle(
                                        font: timesBold,
                                        fontSize: 10,
                                        color: categoryColor,
                                      ),
                                    ),
                                  ),
                                ),
                                pw.SizedBox(width: 12),
                                pw.Expanded(
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        category.name,
                                        style: pw.TextStyle(
                                          font: timesBold,
                                          fontSize: 16,
                                          color: PdfColors.white,
                                        ),
                                      ),
                                      if (category.description != null &&
                                          category.description!.isNotEmpty)
                                        pw.Text(
                                          category.description!,
                                          style: pw.TextStyle(
                                            font: times,
                                            fontSize: 10,
                                            color: PdfColors.white,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          pw.SizedBox(height: 8),

                          // Liste des matières de cette catégorie
                          if (categoryCourses.isNotEmpty)
                            pw.Container(
                              decoration: pw.BoxDecoration(
                                color: PdfColors.white,
                                borderRadius: pw.BorderRadius.circular(8),
                                border: pw.Border.all(color: light, width: 1),
                              ),
                              child: pw.Table(
                                border: pw.TableBorder.all(
                                  color: light,
                                  width: 0.5,
                                ),
                                columnWidths: {
                                  0: const pw.FlexColumnWidth(1),
                                  1: const pw.FlexColumnWidth(3),
                                  2: const pw.FlexColumnWidth(2),
                                },
                                children: [
                                  // En-tête du tableau
                                  pw.TableRow(
                                    decoration: pw.BoxDecoration(
                                      color: lightBg,
                                    ),
                                    children: [
                                      pw.Padding(
                                        padding: const pw.EdgeInsets.all(8),
                                        child: pw.Text(
                                          'N°',
                                          style: pw.TextStyle(
                                            font: timesBold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                      pw.Padding(
                                        padding: const pw.EdgeInsets.all(8),
                                        child: pw.Text(
                                          'Matière',
                                          style: pw.TextStyle(
                                            font: timesBold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                      pw.Padding(
                                        padding: const pw.EdgeInsets.all(8),
                                        child: pw.Text(
                                          'Description',
                                          style: pw.TextStyle(
                                            font: timesBold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Données des matières
                                  ...categoryCourses.asMap().entries.map((
                                    entry,
                                  ) {
                                    final index = entry.key + 1;
                                    final course = entry.value;
                                    return pw.TableRow(
                                      children: [
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.all(8),
                                          child: pw.Text(
                                            '$index',
                                            style: pw.TextStyle(
                                              font: times,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.all(8),
                                          child: pw.Text(
                                            course.name,
                                            style: pw.TextStyle(
                                              font: timesBold,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.all(8),
                                          child: pw.Text(
                                            course.description ?? '-',
                                            style: pw.TextStyle(
                                              font: times,
                                              fontSize: 8,
                                              color: PdfColors.grey600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            )
                          else
                            pw.Container(
                              padding: const pw.EdgeInsets.all(16),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.grey50,
                                borderRadius: pw.BorderRadius.circular(8),
                                border: pw.Border.all(color: light, width: 1),
                              ),
                              child: pw.Text(
                                'Aucune matière dans cette catégorie',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: PdfColors.grey600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),

                // Matières non classées
                if (courses.where((c) => c.categoryId == null).isNotEmpty) ...[
                  pw.SizedBox(height: 20),
                  pw.Anchor(
                    name: 'cat_uncat',
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 16),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // En-tête pour les matières non classées
                          pw.Container(
                            padding: const pw.EdgeInsets.all(12),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey600,
                              borderRadius: pw.BorderRadius.circular(8),
                            ),
                            child: pw.Row(
                              children: [
                                pw.Container(
                                  width: 20,
                                  height: 20,
                                  decoration: pw.BoxDecoration(
                                    color: PdfColors.white,
                                    borderRadius: pw.BorderRadius.circular(4),
                                  ),
                                  child: pw.Center(
                                    child: pw.Text(
                                      '${courses.where((c) => c.categoryId == null).length}',
                                      style: pw.TextStyle(
                                        font: timesBold,
                                        fontSize: 10,
                                        color: PdfColors.grey600,
                                      ),
                                    ),
                                  ),
                                ),
                                pw.SizedBox(width: 12),
                                pw.Text(
                                  'Matières non classées',
                                  style: pw.TextStyle(
                                    font: timesBold,
                                    fontSize: 16,
                                    color: PdfColors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          pw.SizedBox(height: 8),

                          // Liste des matières non classées
                          pw.Container(
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(8),
                              border: pw.Border.all(color: light, width: 1),
                            ),
                            child: pw.Table(
                              border: pw.TableBorder.all(
                                color: light,
                                width: 0.5,
                              ),
                              columnWidths: {
                                0: const pw.FlexColumnWidth(1),
                                1: const pw.FlexColumnWidth(3),
                                2: const pw.FlexColumnWidth(2),
                              },
                              children: [
                                // En-tête du tableau
                                pw.TableRow(
                                  decoration: pw.BoxDecoration(color: lightBg),
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(8),
                                      child: pw.Text(
                                        'N°',
                                        style: pw.TextStyle(
                                          font: timesBold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(8),
                                      child: pw.Text(
                                        'Matière',
                                        style: pw.TextStyle(
                                          font: timesBold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(8),
                                      child: pw.Text(
                                        'Description',
                                        style: pw.TextStyle(
                                          font: timesBold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                // Données des matières non classées
                                ...courses
                                    .where((c) => c.categoryId == null)
                                    .toList()
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                      final index = entry.key + 1;
                                      final course = entry.value;
                                      return pw.TableRow(
                                        children: [
                                          pw.Padding(
                                            padding: const pw.EdgeInsets.all(8),
                                            child: pw.Text(
                                              '$index',
                                              style: pw.TextStyle(
                                                font: times,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ),
                                          pw.Padding(
                                            padding: const pw.EdgeInsets.all(8),
                                            child: pw.Text(
                                              course.name,
                                              style: pw.TextStyle(
                                                font: timesBold,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ),
                                          pw.Padding(
                                            padding: const pw.EdgeInsets.all(8),
                                            child: pw.Text(
                                              course.description ?? '-',
                                              style: pw.TextStyle(
                                                font: times,
                                                fontSize: 8,
                                                color: PdfColors.grey600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  static Future<List<int>> generateLibraryTicketPdf({
    required String batchId,
  }) async {
    _checkSafeMode();
    final fonts = await _loadPdfFonts();
    final schoolInfo = await loadSchoolInfo();
    final db = DatabaseService();
    final header = await db.getLibraryLoanBatchDetails(batchId);
    if (header == null) {
      throw Exception('Batch introuvable: $batchId');
    }
    final items = await db.getLibraryLoanBatchItems(batchId);

    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primaryColor = PdfColor.fromHex('#4F46E5');
    final secondaryColor = PdfColor.fromHex('#6B7280');
    final lightBgColor = PdfColor.fromHex('#F3F4F6');

    pw.MemoryImage? logoImage;
    try {
      final logoPath = schoolInfo.logoPath;
      if (logoPath != null && logoPath.trim().isNotEmpty) {
        final f = File(logoPath);
        if (f.existsSync()) {
          logoImage = pw.MemoryImage(f.readAsBytesSync());
        }
      }
    } catch (_) {}

    final studentName = (header['studentName'] as String?) ?? '';
    final studentClass = (header['studentClassName'] as String?) ?? '';
    final studentYear = (header['studentAcademicYear'] as String?) ?? '';
    final loanDate = DateTime.tryParse((header['loanDate'] as String?) ?? '');
    final dueDate = DateTime.tryParse((header['dueDate'] as String?) ?? '');
    final recordedBy = (header['recordedBy'] as String?) ?? '';

    final qrPayload = jsonEncode({
      'type': 'library_ticket',
      'school': schoolInfo.name,
      'batchId': batchId,
      'student': studentName,
      'class': studentClass,
      'year': studentYear,
      'responsable': recordedBy.trim(),
      'loanDate': header['loanDate'],
      'dueDate': header['dueDate'],
      'count': items.length,
      'books': items
          .map(
            (r) => {
              'id': r['bookId'],
              'title': r['bookTitle'],
              'author': r['bookAuthor'],
              'isbn': r['bookIsbn'],
            },
          )
          .toList(),
    });

    pw.Widget line() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Divider(color: PdfColors.grey400, thickness: 0.7),
    );

    pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              k,
              style: pw.TextStyle(
                font: times,
                fontSize: 9,
                color: secondaryColor,
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              v,
              style: pw.TextStyle(
                font: bold ? timesBold : times,
                fontSize: 9,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );

    final doc = pw.Document();
    final pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      210 * PdfPageFormat.mm,
      marginLeft: 6 * PdfPageFormat.mm,
      marginRight: 6 * PdfPageFormat.mm,
      marginTop: 6 * PdfPageFormat.mm,
      marginBottom: 6 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.7),
                ),
              ),
              child: pw.Column(
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 28,
                      height: 28,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(
                          color: PdfColors.grey300,
                          width: 0.7,
                        ),
                      ),
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.ClipRRect(
                        horizontalRadius: 4,
                        verticalRadius: 4,
                        child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                      ),
                    ),
                  if (logoImage != null) pw.SizedBox(height: 6),
                  pw.Text(
                    dashIfBlank(schoolInfo.name).toUpperCase(),
                    style: pw.TextStyle(font: timesBold, fontSize: 11),
                    textAlign: pw.TextAlign.center,
                  ),
                  if ((schoolInfo.motto ?? '').trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(
                        schoolInfo.motto!.trim(),
                        style: pw.TextStyle(
                          font: times,
                          fontSize: 8,
                          color: secondaryColor,
                          fontStyle: pw.FontStyle.italic,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  if ((schoolInfo.address).trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text(
                        schoolInfo.address.trim(),
                        style: pw.TextStyle(
                          font: times,
                          fontSize: 8.5,
                          color: secondaryColor,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  if ((schoolInfo.telephone ?? '').trim().isNotEmpty ||
                      (schoolInfo.email ?? '').trim().isNotEmpty ||
                      (schoolInfo.website ?? '').trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Wrap(
                        alignment: pw.WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          if ((schoolInfo.telephone ?? '').trim().isNotEmpty)
                            pw.Text(
                              'Tél: ${schoolInfo.telephone!.trim()}',
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 8,
                                color: secondaryColor,
                              ),
                            ),
                          if ((schoolInfo.email ?? '').trim().isNotEmpty)
                            pw.Text(
                              schoolInfo.email!.trim(),
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 8,
                                color: secondaryColor,
                              ),
                            ),
                          if ((schoolInfo.website ?? '').trim().isNotEmpty)
                            pw.Text(
                              schoolInfo.website!.trim(),
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 8,
                                color: secondaryColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              decoration: pw.BoxDecoration(
                color: lightBgColor,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'REÇU D\'EMPRUNT',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 11,
                      color: primaryColor,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    DateFormat(
                      'dd/MM/yyyy HH:mm',
                    ).format(loanDate ?? DateTime.now()),
                    style: pw.TextStyle(
                      font: times,
                      fontSize: 8.5,
                      color: secondaryColor,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'Détails',
                    style: pw.TextStyle(
                      font: timesBold,
                      fontSize: 10,
                      color: primaryColor,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  kv('Élève', dashIfBlank(studentName), bold: true),
                  kv('Classe', dashIfBlank(studentClass)),
                  kv('Année', dashIfBlank(studentYear)),
                  kv('Ticket N°:', batchId),
                  kv(
                    'Retour prévu',
                    dueDate == null
                        ? '-'
                        : DateFormat('dd/MM/yyyy').format(dueDate),
                    bold: true,
                  ),
                  kv('Responsable', dashIfBlank(recordedBy.trim())),
                ],
              ),
            ),
            line(),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: lightBgColor,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'Livres (${items.length})',
                    style: pw.TextStyle(font: timesBold, fontSize: 10.5),
                  ),
                  pw.SizedBox(height: 6),
                  ...items.asMap().entries.map((e) {
                    final i = e.key + 1;
                    final r = e.value;
                    final title = (r['bookTitle'] as String?) ?? '';
                    final author = (r['bookAuthor'] as String?) ?? '';
                    final isbn = (r['bookIsbn'] as String?) ?? '';
                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 6),
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(
                          color: PdfColors.grey300,
                          width: 0.7,
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '$i. ${dashIfBlank(title)}',
                            style: pw.TextStyle(font: timesBold, fontSize: 9.5),
                          ),
                          if (author.trim().isNotEmpty)
                            pw.Text(
                              author.trim(),
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 8.5,
                                color: secondaryColor,
                              ),
                            ),
                          if (isbn.trim().isNotEmpty)
                            pw.Text(
                              'ISBN: ${isbn.trim()}',
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 8.5,
                                color: secondaryColor,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            line(),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
                  borderRadius: pw.BorderRadius.circular(8),
                  color: PdfColors.white,
                ),
                child: pw.BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: qrPayload,
                  width: 62,
                  height: 62,
                  drawText: false,
                  color: PdfColors.black,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Signature / Cachet',
              style: pw.TextStyle(
                font: times,
                fontSize: 9,
                color: secondaryColor,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ];
        },
      ),
    );
    return doc.save();
  }

  static Future<List<int>> generateDisciplineDocumentPdf({
    required String documentTitle,
    required String academicYear,
    required String studentName,
    required String studentId,
    required String className,
    required DateTime eventDate,
    String? eventType,
    int? minutes,
    bool? justified,
    String? description,
    String? responsable,
    String? documentNumber,
  }) async {
    _checkSafeMode();
    await _loadPdfFonts();
    final schoolInfo = await loadSchoolInfo();

    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primaryColor = PdfColor.fromHex('#4F46E5');
    final secondaryColor = PdfColor.fromHex('#6B7280');
    final lightBgColor = PdfColor.fromHex('#F3F4F6');

    pw.MemoryImage? logoImage;
    try {
      final logoPath = schoolInfo.logoPath;
      if (logoPath != null && logoPath.trim().isNotEmpty) {
        final f = File(logoPath);
        if (f.existsSync()) {
          logoImage = pw.MemoryImage(f.readAsBytesSync());
        }
      }
    } catch (_) {}

    pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              k,
              style: pw.TextStyle(
                font: times,
                fontSize: 10,
                color: secondaryColor,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 8,
            child: pw.Text(
              v,
              style: pw.TextStyle(
                font: bold ? timesBold : times,
                fontSize: 10,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );

    String formatMinutes(int m) {
      final mm = m < 0 ? 0 : m;
      final h = mm ~/ 60;
      final r = mm % 60;
      return '${h}h${r.toString().padLeft(2, '0')}';
    }

    final doc = pw.Document();
    final printedAt = DateTime.now();
    final dateFr = DateFormat('dd/MM/yyyy');
    final dateTimeFr = DateFormat('dd/MM/yyyy HH:mm');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Stack(
            children: [
              if (logoImage != null)
                pw.Positioned.fill(
                  child: pw.Center(
                    child: pw.Opacity(
                      opacity: 0.05,
                      child: pw.Image(logoImage, width: 420),
                    ),
                  ),
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.only(bottom: 10),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColors.grey300,
                          width: 0.7,
                        ),
                      ),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoImage != null)
                          pw.Container(
                            width: 46,
                            height: 46,
                            decoration: pw.BoxDecoration(
                              borderRadius: pw.BorderRadius.circular(10),
                              border: pw.Border.all(
                                color: PdfColors.grey300,
                                width: 0.7,
                              ),
                            ),
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.ClipRRect(
                              horizontalRadius: 8,
                              verticalRadius: 8,
                              child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                            ),
                          ),
                        if (logoImage != null) pw.SizedBox(width: 12),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                dashIfBlank(schoolInfo.name).toUpperCase(),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 14,
                                ),
                              ),
                              if ((schoolInfo.motto ?? '').trim().isNotEmpty)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(top: 3),
                                  child: pw.Text(
                                    schoolInfo.motto!.trim(),
                                    style: pw.TextStyle(
                                      font: times,
                                      fontSize: 10,
                                      color: secondaryColor,
                                      fontStyle: pw.FontStyle.italic,
                                    ),
                                  ),
                                ),
                              pw.SizedBox(height: 3),
                              pw.Builder(
                                builder: (context) {
                                  final address = schoolInfo.address.trim();
                                  final tel = (schoolInfo.telephone ?? '')
                                      .trim();
                                  final email = (schoolInfo.email ?? '').trim();
                                  return pw.Text(
                                    [
                                      if (address.isNotEmpty) address,
                                      if (tel.isNotEmpty) 'Tél: $tel',
                                      if (email.isNotEmpty) 'Email: $email',
                                    ].join(' - '),
                                    style: pw.TextStyle(
                                      font: times,
                                      fontSize: 9,
                                      color: secondaryColor,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'Édité le',
                              style: pw.TextStyle(
                                font: times,
                                fontSize: 9,
                                color: secondaryColor,
                              ),
                            ),
                            pw.Text(
                              dateTimeFr.format(printedAt),
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 10,
                              ),
                            ),
                            if ((documentNumber ?? '').trim().isNotEmpty)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 4),
                                child: pw.Text(
                                  'N° ${documentNumber!.trim()}',
                                  style: pw.TextStyle(
                                    font: timesBold,
                                    fontSize: 10,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: pw.BoxDecoration(
                      color: primaryColor,
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Text(
                      documentTitle.toUpperCase(),
                      style: pw.TextStyle(
                        font: timesBold,
                        fontSize: 14,
                        color: PdfColors.white,
                        letterSpacing: 0.6,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  pw.SizedBox(height: 14),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: lightBgColor,
                      borderRadius: pw.BorderRadius.circular(12),
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.7,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Informations élève',
                          style: pw.TextStyle(font: timesBold, fontSize: 12),
                        ),
                        pw.SizedBox(height: 6),
                        kv('Nom', dashIfBlank(studentName), bold: true),
                        kv('Identifiant', dashIfBlank(studentId)),
                        kv('Classe', dashIfBlank(className)),
                        kv('Année académique', dashIfBlank(academicYear)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(12),
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.7,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Détails',
                          style: pw.TextStyle(font: timesBold, fontSize: 12),
                        ),
                        pw.SizedBox(height: 6),
                        kv('Date', dateFr.format(eventDate), bold: true),
                        if ((eventType ?? '').trim().isNotEmpty)
                          kv('Type', eventType!.trim()),
                        if (minutes != null && minutes! > 0)
                          kv('Durée', formatMinutes(minutes!)),
                        if (justified != null)
                          kv('Justifiée', justified! ? 'Oui' : 'Non'),
                        if ((description ?? '').trim().isNotEmpty)
                          kv('Motif / Description', description!.trim()),
                      ],
                    ),
                  ),
                  pw.Spacer(),
                  pw.Container(
                    padding: const pw.EdgeInsets.only(top: 12),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(
                          color: PdfColors.grey300,
                          width: 0.7,
                        ),
                      ),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Responsable',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: secondaryColor,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                dashIfBlank(responsable),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 16),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text(
                                'Signature / Cachet',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 10,
                                  color: secondaryColor,
                                ),
                              ),
                              pw.SizedBox(height: 22),
                              pw.Container(height: 1, color: PdfColors.grey500),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static Future<File> saveLibraryTicketPdf({required String batchId}) async {
    final bytes = await generateLibraryTicketPdf(batchId: batchId);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ticket_bibliotheque_$batchId.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
