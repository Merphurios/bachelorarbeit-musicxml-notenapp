# bachelorarbeit-musicxml-notenapp

Bachelorarbeit (HTW Dresden): Workflow zur Digitalisierung, Versionierung und Bearbeitung gescannter Musiknoten  
(Flutter + OMR-Server + MusicXML)

## Inhalt

Dieses Repository enthält:

- eine **Flutter-Mobile-App** für Android zur Erfassung, Verwaltung und Bearbeitung von Notenprojekten
- einen **OMR-Server** (Flask + Audiveris) zur Umwandlung von PDF-Scans in MusicXML
- ergänzende **Dokumentation** (z. B. die Bachelorarbeit als PDF und Diagramme)

---

## Architekturüberblick

Die Lösung folgt einem klassischen Client-Server-Ansatz:

- **Mobile App (Flutter)**  
  - Anonyme Anmeldung mit Firebase Authentication  
  - Verwaltung von „Werken“ (`works`) und deren Versionen (`versions`) in Firestore  
  - Aufnahme von Notenblättern per Kamera und Speicherung als PDF  
  - Import oder Generierung von MusicXML-Dateien pro Version  
  - Anzeige der MusicXML-Datei im integrierten Notenviewer  
  - Einfache Bearbeitungsfunktionen:
    - Oktavtransposition (±1 Oktave)
    - Halbtontransposition (±2/±3 Halbtöne)
    - Erzeugen/Entfernen einer einfachen Zweitstimme

- **OMR-Server (Python/Flask + Audiveris)**  
  - HTTP-Endpoint `/omr`  
  - nimmt ein PDF als Multipart-Upload entgegen  
  - ruft Audiveris im Batch-Modus auf  
  - durchsucht das Ausgabeverzeichnis nach MusicXML/MXL  
  - liefert bei Erfolg die MusicXML-Datei zurück, ansonsten eine definierte Dummy-MusicXML

- **Datenhaltung**  
  - **Firestore** speichert Metadaten zu Werken und Versionen (Titel, Kommentare, Pfade etc.).  
  - **Lokales Dateisystem** des Geräts speichert PDFs und MusicXML-Dateien unter einer stabilen Ordnerstruktur:

    ```
    <App-Dokumentenordner>/
      works/
        <workId>/
          versions/
            <versionId>/
              score.pdf
              score.musicxml
    ```

---

## Projektstruktur

Eine mögliche Struktur des Repositories:

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
