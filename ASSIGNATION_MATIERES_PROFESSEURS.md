# Affectation professeurs ↔ matières ↔ classes

## Objectif
Mettre en place une affectation explicite "professeur + matière + classe" afin d'éviter les ambiguïtés
et s'aligner avec les pratiques courantes des logiciels scolaires.

## Constat actuel (résumé)
- Les professeurs ont une liste de matières (`staff.courses`).
- Les professeurs ont une liste de classes (`staff.classes`).
- Lors de la génération d'emploi du temps, l'algorithme choisit d'abord un professeur
  qui a **à la fois** la matière et la classe, sinon un professeur qui a seulement la matière.
- Conséquence : si plusieurs profs ont la même matière, le choix peut être non déterministe
  ou pas aligné avec l'organisation réelle.

## Cible fonctionnelle (logique standard)
- Une affectation explicite relie :
  - un professeur
  - une matière
  - une classe
  - une année académique
- Les emplois du temps et la saisie des notes s'appuient en priorité sur ces affectations.
- Les listes "matières" et "classes" côté professeur peuvent rester, mais deviennent des vues
  dérivées (ou optionnelles) pour faciliter le filtrage.

## Modèle de données proposé
Nouvelle table `teacher_assignments` (nom à valider) :

- `id` (TEXT, PK)
- `teacherId` (TEXT, FK -> staff.id)
- `courseId` (TEXT, FK -> courses.id)
- `className` (TEXT)
- `academicYear` (TEXT)
- `weeklyHours` (REAL, optionnel)
- `createdAt` / `updatedAt` (INTEGER, optionnel)

Index recommandé :
- Unique composite (`teacherId`, `courseId`, `className`, `academicYear`)

## Évolutions UI attendues
1) Écran Personnel (`staff_page.dart`)
- Remplacer le simple multi-select par une table ou un panneau d'assignations :
  - Choisir classe + matière + année
  - Afficher la liste des affectations existantes
  - Permettre suppression / édition

2) Écran Classe (`class_details_page.dart`)
- Pour chaque matière d'une classe, afficher/choisir l'enseignant affecté.
- Option de filtrer les enseignants par matière.

3) Emploi du temps (`timetable_page.dart`)
- Lors de la génération, sélectionner l'enseignant depuis `teacher_assignments`.
- Si aucune affectation, fallback optionnel (selon configuration) ou avertissement.

## Impact sur la génération d'emplois du temps
- La sélection d'enseignant se fait par jointure explicite :
  - matière de la classe → affectation → enseignant.
- Si plusieurs affectations identiques existent, privilégier la plus récente ou afficher un conflit.
- Éliminer la logique "prof au hasard qui enseigne la matière".

## Migration (recommandée)
- Créer `teacher_assignments`.
- Optionnel : migrer les affectations implicites actuelles :
  - Pour chaque professeur P
  - Pour chaque matière M dans `staff.courses`
  - Pour chaque classe C dans `staff.classes`
  - Créer une affectation P+M+C pour l'année académique courante
- Marquer ces affectations comme "auto" si besoin.

## Questions ouvertes
- Une matière peut-elle être enseignée par plusieurs professeurs dans la même classe ?
- Faut-il gérer des périodes/semestres différents par affectation ?
- Les affectations doivent-elles être obligatoires pour saisir les notes ?

## Prochaines étapes proposées
1) Valider le schéma de table et la stratégie de migration.
2) Ajouter les CRUD d'affectations dans `DatabaseService`.
3) Mettre à jour les écrans Personnel et Classe.
4) Ajuster la génération d'emploi du temps.
5) Ajouter tests unitaires pour les requêtes et règles d'affectation.
