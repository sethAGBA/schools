# Plan de connexion Flutter ↔ Backend .NET

> Dernière mise à jour : 04 Mai 2026

Ce document décrit l'état d'avancement de la connexion entre le client Flutter Desktop
et le backend .NET, et planifie les prochaines étapes module par module.

---

## ✅ État actuel — Ce qui est connecté

### Backend .NET (`backend/`)
| Module | État | Détail |
|---|---|---|
| Auth (JWT + refresh + RBAC) | ✅ Complet | Login, refresh token, logout |
| Tenancy (multitenant) | ✅ Complet | Isolation via `X-Tenant-Id` |
| Audit | ✅ Complet | Journal immuable des actions sensibles |
| Students (CRUD API) | ✅ Complet | Endpoints list, create, update, delete |
| Academics | 🔴 Squelette vide | Entités et controllers à implémenter |
| Finance | 🔴 Squelette vide | Entités et controllers à implémenter |
| Reporting | 🔴 Squelette vide | À implémenter |
| Documents | 🔴 Squelette vide | À implémenter |

### Flutter (`lib/`)
| Écran / Service | État | Détail |
|---|---|---|
| `ApiClient` | ✅ Complet | HTTP + refresh auto sur 401 + timeout 15s |
| `TokenStorageService` | ✅ Complet | Stockage local access/refresh token |
| `RemoteAuthService` | ✅ Complet | Login backend + fallback local |
| `RemoteStudentsService` | ✅ Complet | CRUD élèves via API |
| `StudentsSyncService` | ✅ Complet | API-first + offline fallback + pending_sync |
| `StudentsPage` | ✅ Complet | Chargement API + fallback SQLite |
| Import CSV/Excel élèves | ✅ Corrigé | Passe via `StudentsSyncService` |
| `GradesPage` (notes) | 🔴 SQLite direct | À connecter |
| `PaymentsPage` (paiements) | 🔴 SQLite direct | À connecter |
| `StaffPage` (personnel) | 🔴 SQLite direct | À connecter |
| `DisciplinePage` | 🔴 SQLite direct | À connecter |
| `TimetablePage` | 🔴 SQLite direct | À connecter |
| `SyncManager` global | 🔴 Absent | À créer |

---

## 🗺️ Priorités — Ordre d'implémentation

---

### 🔴 PRIORITÉ 1 — Backend : Module Academics

**Pourquoi en premier ?** Les notes et bulletins sont le cœur du logiciel.

**Travail backend :**
- Entité `ClassRoom` (id, tenant_id, name, academicYear, level, capacity)
- Entité `Subject` (id, tenant_id, name, coefficient, classRoomId)
- Entité `Grade` (id, tenant_id, studentId, subjectId, period, devoirNote, compositionNote, average, teacherComment, classAverage)
- Migrations EF Core + policies RLS PostgreSQL

**Endpoints à créer (`/api/classes`, `/api/subjects`, `/api/grades`) :**
```
GET    /api/classes                     → liste des classes (filtre année, niveau)
POST   /api/classes                     → créer une classe
PUT    /api/classes/{id}                → modifier une classe
DELETE /api/classes/{id}                → supprimer

GET    /api/subjects?classId=           → matières d'une classe
POST   /api/subjects                    → créer une matière

GET    /api/grades?studentId=&period=   → notes d'un élève
POST   /api/grades/bulk                 → import groupé (flux Excel)
PUT    /api/grades/{id}                 → modifier une note
```

---

### 🔴 PRIORITÉ 2 — Flutter : Connexion GradesPage → API

**Fichiers à créer :**
- `lib/services/api/remote_grades_service.dart`
  - `listGrades(studentId, period, classId)`
  - `bulkUpsertGrades(grades)`
- `lib/services/grades_sync_service.dart`
  - Même pattern que `StudentsSyncService` (API-first + offline fallback)

**Fichier à modifier :**
- `lib/screens/grades_page.dart`
  - `_loadData()` → essai API, fallback SQLite
  - Sauvegarde notes → `GradesSyncService.upsert()`
  - Import Excel → `GradesSyncService.bulkUpsert()`

---

### 🟠 PRIORITÉ 3 — Backend : Module Finance

**Entités :**
- `Payment` (id, tenant_id, studentId, amount, date, type, receiptNumber, status)
- `FeeSchedule` (grille tarifaire par niveau/année)
- Migrations EF + RLS

