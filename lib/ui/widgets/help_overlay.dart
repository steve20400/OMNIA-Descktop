import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../help_overlay_controller.dart';
import '../theme/omnia_theme.dart';
import 'floating_surface.dart';
import 'omnia_icon_button.dart';

/// Récapitulatif des raccourcis (`F1`).
///
/// Un voile sur la scène, une surface flottante, deux colonnes. Les touches
/// sont en mono, dans une petite capsule, pour se lire comme sur un clavier.
class HelpOverlay extends ConsumerWidget {
  const HelpOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(helpVisibleProvider);
    final colors = context.colors;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: OmniaMotion.reveal,
        curve: visible ? OmniaMotion.revealCurve : OmniaMotion.concealCurve,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(helpVisibleProvider.notifier).hide(),
          child: ColoredBox(
            color: colors.overlayScrim,
            child: Center(
              child: GestureDetector(
                // Un clic dans la carte ne doit pas la fermer.
                onTap: () {},
                child: const _HelpCard(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpCard extends ConsumerWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    final groups = <(String, List<(String, String)>)>[
      (
        l10n.helpGroupPlayback,
        [
          (l10n.helpPlayPause, 'Espace'),
          (l10n.helpSeekShort, '← →'),
          (l10n.helpSeekMedium, 'Maj + ← →'),
          (l10n.helpSeekLong, 'Ctrl + ← →'),
          (l10n.helpVolume, '↑ ↓'),
          (l10n.mute, 'M'),
          (l10n.helpSpeed, '+  −'),
          (l10n.resetSpeed, '='),
          (l10n.abLoop, 'A'),
          (l10n.subtitles, 'V'),
          (l10n.screenshot, 'S'),
        ],
      ),
      (
        l10n.helpGroupNavigation,
        [
          (l10n.nextFile, 'N'),
          (l10n.previousFile, 'P'),
          (l10n.endModeLabel, 'L'),
          (l10n.helpPanelToggle, 'Tab'),
          (l10n.helpLeaveSearch, 'Échap'),
        ],
      ),
      (
        l10n.helpGroupWindow,
        [
          (l10n.fullscreen, 'F  ·  double-clic'),
          (l10n.exitFullscreen, 'Échap'),
          (l10n.alwaysOnTop, 'T'),
          (l10n.miniPlayer, 'Ctrl + Maj + M'),
          (l10n.openFile, 'Ctrl + O'),
          (l10n.openFolder, 'Ctrl + Maj + O'),
          (l10n.helpTitle, 'F1'),
        ],
      ),
      (
        l10n.helpGroupDocuments,
        [
          (l10n.docPreviousPage, 'PgUp'),
          (l10n.docNextPage, 'PgDn'),
          (l10n.docGoToPage, 'Ctrl + G'),
          (l10n.docFind, 'Ctrl + F'),
          (l10n.docZoomIn, 'Ctrl + molette'),
          (l10n.docFitWidth, 'Ctrl + 0'),
          (l10n.docRotate, 'Ctrl + R'),
          (l10n.docReadingDark, 'Ctrl + D'),
        ],
      ),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: FloatingSurface(
        padding: const EdgeInsets.all(OmniaMetrics.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.helpTitle, style: type.viewTitle)),
                OmniaIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '${l10n.helpClose}  ·  Échap',
                  onPressed: () => ref.read(helpVisibleProvider.notifier).hide(),
                ),
              ],
            ),
            const SizedBox(height: OmniaMetrics.space2),
            Text(l10n.helpSubtitle, style: type.secondary),
            const SizedBox(height: OmniaMetrics.space5),
            Wrap(
              spacing: OmniaMetrics.space6,
              runSpacing: OmniaMetrics.space5,
              children: [
                for (final (title, rows) in groups)
                  SizedBox(
                    width: 300,
                    child: _HelpGroup(title: title, rows: rows),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpGroup extends StatelessWidget {
  const _HelpGroup({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: type.caption.copyWith(
            color: colors.projector,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: OmniaMetrics.space2),
        for (final (label, keys) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(label, style: type.body)),
                const SizedBox(width: OmniaMetrics.space3),
                _KeyCap(keys),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.keys);

  final String keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OmniaMetrics.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.velvet,
        borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
        border: Border.all(color: colors.seam),
      ),
      child: Text(keys, style: type.timecode.copyWith(fontSize: 12)),
    );
  }
}
