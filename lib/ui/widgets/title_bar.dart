import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../file_dialogs.dart';
import '../theme/omnia_theme.dart';
import 'omnia_icon_button.dart';

/// Barre de titre personnalisée (fenêtre sans cadre).
///
/// Titre du fichier centré, zone de déplacement sur toute la largeur,
/// double-clic pour agrandir, boutons de fenêtre dessinés à la main.
class TitleBar extends ConsumerWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final fileName = ref.watch(playbackStateProvider.select((s) => s.file?.name));
    final window = ref.watch(windowServiceProvider);

    return SizedBox(
      height: OmniaMetrics.titleBarHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: window.toggleMaximize,
              child: DragToMoveArea(
                child: Container(
                  color: colors.curtain,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 160),
                  child: Text(
                    fileName ?? l10n.appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: type.secondary.copyWith(
                      color: fileName == null ? colors.dust : colors.screen,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                // Sur macOS, les feux tricolores natifs occupent ce coin.
                if (Platform.isMacOS) const SizedBox(width: 76),
                const SizedBox(width: OmniaMetrics.space4),
                Text(l10n.appTitle, style: type.wordmark),
                const SizedBox(width: OmniaMetrics.space3),
                OmniaIconButton(
                  icon: Icons.folder_open_rounded,
                  iconSize: OmniaMetrics.iconSize - 2,
                  size: OmniaMetrics.iconButtonSize - 4,
                  tooltip: '${l10n.openFile}  ·  Ctrl+O',
                  onPressed: () => pickAndOpenFile(ref),
                ),
              ],
            ),
          ),
          if (!Platform.isMacOS)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                children: [
                  _WindowButton(
                    glyph: _WindowGlyph.minimize,
                    tooltip: l10n.minimize,
                    onPressed: window.minimize,
                  ),
                  _WindowButton(
                    glyph: _WindowGlyph.maximize,
                    tooltip: l10n.maximize,
                    onPressed: window.toggleMaximize,
                  ),
                  _WindowButton(
                    glyph: _WindowGlyph.close,
                    tooltip: l10n.closeWindow,
                    danger: true,
                    onPressed: window.close,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum _WindowGlyph { minimize, maximize, close }

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final _WindowGlyph glyph;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hoverBg = widget.danger ? colors.alert : colors.hover;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _hovered ? 1 : 0),
            duration: OmniaMotion.hover,
            curve: OmniaMotion.hoverCurve,
            builder: (context, t, _) => Container(
              width: OmniaMetrics.windowButtonWidth,
              height: OmniaMetrics.titleBarHeight,
              color: Color.lerp(Colors.transparent, hoverBg, t),
              child: CustomPaint(
                painter: _WindowGlyphPainter(
                  glyph: widget.glyph,
                  color: Color.lerp(colors.dust, colors.screen, t)!,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glyphes de fenêtre tracés au trait fin, nets à toutes les densités.
class _WindowGlyphPainter extends CustomPainter {
  const _WindowGlyphPainter({required this.glyph, required this.color});

  final _WindowGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    const s = 4.5; // demi-taille du glyphe
    switch (glyph) {
      case _WindowGlyph.minimize:
        canvas.drawLine(Offset(c.dx - s, c.dy), Offset(c.dx + s, c.dy), paint);
      case _WindowGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: s * 2, height: s * 2),
            const Radius.circular(1.5),
          ),
          paint,
        );
      case _WindowGlyph.close:
        canvas.drawLine(Offset(c.dx - s, c.dy - s), Offset(c.dx + s, c.dy + s), paint);
        canvas.drawLine(Offset(c.dx - s, c.dy + s), Offset(c.dx + s, c.dy - s), paint);
    }
  }

  @override
  bool shouldRepaint(_WindowGlyphPainter old) => old.glyph != glyph || old.color != color;
}
