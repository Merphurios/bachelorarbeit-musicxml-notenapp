import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xml/xml.dart' as xml;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/services.dart';

class MusicXmlViewerScreen extends StatefulWidget {
  final String musicXmlPath;
  final String workTitle;
  final String versionId;

  const MusicXmlViewerScreen({
    super.key,
    required this.musicXmlPath,
    required this.workTitle,
    required this.versionId,
  });

  @override
  State<MusicXmlViewerScreen> createState() => _MusicXmlViewerScreenState();
}

class _MusicXmlViewerScreenState extends State<MusicXmlViewerScreen> {
  late final WebViewController _controller;
  bool _pageFinished = false;
  String? _error;

  String? _originalXml;          // Inhalt der Datei beim Laden
  String? _currentXml;           // aktuell bearbeitete Version
  xml.XmlDocument? _doc;         // geparstes XML-Dokument

  bool _isEditing = false;       // Bearbeitungsmodus an/aus
  bool _isBusy = false;          // für Loading/Buttons sperren

  bool _secondVoiceActive = false;

  @override
  void initState() {
    super.initState();

    // In diesem Screen Portrait + Landscape erlauben
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!_pageFinished) {
              _pageFinished = true;
              _loadAndRenderXml();
            }
          },
          onWebResourceError: (e) {
            setState(() {
              _error = 'WebView-Fehler: ${e.description}';
            });
          },
        ),
      )
      ..loadFlutterAsset('assets/musicxml_viewer.html');
  }

  @override
  void dispose() {
    // Beim Verlassen wieder nur Hochformat erlauben
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<void> _loadAndRenderXml() async {
    try {
      final file = File(widget.musicXmlPath);
      if (!await file.exists()) {
        setState(() {
          _error = 'MusicXML-Datei nicht gefunden.';
        });
        return;
      }

      final xmlString = await file.readAsString();

      // HIER: setState, damit _originalXml & Co. im UI ankommen
      setState(() {
        _originalXml = xmlString;
        _currentXml = xmlString;
        _doc = xml.XmlDocument.parse(xmlString);

        _secondVoiceActive = _doc!.rootElement
          .findAllElements('note')
          .any((n) => n.getAttribute('data-second-voice') == 'true');
      });

      await _renderXml(xmlString);

    } catch (e) {
      setState(() {
        _error = 'Fehler beim Laden/Übergeben der MusicXML-Datei: $e';
      });
    }
  }

  Future<void> _renderXml(String xmlSource) async {
    final b64 = base64Encode(utf8.encode(xmlSource));
    await _controller.runJavaScript(
      'window.loadMusicXmlBase64("$b64");',
    );
  }

  void _startEditing() {
    if (_originalXml == null) return;

    try {
      _doc = xml.XmlDocument.parse(_originalXml!);
      _currentXml = _originalXml;
      setState(() {
        _isEditing = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Start des Bearbeitungsmodus: $e')),
      );
    }
  }

  Future<void> _transposeOctave(int delta) async {
    if (!_isEditing || _doc == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      final octaveElements = _doc!.findAllElements('octave').toList();
      for (final elem in octaveElements) {
        final current = int.tryParse(elem.text.trim());
        if (current == null) continue;

        final newVal = current + delta;
        elem.children
          ..clear()
          ..add(xml.XmlText(newVal.toString()));
      }

      final newXml = _doc!.toXmlString(pretty: true, indent: '  ');
      _currentXml = newXml;
      await _renderXml(newXml); // Notenansicht neu zeichnen
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei Oktav-Transposition: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _showSaveOptionsDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Wie möchten Sie speichern?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kachel A: Neue Version
              InkWell(
                onTap: () => Navigator.of(dialogContext).pop('newVersion'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.blue.shade50,
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.library_add, color: Colors.blue),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Neue Version anlegen',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Speichert als V(n+1) und lässt die aktuelle Version unverändert.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Kachel B: Überschreiben
              InkWell(
                onTap: () => Navigator.of(dialogContext).pop('overwrite'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.save, color: Colors.orange),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Diese Version überschreiben',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Speichert die Änderungen direkt in dieser Version.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == 'newVersion') {
      await _saveChanges(createNewVersion: true);
    } else if (result == 'overwrite') {
      await _saveChanges(createNewVersion: false);
    }
  }

  Future<void> _saveChanges({required bool createNewVersion}) async {
    if (!_isEditing || _currentXml == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      final xmlString = _currentXml!;

      if (!createNewVersion) {
        // Variante B: diese Version überschreiben
        final file = File(widget.musicXmlPath);
        await file.writeAsString(xmlString, flush: true);
        _originalXml = xmlString;

        // hasSecondVoice in Firestore updaten
        await FirebaseFirestore.instance
          .collection('version')
          .doc(widget.versionId)
          .update({
          'hasSecondVoice' : _secondVoiceActive,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Änderungen gespeichert (Version überschrieben)')),
          );
        }

        if (mounted) {
          setState(() {
            _isEditing = false;
          });
        }
      } else {
        // Variante A: neue Version anlegen
        final info = await _createNewVersionWithXml(xmlString, _secondVoiceActive);
        if (!mounted || info == null) return;

        final newVersionId = info['versionId']!;
        final newPath = info['musicXmlPath']!;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Neue Version angelegt')),
        );

        // direkt in die neue Version springen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MusicXmlViewerScreen(
              musicXmlPath: newPath,
              workTitle: widget.workTitle,
              versionId: newVersionId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<Map<String, String>?> _createNewVersionWithXml
      (String xmlString, bool hasSecondVoice) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // aktuelle Version aus Firestore holen
      final currentSnap =
      await firestore.collection('versions').doc(widget.versionId).get();

      if (!currentSnap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aktuelle Version in Firestore nicht gefunden')),
          );
        }
        return null;
      }

      final data = currentSnap.data() as Map<String, dynamic>;
      final workId = data['workId'] as String;

      // vorhandene Versionen zählen
      final versionsSnap = await firestore
          .collection('versions')
          .where('workId', isEqualTo: workId)
          .get();

      final count = versionsSnap.docs.length;
      if (count >= 6) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Maximal 6 Versionen pro Stück. Bitte zuerst eine Version löschen.',
              ),
            ),
          );
        }
        return null;
      }

      final nextNumber = count + 1;
      final newLabel = 'V$nextNumber';
      final userId = FirebaseAuth.instance.currentUser?.uid;

      // neue Version in Firestore anlegen (erstmal ohne Pfade)
      final newDocRef = await firestore.collection('versions').add({
        'workId': workId,
        'label': newLabel,
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'pdfPath': data['pdfPath'],
        'musicXmlPath': null,
        'comment': 'Bearbeitete Version (aus ${data['label'] ?? "Version"})',
        'hasSecondVoice': hasSecondVoice,
        'isOriginal': false,
        'xmlWorkTitle': data['xmlWorkTitle'],
        'xmlComposer': data['xmlComposer'],
      });

      // lokaler Ordner für neue Version
      final appDir = await getApplicationDocumentsDirectory();
      final versionDir =
      Directory('${appDir.path}/works/$workId/versions/${newDocRef.id}');
      await versionDir.create(recursive: true);

      // neue MusicXML-Datei speichern
      final newMusicXmlPath = '${versionDir.path}/score.musicxml';
      final xmlFile = File(newMusicXmlPath);
      await xmlFile.writeAsString(xmlString, flush: true);

      // (optional) PDF kopieren
      final oldPdfPath = data['pdfPath'] as String?;
      if (oldPdfPath != null && oldPdfPath.isNotEmpty) {
        final oldPdfFile = File(oldPdfPath);
        if (await oldPdfFile.exists()) {
          final newPdfPath = '${versionDir.path}/score.pdf';
          await oldPdfFile.copy(newPdfPath);
          await newDocRef.update({'pdfPath': newPdfPath});
        }
      }

      // Firestore mit neuem XML-Pfad updaten
      await newDocRef.update({'musicXmlPath': newMusicXmlPath});

      return {
        'versionId': newDocRef.id,
        'musicXmlPath': newMusicXmlPath,
      };
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Anlegen der neuen Version: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _toggleSecondVoice() async {
    if (!_isEditing || _doc == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      final root = _doc!.rootElement;

      // 1. Prüfen, ob bereits generierte Zweitstimmen existieren
      final generatedNotes = root
          .findAllElements('note')
          .where((n) => n.getAttribute('data-second-voice') == 'true')
          .toList();

      if (generatedNotes.isNotEmpty) {
        // -> Zweitstimme ENTFERNEN
        for (final note in generatedNotes) {
          final parent = note.parent;
          if (parent is xml.XmlElement) {
            parent.children.remove(note);
          }
        }

        final newXml = _doc!.toXmlString(pretty: true, indent: '  ');
        _currentXml = newXml;
        await _renderXml(newXml);

        if (mounted) {
          setState(() {
            _secondVoiceActive = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zweitstimme entfernt')),
          );
        }
        return;
      }

      // 2. Noch keine Zweitstimme -> erzeugen
      final allNotes = root.findAllElements('note').toList();

      for (final note in allNotes) {
        final pitchEl = note.getElement('pitch');
        if (pitchEl == null) {
          // z.B. Pausen (<rest/>) überspringen
          continue;
        }

        final octaveEl = pitchEl.getElement('octave');
        if (octaveEl == null) continue;

        // Note duplizieren
        final noteCopy = note.copy() as xml.XmlElement;

        // als generierte Zweitstimme markieren
        noteCopy.attributes.addAll([
          xml.XmlAttribute(
            xml.XmlName('data-second-voice'), 'true',
          ),
          // Farbe für die Zweitstimme (helles, keicht leuchtendes Grün)
          xml.XmlAttribute(
            xml.XmlName('color'), '#66cc99',
          ),
        ]);

        // Stimme auf 2 setzen
        final voiceEl = noteCopy.getElement('voice');
        if (voiceEl != null) {
          voiceEl.children
            ..clear()
            ..add(xml.XmlText('2'));
        } else {
          final voiceNode = xml.XmlElement(xml.XmlName('voice'));
          voiceNode.children.add(xml.XmlText('2'));
          noteCopy.children.add(voiceNode);
        }

        // eine Oktave tiefer setzen
        final pitchCopy = noteCopy.getElement('pitch');
        final octaveCopy = pitchCopy?.getElement('octave');
        if (octaveCopy != null) {
          final current = int.tryParse(octaveCopy.text.trim());
          if (current != null) {
            final newVal = current - 1;
            octaveCopy.children
              ..clear()
              ..add(xml.XmlText(newVal.toString()));
          }
        }

        // Kopie direkt nach Originalnote im gleichen Measure einfügen
        final parent = note.parent;
        if (parent is xml.XmlElement) {
          final idx = parent.children.indexOf(note);
          if (idx != -1) {
            parent.children.insert(idx + 1, noteCopy);
          } else {
            parent.children.add(noteCopy);
          }
        }
      }

      final newXml = _doc!.toXmlString(pretty: true, indent: '  ');
      _currentXml = newXml;
      await _renderXml(newXml);

      if (mounted) {
        setState(() {
          _secondVoiceActive = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zweitstimme erzeugt (Oktave tiefer, Voice 2)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Umschalten der Zweitstimme: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _discardChanges() async {
    if (_originalXml == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      // Original-XML zurück ins Dokument laden
      final parsed = xml.XmlDocument.parse(_originalXml!);
      _doc = parsed;
      _currentXml = _originalXml;

      // Zweitstimme-Flag anhand des Original-XMLs neu berechnen
      final hasSecond = parsed.rootElement
          .findAllElements('note')
          .any((n) => n.getAttribute('data-second-voice') == 'true');

      setState(() {
        _secondVoiceActive = hasSecond;
      });

      // Notenansicht neu rendern
      await _renderXml(_originalXml!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Änderungen verworfen')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Verwerfen: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _transposeSemitones(int semitones) async {
    if (!_isEditing || _doc == null) return;

    setState(() {
      _isBusy = true;
    });

    try {
      // Alle <note>-Elemente durchgehen
      final notes = _doc!.rootElement.findAllElements('note').toList();

      for (final note in notes) {
        final pitchEl = note.getElement('pitch');
        if (pitchEl == null) continue; // Pausen usw. überspringen

        final stepEl = pitchEl.getElement('step');
        final octaveEl = pitchEl.getElement('octave');
        if (stepEl == null || octaveEl == null) continue;

        final alterEl = pitchEl.getElement('alter');

        // Aktuellen Step / Alter / Oktave auslesen
        final stepText = stepEl.text.trim().toUpperCase();
        final octaveText = octaveEl.text.trim();

        int baseSemis;
        switch (stepText) {
          case 'C':
            baseSemis = 0;
            break;
          case 'D':
            baseSemis = 2;
            break;
          case 'E':
            baseSemis = 4;
            break;
          case 'F':
            baseSemis = 5;
            break;
          case 'G':
            baseSemis = 7;
            break;
          case 'A':
            baseSemis = 9;
            break;
          case 'B':
            baseSemis = 11;
            break;
          default:
            continue; // unbekannter Step
        }

        final currentAlter = int.tryParse(alterEl?.text.trim() ?? '0') ?? 0;
        final currentOctave = int.tryParse(octaveText) ?? 4;

        // Semitöne absolut berechnen
        final currentSemis = currentOctave * 12 + baseSemis + currentAlter;
        var newSemis = currentSemis + semitones;
        if (newSemis < 0) newSemis = 0; // simple Sicherheit

        final newOctave = newSemis ~/ 12;
        final newSemisInOctave = newSemis % 12;

        // Semitöne in Step + Alter zurück mappen
        String newStep;
        int newAlter;

        switch (newSemisInOctave) {
          case 0:
            newStep = 'C';
            newAlter = 0;
            break;
          case 1:
            newStep = 'C';
            newAlter = 1; // C#
            break;
          case 2:
            newStep = 'D';
            newAlter = 0;
            break;
          case 3:
            newStep = 'D';
            newAlter = 1; // D#
            break;
          case 4:
            newStep = 'E';
            newAlter = 0;
            break;
          case 5:
            newStep = 'F';
            newAlter = 0;
            break;
          case 6:
            newStep = 'F';
            newAlter = 1; // F#
            break;
          case 7:
            newStep = 'G';
            newAlter = 0;
            break;
          case 8:
            newStep = 'G';
            newAlter = 1; // G#
            break;
          case 9:
            newStep = 'A';
            newAlter = 0;
            break;
          case 10:
            newStep = 'A';
            newAlter = 1; // A#
            break;
          case 11:
            newStep = 'B';
            newAlter = 0;
            break;
          default:
            continue;
        }

        // Step setzen
        stepEl.children
          ..clear()
          ..add(xml.XmlText(newStep));

        // Oktave setzen
        octaveEl.children
          ..clear()
          ..add(xml.XmlText(newOctave.toString()));

        // Alter setzen / entfernen
        if (newAlter == 0) {
          // kein Vorzeichen -> <alter> entfernen, falls vorhanden
          if (alterEl != null) {
            pitchEl.children.remove(alterEl);
          }
        } else {
          if (alterEl != null) {
            alterEl.children
              ..clear()
              ..add(xml.XmlText(newAlter.toString()));
          } else {
            final newAlterEl = xml.XmlElement(xml.XmlName('alter'));
            newAlterEl.children.add(xml.XmlText(newAlter.toString()));

            // optional: hinter <step> einfügen, sonst ans Ende
            final idx = pitchEl.children.indexOf(stepEl);
            if (idx != -1 && idx + 1 <= pitchEl.children.length) {
              pitchEl.children.insert(idx + 1, newAlterEl);
            } else {
              pitchEl.children.add(newAlterEl);
            }
          }
        }
      }

      // Neues XML generieren und neu rendern
      final newXml = _doc!.toXmlString(pretty: true, indent: '  ');
      _currentXml = newXml;
      await _renderXml(newXml);

      if (mounted) {
        final amount = semitones.abs();
        final direction = semitones > 0 ? 'höher' : 'tiefer';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Alle Noten um $amount Halbtöne $direction transponiert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei der Transposition: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Noten – ${widget.workTitle}'),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: (_originalXml == null || _isBusy) ? null : _startEditing,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Änderung verwerfen',
              onPressed: _isBusy ? null : _discardChanges,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Soeichern',
              onPressed: _isBusy ? null : _showSaveOptionsDialog,
            ),
          ],
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : Column(
        children: [
          if (_isEditing) ...[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Zeile 1 Oktaven
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _isBusy ? null : () => _transposeOctave(-1),
                        child: const Text('Oktave -1'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isBusy ? null : () => _transposeOctave(1),
                        child: const Text('Oktave +1'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Zeile 2 Zweitstimme
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                          _secondVoiceActive ? Colors.blue.shade100 : Colors.transparent,
                          side: BorderSide(
                            color: _secondVoiceActive ? Colors.blue.shade700 : Colors.blueGrey,
                          ),
                        ),
                        onPressed: _isBusy ? null : _toggleSecondVoice,
                        child: Text(
                          _secondVoiceActive ? 'Zweitstimme an' : 'Zweitstimme aus',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Zeile 3 Halbton usw
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isBusy ? null : () => _transposeSemitones(2),
                        child: const Text('+2 HT'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isBusy ? null : () => _transposeSemitones(-2),
                        child: const Text('-2 HT'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isBusy ? null : () => _transposeSemitones(3),
                        child: const Text('+3 HT'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isBusy ? null : () => _transposeSemitones(-3),
                        child: const Text('-3 HT'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}