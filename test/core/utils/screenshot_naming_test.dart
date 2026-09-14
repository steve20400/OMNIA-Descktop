import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/utils/screenshot_naming.dart';

void main() {
  final when = DateTime(2026, 9, 7, 21, 4, 5);

  test('nom du média, horodatage lisible, extension', () {
    expect(screenshotFileName('/films/ep1.mkv', when), 'ep1 2026-09-07 21-04-05.png');
  });

  test('les caractères interdits par Windows sont remplacés', () {
    expect(screenshotFileName('/x/a:b?c.mkv', when), 'a_b_c 2026-09-07 21-04-05.png');
  });

  test('un nom vide devient « capture »', () {
    expect(screenshotFileName('', when), 'capture 2026-09-07 21-04-05.png');
    expect(screenshotFileName('/x/???.mkv', when), '___ 2026-09-07 21-04-05.png');
  });

  test('sanitiseFileName retire points et espaces finaux', () {
    expect(sanitiseFileName('fin. '), 'fin');
    expect(sanitiseFileName('  ok  '), 'ok');
  });
}
