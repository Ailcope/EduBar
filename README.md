# EduBar

**FR** · [EN](#english)

Ton emploi du temps Edusign dans la barre des menus macOS.

- En cours : `📚 Pause dans 23 min` (ou `Fin dans…` pour le dernier cours).
- En pause : `☕ Cours dans 8 min · 506`.
- 15 min avant la fin d'un cours, si le suivant est dans une autre salle : `⚠️ Salle 501 · fin dans 14 min`, plus une notification.
- Journée finie : `Demain 9h45`.
- Un clic : la journée complète, avec les salles et les pauses.

## Installation

1. Télécharge `EduBar-x.y.z.zip` depuis les [Releases](../../releases) et dézippe-le.
2. Glisse `EduBar.app` dans `Applications`.
3. L'app n'est pas notarisée par Apple. Au premier lancement : clic droit sur l'app, puis **Ouvrir**. Si macOS dit qu'elle est endommagée :
   ```sh
   xattr -dr com.apple.quarantine /Applications/EduBar.app
   ```

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

L'URL suffit à lire ton emploi du temps : elle ne contient que ton identifiant d'école et d'élève, sans mot de passe. Ne la partage pas. EduBar la garde dans le Trousseau macOS, ne l'écrit jamais dans les logs et ne parle qu'à `api.edusign.fr` (ou à l'hôte que tu donnes). Le calendrier est mis en cache dans `~/Library/Caches/EduBar/` pour marcher hors ligne.

## Compiler

Pas besoin de Xcode, les Command Line Tools suffisent (`xcode-select --install`).

```sh
swift test                 # tests
scripts/bundle.sh 0.1.0    # dist/EduBar.app + dist/EduBar-0.1.0.zip (universel, signature ad-hoc)
```

`EduBar --snapshot <dossier> [--at "2026-09-22 13:10"]` rend le popover en PNG à partir du cache, pratique pour vérifier le rendu.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE.md) · usage non commercial libre, usage commercial sur autorisation. Source disponible, pas open source.

---

## English

Your Edusign timetable in the macOS menu bar: time until the next break or class, the next room, and a heads-up 15 minutes before a class ends when the next one is in a different room. Click for the full day.

**Install:** download the zip from Releases, move `EduBar.app` to Applications, right-click and choose **Open** the first time (the app is not notarized), or run `xattr -dr com.apple.quarantine /Applications/EduBar.app`.

**Calendar URL:** log in to Edusign, open the browser console and run the snippet above. Paste the `webcal://` URL in EduBar's settings. The URL only contains your school and student IDs, so anyone who has it can read your timetable: keep it private. EduBar stores it in the macOS Keychain.

**Build:** `swift test`, then `scripts/bundle.sh <version>`. Command Line Tools only, no Xcode.

**License:** PolyForm Noncommercial 1.0.0 (source-available, noncommercial use only).
