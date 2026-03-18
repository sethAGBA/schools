import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import 'dart:typed_data';

class StatisticsExcelService {
  Future<Uint8List> generateAcademicExcel({
    required String academicYear,
    required Map<String, dynamic> stats,
  }) async {
    final xls.Workbook workbook = xls.Workbook();
    final xls.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'Statistiques Académiques';

    int row = 1;

    // Header
    sheet
        .getRangeByIndex(row, 1)
        .setText('Rapport Statistique Académique - $academicYear');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    sheet.getRangeByIndex(row, 1).cellStyle.fontSize = 14;
    row += 2;

    // Vue d'ensemble
    sheet.getRangeByIndex(row, 1).setText('Vue d\'ensemble');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;
    sheet.getRangeByIndex(row, 1).setText('Moyenne Générale');
    sheet.getRangeByIndex(row, 2).setNumber((stats['globalAverage'] as num? ?? 0.0).toDouble());
    row++;
    sheet.getRangeByIndex(row, 1).setText('Taux de Réussite');
    sheet
        .getRangeByIndex(row, 2)
        .setText('${(stats['globalSuccessRate'] as num? ?? 0.0).toStringAsFixed(1)}%');
    row += 2;

    // Top Students
    sheet.getRangeByIndex(row, 1).setText('Top Élèves');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;
    final topStudents = stats['topStudents'] as List<dynamic>? ?? [];
    for (var s in topStudents) {
      sheet.getRangeByIndex(row, 1).setText(s['name']);
      sheet.getRangeByIndex(row, 2).setText(s['className']);
      sheet.getRangeByIndex(row, 3).setNumber((s['average'] as num).toDouble());
      row++;
    }
    row += 2;

    // Performance par Classe
    sheet.getRangeByIndex(row, 1).setText('Performance par Classe');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;
    final classStats = stats['classStats'] as Map? ?? {};
    sheet.getRangeByIndex(row, 1).setText('Classe');
    sheet.getRangeByIndex(row, 2).setText('Admis');
    sheet.getRangeByIndex(row, 3).setText('Total');
    sheet.getRangeByIndex(row, 4).setText('Taux');
    sheet.getRangeByIndex(row, 1, row, 4).cellStyle.bold = true;
    row++;

    classStats.forEach((className, data) {
      final d = data as Map;
      final success = d['success'] ?? 0;
      final total = d['total'] ?? 1;
      final rate = (success / total) * 100;
      sheet.getRangeByIndex(row, 1).setText(className);
      sheet.getRangeByIndex(row, 2).setNumber(success.toDouble());
      sheet.getRangeByIndex(row, 3).setNumber(total.toDouble());
      sheet.getRangeByIndex(row, 4).setText('${rate.toStringAsFixed(1)}%');
      row++;
    });

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> generateDisciplineExcel({
    required String academicYear,
    required Map<String, dynamic> stats,
  }) async {
    final xls.Workbook workbook = xls.Workbook();
    final xls.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'Statistiques Discipline';

    int row = 1;
    sheet
        .getRangeByIndex(row, 1)
        .setText('Rapport Disciplinaire - $academicYear');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    sheet.getRangeByIndex(row, 1).cellStyle.fontSize = 14;
    row += 2;

    // Top Absent Students
    sheet.getRangeByIndex(row, 1).setText('Élèves les plus absents');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;
    final topAbsent = stats['topAbsentStudents'] as List? ?? [];
    sheet.getRangeByIndex(row, 1).setText('Nom');
    sheet.getRangeByIndex(row, 2).setText('Classe');
    sheet.getRangeByIndex(row, 3).setText('Nombre d\'absences');
    sheet.getRangeByIndex(row, 1, row, 3).cellStyle.bold = true;
    row++;

    for (var s in topAbsent) {
      sheet.getRangeByIndex(row, 1).setText(s['name']);
      sheet.getRangeByIndex(row, 2).setText(s['className']);
      sheet.getRangeByIndex(row, 3).setNumber((s['count'] as num).toDouble());
      row++;
    }

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> generateDemographicExcel({
    required String academicYear,
    required Map<String, dynamic> stats,
  }) async {
    final xls.Workbook workbook = xls.Workbook();
    final xls.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'Statistiques Démographiques';

    int row = 1;
    sheet
        .getRangeByIndex(row, 1)
        .setText('Rapport Démographique - $academicYear');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    sheet.getRangeByIndex(row, 1).cellStyle.fontSize = 14;
    row += 2;

    // Gender Separation
    sheet.getRangeByIndex(row, 1).setText('Répartition par Genre');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;
    final gender = stats['gender'] as Map? ?? {};
    gender.forEach((key, value) {
      sheet.getRangeByIndex(row, 1).setText(key);
      sheet.getRangeByIndex(row, 2).setNumber((value as num).toDouble());
      row++;
    });
    row += 2;

    // Age Pyramid
    sheet.getRangeByIndex(row, 1).setText('Pyramide des Âges');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;
    final age = stats['age'] as Map? ?? {};
    age.forEach((key, value) {
      sheet.getRangeByIndex(row, 1).setText('$key ans');
      sheet.getRangeByIndex(row, 2).setNumber((value as num).toDouble());
      row++;
    });

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> generateFinanceExcel({
    required String academicYear,
    required Map<String, dynamic> stats,
  }) async {
    final xls.Workbook workbook = xls.Workbook();
    final xls.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'Statistiques Financières';

    int row = 1;
    sheet.getRangeByIndex(row, 1).setText('Rapport Financier - $academicYear');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    sheet.getRangeByIndex(row, 1).cellStyle.fontSize = 14;
    row += 2;

    // Overall
    sheet.getRangeByIndex(row, 1).setText('Résumé');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;
    sheet.getRangeByIndex(row, 1).setText('Total Revenus');
    sheet.getRangeByIndex(row, 2).setNumber((stats['totalIncome'] as num? ?? 0.0).toDouble());
    row++;
    sheet.getRangeByIndex(row, 1).setText('Total Dépenses');
    sheet.getRangeByIndex(row, 2).setNumber((stats['totalExpense'] as num? ?? 0.0).toDouble());
    row++;
    sheet.getRangeByIndex(row, 1).setText('Solde');
    sheet.getRangeByIndex(row, 2).setNumber((stats['balance'] as num? ?? 0.0).toDouble());
    row += 2;

    // Expenses by Category
    sheet.getRangeByIndex(row, 1).setText('Dépenses par Catégorie');
    sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
    row++;
    final expenseCat = stats['expenseByCategory'] as Map? ?? {};
    expenseCat.forEach((key, value) {
      sheet.getRangeByIndex(row, 1).setText(key);
      sheet.getRangeByIndex(row, 2).setNumber((value as num).toDouble());
      row++;
    });

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    return Uint8List.fromList(bytes);
  }
}
