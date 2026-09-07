import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../document_ui_controller.dart';
import '../theme/omnia_theme.dart';
import 'floating_surface.dart';
import 'omnia_icon_button.dart';

/// Barre flottante des documents, à la place de la barre de contrôles média :
/// navigation par page, zoom, ajustement, rotation, mode sombre, défilement,
/// recherche. Même surface, même langage que la barre de lecture.
class DocumentBar extends ConsumerStatefulWidget {
  const DocumentBar({super.key});

  @override
  ConsumerState<DocumentBar> createState() => _DocumentBarState();
}

class _DocumentBarState extends ConsumerState<DocumentBar> {
  final TextEditingController _page = TextEditingController();
  final FocusNode _pageFocus = FocusNode(debugLabel: 'omnia.doc.page');
  int _seenGoToRequest = 0;

  @override
  void dispose() {
    _page.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  void _submitPage(String value) {
    final page = int.tryParse(value.trim());
    if (page != null) ref.dispatch(GoToPage(page));
    _pageFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playbackStateProvider);
    final ui = ref.watch(documentUiProvider);

    final isPdf = state.mediaType == MediaType.pdf;
    final hasPages = isPdf && state.totalPages > 0;

    // Le champ suit la page courante, sauf pendant la saisie.
    final pageText = state.currentPage > 0 ? '${state.currentPage}' : '';
    if (!_pageFocus.hasFocus && _page.text != pageText) {
      _page.value = TextEditingValue(
        text: pageText,
        selection: TextSelection.collapsed(offset: pageText.length),
      );
    }

    // `Ctrl+G` : focus sur le champ de page, texte sélectionné.
    if (ui.goToPageRequest != _seenGoToRequest) {
      _seenGoToRequest = ui.goToPageRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pageFocus.requestFocus();
        _page.selection = TextSelection(baseOffset: 0, extentOffset: _page.text.length);
      });
    }

    final zoomPercent = (state.zoom * 100).round();

    return Padding(
      padding: const EdgeInsets.all(OmniaMetrics.controlBarMargin),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: OmniaMetrics.controlBarMaxWidth),
          child: FloatingSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: OmniaMetrics.controlBarPadding,
              vertical: OmniaMetrics.space2,
            ),
            child: Row(
              children: [
                if (hasPages) ...[
                  OmniaIconButton(
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: '${l10n.docPreviousPage}  ·  PgUp',
                    onPressed: state.currentPage > 1
                        ? () => ref.dispatch(const PreviousPage())
                        : null,
                  ),
                  _PageField(
                    controller: _page,
                    focusNode: _pageFocus,
                    total: state.totalPages,
                    onSubmitted: _submitPage,
                  ),
                  OmniaIconButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: '${l10n.docNextPage}  ·  PgDn',
                    onPressed: state.currentPage < state.totalPages
                        ? () => ref.dispatch(const NextPage())
                        : null,
                  ),
                  const SizedBox(width: OmniaMetrics.space3),
                  _Separator(color: colors.seam),
                  const SizedBox(width: OmniaMetrics.space3),
                ],
                OmniaIconButton(
                  icon: Icons.remove_rounded,
                  tooltip: '${l10n.docZoomOut}  ·  Ctrl+molette',
                  onPressed: () => ref.dispatch(const ZoomRelative(1 / 1.2)),
                ),
                Tooltip(
                  message: isPdf ? l10n.docFitWidth : l10n.docFontSize,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref.dispatch(const FitZoom(FitMode.width)),
                    child: SizedBox(
                      width: 56,
                      child: Text(
                        l10n.docZoomValue(zoomPercent),
                        style: type.timecode,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                OmniaIconButton(
                  icon: Icons.add_rounded,
                  tooltip: '${l10n.docZoomIn}  ·  Ctrl+molette',
                  onPressed: () => ref.dispatch(const ZoomRelative(1.2)),
                ),
                if (isPdf) ...[
                  OmniaIconButton(
                    icon: Icons.fit_screen_outlined,
                    tooltip: '${l10n.docFitWidth}  ·  Ctrl+0',
                    onPressed: () => ref.dispatch(const FitZoom(FitMode.width)),
                  ),
                  OmniaIconButton(
                    icon: Icons.crop_portrait_rounded,
                    tooltip: l10n.docFitPage,
                    onPressed: () => ref.dispatch(const FitZoom(FitMode.page)),
                  ),
                  OmniaIconButton(
                    icon: Icons.rotate_right_rounded,
                    tooltip: '${l10n.docRotate}  ·  Ctrl+R',
                    active: state.rotation != 0,
                    onPressed: () => ref.dispatch(const RotateDocument()),
                  ),
                  OmniaIconButton(
                    icon: state.documentLayout == DocumentLayout.continuous
                        ? Icons.view_agenda_outlined
                        : Icons.view_day_outlined,
                    tooltip: state.documentLayout == DocumentLayout.continuous
                        ? l10n.docLayoutPaged
                        : l10n.docLayoutContinuous,
                    onPressed: () => ref.dispatch(const ToggleDocumentLayout()),
                  ),
                ],
                const Spacer(),
                OmniaIconButton(
                  icon: state.readingDark ? Icons.dark_mode_rounded : Icons.dark_mode_outlined,
                  tooltip: '${l10n.docReadingDark}  ·  Ctrl+D',
                  active: state.readingDark,
                  onPressed: () => ref.dispatch(const ToggleReadingDarkMode()),
                ),
                OmniaIconButton(
                  icon: Icons.search_rounded,
                  tooltip: '${l10n.docFind}  ·  Ctrl+F',
                  active: ui.findVisible,
                  onPressed: () => ref.read(documentUiProvider.notifier).toggleFind(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageField extends StatelessWidget {
  const _PageField({
    required this.controller,
    required this.focusNode,
    required this.total,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int total;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    return Tooltip(
      message: '${l10n.docGoToPage}  ·  Ctrl+G',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.velvet,
              borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
              border: Border.all(color: colors.seam),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: type.timecode,
              textAlign: TextAlign.center,
              cursorColor: colors.projector,
              cursorWidth: 1.5,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: onSubmitted,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          const SizedBox(width: OmniaMetrics.space2),
          Text('/ $total', style: type.timecode.copyWith(color: colors.dust)),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(width: 1, height: 22, child: ColoredBox(color: color));
}

/// Utilitaire pour d'autres widgets : le zoom borné d'un PDF.
double clampDocumentZoom(double zoom) =>
    zoom.clamp(PlaybackState.minZoom, PlaybackState.maxZoom);
