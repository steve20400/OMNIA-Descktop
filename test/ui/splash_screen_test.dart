import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/screens/splash_screen.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';

void main() {
  testWidgets('Desktop SplashScreen renders OMNIA branding, wordmark, and navigates', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        home: const SplashScreen(
          duration: Duration(milliseconds: 1000),
          targetWidget: Scaffold(body: Text('DesktopTargetDestination')),
        ),
      ),
    );

    // Rendu initial : logo vectoriel et titre OMNIA
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('O M N I A'), findsOneWidget);
    expect(find.text('LECTEUR UNIVERSEL'), findsOneWidget);

    // Un clic permet de passer immédiatement à la destination
    await tester.tap(find.byType(SplashScreen));
    await tester.pumpAndSettle();

    expect(find.text('DesktopTargetDestination'), findsOneWidget);
  });
}
