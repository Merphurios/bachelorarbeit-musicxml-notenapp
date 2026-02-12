import os
import tempfile
import uuid
import subprocess
from typing import Optional
from pathlib import Path
import zipfile

from flask import Flask, request, Response

app = Flask(__name__)

# Pfad zu DEINER Audiveris-Installation (so wie auf deinem Screenshot)
AUDIVERIS_EXE = r"E:\Audivers für Abschlussarbeit HTW\Audiveris.exe"

# Basis-Ausgabeverzeichnis für von Audiveris erzeugte Dateien
AUDIVERIS_OUTPUT_BASE = Path(r"E:\omr_server\audiveris_output")
AUDIVERIS_OUTPUT_BASE.mkdir(parents=True, exist_ok=True)

# Dummy-MusicXML als Fallback
DUMMY_MUSICXML = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC
  "-//Recordare//DTD MusicXML 3.1 Partwise//EN"
  "http://www.musicxml.org/dtd/partwise.dtd">
<score-partwise version="3.1">
  <work>
    <work-title>Dummy-Werk aus OMR-Server</work-title>
  </work>
  <identification>
    <creator type="composer">Testkomponist</creator>
  </identification>
  <part-list>
    <score-part id="P1">
      <part-name>Music</part-name>
    </score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>0</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration>
        <type>whole</type>
      </note>
    </measure>
  </part>
</score-partwise>
"""

def _read_musicxml_if_valid(path: Path) -> Optional[str]:
    """Liest eine XML-Datei und checkt, ob sie wirklich MusicXML ist.
    MusicXML hat normalerweise <score-partwise> oder <score-timewise> als Root-Element.
    """
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
        snippet = text[:4000].lower()

        if "<score-partwise" in snippet or "<score-timewise" in snippet:
            print(f"[OMR] Verwende MusicXML-Datei: {path}")
            return text

        print(f"[OMR] XML-Datei {path} scheint keine MusicXML zu sein – wird ignoriert.")
        return None
    except Exception as e:
        print(f"[OMR] Fehler beim Lesen von {path}: {e}")
        return None


def run_audiveris(pdf_path: str) -> Optional[str]:
    """
    Nimmt den Pfad zu einer PDF-Datei, ruft Audiveris im Batch-Modus auf
    und gibt den MusicXML-Text zurück, wenn alles klappt.
    Sonst None -> dann nimm Dummy.
    """

    # eigener Output-Ordner pro Request (damit sich nichts in die Quere kommt)
    out_dir = AUDIVERIS_OUTPUT_BASE / str(uuid.uuid4())
    out_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        AUDIVERIS_EXE,
        "-batch",
        "-export",
        "-output", str(out_dir),
        pdf_path,
    ]

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,  # bis zu 5 Minuten
        )
        print("Audiveris stdout:\n", result.stdout)
        print("Audiveris stderr:\n", result.stderr)

        if result.returncode != 0:
            print("Audiveris Exit-Code:", result.returncode)
            return None

    except Exception as e:
        print("Fehler beim Start von Audiveris:", e)
        return None

    # 1) Dateien im Output-Verzeichnis einsammeln
    xml_candidates: list[Path] = []
    mxl_candidates: list[Path] = []

    for root, dirs, files in os.walk(out_dir):
        for name in files:
            lower = name.lower()
            full = Path(root) / name
            if lower.endswith(".mxl"):
                mxl_candidates.append(full)
            elif lower.endswith(".musicxml") or lower.endswith(".xml"):
                xml_candidates.append(full)

    # 2) Zuerst echte XML-Dateien durchgehen und auf MusicXML prüfen
    for xml_path in xml_candidates:
        text = _read_musicxml_if_valid(xml_path)
        if text:
            return text

    # 3) Wenn keine passende XML, dann alle MXL-Zips öffnen und darin suchen
    for mxl_path in mxl_candidates:
        try:
            print(f"[OMR] Versuche MXL zu entpacken: {mxl_path}")
            with zipfile.ZipFile(mxl_path, "r") as zf:
                # alle inneren XML-Dateien
                inner_xmls = [
                    n for n in zf.namelist()
                    if n.lower().endswith(".xml") or n.lower().endswith(".musicxml")
                ]
                for inner_name in inner_xmls:
                    with zf.open(inner_name) as f:
                        data = f.read().decode("utf-8", errors="ignore")
                    lower = data[:4000].lower()
                    if "<score-partwise" in lower or "<score-timewise" in lower:
                        print(f"[OMR] Verwende MusicXML aus MXL: {mxl_path} -> {inner_name}")
                        return data
                    else:
                        print(f"[OMR] XML {inner_name} in {mxl_path} ist keine MusicXML – ignoriert.")
        except Exception as e:
            print("Fehler beim Lesen aus MXL:", e)

    # 4) Gar keine brauchbare MusicXML gefunden
    print("Keine MusicXML-Datei im Ausgabeverzeichnis gefunden.")
    return None


@app.route("/health", methods=["GET"])
def health():
    return "OK", 200


@app.route("/omr", methods=["POST"])
def omr():
    uploaded = request.files.get("file")
    if not uploaded:
        return "No file uploaded", 400

    # 1. Upload in temporäre Datei schreiben
    with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
        tmp_path = tmp.name
        uploaded.save(tmp)

    try:
        # 2. Audiveris versuchen
        musicxml = run_audiveris(tmp_path)

        if musicxml:
            # Erfolg: echte OMR-Antwort
            print("[OMR] MusicXML erfolgreich von Audiveris erzeugt.")
            return Response(musicxml, mimetype="application/xml")

        # 3. Fallback: Dummy-XML
        print("[OMR] Audiveris lieferte nichts, Fallback auf Dummy.")
        return Response(DUMMY_MUSICXML, mimetype="application/xml")

    finally:
        # temporäre Datei wegräumen
        try:
            os.remove(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    # Wichtig: Python 3!
    app.run(host="0.0.0.0", port=5000, debug=True)
