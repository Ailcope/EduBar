<div align="center" markdown="1">

# EduBar

[![Release](https://img.shields.io/github/v/release/Ailcope/EduBar?label=Release&logo=github&logoColor=white&color=blue)](https://github.com/Ailcope/EduBar/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![macOS 14+](https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License: PolyForm NC](https://img.shields.io/badge/License-PolyForm%20NC-orange.svg?logo=opensourceinitiative&logoColor=white)](./LICENSE.md)

**Ton emploi du temps Edusign dans la barre des menus macOS, en Swift natif, sans Xcode.**
**Your Edusign timetable in the macOS menu bar, native Swift, no Xcode.**

Works with **Edusign** &bull; **SwiftUI** &bull; **macOS Notifications**

[🇫🇷 Français](#-français) &bull; [🇬🇧 English](#-english)

</div>

---

<a id="-français"></a>

## 🇫🇷 Français

### Aperçu

**EduBar** est une petite app pour la barre des menus macOS qui lit ton emploi du temps Edusign et te dit d'un coup d'œil combien de temps avant la prochaine pause ou le prochain cours, et dans quelle salle aller. Un clic affiche la journée complète, avec les salles et les pauses. Elle prévient 15 minutes avant la fin d'un cours quand le suivant est dans une autre salle, et envoie des notifications de fin de cours, de début de cours et de changement de salle. Elle est livrée sans calendrier : tu colles ton URL au premier lancement, et elle reste sur ton Mac.

### Fonctionnalités

- **Coup d'œil dans la barre.** `📚 Pause dans 23 min` en cours (`Fin dans…` pour le dernier), `☕ Cours dans 8 min · 506` en pause, `Demain 9h45` une fois la journée finie.
- **Pause déjeuner.** Une pause d'1 h ou plus entre 11h et 14h s'affiche comme le déjeuner : `🍽️ Déjeuner dans 20 min`, puis `📚 Cours dans 50 min · 501` pendant le repas.
- **Changement de salle.** 15 min avant la fin d'un cours, si le suivant est ailleurs : `⚠️ Salle 501 · fin dans 14 min`.
- **Notifications.** Fin de cours, début de cours et changement de salle, chacune activable, avec son délai (0 à 60 min), son titre et son texte, et un bouton **Tester**.
- **Changements d'emploi du temps.** Un cours annulé, déplacé, ajouté ou changé de salle dans les deux semaines à venir envoie une notification : `❌ Cours annulé · demain 14h`, `🔁 Cours déplacé · …`, `📍 Salle changée · 501`.
- **Jours suivants.** Les flèches ‹ › du menu passent d'un jour à l'autre (les week-ends vides sont sautés), **Revenir** ramène à aujourd'hui.
- **Examens.** Un cours dont le titre parle d'examen, partiel, DS, contrôle, soutenance, QCM ou rattrapage a un badge orange, et la barre prévient la veille : `📝 Examen demain 9h · 501`.
- **Alternance.** Dans ⚙️ > **Alternance** : jours fixes en entreprise, semaines alternées (2 semaines d'école, 2 en entreprise…) ou détection automatique des jours sans cours. Ces jours-là : `🏢 Entreprise · école Lun. 9h`.
- **Raccourcis.** Dans ⚙️ > **Raccourcis**, un raccourci de l'app Raccourcis se lance quand les cours commencent et quand ils finissent (mode Concentration, son coupé…).
- **Statistiques.** Heures de la semaine (faites et prévues), prochains examens, progression par matière.
- **Ajouter à Calendrier.** Un bouton abonne l'app Calendrier au flux Edusign : les cours y apparaissent et restent à jour.
- **Textes personnalisables.** Chaque texte de la barre et ses émojis se réécrivent, avec les variables `{temps}`, `{salle}` et `{jour}`.
- **Hors ligne.** Le calendrier est mis en cache dans `~/Library/Caches/EduBar/`, l'app marche sans réseau.
- **Mises à jour.** EduBar regarde une fois par jour s'il existe une nouvelle release et l'installe toute seule : téléchargement vérifié (empreinte SHA-256 publiée par GitHub, identifiant, version et signature), remplacement de l'app, relance. Les réglages sont conservés. Un clic sur la notification « EduBar mis à jour » ouvre les nouveautés. Lancée depuis le `.dmg`, elle propose **Installer dans Applications** : copie, relance depuis Applications et éjection de l'image disque.

### Installation

1. Télécharge `EduBar-x.y.z.dmg` (ou le `.zip`) depuis les [Releases](https://github.com/Ailcope/EduBar/releases) et ouvre-le.
2. Glisse `EduBar.app` sur le raccourci `Applications`, puis éjecte le `.dmg`. Lancée depuis le `.dmg`, l'app empêche de l'éjecter et ne peut pas se mettre à jour : le bouton **Installer dans Applications** du menu règle ça.
3. L'app n'est pas notarisée par Apple. Au premier lancement : clic droit sur l'app, puis **Ouvrir**. Si macOS dit qu'elle est endommagée :
   ```sh
   xattr -dr com.apple.quarantine /Applications/EduBar.app
   ```
4. En venant de la 0.3.2 ou avant : macOS demande une dernière fois si EduBar peut lire son ancien élément du Trousseau. Clique **Toujours autoriser**, l'URL passe ensuite dans un fichier et survit à toutes les mises à jour.

macOS 14 ou plus récent, Apple Silicon ou Intel.

### Obtenir l'URL du calendrier

1. Connecte-toi sur Edusign dans ton navigateur.
2. Ouvre la console (Cmd+Option+J sur Chrome/Brave, Cmd+Option+C sur Safari).
3. Colle et lance :
   ```js
   const schoolId = JSON.parse(localStorage.getItem('EdusignCampusStorage.school')).id;
   const userId = JSON.parse(localStorage.getItem('EdusignCampusStorage.user')).id;
   console.log(`webcal://api.edusign.fr/student/account/ical?sc=${schoolId}&st=${userId}`);
   ```
4. Copie l'URL `webcal://…` affichée, clique sur EduBar, puis ⚙️, colle-la et **Enregistrer**.

### Personnaliser les textes

Dans ⚙️ > **Personnaliser les textes**, chaque situation a son modèle, émojis compris : en cours avant une pause, avant le déjeuner, dernier cours, en pause, pendant le déjeuner, avant le premier cours, changement de salle, journée finie, examen proche, journée en entreprise.

| Variable | Contenu |
|---|---|
| `{temps}` | le temps restant (`23 min`, `1 h 05`) |
| `{salle}` | la salle (`501`). Inconnue, elle disparaît avec son séparateur : `Cours dans 8 min · {salle}` devient `Cours dans 8 min` |
| `{jour}` | le prochain cours quand la journée est finie (`Demain 9h45`) |

Exemple : `🏃 Go {salle} dans {temps}`. Un champ vide reprend le texte par défaut, et un bouton rétablit tout.

### Notifications

Dans ⚙️ > **Notifications**, trois notifications, chacune activable, avec son délai (0 à 60 min avant), son titre et son texte :

| Notification | Quand (par défaut) | Exemple |
|---|---|---|
| Fin de cours | 5 min avant la fin d'une suite de cours | `Fin du cours dans 5 min` · `Langage C avancé se termine à 13h. Ensuite : déjeuner.` |
| Début de cours | 5 min avant le premier cours ou la reprise | `Cours dans 5 min · 501` |
| Changement de salle | 15 min avant la fin, si le cours suivant est ailleurs | `⚠️ Changement de salle : 501` |

Variables : `{cours}`, `{heure}`, `{temps}`, `{salle}`, `{pause}` (`pause de 15 min`, `déjeuner` ou `fin de journée`). Le délai du changement de salle règle aussi l'alerte dans la barre. Le bouton **Tester** envoie un exemple tout de suite. Si rien ne s'affiche, autorise EduBar dans Réglages Système > Notifications.

### Confidentialité

L'URL suffit à lire ton emploi du temps : elle ne contient que ton identifiant d'école et d'élève, sans mot de passe. Ne la partage pas. EduBar la garde dans `~/Library/Application Support/EduBar/feed-url`, lisible par ta session seulement (0600), ne l'écrit jamais dans les logs et ne parle qu'à `api.edusign.fr` (ou à l'hôte que tu donnes) et à `api.github.com` pour les mises à jour, sans rien envoyer d'autre que sa version. Avec **Ajouter à Calendrier**, c'est l'app Calendrier qui lit ensuite l'URL elle-même.

### Compiler

Pas besoin de Xcode, les Command Line Tools suffisent (`xcode-select --install`).

```sh
swift test                 # tests
scripts/bundle.sh 0.1.0    # dist/EduBar.app + .zip + .dmg (universel, signature ad-hoc)
```

Si `swift test` échoue avec `plugin for module 'TestingMacros' not found` (Command Line Tools récents), donne le chemin du plugin :

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

- **Publier :** `scripts/bundle.sh x.y.z`, puis une release GitHub `vx.y.z` avec le `.dmg` et le `.zip` (le `.zip` sert à la mise à jour automatique). Les apps installées se mettent à jour dans la journée.
- **Icône :** elle vient de `Resources/AppIcon.svg`. Après une modif, `scripts/make-icon.sh` régénère `Resources/AppIcon.icns`.
- **Rendu :** `EduBar --snapshot <dossier> [--at "2026-09-22 13:10"]` rend le popover en PNG à partir du cache.

### Licence

[PolyForm Noncommercial 1.0.0](./LICENSE.md) · libre d'utilisation, modification et partage à des fins **non commerciales**. Tout usage commercial ou revente du code nécessite l'accord de l'auteur.

---

<a id="-english"></a>

## 🇬🇧 English

### Overview

**EduBar** is a small macOS menu bar app that reads your Edusign timetable and tells you, at a glance, how long until the next break or class and which room to go to. Click it for the full day, with rooms and breaks. It warns you 15 minutes before a class ends when the next one is in a different room, and sends notifications for class end, class start and room changes. It ships without any calendar URL: you paste yours on first launch, and it stays on your Mac.

### Features

- **Menu bar at a glance.** `📚 Pause dans 23 min` during class, `☕ Cours dans 8 min · 506` on a break, `Demain 9h45` once the day is over.
- **Lunch aware.** A break of one hour or more between 11:00 and 14:00 is shown as lunch: `🍽️ Déjeuner dans 20 min`.
- **Room changes.** 15 minutes before a class ends, if the next one is elsewhere: `⚠️ Salle 501 · fin dans 14 min`.
- **Notifications.** Class end, class start and room change, each with its own toggle, lead time (0 to 60 min), title and text, plus a **Test** button.
- **Timetable changes.** A class cancelled, moved, added or moved to another room within the next two weeks triggers a notification.
- **Next days.** The ‹ › arrows browse the following days (empty weekends are skipped), **Revenir** goes back to today.
- **Exams.** Classes whose title mentions an exam, partiel, DS, contrôle, soutenance, QCM or rattrapage get an orange badge, and the menu bar warns the day before: `📝 Examen demain 9h · 501`.
- **Work-study.** In ⚙️ > **Alternance**: fixed company weekdays, alternating weeks, or automatic detection of days without classes. On those days: `🏢 Entreprise · école Lun. 9h`.
- **Shortcuts.** In ⚙️ > **Raccourcis**, run a Shortcuts shortcut when classes start and when they end.
- **Stats.** Hours this week (done and planned), upcoming exams, progress per subject.
- **Add to Calendar.** One button subscribes the Calendar app to the Edusign feed.
- **Custom texts.** Every menu bar text and emoji can be rewritten, with `{temps}`, `{salle}` and `{jour}` placeholders.
- **Offline.** The timetable is cached locally, so the app keeps working without network.
- **Updates.** Checks GitHub once a day and installs new releases by itself: verified download (GitHub's SHA-256 digest, bundle id, version and signature), in-place replacement, relaunch. Settings are kept. Clicking the "updated" notification opens the release notes. When run from the `.dmg`, it offers **Installer dans Applications**: copy, relaunch from Applications and eject the disk image.

### Install

1. Download `EduBar-x.y.z.dmg` (or the `.zip`) from the [Releases](https://github.com/Ailcope/EduBar/releases) and open it.
2. Drag `EduBar.app` onto the `Applications` shortcut, then eject the `.dmg`. Run from the `.dmg`, the app blocks the eject and cannot update itself: the **Installer dans Applications** button in the menu fixes that.
3. The app is not notarized. On first launch, right-click it and choose **Open**. If macOS says it is damaged:
   ```sh
   xattr -dr com.apple.quarantine /Applications/EduBar.app
   ```
4. Updating from 0.3.2 or older: macOS asks once whether EduBar may read its old Keychain item. Click **Always Allow**, the URL then moves to a file and survives every later update.

Requires macOS 14 or later, Apple Silicon or Intel.

### Calendar URL

1. Log in to Edusign in your browser.
2. Open the console (Cmd+Option+J on Chrome/Brave, Cmd+Option+C on Safari).
3. Paste and run:
   ```js
   const schoolId = JSON.parse(localStorage.getItem('EdusignCampusStorage.school')).id;
   const userId = JSON.parse(localStorage.getItem('EdusignCampusStorage.user')).id;
   console.log(`webcal://api.edusign.fr/student/account/ical?sc=${schoolId}&st=${userId}`);
   ```
4. Copy the `webcal://…` URL, click EduBar, then ⚙️, paste it and hit **Enregistrer**.

### Configuration

Everything lives in ⚙️:

- **Notifications:** three notifications, each with a toggle, a lead time and its own title and text.
- **Personnaliser les textes:** one template per situation (before a break, before lunch, last class, on a break, at lunch, before the first class, room change, day over, exam soon, company day).

| Notification | When (default) | Example |
|---|---|---|
| Class end | 5 min before a run of classes ends | `Fin du cours dans 5 min` · `Langage C avancé se termine à 13h. Ensuite : déjeuner.` |
| Class start | 5 min before the first class or after a break | `Cours dans 5 min · 501` |
| Room change | 15 min before the end, if the next class is elsewhere | `⚠️ Changement de salle : 501` |

Notification placeholders: `{cours}`, `{heure}`, `{temps}`, `{salle}`, `{pause}`. An empty field falls back to the default text. If nothing shows up, allow EduBar in System Settings > Notifications.

### Privacy

The URL is enough to read your timetable: it only holds your school and student IDs, no password. Keep it private. EduBar stores it in `~/Library/Application Support/EduBar/feed-url`, readable by your user only (0600), never writes it to logs, and only talks to `api.edusign.fr` (or the host you give it) and to `api.github.com` for updates, sending nothing but its version. With **Add to Calendar**, the Calendar app then reads the URL itself.

### Build

Command Line Tools only (`xcode-select --install`), no Xcode.

```sh
swift test                 # tests
scripts/bundle.sh 0.1.0    # dist/EduBar.app + .zip + .dmg (universal, ad-hoc signed)
```

### License

[PolyForm Noncommercial 1.0.0](./LICENSE.md) · free to use, modify and share for **noncommercial** purposes. Commercial use or reselling the code requires the author's permission.
