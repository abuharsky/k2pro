import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ui/theme.dart';

/// Рисует фон запуска прямо виджетом AppBackground — тем же, что и на главном
/// экране. Так сплэш совпадает с первым кадром один в один и не разъезжается
/// при правках темы (в обычный прогон flutter test не попадает, каталог вне
/// test/):
///   flutter test tool/launch --update-goldens
///
/// Результат кладётся сразу в каталог ассетов iOS. Два варианта пропорций:
/// телефон и планшет; промежуточные размеры система растянет — пятна мягкие,
/// разница не читается.
void main() {
  Future<void> shoot(WidgetTester tester, String file, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppBackground(child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(AppBackground),
      matchesGoldenFile(
        '../../ios/Runner/Assets.xcassets/LaunchBackground.imageset/$file',
      ),
    );
  }

  testWidgets('фон запуска: телефон', (tester) async {
    await shoot(tester, 'LaunchBackground-phone.png', const Size(645, 1398));
  });

  testWidgets('фон запуска: планшет', (tester) async {
    await shoot(tester, 'LaunchBackground-pad.png', const Size(768, 1024));
  });
}
