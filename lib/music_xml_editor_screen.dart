// NOTE: Legacy/Debug screen. Not used in the current UI flow.
// Kept for documentation / debugging during thesis development.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xml/xml.dart' as xml;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

class MusicXmlEditorScreen extends StatefulWidget {
  final String musicXmlPath;
  final String workTitle;
  final String versionId;

  const MusicXmlEditorScreen({
    super.key,
    required this.musicXmlPath,
    required this.workTitle,
    required this.versionId,
  });

  @override
  State<MusicXmlEditorScreen> createState() => _MusicXmlEditorScreenState();
}

class _MusicXmlEditorScreenState extends State<MusicXmlEditorScreen> {
  String? _rawXml;
  xml.XmlDocument? _doc;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadXml();
  }

  Future<void> _loadXml() async {
    try {
      final file = File(widget.musicXmlPath);
      if (!await file.exists()) {
        setState(() {
          _error = 'MusicXML-Datei nicht gefunden.';
          _isLoading = false;
        });
        return;
      }

      final content = await file.readAsString();
      setState(() {
        _rawXml = content;
        _doc = xml.XmlDocument.parse(content);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Fehler beim Laden der MusicXML-Datei: $e';
        _isLoading = false;
      });
    }
  }

  /// Oktav-Transposition: alle <octave>-Werte um [delta] verändern.
  void _transposeOctave(int delta) {
    if (_doc == null) return;

    final octaveElements = _doc!.findAllElements('octave').toList();
    for (final elem in octaveElements) {
      final current = int.tryParse(elem.text.trim());
      if (current == null) continue;

      final newVal = current + delta;
      elem.children
        ..clear()
        ..add(xml.XmlText(newVal.toString()));
    }

    setState(() {
      _rawXml = _doc!.toXmlString(pretty: true, indent: '  ');
    });
  }

  Future<void> _saveXml({required bool createNewVersion}) async {
    if (_doc == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final xmlString = _doc!.toXmlString(pretty: true, indent: '  ');

      if (createNewVersion) {
        final info = await _createNewVersionWithXml(xmlString);
        if (!mounted || info == null) return;

        // zurück zum Viewer, der dann direkt in die neue Version springt
        Navigator.of(context).pop({
          'mode': 'newVersion',
          'versionId': info['versionId'],
          'musicXmlPath': info['musicXmlPath'],
        });
      } else {
        // aktuelle Datei überschreiben
        final file = File(widget.musicXmlPath);
        await file.writeAsString(xmlString, flush: true);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MusicXML gespeichert (Version überschrieben)'),
          ),
        );

        Navigator.of(context).pop({
          'mode': 'overwrite',
          'versionId': widget.versionId,
          'musicXmlPath': widget.musicXmlPath,
        });
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
          _isSaving = false;
        });
      }
    }
  }

  Future<Map<String, String>?> _createNewVersionWithXml(String xmlString) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // aktuelle Version aus Firestore holen
      final currentSnap =
      await firestore.collection('versions').doc(widget.versionId).get();

      if (!currentSnap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Aktuelle Version in Firestore nicht gefunden'),
            ),
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
        'hasSecondVoice': data['hasSecondVoice'] ?? false,
        'isOriginal': false,
        'xmlWorkTitle': data['xmlWorkTitle'],
        'xmlComposer': data['xmlComposer'],
      });

      // lokaler Ordner für neue Version
      final appDir = await getApplicationDocumentsDirectory();
      final versionDir =
      Directory('${appDir.path}/works/$workId/versions/${newDocRef.id}');
      await versionDir.create(recursive: true);

      // MusicXML-Datei speichern
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
                            Text('Neue Version anlegen',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                )),
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
                            Text('Diese Version überschreiben',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                )),
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
      await _saveXml(createNewVersion: true);
    } else if (result == 'overwrite') {
      await _saveXml(createNewVersion: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('MusicXML – ${widget.workTitle}'),
        ),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('MusicXML – ${widget.workTitle}'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : () => _showSaveOptionsDialog(),
            icon: _isSaving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: Column(
        children: [
          // Transpose-Buttons
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _transposeOctave(-1),
                  child: const Text('Oktave -1'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _transposeOctave(1),
                  child: const Text('Oktave +1'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Rohes XML anzeigen
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _rawXml ?? '',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
