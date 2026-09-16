import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/services/audio_metadata_service.dart';
import 'package:omnia/l10n/app_localizations.dart';
import 'package:omnia/ui/audio_tags_provider.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';
import 'package:omnia/ui/widgets/audio_stage.dart';

/// Tags connus d'avance : pas de lecture de fichier dans ce test.
class _FixedTags extends AudioTagsNotifier {
  _FixedTags(this.tags);

  final AudioTags tags;

  @override
  AudioTags? build() => tags;
}

/// PNG d'un pixel, pour une pochette valide.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  testWidgets('le fond flouté couvre toute la scène et n’en déborde pas', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const stageSize = Size(800, 500);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioTagsProvider.overrideWith(
            () => _FixedTags(AudioTags(title: 'Titre', cover: _pixel, coverMime: 'image/png')),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Material(
            child: Center(
              child: SizedBox.fromSize(
                size: stageSize,
                child: AudioStage(
                  file: MediaFile(
                    path: '/musique/piste.mp3',
                    type: MediaType.audio,
                    size: 1,
                    modifiedAt: DateTime(2026),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final blur = find.byType(ImageFiltered);
    expect(blur, findsOneWidget);

    // Le fond prend toute la scène, quelle que soit la taille de la pochette.
    final backdrop = find.descendant(of: blur, matching: find.byType(Image));
    expect(tester.getSize(backdrop), stageSize);

    // Et il est rogné avant la limite de la vue : le flou ne bave pas dehors.
    final stageBox = tester.renderObject(find.byType(AudioStage));
    RenderObject? node = tester.renderObject(blur);
    var clipped = false;
    while (node != null && node != stageBox) {
      if (node is RenderClipRect) {
        clipped = true;
        break;
      }
      node = node.parent;
    }
    expect(clipped, isTrue, reason: 'aucun ClipRect entre le flou et le bord de la vue');
    expect(tester.takeException(), isNull);
  });

  testWidgets('la pochette suit la scène, s’efface quand la place manque, rien ne déborde', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // La scène change de taille sans remonter la vue.
    final stage = ValueNotifier<Size>(const Size(1200, 700));
    addTearDown(stage.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioTagsProvider.overrideWith(
            () => _FixedTags(AudioTags(title: 'Titre', cover: _pixel, coverMime: 'image/png')),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Material(
            child: Center(
              child: ValueListenableBuilder<Size>(
                valueListenable: stage,
                builder: (context, size, child) => SizedBox.fromSize(size: size, child: child),
                child: AudioStage(
                  file: MediaFile(
                    path: '/musique/piste.mp3',
                    type: MediaType.audio,
                    size: 1,
                    modifiedAt: DateTime(2026),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Taille de scène, et si la pochette y a sa place.
    const cases = <(Size, bool)>[
      (Size(1200, 700), true),
      (Size(800, 500), true),
      (Size(480, 300), true),
      (Size(360, 200), false),
      (Size(320, 160), false),
      (Size(320, 80), false),
    ];
    for (final (size, withCover) in cases) {
      stage.value = size;
      await tester.pumpAndSettle();
      final where = 'scène $size';
      expect(tester.takeException(), isNull, reason: where);

      final cover = find.byKey(AudioStage.coverKey);
      if (withCover) {
        final side = AudioStage.coverSideFor(size);
        expect(side, greaterThanOrEqualTo(AudioStage.minCoverSide), reason: where);
        expect(tester.getSize(cover), Size.square(side), reason: where);
      } else {
        expect(cover, findsNothing, reason: where);
      }

      // Le titre reste là, dans la scène, dès qu'elle peut le montrer.
      final stageRect = tester.getRect(find.byType(AudioStage));
      expect(find.text('Titre'), findsOneWidget, reason: where);
      if (size.height >= 160) {
        final title = tester.getRect(find.text('Titre'));
        expect(stageRect.contains(title.topLeft) && stageRect.contains(title.bottomRight), isTrue,
            reason: '$where : titre $title hors de $stageRect');
      }
    }

    // Aux tailles d'aujourd'hui, la pochette a sa taille idéale, bornée à 420.
    expect(AudioStage.coverSideFor(const Size(2000, 1400)), AudioStage.maxCoverSide);
  });
}
