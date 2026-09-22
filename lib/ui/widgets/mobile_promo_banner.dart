import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/providers.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';
import 'omnia_qr_code.dart';

/// URL officielle du dépôt OMNIA Mobile (releases APK et code source).
const String omniaMobileUrl = 'https://github.com/steve20400/OMNIA-MOBILE';

/// Bannière incitative invitant l'utilisateur Desktop à découvrir la version Mobile.
class MobilePromoBanner extends ConsumerWidget {
  const MobilePromoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final colors = context.colors;
    final connectService = ref.watch(omniaConnectServiceProvider);

    // Ne pas afficher si désactivé dans les réglages
    if (prefs.mobilePromoDismissed) return const SizedBox.shrink();

    // Ne pas afficher si reporté (« Plus tard »)
    if (prefs.mobilePromoSnoozeUntil != null &&
        DateTime.now().isBefore(prefs.mobilePromoSnoozeUntil!)) {
      return const SizedBox.shrink();
    }

    // Ne pas encombrer si un client mobile est déjà connecté
    if (connectService.hasConnectedClients) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space3, vertical: OmniaMetrics.space2),
      padding: const EdgeInsets.all(OmniaMetrics.space4),
      decoration: BoxDecoration(
        color: colors.curtain.withValues(alpha: 0.7),
        borderRadius: OmniaMetrics.cardRadius,
        border: Border.all(color: colors.projector.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(OmniaMetrics.space2),
                decoration: BoxDecoration(
                  color: colors.projector.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.phone_android_rounded, color: colors.projector, size: 20),
              ),
              const SizedBox(width: OmniaMetrics.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Découvrez OMNIA pour Mobile (Android / iOS)',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colors.screen,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Synchronisation locale sans Internet, projection de vos médias et télécommande tactile.',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 12,
                        color: colors.dust,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OmniaMetrics.space3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  final bus = ref.read(commandBusProvider);
                  bus.dispatch(
                    UpdatePreferences.between(
                      prefs,
                      prefs.copyWith(
                        mobilePromoSnoozeUntil: DateTime.now().add(const Duration(days: 7)),
                      ),
                    ),
                  );
                },
                child: Text(
                  'Plus tard',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontSize: 12,
                    color: colors.dust,
                  ),
                ),
              ),
              const SizedBox(width: OmniaMetrics.space1),
              TextButton(
                onPressed: () {
                  final bus = ref.read(commandBusProvider);
                  bus.dispatch(
                    UpdatePreferences.between(
                      prefs,
                      prefs.copyWith(mobilePromoDismissed: true),
                    ),
                  );
                },
                child: Text(
                  'Ne plus afficher',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontSize: 12,
                    color: colors.dust.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: OmniaMetrics.space2),
              OmniaButton(
                label: 'Télécharger l\'application',
                icon: Icons.qr_code_rounded,
                onPressed: () => _showPromoDialog(context, colors),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPromoDialog(BuildContext context, OmniaColors colors) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.curtain,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.phone_android_rounded, color: colors.projector, size: 24),
              const SizedBox(width: 10),
              Text(
                'OMNIA pour Mobile',
                style: TextStyle(
                  fontFamily: OmniaFonts.ui,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.screen,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scannez ce QR code avec votre smartphone pour télécharger l\'APK OMNIA Mobile ou accéder aux sources :',
                style: TextStyle(
                  fontFamily: OmniaFonts.ui,
                  fontSize: 13,
                  color: colors.dust,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              OmniaQrCode(
                data: omniaMobileUrl,
                size: 190,
                color: colors.velvet,
                backgroundColor: colors.screen,
              ),
              const SizedBox(height: 14),
              SelectableText(
                omniaMobileUrl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: OmniaFonts.mono,
                  fontSize: 11,
                  color: colors.projector,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
          actions: [
            OmniaButton(
              label: 'Fermer',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
  }
}
