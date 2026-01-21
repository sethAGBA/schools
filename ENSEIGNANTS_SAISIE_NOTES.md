# Saisie des notes par enseignant (accès limité)

## Objectif
Permettre à chaque enseignant connecté de saisir/modifier les notes **uniquement** pour les **classes** et **matières** qui lui sont attribuées, tout en respectant le **verrouillage de période** déjà présent dans `GradesPage`.

## Principes
- Un enseignant se connecte via un compte `users` (session existante).
- Les droits sont définis par des **affectations** (enseignant → classe + année + matière).
- L’UI doit **masquer** ce qui n’est pas autorisé, mais surtout le backend doit **refuser** toute écriture non autorisée (la sécurité ne doit pas dépendre uniquement de l’UI).
- Si la période est verrouillée (workflow Brouillon/Soumis/Validé), aucune saisie n’est possible, même si l’enseignant est affecté.

## Modèle de données (minimal)
### Table `teacher_assignments`
But : exprimer “tel utilisateur peut agir sur telle matière dans telle classe, pour telle année”.

Champs proposés :
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `username` (TEXT, FK vers `users.username`)
- `className` (TEXT)
- `academicYear` (TEXT)
- `courseId` (TEXT, FK vers `courses.id`)
- `canView` (INTEGER 0/1, défaut 1)
- `canEdit` (INTEGER 0/1, défaut 1)
- `createdAt`, `updatedAt`, `updatedBy` (audit)

Contrainte recommandée :
- UNIQUE(`username`, `className`, `academicYear`, `courseId`)

Pourquoi `courseId` (et pas le nom matière) :
- Évite les ambiguïtés/accents et reste stable si la matière est renommée.
- Permet de s’aligner sur `grades.subjectId` (déjà présent dans le projet).

Extensions possibles (plus tard) :
- Affectation par `term` (Trimestre/Semestre)
- Affectation par niveau (héritage sur plusieurs classes)

## Permissions / Rôles
Créer un groupe/rôle “prof” (ou équivalent) avec permissions minimales :
- `grades.view_assigned` : voir uniquement ses classes/matières affectées
- `grades.edit_assigned` : saisir/modifier uniquement sur ses matières affectées
- (optionnel) `grades.export_assigned` : exporter uniquement ses données
- (admin/direction) `grades.view_all` / `grades.edit_all` : accès complet

Règle : admin/direction = full access, enseignant = strictement “assigned”.

## Règles d’accès (backend/service)
### Lecture (affichage)
Si l’utilisateur a `grades.view_assigned` :
- Liste des classes = uniquement les classes affectées (par année académique)
- Liste des matières = uniquement les `courseId` affectés pour la classe/année
- Données (notes, appréciations, etc.) = filtrées par `(className, academicYear, subjectId ∈ affectations)`

### Écriture (insert/update/delete)
Avant toute écriture (notes, appréciations, synthèse si concernée) :
- Vérifier le verrouillage de période : `!_isPeriodLocked()`
- Vérifier l’affectation : `canEdit=1` pour `(username, className, academicYear, subjectId)`
- Sinon : refuser l’opération (retour `false` / exception), même si l’UI a été contournée.

## UI (GradesPage)
Pour un enseignant connecté :
- Le filtre “Classe” ne propose que ses classes affectées.
- Les sections/onglets de matières ne montrent que ses matières affectées.
- Les actions admin (validation période, exports globaux, etc.) sont masquées/désactivées.
- Si aucune affectation : afficher un message “Aucune matière attribuée”.

## Écran d’administration des affectations
Emplacement recommandé :
- `UsersManagementPage` : action “Affectations” sur un utilisateur enseignant

Fonctionnalités :
- choisir Année / Classe
- ajouter/retirer des matières (idéalement multi-sélection + recherche)
- régler `canView` / `canEdit`
- journaliser l’action (audit)

## Liaison compte ↔ enseignant
Deux options :
- Option A (rapide) : enseignant = `users.username` (toutes les affectations référencent `username`)
- Option B (plus structuré) : ajouter `users.staffId` (FK vers `staff.id`) et lier RH ↔ compte

Recommandation : commencer par A, migrer vers B si besoin RH/traçabilité.

## Ordre d’implémentation (proposé)
1. Migration DB : créer `teacher_assignments`
2. `DatabaseService` : CRUD + `getAssignmentsForUser(year)` + `isTeacherAllowedToEdit(...)`
3. Permissions : ajouter groupe “prof”
4. `GradesPage` : filtrage UI selon affectations
5. Sécurité écriture : contrôles côté service/DB pour insert/update/delete
6. UI admin : écran “Affectations prof”
7. Tests : au moins sur les garde-fous d’écriture (non-assigné → refus)

