import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/cycle.dart';
import 'package:k2pro/ble/k2_device.dart';
import 'package:k2pro/ble/mock_transport.dart';
import 'package:k2pro/ble/protocol.dart';
import 'package:k2pro/ble/session.dart';
import 'package:k2pro/ble/trace.dart';
import 'package:k2pro/model/brew_phase.dart';

/// Прогон вхолостую: те же сценарии, что ловились на живой машине, но на моке.
///
/// Проверяется не «упало или нет», а сама лента переходов — то, что человек
/// увидит на кнопке и что потом придётся читать в трассе. Полная лента каждого
/// сценария складывается в `build/scenarios.log`: с ней разбор живого лога
/// сводится к сравнению двух файлов.
void main() {
  final dump = StringBuffer();

  setUpAll(() => Trace.instance.sink = dump.writeln);
  tearDownAll(() {
    Trace.instance.sink = null;
    Directory('build').createSync(recursive: true);
    File('build/scenarios.log').writeAsStringSync(dump.toString());
  });

  /// Прогнать сценарий и вернуть только переходы машин состояний.
  Future<List<String>> play(
    WidgetTester tester,
    String title,
    Future<void> Function(MockTransport mock, K2Device device) body,
  ) async {
    dump.writeln('\n===== $title =====');
    final from = dump.length;
    // Часы у мока те же, что у устройства: иначе симулятор живёт по настоящему
    // времени, пока приложение идёт по фейковому, и цикл у него не кончается
    // никогда — сценарий пролива просто не досматривается до конца.
    final mock = MockTransport(now: () => tester.binding.clock.now());
    final device = K2Device(mock, now: () => tester.binding.clock.now());
    try {
      await body(mock, device);
    } finally {
      device.dispose();
      await tester.pump();
    }
    return dump
        .toString()
        .substring(from)
        .split('\n')
        .where((l) => l.startsWith('сеанс ') || l.startsWith('цикл '))
        .toList();
  }

  /// Коды команд из всего, что приложение записало.
  List<int> cmds(MockTransport t) => t.sent.map((f) => f[4]).toList();

  Future<void> settle(WidgetTester tester, [int steps = 12]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('бодрая машина: подключились, сварили, остановили', (
    tester,
  ) async {
    final steps = await play(tester, 'бодрая машина', (mock, d) async {
      d.connect('mock');
      await settle(tester);
      expect(d.sessionState, SessionState.ready);

      d.heat();
      await settle(tester);
      expect(d.cycleState, CycleState.running);

      unawaited(d.stop());
      await settle(tester);
      expect(d.cycleState, CycleState.idle);

      unawaited(d.disconnect());
      await settle(tester);
    });

    expect(steps, [
      'сеанс idle --connectRequested--> connecting',
      'сеанс connecting --linkUp--> handshaking',
      'сеанс handshaking --handshakeDone--> ready',
      'цикл idle --startRequested--> starting',
      'цикл starting --machineBusy--> running',
      'цикл running --stopRequested--> stopping',
      'цикл stopping --machineIdle--> idle',
      'сеанс ready --disconnectRequested--> idle',
    ]);
  });

  testWidgets('пролив целиком: фазы сменяются, секунды и градусы идут', (
    tester,
  ) async {
    // То, ради чего экран и открыли: после пуска подпись меняется сама,
    // счётчик секунд растёт, температура ползёт вверх. На живой машине это
    // видно только вживую — здесь это утверждение, а в дампе рядом лежит
    // готовая лента, с которой живую трассу можно сверить построчно.
    final phases = <String>[];
    final seconds = <String, List<int>>{};
    final temps = <int>[];

    final steps = await play(tester, 'пролив целиком', (mock, d) async {
      d.connect('mock');
      await settle(tester);

      d.heatAndBrew();
      for (var i = 0; i < 800 && d.progress.phase != BrewPhase.done; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final p = d.progress;
        if (phases.isEmpty || phases.last != p.phase.name) {
          phases.add(p.phase.name);
        }
        (seconds[p.phase.name] ??= []).add(p.elapsed.inSeconds);
        final t = d.status?.temperatureC;
        if (t != null) temps.add(t);
      }
    });

    expect(steps, [
      'сеанс idle --connectRequested--> connecting',
      'сеанс connecting --linkUp--> handshaking',
      'сеанс handshaking --handshakeDone--> ready',
      'цикл idle --startRequested--> starting',
      'цикл starting --machineBusy--> running',
      'цикл running --machineDone--> finished',
    ]);

    // Ни одна фаза не пропущена и ни одна не повторилась: машина у уставки
    // колеблется ±1°, и подпись не должна прыгать обратно в нагрев.
    expect(phases, [
      'heating',
      'preInfusion',
      'standstill',
      'extraction',
      'done',
    ]);

    for (final phase in ['heating', 'preInfusion', 'standstill', 'extraction']) {
      final ticks = seconds[phase]!;
      expect(
        ticks,
        orderedEquals(List.of(ticks)..sort()),
        reason: '$phase: секунды идут только вперёд',
      );
      expect(ticks.last, greaterThan(0), reason: '$phase: счётчик пошёл');
    }

    expect(temps.first, lessThan(temps.last), reason: 'нагрев виден на экране');
    expect(temps.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(92));
  });

  testWidgets('спящая машина: пуск проходит, опрос доводится при пробуждении', (
    tester,
  ) async {
    final steps = await play(tester, 'спящая машина', (mock, d) async {
      mock.mute = true;
      d.connect('mock');
      await settle(tester, 32);
      expect(d.sessionState, SessionState.dormant);
      expect(d.isConnected, isTrue, reason: 'связь есть, молчит машина');

      // Пуск уходит сразу: очередь свободна, опрос не заведён. Спящая машина
      // его глотает — как и всё остальное, — но кнопка не заперта.
      d.heat();
      await tester.pump(const Duration(milliseconds: 100));
      expect(d.cycleState, CycleState.starting);
      expect(cmds(mock), contains(Cmd.setWorkState));

      // Машина проснулась сама. Первый кадр пуска она проспала — но повтор
      // приходится уже на проснувшуюся, и пуск доходит с того же нажатия.
      // Раньше повторов у пуска не было вовсе, и такое нажатие пропадало
      // молча: человек жал ещё раз, а машина включалась от старого кадра.
      mock.mute = false;
      await settle(tester, 44);
      expect(d.sessionState, SessionState.ready);
      expect(d.cycleState, CycleState.running);

      unawaited(d.stop());
      await settle(tester);
    });

    expect(steps, [
      'сеанс idle --connectRequested--> connecting',
      'сеанс connecting --linkUp--> handshaking',
      'сеанс handshaking --probeSilent--> dormant',
      'цикл idle --startRequested--> starting',
      'сеанс dormant --telemetry--> handshaking',
      'цикл starting --machineBusy--> running',
      'сеанс handshaking --handshakeDone--> ready',
      'цикл running --stopRequested--> stopping',
      'цикл stopping --machineIdle--> idle',
    ]);
  });

  testWidgets('машина приняла пуск и молчит: линия пересобирается', (
    tester,
  ) async {
    // Живой случай 25.08 10:36: машина спала, кадры принимала — от пуска она
    // включилась, — но не ответила ни на один и телеметрию не прислала. На
    // этой линии ждать больше нечего: подписка до машины не доходит.
    final steps = await play(tester, 'пересборка линии', (mock, d) async {
      mock.mute = true;
      d.connect('mock');
      await settle(tester, 32);
      expect(d.sessionState, SessionState.dormant);
      final links = mock.connects;

      d.heat();
      await settle(tester, 40);
      expect(mock.connects, links + 1, reason: 'линия пересобрана');

      // На свежей линии машина отзывается — приложение догоняет само.
      mock.mute = false;
      await settle(tester, 40);
      expect(d.sessionState, SessionState.ready);
    });
    expect(steps, [
      'сеанс idle --connectRequested--> connecting',
      'сеанс connecting --linkUp--> handshaking',
      'сеанс handshaking --probeSilent--> dormant',
      'цикл idle --startRequested--> starting',
      'цикл starting --confirmTimeout--> idle',
      // Линию рвём мы сами, поэтому обрыв идёт через переподключение — но без
      // паузы: отложенная попытка снимается, поднимаем сразу.
      'сеанс dormant --linkDown--> reconnecting',
      'сеанс reconnecting --linkUp--> handshaking',
      'сеанс handshaking --probeSilent--> dormant',
      'сеанс dormant --telemetry--> handshaking',
      'сеанс handshaking --handshakeDone--> ready',
    ]);
  });

  testWidgets('нет воды: цикл оборван, ошибка не теряется', (tester) async {
    final steps = await play(tester, 'нет воды', (mock, d) async {
      d.connect('mock');
      await settle(tester);
      d.heat();
      await settle(tester);

      mock.fault = MachineError.dryBurning;
      await tester.pump(const Duration(milliseconds: 600));
      mock.fault = MachineError.none;
      await settle(tester);
      expect(d.cycleState, CycleState.faulted);
      expect(d.lastFault, MachineError.dryBurning);

      // Ошибку прочли — и цикл заново сверяется с машиной, а не решает за неё:
      // мок после аварии продолжает греть, значит и на кнопке должен быть стоп.
      d.clearFault();
      await tester.pump();
      expect(d.cycleState, CycleState.idle);
      await settle(tester);
      expect(d.cycleState, CycleState.running);

      unawaited(d.stop());
      await settle(tester);
    });

    expect(steps, [
      'сеанс idle --connectRequested--> connecting',
      'сеанс connecting --linkUp--> handshaking',
      'сеанс handshaking --handshakeDone--> ready',
      'цикл idle --startRequested--> starting',
      'цикл starting --machineBusy--> running',
      'цикл running --machineFault--> faulted',
      'цикл faulted --faultCleared--> idle',
      'цикл idle --machineBusy--> running',
      'цикл running --stopRequested--> stopping',
      'цикл stopping --machineIdle--> idle',
    ]);
  });

  testWidgets('машину унесли посреди цикла и принесли обратно', (tester) async {
    final steps = await play(tester, 'обрыв и возврат', (mock, d) async {
      d.connect('mock');
      await settle(tester);
      d.heat();
      await settle(tester);
      expect(d.cycleState, CycleState.running);

      mock.dropLink();
      await tester.pump();
      expect(d.cycleState, CycleState.idle, reason: 'про машину ничего не знаем');
      expect(d.sessionState, SessionState.reconnecting);

      // Первая пауза — две секунды; ждём её и подъём связи.
      await settle(tester, 24);
      expect(d.sessionState, SessionState.ready);

      unawaited(d.stop());
      await settle(tester);
    });

    expect(steps, [
      'сеанс idle --connectRequested--> connecting',
      'сеанс connecting --linkUp--> handshaking',
      'сеанс handshaking --handshakeDone--> ready',
      'цикл idle --startRequested--> starting',
      'цикл starting --machineBusy--> running',
      'сеанс ready --linkDown--> reconnecting',
      'цикл running --linkLost--> idle',
      'сеанс reconnecting --reconnectDue--> connecting',
      'сеанс connecting --linkUp--> handshaking',
      // Машина всё ещё греет — цикл подхватывается по первой же телеметрии.
      'цикл idle --machineBusy--> running',
      'сеанс handshaking --handshakeDone--> ready',
      'цикл running --stopRequested--> stopping',
      'цикл stopping --machineIdle--> idle',
    ]);
  });

  testWidgets('кадр пуска потерялся: кнопка отпускается сама', (tester) async {
    final steps = await play(tester, 'потерянный пуск', (mock, d) async {
      d.connect('mock');
      await settle(tester);
      mock.mute = true;

      d.heat();
      await settle(tester, 40);
      expect(d.cycleState, CycleState.idle);
      expect(d.sessionState, SessionState.dormant, reason: 'замолчала совсем');
    });

    expect(steps, [
      'сеанс idle --connectRequested--> connecting',
      'сеанс connecting --linkUp--> handshaking',
      'сеанс handshaking --handshakeDone--> ready',
      'цикл idle --startRequested--> starting',
      // Три попытки укладываются в полторы секунды — кнопка отпускается
      // раньше, чем сеанс успевает признать машину спящей.
      'цикл starting --confirmTimeout--> idle',
      'сеанс ready --silenceElapsed--> dormant',
    ]);
  });
}
