import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/document_layout.dart';
import 'package:omnia/core/models/equalizer.dart';

void main() {
  group('AppPreferences — valeurs par défaut', () {
    test('conformes au cahier des charges', () {
      const p = AppPreferences.defaults;
      expect(p.language, AppLanguage.system);
      expect(p.themeMode, AppThemeMode.dark);
      expect(p.resumePolicy, ResumePolicy.auto);
      expect(p.singleInstance, isTrue);
      expect(p.seekStepSeconds, 5);
      expect(p.defaultSpeed, 1.0);
      expect(p.startupVolume, StartupVolume.last);
      expect(p.subtitleAutoLoad, isTrue);
      expect(p.equalizerEnabled, isFalse);
      expect(p.pdfLayout, DocumentLayout.continuous);
      expect(p.screenshotNamePattern, AppPreferences.defaultScreenshotPattern);
    });
  });

  group('AppPreferences — JSON', () {
    test('aller-retour exact', () {
      final p = AppPreferences.defaults.copyWith(
        language: AppLanguage.en,
        themeMode: AppThemeMode.light,
        resumePolicy: ResumePolicy.ask,
        singleInstance: false,
        seekStepSeconds: 30,
        defaultSpeed: 1.25,
        startupVolume: StartupVolume.fixed,
        fixedVolume: 42,
        subtitleScale: 1.5,
        subtitleAutoLoad: false,
        subtitleDelay: -1.5,
        equalizerEnabled: true,
        equalizerGains: Equalizer.presets['rock'],
        pdfLayout: DocumentLayout.paged,
        readingDark: true,
        textScale: 1.4,
        screenshotNamePattern: '{name} @ {position}',
      );
      final restored = AppPreferences.fromJson(p.toJson());
      expect(restored, p);
      expect(restored.hashCode, p.hashCode);
    });

    test('carte vide → valeurs par défaut', () {
      expect(AppPreferences.fromJson(const {}), AppPreferences.defaults);
    });

    test('types erronés → valeurs par défaut, sans exception', () {
      final p = AppPreferences.fromJson(const {
        'language': 42,
        'themeMode': 'violet',
        'resumePolicy': null,
        'singleInstance': 'oui',
        'seekStepSeconds': 'cinq',
        'defaultSpeed': 'vite',
        'equalizerGains': 'plat',
        'screenshotNamePattern': 7,
      });
      expect(p, AppPreferences.defaults);
    });

    test('valeurs hors bornes ramenées dans les bornes', () {
      final p = AppPreferences.fromJson(const {
        'seekStepSeconds': 7,
        'defaultSpeed': 9.0,
        'fixedVolume': 250,
        'subtitleScale': 10,
        'subtitleDelay': -99,
        'textScale': 0.1,
        'equalizerGains': [40, -40],
      });
      expect(p.seekStepSeconds, 5, reason: 'pas le plus proche de 7');
      expect(p.defaultSpeed, 4.0);
      expect(p.fixedVolume, 100);
      expect(p.subtitleScale, 2.5);
      expect(p.subtitleDelay, -30);
      expect(p.textScale, 0.6);
      expect(p.equalizerGains.length, Equalizer.bands.length);
      expect(p.equalizerGains.first, Equalizer.maxGain);
      expect(p.equalizerGains[1], Equalizer.minGain);
      expect(p.equalizerGains.last, 0);
    });

    test('un motif de capture vide retombe sur le motif par défaut', () {
      expect(
        AppPreferences.defaults.copyWith(screenshotNamePattern: '   ').screenshotNamePattern,
        AppPreferences.defaultScreenshotPattern,
      );
    });
  });

  group('AppPreferences — copyWith', () {
    test('ne modifie que ce qui est demandé', () {
      final p = AppPreferences.defaults.copyWith(seekStepSeconds: 10);
      expect(p.seekStepSeconds, 10);
      expect(p.copyWith(), p);
      expect(p == AppPreferences.defaults, isFalse);
    });

    test('la vitesse suit le pas de 0,25', () {
      expect(AppPreferences.defaults.copyWith(defaultSpeed: 1.3).defaultSpeed, 1.25);
      expect(AppPreferences.defaults.copyWith(defaultSpeed: 0.1).defaultSpeed, 0.25);
    });
  });

  test('les énumérations tolèrent une valeur inconnue', () {
    expect(AppLanguage.fromJson('klingon'), AppLanguage.system);
    expect(AppThemeMode.fromJson(null), AppThemeMode.dark);
    expect(ResumePolicy.fromJson('peut-être'), ResumePolicy.auto);
    expect(StartupVolume.fromJson(3), StartupVolume.last);
  });
}
