// Le contrôleur PDF, sans pdfium.
//
// Toute la navigation (page courante, reprise, défilement) se joue entre
// l'état de lecture et le contrôleur de vue pdfrx : les deux sont remplacés
// ici par des doublures, ce qui permet de rejouer exactement ce que la vraie
// vue annonce — y compris l'annonce de la page 1 d'une vue qui vient d'être
// montée, celle qui empêchait de remonter dans un document.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/controllers/pdf_controller.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/pdf_note.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/services/pdf_notes_engine.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

class _Sink implements PlaybackStateSink {
  PlaybackState _state = const PlaybackState();
  @override
  PlaybackState get state => _state;
  @override
  void update(PlaybackState Function(PlaybackState) reducer) => _state = reducer(_state);
}

/// Une page sans contenu : le contrôleur ne lit que leur nombre.
class _FakePage implements PdfPage {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Un document sans pdfium : un nombre de pages et un sommaire vide.
class _FakeDocument extends PdfDocument {
  _FakeDocument(int pageCount)
      : _pages = List<PdfPage>.generate(pageCount, (_) => _FakePage()),
        super(sourceName: 'test');

  final List<PdfPage> _pages;
  bool disposed = false;

  @override
  List<PdfPage> get pages => _pages;

  @override
  Future<List<PdfOutlineNode>> loadOutline() async => const [];

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Un document sans protection : on peut y poser des notes.
class _EditableDocument extends _FakeDocument {
  _EditableDocument(super.pageCount);

  @override
  PdfPermissions? get permissions => null;
}

/// Les notes en mémoire : celles du « fichier », et les modifications
/// demandées, dans l'ordre.
class _MemoryNotes extends PdfNotesEngine {
  _MemoryNotes(this.notes);

  final List<PdfNote> notes;
  final List<PdfNoteChange> applied = [];
  bool refuse = false;

  @override
  Future<List<PdfNote>> read(PdfDocument document) async => notes;

  @override
  Future<Uint8List> apply(PdfDocument document, List<PdfNoteChange> changes) async {
    if (refuse) throw StateError('refusé par pdfium');
    applied.addAll(changes);
    return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
  }
}

/// La vue pdfrx, réduite à ce que le contrôleur lui demande : la page qu'elle
/// annonce, la zone visible, le zoom — et un moyen de la faire parler
/// ([notify]), comme le fait la vraie vue à chaque mouvement.
class _FakeViewer extends PdfViewerController {
  final List<VoidCallback> _listeners = [];

  /// Les navigations demandées à la vue, dans l'ordre.
  final List<int> goneToPages = [];

  /// Les recentrages demandés à la vue, dans l'ordre.
  final List<Offset> zoomCenters = [];

  bool ready = true;
  int? page = 1;
  double zoom = 1;
  double cover = 1;
  Rect rect = const Rect.fromLTWH(0, 1000, 600, 800);

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// La vue a bougé : elle prévient son contrôleur.
  void notify() {
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  @override
  Matrix4 get value => Matrix4.identity();

  @override
  bool get isReady => ready;

  @override
  int? get pageNumber => page;

  @override
  Rect get visibleRect => rect;

  @override
  double get currentZoom => zoom;

  @override
  double get coverScale => cover;

  @override
  double get minScale => 0.2;

  @override
  double? get alternativeFitScale => 0.8;

  @override
  Future<void> goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    goneToPages.add(pageNumber);
    page = pageNumber;
  }

  @override
  Future<void> setZoom(
    Offset position,
    double zoom, {
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    zoomCenters.add(position);
    this.zoom = zoom;
    rect = Rect.fromCenter(center: position, width: rect.width, height: rect.height);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Directory dir;
  late _FakeViewer viewer;
  late _FakeDocument document;
  late PdfController controller;
  late _Sink sink;
  late MediaFile file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('omnia_pdf_');
    final path = p.join(dir.path, 'rapport.pdf');
    File(path).writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);
    file = MediaFile(path: path, type: MediaType.pdf);
    viewer = _FakeViewer();
    document = _FakeDocument(12);
    sink = _Sink();
    controller = PdfController(
      viewer: viewer,
      openDocument: (_) async => document,
    );
  });

