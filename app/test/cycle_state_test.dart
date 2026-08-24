import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/ble/cycle.dart';

/// Таблица переходов цикла — отдельно от устройства.
void main() {
  Cycle run(List<CycleEvent> events, {List<String>? trace}) {
    final c = Cycle(onEnter: (from, to) => trace?.add(to.name));
    for (final e in events) {
      c.fire(e);
    }
    return c;
  }

  test('обычный цикл: пуск → работа → готово → покой', () {
    fakeAsync((a) {
      final trace = <String>[];
      final c = Cycle(onEnter: (from, to) => trace.add(to.name));
      addTearDown(c.dispose);

      c.fire(CycleEvent.startRequested);
      expect(c.state, CycleState.starting);
      c.fire(CycleEvent.machineBusy);
      expect(c.state, CycleState.running);
      c.fire(CycleEvent.machineDone);
      expect(c.state, CycleState.finished);

      // Зелёное «готово» уходит само.
      a.elapse(kDoneBadge - const Duration(milliseconds: 1));
      expect(c.state, CycleState.finished);
      a.elapse(const Duration(milliseconds: 2));
      expect(c.state, CycleState.idle);

      expect(trace, ['starting', 'running', 'finished', 'idle']);
    });
  });

  test('пуск и останов по нажатию', () {
    final c = run([
      CycleEvent.startRequested,
      CycleEvent.machineBusy,
      CycleEvent.stopRequested,
    ]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.stopping);
    c.fire(CycleEvent.machineIdle);
    expect(c.state, CycleState.idle);
  });

  test('несостоявшийся пуск отпускает кнопку сам', () {
    fakeAsync((a) {
      final c = Cycle(onEnter: (_, _) {});
      addTearDown(c.dispose);
      c.fire(CycleEvent.startRequested);
      a.elapse(kConfirmTimeout + const Duration(seconds: 1));
      expect(c.state, CycleState.idle, reason: 'кадр потерялся — пуска не было');
    });
  });

  test('неподтверждённый останов считается работой, а не покоем', () {
    // Ошибиться тут можно только в одну сторону: показать «стоит», когда она
    // греет, — хуже, чем показать «работает», когда уже встала.
    fakeAsync((a) {
      final c = Cycle(onEnter: (_, _) {});
      addTearDown(c.dispose);
      c.fire(CycleEvent.startRequested);
      c.fire(CycleEvent.machineBusy);
      c.fire(CycleEvent.stopRequested);
      a.elapse(kConfirmTimeout + const Duration(seconds: 1));
      expect(c.state, CycleState.running);
    });
  });

  test('пока кадр пуска в пути, прошлое состояние машины не считается', () {
    // Между нашим 0x02 и первой «занятой» телеметрией машина ещё повторяет то,
    // чем была. Принять это за ответ — значит отпустить кнопку впустую.
    final c = run([CycleEvent.startRequested, CycleEvent.machineIdle]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.starting);
  });

  test('пока кадр останова в пути, «занята» не отменяет ожидания', () {
    final c = run([
      CycleEvent.startRequested,
      CycleEvent.machineBusy,
      CycleEvent.stopRequested,
      CycleEvent.machineBusy,
    ]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.stopping);
  });

  test('подключились к уже работающей машине — цикл её подхватывает', () {
    final c = run([CycleEvent.machineBusy]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.running);
  });

  test('чужое «готово» в покое не зажигает зелёную кнопку', () {
    // Машина держит «готово» до следующей команды. Подключение к ней — не наш
    // цикл, и итога у него нет.
    final c = run([CycleEvent.machineDone]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.idle);
  });

  test('после зелёной кнопки повтор «готово» её не возвращает', () {
    fakeAsync((a) {
      final c = Cycle(onEnter: (_, _) {});
      addTearDown(c.dispose);
      c.fire(CycleEvent.startRequested);
      c.fire(CycleEvent.machineBusy);
      c.fire(CycleEvent.machineDone);
      a.elapse(kDoneBadge * 2);
      expect(c.state, CycleState.idle);
      c.fire(CycleEvent.machineDone);
      expect(c.state, CycleState.idle, reason: 'иначе кнопка мигала бы вечно');
    });
  });

  test('ошибка обрывает цикл и держит его оборванным', () {
    final c = run([
      CycleEvent.startRequested,
      CycleEvent.machineBusy,
      CycleEvent.machineFault,
    ]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.faulted);

    // Машина встала — но молча вернуться в покой значит потерять единственный
    // признак: код ошибки живёт в телеметрии один пакет.
    c.fire(CycleEvent.machineIdle);
    expect(c.state, CycleState.faulted);

    c.fire(CycleEvent.faultCleared);
    expect(c.state, CycleState.idle);
  });

  test('из оборванного цикла можно пустить заново', () {
    final c = run([
      CycleEvent.startRequested,
      CycleEvent.machineBusy,
      CycleEvent.machineFault,
      CycleEvent.startRequested,
    ]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.starting);
  });

  test('в покое ошибка цикл не портит: её показывает баннер', () {
    final c = run([CycleEvent.machineFault]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.idle);
  });

  test('повторный пуск по идущему циклу ничего не делает', () {
    for (final path in [
      [CycleEvent.startRequested],
      [CycleEvent.startRequested, CycleEvent.machineBusy],
      [
        CycleEvent.startRequested,
        CycleEvent.machineBusy,
        CycleEvent.stopRequested,
      ],
    ]) {
      final c = run(path);
      addTearDown(c.dispose);
      final was = c.state;
      expect(c.fire(CycleEvent.startRequested), isFalse, reason: '$path');
      expect(c.state, was);
    }
  });

  test('стоп догоняет незавершённый пуск', () {
    // Кадр пуска мог и уйти: человек, нажавший стоп, хочет стоп, а не отмену
    // собственного ожидания.
    final c = run([CycleEvent.startRequested, CycleEvent.stopRequested]);
    addTearDown(c.dispose);
    expect(c.state, CycleState.stopping);
  });

  test('обрыв связи возвращает цикл в покой из любого места', () {
    for (final path in [
      [CycleEvent.startRequested],
      [CycleEvent.startRequested, CycleEvent.machineBusy],
      [
        CycleEvent.startRequested,
        CycleEvent.machineBusy,
        CycleEvent.machineDone,
      ],
      [
        CycleEvent.startRequested,
        CycleEvent.machineBusy,
        CycleEvent.machineFault,
      ],
    ]) {
      final c = run([...path, CycleEvent.linkLost]);
      addTearDown(c.dispose);
      expect(c.state, CycleState.idle, reason: '$path');
    }
  });

  test('таймер прошлого состояния не срабатывает в новом', () {
    fakeAsync((a) {
      final c = Cycle(onEnter: (_, _) {});
      addTearDown(c.dispose);
      c.fire(CycleEvent.startRequested);
      a.elapse(kConfirmTimeout - const Duration(seconds: 1));
      c.fire(CycleEvent.machineBusy);
      a.elapse(const Duration(seconds: 5));
      expect(c.state, CycleState.running, reason: 'таймаут пуска снят');
    });
  });
}
