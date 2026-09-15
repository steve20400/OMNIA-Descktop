import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/video_adjust.dart';
import 'package:omnia/ui/widgets/stage.dart';

void main() {
  test('« Remplir » couvre toute la scène ; les autres modes montrent l’image entière', () {
    expect(videoFitFor(AspectMode.fill), BoxFit.cover);
    for (final mode in [AspectMode.auto, AspectMode.wide, AspectMode.standard]) {
      expect(videoFitFor(mode), BoxFit.contain, reason: mode.name);
    }
  });

  test('les ratios imposés : 16:9 et 4:3 ; sinon celui de la vidéo', () {
    expect(videoAspectRatioFor(AspectMode.wide), 16 / 9);
    expect(videoAspectRatioFor(AspectMode.standard), 4 / 3);
    expect(videoAspectRatioFor(AspectMode.auto), isNull);
    expect(videoAspectRatioFor(AspectMode.fill), isNull);
  });
}
