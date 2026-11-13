# edu-stats

Worker Cloudflare de comptage anonyme des installations d'EduBar, servi sur `https://edu.mathys.cc`.

## Principe

- `POST /v1/installation` : le Worker tire un UUID v4 et le renvoie. Il ne garde que `sha256(id)` et le jour (Europe/Paris, sans heure).
- `POST /v1/signal` `{"id","version"}` : une ligne par jour et par installation (`presences`). Empreinte inconnue : 404, le client redemande un UUID.
- `GET /v1/stats` : agrégats, protégé par `Authorization: Bearer <EDU_STATS_TOKEN>`.
- Plafond : 500 créations d'installations par jour (Europe/Paris), compté dans D1, au-delà 429.
- Cron quotidien (03:17 UTC) : les présences de plus de 35 jours sont agrégées dans `jours_agreges` puis supprimées ; les installations sans présence depuis plus de 35 jours sont aussi purgées.

## Ce qui n'est jamais stocké ni journalisé

IP, User-Agent, pays, heure précise, en-têtes. `observability` est désactivé, pas de logpush, aucun `console.log`. L'IP n'est ni stockée ni journalisée : elle sert uniquement à calculer, en mémoire, la clé des limiteurs. Cette clé est l'empreinte SHA-256 de l'IPv4 (ou du préfixe /64 pour une IPv6), salée par le jour et par un secret existant, donc différente chaque jour. Deux limiteurs : `LIMITER` (5 par 60 s sur `POST /v1/installation`) et `LIMITER_SIGNAL` (30 par 60 s sur `POST /v1/signal`, avant tout accès à D1). Si un binding est absent, sa limite est simplement ignorée. Cloudflare voit l'IP comme pour toute requête.

## Tests

```
node --test cloudflare/edu-stats/test/
```

D1 est simulé avec `node:sqlite` (Node 22+), sans dépendance.

## Déploiement

Voir `docs/deploiement.md`, section « Worker edu-stats ».
