import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble/ble_transport.dart';
import 'ble/k2_device.dart';
import 'ble/mock_transport.dart';
import 'ble/transport.dart';
import 'l10n/app_l10n.dart';
import 'store/prefs.dart';
import 'store/recipe_editor.dart';
import 'watch/watch_bridge.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// Запуск с симулятором машины:
///   flutter run -d macos --dart-define=MOCK=true
const bool kUseMock = bool.fromEnvironment('MOCK');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  final prefs = await Prefs.load();
  final K2Transport transport = kUseMock ? MockTransport() : BleTransport();
  final device = K2Device(transport);
  final editor = RecipeEditor(device: device, prefs: prefs);

  // Часы. Если их нет, мост просто молчит — проверять платформу не нужно.
  WatchBridge(
    device: device,
    prefs: prefs,
    editor: editor,
    l10n: () => lookupAppL10n(_activeLocale(prefs)),
  );

  runApp(K2App(device: device, prefs: prefs, editor: editor));
}

/// Язык, на котором сейчас говорит приложение. Нужен снимку для часов: там
/// контекста нет, а подписи уезжают готовыми.
Locale _activeLocale(Prefs prefs) {
  final code = prefs.localeCode;
  if (code != null) return Locale(code);
  final system = PlatformDispatcher.instance.locale;
  return AppL10n.supportedLocales.any(
        (l) => l.languageCode == system.languageCode,
      )
      ? Locale(system.languageCode)
      : const Locale('en');
}

class K2App extends StatelessWidget {
  const K2App({
    super.key,
    required this.device,
    required this.prefs,
    required this.editor,
  });

  final K2Device device;
  final Prefs prefs;
  final RecipeEditor editor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: prefs,
    builder: (context, _) {
      final code = prefs.localeCode;
      return MaterialApp(
        onGenerateTitle: (context) => AppL10n.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: K.theme(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        // null — язык берётся из системы.
        locale: code == null ? null : Locale(code),
        home: HomePage(device: device, prefs: prefs, editor: editor),
      );
    },
  );
}
