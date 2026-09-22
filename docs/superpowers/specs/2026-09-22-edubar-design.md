# EduBar · design

Date : 2026-09-22

## But

App macOS de barre des menus qui lit un calendrier Edusign (`webcal://api.edusign.fr/student/account/ical?...`) et répond d'un coup d'œil à « c'est quand la pause / le prochain cours, et dans quelle salle ? ».

## Contraintes

- Pas de Xcode, pas de compte Apple Developer : Swift Package + Command Line Tools, `.app` assemblé par script, signature ad-hoc.
- macOS 14+ (`MenuBarExtra`, `SMAppService`).
- Dépôt privé pour l'instant, release publique prévue : aucune URL/token Edusign dans le dépôt, fixtures anonymisées.
- Licence PolyForm Noncommercial 1.0.0.

## Observations sur le flux Edusign

- `VEVENT` avec `UID`, `DTSTART`/`DTEND` en UTC (`20260922T074500Z`), `SUMMARY`, `LOCATION` optionnel.
- `LOCATION` présent sur ~30 % des cours seulement.
- Pas d'événement « pause » : les pauses sont les trous entre deux cours consécutifs du même jour.
- Titres préfixés `T1 - ` (trimestre) : affichés tels quels dans le popover, préfixe retiré dans la barre.

## Architecture

Deux cibles SwiftPM :

- `EduBarCore` (bibliothèque, sans UI, testée)
  - `ICSParser` : `String -> [Course]`. Déplie les lignes (RFC 5545 : ligne suivante commençant par espace/tab), déséchappe `\,` `\;` `\n` `\\`, lit les dates UTC (`...Z`), locales avec `TZID` et date seule (`VALUE=DATE`, ignorées : pas un cours). Événements sans début/fin ignorés.
  - `Course` : `id`, `title`, `start`, `end`, `room: String?`, `shortTitle` (sans préfixe `T1 - `).
  - `Schedule` : `status(at: Date, calendar: Calendar) -> Status`, fonction pure.
  - `Status` :
    - `.inClass(current, next: Course?, blockEnd, breakFollows)` : en cours ; `next` = cours suivant du même jour ; `blockEnd` = fin du bloc de cours contigus ; `breakFollows` = un cours suit plus tard dans la journée.
    - `.onBreak(previous, next)` : entre deux cours du même jour.
    - `.beforeFirst(next)` : aujourd'hui, avant le premier cours.
    - `.dayOver(next: Course?)` / `.noClassToday(next: Course?)` : `next` = prochain cours futur, quel que soit le jour.
  - `RoomChange` : `roomAlert(status, at:, lead: 15 min) -> RoomAlert?`. Alerte si en cours, fin dans ≤ 15 min, cours suivant le même jour, salle suivante connue et différente de la salle actuelle (ou salle actuelle inconnue).
  - `Display` : texte de la barre et durées (`23 min`, `1 h 05`).
  - `FeedURL` : normalise `webcal://` → `https://`, valide l'hôte, masque les paramètres pour les logs.
- `EduBar` (exécutable SwiftUI)
  - `CalendarStore` (`@MainActor ObservableObject`) : télécharge le flux toutes les 15 min, cache disque (`~/Library/Caches/EduBar/calendar.ics`), garde les derniers cours valides si le réseau tombe, expose `lastError`.
  - `Clock` : tick toutes les 30 s (aligné sur la minute) pour rafraîchir le texte.
  - `Notifier` : `UNUserNotificationCenter`, une seule notification par cours (clé = `course.id`).
  - `SettingsStore` : URL dans le Keychain, lancement au démarrage via `SMAppService.mainApp`.
  - UI : `MenuBarExtra` (style `.window`) avec label texte, popover journée, fenêtre réglages.

## Texte de la barre

| État | Texte |
|---|---|
| En cours, alerte salle active (≤ 15 min avant la fin) | `⚠️ Salle 501 · fin dans 14 min` |
| En cours, cours suivant aujourd'hui | `📚 Pause dans 23 min` |
| En cours, dernier cours du jour | `📚 Fin dans 23 min` |
| En pause | `☕ Cours dans 8 min · 501` (salle omise si inconnue) |
| Avant le premier cours | `Cours dans 1 h 05 · 506` |
| Journée finie / pas de cours | `Demain 8h45`, `Lun. 8h45`, ou icône seule si aucun cours à venir |
| Pas d'URL configurée | icône + « Configurer » dans le popover |

## Popover

- En-tête : date du jour, statut en une ligne.
- Timeline du jour : chaque cours (heures, titre, salle), cours actuel mis en évidence, cours passés grisés, pauses affichées entre deux cours (« Pause 15 min »).
- Si aucun cours aujourd'hui : prochain jour de cours.
- Pied : dernière mise à jour / erreur, boutons Rafraîchir, Réglages, Quitter.

## Réglages

- Champ URL (webcal ou https), bouton « Tester » (télécharge et compte les cours).
- Case « Lancer au démarrage ».
- Case « Notifier les changements de salle ».

## Erreurs

- URL invalide : message dans les réglages, pas de requête.
- Échec réseau / HTTP ≠ 200 : on garde le cache, `lastError` affichée dans le pied du popover.
- ICS vide ou illisible : idem, le cache n'est pas écrasé.

## Tests

- `ICSParser` : fixture anonymisée (lignes pliées, accents, sans `LOCATION`, `TZID`, date seule).
- `Schedule` : en cours, pause, avant premier, dernier cours, journée finie, week-end, cours qui se touchent (pas de pause de 0 min).
- `RoomChange` : même salle, salle différente, salle suivante inconnue, salle actuelle inconnue, hors fenêtre de 15 min, cours suivant le lendemain.
- `Display` : durées et textes de la barre.
- `FeedURL` : webcal → https, rejets.

## Build et release

- `swift test`, `swift build -c release`.
- `scripts/bundle.sh` : crée `dist/EduBar.app` (Info.plist `LSUIElement`, `CFBundleIdentifier` `dev.ailcope.edubar`), `codesign --sign -`, zip.
- README FR/EN avec contournement Gatekeeper (clic droit → Ouvrir, ou `xattr -dr com.apple.quarantine`).

## Hors périmètre (YAGNI)

Plusieurs calendriers, widgets, iOS, édition des cours, statistiques de présence.
