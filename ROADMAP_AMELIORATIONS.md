# Feuille de route — Améliorations pour dépasser une app “pro”

Ce document liste ce qu’il reste à faire (priorisé) pour que l’app **school_manager** ait une qualité comparable aux meilleures apps du marché, voire supérieure.

## Objectifs produits
- **Rapide & fiable**: zéro crash, démarrage rapide, actions instantanées.
- **UX cohérente**: design system, comportements prévisibles, parcours courts.
- **Données sûres**: sauvegardes, audit, permissions, confidentialité.
- **Scalable**: code modulaire, tests, CI, release propre.

## P0 — À faire en priorité (impact fort / effort raisonnable)
### UX & cohérence visuelle
- [ ] Définir un **design system** (couleurs, tailles, espacements, boutons, champs, cartes) et l’appliquer partout.
- [ ] Unifier la navigation: titres, breadcrumbs, actions principales (FAB/boutons), retour, states vides.
- [ ] Standardiser les **snackbars / dialogs / loaders** (un seul style).
- [ ] Ajouter des **empty states** utiles (ex: “aucun élève” + bouton “ajouter”).

### Robustesse & qualité
- [ ] Activer une **politique d’erreurs**: capture centralisée + logs utiles (sans données sensibles).
- [ ] Corriger/éviter les “UI freeze”: opérations DB/PDF lourdes isolées + indicateurs de progression.
- [ ] Ajouter une page “**Santé du système**” (DB ok, chemins logo/photo valides, permissions fichiers).

### Structure du code
- [ ] Découper les “gros fichiers” en modules (notamment `lib/services/pdf_service.dart`).
- [ ] Introduire une architecture simple par features:
  - `lib/features/students/…`
  - `lib/features/payments/…`
  - `lib/features/reports/…`
- [ ] Clarifier la responsabilité: UI ↔ services ↔ DB (service = logique métier, pas de UI).

### Paramètres & sources de vérité
- [ ] Réconcilier **SharedPreferences vs DB**: définir une source de vérité claire (idéal: DB) et une stratégie de migration.
- [ ] Centraliser la lecture des settings dans un `SettingsService` (au lieu de lire partout).

## P1 — Qualité “pro” (tests, performance, automatisation)
### Tests
- [ ] Ajouter des tests unitaires pour les règles métier (totaux, seuils, décisions, exports).
- [ ] Ajouter des `testWidgets` pour 3 parcours critiques:
  - ajout élève → profil → paiement
  - génération PDF cartes scolaires
  - génération bulletin
- [ ] Mettre des données fixtures pour tests (students/classes/payments).

### Performance
- [ ] Index DB (si besoin) sur requêtes fréquentes (`students`, `payments`, `grades`).
- [ ] Caching léger des lectures répétées (ex: `SchoolInfo`, settings).
- [ ] Mesurer: temps de démarrage, temps export PDF, temps chargement listes (profiling).

### CI/CD
- [ ] Pipeline CI: `flutter analyze`, `flutter test`, build (web/apk) sur PR.
- [ ] Script “release checklist” + versioning.
- [ ] Générer automatiquement changelog + artifacts.

## P2 — Fonctionnalités différenciantes (surpasser)
### Expérience admin
- [ ] Mode multi-établissement / multi-base (switch rapide).
- [ ] Rôles & permissions plus fines (lecture/écriture/export/audit).
- [ ] Historique d’actions (audit) consultable + export.

### Exports “premium”
- [ ] Templates PDF configurables (logo, mise en page, langue, signatures).
- [ ] Génération par lots + zip + nommage standard.
- [ ] Previews (aperçu avant export) avec options (compact/grand, champs inclus).

### Données & sauvegardes
- [ ] Backup auto (local) + restauration guidée.
- [ ] Export CSV/Excel standardisé (schémas stables).
- [ ] Vérification d’intégrité DB + réparations simples.

### Accessibilité & internationalisation
- [ ] Audit accessibilité: contrastes, tailles, focus, labels, navigation clavier.
- [ ] I18n complète (arb) au lieu de chaînes dispersées.

## Dette technique constatée (à traiter au fil de l’eau)
- `lib/services/pdf_service.dart` est très volumineux → à scinder en sous-services (cartes, bulletins, reçus, fiches).
- Répétitions de logique “lycée/proviseur” → à centraliser (settings + util).
- Manipulation de chemins fichiers (photos/logo) à fiabiliser (validation + fallback).

## Définition de “Done” (qualité de livraison)
- [ ] `flutter analyze` sans erreurs.
- [ ] Tests verts + couverture raisonnable sur les règles critiques.
- [ ] Aucun écran sans état vide/erreur propre.
- [ ] Exports stables (PDF/Excel) sur Windows/macOS/Linux (si supportés).
- [ ] Documentation minimale: `README.md` (install/run), guide utilisateur, FAQ.

## Prochaine itération recommandée (1 semaine)
1) Scinder `PdfService` (cartes scolaires → service dédié + tests).
2) `SettingsService` (source de vérité + lecture unique).
3) Harmoniser UI (snackbar/dialog/loading) sur 3 écrans clés.

