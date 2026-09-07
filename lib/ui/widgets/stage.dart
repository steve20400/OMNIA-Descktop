import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/media_file.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../file_dialogs.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';
import 'recent_files_menu.dart';

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

    final Widget content;
    if (state.status == PlaybackStatus.error) {
      content = _ErrorStage(
        key: const ValueKey('error'),
        error: state.error ?? const PlaybackError(PlaybackErrorCode.unknown),
        file: state.file,
      );
    } else if (!state.hasFile) {
      content = const _EmptyStage(key: ValueKey('empty'));
    } else if (state.hasVideo) {
      content = const _VideoStage(key: ValueKey('video'));
    } else {
      content = _AudioStage(key: const ValueKey('audio'), file: state.file!);
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

/// Vue audio de Phase 1 : nom du morceau et symbole. La pochette et le fond
/// dérivé arrivent en Phase 5.
class _AudioStage extends StatelessWidget {
  const _AudioStage({super.key, required this.file});

  final MediaFile file;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OmniaMetrics.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                color: colors.curtain,
                borderRadius: OmniaMetrics.overlayRadius,
                border: Border.all(color: colors.seam),
              ),
              child: Icon(Icons.music_note_rounded, size: 56, color: colors.dust),
            ),
            const SizedBox(height: OmniaMetrics.space5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                file.baseName,
                style: type.viewTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: OmniaMetrics.space2),
            Text(l10n.audioOnly, style: type.secondary),
          ],
        ),
      ),
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
                  shortcut: 'Ctrl+O',
                  primary: true,
                  onPressed: () => pickAndOpenFile(ref),
                ),
                OmniaButton(
                  label: l10n.openFolder,
                  icon: Icons.folder_outlined,
                  shortcut: 'Ctrl+Shift+O',
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
