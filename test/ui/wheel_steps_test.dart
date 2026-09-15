import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/wheel_steps.dart';

void main() {
  final t0 = DateTime(2026, 9, 15, 10);

  test('un cran de molette classique donne un pas, dans le bon sens', () {
    final wheel = WheelSteps();
    expect(wheel.add(-60, now: t0), 1, reason: 'vers le haut');
    expect(wheel.add(60, now: t0.add(const Duration(milliseconds: 50))), -1, reason: 'vers le bas');
  });

  test('une rafale de petits déplacements ne donne qu’un pas par seuil', () {
    final wheel = WheelSteps();
    final steps = [
      for (var i = 0; i < 8; i++) wheel.add(-7.5, now: t0.add(Duration(milliseconds: 10 * i))),
    ];
    // 4 × 7,5 = 30 : un pas au quatrième, un autre au huitième.
    expect(steps.where((s) => s != 0).toList(), [1, 1]);
  });

  test('une pause oublie un déplacement partiel', () {
    final wheel = WheelSteps();
    expect(wheel.add(-20, now: t0), 0);
    expect(wheel.add(-20, now: t0.add(const Duration(seconds: 1))), 0);
  });
}
