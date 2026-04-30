# Déploiement (VPS + Docker + Caddy)

Ce dossier contient les fichiers de base pour déployer l'API (à venir) derrière Caddy avec TLS automatique.

## Pré-requis (VPS)
- Ubuntu 24.04 LTS
- Docker + Docker Compose
- Un domaine pointant vers le VPS (ex: `api.votredomaine.tld`)

## Fichiers
- `docker-compose.yml`: reverse proxy (Caddy) + API
- `Caddyfile`: TLS auto + reverse proxy vers l'API
- `.env.example`: variables d'environnement (à copier en `.env`)

## Mise en route (quand l'API existe)
1. Copier `.env.example` en `.env` et compléter les valeurs.
2. Lancer:

```bash
docker compose up -d
```

## Notes sécurité
- Ne jamais exposer Postgres publiquement.
- Restreindre SSH à ton IP.
- Stocker les secrets uniquement dans `.env` côté serveur (pas dans git).

