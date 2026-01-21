#!/usr/bin/env python3
"""Script pour corriger les problèmes de duplication dans database_service.dart"""
import re

def fix_database_service():
    file_path = 'lib/services/database_service.dart'
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Fix 1: Corriger la requête SQL dupliquée (lignes 8040-8051)
    # ON cherche le pattern entre "final whereClause = parts.join" et "if (gradesRows.isEmpty)"
    pattern1 = r"(final whereClause = parts\.join\(' AND '\);)\s*\n\s*// 2\. Fetch live grades\s*\n\s*final gradesRows = await db\.rawQuery\('''\\n\s*SELECT g\.value.*?s\.className\s*\n\s*// 2\. Fetch live grades with gender and status\s*\n\s*final gradesRows = await db\.rawQuery\('''\\n\s*SELECT\s*g\.value.*?WHERE \$whereClause\s*\n\s*''', args\);"
    
    replacement1 = r"\1\n\n    // 2. Fetch live grades with gender and status\n    final gradesRows = await db.rawQuery('''\n      SELECT g.value, g.maxValue, g.coefficient, g.subject, g.subjectId, \n             s.id as studentId, s.firstName, s.lastName, s.className, s.gender, s.status\n      FROM grades g\n      JOIN students s ON g.studentId = s.id\n      WHERE $whereClause\n    ''', args);"
    
    content = re.sub(pattern1, replacement1, content, flags=re.DOTALL)
    
    # Fix 2: Supprimer return 'globalSuccessRate' dupliqué (ligne vers 8116-8121)
    pattern2 = r"// 4\. Global Success Rate.*?\n\s*final globalSuccessRate = studentsList\.isNotEmpty.*?\n\s*\? \(passingCount / studentsList\.length\) \* 100\s*\n\s*// 4\. Success / Failure Counts"
    replacement2 = "// 4. Success / Failure Counts"
    content = re.sub(pattern2, replacement2, content, flags=re.DOTALL)
    
    # Fix 3: Supprimer le return dupliqué (ligne vers 8262-8266)
    pattern3 = r"}\);\s*\n\s*return {\s*\n\s*'globalSuccessRate': globalSuccessRate,\s*\n\s*'topStudents': topStudents,\s*\n\s*'bottomStudents': bottomStudents,\s*\n\s*'subjectStats': subjectStats,\s*\n\s*// 7\. Compute Progression"
    replacement3 = "});\n\n    // 7. Compute Progression"
    content = re.sub(pattern3, replacement3, content, flags=re.DOTALL)
    
    # Fix 4: Supprimer le point-virgule en trop à la fin
    content = content.rstrip()
    if content.endswith('\n};'):
        content = content[:-2] + '\n}'
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("Fichier database_service.dart corrigé!")

if __name__ == '__main__':
    fix_database_service()
