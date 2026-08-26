import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble/ble_transport.dart';
import 'ble/demo.dart';
import 'ble/k2_device.dart';
import 'ble/profiles.dart';
import 'ble/scale/scale_device.dart';
import 'ble/switchable_transport.dart';
import 'live/live_activity_bridge.dart';
import 'l10n/app_l10n.dart';
import 'store/prefs.dart';
import 'store/shot_store.dart';
import 'store/recipe_editor.dart';
import 'watch/watch_bridge.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/welcome_page.dart';

/// Запуск сразу в демо-режиме, без железа:
///   flutter run -d macos --dart-define=MOCK=true
///
/// Того же можно добиться из самого приложения — первым экраном или шторкой
/// настроек; ключ остаётся затем, чтобы не тыкать в него каждый запуск.
const bool kUseMock = bool.fromEnvironment('MOCK');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  final prefs = await Prefs.load();

  // Машина и весы — два независимых подключения, но поиск у них общий:
  // радиоканал один, и два скана разом держать нельзя.
  final scanner = BleScanner();

  // Между устройством и эфиром стоит переходник: демо-режим меняет начинку
  // под ногами, а подписки выше по стеку остаются теми же. К адаптеру до
  // первого скана никто не ходит, так что заводить их всегда безопасно.
  final machineLink = SwitchableTransport(
    BleTransport(profile: kMachineProfile, scanner: scanner),
  );
  final scaleLink = SwitchableTransport(
    BleTransport(profile: kScaleProfile, scanner: scanner),
  );

  final device = K2Device(machineLink);
  final scale = ScaleDevice(scaleLink);
  final editor = RecipeEditor(device: device, prefs: prefs);

  final demo = Demo(
    machineLink: machineLink,
    scaleLink: scaleLink,
    device: device,
    scale: scale,
    prefs: prefs,
  );

  // Часы. Если их нет, мост просто молчит — проверять платформу не нужно.
  WatchBridge(
    device: device,
    scale: scale,
    prefs: prefs,
    editor: editor,
    l10n: () => lookupAppL10n(_activeLocale(prefs)),
  );

  // Live Activity на экране блокировки, пока идёт пролив. Не на iOS или старше
  // 16.1 — нативная сторона молча ничего не делает.
  LiveActivityBridge(
    device: device,
    scale: scale,
    prefs: prefs,
    l10n: () => lookupAppL10n(_activeLocale(prefs)),
  );

  if (kUseMock) unawaited(demo.enter());

  runApp(
    K2App(
      device: device,
      scale: scale,
      prefs: prefs,
      editor: editor,
      demo: demo,
    ),
  );
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
    required this.scale,
    required this.prefs,
    required this.editor,
    this.demo,
    this.store,
  });

  final K2Device device;

  /// Весы. Их может не быть в эфире вовсе — тогда всё, что с ними связано,
  /// просто не показывается.
  final ScaleDevice scale;

  final Prefs prefs;
  final RecipeEditor editor;

  /// Хранилище кривых. null — обычная папка приложения.
  final ShotStore? store;

  /// Демо-режим. null — демо недоступно: так собраны тесты и снимки экранов,
  /// где транспорт задаётся напрямую.
  final Demo? demo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([prefs, demo]),
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
        // Пока ни одной машины не добавили и демо не идёт — показывать на
        // главном экране нечего: там машина, которой нет. Развилка держится
        // на списке машин, а он пополняется сам, при первом подключении.
        home: demo != null && prefs.devices.isEmpty && !demo!.on
            ? WelcomePage(
                device: device,
                scale: scale,
                prefs: prefs,
                demo: demo!,
              )
            : HomePage(
                device: device,
                scale: scale,
                prefs: prefs,
                editor: editor,
                demo: demo,
                store: store,
              ),
      );
    },
  );
}
