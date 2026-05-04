# Etat d'avancement du projet

Ce document resume ce qui a deja ete implemente et ce qu'il reste a realiser pour connecter completement le frontend Flutter desktop au backend .NET securise et multitenant.

## 1) Ce qui est fait

### Backend .NET

- Squelette backend modulaire cree dans `backend/`.
- Solution et modules en place (`Identity`, `Tenancy`, `Authorization`, `Students`, `Academics`, `Finance`, `Reporting`, `Audit`, `Documents`).
- `DbContext` multitenant avec conventions `tenant_id`.
- Migrations EF creees et appliquees au demarrage via `DbInitializer`.

### Securite et auth

- Auth JWT + refresh token rotatif.
- Endpoints auth:
  - `POST /api/auth/login`
  - `POST /api/auth/refresh`
  - `POST /api/auth/logout`
- Hash mots de passe en PBKDF2.
- Roles separes:
  - `SuperAdmin` (plateforme)
  - `Admin` (ecole)
  - `Teacher`, `Staff`
- RBAC/policies actives (`SuperAdminOnly`, `AdminOnly`, etc.).

### Multitenant et plateforme

- Resolution tenant via header `X-Tenant-Id`.
- Separation claire plateforme vs ecole.
- Endpoints plateforme en `SuperAdminOnly`:
  - gestion des tenants
  - gestion des admins d'ecole

### Audit et protection

- Audit log des actions sensibles (plateforme + auth).
- Protection bruteforce login (tenant + email + IP, lockout configurable).
- Rate limiting global + renforce sur auth.
- Headers HTTP de securite.
- CORS strict configurable.
- Forwarded headers configures pour reverse proxy (Caddy).

### Deploiement / exploitation

- Dossier `deploy/` pret (Compose + Caddy + `.env.example`).
- Documentation ops ajoutee:
  - `backend/README.md`
  - `backend/runbook.md`
  - `backend/handover-checklist.md`

### Frontend Flutter (debut integration API)

- Configuration API ajoutee (`API_BASE_URL`, `TENANT_ID`).
- Client HTTP de base ajoute.
- Stockage local des tokens ajoute.
- Service auth distant ajoute.
- Ecran login branche backend-first avec fallback local SQLite.
- Champ tenant ajoute + memorisation tenant/utilisateur.

## 2) Ce qu'il reste a faire

### A. Connexion Flutter -> API (priorite immediate)

- Migrer progressivement les ecrans metier vers l'API (au lieu SQLite direct).
- Ajouter gestion robuste des erreurs reseau (timeouts, offline, retry user-friendly).
- Ajouter refresh auto du token en cas de 401.

### B. Mode hybride SQLite (offline)

- Conserver SQLite comme cache local + file de synchronisation.
- Ajouter table `pending_sync` pour operations offline.
- Mettre en place moteur de synchro (FIFO + retries + idempotence).
- Definir strategie de conflits (`updated_at`/version, server wins par defaut).

### C. Modules metier backend

- Commencer par module `Students` (CRUD API complet + pagination/filtres).
- Enchainer avec `Academics`, `Finance`, `Reporting`.

### D. Validation production

- Remplacer tous les secrets et comptes seed par defaut.
- Finaliser CORS/domaines/proxy pour environnement reel.
- Activer monitoring + alerting en production.
- Tester restauration backup en condition reelle.

### E. Qualite / tests

- Tests integration backend (auth, RBAC, multitenant, anti-fuite).
- Tests E2E Flutter sur parcours login + parcours metier principal.

## 3) Prochaine etape recommandee

Demarrer un premier flux metier complet de bout en bout:

1. Backend: CRUD `Students` (API + validations + permissions).
2. Flutter: brancher l'ecran liste/creation eleves sur l'API.
3. SQLite: cache lecture + queue `pending_sync` pour creation offline.
4. Tests smoke: login -> liste eleves -> creation -> synchro.

Cela permettra de valider l'architecture complete (API securisee + client hybride online/offline).





cd C:\Users\LEGION\Desktop\Project\schools\backend

dotnet run --project src/SchoolManager.Api/SchoolManager.Api.csproj --urls "[http://localhost:5000](http://localhost:5000)"