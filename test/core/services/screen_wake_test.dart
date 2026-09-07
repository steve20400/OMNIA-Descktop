import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/services/screen_wake.dart';

void main() {
  test('l’écran reste allumé pendant une vidéo qui joue, et seulement là', () {
    expect(shouldKeepScreenAwake(playing: true, hasVideo: true), isTrue);
    expect(shouldKeepScreenAwake(playing: false, hasVideo: true), isFalse);
    expect(shouldKeepScreenAwake(playing: true, hasVideo: false), isFalse);
    expect(shouldKeepScreenAwake(playing: false, hasVideo: false), isFalse);
  });

  test('l’implémentation d’enregistrement note chaque appel', () async {
    final wake = RecordingScreenWake();
    await wake.setKeepAwake(true);
    await wake.setKeepAwake(false);
    expect(wake.calls, [true, false]);
  });
}