  tearDown(() async {
    await controller.dispose();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  test('ouvre le document et publie sa session', () async {
    await controller.open(file, sink);

    expect(sink.state.status, PlaybackStatus.playing);
    expect(sink.state.totalPages, 12);
    expect(sink.state.currentPage, 1);
    expect(controller.session?.pageCount, 12);
  });

  test('la vue qui descend fait suivre la page courante', () async {
    await controller.open(file, sink);

    viewer.page = 3;
    viewer.notify();

    expect(sink.state.currentPage, 3);
    expect(viewer.goneToPages, isEmpty);
  });

  test('remonter jusqu’à la première page n’est plus renvoyé vers le bas', () async {
    // Le symptôme : dans un PDF, le défilement ne descendait plus que. Passé la
    // première page, chaque remontée vers elle était annulée par le contrôleur,
    // qui prenait l'annonce de pdfrx pour un artéfact de montage.
    await controller.open(file, sink);

    viewer.page = 3;
    viewer.notify();
    viewer.page = 2;
    viewer.notify();
    viewer.goneToPages.clear();

    viewer.page = 1;
    viewer.notify();

    expect(sink.state.currentPage, 1);
    expect(viewer.goneToPages, isEmpty, reason: 'la vue ne doit pas être renvoyée vers le bas');
  });

  test('la première page annoncée par une vue neuve ne remplace pas la page courante', () async {
    // La bascule mini-lecteur ⬌ fenêtre normale monte une nouvelle vue : pdfrx
    // y annonce la page 1 avant d'avoir appliqué celle qu'on lui demande.
    await controller.open(file, sink);
    viewer.page = 5;
    viewer.notify();
    expect(sink.state.currentPage, 5);

    // L'ancienne vue se démonte, la nouvelle n'est pas encore prête.
    viewer.ready = false;
    viewer.notify();
    viewer.ready = true;
    viewer.goneToPages.clear();

    viewer.page = 1;
    viewer.notify();

    expect(sink.state.currentPage, 5, reason: 'la page de l’utilisateur est conservée');
    expect(viewer.goneToPages, [5], reason: 'la vue neuve est remise à la bonne page');
  });

  test('la page de reprise est tenue jusqu’à ce que la vue l’atteigne', () async {
    sink.update((st) => st.copyWith(currentPage: 7));
    await controller.open(file, sink);
    expect(sink.state.currentPage, 7);

    // La vue annonce encore la page 1 : elle n'a pas fini de se placer.
    viewer.page = 1;
    viewer.notify();
    expect(sink.state.currentPage, 7);
    expect(viewer.goneToPages, [7]);

    viewer.notify();
    expect(sink.state.currentPage, 7);

    // Une fois arrivée, la vue reprend la main : l'utilisateur peut remonter.
    viewer.goneToPages.clear();
    viewer.page = 6;
    viewer.notify();
    expect(sink.state.currentPage, 6);
    expect(viewer.goneToPages, isEmpty);
  });

  test('une page cible jamais atteinte finit par être abandonnée', () async {
    // Garde-fou : chaque relance fait bouger la vue, donc repasse par le même
    // code. Sans borne, un document que la vue n'arrive pas à placer ferait
    // tourner OMNIA en rond.
    sink.update((st) => st.copyWith(currentPage: 9));
    await controller.open(file, sink);

    for (var i = 0; i < 40; i++) {
      viewer.page = 1;
      viewer.notify();
    }

    expect(viewer.goneToPages.length, lessThan(20));
    // La vue a de nouveau la parole : l'état suit ce qu'elle annonce.
    viewer.page = 2;
    viewer.notify();
    expect(sink.state.currentPage, 2);
  });

  test('le défilement commandé va dans les deux sens', () async {
    await controller.open(file, sink);
    final start = viewer.rect.center;

    expect(await controller.handle(const ScrollDocument(175)), isTrue);
    final down = viewer.rect.center;
    expect(down.dy, greaterThan(start.dy));

    expect(await controller.handle(const ScrollDocument(-175)), isTrue);
    expect(viewer.rect.center.dy, closeTo(start.dy, 0.001));
  });

  test('le zoom reste borné et se reflète dans l’état', () async {
    await controller.open(file, sink);
    viewer.cover = 2;

    await controller.handle(const SetZoom(3));
    expect(sink.state.zoom, 3);
    expect(viewer.zoom, 6, reason: 'le zoom pdfrx est relatif à l’échelle « largeur »');

    await controller.handle(const ZoomRelative(100));
    expect(sink.state.zoom, PlaybackState.maxZoom);
  });

  test('fichier introuvable → erreur claire, pas de session', () async {
    final missing = MediaFile(path: p.join(dir.path, 'absent.pdf'), type: MediaType.pdf);
    await controller.open(missing, sink);

    expect(sink.state.status, PlaybackStatus.error);
    expect(sink.state.error?.code, PlaybackErrorCode.fileNotFound);
    expect(controller.session, isNull);
  });

  group('Notes', () {
    const seen = PdfNote(
      page: 2,
      index: 0,
      left: 10,
      top: 700,
      right: 34,
      bottom: 676,
      text: 'Vu',
      author: 'Ana',
    );
    late _MemoryNotes notes;
    late List<(String, Uint8List)> written;
    late int opened;

    PdfController notesController({PdfFileWriter? writer}) {
      final created = PdfController(
        viewer: viewer,
        openDocument: (_) async {
          opened++;
          return _EditableDocument(12);
        },
        notes: notes,
        writeFile: writer ?? (path, bytes) async => written.add((path, bytes)),
      );
      addTearDown(created.dispose);
      return created;
    }

    setUp(() {
      notes = _MemoryNotes(const [seen]);
      written = [];
      opened = 0;
    });

    test('les notes du fichier arrivent avec la session', () async {
      final notesOf = notesController();
      await notesOf.open(file, sink);
      await Future<void>.delayed(Duration.zero);

      expect(notesOf.session?.notes, [seen]);
      expect(notesOf.session?.notesEditable, isTrue);
    });

    test('une note ajoutée est écrite, et le document rouvert à la même page', () async {
      final notesOf = notesController();
      sink.update((st) => st.copyWith(currentPage: 4));
      await notesOf.open(file, sink);
      await Future<void>.delayed(Duration.zero);

      final handled = await notesOf.handle(
        const AddPdfNote(page: 4, x: 72, y: 700, text: 'À relire'),
      );

      expect(handled, isTrue);
      final added = notes.applied.single as PdfNoteAdded;
      expect((added.page, added.x, added.y, added.text), (4, 72.0, 700.0, 'À relire'));
      expect(written.single.$1, file.path, reason: 'le PDF lui-même est réécrit');
      expect(opened, 2, reason: 'rouvert pour redessiner les pages avec la note');
      expect(sink.state.currentPage, 4);
      expect(notesOf.session?.notesError, isNull);
    });

    test('modifier et effacer passent par le même chemin', () async {
      final notesOf = notesController();
      await notesOf.open(file, sink);

      await notesOf.handle(const EditPdfNote(page: 2, index: 0, text: 'Relu'));
      await notesOf.handle(const DeletePdfNote(page: 2, index: 0));

      expect(notes.applied, hasLength(2));
      expect(notes.applied.first, isA<PdfNoteEdited>());
      expect(notes.applied.last, isA<PdfNoteDeleted>());
      expect(written, hasLength(2));
    });

    test('un fichier qui refuse l’écriture : le document reste, et le dit', () async {
      final notesOf = notesController(
        writer: (path, bytes) async => throw const FileSystemException('refusé'),
      );
      await notesOf.open(file, sink);

      await notesOf.handle(const DeletePdfNote(page: 2, index: 0));

      expect(notesOf.session, isNotNull, reason: 'le PDF est rouvert tel qu’il était');
      expect(notesOf.session?.notesError, contains('enregistré'));
      expect(sink.state.status, PlaybackStatus.playing);
    });

    test('pdfium qui refuse la note : rien n’est écrit, l’erreur est dite', () async {
      notes.refuse = true;
      final notesOf = notesController();
      await notesOf.open(file, sink);

      await notesOf.handle(const AddPdfNote(page: 1, x: 10, y: 10, text: 'x'));

      expect(written, isEmpty);
      expect(notesOf.session?.notesError, isNotNull);
    });

    test('un document qui ne dit rien de ses droits ne reçoit pas de note', () async {
      // Le document factice des autres tests ne sait pas répondre : par
      // prudence, ses notes ne sont pas modifiables.
      final readOnly = PdfController(
        viewer: viewer,
        openDocument: (_) async => _FakeDocument(3),
        notes: notes,
        writeFile: (path, bytes) async => written.add((path, bytes)),
      );
      addTearDown(readOnly.dispose);
      await readOnly.open(file, sink);

      await readOnly.handle(const AddPdfNote(page: 1, x: 10, y: 10, text: 'x'));

      expect(readOnly.session?.notesEditable, isFalse);
      expect(written, isEmpty);
    });
  });

  group('Enregistrement du PDF', () {
    test('le fichier est remplacé d’un bloc, sans copie laissée à côté', () async {
      final path = p.join(dir.path, 'annoté.pdf');
      File(path).writeAsBytesSync(const [1, 2, 3]);

      await replacePdfFile(path, Uint8List.fromList(const [4, 5, 6, 7]));

      expect(File(path).readAsBytesSync(), [4, 5, 6, 7]);
      expect(File('$path.omnia-notes').existsSync(), isFalse);
    });

    test('les dates au format des PDF', () {
      expect(
        pdfDate(DateTime(2026, 11, 19, 14, 30, 5)),
        matches(RegExp(r"^D:20261119143005[+-]\d\d'\d\d'$")),
      );
    });
  });
}
