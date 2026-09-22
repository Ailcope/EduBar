# EduBar

**FR** · [EN](#english)

Ton emploi du temps Edusign dans la barre des menus macOS.

- En cours : `📚 Pause dans 23 min` (ou `Fin dans…` pour le dernier cours).
- En pause : `☕ Cours dans 8 min · 506`.
- Pause déjeuner (1 h ou plus, entre 11h et 14h) : `🍽️ Déjeuner dans 20 min`, puis `📚 Cours dans 50 min · 501` pendant le repas.
- 15 min avant la fin d'un cours, si le suivant est dans une autre salle : `⚠️ Salle 501 · fin dans 14 min`.
- Notifications : fin de cours, début de cours, changement de salle (voir plus bas).
- Journée finie : `Demain 9h45`.
- Un clic : la journée complète, avec les salles et les pauses.
- Mises à jour : EduBar regarde une fois par jour s'il existe une nouvelle release et propose de télécharger le `.dmg` (rien ne s'installe tout seul).

L'app est livrée sans calendrier : c'est toi qui colles ton URL au premier lancement.

## Personnaliser les textes

Dans ⚙️ > **Personnaliser les textes**, chaque situation a son modèle, émojis compris : en cours avant une pause, avant le déjeuner, dernier cours, en pause, pendant le déjeuner, avant le premier cours, changement de salle, journée finie. Variables :

- `{temps}` : le temps restant (`23 min`, `1 h 05`)
- `{salle}` : la salle (`501`). Si elle est inconnue, elle disparaît avec son séparateur (`Cours dans 8 min · {salle}` devient `Cours dans 8 min`)
- `{jour}` : le prochain cours quand la journée est finie (`Demain 9h45`)

Exemple : `🏃 Go {salle} dans {temps}`. Un champ vide reprend le texte par défaut, et un bouton rétablit tout.

## Notifications

Dans ⚙️ > **Notifications**, trois notifications, chacune activable, avec son délai (0 à 60 min avant) et son titre et texte :

| Notification | Quand (par défaut) | Exemple |
|---|---|---|
| Fin de cours | 5 min avant la fin d'une suite de cours | `Fin du cours dans 5 min` · `Langage C avancé se termine à 13h. Ensuite : déjeuner.` |
| Début de cours | 5 min avant le premier cours ou la reprise | `Cours dans 5 min · 501` |
| Changement de salle | 15 min avant la fin, si le cours suivant est ailleurs | `⚠️ Changement de salle : 501` |

Variables : `{cours}`, `{heure}`, `{temps}`, `{salle}`, `{pause}` (`pause de 15 min`, `déjeuner` ou `fin de journée`). Le délai du changement de salle règle aussi l'alerte dans la barre. Le bouton **Tester** envoie un exemple tout de suite. Si rien ne s'affiche, autorise EduBar dans Réglages Système > Notifications.

## Installation

1. Télécharge `EduBar-x.y.z.dmg` depuis les [Releases](../../releases) (ou le `.zip`), ouvre-le.
2. Glisse `EduBar.app` sur le raccourci `Applications`.
3. L'app n'est pas notarisée par Apple. Au premier lancement : clic droit sur l'app, puis **Ouvrir**. Si macOS dit qu'elle est endommagée :
   ```sh
   xattr -dr com.apple.quarantine /Applications/EduBar.app
   ```
4. Après chaque mise à jour, macOS demande si EduBar peut lire son élément du Trousseau : clique **Toujours autoriser** (l'app est signée ad-hoc, macOS la voit comme une nouvelle app).

macOS 14 ou plus récent, Apple Silicon ou Intel.

## Obtenir l'URL du calendrier

1. Connecte-toi sur Edusign dans ton navigateur.
2. Ouvre la console (Cmd+Option+J sur Chrome/Brave, Cmd+Option+C sur Safari).
3. Colle et lance :
   ```js
   const schoolId = JSON.parse(localStorage.getItem('EdusignCampusStorage.school')).id;
   const userId = JSON.parse(localStorage.getItem('EdusignCampusStorage.user')).id;
   console.log(`webcal://api.edusign.fr/student/account/ical?sc=${schoolId}&st=${userId}`);
   ```
4. Copie l'URL `webcal://…` affichée, clique sur EduBar, puis ⚙️, colle-la et **Enregistrer**.

## Confidentialité

L'URL suffit à lire ton emploi du temps : elle ne contient que ton identifiant d'école et d'élève, sans mot de passe. Ne la partage pas. EduBar la garde dans le Trousseau macOS, ne l'écrit jamais dans les logs et ne parle qu'à `api.edusign.fr` (ou à l'hôte que tu donnes) et à `api.github.com` pour les mises à jour, sans rien envoyer d'autre que sa version. Le calendrier est mis en cache dans `~/Library/Caches/EduBar/` pour marcher hors ligne.

## Compiler

Pas besoin de Xcode, les Command Line Tools suffisent (`xcode-select --install`).

```sh
swift test                 # tests
scripts/bundle.sh 0.1.0    # dist/EduBar.app + .zip + .dmg (universel, signature ad-hoc)
```

Si `swift test` échoue avec `plugin for module 'TestingMacros' not found` (Command Line Tools récents), donne le chemin du plugin :

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

Pour publier une version : `scripts/bundle.sh x.y.z`, puis une release GitHub `vx.y.z` avec le `.dmg`. Les apps installées la verront dans la journée.

L'icône vient de `Resources/AppIcon.svg` : après une modif, `scripts/make-icon.sh` régénère `Resources/AppIcon.icns`.

`EduBar --snapshot <dossier> [--at "2026-09-22 13:10"]` rend le popover en PNG à partir du cache, pratique pour vérifier le rendu.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE.md) · usage non commercial libre, usage commercial sur autorisation. Source disponible, pas open source.

---

## English

Your Edusign timetable in the macOS menu bar: time until the next break or class, the next room, and a heads-up 15 minutes before a class ends when the next one is in a different room. Lunch breaks are labeled as such. Notifications for class end, class start and room changes, each with its own toggle, lead time (0 to 60 min) and text, plus a Test button. Every menu bar text and emoji can be customized in the settings with `{temps}`, `{salle}` and `{jour}` placeholders. Click for the full day. Ships without any calendar URL; EduBar checks GitHub once a day for a new release and offers the dmg.

**Install:** download the dmg (or zip) from Releases, drag `EduBar.app` to Applications, right-click and choose **Open** the first time (the app is not notarized), or run `xattr -dr com.apple.quarantine /Applications/EduBar.app`.

**Calendar URL:** log in to Edusign, open the browser console and run the snippet above. Paste the `webcal://` URL in EduBar's settings. The URL only contains your school and student IDs, so anyone who has it can read your timetable: keep it private. EduBar stores it in the macOS Keychain.

**Build:** `swift test`, then `scripts/bundle.sh <version>`. Command Line Tools only, no Xcode.

**License:** PolyForm Noncommercial 1.0.0 (source-available, noncommercial use only).
