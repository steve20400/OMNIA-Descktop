import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';
import 'package:omnia/ui/widgets/mobile_promo_banner.dart';

class _CustomPreferencesNotifier extends PreferencesNotifier {
  _CustomPreferencesNotifier(this._initial);
  final AppPreferences _initial;

  @override
  AppPreferences build() => _initial;
}

void main() {
  testWidgets('MobilePromoBanner displays Mobile promotion when not dismissed', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith(
            () => _CustomPreferencesNotifier(const AppPreferences()),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          home: const Scaffold(body: MobilePromoBanner()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Découvrez OMNIA pour Mobile (Android / iOS)'), findsOneWidget);
    expect(find.text('Télécharger l\'application'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
    expect(find.text('Ne plus afficher'), findsOneWidget);
  });

  testWidgets('MobilePromoBanner hides when mobilePromoDismissed is true', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith(
            () => _CustomPreferencesNotifier(
              const AppPreferences(mobilePromoDismissed: true),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          home: const Scaffold(body: MobilePromoBanner()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Découvrez OMNIA pour Mobile (Android / iOS)'), findsNothing);
  });

  testWidgets('MobilePromoBanner hides when mobilePromoSnoozeUntil is in the future', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith(
            () => _CustomPreferencesNotifier(
              AppPreferences(
                mobilePromoSnoozeUntil: DateTime.now().add(const Duration(days: 3)),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          home: const Scaffold(body: MobilePromoBanner()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Découvrez OMNIA pour Mobile (Android / iOS)'), findsNothing);
  });
}
