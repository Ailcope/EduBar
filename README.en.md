<div align="center" markdown="1">

# EduBar

[![Release](https://img.shields.io/github/v/release/Ailcope/EduBar?label=Release&logo=github&logoColor=white&color=blue)](https://github.com/Ailcope/EduBar/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![macOS 14+](https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![License: PolyForm NC](https://img.shields.io/badge/License-PolyForm%20NC-orange.svg?logo=opensourceinitiative&logoColor=white)](./LICENSE.md)

**Your myGES timetable and grades in the macOS menu bar, native Swift, no Xcode.**

Works with **myGES** (or an Edusign iCal feed) &bull; **SwiftUI** &bull; **macOS Notifications**

[🇫🇷 FR](README.md) &bull; **🇬🇧 EN**

</div>

---

## Contents

- [Overview](#overview)
- [Features](#features)
- [Install](#install)
- [Connect myGES](#connect-myges)
- [Configuration](#configuration)
- [Privacy](#privacy)
- [Build](#build)
- [License](#license)

## Overview

**EduBar** is a small macOS menu bar app that reads your myGES timetable and tells you, at a glance, how long until the next break or class and which room to go to. Click it for the full day, with rooms and breaks; another click shows your grades, subject by subject, with a notification as soon as a new one lands. It warns you 15 minutes before a class ends when the next one is in a different room, and sends notifications for class end, class start and room changes. It ships without any account: you enter your myGES credentials on first launch (or an Edusign iCal URL), and they stay on your Mac.

## Features

Screenshots show made-up subjects, rooms, names and weather (`EduBar --snapshot <dir> --demo`).

- **Menu bar at a glance.** `📚 Pause dans 23 min` during class, `☕ Cours dans 8 min · 506` on a break, `Demain 9h45` once the day is over.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/bar-glance-dark.png"><img src="docs/screenshots/bar-glance.png" width="203" alt="Menu bar texts through the day"></picture>

- **Lunch aware.** A break of one hour or more between 11:00 and 14:00 is shown as lunch: `🍽️ Déjeuner dans 20 min`.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/bar-lunch-dark.png"><img src="docs/screenshots/bar-lunch.png" width="209" alt="Before and during lunch"></picture>

- **Room changes.** 15 minutes before a class ends, if the next one is elsewhere: `⚠️ Salle 501 · fin dans 14 min`.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/bar-room-dark.png"><img src="docs/screenshots/bar-room.png" width="220" alt="Room change alert"></picture>

- **Notifications.** Class end, class start and room change, each with its own toggle, lead time (0 to 60 min), title and text, plus a **Test** button.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel-notifications-dark.png"><img src="docs/screenshots/panel-notifications.png" width="340" alt="Notification settings"></picture>

- **Timetable changes.** A class cancelled, moved, added or moved to another room within the next two weeks triggers a notification.
- **Next days.** The ‹ › arrows browse the following days (empty weekends are skipped), **Revenir** goes back to today.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/day-dark.png"><img src="docs/screenshots/day.png" width="340" alt="The day"></picture>

- **Week view.** The calendar button at the bottom of the day opens the week as a grid, one column per day and one coloured block per course. Arrows browse nearby weeks, clicking a day opens it.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/week-dark.png"><img src="docs/screenshots/week.png" width="420" alt="The week"></picture>

- **Exams.** Classes whose title mentions an exam, partiel, DS, contrôle, soutenance, QCM or rattrapage get an orange badge, and the menu bar warns the day before: `📝 Examen demain 9h · 501`.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/bar-exam-dark.png"><img src="docs/screenshots/bar-exam.png" width="210" alt="Exam tomorrow"></picture>

- **Work-study.** In ⚙️ > **Alternance**: fixed company weekdays, alternating weeks, or automatic detection of days without classes. On those days: `🏢 Entreprise · école Lun. 9h`.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/bar-company-dark.png"><img src="docs/screenshots/bar-company.png" width="217" alt="Company day"></picture>

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel-alternance-dark.png"><img src="docs/screenshots/panel-alternance.png" width="340" alt="Work-study settings"></picture>

- **Shortcuts.** In ⚙️ > **Raccourcis**, run a Shortcuts shortcut when classes start and when they end.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel-shortcuts-dark.png"><img src="docs/screenshots/panel-shortcuts.png" width="340" alt="Shortcuts settings"></picture>

- **Stats.** Hours this week (done and planned), hours done this month, upcoming exams, progress per subject.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/stats-dark.png"><img src="docs/screenshots/stats.png" width="340" alt="Stats"></picture>

- **Hours report.** In the stats, **Copier le relevé d'heures** copies the hours done per month and per subject, ready to paste into a spreadsheet (Numbers, Excel, Sheets).
- **Subject colors.** Each subject gets its own color, the same in the day view and in the stats (orange stays for exams).
- **Holidays and breaks.** A gap of 7 days or more shows up under the day: `Vacances dans 12 jours`, then `Vacances · reprise lun. 02/11`. French public holidays of the week are listed to explain the gaps: `Férié mer. 11/11 · Armistice`.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/holiday-dark.png"><img src="docs/screenshots/holiday.png" width="340" alt="Public holiday this week"></picture>

- **Shared breaks.** In ⚙️ > **Pauses communes**, paste the Edusign URL of up to 3 friends (they get it the same way you do), with their first name: the day view shows `Alex finit à 15h30` and the breaks you share, for each of them.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel-friend-dark.png"><img src="docs/screenshots/panel-friend.png" width="340" alt="Shared breaks settings"></picture>

- **Weekend.** During the last class of the week (no class or company day left afterwards): `🎉 Week-end dans 1 h 15`. The text can be rewritten, or turned off in ⚙️ > **Personnaliser les textes**.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/bar-weekend-dark.png"><img src="docs/screenshots/bar-weekend.png" width="194" alt="Weekend countdown"></picture>

- **Weather.** In ⚙️ > **Météo**, pick your city: when the next class is far away (12 h or more by default, adjustable), the menu bar shows `🌤️ 23°` instead and the day view opens on the current weather and a 5-day forecast. Data from [Open-Meteo](https://open-meteo.com), no key, no account. The search lists French cities first. Tick **Toujours en haut de la journée** (always at the top of the day) to keep the weather card at the top of the menu even during class; the bar still follows the threshold. It reloads by itself at the delay you pick (15 min to 3 h), or only with the menu's ↻ button if you turn automatic refresh off. Off by default.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/bar-weather-dark.png"><img src="docs/screenshots/bar-weather.png" width="81" alt="Weather in the menu bar"></picture>

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/weather-dark.png"><img src="docs/screenshots/weather.png" width="340" alt="Weather when the next class is far away"></picture>

- **Two cities.** The displayed city (home, work) and the campus one, if different: the first feeds the menu bar and the day view, the second the rain alert.
- **Rain alert.** In ⚙️ > **Météo**, a notification 30 min before the last class of the day ends if rain is likely when you leave: `🌧️ Pluie probable à la sortie`. Lead time (5 min to 2 h) and threshold (50 % by default) are adjustable, nothing is sent when it stays dry. Off by default.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel-weather-dark.png"><img src="docs/screenshots/panel-weather.png" width="340" alt="Weather, two cities and rain alert settings"></picture>

- **Keyboard shortcut.** ⌥⌘E opens and closes the menu from any app, no Accessibility permission needed. Change or disable it in ⚙️.
- **Copy diagnostics.** A button at the bottom of the settings copies the version, app location, quarantine and calendar state for a bug report. Never the URL.
- **Grades.** The 🎓 button lists this year's subjects: average, every continuous-assessment mark, exam, coefficient and ECTS, with new marks highlighted. As soon as a grade appears on myGES, a notification: `Nouvelle note : Sécurité des réseaux` · `CC2 : 15,5/20`. Can be turned off in ⚙️ > **Notifications**.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/grades-dark.png"><img src="docs/screenshots/grades.png" width="340" alt="Grades by subject"></picture>

- **Add to Calendar.** With the iCal source, one button subscribes the Calendar app to the Edusign feed.
- **Custom texts.** Every menu bar text and emoji can be rewritten, with `{temps}`, `{salle}` and `{jour}` placeholders.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel-templates-dark.png"><img src="docs/screenshots/panel-templates.png" width="340" alt="Custom texts"></picture>

- **Offline.** The timetable is cached locally, so the app keeps working without network.
- **Stale source.** If the timetable could not be refreshed for more than 24 h, the menu bar shows `⚠︎` and the day view says since when. An empty answer while courses are still planned is ignored: known courses stay.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/bar-stale-dark.png"><img src="docs/screenshots/bar-stale.png" width="136" alt="Timetable may be stale"></picture>

- **Past days kept.** myGES is only read a few weeks around today and Edusign drops yesterday from the feed: EduBar archives every past day locally (400 days, 0600), so browsing back and stats stay complete.
- **Updates.** Checks GitHub every 6 hours and installs new releases by itself: verified download (GitHub's SHA-256 digest, bundle id, version and signature), in-place replacement, relaunch. Settings are kept. Clicking the "updated" notification opens the release notes. When run from the `.dmg`, it offers **Installer**: copy, relaunch from Applications and eject the disk image. If it cannot replace itself, a notification announces the new version and links to the download.

## Install

1. Download `EduBar-x.y.z.dmg` (or the `.zip`) from the [Releases](https://github.com/Ailcope/EduBar/releases) and open it.
2. Drag `EduBar.app` onto the `Applications` shortcut, then eject the `.dmg`. Run from the `.dmg`, the app blocks the eject and cannot update itself: the **Installer** button in the menu fixes that.
3. The app is not notarized. On first launch, right-click it and choose **Open**. If macOS says it is damaged:
   ```sh
   xattr -dr com.apple.quarantine /Applications/EduBar.app
   ```
4. Updating from 0.3.2 or older: macOS asks once whether EduBar may read its old Keychain item. Click **Always Allow**, the URL then moves to a file and survives every later update.

Requires macOS 14 or later, Apple Silicon or Intel.

## Connect myGES

1. Click EduBar, then ⚙️ > **Compte myGES**.
2. Enter your myGES username (`f.lastname`) and password, then **Se connecter**. EduBar checks them against myGES, loads the next 8 weeks of timetable and this year's grades.
3. Done: the **Compte myGES** source is selected in ⚙️ > **Calendrier**. **Oublier ce compte** wipes the credentials and grades from this Mac.

  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/panel-account-dark.png"><img src="docs/screenshots/panel-account.png" width="340" alt="myGES account settings"></picture>

For diagnostics, `EduBar --myges-dump` (from `/Applications/EduBar.app/Contents/MacOS/`) prints the raw myGES answers (years, agenda, grades), never the token or the credentials.

### Or an iCal feed (Edusign)

Without a myGES account, pick **Flux iCal (Edusign)** in ⚙️ > **Calendrier**:

1. Log in to Edusign in your browser.
2. Open the console (Cmd+Option+J on Chrome/Brave, Cmd+Option+C on Safari).
3. Paste and run:
   ```js
   const schoolId = JSON.parse(localStorage.getItem('EdusignCampusStorage.school')).id;
   const userId = JSON.parse(localStorage.getItem('EdusignCampusStorage.user')).id;
   console.log(`webcal://api.edusign.fr/student/account/ical?sc=${schoolId}&st=${userId}`);
   ```
4. Copy the `webcal://…` URL, click EduBar, then ⚙️, paste it and hit **Enregistrer**.

## Configuration

Everything lives in ⚙️:

- **Notifications:** three notifications, each with a toggle, a lead time and its own title and text.
- **Personnaliser les textes:** one template per situation (before a break, before lunch, last class, on a break, at lunch, before the first class, room change, day over, exam soon, company day).

| Notification | When (default) | Example |
|---|---|---|
| Class end | 5 min before a run of classes ends | `Fin du cours dans 5 min` · `Langage C avancé se termine à 13h. Ensuite : déjeuner.` |
| Class start | 5 min before the first class or after a break | `Cours dans 5 min · 501` |
| Room change | 15 min before the end, if the next class is elsewhere | `⚠️ Changement de salle : 501` |
| New grade | as soon as a grade appears on myGES (checked every 15 min) | `Nouvelle note : Sécurité des réseaux` · `CC2 : 15,5/20` |

Notification placeholders: `{cours}`, `{heure}`, `{temps}`, `{salle}`, `{pause}`. An empty field falls back to the default text. If nothing shows up, allow EduBar in System Settings > Notifications.

## Privacy

**myGES account.** Your credentials are only used to get a token from myGES (`authentication.kordis.fr`, the same API as the official mobile app); the token then reads your agenda and grades on `api.kordis.fr`. They are stored in `~/Library/Application Support/EduBar/myges-credentials`, readable by your user only (0600), never written to logs nor sent anywhere else; the token only lives in memory. Grades are cached in the same folder (`grades.json`, 0600). **Oublier ce compte** wipes it all. The app is ad-hoc signed, which is why it does not use the Keychain: it would ask for access again after every update.

**iCal feed.** The URL is enough to read your timetable: it only holds your school and student IDs, no password. Keep it private. EduBar stores it in `~/Library/Application Support/EduBar/feed-url` (0600), never writes it to logs, and only talks to `api.edusign.fr` (or the host you give it). With **Add to Calendar**, the Calendar app then reads the URL itself.

In both cases, EduBar also talks to `api.github.com` for updates (sending nothing but its version) and to `edu.mathys.cc` for the anonymous signal described below.

**Anonymous usage signal.** At most once a day, EduBar sends `edu.mathys.cc` a random identifier generated by the server (kept in `~/Library/Application Support/EduBar/installation`, 0600, unrelated to you) and its version number. Nothing else: no URL, no calendar, no name. The server only keeps a hash of the identifier, the day and the version; presence records are deleted after 35 days and no IP address is stored. It only serves to know how many people use EduBar. To turn it off: **Réglages › Application › Compter cette installation (anonyme)** (the app is in French), untick it, and nothing is sent anymore.

For shared breaks, your friend's URL follows the same rules: they give it to you themselves, it stays in `~/Library/Application Support/EduBar/friend-url` (0600) and their cached timetable never leaves your Mac. Clear the field and hit **Enregistrer** to forget it.

Weather is off by default. Once enabled, EduBar also talks to Open-Meteo (`geocoding-api.open-meteo.com` to find the city, `api.open-meteo.com` for the forecast): it only sends the searched name and the city's coordinates rounded to a hundredth of a degree, never your timetable, and only when the weather has to be shown. The rain alert adds one request per school day, right before you leave, for the campus city.

## Build

Command Line Tools only (`xcode-select --install`), no Xcode.

```sh
swift test                 # tests
scripts/bundle.sh 0.1.0    # dist/EduBar.app + .zip + .dmg (universal, ad-hoc signed)
```

## License

[PolyForm Noncommercial 1.0.0](./LICENSE.md) · free to use, modify and share for **noncommercial** purposes. Commercial use or reselling the code requires the author's permission.
