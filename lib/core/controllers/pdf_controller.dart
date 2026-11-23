import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

import '../commands/player_command.dart';
import '../models/document_layout.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/pdf_note.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import '../services/pdf_notes_engine.dart';
import '../utils/outline_flattener.dart';
import 'media_controller.dart';

/// Un PDF ouvert : le document pdfium, son sommaire aplati et le contrôleur
/// de vue que le widget pdfrx pilote.
class PdfSession {
  const PdfSession({
    required this.path,
    required this.document,
    required this.outline,
    required this.viewer,
    this.notes = const [],
    this.notesEditable = false,
    this.notesError,
  });

  final String path;
  final PdfDocument document;
  final List<OutlineItem> outline;
  final PdfViewerController viewer;

  /// Les notes du document, relevées après l'ouverture : la liste arrive un
  /// instant après les pages.
  final List<PdfNote> notes;

  /// Vrai quand on peut écrire dans ce PDF : fichier modifiable, et
  /// document qui autorise les annotations.
  final bool notesEditable;

  /// Pourquoi la dernière note n'a pas pu être écrite, `null` si elle l'a
  /// été.
  final String? notesError;

  int get pageCount => document.pages.length;

  PdfSession copyWith({List<PdfNote>? notes, String? notesError, bool clearNotesError = false}) =>
      PdfSession(
        path: path,
        document: document,
        outline: outline,
        viewer: viewer,
        notes: notes ?? this.notes,
        notesEditable: notesEditable,
        notesError: clearNotesError ? null : notesError ?? this.notesError,
      );
}

/// Remplace le fichier [path] par [bytes]. Injectable pour les tests.
typedef PdfFileWriter = Future<void> Function(String path, Uint8List bytes);

/// Écrit d'abord une copie à côté, puis la met à la place de l'original :
/// une coupure en pleine écriture laisse l'ancien PDF intact. Si le dossier
/// refuse la copie (dossier synchronisé, droits), l'écriture se fait en
/// place.
Future<void> replacePdfFile(String path, Uint8List bytes) async {
  final temp = File('$path.omnia-notes');
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
    return;
  } on FileSystemException {
    try {
      if (temp.existsSync()) await temp.delete();
    } on FileSystemException {
      // La copie restera : elle ne gêne personne.
    }
  }
  await File(path).writeAsBytes(bytes, flush: true);
}

/// Vrai si le document permet d'y poser des notes : un PDF protégé peut
/// l'interdire. Sans protection, pas de restriction.
bool _allowsAnnotations(PdfDocument document) {
  try {
    return document.permissions?.allowsModifyAnnotations ?? true;
  } on Object {
    // Document qui ne sait pas répondre : on ne promet pas d'écrire dedans.
    return false;
  }
}

