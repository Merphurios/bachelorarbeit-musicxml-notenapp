import 'dart:io';
import 'music_xml_editor_screen.dart';
import 'music_xml_viewer_screen.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart' as xml;

import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Notes App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaleFactor.clamp(0.8,1.2);

        return MediaQuery(
          data: mq.copyWith(textScaleFactor: clamped),
          child: child!,
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _signInAnonymously();
  }

  Future<void> _signInAnonymously() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: Text('Anmeldung fehlgeschlagen')),
          );
        }
        return const WorkListScreen();
      },
    );
  }
}

class WorkListScreen extends StatelessWidget {
  const WorkListScreen({super.key});

  // Stück + alle Versionen + lokale PDFs löschen
  Future<void> _deleteWork(
      BuildContext context, String workId, String title) async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Stück löschen?'),
            content: Text(
              'Möchten Sie das Stück "$title" und alle zugehörigen Versionen wirklich löschen?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Löschen'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;

      final firestore = FirebaseFirestore.instance;

      // 1. Alle Versionen zu diesem Work laden
      final versionsSnap = await firestore
          .collection('versions')
          .where('workId', isEqualTo: workId)
          .get();

      // 2. Zu jeder Version die lokale PDF löschen + Version-Dokument löschen
      for (final doc in versionsSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final pdfPath = data['pdfPath'] as String?;
        final musicXmlPath = data['musicXmlPath'] as String?;

        if (pdfPath != null && pdfPath.isNotEmpty) {
          final file = File(pdfPath);
          if (await file.exists()) {
            await file.delete();
          }
        }

        if (musicXmlPath != null && musicXmlPath.isNotEmpty) {
          final file = File(musicXmlPath);
          if (await file.exists()) {
            await file.delete();
          }
        }

        await firestore.collection('versions').doc(doc.id).delete();
      }

      // 3. Work-Dokument löschen
      await firestore.collection('works').doc(workId).delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stück und Versionen gelöscht')),
        );
      }
    } catch (e) {
      debugPrint('Fehler beim Löschen des Stücks: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Löschen des Stücks')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final worksRef = FirebaseFirestore.instance.collection('works');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Stücke'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: worksRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Fehler beim Laden'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Noch keine Stücke vorhanden'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final title = data['title'] ?? 'Ohne Titel';
              final createdAt = data['createdAt'];

              return ListTile(
                title: Text(title),
                subtitle: Text(createdAt?.toDate().toString() ?? ''),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VersionListScreen(
                        workId: doc.id,
                        workTitle: title,
                      ),
                    ),
                  );
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  color: Colors.red,
                  onPressed: () => _deleteWork(context, doc.id, title),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NewWorkScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}


class NewWorkScreen extends StatefulWidget {
  const NewWorkScreen({super.key});

  @override
  State<NewWorkScreen> createState() => _NewWorkScreenState();
}

