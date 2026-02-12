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
