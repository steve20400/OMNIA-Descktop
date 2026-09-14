import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/resume_offer.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';
import 'floating_surface.dart';
import 'omnia_button.dart';

/// Invite de reprise (politique « demander ») : une pastille discrète au-dessus
/// des contrôles. Sans réponse, elle s'efface d'elle-même et le fichier
/// continue depuis le début.
class ResumePrompt extends ConsumerStatefulWidget {
  const ResumePrompt({super.key});

  /// Temps laissé pour répondre.
  static const Duration timeout = Duration(seconds: 10);

  @override
  ConsumerState<ResumePrompt> createState() => _ResumePromptState();
}

class _ResumePromptState extends ConsumerState<ResumePrompt> {
  Timer? _timeout;
  ResumeOffer? _armedFor;

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _arm(ResumeOffer? offer) {
    if (offer == _armedFor) return;
    _armedFor = offer;
    _timeout?.cancel();
    if (offer == null) return;
    _timeout = Timer(ResumePrompt.timeout, () {
      if (mounted && ref.read(playbackStateProvider).resumeOffer == offer) {
        ref.dispatch(const DeclineResume());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final type = context.type;
    final colors = context.colors;
    final offer = ref.watch(playbackStateProvider.select((s) => s.resumeOffer));
    _arm(offer);

    final Widget content;
    if (offer == null) {
      content = const SizedBox.shrink(key: ValueKey('resume-none'));
    } else {
      final position = offer.position;
      final page = offer.page;
      final question = position != null
          ? l10n.resumePromptPosition(formatTimecode(position))
          : page != null
              ? l10n.resumePromptPage(page)
              : l10n.resumePromptScroll;

      content = FloatingSurface(
        key: ValueKey(offer),
        borderRadius: OmniaMetrics.controlRadius,
        padding: const EdgeInsets.fromLTRB(
          OmniaMetrics.space4,
          OmniaMetrics.space2,
          OmniaMetrics.space2,
          OmniaMetrics.space2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: OmniaMetrics.iconSize, color: colors.projector),
            const SizedBox(width: OmniaMetrics.space3),
            Text(question, style: type.osdLabel),
            const SizedBox(width: OmniaMetrics.space4),
            OmniaButton(
              label: l10n.resumeAccept,
              primary: true,
              onPressed: () => ref.dispatch(const AcceptResume()),
            ),
            const SizedBox(width: OmniaMetrics.space2),
            OmniaButton(
              label: l10n.resumeDecline,
              onPressed: () => ref.dispatch(const DeclineResume()),
            ),
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: OmniaMotion.reveal,
      switchInCurve: OmniaMotion.revealCurve,
      switchOutCurve: OmniaMotion.concealCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: content,
    );
  }
}
