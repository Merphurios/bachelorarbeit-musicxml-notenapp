# bachelorarbeit-musicxml-notenapp

Bachelorarbeit (HTW Dresden): Workflow zur Digitalisierung, Versionierung und Bearbeitung gescannter Musiknoten  
(Flutter + OMR-Server + MusicXML)

---

## Inhalt

Dieses Repository enthält:

- eine **Flutter-Mobile-App** für Android zur Erfassung, Verwaltung und Bearbeitung von Notenprojekten
- einen **OMR-Server** (Flask + Audiveris) zur Umwandlung von PDF-Scans in MusicXML
- ergänzende **Dokumentation** (z. B. die Bachelorarbeit als PDF und Diagramme)

---

## Architekturüberblick

Die Lösung folgt einem klassischen Client-Server-Ansatz:

### Mobile App (Flutter)

- Anonyme Anmeldung mit Firebase Authentication  
- Verwaltung von „Werken“ (`works`) und deren Versionen (`versions`) in Firestore  
- Aufnahme von Notenblättern per Kamera und Speicherung als PDF  
- Import oder Generierung von MusicXML-Dateien pro Version  
- Anzeige der MusicXML-Datei im integrierten Notenviewer  
- Einfache Bearbeitungsfunktionen:
  - Oktavtransposition (±1 Oktave)
  - Halbtontransposition (±2/±3 Halbtöne)
  - Erzeugen/Entfernen einer einfachen Zweitstimme

### OMR-Server (Python/Flask + Audiveris)

- HTTP-Endpoint `/omr`  
- nimmt ein PDF als Multipart-Upload entgegen  
- ruft Audiveris im Batch-Modus auf  
- durchsucht das Ausgabeverzeichnis nach MusicXML/MXL  
- liefert bei Erfolg die MusicXML-Datei zurück  
- bei Fehlern wird eine definierte Dummy-MusicXML zurückgegeben

### Datenhaltung

- **Firestore** speichert Metadaten zu Werken und Versionen (Titel, Kommentare, Pfade etc.).  
- **Lokales Dateisystem** des Geräts speichert PDFs und MusicXML-Dateien unter einer stabilen Ordnerstruktur:


---

## Projektstruktur

```text
.
├─ lib/                      # Flutter-Dart-Code (App)
├─ android/                  # Android-spezifische Flutter-Dateien
├─ ios/                      # iOS-spezifische Flutter-Dateien (optional)
├─ assets/
│   └─ musicxml_viewer.html  # HTML + JS (OpenSheetMusicDisplay) für den Notenviewer
├─ omr_server/
│   ├─ omr_server.py         # Flask-Server, der Audiveris ansteuert
│   ├─ requirements.txt      # Python-Abhängigkeiten
│   └─ audiveris_output/     # (im .gitignore, nur Laufzeit-Output)
├─ docs/
│   └─ Bachelorarbeit.pdf    # (optional) finale Arbeit / Diagramme
├─ pubspec.yaml
├─ README.md
└─ .gitignore

## Setup

### Voraussetzungen

#### Flutter / App
- Flutter: **>= 3.32.0** (siehe `pubspec.lock`)
- Dart: **>= 3.8.1**
- Android Studio / Android SDK (für Android Build/Emulator)

#### Python / OMR-Server
- Python: **3.7+** (getestet mit 3.7.8)
- Abhängigkeiten:

```bash
cd omr_server
py -m pip install -r requirements.txt
```

#### Verbindung zwischen App und OMR-Server

Die Flutter-App kommuniziert mit dem lokalen OMR-Server (Flask, Standard: Port 5000) über HTTP.

Standardmäßig wird folgende Basis-URL verwendet:  
`http://127.0.0.1:5000`

Wichtig:
- `127.0.0.1` funktioniert nur, wenn App und Server auf demselben Gerät laufen.
- Bei Verwendung eines Android-Emulators muss in der Regel `http://10.0.2.2:5000` verwendet werden.
- Bei einem echten Android-Gerät muss die IP-Adresse des PCs im lokalen Netzwerk verwendet werden (z. B. `http://192.168.x.x:5000`).

Die Basis-URL kann beim Build der App über `--dart-define` gesetzt werden:

```bash
flutter run --dart-define=OMR_BASE_URL=http://<IP-Adresse>:5000
```
