import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/chrome_controller.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';

// testWidgets : les minuteries du contrôleur tournent en temps simulé, et
// chaque test libère le conteneur avant de finir (plus aucune minuterie).
void main() {
  const justAfter = Duration(milliseconds: 20);

  testWidgets('se masque après le délai, revient au premier mouvement', (tester) async {
    final container = ProviderContainer();
    final chrome = container.read(chromeProvider.notifier)..setAutoHide(true);

    expect(container.read(chromeProvider), isTrue);
    await tester.pump(OmniaMotion.idleHide - justAfter);
    expect(container.read(chromeProvider), isTrue);
    await tester.pump(justAfter * 2);
    expect(container.read(chromeProvider), isFalse);

    chrome.activity();
    expect(container.read(chromeProvider), isTrue);
    container.dispose();
  });

  testWidgets('une retenue garde les contrôles ; sa levée relance le délai', (tester) async {
    final container = ProviderContainer();
    final chrome = container.read(chromeProvider.notifier)
      ..setAutoHide(true)
      ..hold('menu');

    await tester.pump(OmniaMotion.idleHide * 3);
    expect(container.read(chromeProvider), isTrue);

    chrome.release('menu');
    await tester.pump(OmniaMotion.idleHide + justAfter);
    expect(container.read(chromeProvider), isFalse);
    container.dispose();
  });

  testWidgets('deux retenues : il faut lever les deux', (tester) async {
    final container = ProviderContainer();
    final chrome = container.read(chromeProvider.notifier)
      ..setAutoHide(true)
      ..hold('barre')
      ..hold('menu')
      ..release('menu');

    await tester.pump(OmniaMotion.idleHide * 2);
    expect(container.read(chromeProvider), isTrue);
    chrome.release('barre');
    await tester.pump(OmniaMotion.idleHide + justAfter);
    expect(container.read(chromeProvider), isFalse);
    container.dispose();
  });

  testWidgets('masquage coupé : les contrôles restent et réapparaissent', (tester) async {
    final container = ProviderContainer();
    final chrome = container.read(chromeProvider.notifier)..setAutoHide(true);
    await tester.pump(OmniaMotion.idleHide + justAfter);
    expect(container.read(chromeProvider), isFalse);

    chrome.setAutoHide(false);
    expect(container.read(chromeProvider), isTrue);
    await tester.pump(OmniaMotion.idleHide * 3);
    expect(container.read(chromeProvider), isTrue);
    container.dispose();
  });

  testWidgets('pointeur sorti du média : masquage rapide, sauf retenue', (tester) async {
    final container = ProviderContainer();
    final chrome = container.read(chromeProvider.notifier)
      ..setAutoHide(true)
      ..pointerLeft();
    await tester.pump(OmniaMotion.chromeLeaveHide + justAfter);
    expect(container.read(chromeProvider), isFalse);

    chrome
      ..activity()
      ..hold('menu')
      ..pointerLeft();
    await tester.pump(OmniaMotion.idleHide * 2);
    expect(container.read(chromeProvider), isTrue);
    container.dispose();
  });
}