/// Vrai si [path] s'ouvre en écriture. Vérifié avant que pdfium n'ouvre le
/// fichier : sous Windows, une fois ouvert par pdfium, il ne se laisse plus
/// ouvrir en écriture par personne.
bool _isWritable(String path) {
  try {
    File(path).openSync(mode: FileMode.append).closeSync();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Ouvre un document pdfium. Injectable : pdfium est une bibliothèque native
/// que les tests n'ont pas, et toute la logique de page et de zoom se vérifie
/// sans lui.
typedef PdfDocumentOpener = Future<PdfDocument> Function(String path);

/// L'ouverture réelle, par pdfium.
///
/// Sans fournisseur de mot de passe, un document protégé lève
/// [PdfPasswordException] : c'est le comportement voulu, OMNIA ne demande pas
/// de mot de passe (lecture seule, pas de saisie de secret).
Future<PdfDocument> _openWithPdfium(String path) async {
  await pdfrxFlutterInitialize();
  return PdfDocument.openFile(path, firstAttemptByEmptyPassword: true);
}

/// Contrôleur des documents PDF (pdfium via pdfrx).
///
/// Il ouvre le document une seule fois (nombre de pages, sommaire, détection
/// de protection) et le confie à la vue. Les commandes de page et de zoom
/// passent par le [PdfViewerController] quand la vue continue est montée ;
/// en mode page par page, seul l'état change et la vue le suit.
class PdfController implements MediaController {
  PdfController({
    PdfViewerController? viewer,
    PdfDocumentOpener? openDocument,
    PdfNotesEngine? notes,
    PdfFileWriter? writeFile,
  })  : viewer = viewer ?? PdfViewerController(),
        _openDocument = openDocument ?? _openWithPdfium,
        // Le vrai pdfium va avec le vrai moteur de notes ; un document
        // factice de test n'en a pas.
        _notes = notes ?? (openDocument == null ? const PdfiumNotesEngine() : const NoPdfNotesEngine()),
        _writeFile = writeFile ?? replacePdfFile {
    this.viewer.addListener(_onViewerChanged);
  }

  final PdfNotesEngine _notes;
  final PdfFileWriter _writeFile;

  /// La lecture des notes en cours : le document ne se ferme pas tant
  /// qu'elle n'est pas finie, pdfium la mènerait dans un document libéré.
  Future<void>? _readingNotes;

  /// Contrôleur pdfrx, unique pour toute la vie de l'application : la vue le
  /// prend en charge quand elle est montée.
  final PdfViewerController viewer;

  final PdfDocumentOpener _openDocument;

  final StreamController<PdfSession?> _sessions = StreamController<PdfSession?>.broadcast();

  PdfSession? _session;
  PlaybackStateSink? _sink;
  int? _targetPage;

  /// Dernière page annoncée par pdfrx, `null` tant qu'une vue neuve n'en a
  /// annoncé aucune. Voir [_onViewerChanged].
  int? _lastSeenPage;

  /// Relances de navigation déjà tentées vers [_targetPage].
  int _restoreAttempts = 0;

  /// Chaque relance fait bouger la vue, donc repasse par [_onViewerChanged] :
  /// sans borne, une page cible que la vue n'atteint jamais ferait tourner
  /// OMNIA en rond au lieu d'afficher le document.
  static const int _maxRestoreAttempts = 8;

  PdfSession? get session => _session;
  Stream<PdfSession?> get sessions => _sessions.stream;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.pdf};

  void _publish(PdfSession? session) {
    _session = session;
    if (!_sessions.isClosed) _sessions.add(session);
  }

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    _sink = sink;
    _targetPage = null;
    _lastSeenPage = null;
    _restoreAttempts = 0;
    final pendingPage = sink.state.currentPage > 0 ? sink.state.currentPage : 1;
    sink.update(
      (st) => st.copyWith(
        file: file,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: false,
        currentPage: pendingPage,
        totalPages: 0,
        rotation: 0,
        zoom: 1.0,
        scrollFraction: 0,
        clearError: true,
      ),
    );

    if (!File(file.path).existsSync()) {
      await _closeSession();
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: const PlaybackError(PlaybackErrorCode.fileNotFound),
        ),
      );
      return;
    }

    // Avant pdfium : une fois le fichier ouvert par lui, Windows ne le
    // laisse plus ouvrir en écriture, et la réponse serait toujours non.
    final writable = _isWritable(file.path);

    try {
      final document = await _openDocument(file.path);
      final nodes = await document.loadOutline();
      final outline = flattenOutline<PdfOutlineNode>(
        nodes,
        title: (n) => n.title,
        page: (n) => n.dest?.pageNumber,
        children: (n) => n.children,
      );

      await _closeSession();
      final session = PdfSession(
        path: file.path,
        document: document,
        outline: outline,
        viewer: viewer,
        notesEditable: writable && _allowsAnnotations(document),
      );
      _publish(session);
      _readNotes(session);

      final targetPage = pendingPage.clamp(1, document.pages.length);
      _targetPage = targetPage > 1 ? targetPage : null;

      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.playing,
          currentPage: targetPage,
          totalPages: document.pages.length,
        ),
      );
    } on PdfPasswordException {
      await _closeSession();
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: const PlaybackError(PlaybackErrorCode.protectedDocument),
        ),
      );
    } on Object catch (e) {
      await _closeSession();
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: e.toString()),
        ),
      );
    }
  }

  /// Relève les notes du document, puis les publie avec la session.
  void _readNotes(PdfSession session) {
    final reading = _notes.read(session.document).then((notes) {
      final current = _session;
      if (current == null || !identical(current.document, session.document)) return;
      if (notes.isNotEmpty) _publish(current.copyWith(notes: notes));
    }).catchError((Object _) {
      // Notes illisibles : le document s'affiche quand même, sans elles.
    });
    _readingNotes = reading;
  }

  /// Ajoute, modifie ou efface une note, puis enregistre le PDF.
  ///
  /// Le document est fermé avant que le fichier ne soit remplacé — Windows
  /// refuse de remplacer un fichier ouvert —, puis rouvert à la même page :
  /// les pages se redessinent avec la note, et la liste des notes est
  /// relue du fichier.
  Future<void> _changeNotes(PdfNoteChange change) async {
    final session = _session;
    final sink = _sink;
    final file = sink?.state.file;
    if (session == null || sink == null || file == null || !session.notesEditable) return;
    await _readingNotes;

    String? failure;
    Uint8List? bytes;
    try {
      bytes = await _notes.apply(session.document, [change]);
    } on Object {
      failure = 'La note n’a pas pu être écrite dans ce PDF.';
    }

    await _closeSession();
    if (bytes != null) {
      try {
        await _writeFile(file.path, bytes);
      } on Object {
        failure = 'Le PDF n’a pas pu être enregistré : le fichier est peut-être '
            'ouvert ailleurs, ou en lecture seule.';
      }
    }
    await open(file, sink);
    final reopened = _session;
    if (failure != null && reopened != null) {
      _publish(reopened.copyWith(notesError: failure));
    }
  }

  /// La vue a bougé (défilement, zoom) : on reflète page et zoom dans l'état.
  void _onViewerChanged() {
    final sink = _sink;
    if (sink == null || _session == null) return;
    if (!viewer.isReady) {
      // Vue démontée ou pas encore prête : la prochaine page annoncée sera la
      // première de cette vue-là. Voir le garde de l'artéfact plus bas.
      _lastSeenPage = null;
      return;
    }
    final page = viewer.pageNumber;
    final previous = _lastSeenPage;
    _lastSeenPage = page;
    final target = _targetPage;
    if (target != null) {
      if (page == target) {
        _targetPage = null;
        _restoreAttempts = 0;
      } else {
        // En transition vers la page cible : s'assurer que le visualiseur est bien
        // en train d'y naviguer, sans y revenir indéfiniment ([_maxRestoreAttempts]).
        if (_restoreAttempts < _maxRestoreAttempts) {
          _restoreAttempts++;
          unawaited(viewer.goToPage(pageNumber: target, anchor: PdfPageAnchor.top));
        } else {
          _targetPage = null;
          _restoreAttempts = 0;
        }
        return;
      }
    } else if (page == 1 && previous == null && sink.state.currentPage > 1) {
      // Artéfact d'initialisation de pdfrx (montage d'une nouvelle vue lors de la
      // bascule mini-lecteur ⬌ fenêtre normale) : la vue annonce la page 1 avant
      // d'avoir appliqué celle qu'on lui demande. On la remet où l'utilisateur en
      // était, sans écraser la page courante.
      //
      // `previous == null` est ce qui empêche ce garde de se retourner contre
      // l'utilisateur : une page 1 annoncée APRÈS une autre page, c'est quelqu'un
      // qui vient de remonter en haut du document. Sans cette condition, chaque
      // remontée vers la première page était renvoyée vers le bas — le défilement
      // ne « descendait » plus que, et la première page devenait inatteignable.
      _targetPage = sink.state.currentPage;
      _restoreAttempts = 0;
      unawaited(viewer.goToPage(pageNumber: sink.state.currentPage, anchor: PdfPageAnchor.top));
      return;
    }
    final cover = viewer.coverScale;
    final zoom = cover > 0 ? viewer.currentZoom / cover : sink.state.zoom;
    _noteScroll();
    final changedPage = page != null && page != sink.state.currentPage;
    final changedZoom = zoom.isFinite && (zoom - sink.state.zoom).abs() > 0.001;
    if (!changedPage && !changedZoom) return;
    sink.update(
      (st) => st.copyWith(
        currentPage: changedPage ? page : null,
        zoom: changedZoom ? zoom.clamp(PlaybackState.minZoom, PlaybackState.maxZoom) : null,
      ),
    );
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    final sink = _sink;
    final session = _session;
    if (sink == null || session == null) return false;
    final state = sink.state;

    switch (command) {
      case NextPage():
        await _goToPage(state.currentPage + 1);
      case PreviousPage():
        await _goToPage(state.currentPage - 1);
      case GoToPage(:final page):
        await _goToPage(page);
      case ZoomRelative(:final factor):
        await _setZoom(state.zoom * factor);
      case SetZoom(:final zoom):
        await _setZoom(zoom);
      case FitZoom(:final mode):
        await _fit(mode);
      case RotateDocument(:final quarterTurns):
        sink.update((st) => st.copyWith(rotation: (st.rotation + quarterTurns) % 4));
      case ToggleReadingDarkMode():
        sink.update((st) => st.copyWith(readingDark: !st.readingDark));
      case SetDocumentLayout(:final layout):
        sink.update((st) => st.copyWith(documentLayout: layout));
      case ToggleDocumentLayout():
        sink.update((st) => st.copyWith(documentLayout: st.documentLayout.other));
      case AddPdfNote(:final page, :final x, :final y, :final text):
        await _changeNotes(PdfNoteAdded(page: page, x: x, y: y, text: text));
      case AddPdfHighlight(:final page, :final quads, :final text):
        await _changeNotes(PdfHighlightAdded(page: page, quads: quads, text: text));
      case EditPdfNote(:final page, :final index, :final text):
        await _changeNotes(PdfNoteEdited(page: page, index: index, text: text));
      case DeletePdfNote(:final page, :final index):
        await _changeNotes(PdfNoteDeleted(page: page, index: index));
      case ScrollTo(:final fraction):
        // La position dans le document, de 0 à 1 : c'est ce que transmet la
        // lecture miroir, parce que deux fenêtres de formes différentes ne
        // s'accordent ni sur les pixels ni sur la page courante.
        if (viewer.isReady) {
          try {
            final visible = viewer.visibleRect;
            final travel = viewer.documentSize.height - visible.height;
            if (travel > 0) {
              final top = fraction.clamp(0.0, 1.0) * travel;
              await viewer.setZoom(
                Offset(visible.center.dx, top + visible.height / 2),
                viewer.currentZoom,
                duration: Duration.zero,
              );
            }
          } on Object {
            // Vue en cours de mise en page : sa géométrie n'existe pas
            // encore. L'état suivant du miroir rattrapera ce défilement.
          }
        }
      case ScrollDocument(:final delta):
        if (viewer.isReady) {
          final center = viewer.visibleRect.center;
          // Sans durée : pdfrx anime sur 200 ms par défaut, et cette commande
          // est attendue dans la file du service. Chaque cran de molette
          // bloquait donc la file un cinquième de seconde, les crans arrivant
          // bien plus vite que cela — ils s'empilaient, et le document
          // continuait de défiler longtemps après qu'on avait lâché la molette.
          await viewer.setZoom(
            Offset(center.dx, center.dy + delta),
            viewer.currentZoom,
            duration: Duration.zero,
          );
        }
      default:
        return false;
    }
    return true;
  }

  Future<void> _goToPage(int page) async {
    final sink = _sink!;
    final total = sink.state.totalPages;
    if (total <= 0) return;
    final target = page.clamp(1, total);
    _targetPage = target;
    _restoreAttempts = 0;
    if (viewer.isReady) {
      // Lancée, jamais attendue. pdfrx anime ce déplacement, et une animation
      // Flutter interrompue ne se termine pas : son futur reste en suspens
      // pour toujours. Or n'importe quoi l'interrompt — un redimensionnement
      // de la fenêtre, un geste, la commande suivante. Attendue ici, dans la
      // file strictement ordonnée du service, elle emportait alors toutes les
      // commandes suivantes : le lecteur s'affichait encore, mais n'obéissait
      // plus à rien.
      unawaited(viewer.goToPage(pageNumber: target, anchor: PdfPageAnchor.top));
    }
    // Mode page par page (pas de vue continue montée) ou vue en retard : on
    // écrit l'état, la vue suit.
    if (sink.state.currentPage != target) {
      sink.update((st) => st.copyWith(currentPage: target));
    }
  }

  Future<void> _setZoom(double zoom) async {
    final sink = _sink!;
    final target = zoom.clamp(PlaybackState.minZoom, PlaybackState.maxZoom);
    if (viewer.isReady) {
      // Même raison que pour le changement de page : l'animation du zoom se
      // lance, mais la file ne l'attend pas. Un cran de molette de plus, un
      // redimensionnement, et l'animation en cours était annulée — son futur
      // ne revenait jamais.
      unawaited(
        viewer.setZoom(viewer.visibleRect.center, target * viewer.coverScale),
      );
    }
    sink.update((st) => st.copyWith(zoom: target));
  }

  Future<void> _fit(FitMode mode) async {
    final sink = _sink!;
    if (!viewer.isReady) {
      // Page par page : « largeur » et « page » reviennent à l'échelle 1.
      sink.update((st) => st.copyWith(zoom: 1.0));
      return;
    }
    final cover = viewer.coverScale;
    final scale = switch (mode) {
      FitMode.width => cover,
      FitMode.page => viewer.alternativeFitScale ?? viewer.minScale,
    };
    // Sans animation, et c'est le point le plus important des trois. Cet
    // ajustement est demandé par la vue à chaque image d'un redimensionnement
    // de fenêtre. Animé sur 200 ms et attendu dans la file, il était annulé
    // dès l'image suivante : pdfrx repositionne lui-même la vue à chaque
    // changement de taille, et tout nouveau déplacement remet son animation
    // à zéro. Or une animation annulée ne rend jamais la main. Le premier
    // redimensionnement d'un document suffisait donc à figer le lecteur pour
    // de bon — et tant qu'il durait, la page restait floue, toujours en
    // transition entre deux tailles. Une mise en page suit la fenêtre sans
    // délai ; elle ne s'anime pas.
    await viewer.setZoom(
      viewer.visibleRect.center,
      scale,
      duration: Duration.zero,
    );
    sink.update((st) => st.copyWith(zoom: cover > 0 ? scale / cover : 1.0));
  }

  Timer? _scrollNote;

  /// Publie la position de la vue dans le document, dix fois par seconde au
  /// plus.
  ///
  /// Le lecteur ne publiait que la page courante. Défiler lentement dans une
  /// page ne changeait donc rien à l'état, et la lecture miroir n'avait rien
  /// à transmettre : l'autre appareil ne suivait que les sauts de page.
  ///
  /// Pas à chaque image : la vue bouge soixante fois par seconde pendant un
  /// défilement, et autant de mises à jour de l'état le rendraient saccadé.
  void _noteScroll() {
    _scrollNote ??= Timer(const Duration(milliseconds: 100), () {
      _scrollNote = null;
      final sink = _sink;
      if (sink == null || _session == null || !viewer.isReady) return;
      final double fraction;
      try {
        final visible = viewer.visibleRect;
        final travel = viewer.documentSize.height - visible.height;
        fraction = travel > 0 ? (visible.top / travel).clamp(0.0, 1.0) : 0.0;
      } on Object {
        // Vue en cours de mise en page : rien à publier pour l'instant.
        return;
      }
      if (!fraction.isFinite) return;
      if ((fraction - sink.state.scrollFraction).abs() < 0.0005) return;
      sink.update((st) => st.copyWith(scrollFraction: fraction));
    });
  }

  Future<void> _closeSession() async {
    _scrollNote?.cancel();
    _scrollNote = null;
    _targetPage = null;
    _lastSeenPage = null;
    _restoreAttempts = 0;
    final current = _session;
    if (current == null) return;
    _publish(null);
    // Une lecture des notes en cours finit avant la fermeture : pdfium ne
    // lit pas dans un document libéré.
    final reading = _readingNotes;
    _readingNotes = null;
    if (reading != null) await reading;
    try {
      await current.document.dispose();
    } on Object {
      // Document déjà libéré par pdfium : sans conséquence.
    }
  }

  @override
  Future<void> close() async {
    await _closeSession();
    _sink?.update(
      (st) => st.copyWith(
        clearFile: true,
        status: PlaybackStatus.idle,
        currentPage: 0,
        totalPages: 0,
        clearError: true,
      ),
    );
    _sink = null;
  }

  @override
  Future<void> dispose() async {
    viewer.removeListener(_onViewerChanged);
    await _closeSession();
    await _sessions.close();
  }
}
