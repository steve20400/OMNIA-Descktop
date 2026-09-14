import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/commands/player_command.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../file_dialogs.dart';
import '../recent_files.dart';
import '../theme/omnia_theme.dart';
import 'omnia_icon_button.dart';
import 'omnia_menu.dart';

/// Bouton « Ouvrir » de la barre de titre, avec le menu des fichiers récents.
class OpenMenuButton extends ConsumerWidget {
  const OpenMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recents = ref.watch(recentFilesProvider);

    return MenuAnchor(
      consumeOutsideTap: true,
      alignmentOffset: const Offset(0, OmniaMetrics.space1),
      menuChildren: [
        OmniaMenuItem(
          icon: Icons.insert_drive_file_outlined,
          label: l10n.openFile,
          trailing: 'Ctrl+O',
          onPressed: () => pickAndOpenFile(ref),
        ),
        OmniaMenuItem(
          icon: Icons.folder_outlined,
          label: l10n.openFolder,
          trailing: 'Ctrl+Maj+O',
          onPressed: () => pickAndOpenFolder(ref),
        ),
        const OmniaMenuDivider(),
        OmniaMenuHeader(l10n.recentFiles),
        if (recents.isEmpty)
          OmniaMenuItem(label: l10n.noRecentFiles, enabled: false, onPressed: null)
        else ...[
          for (final recent in recents)
            OmniaMenuItem(
              icon: _iconFor(recent),
              label: p.basename(recent.path),
              subtitle: recent.exists ? p.dirname(recent.path) : l10n.recentMissing,
              enabled: recent.exists,
              onPressed: () => ref.dispatch(OpenFile(recent.path)),
            ),
          const OmniaMenuDivider(),
          OmniaMenuItem(
            icon: Icons.delete_sweep_outlined,
            label: l10n.clearRecent,
            // Vide la liste sans oublier où l'on s'était arrêté dans chaque
            // fichier : les positions s'effacent à part, dans les paramètres.
            onPressed: () => ref.dispatch(const ClearRecentFiles()),
          ),
        ],
      ],
      builder: (context, controller, _) => OmniaIconButton(
        icon: Icons.folder_open_rounded,
        iconSize: OmniaMetrics.iconSize - 2,
        size: OmniaMetrics.iconButtonSize - 4,
        tooltip: '${l10n.openFile}  ·  Ctrl+O',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  static IconData _iconFor(RecentFile recent) {
    if (recent.entry.completed) return Icons.check_circle_outline_rounded;
    if (recent.entry.resumePosition != null) return Icons.history_rounded;
    return Icons.insert_drive_file_outlined;
  }
}

/// Liste compacte des récents pour l'état vide de la scène.
class RecentFilesList extends ConsumerWidget {
  const RecentFilesList({super.key, this.limit = 5});

  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final recents = ref.watch(recentFilesProvider).take(limit).toList();

    if (recents.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.recentFiles.toUpperCase(),
          style: type.caption.copyWith(
            color: colors.dust,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: OmniaMetrics.space2),
        for (final recent in recents)
          _RecentRow(recent: recent, onTap: () => ref.dispatch(OpenFile(recent.path))),
      ],
    );
  }
}

class _RecentRow extends StatefulWidget {
  const _RecentRow({required this.recent, required this.onTap});

  final RecentFile recent;
  final VoidCallback onTap;

  @override
  State<_RecentRow> createState() => _RecentRowState();
}

class _RecentRowState extends State<_RecentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final enabled = widget.recent.exists;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: OmniaMotion.hover,
          curve: OmniaMotion.hoverCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: OmniaMetrics.space3,
            vertical: OmniaMetrics.space2,
          ),
          decoration: BoxDecoration(
            color: _hovered && enabled ? colors.hover : Colors.transparent,
            borderRadius: OmniaMetrics.controlRadius,
          ),
          child: Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 16,
                color: enabled ? colors.dust : colors.dust.withValues(alpha: 0.4),
              ),
              const SizedBox(width: OmniaMetrics.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.basename(widget.recent.path),
                      style: type.body.copyWith(
                        color: enabled ? colors.screen : colors.dust.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      enabled ? p.dirname(widget.recent.path) : l10n.recentMissing,
                      style: type.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
