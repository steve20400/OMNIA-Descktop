import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';
import 'omnia_button.dart';

/// Encart affiché quand le pare-feu du système refuse les connexions vers
/// OMNIA.
///
/// Sans lui, l'appairage échouait sans explication : une connexion que le
/// pare-feu refuse n'arrive jamais jusqu'à l'application, qui n'a donc rien à
/// signaler au moment où elle échoue. Le seul remède connu était de couper le
/// pare-feu tout entier. L'encart dit ce qui bloque **avant** l'appairage, et
/// propose d'autoriser OMNIA seul.
class FirewallNotice extends StatelessWidget {
  const FirewallNotice({
    super.key,
    required this.onAllow,
    this.busy = false,
    this.refused = false,
  });

  /// Demande l'autorisation au système.
  final VoidCallback onAllow;

  /// Vrai pendant que le système attend la confirmation de l'utilisateur.
  final bool busy;

  /// Vrai quand l'autorisation vient d'être demandée sans être obtenue.
  final bool refused;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final accent = colors.alert;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pare-feu de Windows',
                  style: type.bodyStrong.copyWith(color: accent),
                ),
                const SizedBox(height: 2),
                Text(
                  'Il refuse les connexions vers OMNIA sur ce réseau : '
                  "l'autre appareil ne pourra pas le joindre. Inutile de "
                  'couper le pare-feu — OMNIA peut être autorisé seul, et '
                  'Windows vous demandera de confirmer.',
                  style: type.secondary.copyWith(
                    color: colors.screen,
                    height: 1.4,
                  ),
                ),
                if (refused) ...[
                  const SizedBox(height: 6),
                  Text(
                    "L'autorisation n'a pas été accordée : rien n'a été "
                    "modifié, et l'appairage échouera sur ce réseau.",
                    style: type.secondary.copyWith(color: accent, height: 1.4),
                  ),
                ],
                const SizedBox(height: 10),
                OmniaButton(
                  label: busy
                      ? 'En attente de la confirmation de Windows…'
                      : 'Autoriser OMNIA dans le pare-feu',
                  icon: Icons.verified_user_outlined,
                  primary: true,
                  onPressed: busy ? null : onAllow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
