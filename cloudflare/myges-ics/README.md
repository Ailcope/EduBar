# myges-ics

Worker Cloudflare qui publie l'emploi du temps myGES en flux iCal sur `https://edt.mathys.cc/<FEED_TOKEN>.ics`, pour s'y abonner depuis Google Agenda (« À partir de l'URL ») ou Calendrier Apple.

## Principe

- Cron toutes les 30 min : connexion à l'API Kordis (identifiants myGES), lecture de `/me/agenda` de J-14 à J+120, construction du `.ics`, enregistrement en KV.
- `GET /<FEED_TOKEN>.ics` : sert le dernier `.ics` enregistré. Tout autre chemin, ou un mauvais jeton : 404.
- Seuls les vrais cours sont publiés (`type` « Cours » ou absent, même règle qu'EduBar). Les animations de l'école (`type` « Autre ») sont exclues.
- myGES en panne, identifiants refusés ou agenda soudain vide : l'ancien `.ics` reste servi et la sonde Healthchecks reçoit `/fail`.
- Google Agenda relit un abonnement à son propre rythme (souvent toutes les 8 à 24 h) : le Worker est à jour à 30 min près, Google non.

## Tests

```
node --test cloudflare/myges-ics/test/worker.test.mjs
```

## Déploiement

Voir `docs/deploiement.md`, section « Worker myges-ics ».
