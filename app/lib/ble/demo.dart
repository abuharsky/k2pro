/// Демо-режим: приложение целиком переезжает на симуляторы.
///
/// Единственное место, которое знает, что демо вообще бывает. Всё остальное
/// работает как обычно: симуляторы отвечают настоящими кадрами протокола, так
/// что в демо проверяется тот же код, что и на живой машине.
///
/// Демо не переживает перезапуск: флага в настройках нет намеренно — закрыл
/// приложение, снова первый экран. Спутать симулятор с железом дороже, чем
/// нажать одну кнопку ещё раз.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../store/prefs.dart';
import 'k2_device.dart';
import 'mock_transport.dart';
import 'protocol.dart';
import 'scale/mock_scale_transport.dart';
import 'scale/scale_device.dart';
import 'switchable_transport.dart';
import 'trace.dart';
import 'transport.dart';

/// Что ломается в демо и в каком порядке: чистый прогон, нет воды, чистый,
/// перегрев — и по кругу.
///
/// Исправная машина показывает половину приложения. Вторая половина — сорванный
/// цикл, запертый до «Проверить» пуск и подсказка, что с этим делать, — без
/// поломки не показывается никогда.
///
/// Из пяти кодов взяты эти два: у них есть внятное действие в ответ («добавьте
/// воду», «дайте остыть»). Замыкание нагревателя — тупик с «нужен сервис»,
/// показывать в демо нечего, а низкий заряд путался бы с батареей, которая в
/// симуляторе и так садится.
const List<MachineError> kDemoFaults = [
  MachineError.none,
  MachineError.dryBurning,
  MachineError.none,
  MachineError.batteryOverheating,
];

class Demo extends ChangeNotifier {
  Demo({
    required this.machineLink,
    required this.scaleLink,
    required this.device,
    required this.scale,
    required this.prefs,
  }) : _realMachine = machineLink.inner,
       _realScale = scaleLink.inner;

  /// Транспорты, у которых меняется начинка.
  final SwitchableTransport machineLink;
  final SwitchableTransport scaleLink;

  final K2Device device;
  final ScaleDevice scale;
  final Prefs prefs;

  /// То, с чем приложение говорит вне демо. Запоминаем на старте: вернуться
  /// нужно ровно к этим, а не к новым — на них висит общий сканер.
  final K2Transport _realMachine;
  final K2Transport _realScale;

  MockTransport? _machineMock;
  MockScaleTransport? _scaleMock;

  bool get on => _machineMock != null;

  /// Симулятор машины, пока демо идёт. Через него дёргаются ручки, которых у
  /// живой машины нет: ошибка, обрыв связи, дежурный режим.
  MockTransport? get machineMock => _machineMock;

  /// Симулятор весов.
  MockScaleTransport? get scaleMock => _scaleMock;

  /// Войти в демо: подменить оба транспорта и подключиться к обоим сразу.
  ///
  /// Поиск в демо не нужен — искать нечего, а человек нажал «посмотреть», а не
  /// «выбрать устройство».
  Future<void> enter() async {
    if (on) return;
    Trace.instance.ui('демо: вход');

    // Симуляторы строятся парой: весы смотрят на машину, и вода, которую та
    // льёт, доезжает до них с задержкой. Порознь они бесполезны — весь контур
    // останова держится именно на этой задержке.
    final machine = MockTransport(faultCycle: kDemoFaults);
    final scaleMock = MockScaleTransport(pourFlow: () => machine.pourFlow);
    _machineMock = machine;
    _scaleMock = scaleMock;

    // Сначала отключаемся, потом меняем начинку: обрыв, случившийся при живом
    // сеансе, поднял бы переподключение — и оно ушло бы искать прежнюю машину
    // уже в симуляторе.
    await device.disconnect();
    await scale.disconnect();

    prefs.demo = true;
    await machineLink.swap(machine);
    await scaleLink.swap(scaleMock);
    notifyListeners();

    await device.connect(kMockMachineId);
    await scale.connect(kMockScaleId);
  }

  /// Выйти из демо: вернуть настоящие транспорты и погасить симуляторы.
  Future<void> leave() async {
    final machine = _machineMock;
    final scaleMock = _scaleMock;
    if (machine == null || scaleMock == null) return;
    Trace.instance.ui('демо: выход');

    await device.disconnect();
    await scale.disconnect();

    await machineLink.swap(_realMachine);
    await scaleLink.swap(_realScale);

    _machineMock = null;
    _scaleMock = null;
    prefs.demo = false;
    notifyListeners();

    // Гасим только после подмены: у симуляторов свои таймеры, и оставленные
    // работать они продолжали бы слать кадры в закрытые потоки.
    await machine.dispose();
    await scaleMock.dispose();
  }

  @override
  void dispose() {
    // Гасим симуляторы, если демо шло: их таймеры переживают экран.
    unawaited(_machineMock?.dispose() ?? Future<void>.value());
    unawaited(_scaleMock?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}