**Endpoints :**
```
GET    /api/payments?studentId=&classId=&year=  → liste des paiements
POST   /api/payments                             → enregistrer un paiement
GET    /api/payments/summary                     → rapport financier agrégé
GET    /api/payments/{id}/receipt                → reçu en JSON (pour PDF client)
```

---

### 🟠 PRIORITÉ 4 — Flutter : Connexion PaymentsPage → API

**Fichiers à créer :**
- `lib/services/api/remote_payments_service.dart`
- `lib/services/payments_sync_service.dart`

**Fichier à modifier :**
- `lib/screens/payments_page.dart`

---

### 🟡 PRIORITÉ 5 — Flutter : Modules restants

Même pattern pour chaque module :
1. Créer `lib/services/api/remote_[module]_service.dart`
2. Créer `lib/services/[module]_sync_service.dart`
3. Brancher l'écran Flutter

| Module | Écran Flutter | Endpoints backend |
|---|---|---|
| Personnel | `staff_page.dart` | `/api/staff` |
| Discipline | `discipline/` | `/api/discipline` |
| Emploi du temps | `timetable_page.dart` | `/api/timetable` |
| Bibliothèque | `library/` | `/api/library` |

---

### 🟢 PRIORITÉ 6 — SyncManager global

**Fichier à créer :** `lib/services/sync_manager.dart`

- Déclencher `syncPending()` pour **tous les modules** au démarrage si connecté
- Retry automatique toutes les 5 minutes si connexion disponible
- Badge dans la Sidebar : "N éléments en attente de sync"

**Fichier à modifier :** `lib/widgets/sidebar.dart`
- Afficher un indicateur visuel si `pendingSyncCount > 0`

---

### 🟢 PRIORITÉ 7 — Déploiement VPS Production

D'après `backend/handover-checklist.md`, tout reste à faire :

- [ ] VPS Linux (Ubuntu 24.04) configuré + SSH sécurisé
- [ ] DNS `api.<domaine>` → VPS
- [ ] Caddy TLS (Let's Encrypt) actif
- [ ] Docker Compose déployé (`deploy/`)
- [ ] PostgreSQL managé (backups automatiques chiffrés)
- [ ] Fichier `.env` prod renseigné (remplacer `ChangeMeNow123!`)
- [ ] CORS restreint aux vrais domaines
- [ ] Monitoring uptime + alerting (Uptime Kuma ou similaire)
- [ ] Package MSIX Windows signé + canal de mise à jour

---

## 🏗️ Pattern standard pour chaque nouveau module

Chaque connexion Flutter → API suit ce schéma :

```
Écran Flutter (_loadData)
    │
    ├─ TokenStorage.getAccessToken() == null ?
    │       └─ → SQLite direct (mode déconnecté, label "Local")
    │
    └─ Token OK → Remote[Module]Service.list()
            ├─ Succès → afficher données API (label "Serveur")
            └─ Erreur  → SQLite fallback + snackbar avertissement

Écran Flutter (sauvegarde/modification)
    │
    └─ [Module]SyncService.upsert()
            ├─ API OK → SQLite cache mis à jour
            │           snackbar vert ✅
            └─ API KO → SQLite local + enqueuePendingSync()
                        snackbar orange ☁️
                            │
                        SyncManager.syncPending()
                        (au prochain démarrage / reconnexion)
```

---

## 📊 Tableau de bord — Avancement global

| Phase | Description | Avancement |
|---|---|---|
| Infra backend sécurisée | Auth, JWT, RBAC, Audit, Déploiement docs | ✅ 100% |
| Students connecté Flutter | API + offline + sync | ✅ 100% |
| Academics backend | Entités + migrations + controllers | 🔴 0% |
| GradesPage Flutter | Connexion API + sync service | 🔴 0% |
| Finance backend | Entités + migrations + controllers | 🔴 0% |
| PaymentsPage Flutter | Connexion API + sync service | 🔴 0% |
| Modules restants Flutter | Staff, Discipline, Timetable | 🔴 0% |
| SyncManager global | Badge + retry auto | 🔴 0% |
| Déploiement VPS | Prod en ligne | 🔴 0% |

---

*Document de suivi — à mettre à jour au fur et à mesure de l'avancement.*
