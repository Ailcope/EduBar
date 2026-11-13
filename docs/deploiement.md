# Déploiement

## Worker edu-stats

Comptage anonyme des installations d'EduBar. Code dans `cloudflare/edu-stats/`.

### Où

- Cloudflare, compte de Mathys (`account_id` dans `wrangler.toml`), Worker `edu-stats`.
- Domaine personnalisé `edu.mathys.cc` (zone mathys.cc), `workers_dev = false`.
- Base D1 `edu-stats` (id `bddfcf9b-8158-40c8-8b7c-13b04d021c1f`, région WEUR).
- wrangler connecté en OAuth sur le Mac (`npx wrangler login`).

### Bindings et secrets (noms seulement)

- `DB` : base D1 `edu-stats`.
- `LIMITER` : rate limiting Cloudflare (`[[unsafe.bindings]]`, 5 requêtes par 60 s, utilisé par `POST /v1/installation`). Plafond global de 500 créations par jour (Europe/Paris), appliqué dans D1 par une seule instruction INSERT conditionnelle.
- `LIMITER_SIGNAL` : second limiteur (`[[unsafe.bindings]]`, namespace 4202, 30 requêtes par 60 s), utilisé par `POST /v1/signal` avant tout accès à D1. Absent, le Worker fonctionne sans cette limite.
- Corps des requêtes : refus (413) au-delà de 1024 octets d'après `Content-Length`, puis lecture bornée par blocs.
- Secret `EDU_STATS_TOKEN` : jeton Bearer de `GET /v1/stats`.
- Cron : `17 3 * * *` (UTC), agrégation et purge.

### Déploiement, dans l'ordre

Depuis `cloudflare/edu-stats/` :

1. `npx wrangler d1 create edu-stats` (une seule fois), reporter l'id dans `wrangler.toml`.
2. `npx wrangler d1 execute edu-stats --remote --file schema.sql` (idempotent).
3. `openssl rand -hex 32 > <fichier hors dépôt>` puis `npx wrangler secret put EDU_STATS_TOKEN < <fichier>`.
4. `npx wrangler deploy`.
5. Si le domaine n'est pas rattaché (la première publication peut échouer sur une erreur 10007 après l'upload) : `npx wrangler triggers deploy`.
6. Contrôle : `POST /v1/installation` doit renvoyer 201, `GET /v1/stats` sans jeton 401.

Tests avant déploiement : `node --test cloudflare/edu-stats/test/`.

### Règle WAF de zone (étape manuelle, non créée par le code)

Un limiteur dans le Worker ne protège que D1 : chaque requête compte quand même dans le quota du Worker. À créer à la main dans le tableau de bord Cloudflare (zone mathys.cc, Sécurité, Règles de limitation de débit) :

1. Expression : `http.host eq "edu.mathys.cc" and starts_with(http.request.uri.path, "/v1/")`.
2. Caractéristique de comptage : IP. Seuil conseillé : 60 requêtes par 10 secondes. Action : bloquer 10 minutes.
3. Contrôle : après création, une rafale de requêtes de test depuis un poste doit finir en 429.

### Limites connues du Worker

