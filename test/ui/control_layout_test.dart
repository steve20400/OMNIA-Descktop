import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/widgets/control_layout.dart';

/// Une barre type : lecture (priorité 0), temps, puis des commandes de moins
/// en moins utiles, et le plein écran, qui cède presque en dernier.
const _slots = [
  ControlSlot(id: 'previous', width: 34, priority: 4),
  ControlSlot(id: 'play', width: 44, priority: 0),
  ControlSlot(id: 'next', width: 34, priority: 4),
  ControlSlot(id: 'time', width: 150, priority: 2),
  ControlSlot(id: 'abLoop', width: 34, priority: 7),
  ControlSlot(id: 'record', width: 34, priority: 5),
  ControlSlot(id: 'speed', width: 56, priority: 5),
  ControlSlot(id: 'volume', width: 46, priority: 3),
  ControlSlot(id: 'fullscreen', width: 34, priority: 1),
];

const double _total = 34 + 44 + 34 + 150 + 34 + 34 + 56 + 46 + 34;

void main() {
  test('tout tient : aucune commande dans le menu, donc pas de menu', () {
    final fit = fitControls(_slots, _total, overflowWidth: 42);
    expect(fit.hasOverflow, isFalse);
    expect(fit.shown, [for (final s in _slots) s.id]);
  });

  test('la moins utile cède sa place la première, et le menu apparaît', () {
    final fit = fitControls(_slots, _total - 1, overflowWidth: 42);
    expect(fit.hasOverflow, isTrue);
    // 1 px manquant + 42 px pour le menu : A-B (34) puis une priorité 5 (la
    // plus à droite : la vitesse, 56) partent.
    expect(fit.overflow, ['abLoop', 'speed']);
    expect(fit.shown, isNot(contains('abLoop')));
  });

  test('l’ordre d’origine est gardé, dans la barre comme dans le menu', () {
    final fit = fitControls(_slots, 200, overflowWidth: 42);
    final shownOrder = [for (final s in _slots) s.id].where(fit.shown.contains).toList();
    expect(fit.shown, shownOrder);
    final menuOrder = [for (final s in _slots) s.id].where(fit.overflow.contains).toList();
    expect(fit.overflow, menuOrder);
  });

  test('la lecture ne part jamais dans le menu, même sans place', () {
    final fit = fitControls(_slots, 10, overflowWidth: 42);
    expect(fit.shown, ['play']);
    expect(fit.overflow, hasLength(_slots.length - 1));
  });

  test('plus étroit ne montre jamais une commande qu’une barre plus large cache', () {
    Set<String> shownAt(double width) => fitControls(_slots, width, overflowWidth: 42).shown.toSet();
    for (var width = 60.0; width <= _total; width += 7) {
      expect(shownAt(width).difference(shownAt(width + 7)), isEmpty, reason: 'largeur $width');
    }
  });

  test('le plein écran tient plus longtemps que le temps et les boutons', () {
    // Place pour lecture (44) + menu (42) + une commande de 34 px.
    final fit = fitControls(_slots, 44 + 42 + 34, overflowWidth: 42);
    expect(fit.shown, ['play', 'fullscreen']);
  });
}
