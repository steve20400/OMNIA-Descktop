import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import 'theme/omnia_theme.dart';

/// Écran affiché quand OMNIA ne peut pas préparer son stockage local.
///
/// Il vaut mieux une fenêtre qui explique le problème qu'un binaire qui se
/// termine en silence : sans cela, l'utilisateur voit son application ne pas
/// démarrer, sans savoir pourquoi. Les préférences étant justement
/// inaccessibles, la langue est celle du système (français à défaut).
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMNIA',
      debugShowCheckedModeBanner: false,
      theme: buildOmniaTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) {
        for (final s in supported) {
          if (s.languageCode == locale?.languageCode) return s;
        }
        return const Locale('fr');
      },
      home: Builder(
        builder: (context) {
          final colors = context.colors;
          final type = context.type;
          final l10n = AppLocalizations.of(context);
          return DragToMoveArea(
            // Material : style de texte par défaut et fond, sans Scaffold.
            child: Material(
              color: colors.velvet,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 40, color: colors.alert),
                      const SizedBox(height: OmniaMetrics.space4),
                      Text(
                        l10n.startupFailureTitle,
                        style: type.viewTitle,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: OmniaMetrics.space2),
                      Text(
                        l10n.startupFailureBody,
                        style: type.body,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: OmniaMetrics.space5),
                      SelectableText(detail, style: type.caption),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
