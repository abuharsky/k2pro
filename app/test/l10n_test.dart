import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/l10n/app_l10n.dart';

/// Два языка живут в четырёх местах сразу: два ARB, карта `_strings` в снимке
/// для часов и каталог строк самих часов. Ничто в компиляторе их не связывает,
/// а расходятся они молча — забытый ключ виден только на живом устройстве и
/// только на одном из языков. Здесь эта связь проверяется статически.

/// Ключи ARB без служебных `@`-метаданных.
Set<String> _arbKeys(String path) {
  final map = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return map.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('русский и английский описывают одно и то же', () {
    final en = _arbKeys('lib/l10n/app_en.arb');
    final ru = _arbKeys('lib/l10n/app_ru.arb');
    expect(ru.difference(en), isEmpty, reason: 'лишнее в русском');
    expect(en.difference(ru), isEmpty, reason: 'не переведено на русский');
  });

  test('поддерживаются ровно эти два языка', () {
    expect(
      AppL10n.supportedLocales.map((l) => l.languageCode).toSet(),
      {'en', 'ru'},
    );
  });

  group('часы', () {
    // Ключи, за которыми часы приходят к телефону: `link.string("…")`.
    final asked = Directory('ios/K2ProWatch')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.swift'))
        .expand(
          (f) => RegExp(r'link\.string\("([A-Za-z]+)"\)')
              .allMatches(f.readAsStringSync())
              .map((m) => m.group(1)!),
        )
        .toSet();

    test('часы вообще что-то спрашивают', () {
      // Пустой набор означал бы, что регулярка разошлась с кодом, и все
      // проверки ниже стали бы тавтологией.
      expect(asked, isNotEmpty);
    });

    test('телефон присылает каждую подпись, которую часы спрашивают', () {
      // Карта строк в снимке — источник, из которого часы живут в рабочем
      // режиме. Читаем её из исходника: собирать снимок ради имён ключей
      // значило бы тащить сюда устройство, весы и настройки.
      final src = File('lib/watch/watch_snapshot.dart').readAsStringSync();
      final body = RegExp(
        r'Map<String, Object\?> _strings\(AppL10n t\) => \{(.*?)\n\};',
        dotAll: true,
      ).firstMatch(src);
      expect(body, isNotNull, reason: '_strings в снимке не найдена');
      final sent = RegExp(r"'([A-Za-z]+)':")
          .allMatches(body!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      expect(asked.difference(sent), isEmpty, reason: 'телефон промолчит');
    });

    test('часы знают эти подписи сами, на обоих языках', () {
      // Фолбэк на случай, когда телефон ещё ни разу не ответил: без него
      // экран покажет голый ключ.
      final catalog =
          jsonDecode(
                File('ios/K2ProWatch/Localizable.xcstrings').readAsStringSync(),
              )
              as Map<String, Object?>;
      final strings = catalog['strings']! as Map<String, Object?>;

      expect(asked.difference(strings.keys.toSet()), isEmpty,
          reason: 'нет в каталоге часов');

      for (final key in asked) {
        final entry = strings[key]! as Map<String, Object?>;
        final locales = entry['localizations']! as Map<String, Object?>;
        expect(locales.keys.toSet(), {'en', 'ru'}, reason: 'ключ $key');
      }
    });
  });
}
