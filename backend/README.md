# SchoolManager Backend - Guide d'exploitation

Ce dossier contient l'API .NET (modulaire) du projet `school_manager`.

## 1) Prerequis

- .NET SDK 10+
- PostgreSQL 15+ (local ou managé)
- (Optionnel) Docker pour le deploiement VPS

## 2) Structure

- `SchoolManager.slnx` : solution backend
- `src/SchoolManager.Api` : API ASP.NET Core
- `src/SchoolManager.BuildingBlocks` : briques communes
- `src/Modules/*` : modules (Identity, Tenancy, Audit, ...)

## 3) Configuration (variables d'environnement)

La configuration suit le format .NET `Section__Key`.

Variables minimum en production:

- `Postgres__ConnectionString`
- `Jwt__Issuer`
- `Jwt__Audience`
- `Jwt__SigningKey`
- `Jwt__AccessTokenMinutes`
- `Cors__AllowedOrigins__0` (et suivants si plusieurs origines)

Variables utiles:

- `BruteForce__MaxFailedAttempts`
- `BruteForce__WindowMinutes`
- `BruteForce__LockoutMinutes`
- `RateLimit__GlobalPermitLimit`
- `RateLimit__GlobalWindowSeconds`
- `RateLimit__AuthPermitLimit`
- `RateLimit__AuthWindowSeconds`

Seed (a changer en dehors du dev):

- `Seed__PlatformTenantId`
- `Seed__SuperAdminEmail`
- `Seed__SuperAdminPassword`
- `Seed__SchoolTenantId`
- `Seed__SchoolAdminEmail`
- `Seed__SchoolAdminPassword`

## 4) Lancement local

Depuis `backend/`:

```powershell
dotnet restore SchoolManager.slnx
dotnet build SchoolManager.slnx
dotnet run --project src/SchoolManager.Api/SchoolManager.Api.csproj
```

Notes:

- Les migrations EF sont appliquees automatiquement au demarrage (`DbInitializer`).
- Le seed cree un tenant `platform` + `demo-school`, puis un `SuperAdmin` et un `Admin` par defaut.

## 5) Migrations EF

Creer une migration:

```powershell
dotnet ef migrations add NomMigration --project src/SchoolManager.Api/SchoolManager.Api.csproj --startup-project src/SchoolManager.Api/SchoolManager.Api.csproj --output-dir Data/Migrations
```

Appliquer manuellement (si besoin):

```powershell
dotnet ef database update --project src/SchoolManager.Api/SchoolManager.Api.csproj --startup-project src/SchoolManager.Api/SchoolManager.Api.csproj
```

## 6) Verification API rapide

Health:

```powershell
Invoke-RestMethod -Method GET -Uri "http://localhost:5000/health"
```

Login SuperAdmin:

```powershell
$headers = @{ "X-Tenant-Id" = "platform" }
$body = @{
  email = "owner@platform.local"
  password = "ChangeMeNow123!"
} | ConvertTo-Json

$login = Invoke-RestMethod -Method POST -Uri "http://localhost:5000/api/auth/login" -Headers $headers -ContentType "application/json" -Body $body
$login
```

Endpoint protege:

```powershell
$authHeaders = @{
  "X-Tenant-Id" = "platform"
  "Authorization" = "Bearer $($login.accessToken)"
}
Invoke-RestMethod -Method GET -Uri "http://localhost:5000/api/secure/super-admin" -Headers $authHeaders
```

## 7) Securite deja en place

- JWT + refresh token en rotation
- separation `SuperAdmin` (plateforme) / `Admin` (ecole)
- audit log (actions plateforme + auth)
- protection bruteforce login
- rate limiting global + auth
- headers HTTP de securite
- CORS strict configurable
- forwarded headers pour reverse proxy (Caddy)

## 8) Deploiement VPS

Les fichiers Docker/Caddy sont dans `../deploy/`.

Flux recommande:

1. Build/push de l'image API.
2. Copier `deploy/.env.example` vers `deploy/.env` et renseigner les secrets.
3. Lancer `docker compose up -d` dans `deploy/`.

## 9) Checklist pre-prod

- Remplacer tous les secrets par des valeurs fortes
- Changer les comptes seed par defaut
- Restreindre CORS aux vrais domaines
- Verifier TLS (certificat valide via Caddy)
- Verifier sauvegardes PostgreSQL
- Activer monitoring/alerting


dotnet run --project src/SchoolManager.Api/SchoolManager.Api.csproj --urls "http://localhost:5000"
