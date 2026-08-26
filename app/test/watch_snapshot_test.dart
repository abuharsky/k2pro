import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/scale/mock_scale_transport.dart';
import 'package:k2pro/ble/scale/scale_device.dart';
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
  late ScaleDevice scale;
  late RecipeEditor editor;
  final t = lookupAppL10n(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await Prefs.load();
    device = K2Device(MockTransport());
    scale = ScaleDevice(MockScaleTransport());
  });

  tearDown(() {
    device.dispose();
    scale.dispose();
  });

  Map<String, Object?> snapshot() {
    editor = RecipeEditor(device: device, prefs: prefs);
    return buildWatchSnapshot(
      d: device,
      scale: scale,
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
      scale: scale,
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

  test('нагрев с проливом: четыре ряда, пролив свёрнут', () async {
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
    expect(mine['battery'], isA<int>());
    expect(mine['batteryPercent'], isNull);
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

  test('весы стоят в списке устройств отдельной строкой', () async {
    prefs.lastDeviceId = 'mock-k2pro';
    prefs.deviceName = 'Моя K2';
    await scale.connect(kMockScaleId);
    await Future<void>.delayed(const Duration(seconds: 1));

    final devices = snapshot()['devices'] as List;
    // Машина и весы — два разных прибора, и род у каждого свой: по нему часы
    // и решают, какой экран открыть по тапу.
    expect([for (final d in devices) (d as Map)['kind']], ['machine', 'scale']);
  });

  test('весы отдают готовые строки, а не граммы', () async {
    await scale.connect(kMockScaleId);
    await Future<void>.delayed(const Duration(seconds: 1));

    final s = snapshot()['scale'] as Map;
    expect(s['connected'], true);
    expect(s['live'], true);
    // Пересчитывать граммы на часах нечем и незачем: строка уже готова.
    expect(s['grams'], isA<String>());
    expect(s['tareEnabled'], true);
  });

  test('ряд веса появляется только с весами и уходит последним', () async {
    await device.connect('mock-k2pro');
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(idsOf(snapshot()), isNot(contains('weight')));

    await scale.connect(kMockScaleId);
    await Future<void>.delayed(const Duration(seconds: 1));

    final s = snapshot();
    expect(idsOf(s).last, 'weight');
    final weight = (s['steps'] as List).last as Map;
    // Цель едет десятыми долями грамма: редактор на часах целочисленный.
    expect(weight['editor'], 'weight');
    expect(weight['decimals'], 1);
    expect(weight['editValue'], (prefs.gravimetry.targetG * 10).round());
  });

  test('снимок с весами тоже сериализуется', () async {
    await scale.connect(kMockScaleId);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(() => _encode(snapshot()), returnsNormally);
  });

  test('таймер: пресеты на месте, взведён — есть отсчёт и час старта', () async {
    await device.connect('mock-k2pro');
    await Future<void>.delayed(const Duration(seconds: 3));

    final idle = snapshot()['timer'] as Map;
    expect(idle['armed'], false);
    expect(idle['presets'], [5, 10, 20, 30]);
    // Пока не взведён, живому отсчёту взяться неоткуда.
    expect(idle['readyInSeconds'], isNull);
    expect(idle['startLine'], isNull);

    // Взвели будильник — теперь есть и остаток, и строка «Старт в …».
    final a = device.appointment;
    device.setSchedule(a.copyWith(enabled: true), immediate: true);
    final armed = snapshot()['timer'] as Map;
    expect(armed['armed'], true);
    expect(armed['readyInSeconds'], isA<int>());
    expect(armed['startLine'], isA<String>());
  });

  test('снимок сериализуется: null-ов в WatchConnectivity быть не должно', () {
    final s = snapshot();
    expect(() => _encode(s), returnsNormally);
  });
}

String _encode(Object? o) => jsonEncode(o);
