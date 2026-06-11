# bachelorarbeit-musicxml-notenapp

Bachelorarbeit an der HTW Dresden: Workflow zur Digitalisierung, Versionierung und Bearbeitung gescannter Musiknoten
(Flutter + OMR-Server + MusicXML)

---

## Inhalt

Dieses Repository enthält:

* eine **Flutter-App** für Android zur Erfassung, Verwaltung und Bearbeitung von Notenprojekten
* einen **OMR-Server** auf Basis von Flask und Audiveris zur Umwandlung von PDF-Scans in MusicXML

---

## Architekturüberblick

Die Lösung folgt einem Client-Server-Ansatz.

### Mobile App (Flutter)

* anonyme Anmeldung mit Firebase Authentication
* Verwaltung von Werken (`works`) und deren Versionen (`versions`) in Firestore
* Aufnahme von Notenblättern per Kamera und Speicherung als PDF
* Import oder Generierung von MusicXML-Dateien pro Version
* Anzeige der MusicXML-Dateien im integrierten Notenviewer
* einfache Bearbeitungsfunktionen:

  * Oktavtransposition um ±1 Oktave
  * Halbtontransposition um ±2 oder ±3 Halbtöne
  * Erzeugen und Entfernen einer einfachen Zweitstimme

### OMR-Server (Python/Flask + Audiveris)

* stellt den HTTP-Endpunkt `/omr` bereit
* nimmt ein PDF als Multipart-Upload entgegen
* ruft Audiveris im Batch-Modus auf
* durchsucht das Ausgabeverzeichnis nach MusicXML- oder MXL-Dateien
* liefert bei Erfolg die erzeugte MusicXML-Datei zurück
* gibt bei Fehlern eine definierte Dummy-MusicXML zurück

### Datenhaltung

* **Firestore** speichert Metadaten zu Werken und Versionen, beispielsweise Titel, Kommentare und lokale Dateipfade.
* Das **lokale Dateisystem** des Geräts speichert die erzeugten PDF- und MusicXML-Dateien.

---

## Projektstruktur

```text
.
├─ lib/                      # Flutter-Dart-Code der App
├─ android/                  # Android-spezifische Flutter-Dateien
├─ assets/
│  └─ musicxml_viewer.html   # Notenviewer mit OpenSheetMusicDisplay
├─ omr_server/
│  ├─ omr_server.py          # Flask-Server zur Ansteuerung von Audiveris
│  ├─ requirements.txt       # Python-Abhängigkeiten
│  └─ audiveris_output/      # Laufzeitausgabe, nicht versioniert
├─ web/                      # Flutter-Webdateien
├─ windows/                  # Flutter-Windowsdateien
├─ pubspec.yaml              # Flutter-Abhängigkeiten
├─ analysis_options.yaml     # Dart-Analyseoptionen
├─ LICENSE                   # MIT-Lizenz
├─ README.md
└─ .gitignore
```

---

## Setup

### Voraussetzungen

#### Flutter/App

* Flutter: **>= 3.32.0**
* Dart: **>= 3.8.1**
* Android Studio und Android SDK für den Android-Build oder Emulator

#### Python/OMR-Server

* Python: **3.7+** (getestet mit Python 3.7.8)
* Installation der Python-Abhängigkeiten:

```bash
cd omr_server
py -m pip install -r requirements.txt
```

### Firebase-Konfiguration

Die Firebase-Konfigurationsdateien sind nicht im Repository enthalten.

Zum Ausführen der App muss ein eigenes Firebase-Projekt eingerichtet werden. Anschließend muss die Datei

```text
android/app/google-services.json
```

lokal ergänzt werden.

Im Firebase-Projekt werden außerdem benötigt:

* Firebase Authentication mit aktivierter anonymer Anmeldung
* eine Cloud-Firestore-Datenbank
* geeignete Firestore-Sicherheitsregeln

### Verbindung zwischen App und OMR-Server

Die Flutter-App kommuniziert über HTTP mit dem lokalen Flask-Server. Standardmäßig wird Port `5000` verwendet.

Die voreingestellte Basis-URL lautet:

```text
http://127.0.0.1:5000
```

Dabei ist Folgendes zu beachten:

* Bei einem Android-Emulator wird normalerweise `http://10.0.2.2:5000` verwendet.
* Bei einem echten Android-Gerät muss die lokale IP-Adresse des PCs verwendet werden, beispielsweise `http://192.168.x.x:5000`.
* Das Android-Gerät und der PC müssen sich im selben lokalen Netzwerk befinden.

Die Basis-URL kann beim Start über `--dart-define` gesetzt werden:

```bash
flutter run --dart-define=OMR_BASE_URL=http://<IP-Adresse>:5000
```

Damit ein echtes Android-Gerät auf den Server zugreifen kann, muss Flask auf allen Netzwerkschnittstellen lauschen:

```bash
flask --app omr_server.py run --host 0.0.0.0 --port 5000
```

Für den Android-Emulator wird üblicherweise `10.0.2.2` als Adresse des Host-PCs verwendet.

---

## Lizenz

Dieses Projekt steht unter der MIT-Lizenz. Weitere Informationen befinden sich in der Datei [`LICENSE`](LICENSE).
