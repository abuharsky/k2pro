import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/l10n/app_l10n.dart';
import 'package:k2pro/ui/sheets/sheet.dart';

/// Ряд с живым значением: обработчики замкнуты на текущее число и
/// пересобираются на каждое изменение — ровно как в настоящих листах.
Widget _row(double Function() read, void Function(double) write) => MaterialApp(
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, setState) {
        final value = read();
        return SheetStepperRow(
          label: 'Вес',
          value: value.toStringAsFixed(1),
          canDown: true,
          canUp: true,
          onDown: () => setState(() => write(value - 1)),
          onUp: () => setState(() => write(value + 1)),
        );
      },
    ),
  ),
);

/// Держим кнопку [ms] миллисекунд, рисуя кадры: без кадров ряд не
/// пересоберётся, а вместе с ним не обновятся и обработчики.
Future<void> _hold(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('удержание минуса отсчитывает шаг за шагом, а не один раз', (
    tester,
  ) async {
    var value = 40.0;
    await tester.pumpWidget(_row(() => value, (v) => value = v));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StepButton).first),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    expect(value, 39, reason: 'первый шаг — сразу по удержанию');

    await _hold(tester, 700);
    expect(value, lessThan(36), reason: 'дальше отсчёт идёт сам');

    final onRelease = value;
    await gesture.up();
    await _hold(tester, 500);
    expect(value, onRelease, reason: 'отпустили — отсчёт встал');
  });

  testWidgets('отсчёт разгоняется', (tester) async {
    var value = 400.0;
    await tester.pumpWidget(_row(() => value, (v) => value = v));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StepButton).first),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));

    final start = value;
    await _hold(tester, 400);
    final slow = start - value;

    await _hold(tester, 1000);
    final mid = value;
    await _hold(tester, 400);
    final fast = mid - value;

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));

    expect(fast, greaterThan(slow * 2));
  });
}
