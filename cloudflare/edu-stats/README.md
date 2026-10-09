# edu-stats

Worker Cloudflare de comptage anonyme des installations d'EduBar, servi sur `https://edu.mathys.cc`.

## Principe

- `POST /v1/installation` : le Worker tire un UUID v4 et le renvoie. Il ne garde que `sha256(id)` et le jour (Europe/Paris, sans heure).
- `POST /v1/signal` `{"id","version"}` : une ligne par jour et par installation (`presences`). Empreinte inconnue : 404, le client redemande un UUID.
- `GET /v1/stats` : agrégats, protégé par `Authorization: Bearer <EDU_STATS_TOKEN>`.
- Cron quotidien (03:17 UTC) : les présences de plus de 35 jours sont agrégées dans `jours_agreges` puis supprimées.

## Ce qui n'est jamais stocké ni journalisé

IP, User-Agent, pays, heure précise, en-têtes. `observability` est désactivé, pas de logpush, aucun `console.log`. L'IP sert uniquement de clé de limitation de débit (5 par 60 s sur `POST /v1/installation`, clé = SHA-256 de l'IP calculé en mémoire) via le binding `LIMITER`. Si ce binding est absent, la limite est simplement ignorée.

## Tests

```
node --test cloudflare/edu-stats/test/
```

D1 est simulé avec `node:sqlite` (Node 22+), sans dépendance.

## Déploiement

Voir `docs/deploiement.md`, section « Worker edu-stats ».
