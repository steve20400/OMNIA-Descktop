import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'theme/omnia_theme.dart';

/// Écran affiché quand OMNIA ne peut pas préparer son stockage local.
///
/// Il vaut mieux une fenêtre qui explique le problème qu'un binaire qui se
/// termine en silence : sans cela, l'utilisateur voit son application ne pas
/// démarrer, sans savoir pourquoi.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMNIA',
      debugShowCheckedModeBanner: false,
      theme: buildOmniaTheme(Brightness.dark),
      home: Builder(
        builder: (context) {
          final colors = context.colors;
          final type = context.type;
          return DragToMoveArea(
            child: ColoredBox(
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
                        'OMNIA n’a pas pu préparer ses données',
                        style: type.viewTitle,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: OmniaMetrics.space2),
                      Text(
                        'Le dossier de données de l’application est inaccessible. '
                        'Vérifiez l’espace disque et les droits sur votre dossier '
                        'personnel, puis relancez OMNIA.',
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
