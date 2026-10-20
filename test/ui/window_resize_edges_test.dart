// Les bords de redimensionnement ne mangent plus les clics.
//
// Symptôme : sous Linux, certains clics étaient ignorés et il fallait
// recommencer — la languette du panneau (14 px de large, collée au bord
// gauche) et les boutons de la barre de titre (34 px de haut dans une barre de
// 40) tombent en partie dans les huit pixels de bord. `DragToResizeArea` de
// window_manager y pose un `MouseRegion` OPAQUE par-dessus toute
// l'application : le test de pointeur s'y arrêtait, et la commande dessous ne
// recevait rien.
//
// Le dernier test de ce fichier mesure les deux implémentations côte à côte :
// c'est lui qui dit pourquoi OMNIA dessine ses propres bords.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/widgets/window_resize_edges.dart';
import 'package:window_manager/window_manager.dart';

/// Une commande posée dans le coin bas-gauche, là où les bords se croisent.
class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [startWindowResizeProvider.overrideWithValue(resized.add)],
    );
  }

  final List<ResizeEdge> resized = [];
  int taps = 0;
  bool hovered = false;
  late final ProviderContainer container;

  Widget get control => Align(
        alignment: Alignment.bottomLeft,
        child: MouseRegion(
          onEnter: (_) => hovered = true,
          onExit: (_) => hovered = false,
          child: GestureDetector(
            key: const ValueKey('control'),
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 34, height: 34),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, {bool enabled = true}) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: WindowResizeEdges(force: true, enabled: enabled, child: control),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect get rect => _rect;
  late Rect _rect;
  void measure(WidgetTester tester) =>
      _rect = tester.getRect(find.byKey(const ValueKey('control')));
}

void main() {
  testWidgets('un clic au bord de la fenêtre arrive bien à la commande', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    h.measure(tester);

    // Quatre pixels du bord bas, puis quatre pixels du bord gauche : les deux
    // points tombent dans les bandes de redimensionnement.
    await tester.tapAt(Offset(h.rect.center.dx, h.rect.bottom - 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.taps, 1, reason: 'bord bas');

    await tester.tapAt(Offset(h.rect.left + 4, h.rect.center.dy));
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.taps, 2, reason: 'bord gauche');

    // Et le clic n'a pas non plus réveillé le redimensionnement : un clic
    // n'est pas un glissement.
    expect(h.resized, isEmpty);
  });

  testWidgets('la commande s’allume encore sous le bord', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    h.measure(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(h.rect.left + 4, h.rect.center.dy));
    await tester.pump();

    // Les bandes ne sont pas exclusives : le survol traverse, la commande
    // reste donc visiblement cliquable là où elle l'est.
    expect(h.hovered, isTrue);
  });

  testWidgets('un glissement de trois pixels confie le geste au système', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    h.measure(tester);

    final start = Offset(h.rect.left + 4, h.rect.center.dy);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(h.resized, isEmpty, reason: 'un pixel : encore un clic tremblant');

    await gesture.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(h.resized, [ResizeEdge.left]);

    // Un seul départ par pression, même si le pointeur continue.
    await gesture.moveBy(const Offset(10, 0));
    await gesture.up();
    await tester.pump();
    expect(h.resized, [ResizeEdge.left]);
  });

  testWidgets('chaque bande demande son propre bord', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    final size = tester.getSize(find.byType(WindowResizeEdges));

    Future<void> dragAt(Offset point) async {
      final gesture = await tester.startGesture(point);
      await gesture.moveBy(const Offset(6, 6));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    await dragAt(const Offset(4, 4));
    await dragAt(Offset(size.width / 2, 4));
    await dragAt(Offset(size.width - 4, size.height - 4));
    expect(h.resized, [ResizeEdge.topLeft, ResizeEdge.top, ResizeEdge.bottomRight]);
  });

  testWidgets('bords désactivés : plus rien à redimensionner', (tester) async {
    final h = _Harness();
    await h.pump(tester, enabled: false);
    h.measure(tester);

    final gesture = await tester.startGesture(Offset(h.rect.left + 4, h.rect.center.dy));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pump();

    expect(h.resized, isEmpty);
    // La commande reste atteignable, elle.
    await tester.tapAt(Offset(h.rect.left + 4, h.rect.center.dy));
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.taps, 1);
  });

  testWidgets('c’est le MouseRegion opaque de DragToResizeArea qui mangeait le clic',
      (tester) async {
    // La mesure qui justifie ce fichier. Au même point, à quatre pixels du
    // bord : le widget de window_manager retient le clic, les bandes d'OMNIA
    // le laissent passer. Si quelqu'un revient un jour à `DragToResizeArea`,
    // ce test le dira.
    Future<int> tapsAtEdge(Widget Function(Widget) wrap) async {
      final h = _Harness();
      final container = ProviderContainer(
        overrides: [startWindowResizeProvider.overrideWithValue(h.resized.add)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: wrap(h.control),
          ),
        ),
      );
      await tester.pump();
      h.measure(tester);
      await tester.tapAt(Offset(h.rect.center.dx, h.rect.bottom - 4));
      await tester.pump(const Duration(milliseconds: 400));
      return h.taps;
    }

    expect(
      await tapsAtEdge((child) => DragToResizeArea(
            resizeEdgeSize: WindowResizeEdges.thickness,
            child: child,
          )),
      0,
      reason: 'le clic s’arrête sur la bande opaque',
    );
    expect(
      await tapsAtEdge((child) => WindowResizeEdges(force: true, child: child)),
      1,
      reason: 'les bandes d’OMNIA sont translucides au test de pointeur',
    );
  });
}
