# Handover Checklist - DevOps/Ops

Checklist courte pour transferer l'exploitation du backend.

## 1) Acces et secrets

- [ ] Acces VPS (SSH) transmis et teste
- [ ] Acces registry image Docker transmis
- [ ] Fichier `.env` prod renseigne (hors git)
- [ ] Secrets verifies: DB, JWT, CORS
- [ ] Procedure rotation secrets partagee

## 2) Infrastructure

- [ ] Domaine pointe vers VPS (`PUBLIC_API_HOST`)
- [ ] Caddy actif avec TLS valide
- [ ] API up via `docker compose ps`
- [ ] Health check OK: `GET /health`
- [ ] Firewall/ports verifies (22 restreint, 80/443 ouverts)

## 3) Base de donnees

- [ ] PostgreSQL accessible depuis VPS uniquement
- [ ] Sauvegardes automatiques actives
- [ ] Retention backup validee
- [ ] Test restauration effectue (au moins 1)

## 4) Securite applicative

- [ ] Comptes seed par defaut remplaces
- [ ] CORS limite aux vrais domaines
- [ ] Rate limit et bruteforce verifies
- [ ] Headers securite verifies
- [ ] Audit log consultable (`/api/platform/audit`)

## 5) Supervision

- [ ] Logs `api` et `caddy` consultables
- [ ] Alerting minimal configure (service down, erreurs 5xx)
- [ ] Runbook connu par l'astreinte (`backend/runbook.md`)

## 6) Validation fonctionnelle

- [ ] Login SuperAdmin OK
- [ ] Endpoint protege SuperAdmin OK
- [ ] CRUD tenants OK
- [ ] CRUD admins ecole OK
- [ ] Refresh/logout OK

## 7) Go-live

- [ ] Fenetre de mise en ligne validee
- [ ] Contact escalation defini
- [ ] Rollback plan confirme
- [ ] Statut final: **READY FOR PRODUCTION**
