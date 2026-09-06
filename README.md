# TanaSR

Spaced Repetition für die `#sr`-Karten aus Tana. Zwei Clients auf derselben
Datenbasis:

- `docs/` — **PWA** (Web-App, läuft über GitHub Pages, installierbar auf dem
  Homescreen). Läuft nie ab.
- `TanaSR/` — die native iOS-App (SwiftUI). Braucht alle 7 Tage eine neue
  Signatur, wenn sie mit einem kostenlosen Apple-Account sideloaded wird.

## Architektur

```
Tana  ──►  sync_tana_sr.py (Mac, launchd, alle 15 min)  ──►  cards.json  ──►  Client
Tana  ◄──  sync_tana_sr.py  ◄──  reviews-pending.json    ◄────────────────────  Client
```

`cards.json` im Dropbox-App-Ordner `TanaSR` ist die Quelle der Wahrheit für den
SM-2-Lernzustand. **Kein Client schreibt `cards.json`** — beide hängen ihre
Bewertungen nur an `reviews-pending.json` an. Das Mac-Skript
(`AIDE-Privat/Scripts/tana-sr/sync_tana_sr.py`) rechnet SM-2 nach, aktualisiert
`cards.json` und schreibt das Fälligkeitsdatum ins Tana-`srs`-Feld zurück.

Die SM-2-Funktion in `docs/app.js` ist gegen die Python-Funktion über 21'296
Parameterkombinationen auf exakte Gleichheit geprüft, inklusive Pythons
kaufmännischer Rundung zur geraden Zahl.

### Abweichung vom klassischen SM-2 (06.09.2026)

Im klassischen SM-2 sind die Intervalle der ersten beiden Stufen fest — 1 und
6 Tage, unabhängig von der Note. Bei der Migration bekamen 1120 der 1181 Karten
`repetitions = 1` als Heuristik und landeten damit alle auf der 6-Tage-Stufe,
obwohl sie teils seit Jahren sicher sitzen. Deshalb:

- **Einfach** auf `repetitions ≤ 1` → 14 Tage statt 1 bzw. 6
- **Einfach** ab `repetitions ≥ 2` → `Intervall × Ease × 1.3` (Easy-Bonus)
- Obergrenze 365 Tage — was man behalten will, soll jährlich auftauchen
- Gut, Schwer, Nochmal unverändert SM-2

Die Werte stehen als Konstanten am Kopf von `sm2()` und müssen in allen drei
Implementierungen gleich bleiben (`sync_tana_sr.py`, `docs/app.js`,
`TanaSR/Services/SM2.swift`). Auch die Klammerung zählt: `ease * bonus` zuerst,
sonst weicht die Gleitkomma-Rundung um einen Tag ab.

## PWA aufsetzen

GitHub Pages: Repository → Settings → Pages → Source «Deploy from a branch»,
Branch `main`, Ordner `/docs`.

Auf dem iPhone: URL in **Safari** öffnen (nicht Chrome — nur Safari kann zum
Homescreen installieren) → Teilen → «Zum Home-Bildschirm». Beim ersten Start den
Dropbox-Refresh-Token aus `~/.tana-sr/dropbox_credentials.json` einfügen.

## Was die PWA kann

- Fällige Karten, Bild und Vogelstimme, vier Bewertungsstufen wie in der iOS-App
- Tana-Auszeichnung wird gerendert: `<a href>`- und `<mark>`-Auszeichnung,
  Markdown-Links, eingebettete Bilder, Tana-Referenzen `[Text](tana:ID)`,
  nackte URLs, `**fett**`, `*kursiv*`, `#tags`. Aussenlinks öffnen in Safari
  (`target="_blank"`), sonst ersetzt die Seite die installierte App
- Offline: Service Worker cacht die App, `cards.json` und die Medien der
  nächsten 40 fälligen Karten. Bewertungen werden lokal gestapelt und beim
  nächsten Netz nach Dropbox geschoben (Zähler oben rechts)
- Bewertete Karten bleiben auch über einen Neustart weg, obwohl `cards.json`
  erst nach dem nächsten Mac-Sync (alle 15 min) aktualisiert ist: ein lokales
  Journal spielt die eigenen Bewertungen auf die geladenen Karten nach und wird
  geleert, sobald `cards.json` sie zeigt. **Die iOS-App hat diese Lücke noch** —
  dort kehren gerade bewertete Karten nach einem Neustart zurück.
- Tastatur am Desktop: Leertaste zeigt die Antwort, `1`–`4` bewerten

## Bekannte Grenzen

- Der Refresh-Token liegt in `localStorage`, nicht im Keychain. Der Token hat
  App-Folder-Scope, kommt also nur an den Dropbox-Ordner `TanaSR`.
- Autoplay der Vogelstimme unterbindet iOS ohne vorherige Tippgeste — dafür gibt
  es den Abspiel-Knopf.
- Ob `tana:`-Referenzen beim Antippen die Tana-App öffnen, hängt davon ab, ob
  Tana das URL-Schema auf dem Gerät registriert — ungeprüft.
- `reviews-pending.json` wird gelesen und komplett zurückgeschrieben. Leert das
  Mac-Skript die Datei genau zwischen diesen beiden Schritten, geht dessen
  Änderung verloren. Gilt für die iOS-App genauso; bei 15-Minuten-Intervall und
  Sekundenbruchteilen Schreibfenster praktisch nicht relevant.
