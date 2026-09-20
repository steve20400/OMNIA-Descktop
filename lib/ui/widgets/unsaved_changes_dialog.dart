import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';

/// Choix possible lors de la fermeture avec des modifications non enregistrées.
enum UnsavedChangesAction {
  /// Enregistrer les modifications sur le disque puis fermer.
  save,

  /// Ignorer les modifications et fermer immédiatement.
  discard,

  /// Annuler la fermeture et rester dans l'application.
  cancel,
}

/// Boîte de dialogue de confirmation élégante affichée lorsque l'utilisateur
/// tente de fermer l'application alors qu'un document est en cours d'édition.
class UnsavedChangesDialog extends StatelessWidget {
  const UnsavedChangesDialog({super.key, required this.fileName});

  final String fileName;

  static Future<UnsavedChangesAction?> show(
    BuildContext context, {
    required String fileName,
  }) {
    return showDialog<UnsavedChangesAction>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => UnsavedChangesDialog(fileName: fileName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 440,
          margin: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space4),
          decoration: BoxDecoration(
            color: colors.curtain,
            borderRadius: BorderRadius.circular(OmniaMetrics.radiusLarge),
            border: Border.all(color: colors.seam),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(OmniaMetrics.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.projector.withValues(alpha: 0.15),
                      borderRadius: OmniaMetrics.controlRadius,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: colors.projector,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: OmniaMetrics.space3),
                  Expanded(
                    child: Text(
                      'Enregistrer les modifications ?',
                      style: type.sectionTitle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OmniaMetrics.space4),
              Text(
                'Le document « $fileName » contient des modifications non enregistrées. '
                'Voulez-vous les enregistrer avant de quitter l’application ?',
                style: type.body.copyWith(
                  color: colors.screen.withValues(alpha: 0.85),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: OmniaMetrics.space6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(UnsavedChangesAction.cancel),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.screen.withValues(alpha: 0.7),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: OmniaMetrics.space2),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(UnsavedChangesAction.discard),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade300,
                      side: BorderSide(color: Colors.red.shade900.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: OmniaMetrics.controlRadius),
                    ),
                    child: const Text('Ne pas enregistrer'),
                  ),
                  const SizedBox(width: OmniaMetrics.space2),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(UnsavedChangesAction.save),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.projector,
                      foregroundColor: colors.velvet,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: OmniaMetrics.controlRadius),
                    ),
                    child: const Text(
                      'Enregistrer',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
