import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../help_overlay_controller.dart';
import '../player_focus.dart';
import '../settings/settings_controller.dart';
import '../shortcuts/keymap_provider.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'floating_surface.dart';
import 'key_cap.dart';
import 'omnia_button.dart';
import 'omnia_icon_button.dart';

/// Récapitulatif des raccourcis (`F1`).
///
/// Lu dans la table de l'utilisateur, pas dans une liste figée : un raccourci
/// réaffecté dans les paramètres apparaît ici tel quel, dans la langue de
/// l'interface.
class HelpOverlay extends ConsumerWidget {
  const HelpOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(helpVisibleProvider);
    final colors = context.colors;

    ref.listen<bool>(helpVisibleProvider, (previous, next) {
      if (previous == true && !next) ref.read(playerFocusProvider).restore();
    });

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
                child: visible ? const _HelpCard() : const SizedBox.shrink(),
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
    final size = MediaQuery.sizeOf(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 760,
        maxHeight: math.max(240, size.height - 2 * OmniaMetrics.space5),
      ),
      child: FloatingSurface(
        padding: const EdgeInsets.all(OmniaMetrics.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.helpTitle, style: type.viewTitle)),
                OmniaButton(
                  label: l10n.settingsSectionShortcuts,
                  icon: Icons.keyboard_outlined,
                  onPressed: () {
                    ref.read(helpVisibleProvider.notifier).hide();
                    ref.read(settingsUiProvider.notifier).show(SettingsSection.shortcuts);
                  },
                ),
                const SizedBox(width: OmniaMetrics.space2),
                OmniaIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '${l10n.helpClose}  ·  ${l10n.keyEscape}',
                  onPressed: () => ref.read(helpVisibleProvider.notifier).hide(),
                ),
              ],
            ),
            const SizedBox(height: OmniaMetrics.space2),
            Text(l10n.helpSubtitle, style: type.secondary),
            const SizedBox(height: OmniaMetrics.space4),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: OmniaMetrics.space6,
                  runSpacing: OmniaMetrics.space5,
                  children: [
                    for (final group in ShortcutGroup.values)
                      SizedBox(width: 320, child: _HelpGroup(group: group)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: OmniaMetrics.space4),
            Text(
              [
                '${l10n.keyDoubleClick} : ${l10n.fullscreen}',
                '${l10n.keyWheel} : ${l10n.helpVolume}',
                '${l10n.keyCtrlWheel} : ${l10n.docZoomIn}',
              ].join('   ·   '),
              style: type.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpGroup extends ConsumerWidget {
  const _HelpGroup({required this.group});

  final ShortcutGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final keymap = ref.watch(keymapProvider);
    final prefs = ref.watch(preferencesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.label(l10n).toUpperCase(),
          style: type.caption.copyWith(
            color: colors.projector,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: OmniaMetrics.space2),
        for (final action in group.actions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(actionLabel(action, l10n, prefs), style: type.body)),
                const SizedBox(width: OmniaMetrics.space3),
                if (keymap.combosFor(action).isEmpty)
                  KeyCap(l10n.shortcutsNone, muted: true)
                else
                  Wrap(
                    spacing: OmniaMetrics.space1,
                    children: [
                      for (final combo in keymap.combosFor(action))
                        KeyCap(comboLabel(combo, l10n)),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