class _NewWorkScreenState extends State<NewWorkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveWork() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final userId = FirebaseAuth.instance.currentUser?.uid;

      // 1. Work-Dokument anlegen
      final workRef = await firestore.collection('works').add({
        'title': _titleController.text.trim(),
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Erste Version (V1) für dieses Work anlegen
      await firestore.collection('versions').add({
        'workId': workRef.id,
        'label': 'V1 Original',
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'pdfPath': null,
        'musicXmlPath': null,
        'comment': 'Erste Version (noch ohne Dateien)',
        'hasSecondVoice': false,
        'isOriginal': true,
      });


      if (!mounted) return;
      Navigator.of(context).pop(); // zurück zur Liste
    } catch (e) {
      debugPrint('Fehler beim Speichern: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speichern fehlgeschlagen')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neues Stück'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Titel',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Bitte einen Titel eingeben';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveWork,
                  child: _isSaving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Speichern'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VersionListScreen extends StatelessWidget {
  final String workId;
  final String workTitle;

  const VersionListScreen({
    super.key,
    required this.workId,
    required this.workTitle,
  });

  Future<void> _createNewVersion(BuildContext context) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Bisherige Versionen für dieses Werk laden
      final snapshot = await firestore
          .collection('versions')
          .where('workId', isEqualTo: workId)
          .get();

      final count = snapshot.docs.length;

      // 2. Maximal 6 Versionen (inkl. V1 Original)
      if (count >= 6) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Maximal 6 Versionen pro Stück. Bitte zuerst eine Version löschen.',
              ),
            ),
          );
        }
        return;
      }

      // 3. Nächste Versionsnummer bestimmen (einfach: Anzahl + 1)
      final nextNumber = count + 1;
      final defaultLabel = 'V$nextNumber';

      // 4. Dialog für Zusatzinfo anzeigen
      final textController = TextEditingController();

      final info = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Neue Version anlegen'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Label: $defaultLabel'),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  decoration: const InputDecoration(
                    labelText: 'Zusatzinfo (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(textController.text.trim()),
                child: const Text('Anlegen'),
              ),
            ],
          );
        },
      );

      // Nutzer hat abgebrochen
      if (info == null) return;

      final userId = FirebaseAuth.instance.currentUser?.uid;

      // 5. Neue Version in Firestore anlegen
      final versionRef = await firestore.collection('versions').add({
        'workId': workId,
        'label': defaultLabel,
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'pdfPath': null,
        'musicXmlPath': null,
        'comment': info.isEmpty ? '' : info,
        'hasSecondVoice': false,
        'isOriginal': false,
      });

      // 6. Direkt in den Detail-Screen der neuen Version springen
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VersionDetailScreen(
              versionId: versionRef.id,
              workTitle: workTitle,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Fehler beim Anlegen der Version: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Anlegen der Version')),
        );
      }
    }
  }

  Future<void> _deleteVersion(
      BuildContext context, DocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final label = data['label'] ?? 'Version';
      final pdfPath = data['pdfPath'] as String?;
      final isOriginal =
          data['isOriginal'] == true || data['label'] == 'V1 Original';
      final musicXmlPath = data['musicXmlPath'] as String?;

      if (isOriginal) {
        // Sicherheit: Original darf nicht gelöscht werden
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Original-Version kann nicht gelöscht werden.'),
          ),
        );
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Version löschen?'),
            content: Text(
                'Möchten Sie die Version "$label" wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Löschen'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;

      // Lokale PDF löschen
      if (pdfPath != null && pdfPath.isNotEmpty) {
        final file = File(pdfPath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      if (musicXmlPath != null && musicXmlPath.isNotEmpty) {
        final file = File(musicXmlPath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Firestore-Dokument löschen
      await FirebaseFirestore.instance
          .collection('versions')
          .doc(doc.id)
          .delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Version gelöscht')),
        );
      }
    } catch (e) {
      debugPrint('Fehler beim Löschen der Version: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Löschen der Version')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionsRef = FirebaseFirestore.instance
        .collection('versions')
        .where('workId', isEqualTo: workId)
        //.orderBy('createAt', descending: false)
        ;

    return Scaffold(
      appBar: AppBar(
        title: Text('Versionen – $workTitle'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: versionsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Fehler beim Laden der Versionen'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.toList();

          // nach createdAt aufsteigend sortieren (älteste zuerst: V1, dann V2, V3, ...)
          docs.sort((a, b) {
            final ta = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
            final tb = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
            return ta.compareTo(tb);
          });

          if (docs.isEmpty) {
            return const Center(child: Text('Noch keine Versionen vorhanden'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final label = data['label'] ?? 'Ohne Label';
              final createdAt = data['createdAt'];
              final comment = data['comment'] ?? '';
              final isOriginal =
                  data['isOriginal'] == true || data['label'] == 'V1 Original';

              return ListTile(
                title: Text(label),
                subtitle: Text(
                  '${createdAt?.toDate().toString() ?? ''}\n$comment',
                ),
                isThreeLine: comment.isNotEmpty,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VersionDetailScreen(
                        versionId: doc.id,
                        workTitle: workTitle,
                      ),
                    ),
                  );
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  color: Colors.red,
                  onPressed:
                  isOriginal ? null : () => _deleteVersion(context, doc), // Original gesperrt
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNewVersion(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class VersionDetailScreen extends StatelessWidget {
  final String versionId;
  final String workTitle;

  const VersionDetailScreen({
    super.key,
    required this.versionId,
    required this.workTitle,
  });

  Future<void> _addPdfFromPhoto(BuildContext context, String workId) async {
    final picker = ImagePicker();

    final picked = await picker.pickImage(
      source: ImageSource.camera,
    );

    if (picked == null) {
      return;
    }

    try {
      final imageBytes = await picked.readAsBytes();

      final pdf = pw.Document();
      final pdfImage = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) {
            return pw.Center(
              child: pw.Image(
                pdfImage,
                fit: pw.BoxFit.contain,
              ),
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();

      final appDir = await getApplicationDocumentsDirectory();
      final versionDir =
      Directory('${appDir.path}/works/$workId/versions/$versionId');
      await versionDir.create(recursive: true);

      final filePath = '${versionDir.path}/score.pdf';
      final file = File(filePath);

      await file.writeAsBytes(pdfBytes, flush: true);

      await FirebaseFirestore.instance
          .collection('versions')
          .doc(versionId)
          .update({
        'pdfPath': filePath,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF lokal gespeichert')),
        );
      }
    } catch (e) {
      debugPrint('Fehler beim lokalen PDF-Speichern: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Erstellen oder Speichern des PDFs'),
          ),
        );
      }
    }
  }

  Future<void> _pickMusicXml(BuildContext context, String workId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['musicxml', 'xml'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;
      if (pickedFile.path == null) {
        return;
      }

      final sourceFile = File(pickedFile.path!);
      final xmlContent = await sourceFile.readAsString();

      final appDir = await getApplicationDocumentsDirectory();
      final versionDir =
      Directory('${appDir.path}/works/$workId/versions/$versionId');
      await versionDir.create(recursive: true);

      final destPath = '${versionDir.path}/score.musicxml';
      final destFile = File(destPath);

      await destFile.writeAsString(xmlContent, flush: true);

      String? workTitle;
      String? composer;

      try {
        final doc = xml.XmlDocument.parse(xmlContent);

        final workTitleElements = doc.findAllElements('work-title');
        if (workTitleElements.isNotEmpty) {
          workTitle = workTitleElements.first.text.trim();
        }

        final creators = doc.findAllElements('creator');
        for (final c in creators) {
          final typeAttr = c.getAttribute('type');
          if (typeAttr == 'composer') {
            composer = c.text.trim();
            break;
          }
        }
      } catch (e) {
        debugPrint('Fehler beim Parsen der MusicXML: $e');
      }

      await FirebaseFirestore.instance
          .collection('versions')
          .doc(versionId)
          .update({
        'musicXmlPath': destPath,
        'xmlWorkTitle': workTitle,
        'xmlComposer': composer,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MusicXML gespeichert')),
        );
      }
    } catch (e) {
      debugPrint('Fehler beim MusicXML-Import: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Import der MusicXML-Datei'),
          ),
        );
      }
    }
  }

  Future<void> _generateMusicXmlFromPdf(
      BuildContext context,
      String workId,
      String pdfPath,
      ) async {
    try {
      final uri = Uri.parse('http://192.168.2.100:5000/omr');

      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('file', pdfPath),
      );

      final response = await request.send();

      if (response.statusCode != 200) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'OMR-Server-Fehler: ${response.statusCode}',
              ),
            ),
          );
        }
        return;
      }

      final xmlString = await response.stream.bytesToString();

      final appDir = await getApplicationDocumentsDirectory();
      final versionDir =
      Directory('${appDir.path}/works/$workId/versions/$versionId');
      await versionDir.create(recursive: true);

      final destPath = '${versionDir.path}/score.musicxml';
      final destFile = File(destPath);
      await destFile.writeAsString(xmlString, flush: true);

      String? workTitle;
      String? composer;
      try {
        final doc = xml.XmlDocument.parse(xmlString);

        final workTitleElements = doc.findAllElements('work-title');
        if (workTitleElements.isNotEmpty) {
          workTitle = workTitleElements.first.text.trim();
        }

        final creators = doc.findAllElements('creator');
        for (final c in creators) {
          final typeAttr = c.getAttribute('type');
          if (typeAttr == 'composer') {
            composer = c.text.trim();
            break;
          }
        }
      } catch (e) {
        debugPrint('Fehler beim Parsen der OMR-MusicXML: $e');
      }

      await FirebaseFirestore.instance
          .collection('versions')
          .doc(versionId)
          .update({
        'musicXmlPath': destPath,
        'xmlWorkTitle': workTitle,
        'xmlComposer': composer,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('MusicXML aus PDF generiert und gespeichert')),
        );
      }
    } catch (e) {
      debugPrint('Fehler bei OMR-Request: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
            Text('Fehler bei der Verbindung zum OMR-Service'),
          ),
        );
      }
    }
  }

  /// NEU: Editor öffnen
  void _openMusicXmlEditor(
      BuildContext context,
      String? musicXmlPath,
      String workTitle) {
    if (musicXmlPath == null || musicXmlPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kein MusicXML für diese Version vorhanden.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MusicXmlEditorScreen(
          musicXmlPath: musicXmlPath,
          workTitle: workTitle,
          versionId: versionId,
        ),
      ),
    );
  }

  void _openMusicXmlViewer(
      BuildContext context,
      String musicXmlPath,
      String workTitle,
      ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MusicXmlViewerScreen(
          musicXmlPath: musicXmlPath,
          workTitle: workTitle,
          versionId: versionId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docRef =
    FirebaseFirestore.instance.collection('versions').doc(versionId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Version – $workTitle'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: docRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Fehler beim Laden der Version'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return const Center(child: Text('Version nicht gefunden'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final label = data['label'] ?? 'Ohne Label';
          final createdAt = data['createdAt'];
          final comment = data['comment'] ?? '';
          final pdfPath = data['pdfPath'] as String?;
          final musicXmlPath = data['musicXmlPath'] as String?;
          final workId = data['workId'] as String;
          final xmlWorkTitle = data['xmlWorkTitle'] as String?;
          final xmlComposer = data['xmlComposer'] as String?;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(createdAt?.toDate().toString() ?? ''),
                const SizedBox(height: 16),
                if (comment.isNotEmpty) ...[
                  Text(
                    comment,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      (pdfPath != null && pdfPath.isNotEmpty)
                          ? 'PDF vorhanden'
                          : 'Kein PDF gespeichert',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.music_note, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      (musicXmlPath != null && musicXmlPath.isNotEmpty)
                          ? 'MusicXML vorhanden'
                          : 'Keine MusicXML-Datei',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Dateipfade anzeigen'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FileInfoScreen(
                            pdfPath: pdfPath,
                            musicXmlPath: musicXmlPath,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (xmlWorkTitle != null && xmlWorkTitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Werk-Titel (aus XML): $xmlWorkTitle'),
                ],
                if (xmlComposer != null && xmlComposer.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Komponist (aus XML): $xmlComposer'),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => _addPdfFromPhoto(context, workId),
                  child: const Text('Foto aufnehmen & PDF speichern'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _pickMusicXml(context, workId),
                  child: const Text('MusicXML-Datei auswählen'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: pdfPath == null
                      ? null
                      : () =>
                      _generateMusicXmlFromPdf(context, workId, pdfPath),
                  child: const Text('MusicXML aus PDF erzeugen (OMR)'),
                ),
                // Nur anzeigen, wenn eine MusicXML-Datei vorhanden ist
                if (musicXmlPath != null && musicXmlPath.isNotEmpty) ...[
                  const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () =>
                        _openMusicXmlViewer(context, musicXmlPath, workTitle),
                        child: const Text('Noten anzeigen'),
                  ),
                  /*const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () =>
                        _openMusicXmlEditor(context, musicXmlPath, workTitle),
                        child: const Text('MusicXML bearbeiten'),
                    ),*/
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class FileInfoScreen extends StatelessWidget {
  final String? pdfPath;
  final String? musicXmlPath;

  const FileInfoScreen({
    super.key,
    this.pdfPath,
    this.musicXmlPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dateipfade'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lokale Dateien dieser Version',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),

            Text(
              'PDF:',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              pdfPath ?? 'Kein PDF gespeichert',
              style: const TextStyle(fontFamily: 'monospace'),
            ),

            const SizedBox(height: 16),

            Text(
              'MusicXML:',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              musicXmlPath ?? 'Keine MusicXML-Datei gespeichert',
              style: const TextStyle(fontFamily: 'monospace'),
            ),

            const SizedBox(height: 24),
            Text(
              'Hinweis: Diese Pfade zeigen die lokalen Dateien im App-Speicher. '
                  'Sie sind vor allem für Debugging und für die Dokumentation der Bachelorarbeit gedacht.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}


