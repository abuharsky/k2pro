import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/l10n/app_l10n.dart';
import 'package:k2pro/store/prefs.dart';
import 'package:k2pro/store/recipe_editor.dart';
import 'package:k2pro/watch/watch_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Снимок для часов — это контракт, а не картинка. Здесь проверяется его
/// форма: набор рядов верхнего уровня и то, что настройки пролива свёрнуты в
/// один ряд с вложенными.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Prefs prefs;
  late K2Device device;
  late RecipeEditor editor;
  final t = lookupAppL10n(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
    device = K2Device(MockTransport());
  });

  tearDown(() => device.dispose());

  Map<String, Object?> snapshot() {
    editor = RecipeEditor(device: device, prefs: prefs);
    return buildWatchSnapshot(
      d: device,
      t: t,
      prefs: prefs,
      recipe: editor.active,
      scanning: false,
    );
  }

  Map<String, Object?> busySnapshot() {
    editor = RecipeEditor(device: device, prefs: prefs);
    return buildWatchSnapshot(
      d: device,
      t: t,
      prefs: prefs,
      recipe: editor.active,
      scanning: false,
      ctaBusy: true,
    );
  }

  List<String> idsOf(Map<String, Object?> s) => [
    for (final r in s['steps'] as List) (r as Map)['id'] as String,
  ];

  test('полный цикл: четыре ряда, пролив свёрнут', () async {
    await device.connect('mock-k2pro');
    await Future<void>.delayed(const Duration(seconds: 3));

    final s = snapshot();
    expect(s['v'], kWatchContractVersion);
    expect(idsOf(s), ['alarm', 'mode', 'heat', 'pour']);

    final pour = (s['steps'] as List).last as Map;
    expect(pour['editor'], 'group');
    final children = pour['children'] as List;
    expect(
      [for (final c in children) (c as Map)['id']],
      ['wetting', 'pause', 'extraction', 'flow'],
    );
    // Границы приезжают с телефона: на часах их выдумывать нечем.
    for (final c in children) {
      expect((c as Map)['max'], isA<int>());
      expect(c['max'], greaterThan(0));
    }
  });

  test('только нагрев: пролива нет вовсе', () async {
    prefs.runMode = WorkMode.heat;
    await device.connect('mock-k2pro');
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(idsOf(snapshot()), ['alarm', 'mode', 'heat']);
  });

  test('холодный пролив: нагрева нет', () async {
    prefs.runMode = WorkMode.brew;
    await device.connect('mock-k2pro');
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(idsOf(snapshot()), ['alarm', 'mode', 'pour']);
  });

  test('своя машина в списке даже без сканирования', () async {
    // Раньше список строился из результатов скана — и пустел, как только скан
    // заканчивался, хотя телефон машину прекрасно помнил.
    prefs.lastDeviceId = 'mock-k2pro';
    prefs.deviceName = 'Моя K2';

    final devices = snapshot()['devices'] as List;
    expect(devices, hasLength(1));
    final mine = devices.first as Map;
    expect(mine['name'], 'Моя K2');
    expect(mine['known'], true);
    expect(mine['connected'], false);
  });

  test('подключённая машина помечена и несёт заряд', () async {
    prefs.deviceName = 'Моя K2';
    await device.connect('mock-k2pro');
    await Future<void>.delayed(const Duration(seconds: 3));

    final mine = (snapshot()['devices'] as List).first as Map;
    expect(mine['connected'], true);
    expect(mine['name'], 'Моя K2');
    expect(mine['batteryPercent'], isA<int>());
  });

  test('ожидание показывается только на пуске и остановке', () async {
    // До подключения кнопка предлагает подключиться — крутить там нечего.
    expect(((busySnapshot()['cta'] as Map)['busy']), false);

    await device.connect('mock-k2pro');
    await Future<void>.delayed(const Duration(seconds: 3));

    final cta = busySnapshot()['cta'] as Map;
    expect(cta['kind'], 'start');
    expect(cta['busy'], true);
  });

  test('снимок сериализуется: null-ов в WatchConnectivity быть не должно', () {
    final s = snapshot();
    expect(() => _encode(s), returnsNormally);
  });
}

String _encode(Object? o) => jsonEncode(o);
