# API Kordis / myGES (non officielle) : synthèse

Document établi le 15/10/2026 à partir du code de dépôts publics (clonés et relus) et de deux requêtes sans identifiants. Rien n'a été inventé : ce qui n'est pas prouvé par un dépôt ou une requête est marqué « à vérifier ».

## 1. Authentification

Flux OAuth2 "implicit" (client public `skolae-app`), avec les identifiants de l'étudiant envoyés en Basic. Cohérent dans tous les dépôts lus (PHP, TS, Go, Python, PHP).

| Élément | Valeur |
|---|---|
| Méthode | `GET` |
| URL | `https://authentication.kordis.fr/oauth/authorize?response_type=token&client_id=skolae-app` |
| En-tête | `Authorization: Basic base64(identifiant:motdepasse)` (identifiant de type `pnom`, selon Augaton/kordis_token_retriever) |
| Redirections | NE PAS les suivre (`allow_redirects=False`, `redirect: 'manual'`, `maxRedirects: 0`) |
| Succès | HTTP 302, en-tête `Location: comreseaugesskolae://oauth2redirect#access_token=...&token_type=bearer&expires_in=...&scope=...&uid=...` (schéma mobile ; la doc SebPautot écrit `comreseaugesskolae:/oauth2redirect#`) |
| Récupération du token | Lire le **fragment** (après `#`) de `Location`, découper sur `&` puis `=`. Champs lus par le code : `access_token`, `token_type`, `expires_in`, `scope`, `uid` |
| Mauvais identifiants | pas de 302 : 401 (tchenu/myges, Spatulox : « Bad username or password » si code différent de 302 ; Bot-Myges : absence de `Location` = mauvais identifiants, 5xx/429 = panne) |
| Cas du fragment | Ne pas décoder les valeurs : un token peut contenir des `+` (commentaire de Bot-Myges `auth.ts`) |

Exemple de requête (reconstitué depuis le code, pas une capture réelle) :

```
curl -i -H "Authorization: Basic $(printf '%s:%s' "$ID" "$PW" | base64)" \
  "https://authentication.kordis.fr/oauth/authorize?response_type=token&client_id=skolae-app"
# -> 302, lire Location, extraire access_token après '#'
```

