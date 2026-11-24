import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';
import 'package:omnia/ui/widgets/media_stage_theme.dart';

class _Preferences extends PreferencesNotifier {
  _Preferences(this.mode);

  final AppThemeMode mode;

  @override
  AppPreferences build() => AppPreferences.defaults.copyWith(themeMode: mode);
}

/// Monte une interface claire, et rend les couleurs vues dans la scène et
/// hors d'elle.
Future<({OmniaColors stage, OmniaColors chrome})> _colorsFor(
  WidgetTester tester,
  AppThemeMode mode,
) async {
  late OmniaColors stage;
  late OmniaColors chrome;
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [preferencesProvider.overrideWith(() => _Preferences(mode))],
      child: MaterialApp(
        theme: buildOmniaTheme(Brightness.light),
        home: Column(
          children: [
            Builder(builder: (context) {
              chrome = context.colors;
              return const SizedBox(height: 10);
            }),
            MediaStageTheme(
              child: Builder(builder: (context) {
                stage = context.colors;
                return const SizedBox(height: 10);
              }),
            ),
          ],
        ),
      ),
    ),
  );
  return (stage: stage, chrome: chrome);
}

void main() {
  group('Thème Mixte', () {
    testWidgets('la scène passe en noir, l’interface reste claire', (tester) async {
      final seen = await _colorsFor(tester, AppThemeMode.mixed);
      expect(seen.stage.velvet, OmniaColors.dark.velvet);
      expect(seen.chrome.velvet, OmniaColors.light.velvet);
    });

    testWidgets('en thème clair, la scène reste claire', (tester) async {
      final seen = await _colorsFor(tester, AppThemeMode.light);
      expect(seen.stage.velvet, OmniaColors.light.velvet);
    });

    test('le choix est gardé d’une séance à l’autre', () {
      final p = AppPreferences.defaults.copyWith(themeMode: AppThemeMode.mixed);
      expect(AppPreferences.fromJson(p.toJson()).themeMode, AppThemeMode.mixed);
    });
  });
}
