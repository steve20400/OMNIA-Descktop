import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/media_file.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../document_search.dart';
import '../document_search_provider.dart';
import '../file_dialogs.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'audio_stage.dart';
import 'omnia_button.dart';
import 'pdf_stage.dart';
import 'recent_files_menu.dart';
import 'text_view.dart';

/// La scène : la zone plein cadre où vit le contenu.
///
/// Selon l'état, elle affiche la vidéo, une vue audio, l'état vide ou une
/// erreur, avec un fondu doux entre les transitions.
class Stage extends ConsumerWidget {
  const Stage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateProvider);
    final colors = context.colors;

    final textDocument = ref.watch(textDocumentProvider);

    final Widget content;
    if (state.status == PlaybackStatus.error) {
      content = _ErrorStage(
        key: const ValueKey('error'),
        error: state.error ?? const PlaybackError(PlaybackErrorCode.unknown),
        file: state.file,
      );
    } else if (!state.hasFile) {
      content = const _EmptyStage(key: ValueKey('empty'));
    } else if (state.mediaType == MediaType.text && textDocument != null) {
      content = TextView(
        key: ValueKey('text:${textDocument.path}'),
        document: textDocument,
        search: ref.watch(documentSearchProvider) as PlainTextSearch?,
      );
    } else if (state.mediaType == MediaType.pdf) {
      content = const PdfStage(key: ValueKey('pdf'));
    } else if (state.isDocument) {
      // Document en cours de chargement.
      content = const SizedBox.shrink(key: ValueKey('doc-loading'));
    } else if (state.hasVideo) {
      content = const _VideoStage(key: ValueKey('video'));
    } else {
      content = AudioStage(key: const ValueKey('audio'), file: state.file!);
    }

    return ColoredBox(
      color: colors.velvet,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: OmniaMotion.stage,
            switchInCurve: OmniaMotion.stageCurve,
            switchOutCurve: OmniaMotion.concealCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: content,
          ),
          if (state.status == PlaybackStatus.loading)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoStage extends ConsumerWidget {
  const _VideoStage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(videoControllerProvider);
    return Video(
      controller: controller,
      controls: NoVideoControls,
      fill: context.colors.velvet,
    );
  }
}

class _EmptyStage extends ConsumerWidget {
  const _EmptyStage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OmniaMetrics.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.appTitle,
              style: type.wordmark.copyWith(fontSize: 16, letterSpacing: 9),
            ),
            const SizedBox(height: OmniaMetrics.space5),
            Text(l10n.emptyStageHint, style: type.viewTitle, textAlign: TextAlign.center),
            const SizedBox(height: OmniaMetrics.space2),
            Text(l10n.emptyStageSubtitle, style: type.secondary, textAlign: TextAlign.center),
            const SizedBox(height: OmniaMetrics.space6),
            Wrap(
              spacing: OmniaMetrics.space3,
              runSpacing: OmniaMetrics.space3,
              alignment: WrapAlignment.center,
              children: [
                OmniaButton(
                  label: l10n.openFile,
                  icon: Icons.insert_drive_file_outlined,
                  shortcut: ref.shortcutOf(ShortcutAction.openFile, l10n),
                  primary: true,
                  onPressed: () => pickAndOpenFile(ref),
                ),
                OmniaButton(
                  label: l10n.openFolder,
                  icon: Icons.folder_outlined,
                  shortcut: ref.shortcutOf(ShortcutAction.openFolder, l10n),
                  onPressed: () => pickAndOpenFolder(ref),
                ),
              ],
            ),
            const SizedBox(height: OmniaMetrics.space8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const RecentFilesList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorStage extends ConsumerWidget {
  const _ErrorStage({super.key, required this.error, required this.file});

  final PlaybackError error;
  final MediaFile? file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    final message = switch (error.code) {
      PlaybackErrorCode.fileNotFound => l10n.errorFileNotFound,
      PlaybackErrorCode.unsupportedFormat => l10n.errorUnsupported,
      PlaybackErrorCode.decodeFailed => l10n.errorDecode,
      PlaybackErrorCode.permissionDenied => l10n.errorPermission,
      PlaybackErrorCode.emptyFolder => l10n.errorEmptyFolder,
      PlaybackErrorCode.protectedDocument => l10n.errorProtectedDocument,
      PlaybackErrorCode.unknown => l10n.errorUnknown,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OmniaMetrics.space6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: colors.alert),
              const SizedBox(height: OmniaMetrics.space4),
              Text(l10n.errorTitle, style: type.viewTitle, textAlign: TextAlign.center),
              const SizedBox(height: OmniaMetrics.space2),
              Text(message, style: type.body, textAlign: TextAlign.center),
              if (file != null) ...[
                const SizedBox(height: OmniaMetrics.space3),
                Text(
                  file!.name,
                  style: type.caption,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: OmniaMetrics.space5),
              Text(l10n.errorHint, style: type.secondary, textAlign: TextAlign.center),
              const SizedBox(height: OmniaMetrics.space4),
              OmniaButton(
                label: l10n.openAnotherFile,
                icon: Icons.folder_open_rounded,
                onPressed: () => pickAndOpenFile(ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