- Durée de vie du token : le serveur renvoie `expires_in` dans le fragment, **valeur numérique jamais documentée dans les dépôts : à vérifier** (Bot-Myges le traite comme des secondes, `expires_at = now + ttl*1000`, et se reconnecte à 60 s de l'échéance ou sur 401).
- Refresh token : **aucun** relevé dans les fragments lus (pas de `refresh_token` utilisé par aucun dépôt). Tous se reconnectent avec identifiant et mot de passe. À vérifier si le fragment en contient un.
- Piège signalé (Augaton/kordis_token_retriever, fév. 2026) : un pare-feu renvoie 403 sans `User-Agent` de navigateur ; le script envoie un UA Chrome. Lululufr (mars 2025) envoie aussi un UA navigateur. Affirmation d'un README, non vérifiée par moi.
- `Content-Type`/`Accept` : non nécessaires d'après tchenu, Bot-Myges, Spatulox (seulement `Authorization`).

## 2. Endpoints

Base : `https://api.kordis.fr`. En-tête obligatoire : `Authorization: Bearer {access_token}` (le code utilise `{token_type} {access_token}`, avec `token_type=bearer`). Toutes les routes relevées sont préfixées `/me`. `{year}` est une année scolaire entière (valeur issue de `/me/years`, ex. 2025 : exemple de forme, à vérifier).

| Méthode | Chemin | Paramètres | Sources |
|---|---|---|---|
| GET | `/me/profile` | aucun | tous |
| PUT? | `/me/profile` | mise à jour (`updateProfile` dans tchenu, verbe et corps à vérifier) | tchenu `Me.php` |
| GET | `/me/years` | aucun | myges-cli, Bot-Myges, Spatulox, MeTtHa |
| GET | `/me/agenda?start={ms}&end={ms}` | **millisecondes epoch** (entiers) | doc SebPautot, myges-cli (`Date.valueOf()`), Bot-Myges, Go (`UnixMilli`), Python (`int(ts)*1000`) |
| GET | `/me/{year}/grades` | | doc SebPautot, tous |
| GET | `/me/{year}/absences` | | doc SebPautot, myges-cli, Bot-Myges, Go ; Python : « cassé » (commenté) |
| GET | `/me/{year}/courses` | | myges-cli, Bot-Myges, Go |
| GET | `/me/{year}/classes` | | doc SebPautot, Bot-Myges |
| GET | `/me/{year}/teachers` | | doc SebPautot, Bot-Myges |
| GET | `/me/{year}/projects` | | myges-cli, Bot-Myges, Go |
| GET | `/me/projects/{id}` | | myges-cli, Bot-Myges |
| GET | `/me/nextProjectSteps` | | myges-cli, Bot-Myges |
| POST / DELETE | `/me/courses/{rcId}/projects/{projectId}/groups/{groupId}` | rejoindre / quitter un groupe | myges-cli, Bot-Myges |
| GET / POST | `/me/projectGroups/{id}/messages` | POST corps JSON `{projectGroupId, message}` | myges-cli, Bot-Myges |
| GET | `/me/news?page={n}` (Bot-Myges ajoute `&size=10`) | | doc SebPautot, Bot-Myges |
| GET | `/me/news/banners` | | doc SebPautot, tchenu, Go |
| GET | `/me/classes/{classeId}/students` | | doc SebPautot, Bot-Myges |
| GET | `/me/students/{studentId}` | | doc SebPautot, Python |
| GET | `/me/events`, `/me/event/{id}` | champs `event_id`, `name`, `description`, `start_date`, `end_date`, `color`, `event_date` | Python (lululufr), Go : à vérifier |

Les ressources `/me/{year}/...` n'acceptent a priori que l'année scolaire de l'étudiant.

### 2.1 Agenda (`/me/agenda`)

`result` est un tableau. Champs réels, tirés des interfaces TypeScript de Bot-Myges (`interfaces/timetable.ts`, 2026) et des structures Go de Spatulox (nov. 2025). Aucun JSON brut complet n'existe dans les dépôts, voici donc la forme reconstituée avec des valeurs factices (les noms et types sont, eux, tirés du code) :

```json
{
  "reservation_id": 0,
  "name": "string",
  "type": "string",
  "modality": "string",
  "start_date": 1760000000000,
  "end_date": 1760003600000,
  "state": "string",
  "comment": null,
  "classes": null,
  "author": 0,
  "create_date": 0,
  "teacher": "string",
  "promotion": "string",
  "prestation_type": 0,
  "is_electronic_signature": false,
  "rooms": [
    { "room_id": 0, "name": "string", "floor": "string", "campus": "string",
      "color": "string", "latitude": "string", "longitude": "string" }
  ],
  "discipline": {
    "name": "string", "teacher": "string", "teacher_id": 0, "trimester": "string",
    "coef": null, "ects": null, "year": 0, "has_documents": null, "has_grades": null,
    "nb_students": 0, "rc_id": 0, "school_id": 0, "student_group_id": 0,
    "student_group_name": "string", "syllabus_id": null, "trimester_id": 0
  }
}
```

- `start_date`, `end_date`, `create_date` : millisecondes epoch (le Go convertit `/1000`).
- Valeurs d'énumération de `type`, `modality`, `state` : non documentées, **à vérifier**.
- Dans le Go, `discipline.trimester` est un `*string` et `coef`/`ects` des `*float32` (peuvent être `null`).

### 2.2 Notes (`/me/{year}/grades`)

`result` est un tableau, un objet par matière. Champs relevés (Spatulox `GradesStructures.go`, Bot-Myges `notesImage.ts`) :

| Champ | Type | Remarque |
|---|---|---|
| `course` | string | préfixé parfois de `T1 - ` (trimestre) ; Bot-Myges retire le préfixe |
| `grades` | tableau de nombres | notes de contrôle continu ; Bot-Myges note « parfois en objets selon l'année » (`grade`/`value`), à vérifier |
| `exam` | nombre ou null | note d'examen |
| `average` | nombre ou null | moyenne définitive (champ lu par Bot-Myges, absent de la struct Go) |
| `ccaverage` | nombre | moyenne de CC ; `0` = pas de note |
| `coef` | **string** (Go) | |
| `ects` | string (Go) ; Bot-Myges parse un nombre | |
| `bonus` | int | |
| `trimester` | int | |
| `year` | int | |
| `teacher_civility`, `teacher_first_name`, `teacher_last_name` | string | |
| `absences` | nombre | lu par Bot-Myges ; présence réelle à vérifier |

Bot-Myges précise : « l'API renvoie indifféremment null, '', 0 ou une chaîne » pour ces valeurs numériques.

### 2.3 Absences (`/me/{year}/absences`)

Champs (Go) : `course_name`, `date` (float, ms), `justified` (bool), `links` (tableau), `trimester` (int), `trimester_name`, `type`, `year` (int). Python (mars 2025) signale la route comme « cassé » : à vérifier.

### 2.4 Profil, années, autres

- `/me/profile` : champs confirmés seulement `name`, `firstname`, `_links.photo.href` (exemple tchenu `profile.php`). Le reste : à vérifier.
- `/me/years` : tableau d'années ; MeTtHa-Matt lit `years[0]` comme entier numérique. Pas d'autre champ vu.
- `/me/{year}/classes` : Python lit `result[0].puid` comme id de classe.
- Projets : types complets dans Bot-Myges `interfaces/project.ts` (`project_id`, `name`, `course_name`, `groups[]`, `steps[]`, `rc_id`, `year`, etc.). Non recopiés ici.
- Autres routes (courses, teachers, news, students) : forme à vérifier.

## 3. Enveloppe de réponse

- Succès : objet JSON `{"result": <données>}`. `result` est un tableau (agenda, notes, absences, années) ou un objet. Confirmé par myges-cli (`data.result`), Bot-Myges (`data.result`), Go (`result["result"]`), Python (`["result"]`).
- Pas de champ `response_code` dans le code lu : à vérifier.
- Erreurs : voir §5 (401 en XML pour le jeton absent). Bot-Myges rejoue sur 429/500/502/503/504 (« MyGes renvoie régulièrement des 500/502/503 passagers »).
- Expiration du token : 401 sur l'API, Bot-Myges se reconnecte alors une fois.

## 4. Dépôts consultés (dates = dernier push, via l'API GitHub le 15/10/2026)

| Dépôt | Langage | Dernière activité | Remarques |
|---|---|---|---|
| https://github.com/Augaton/Bot-Myges | TypeScript (Discord) | 01/10/2026 (v3.4.0) | le plus frais ; code qui fonctionne, retries, renouvellement du token |
| https://github.com/Augaton/kordis_token_retriever | Python | 04/02/2026 | récupère le token ; mentionne un 403 sans User-Agent navigateur |
| https://github.com/MeTtHa-Matt/MyGES | PHP (proxy web) | 12/10/2026 | utilise `authentication.kordis.fr/oauth` + `api.kordis.fr` ; aussi `ges-cas.kordis.fr` (portail web) et `ges-dl.kordis.fr` (documents) |
| https://github.com/Spatulox/MyGesClient | Go (Wails) | 04/11/2025 | structs Go des réponses (notes, absences, agenda) |
| https://github.com/lululufr/MygesAPI-Python | Python | 03/03/2025 | absences notées « cassé » ; autres routes `events`, `event/{id}` |
| https://github.com/SebPautot/myges-documentation | Doc | 11/12/2024 | dernier commit « API is back, just a maintenance ? » (coupure temporaire fin 2024) |
| https://github.com/tchenu/myges | PHP | 17/10/2021, archivé août 2024 | plus ancienne référence ; a changé de domaine (« fix/new-domain ») |
| https://github.com/quantumsheep/myges-cli (npm `myges` 4.7.1) | TypeScript | 26/03/2022 (npm mai 2022) | CLI avec commande `request` brute |

Dépôts vus mais non lus : mrpinkcat/myges-calendar-scraper, Melv1no/myges-api, Jawad-Ahmindache/MyGES, UnBonWhisky/myges-to-icalendar, Ailcope/MyPrettyGradES (à toi, 13/10/2026).

Signaux de changement ou de casse :
- Fin 2024 : coupure puis retour (« API is back »).
- Fév. 2026 : un 403 de pare-feu sur l'authentification sans User-Agent navigateur (à vérifier).
- Mars 2025 : route absences « cassée » côté Python (à vérifier aujourd'hui).
- Aucun dépôt ne mentionne un changement de flux d'authentification.

## 5. Vérification en direct, sans identifiants (15/10/2026, 09:32 GMT)

`curl -sI "https://authentication.kordis.fr/oauth/authorize?response_type=token&client_id=skolae-app"` :
- HTTP/2 **401**, `www-authenticate: Basic realm="Realm"`, `content-type: text/html;charset=utf-8`, `set-cookie: JSESSIONID=...; Secure; HttpOnly`, CORS ouvert (`access-control-allow-origin: *`, méthodes `POST, GET, OPTIONS, DELETE`, en-têtes autorisés dont `authorization`), `cache-control: no-store`, HSTS. Plateforme Java (Spring) vraisemblable. Le endpoint est donc vivant et réclame bien du Basic.

`curl -sI https://api.kordis.fr/me/profile` :
- HTTP/2 **401**, `www-authenticate: Bearer realm="ges-api", error="unauthorized", error_description="Full authentication is required to access this resource"`, `content-type: application/xml;charset=UTF-8`.
- Corps : `<UnauthorizedException><error>unauthorized</error><error_description>Full authentication is required to access this resource</error_description></UnauthorizedException>`.
- Le realm `ges-api` et la route `/me/profile` existent bien.

Aucun identifiant n'a été essayé : le succès du flux complet (302 et fragment) n'est pas vérifié par moi, seulement par le code récent de Bot-Myges (oct. 2026).
