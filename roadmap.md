# Roadmap securite + multitenant (desktop)

## Objectif
Mettre en place une architecture robuste pour `school_manager` avec:
- securite prioritaire (auth forte, audit, chiffrement, controle d'acces),
- multitenant strict (isolation complete des donnees par etablissement),
- application Flutter desktop qui consomme une API (pas d'acces direct DB).

## Architecture cible
- Client: Flutter desktop (Windows)
- API: Backend dedie (NestJS ou .NET)
- Base de donnees centrale: PostgreSQL
- Base locale desktop: SQLite (cache + mode offline + file de synchronisation)
- Auth: JWT court + refresh token rotatif + MFA
- Isolation multitenant: `tenant_id` + Row Level Security (RLS)

## Architecture modulaire cible (.NET)
Approche recommandee: **modular monolith** au depart, puis extraction possible en services independants plus tard (ex: module Django).

### Modules metier (v1)
- `Identity`: authentification, MFA, sessions, rotation refresh token.
- `Tenancy`: gestion tenants, rattachement utilisateurs, activation/suspension tenant.
- `Authorization`: roles, permissions fines, policies d'acces.
- `Students`: dossier eleve, informations administratives, etat scolaire.
- `Academics`: classes, matieres, notes, bulletins, calculs.
- `Finance`: frais de scolarite, echeances, paiements, recouvrements.
- `Reporting`: exports PDF/Excel, statistiques, tableaux de bord.
- `Audit`: journal immuable, traces securite, preuves de conformite.
- `Documents`: depot/consultation de fichiers avec controle d'acces.

### Contrats et frontieres inter-modules
- Communication interne via interfaces explicites (pas d'acces direct entre tables privees de modules).
- DTO et contrats API versionnes (`/api/v1`).
- Evenements de domaine pour decoupler les traitements transverses (audit, notifications, reporting).
- Validation des permissions au niveau endpoint **et** verification RLS en base.

### Multitenant par module
- Chaque aggregate metier porte `tenant_id`.
- Chaque requete applicative transporte un contexte tenant resolu des le middleware.
- RLS activee table par table avec politique par module.
- Tests automatises anti-fuite inter-tenant pour chaque module.

### Ordre d'implementation recommande
1. `Identity`
2. `Tenancy`
3. `Authorization`
4. `Audit` (branche tres tot pour tracer toutes actions)
5. `Students`
6. `Academics`
7. `Finance`
8. `Reporting`
9. `Documents`

### Strategie d'evolution vers Django (plus tard)
- Garder les modules faiblement couples et orienter l'integration via API/events.
- Candidats naturels a externaliser en Django: `Reporting` avance, portail web, workflows documentaires.
- Prerequis avant extraction:
  - contrats stables,
  - observabilite complete,
  - idempotence des traitements async,
  - tests de non-regression fonctionnelle et securite.

---

## Phase 0 - Cadrage (Semaine 1)
- Definir les tenants (ex: 1 ecole = 1 tenant).
- Definir les roles metier (Admin, Direction, Scolarite, Enseignant, Lecture).
- Cartographier les donnees sensibles (notes, infos eleves, paiements, documents).
- Definir les exigences conformite (journalisation, retention, export, suppression).
- Produire un document de menaces (menaces internes/externe, fuite inter-tenant).

**Livrables**
- Matrice roles/permissions.
- Liste des donnees sensibles.
- Politique securite v1.

## Phase 1 - Fondations backend (Semaines 2-3)
- Initialiser le backend API.
- Configurer secrets management (variables securisees, rotation planifiee).
- Mettre en place PostgreSQL (prod/staging/dev separes).
- Ajouter migration SQL versionnee.
- Definir convention `tenant_id` obligatoire sur toutes tables metier.

**Livrables**
- Repo backend operationnel.
- Pipeline migration DB.
- Environnements separes.

## Phase 2 - Modele multitenant DB (Semaines 3-4)
- Creer tables coeur:
  - `tenants`
  - `users`
  - `user_tenant_roles`
  - tables metier (`students`, `classes`, `grades`, etc.) avec `tenant_id`.
- Activer RLS sur toutes les tables metier.
- Ajouter policies SQL qui filtrent strictement par `tenant_id`.
- Interdire toute requete metier sans contexte tenant.
- Ajouter index composes (ex: `(tenant_id, created_at)`).

**Livrables**
- Schema SQL multitenant v1.
- Policies RLS actives et testees.

## Phase 3 - Authentification et sessions (Semaines 4-5)
- Login securise avec hash `Argon2id`.
- JWT access token (duree courte: 10-15 min).
- Refresh token rotatif avec invalidation immediate en cas d'abus.
- MFA (TOTP) obligatoire pour comptes admin/sensibles.
- Verrouillage progressif en cas d'echecs login + rate limiting.

**Livrables**
- Module auth complet.
- Gestion session/revocation.
- MFA active sur profils critiques.

## Phase 4 - Autorisation et controles d'acces (Semaine 5)
- Implementer RBAC serveur (par role et permission fine).
- Verification permission sur chaque endpoint.
- Verifier coherence API + RLS (defense en profondeur).
- Bloquer operations cross-tenant explicitement.

**Livrables**
- Middleware d'autorisation.
- Catalogue permissions.

## Phase 5 - Audit, observabilite, alerting (Semaines 6-7)
- Journal d'audit immuable:
  - qui, quoi, quand, tenant, ip, user-agent, resultat.
- Traces de securite: login, echec MFA, elevation role, export donnees.
- Dashboards de monitoring + alertes anomalies.
- Politique retention + archivage des logs.

**Livrables**
- Audit trail exploitable.
- Alerting securite operationnel.

## Phase 6 - Hardening plateforme (Semaine 7)
- TLS partout (API, reverse proxy).
- CORS strict et headers securite.
- Validation stricte des inputs + protection injection.
- Sauvegardes chiffrees + test de restauration periodique.
- Scans dependances + patch management.

**Livrables**
- Checklist hardening validee.
- Procedure de restore testee.

## Phase 7 - Integration Flutter desktop (Semaines 8-9)
- Retirer acces direct DB dans le client.
- Ajouter couche `ApiClient` + gestion token.
- Stockage local securise des secrets/session.
- Ecran de selection tenant si utilisateur multi-tenant.
- Activer mode hybride: API comme source de verite + SQLite local comme cache/offline.
- Ajouter une table locale `pending_sync` pour operations hors-ligne (insert/update/delete).
- Definir l'ordre de resynchronisation (FIFO), retries et idempotence.
- Limiter les donnees sensibles conservees en local (chiffrement local si necessaire).

**Livrables**
- Client desktop branche a l'API.
- Flux auth complet en desktop.
- Cache SQLite + file de synchro operationnels.

## Phase 8 - Migration SQLite -> PostgreSQL (Semaines 9-10)
- Inventorier tables SQLite existantes.
- Mapper vers schema multitenant cible.
- Script ETL de migration + validation integrite.
- Migration pilote sur un tenant de test.
- Plan rollback + plan de coupure.
- Basculer SQLite vers role **cache/sync** (et non source metier principale).
- Definir strategie de resolution de conflits (`updated_at`/version, regle serveur prioritaire par defaut).

**Livrables**
- Scripts migration versionnes.
- Rapport de reconciliation.
- Politique de synchro et conflits documentee.

## Phase 9 - Tests securite et validation finale (Semaines 10-11)
- Tests unitaires/integration sur auth, RBAC, RLS.
- Tests de non-regression multitenant (pas de fuite inter-tenant).
- Pentest applicatif (OWASP ASVS top controles).
- Revue des journaux, politiques retention, recovery drills.

**Livrables**
- Rapport de tests securite.
- Go-live checklist signee.

## Phase 10 - Go-live et exploitation (Semaine 12)
- Deploiement progressif (tenant par tenant si possible).
- Monitoring renforce 2-4 semaines.
- Rotation initiale des secrets post-mise en prod.
- Retro + backlog d'amelioration continue.

**Livrables**
- Mise en production stable.
- Plan d'amelioration continue.

---

## Exigences techniques minimales (non negociables)
- Aucune connexion DB directe depuis Flutter.
- `tenant_id` obligatoire sur toute donnee metier.
- RLS active sur chaque table metier.
- MFA pour roles privilegies.
- Audit complet sur operations sensibles.
- Backups chiffres + restauration testee.
- SQLite autorisee uniquement pour cache local et operations offline a resynchroniser.

## KPI de succes
- 0 fuite inter-tenant en tests de securite.
- 100% endpoints sensibles couverts par controle permission.
- 100% tables metier couvertes par RLS.
- 100% operations critiques journalisees.
- RPO/RTO atteints sur exercices de restauration.

## Strategie de deploiement (ou sera deploye le systeme)

### Composants et emplacement
- **Postes utilisateurs (Windows)**: deploiement de `school_manager.exe` sur chaque poste autorise.
- **Serveur API .NET**: hebergement sur VM ou conteneur (IIS/Kestrel + reverse proxy).
- **Base PostgreSQL**: instance dediee separee de l'API, acces reseau prive uniquement.
- **Stockage documents**: bucket prive (S3/Blob) ou serveur de fichiers securise.

### Option A - Cloud centralise (recommandee)
- Une plateforme centrale hebergee dans le cloud (Azure, AWS, OVH, Hetzner).
- Toutes les ecoles se connectent a la meme API multitenant.
- Avantages:
  - maintenance centralisee,
  - supervision simplifiee,
  - deploiements plus rapides,
  - meilleure reprise apres incident.

### Option B - On-premise par etablissement
- API + DB hebergees dans l'infrastructure locale de chaque ecole.
- Avantages:
  - autonomie locale,
  - fonctionnement possible avec internet instable.
- Contraintes:
  - maintenance plus lourde,
  - cout operationnel plus eleve,
  - niveau de securite variable selon les sites.

### Decision cible (v1)
- Prioriser **Option A: cloud centralise** pour la version initiale.
- Prevoir un mode de secours de connectivite cote desktop (file d'attente locale non sensible + resynchronisation).

### Exigences reseau et securite de deploiement
- API exposee uniquement en HTTPS (TLS 1.2+).
- Base PostgreSQL non exposee sur internet public.
- Segmentation reseau (subnets prives, security groups restrictifs).
- Sauvegardes chiffrees + tests de restauration periodiques.
- Journalisation centralisee + alerting securite.
- Rotation des secrets et certificats planifiee.

### Plan de deploiement pro (VPS + Docker + auto-update Windows)
Pile recommandee:
- **VPS Linux (Ubuntu 24.04)**: Docker + Compose
- **Reverse proxy**: Caddy (TLS auto via Let's Encrypt)
- **API**: conteneur .NET (Kestrel) derriere Caddy
- **PostgreSQL**: service managé (recommandé) avec allowlist IP (VPS uniquement)
- **Stockage documents**: objet (S3/B2/Wasabi) + policies par tenant
- **Auto-update Windows**: MSIX + App Installer (canal stable)

Checklist de mise en ligne:
- **DNS/Domaines**
  - `api.<domaine>` -> VPS (A/AAAA)
  - `updates.<domaine>` -> hebergement updates (VPS ou storage statique)
- **Reseau/Firewall VPS**
  - Ouvrir uniquement 80/443 (et SSH restreint a ton IP)
  - DB jamais exposee publiquement
- **Docker (prod)**
  - `caddy` + `api` via `docker-compose`
  - Variables d'environnement pour secrets (pas dans git)
  - Logs structurés + rotation
- **Base PostgreSQL (prod)**
  - Backups automatiques chiffrés
  - Test de restauration planifie
  - Migrations versionnees (run a chaque release)
- **CI/CD**
  - Build image API -> push registry -> deploy compose sur VPS
  - Strategie rollback (tag N-1) + health checks
  - Environnements: staging + prod
- **Observabilite**
  - Monitoring uptime + alerting (5xx, latence)
  - Centralisation logs (API + proxy) + audit trail
- **Auto-update Windows (MSIX)**
  - Generer package MSIX signe
  - Publier `.msix` + `.appinstaller` sur `updates.<domaine>`
  - Configurer verif updates periodique (App Installer)
  - Garder un canal staging pour tests (facultatif mais recommandé)

## Risques principaux
- Mauvaise propagation du contexte tenant dans l'API.
- Permissions trop larges au demarrage.
- Migration donnees avec incoherences historiques.
- Sous-estimation de la dette de securite desktop locale.

## Prochaines actions immediates (cette semaine)
1. Valider decision stack backend (NestJS ou .NET).
2. Ecrire schema SQL v1 avec `tenant_id` partout.
3. Prototyper auth + RBAC + RLS sur 2-3 tables metier.
4. Definir format unique des logs d'audit.
5. Planifier migration pilote depuis SQLite.
# Roadmap - Logiciel de Gestion d'École

Ce document suit l'évolution du projet et planifie les prochaines étapes de développement.

## ✅ Réalisé (Phase Initial & Authentification)
- [x] Structure de base du projet (Flutter/Dart).
- [x] Gestion de la base de données SQLite avec migrations.
- [x] Système d'authentification robuste (SHA-256 + Sel).
- [x] Authentification à deux facteurs (2FA/TOTP).
- [x] Module de gestion des élèves (Inscription, Profils).
- [x] Module de gestion des notes et bulletins (Brouillon, Verrouillage).
- [x] Gestion des types de notes (Devoir, Composition).
- [x] Import/Export Excel pour les notes.
- [x] Audit Trail (Journal d'audit pour les transactions).
- [x] Paramètres généraux de l'établissement.

## 🚀 En cours : Module Examens Blancs
- [ ] **Écran Dédié** : Créer `mock_exams_page.dart` pour la gestion isolée des sessions d'examens.
- [ ] **Navigation** : Ajouter une entrée "Examens Blancs" dans la Sidebar.
- [ ] **Saisie Groupée** : Interface optimisée pour la saisie massive des notes par session (Examen Blanc 1, 2, etc.).
- [ ] **Logique de Calcul** : Moyenne spécifique à l'examen blanc, calculée séparément du trimestre.
- [ ] **Exportation** : Génération de palmarès PDF/Excel dédiés, sans impact sur le bulletin standard.
- [ ] **Persistance** : Amélioration de la persistance des appréciations automatiques.

## 📅 Prochaines Étapes (Priorité Haute)
- [x] **Suivi de la Discipline** : Absences, retards, sanctions et avertissements.
- [x] **Gestion du Personnel** : Présences, absences, attribution des classes.
- [x] **Statistiques Avancées** : Tableaux de bord visuels, taux de réussite par matière.
- [x] **Paiements & Finances** : Suivi des frais de scolarité, alertes impayés, rapports financiers.

## 🛠️ Futur (Priorité Basse / Optionnel)
- [x] **Gestion de la Bibliothèque** : Emprunts, retours, inventaire.
- [x] **Gestion du Matériel** : Stock de fournitures scolaires.
- [x] **Réinscriptions** : Processus automatisé pour les années suivantes.

---
*Dernière mise à jour : 18 Avril 2026*
