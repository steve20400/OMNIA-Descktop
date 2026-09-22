import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';
import 'package:omnia/ui/widgets/omnia_connect_dialog.dart';
import 'package:omnia/ui/widgets/omnia_qr_code.dart';

class _StaticPlaybackNotifier extends PlaybackStateNotifier {
  @override
  PlaybackState build() => const PlaybackState();
}

void main() {
  testWidgets('OmniaConnectDialog renders title, QR code, and status with initial data', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackStateProvider.overrideWith(_StaticPlaybackNotifier.new),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          home: const Scaffold(
            body: OmniaConnectDialog(
              initialPairingData: '{"protocol":"omnia-connect","name":"Test"}',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Vérifie le titre
    expect(find.text('OMNIA Connect'), findsOneWidget);
    expect(
      find.text('Synchronisation locale sans Internet (PC ↔ Mobile)'),
      findsOneWidget,
    );

    // Vérifie le widget QR Code
    expect(find.byType(OmniaQrCode), findsOneWidget);

    // Vérifie le texte de statut
    expect(
      find.text('Scannez ce QR Code avec l\'application OMNIA Mobile'),
      findsOneWidget,
    );

    // Vérifie le bouton de fermeture
    expect(find.text('Fermer'), findsOneWidget);
  });
}
