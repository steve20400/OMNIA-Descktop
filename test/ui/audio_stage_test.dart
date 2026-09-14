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
}
