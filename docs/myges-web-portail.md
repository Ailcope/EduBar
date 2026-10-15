# myGES (web) : échanges à rejouer en pur HTTP

Source : capture HTTP Toolkit du 15/10/2026, Chrome/Brave 155. Aucun identifiant, mot de passe, cookie ou ticket n'est recopié ici (`<redacted>`). Le corps du POST CAS /login n'a PAS été lu : on sait seulement, par le HTML de la page, quels champs il contient.

Hôtes : `ges-cas.kordis.fr` (CAS, Apache-Coyote/Tomcat), `myges.fr` (JSF 2.0 / PrimeFaces 5.1, Spring Security CAS), `ges-dl.kordis.fr` (photos/fichiers).

## 1. Authentification CAS

Flux observé (CAS 3.x classique, protocole "ticket" avec `lt` + `execution`) :

| # | Méthode / URL | Résultat |
|---|---|---|
| 1 | `GET https://myges.fr/student/home` (non connecté) | 302 vers `https://ges-cas.kordis.fr/login?service=https%3A%2F%2Fmyges.fr%2Fj_spring_cas_security_check` (déduit : la capture débute à l'étape 2, mais le Referer et le service le confirment) |
| 2 | `GET https://ges-cas.kordis.fr/login?service=https%3A%2F%2Fmyges.fr%2Fj_spring_cas_security_check` | 200 HTML. Pose `JSESSIONID` (cookie CAS, `Path=/`, visible aussi comme `;jsessionid=<redacted>` dans l'URL des ressources). Pas de `Set-Cookie` CASTGC à ce stade. |
| 3 | `POST https://ges-cas.kordis.fr/login;jsessionid=<redacted>?service=https%3A%2F%2Fmyges.fr%2Fj_spring_cas_security_check` (événement 391217df, corps non lu) | 302. Le cookie `CASTGC` (TGT, `TGT-...-cas`) est ensuite présent dans la requête suivante, donc posé ici. |
| 4 | `GET https://ges-cas.kordis.fr/login;jsessionid=<redacted>?service=https%3A%2F%2Fmyges.fr%2Fj_spring_cas_security_check` avec cookies `CASTGC` + `JSESSIONID` | 302 `Location: https://myges.fr/j_spring_cas_security_check?ticket=ST-<n>-<redacted>-cas` (ticket de service `ST-`, usage unique) |
| 5 | `GET https://myges.fr/j_spring_cas_security_check?ticket=ST-...` (sans cookie, Referer `https://ges-cas.kordis.fr/`) | 302, `Set-Cookie: JSESSIONID=<redacted>; Path=/; HttpOnly`, `Location: /student/home` |
| 6 | `GET https://myges.fr/student/home` avec `Cookie: JSESSIONID=<myges>` | 200 HTML, session ouverte |

Dans la capture, 4 est une GET faite par le navigateur après la 302 du POST (le Location du POST pointe donc vers cette URL, non vérifié car corps/en-têtes du POST non lus). Un client URLSession qui suit les redirections fait 3 -> 4 -> 5 -> 6 automatiquement.

### 1.1 Page de login (GET étape 2), champs du formulaire

Formulaire : `<form id="fm1" action="/login" method="post">` (action relative, donc POST sur `https://ges-cas.kordis.fr/login`; le navigateur y ajoute `;jsessionid=...?service=...`, repris de l'URL de la page).

| name | type | valeur |
|---|---|---|
| `username` | text | identifiant |
| `password` | password | mot de passe |
| `lt` | hidden | ticket de login, format `LT-<n>-<aléatoire>-cas`, UNIQUE PAR AFFICHAGE : à extraire de la page de l'étape 2 |
| `execution` | hidden | `e2s1` (webflow, valeur lue ; la relire à chaque fois) |
| `_eventId` | hidden | `submit` |
| `submit` | submit | `CONNEXION` (présent dans le formulaire ; probablement envoyé par le navigateur) |

Content-Type attendu : `application/x-www-form-urlencoded`. Extraire avec regex `name="lt" value="([^"]+)"` et `name="execution" value="([^"]+)"` (attention : les `<input>` sont séparés par des retours à la ligne dans le HTML, ex. `<input\n type="hidden" name="execution" ...`, utiliser `(?s)` / `\s+`).

Autres : la page charge jQuery depuis ajax.googleapis.com (inutile), liens "Mot de passe oublié" et "Changer mon mot de passe" vers `https://authentication.kordis.fr/...`. Titre : "Réseau GES - Authentification". Pas de captcha ni 2FA visibles dans cette page.

Echec de login : non capturé (non testé), probablement 200 avec la même page et un message d'erreur (`id="msg"` classique CAS) ; à vérifier.

### 1.2 Cookies

| Domaine | Cookie | Rôle |
|---|---|---|
| ges-cas.kordis.fr | `JSESSIONID` | session webflow CAS (lt/execution liés à elle) |
| ges-cas.kordis.fr | `CASTGC` | SSO (TGT), posé après le POST réussi. Permet de re-obtenir un ticket sans mot de passe (étape 4 seule) tant qu'il est valide |
| myges.fr | `JSESSIONID` (`Path=/; HttpOnly`) | seul cookie de session myges. Durée d'inactivité côté JS : `maxIdleTime = 7200` s |
| ges-dl.kordis.fr | `JSESSIONID` | uniquement pour photos/fichiers |

Déconnexion : `GET https://myges.fr/logout`.

## 2. Session myges.fr et ViewState

- Pages en rendu serveur JSF 2.0 / PrimeFaces 5.1 (`X-Powered-By: JSF/2.0`).
- Menu (extraits de `/student/home`) : `/student/home` (Accueil), `/student/planning-calendar` (Plannings), `/student/marks` (Notes et absences), `/common/student-documents`, `/student/documents`, `/student/invoice`, `/student/courses-files`, `/student/syllabus-list`, `/common/elearning`, `/student/project-list`, `/student/practical-list`, `/student/student-directory`, `/student/student-teacher-directory`, `/student/relations-entreprises`, `/student/academic-software`, `/student/contacts`, `/common/user-message`, `/common/student-profile`, `/logout`.
- Le nom/prénom de l'étudiant est dans la page d'accueil (`<span>NOM</span>` puis prénom, dans `userinfo:mg_userinfo_a`). Photo : voir 2.2.
- `javax.faces.ViewState` : chaîne `<nombre>:<nombre>` (ex. forme `-5329...:-2952...`), présente dans CHAQUE `<form>` de la page :
  `<input type="hidden" name="javax.faces.ViewState" id="javax.faces.ViewState" value="..." autocomplete="off" />`.
  Il est lié à la vue (une page = un ViewState), et NE CHANGE PAS entre les appels AJAX d'une même vue dans la capture (la réponse partial renvoie le même ViewState dans `<update id="javax.faces.ViewState">`). Toujours le relire dans la réponse partial et le réutiliser. Il y en a 2 valeurs égales dans la page (form de breadcrumb `j_idt158` et form métier).
- Les ids `j_idtNNN` sont générés et sont stables pour une même page, mais peuvent changer à une mise à jour du site : ne pas les coder en dur sans repli (voir 5).
- Tout appel AJAX PrimeFaces doit : POST sur la MÊME URL que la page (`/student/planning-calendar` ou `/student/marks`), avec le cookie `JSESSIONID` myges et la GET préalable de cette page (pour obtenir le ViewState).

### 2.1 En-têtes des POST AJAX (identiques planning et notes)

```
POST /student/planning-calendar HTTP/1.1      (ou /student/marks)
Host: myges.fr
Faces-Request: partial/ajax
X-Requested-With: XMLHttpRequest
Accept: application/xml, text/xml, */*; q=0.01
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
Origin: https://myges.fr
Referer: https://myges.fr/student/planning-calendar
Cookie: JSESSIONID=<redacted>
```
Réponse : `200`, `Content-Type: text/xml;charset=UTF-8`, corps `<partial-response><changes><update id="..."><![CDATA[...]]></update>...</changes></partial-response>`.

### 2.2 Requêtes vers ges-dl.kordis.fr

- `GET https://ges-dl.kordis.fr/public/<id>?pfdrid_c=true` et `/public/<id>` : images publiques (200), dont la photo de l'étudiant (`<img id="userinfo:photo" src="https://ges-dl.kordis.fr/public/...">`).
- `GET https://ges-dl.kordis.fr/private/<id>` (3 occurrences, appelées par du JS `loadPhoto(4)` sur chaque page, en XHR cross-origin avec `withCredentials`, Origin `https://myges.fr`) : répond 302 vers `https://ges-cas.kordis.fr/login?service=https%3A%2F%2Fges-dl.kordis.fr%2Fj_spring_cas_security_check` + nouveau `JSESSIONID` ges-dl. C'est un amorçage de la session SSO sur ges-dl pour pouvoir ensuite télécharger des fichiers privés (documents, supports de cours). Le navigateur ne suit pas la redirection cross-origin dans le XHR (on voit 302 seulement) : le script retente jusqu'à 4 fois. NON nécessaire pour planning et notes. Pour de futurs téléchargements de fichiers privés : suivre la 302 avec le TGC déjà acquis (étape 4 du CAS avec `service=https://ges-dl.kordis.fr/j_spring_cas_security_check`).

## 3. Planning

### 3.1 Page

`GET https://myges.fr/student/planning-calendar` (200 HTML, 38 Ko). Contient :
- `<form id="calendar" ... action="/student/planning-calendar">` avec champ `<input type="hidden" name="calendar" value="calendar">`, et ViewState dedans.
- Composant PrimeFaces Schedule, id `calendar:myschedule`, vue `agendaWeek`, config JS : `defaultView:"agendaWeek", locale:"fr", offset:7200000, year:2026, month:9 (0-indexé), date:15, minTime:"07:00", maxTime:"24:00", disableDragging/Resizing:true`. `offset:7200000` est le décalage UTC du serveur au moment de la page (UTC+2 été).
- Le contenu des événements n'est PAS dans la page : il est chargé par un POST AJAX "lazy" juste après (3.2).
- Libellés/boutons (même form `calendar`) : `calendar:previousMonth` (◄), `calendar:nextMonth` (►), `calendar:currentDate` ("Maintenant"), `calendar:j_idt170` (rafraîchir). Leur `onclick` met à jour `calendar:myschedule calendar:currentDate calendar:currentWeek calendar:campuses calendar:lastUpdate`. Je n'ai pas capturé de clic sur ◄/► : le navigateur a seulement fait la requête de chargement initial. Pour changer de semaine, la voie documentée par PrimeFaces est de rejouer le POST 3.2 avec d'autres `_start`/`_end`.
- Légende des campus (`calendar:campuses`) et label `calendar:currentWeek` ("12 octobre - 18 octobre 2026"), `calendar:lastUpdate` ("Mise à jour le : 15 octobre 2026 à 11:13"), texte "Emploi du temps prévisionnel, sous réserve de modification".

### 3.2 Chargement des événements (POST observé, événement 42efccbf)

`POST https://myges.fr/student/planning-calendar` en-têtes de 2.1. Corps (urlencoded, valeurs réelles décodées) :

```
javax.faces.partial.ajax=true
javax.faces.source=calendar:myschedule
javax.faces.partial.execute=calendar:myschedule
javax.faces.partial.render=calendar:myschedule
calendar:myschedule=calendar:myschedule
calendar:myschedule_start=1791756000000
calendar:myschedule_end=1792360800000
calendar=calendar
calendar:myschedule_view=agendaWeek
javax.faces.ViewState=<valeur lue dans la page>
```
(les `:` sont encodés `%3A` dans le corps réel, longueur 417 octets.)

Plage de dates : timestamps EN MILLISECONDES depuis l'époque Unix (UTC), sans fuseau dans la requête.
- `_start` = 1791756000000 = lundi 12/10/2026 00:00 heure de Paris (= 11/10 22:00 UTC)
- `_end`   = 1792360800000 = lundi 19/10/2026 00:00 heure de Paris, soit exactement +604800000 ms (7 jours).
Donc semaine lundi 00:00 -> lundi suivant 00:00 (Europe/Paris), fin exclusive. Pas testé : plage plus longue (mois, plusieurs semaines) ; PrimeFaces accepte toute plage, à essayer côté app pour réduire le nombre de requêtes (voir 5).

Réponse (200, text/xml, 2,3 Ko pour 9 événements) :

```xml
<?xml version='1.0' encoding='UTF-8'?>
<partial-response><changes>
<update id="calendar:myschedule"><![CDATA[{"events" : [ {...}, {...} ]}]]></update>
<update id="javax.faces.ViewState"><![CDATA[<même ViewState>]]></update>
</changes></partial-response>
```
Le contenu du CDATA est du JSON (non pretty-printed, ordre des événements NON chronologique). Un événement, format exact :

```json
{"id": "<uuid>","title": "T1 - sécurité...\nQuai 12 - 506","start": "2026-10-16T15:45:00+0200","end": "2026-10-16T17:15:00+0200","allDay":false,"editable":true,"className":"reservation-REIMS"}
```
Deux exemples complets (anonymisés, ids remplacés) :

```json
{"id": "e80cc9f3-xxxx","title": "T1 - sécurité...\nQuai 12 - 506","start": "2026-10-16T15:45:00+0200","end": "2026-10-16T17:15:00+0200","allDay":false,"editable":true,"className":"reservation-REIMS"}
{"id": "512a1dac-xxxx","title": "T1 - gestion...\nQuai 12 - 301","start": "2026-10-15T11:30:00+0200","end": "2026-10-15T13:00:00+0200","allDay":false,"editable":true,"className":"reservation-REIMS"}
```
Champs :
- `id` : UUID de la réservation (sert de clé pour `eventSelect`, voir plus bas).
- `title` : DEUX lignes séparées par `\n` : ligne 1 = intitulé de la matière TRONQUÉ (13 premiers caractères environ + `...`, ex. "T1 - sécurité..."), ligne 2 = campus/bâtiment + salle (`Quai 12 - 506`). Le titre complet n'est donc PAS dans ce JSON.
- `start`, `end` : ISO 8601 avec décalage SANS deux-points : `yyyy-MM-dd'T'HH:mm:ssZ` (`+0200`, `+0100` en hiver). Formatter Swift : `yyyy-MM-dd'T'HH:mm:ssZ` (Z = `+0200`), locale `en_US_POSIX`.
- `allDay` : false. `editable` : true (sans effet).
- `className` : `reservation-<CAMPUS>` (ici `reservation-REIMS`) ; sert à la couleur de légende campus. La légende contient aussi "Hybride" (vert #2E9E4B) : probablement un autre className pour les cours hybrides/distanciel (non vu dans cette semaine).
- Pas de champ prof, modalité, type, commentaire dans le JSON.

### 3.3 Détail d'un cours (NON capturé)

Le JS de la page définit `behaviors:{eventSelect: PrimeFaces.ab({s:'calendar:myschedule', e:'eventSelect', p:'calendar:myschedule', u:'@(.dlg1)', onco: PF('dlg1').show()}, ext)}`. Le clic sur un cours envoie donc un POST AJAX avec `javax.faces.behavior.event=eventSelect`, `javax.faces.partial.event=eventSelect`, `javax.faces.source=calendar:myschedule`, `execute/…=calendar:myschedule`, `javax.faces.partial.render=@(.dlg1)` (valeur réelle du paramètre `render` à confirmer) et `calendar:myschedule_selectedEventId=<id uuid>` (nom standard PrimeFaces 5.1 `<clientId>_selectedEventId`), plus `calendar=calendar` et le ViewState. La réponse remplit la boîte "Cours" (`table#dlg1` avec les `<span>` : `duration` Durée, `matiere` Matière, `intervenant` Intervenant, `salle` Salle, `type` Type, `modality` Modalité, `commentaire`). C'est là que se trouvent le titre complet, le prof, la modalité (présentiel/distanciel/hybride) et le type. A CAPTURER avant d'implémenter (cliquer un cours dans HTTP Toolkit). Ces paramètres sont déduits du code PrimeFaces, pas observés.

### 3.4 Autres paramètres vus

- `javax.faces.partial.render`/`update` du bouton ◄/► : `calendar:myschedule calendar:currentDate calendar:currentWeek calendar:campuses calendar:lastUpdate`.

## 4. Notes (et absences)

### 4.1 Page

`GET https://myges.fr/student/marks` (200 HTML, 46 Ko, ViewState propre à cette page : forme `7212...:1179...`). Elle affiche DIRECTEMENT le semestre courant (le plus récent, ici "Semestre 2 2026-2027") déjà rendu dans le HTML : le tableau de notes ET le tableau d'absences. Pas besoin d'AJAX pour le semestre par défaut.

Form : `<form id="marksForm" action="/student/marks">` avec `<input type="hidden" name="marksForm" value="marksForm">` + ViewState.

Sélecteur de période (liste des semestres disponibles, à parser pour connaître les ids) :
```html
<select id="marksForm:j_idt174:periodSelect_input" name="marksForm:j_idt174:periodSelect_input" ...>
 <option value="3369497" selected="selected">2026-2027 - ESGI-REIMS - BCH_SE2_000_ALT  - Semestre 2</option>
 <option value="3314314">2026-2027 - ESGI-REIMS - BCH_SE2_000_ALT  - Semestre 1</option>
 <option value="3262967">2025-2026 - ESGI-REIMS - BCH_SE1_000_INI  - Semestre 3</option>
 <option value="3191221">2025-2026 - ESGI-REIMS - BCH_SE1_000_INI  - Semestre 2</option>
 <option value="3162432">2025-2026 - ESGI-REIMS - BCH_SE1_000_INI  - Semestre 1</option>
</select>
```
Valeur = identifiant numérique interne de période (pas de lien évident entre les ids, il faut lire les `<option>`). Le libellé contient année, école-campus, code classe, "Semestre N".

### 4.2 Les 4 POST (changement de semestre)

Les 4 POST (57620ec9, d241ad92, dd3447ba, cdaf0fea) sont strictement le même appel avec une valeur `_input` différente : changement du `<select>` de période (événement `valueChange`). Ordre : 3314314 (S1 2026-27), 3262967 (S3 2025-26), 3191221 (S2 2025-26), 3162432 (S1 2025-26).

Corps (décodé), 539 octets :
```
javax.faces.partial.ajax=true
javax.faces.source=marksForm:j_idt174:periodSelect
javax.faces.partial.execute=marksForm:j_idt174:periodSelect
javax.faces.partial.render=marksForm:marksWidget:coursesTable marksForm:missingsWidget:missingsTable marksForm:acceptFirmMarksPanel
javax.faces.behavior.event=valueChange
javax.faces.partial.event=change
marksForm=marksForm
marksForm:j_idt174:periodSelect_focus=
marksForm:j_idt174:periodSelect_input=<id période, ex. 3191221>
javax.faces.ViewState=<ViewState de la page marks>
```
(le séparateur dans `partial.render` est `+` = espace encodé.) En-têtes : voir 2.1, Referer `https://myges.fr/student/marks`.

Réponse : partial-response avec 4 `<update>` : `marksForm:acceptFirmMarksPanel` (case "j'autorise mon tuteur..." : vide pour les années passées), `marksForm:marksWidget:coursesTable` (le tableau de notes), `marksForm:missingsWidget:missingsTable` (absences/retards), `javax.faces.ViewState` (inchangé). Les contenus sont du HTML dans des CDATA.

Aucun autre mécanisme (dépliage, pagination) vu. Il n'y a pas de bouton de dépliage de lignes dans ce tableau.

### 4.3 Structure HTML du tableau de notes

Conteneur : `div#marksForm:marksWidget:coursesTable.ui-datatable` > `table[role=grid]` > `thead` + `tbody#marksForm:marksWidget:coursesTable_data`. IMPORTANT : le nombre de colonnes est DYNAMIQUE.
- Colonnes fixes (dans l'ordre) : `Matière`, `Intervenant`, `Coef.`, `ECTS`.
- Puis N colonnes de contrôle continu : `CC1`, `CC2`, ... (N = max des CC présents pour la période : 0 pour le semestre courant sans notes, 2 pour le S1 2025-26, 4 pour le S2 2025-26). Leurs `<th>` ont un id `...coursesTable:j_idt190:0`, `:1`, ...
- Puis la colonne finale `Exam`.
=> Il faut lire l'en-tête (`<span class="ui-column-title">`) pour savoir quelle colonne est quoi, pas des indices fixes. Aucune colonne "Moyenne" ni "Rattrapage" n'apparaît dans les 5 périodes capturées. Pas de nom de contrôle (juste CC1..CC4 / Exam), pas de moyenne de classe, pas de date.
- Pas de classes CSS spécifiques à la note : les cellules sont des `<td role="gridcell" style="width:45px;text-align: center">VALEUR</td>`. Les lignes ont `data-ri="<index>"` et `class="ui-widget-content ui-datatable-even odd-row"` / `ui-datatable-odd even-row`. Repérer matière = 1re cellule (`span.mg_inherit_color`), intervenant = 2e (`span`), puis par position selon l'en-tête.
- Valeurs : notes sur 20, virgule décimale (`18,5`, `9,75`), cellule VIDE si pas de note. `N.C` pour coef/ECTS non concernés. Les 0/20 sont "provisoires en attente de justificatif d'absence" (texte du bandeau).
- Lignes spéciales sans intervenant ni CC : "Note entreprise", "Open" (note dans la colonne Exam, coef `N.C`).
- Tableau vide : `<tr class="ui-widget-content ui-datatable-empty-message"><td colspan="5">Aucune entrée</td></tr>`.

Extrait représentatif d'une ligne (S2 2025-26, 4 colonnes CC + Exam, anonymisé : nom de prof remplacé) :
```html
<tr data-ri="2" class="ui-widget-content ui-datatable-even odd-row" role="row">
 <td role="gridcell" style="width:250px" class="mg_inherit_bg"><span class="mg_inherit_color" style="font-weight: bold; font-size: 11px">S2 - algorithmique et structure de données</span></td>
 <td role="gridcell" style="width:100px;"><span style="font-weight: bold; font-size: 11px; color: #5D5D5D">M. XXXXX</span></td>
 <td role="gridcell" style="width:37px;text-align: center">2.00</td>
 <td role="gridcell" style="width:37px;text-align: center">2.00</td>
 <td role="gridcell" style="width:45px;text-align: center">9</td>
 <td role="gridcell" style="width:45px;text-align: center">13</td>
 <td role="gridcell" style="width:45px;text-align: center"></td>
 <td role="gridcell" style="width:45px;text-align: center"></td>
 <td role="gridcell" style="width:55px;text-align: center">7</td>
</tr>
```
= Matière | Intervenant | Coef 2.00 | ECTS 2.00 | CC1=9 | CC2=13 | CC3 vide | CC4 vide | Exam=7. Le préfixe de matière `S2 - ` / `T2 - ` indique le semestre/trimestre ; la matière est en minuscules dans ce tableau, avec majuscule initiale dans le tableau d'absences.

### 4.4 Tableau d'absences (même page / mêmes POST)

`table` dans `marksForm:missingsWidget:missingsTable`, colonnes : `Date` ("08/04/2026 11h30" = jj/MM/aaaa HHhmm), `Matière`, `Type` ("Absence" ou retard), `Justifié` ("Oui"/"Non"). Pied : `Absences non justifiées : 3, Retards non justifiés : 0`.

```html
<tr data-ri="0" ...><td role="gridcell">08/04/2026 11h30</td><td role="gridcell" class="mg_inherit_bg"><span class="mg_inherit_color">Développement web : javascript, web api fetch et json</span></td><td role="gridcell">Absence</td><td role="gridcell" style="text-align:center;">Non</td></tr>
```

## 5. Pièges

1. `lt` et `execution` : toujours extraire de la page de login fraîche, dans la MÊME session (`JSESSIONID` CAS) que le POST. Utiliser un `URLSession` avec cookie storage actif (ou `httpCookieStorage` dédié) ; ne pas partager le stockage avec l'app.
2. Redirections : laisser URLSession suivre 302 (login POST -> ticket -> myges). Le `Set-Cookie` myges arrive sur la 302 du `j_spring_cas_security_check`. Si on désactive le suivi, il faut gérer les cookies à la main.
3. Le POST CAS doit viser l'URL avec `;jsessionid=...?service=...` (comme le navigateur) ; sans `service` le login réussit mais ne redirige pas vers myges.
4. Session expirée : myges renvoie probablement une 302 vers CAS (ou la page de login) au lieu de XML. Détecter (content-type text/html au lieu de text/xml, ou URL finale sur ges-cas) et refaire 1.x. Si `CASTGC` est encore valide, seule l'étape 4 suffit (sans mot de passe). Le JS du site considère la session morte après 7200 s d'inactivité.
5. ViewState : à relire depuis la page juste chargée, ET le réutiliser ensuite. Un POST sans GET préalable de la page échoue (ViewState expiré / `ViewExpiredException`).
6. Les ids `j_idt174`, `j_idt158` etc. sont auto-générés. Pour les notes, chercher dynamiquement le `<select name="...periodSelect_input">` (regex `name="(marksForm:[^"]*periodSelect)_input"`) plutôt que coder `j_idt174`.
7. Les ids de période (`value` des `<option>`) sont ceux de l'étudiant : à lister à chaque fois depuis la page.
8. Planning : titres tronqués dans le JSON, prof/modalité seulement via la boîte de détail (3.3, à capturer). Ordre des événements aléatoire : trier par `start`. Dates avec `+0200` sans deux-points. L'API semble sensible aux `_start`/`_end` en ms exacts de minuit local.
9. Réponse partial : parser le XML puis extraire le CDATA de `<update id="calendar:myschedule">` (JSON) ou des `<update id="marksForm:...">` (HTML). Le CDATA peut contenir `]]>` échappé en théorie ; ici non vu.
10. Décimales à virgule dans les notes (`9,75`) : convertir.
11. Colonnes de notes variables (CC1..CCn) : mapper via les en-têtes.
12. Pas d'endpoint JSON, pas d'API REST, pas d'ID client ni jeton Bearer dans la capture (grep `api.kordis` : 0 résultat). Le front est du JSF pur. Une application mobile officielle (Skolae / "myGES") existe peut-être avec une API différente, non visible ici.
13. Robustesse : l'agent a vu un cookie `Path=/; HttpOnly` sans `Secure`/`SameSite` ; pas d'en-tête CSRF particulier (le ViewState joue ce rôle). User-Agent navigateur utilisé par la capture ; non testé avec un UA personnalisé (WAF possible).
