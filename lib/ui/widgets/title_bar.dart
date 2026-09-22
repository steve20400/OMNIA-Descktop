import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../app_close.dart';
import '../settings/settings_controller.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'always_on_top_button.dart';
import 'omnia_connect_dialog.dart';
import 'omnia_icon_button.dart';
import 'recent_files_menu.dart';


/// Barre de titre personnalisée (fenêtre sans cadre).
///
/// Titre du fichier centré, zone de déplacement sur toute la largeur,
/// double-clic pour agrandir, boutons de fenêtre dessinés à la main.
///
/// La place du titre se calcule sur la largeur réelle des deux groupes de
/// boutons : centré tant qu'il le peut, décalé sinon, jamais par-dessus un
/// bouton. Dans une fenêtre étroite, le mot « OMNIA » cède sa place, puis le
/// titre lui-même ; les boutons de fenêtre et la zone de déplacement restent.
class TitleBar extends ConsumerWidget {
  const TitleBar({super.key});

  /// Largeur sous laquelle le mot « OMNIA » s'efface : le nom du fichier
  /// compte davantage.
  static const double wordmarkMinWidth = 480;

  /// Titre le plus étroit qui vaille encore la peine d'être montré.
  static const double minTitleWidth = 80;

  /// Écart minimal entre le titre et chacun des deux groupes.
  static const double titleGap = OmniaMetrics.space3;

  /// Boutons « Ouvrir » et « Paramètres » du groupe de gauche.
  static const double _leftButtonSize = OmniaMetrics.iconButtonSize - 4;

  /// Coin des feux tricolores natifs de macOS.
  static const double _macTrafficLights = 76;

  /// Largeur d'un texte d'une ligne, mise à l'échelle du texte comprise.
  static double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final fileName = ref.watch(playbackStateProvider.select((s) => s.file?.name));
    final window = ref.watch(windowServiceProvider);
    final title = fileName ?? l10n.appTitle;
    final titleStyle = type.secondary.copyWith(
      color: fileName == null ? colors.dust : colors.screen,
    );

    return SizedBox(
      height: OmniaMetrics.titleBarHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final showWordmark = width >= wordmarkMinWidth;

          // Largeurs des deux groupes, calculées sur les mêmes éléments que
          // les rangées ci-dessous : un bouton ajouté là doit l'être ici.
          final leftWidth = (Platform.isMacOS ? _macTrafficLights : 0.0) +
              OmniaMetrics.space4 +
              (showWordmark
                  ? _textWidth(context, l10n.appTitle, type.wordmark) + OmniaMetrics.space3
                  : 0.0) +
              4 * _leftButtonSize;
          final rightWidth = Platform.isMacOS ? 0.0 : 3 * OmniaMetrics.windowButtonWidth;

          final slot = placeTitle(
            barWidth: width,
            leading: leftWidth,
            trailing: rightWidth,
            textWidth: _textWidth(context, title, titleStyle),
          );

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: window.toggleMaximize,
                  child: DragToMoveArea(
                    // Le titre vit dans la zone de déplacement : on déplace la
                    // fenêtre en le saisissant, comme partout ailleurs.
                    child: Container(
                      color: colors.curtain,
                      alignment: Alignment.center,
                      padding: slot == null
                          ? EdgeInsets.zero
                          : EdgeInsets.only(
                              left: slot.left,
                              right: math.max(0.0, width - slot.left - slot.width),
                            ),
                      child: slot == null
                          ? null
                          : Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: titleStyle,
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
                    if (Platform.isMacOS) const SizedBox(width: _macTrafficLights),
                    const SizedBox(width: OmniaMetrics.space4),
                    if (showWordmark) ...[
                      Text(l10n.appTitle, style: type.wordmark),
                      const SizedBox(width: OmniaMetrics.space3),
                    ],
                    const OpenMenuButton(),
                    OmniaIconButton(
                      icon: Icons.settings_outlined,
                      iconSize: OmniaMetrics.iconSize - 2,
                      size: _leftButtonSize,
                      tooltip: ref.tooltipWith(l10n.settingsTitle, ShortcutAction.settings, l10n),
                      active: ref.watch(settingsUiProvider.select((s) => s.visible)),
                      onPressed: () => ref.read(settingsUiProvider.notifier).toggle(),
                    ),
                    const AlwaysOnTopButton(),
                    OmniaIconButton(
                      icon: Icons.wifi_tethering_rounded,
                      iconSize: OmniaMetrics.iconSize - 2,
                      size: _leftButtonSize,
                      tooltip: 'OMNIA Connect (Synchronisation Mobile)',
                      onPressed: () => OmniaConnectDialog.show(context),
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
                        onPressed: () => closeApplication(ref, context),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Emplacement du titre dans la barre : abscisse de départ et largeur.
typedef TitleSlot = ({double left, double width});

/// Place du titre entre le groupe de gauche ([leading] pixels) et celui de
/// droite ([trailing] pixels), dans une barre de [barWidth] pixels.
///
/// Centré sur la barre quand il le peut ; sinon décalé juste ce qu'il faut
/// pour garder [gap] pixels de chaque groupe, et abrégé s'il est plus long
/// que la place. `null` : moins de [minWidth] pixels entre les groupes, le
/// titre ne s'affiche pas.
TitleSlot? placeTitle({
  required double barWidth,
  required double leading,
  required double trailing,
  required double textWidth,
  double gap = TitleBar.titleGap,
  double minWidth = TitleBar.minTitleWidth,
}) {
  final start = leading + gap;
  final end = barWidth - trailing - gap;
  final room = end - start;
  if (room < minWidth) return null;
  final width = math.min(math.max(0.0, textWidth), room);
  final left = ((barWidth - width) / 2).clamp(start, end - width).toDouble();
  return (left: left, width: width);
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
