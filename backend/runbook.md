# Runbook Exploitation - SchoolManager API

Ce runbook sert a gerer rapidement les incidents en production.

## 1) Verification rapide etat service

Depuis le VPS, dans `deploy/`:

```bash
docker compose ps
docker compose logs --tail=200 api
docker compose logs --tail=200 caddy
```

Verifier la sante API:

```bash
curl -i https://$PUBLIC_API_HOST/health
```

Resultat attendu:

- HTTP 200
- body simple de health check

## 2) API indisponible (HTTP 5xx / timeout)

1. Verifier si le conteneur `api` est up:
   - `docker compose ps`
2. Redemarrer l'API:
   - `docker compose restart api`
3. Si echec, reconstruire et relancer:
   - `docker compose pull`
   - `docker compose up -d`
4. Re-verifier `/health`.

## 3) Erreur base PostgreSQL

Symptomes frequents:

- erreurs de connexion dans logs (`Npgsql`, `timeout`, `authentication failed`)
- health KO

Checklist:

1. Verifier `POSTGRES_CONNECTION_STRING` dans `.env`.
2. Verifier acces reseau VPS -> PostgreSQL (security group / firewall).
3. Verifier credentials DB.
4. Verifier quota/stockage de la base.

Si credentials changes:

- Mettre a jour `.env`
- `docker compose up -d`

## 4) Probleme migration EF

L'API applique les migrations au demarrage.

Si migration casse le demarrage:

1. Lire logs `api` pour identifier la migration en faute.
2. Revenir a l'image precedente stable (rollback applicatif).
3. Corriger migration en dev, tester, redeployer.

Commandes utiles en local:

```powershell
dotnet ef migrations list --project src/SchoolManager.Api/SchoolManager.Api.csproj --startup-project src/SchoolManager.Api/SchoolManager.Api.csproj
dotnet ef database update NomMigrationPrecedente --project src/SchoolManager.Api/SchoolManager.Api.csproj --startup-project src/SchoolManager.Api/SchoolManager.Api.csproj
```

## 5) Rotation secrets (JWT / mots de passe)

Secrets concernes:

- `JWT_SIGNING_KEY`
- credentials DB
- comptes seed si utilises

Procedure:

1. Generer nouveaux secrets forts.
2. Mettre a jour `.env`.
3. Redemarrer API: `docker compose up -d`.
4. Verifier login et endpoints proteges.

Note:

- Changer `JWT_SIGNING_KEY` invalide les tokens existants (relogin requis).

## 6) Incident securite (suspicion acces non autorise)

1. Isoler:
   - restreindre temporairement acces reseau (WAF/firewall)
2. Investiguer:
   - consulter logs Caddy + API
   - verifier `/api/platform/audit` (actions sensibles)
3. Contenir:
   - desactiver comptes suspects
   - rotation `JWT_SIGNING_KEY`
4. Eradiquer:
   - corriger la faille
   - redeployer
5. Recuperer:
   - tests smoke
   - monitoring renforce 24-48h

## 7) Verification post-incident

Tests minimaux:

1. `GET /health` -> 200
2. login SuperAdmin -> OK
3. endpoint protege SuperAdmin -> OK
4. CRUD tenant -> OK
5. audit log visible -> OK

## 8) Backup / restauration

Minimum recommande:

- backup quotidien PostgreSQL
- retention >= 14 jours
- test de restauration au moins 1 fois/mois

En cas de restauration:

1. Restaurer DB a point stable.
2. Redeployer image API compatible schema.
3. Verifier migrations/etat schema.
4. Executer tests post-incident.

## 9) Commandes utiles

```bash
docker compose ps
docker compose logs -f api
docker compose restart api
docker compose pull && docker compose up -d
```

## 10) Escalade

Escalader immediatement si:

- indisponibilite > 15 min
- perte de donnees
- suspicion compromission
- echec restauration backup
