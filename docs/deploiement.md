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
- `LIMITER` : rate limiting Cloudflare (`[[unsafe.bindings]]`, 5 requêtes par 60 s, utilisé par `POST /v1/installation`).
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

### Rétention

- `installations` : empreinte SHA-256 et jour de création, conservés.
- `presences` : 35 jours (versions comprises). Le cron quotidien agrège les lignes plus anciennes dans `jours_agreges(jour, actifs, nouvelles)` puis les supprime.
- Rien d'autre n'est stocké : ni IP, ni User-Agent, ni pays, ni heure. Observabilité et logpush désactivés.

### Retour arrière

- Code : `git revert` du commit puis `npx wrangler deploy`. Les versions précédentes sont listées par `npx wrangler deployments list` et rétablies par `npx wrangler rollback`.
- Arrêt complet : `npx wrangler delete` supprime le Worker et son domaine. La base D1 reste (`npx wrangler d1 delete edu-stats` pour l'effacer).
- Rotation du jeton : régénérer le fichier et refaire l'étape 3.
- Purge des données : `npx wrangler d1 execute edu-stats --remote --command "DELETE FROM presences; DELETE FROM installations; DELETE FROM jours_agreges;"`.

## Worker myges-ics

Emploi du temps myGES en flux iCal, pour l'abonnement Google Agenda. Code dans `cloudflare/myges-ics/`.

### Où

- Cloudflare, compte de Mathys (`account_id` dans `wrangler.toml`), Worker `myges-ics`.
- Domaine personnalisé `edt.mathys.cc` (zone mathys.cc), `workers_dev = false`.
- Espace KV `myges-ics` (binding `ICS`, clé `ics` = dernier `.ics` correct).
- Flux : `https://edt.mathys.cc/<FEED_TOKEN>.ics`.

### Bindings et secrets (noms seulement)

- `ICS` : espace KV.
- Secrets `MYGES_LOGIN`, `MYGES_PASSWORD` : identifiants myGES (connexion Kordis en Basic, aucun jeton de rafraîchissement).
- Secret `FEED_TOKEN` : partie secrète de l'URL du flux (16 à 128 caractères `A-Za-z0-9_-`).
- Secret `HC_PING_URL` (facultatif) : URL de ping Healthchecks, `/fail` ajouté en cas d'échec.
- Cron : `*/30 * * * *` (UTC).

### Déploiement, dans l'ordre

Depuis `cloudflare/myges-ics/` :

1. `npx wrangler login` si wrangler n'est pas connecté.
2. `npx wrangler kv namespace create myges-ics` (une seule fois), reporter l'id dans `wrangler.toml`.
3. `npx wrangler deploy`. Si le domaine n'est pas rattaché (erreur 10007) : `npx wrangler triggers deploy`.
4. `npx wrangler secret put MYGES_LOGIN` puis `npx wrangler secret put MYGES_PASSWORD` (saisie au clavier, jamais en argument).
5. Générer le jeton du flux et le garder hors dépôt : `node -e "console.log(require('crypto').randomBytes(24).toString('hex'))"`, puis `npx wrangler secret put FEED_TOKEN`.
6. Healthchecks (hc.mathys.cc) : sonde `cf_myges_ics`, période 30 min, délai de grâce 2 h ; `npx wrangler secret put HC_PING_URL`.
7. Contrôle : `curl -sI https://edt.mathys.cc/<FEED_TOKEN>.ics` renvoie 200 et `text/calendar` ; `curl -sI https://edt.mathys.cc/` renvoie 404.
8. Google Agenda > Autres agendas > « + » > À partir de l'URL : coller l'URL du flux. Supprimer ensuite l'abonnement Edusign.

Tests avant déploiement : `node --test cloudflare/myges-ics/test/worker.test.mjs`.

### Retour arrière

- Code : `git revert` du commit puis `npx wrangler deploy`, ou `npx wrangler rollback`.
- Fuite de l'URL : refaire l'étape 5 (nouveau `FEED_TOKEN`), puis remplacer l'abonnement dans Google Agenda.
- Changement du mot de passe myGES : refaire `npx wrangler secret put MYGES_PASSWORD`, sinon la sonde passe en échec.
- Arrêt complet : `npx wrangler delete`, puis `npx wrangler kv namespace delete --namespace-id <id>`, et supprimer la sonde Healthchecks.