1. Le plafond de 500 créations par jour échoue fermé : s'il est atteint (abus), les nouvelles installations ne sont pas comptées ce jour-là, sans effet pour l'utilisateur.
2. Après une coupure de plus de 35 jours (vacances d'été), les installations purgées se réinscrivent et sont comptées comme « nouvelles ».
3. L'étape de règle WAF ci-dessus (blocage 10 minutes sur une période de 10 secondes) peut ne pas être disponible sur l'offre gratuite de Cloudflare : vérifier les valeurs proposées par le tableau de bord et prendre la durée de blocage la plus longue disponible.

### Rétention

- `installations` : empreinte SHA-256 et jour de création. Le cron supprime celles sans aucune présence depuis plus de 35 jours (une installation neuve reste au moins 35 jours). Une app purgée reçoit 404 au prochain signal et se réinscrit seule.
- Plafond global de 500 créations d'installations par jour (`PLAFOND_CREATIONS_JOUR` dans `worker.js`), compté dans D1, sans IP. Au-delà : 429.
- Limiteur de création : clé = SHA-256(jour, jeton, IPv4 entière ou préfixe IPv6 /64), calculée en mémoire.
- `presences` : 35 jours (versions comprises). Le cron quotidien agrège les lignes plus anciennes dans `jours_agreges(jour, actifs, nouvelles)` puis les supprime.
- Surveillance de la purge : `GET /v1/stats` expose `presence_la_plus_ancienne` (date, ou `null`). Elle doit rester sous 37 jours (elle vaut 36 chaque nuit entre minuit Paris et le cron de 03:17 UTC, donc 36 est normal). À 37 jours ou plus, le cron ne tourne plus ou échoue : à contrôler avec `npx wrangler deployments list` et le tableau de bord (Triggers).
- Toutes les réponses portent `X-Content-Type-Options: nosniff`.
- Rien d'autre n'est stocké : ni IP, ni User-Agent, ni pays, ni heure. Observabilité et logpush désactivés.

### Réserves d'anonymat (l'engagement ne change pas)

Aucune IP, aucun User-Agent, aucun pays, aucune heure n'est stocké ni journalisé. Trois réserves à connaître :

1. L'empreinte (SHA-256 de l'identifiant) est un pseudonyme stable : la table `presences` la relie aux jours d'usage et à la version pendant 35 jours. Sans IP, elle n'identifie personne.
2. L'IP sert de clé au limiteur, en mémoire seulement. Elle est salée par le jour et le jeton `EDU_STATS_TOKEN` avant le SHA-256 : l'empreinte ne s'inverse pas par énumération des adresses IPv4 et change chaque jour. Rien n'est persisté côté D1. (Cloudflare traite l'IP pour le limiteur et le WAF, comme pour toute requête.)
3. La version est déclarable librement (`999.999.999` passe la validation) et une installation n'est pas une personne : réinstaller, ou plusieurs postes, comptent plusieurs fois. Les chiffres sont des ordres de grandeur, pas des audiences.

### Mise en production de ce lot (dans l'ordre)

Aucun changement de schéma : pas de migration D1. Depuis `cloudflare/edu-stats/` :

1. `node --test test/` (doit être vert).
2. `npx wrangler deploy` : crée aussi le binding `LIMITER_SIGNAL` déclaré dans `wrangler.toml`.
3. Contrôle : `POST /v1/installation` renvoie 201, `POST /v1/signal` avec un corps de plus de 1024 octets renvoie 413, `GET /v1/stats` avec le jeton contient `presence_la_plus_ancienne`, toute réponse porte `X-Content-Type-Options: nosniff`.
4. Créer la règle WAF de zone ci-dessus.

Premier passage du cron après déploiement : il purge les installations sans présence depuis plus de 35 jours (y compris les anciennes jamais revenues). Le compteur `installations` de `/v1/stats` baissera d'autant, c'est voulu.

### Retour arrière

- Ce lot : `npx wrangler rollback` (version précédente du Worker). Le binding `LIMITER_SIGNAL` inutilisé est inoffensif. Les installations déjà purgées ne reviennent pas : les apps concernées reçoivent 404 et se réinscrivent seules. Pas de migration à défaire.
- Code : `git revert` du commit puis `npx wrangler deploy`. Les versions précédentes sont listées par `npx wrangler deployments list` et rétablies par `npx wrangler rollback`.
- Arrêt complet : `npx wrangler delete` supprime le Worker et son domaine. La base D1 reste (`npx wrangler d1 delete edu-stats` pour l'effacer).
- Rotation du jeton : régénérer le fichier et refaire l'étape 3.
- Purge des données : `npx wrangler d1 execute edu-stats --remote --command "DELETE FROM presences; DELETE FROM installations; DELETE FROM jours_agreges;"`.
