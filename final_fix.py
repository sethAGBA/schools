#!/usr/bin/env python3
"""Script final pour corriger tous les problèmes de compilation."""
import re

# Fix database_service.dart - problème de requête SQL dupliquée
with open('lib/services/database_service.dart', 'r', encoding='utf-8') as f:
    db_content = f.read()

# Corriger la requête dupliquée autour de ligne 8040-8051
# Chercher le pattern où on a deux "final gradesRows = await db.rawQuery"
pattern = r"(final whereClause = parts\.join\(' AND '\);)\s*\n\s*// 2\. Fetch live grades\s*\n\s*final gradesRows = await db\.rawQuery\('''.*?s\.className.*?// 2\. Fetch live grades with gender and status\s*\n\s*final gradesRows = await db\.rawQuery\('''.*?WHERE \$whereClause\s*\n\s*''', args\);"

replacement = r"""\1

    // 2. Fetch live grades with gender and status
    final gradesRows = await db.rawQuery('''
      SELECT g.value, g.maxValue, g.coefficient, g.subject, g.subjectId, 
             s.id as studentId, s.firstName, s.lastName, s.className, s.gender, s.status
      FROM grades g
      JOIN students s ON g.studentId = s.id
      WHERE $whereClause
    ''', args);"""

db_content = re.sub(pattern, replacement, db_content, flags=re.DOTALL)

with open('lib/services/database_service.dart', 'w', encoding='utf-8') as f:
    f.write(db_content)

print("✓ Corrigé database_service.dart")

# Analyser rapidement pour voir tous les fichiers qui ont encore des problèmes de lint
print("\nRecherche des marqueurs de conflit restants...")
import os
import subprocess

result = subprocess.run(
   ['grep', '-r', '-n', "<<<<<<< HEAD", 'lib/', 'test/'],
    capture_output=True,
    text=True
)

if result.stdout:
    print("⚠ Marqueurs de conflit trouvés:")
    print(result.stdout)
else:
    print("✓ Aucun marqueur de conflit trouvé!")

print("\n✓ Script terminé!")
