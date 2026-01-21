# Documents de discipline (justificatifs / billets / convocations)

Ce document décrit l’implémentation des « papiers » remis aux élèves/parents pour les **absences**, **retards** et **sanctions (exclusion, avertissement, etc.)**.

## Terminologie

- **Absence / retard** : *justificatif d’absence* / *justificatif de retard* (mot d’excuse, certificat médical si besoin).
- **Sanctions** : *avis de sanction* (ou *notification*), *billet d’exclusion* (si exclusion), *convocation des parents* (si nécessaire).

## Objectif

- Générer un **PDF imprimable** pour chaque événement (assiduité/sanction) quand l’utilisateur le souhaite.
- Permettre de **réimprimer** à tout moment depuis l’historique.
- Permettre de **sauvegarder** le document à l’emplacement choisi par l’utilisateur et **ouvrir** automatiquement le fichier après sauvegarde.
- Tracer l’action (audit/log) : qui a généré, quand, pour quel élève et événement.

## Types de documents à supporter

### Assiduité
- `absence_slip` : Justificatif d’absence
- `late_slip` : Justificatif de retard

### Discipline
- `sanction_notice` : Avis de sanction (avertissement, blâme, etc.)
- `exclusion_slip` : Billet d’exclusion (si type = exclusion)
- `parent_summons` : Convocation des parents (optionnel)

## Données source (événements)

L’application dispose déjà des tables :
- `attendance_events` : absence/retard (minutes, justified, reason, recordedBy, date, academicYear, className, studentId)
- `sanction_events` : avertissement/blâme/exclusion/autre (description, recordedBy, date, academicYear, className, studentId)

Les documents doivent référencer **un événement existant** (clé étrangère logique via id/type).

## Modèle de stockage recommandé (DB)

Créer une table dédiée :

`discipline_documents`
- `id TEXT PRIMARY KEY` (UUID)
- `academicYear TEXT NOT NULL`
- `studentId TEXT NOT NULL`
- `className TEXT NOT NULL`
- `eventKind TEXT NOT NULL` (`attendance` | `sanction`)
- `eventId INTEGER NOT NULL` (id dans `attendance_events` ou `sanction_events`)
- `documentType TEXT NOT NULL` (ex: `absence_slip`, `exclusion_slip`)
- `documentNumber TEXT` (numéro lisible, ex: `DIS-2025-000123`)
- `filePath TEXT NOT NULL` (chemin du PDF sauvegardé)
- `generatedBy TEXT` (nom utilisateur)
- `generatedAt TEXT NOT NULL`
- `notes TEXT`

Contraintes / index :
- index sur `(academicYear, studentId, generatedAt)`
- index sur `(eventKind, eventId)`

Remarque : SQLite ne permet pas une FK propre vers 2 tables différentes. On garde `eventKind + eventId` et on valide côté code.

## Génération PDF (inspiration : ticket de paiement / ticket bibliothèque)

### Contenu minimal commun
- En-tête harmonisé (même style que paiement) :
  - Nom établissement
  - Contacts/adresse (si dispo)
  - Date/heure d’édition
- Bloc élève :
  - Nom complet, ID, classe, année académique
- Bloc document :
  - Titre (ex: `JUSTIFICATIF D’ABSENCE`, `BILLET D’EXCLUSION`)
  - Numéro de document
  - Date de l’événement
  - Motif / description
  - Statut (justifiée/non justifiée) si assiduité
  - Durée (minutes/heures) si retard/absence
- Signatures :
  - Responsable (generatedBy)
  - Emplacement “Signature parent” si convocation/avis

### Service
Ajouter dans `PdfService` (ou un service dédié) :
- `Future<Uint8List> generateDisciplineDocumentPdf({...})`

Inclure logs :
- `flutter: [Discipline] Document: generate type=... event=... student=...`
- `flutter: [Discipline] Document: save path=... bytes=...`

## Flux UI

### 1) À la création d’un événement
Dans la boîte de dialogue “Ajouter absence/retard” et “Sanction/Avertissement” :
- Ajouter un switch/checkbox : `Générer un document (PDF)`
- Pour assiduité :
  - si `absence` → `absence_slip`
  - si `retard` → `late_slip`
- Pour sanctions :
  - si `exclusion` → proposer `exclusion_slip` (et éventuellement `parent_summons`)
  - sinon → `sanction_notice`

Si coché :
1. Enregistrer l’événement en base
2. Générer le PDF
3. Demander à l’utilisateur où sauvegarder (`FilePicker.platform.getDirectoryPath()` ou `saveFile()`)
4. Sauvegarder le PDF
5. Ouvrir le fichier (`open_file`)
6. Enregistrer une ligne dans `discipline_documents`

### 2) Réimpression
Depuis l’onglet **Historique** (ou un bouton sur chaque ligne) :
- Action `Réimprimer` → régénère le PDF à partir de l’événement + infos actuelles établissement, puis demande un dossier, sauvegarde et ouvre.
- Option : si `filePath` existe et est accessible, proposer :
  - `Ouvrir le dernier document`
  - `Réimprimer (nouvelle sauvegarde)`

### 3) Gestion des documents
Optionnel : un onglet “Documents” filtrable (année/classe/élève/type) listant :
- type, numéro, date, responsable, actions (ouvrir / réimprimer / supprimer référence)

## Permissions & audit

Permissions recommandées :
- `view_discipline` (déjà)
- `print_discipline_documents` (nouvelle) : autorise génération/réimpression

Audit :
- `discipline_document_generated` avec metadata (type, studentId, eventKind/eventId, documentNumber)

## Gestion des erreurs

- Si l’utilisateur annule le choix de dossier : ne pas planter, afficher un message et ne pas créer l’entrée `discipline_documents` (ou créer avec `filePath` vide → déconseillé).
- Si la génération PDF échoue : afficher erreur et garder l’événement (déjà enregistré).
- Si la sauvegarde échoue : afficher erreur; proposer “Réessayer”.

## Conventions d’identification

Numéro de document lisible (exemple) :
- `DIS-${YYYY}-${000001}`

Stocker le compteur :
- table `counters` existante si disponible, sinon `discipline_document_counter` (année → dernier numéro).

## Checklist d’implémentation

- [ ] DB : table `discipline_documents` + index + migration
- [ ] Service DB : CRUD (insert, list, findByEvent, delete)
- [ ] Service PDF : génération selon `documentType`
- [ ] UI : options “Générer document” dans formulaires + bouton “Réimprimer” dans historique
- [ ] Logs + audit
- [ ] Tests widget : création événement + génération “mockée” (désactivable comme pour la bibliothèque)

