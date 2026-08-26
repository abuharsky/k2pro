import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../model/brew_phase.dart';
import '../model/recipe.dart';
import 'protocol.dart';
import 'cycle.dart';
import 'session.dart';
import 'trace.dart';
import 'transport.dart';

/// Высокоуровневый API машины. UI знает только про этот класс.
class K2Device extends ChangeNotifier {
  K2Device(this._transport, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _linkSub = _transport.linkState.listen(_onLink);
    _notifySub = _transport.notifications.listen(_onNotify);
    _scanSub = _transport.scanResults.listen((d) {
      discovered = d;
      notifyListeners();
    });
  }

  final K2Transport _transport;
  final DateTime Function() _now;
  late final StreamSubscription<LinkState> _linkSub;
  late final StreamSubscription<Uint8List> _notifySub;
  late final StreamSubscription<List<DiscoveredDevice>> _scanSub;

  final _decoder = FrameDecoder();
  final _fragments = FragmentAssembler();
  final _phases = BrewPhaseEstimator();

  // ---- наблюдаемое состояние -------------------------------------------

  LinkState link = LinkState.disconnected;
  List<DiscoveredDevice> discovered = const [];
  String? connectedId;

  DeviceStatus? status;

  /// Диапазоны уставок. Пустыми не бывают никогда: до первого ответа машины
  /// здесь стоит кэш прошлого сеанса, а в самый первый раз — [kFallbackLimits]
  /// и [kFallbackParams]. Иначе из дежурного режима, где машина молчит на всё
  /// рукопожатие, экран остался бы нередактируемым до переподключения вручную.
  TempLimits tempLimits = kFallbackLimits;
  WorkParams workParams = kFallbackParams;

  /// Машина сама рассказала о себе — значит, диапазоны настоящие, а не кэш.
  bool rangesFromDevice = false;
  Appointment appointment = const Appointment.disabled();

  /// Когда будильник взвели. Машина момент срабатывания не сообщает и своих
  /// часов нам не показывает, поэтому без этой отметки непонятно, на какие
  /// ближайшие hh:mm указывает уставка — на сегодня или уже на завтра.
  DateTime? _armedAt;

  /// Когда будильник отжил своё. Свой переключатель мы гасим сами, а что при
  /// этом сделала со своим флагом машина — идём проверять у неё же. Но не
  /// сразу: в момент срабатывания она ещё в покое и цикл начинает секунд
  /// через семь, так что ранний 0x24 вернул бы флаг ещё взведённым.
  DateTime? _spentAt;

  /// Машина после срабатывания успела уйти в работу. Тогда её возврат в покой
  /// — это конец цикла, и самое время спросить про флаг.
  bool _busySinceSpent = false;

  /// Пока крутят время, запись в машину ждёт паузы. См. [setSchedule].
  Timer? _scheduleDebounce;

  /// Когда пришёл последний кадр телеметрии.
  ///
  /// Машина шлёт его сама, ровно раз в 1.02 с (медиана по 82 тысячам
  /// интервалов; внутри одной сессии разброс — единицы миллисекунд). Нужен он
  /// затем, чтобы в трассе у каждой отправки стояла фаза — расстояние до
  /// прошлого тика. Если потери и правда липнут к какому-то участку периода,
  /// это будет видно на гистограмме; пока по четырём точкам не видно ничего.
  DateTime? _lastTelemetryAt;

  /// Последний кадр, который машина прислала сама и который мы не умеем
  /// разбирать. Держим сырым: толковать пока не на чем.
  String? lastEventRaw;
  int? lastEventCmd;
  DateTime? lastEventAt;
  DeviceInfo? info;
  int? todayCups;
  Map<DateTime, int> history = const {};
  BrewProgress progress = BrewProgress.idle;
  String? lastError;

  /// Последняя ошибка, которую сообщила машина, и когда это было. В отличие от
  /// [status], переживает возврат в норму — по ней видно, почему цикл встал.
  MachineError lastFault = MachineError.none;
  DateTime? lastFaultAt;

  /// Сырой код той же ошибки. Для незнакомого кода это всё, что есть, —
  /// и то, что человек продиктует в сервис.
  int lastFaultCode = 0;

  /// Последний пакет 0x00 как есть. Нужен, когда машина ведёт себя не по
  /// документации: по разобранным полям видно не всё.
  String lastStateRaw = '';

  /// Рецепт, который сейчас записан в машине.
  Recipe get deviceRecipe => Recipe(
    name: 'Device',
    temperatureC: tempLimits.target,
    pressure: workParams.pressure.value,
    preInfusionSeconds: workParams.preInfusion.value,
    standstillSeconds: workParams.standstill.value,
    extractionSeconds: workParams.extraction.value,
  );

  /// Подставить уставки и диапазоны, снятые в прошлый раз.
  ///
  /// Зовётся до подключения, ответ машины их перекрывает. Сама машина хранит
  /// всё это у себя, так что кэш нужен ровно затем, чтобы было чем жить, пока
  /// она не отозвалась.
  void seed({TempLimits? limits, WorkParams? params}) {
    if (rangesFromDevice) return;
    if (limits != null) tempLimits = limits;
    if (params != null) workParams = params;
    notifyListeners();
  }

  /// Машина на линии. Спрашивать надо у сеанса, а не у транспорта: связь может
  /// стоять, а сеанс уже считать её мёртвой — и наоборот.
  bool get isConnected => _session.state.isLinked;

  /// Связи нет, но мы её добиваемся — первое подключение или переподключение.
  /// Для человека это одно и то же ожидание.
  bool get isSeeking => _session.state.isSeeking;
  bool get isBusy => status?.state.isBusy ?? false;

  /// Единая точка времени для UI и детерминированных тестов будильника.
  DateTime get currentTime => _now();

  /// Машина на связи, но молчит — спит.
  ///
  /// Отличать это состояние приходится самим: оригинал его не различает вовсе.
  /// Периодических таймеров в его BLE-слое нет ни одного, а «Standby» на его
  /// экране — это состояние 0 из той же телеметрии, то есть признак живой
  /// машины, а не спящей. Пока кадры не идут, у него на экране остаётся
  /// последнее, что пришло.
  bool get isAsleep => _session.state == SessionState.dormant;

  /// Телеметрии нет дольше отведённого. Отсчёт от последнего кадра, а до
  /// первого — от момента связи: живая машина отзывается за секунду, так что
  /// за отведённые пять её молчание успевает стать фактом, а не задержкой
  /// подключения.
  bool get _silent {
    final t = _lastTelemetryAt ?? _linkedAt;
    if (t == null) return true;
    return _now().difference(t) > kTelemetrySilence;
  }

  /// Когда установилась связь. Точка отсчёта молчания до первой телеметрии.
  DateTime? _linkedAt;

  // ---- сеанс ------------------------------------------------------------

  /// Где сейчас связь. Единственный источник правды про неё: см. [Session].
  late final Session _session = Session(onEnter: _onSession, log: _log);

  SessionState get sessionState => _session.state;

  late final Cycle _cycle = Cycle(
    onEnter: (from, to) {
      // Цикл кончился — прежние оценки фаз к следующему отношения не имеют.
      if (to == CycleState.idle) {
        // И заново сверяемся с машиной: в покой можно вернуться по таймауту
        // или по прочитанной ошибке, а она при этом продолжает греть. Без
        // сброса следующая телеметрия не считалась бы сменой, и кнопка
        // предлагала бы пуск работающей машине.
        _cycleSaw = null;
        _phases.reset();
        progress = BrewProgress.idle;
      }
      notifyListeners();
    },
    log: _log,
  );

  /// Где сейчас цикл заваривания. Один на экран, часы и трассу.
  CycleState get cycleState => _cycle.state;

  /// Состояние машины, каким его видел цикл в прошлый раз. Событие рождает
  /// смена, а не кадр: пока наш 0x02 в пути, машина повторяет прошлое, и
  /// принимать это за ответ нельзя. После обрыва обнуляется — за время
  /// молчания машина могла и заработать, и встать.
  MachineState? _cycleSaw;

  int get _linkGen => _session.generation;

  /// Побочные действия перехода. Всё, что раньше висело на присваиваниях
  /// в пяти разных местах, собрано здесь.
  void _onSession(SessionState from, SessionState to) {
    if (from.isLinked && !to.isLinked) _dropLinkState();
    switch (to) {
      case SessionState.handshaking:
        _linkedAt = _now();
        _reconnectAttempt = 0;
        unawaited(_handshake());
      case SessionState.reconnecting:
        _armReconnect();
      case SessionState.ready:
        _reconnectAttempt = 0;
      case SessionState.idle:
        _cancelReconnect();
        connectedId = null;
      case SessionState.connecting:
      case SessionState.dormant:
        break;
    }
    notifyListeners();
  }

  /// Забыть всё, что относилось к упавшей линии.
  void _dropLinkState() {
    _decoder.reset();
    _fragments.reset();
    for (final c in _waiters.values) {
      if (!c.isCompleted) c.completeError(StateError('disconnected'));
    }
    _waiters.clear();
    _lastTelemetryAt = null;
    _linkedAt = null;
    _cycleSaw = null;
    _cycle.fire(CycleEvent.linkLost);
    _phases.reset();
    progress = BrewProgress.idle;
    _ticker?.cancel();
    _ticker = null;
  }

  // ---- подключение ------------------------------------------------------

  Future<void> startScan({bool showAll = false}) async {
    discovered = const [];
    notifyListeners();
    await _transport.startScan(showAll: showAll);
  }

  Future<void> stopScan() => _transport.stopScan();

  Future<void> connect(String id) async {
    _cancelReconnect();
    lastError = null;
    connectedId = id;
    _session.fire(SessionEvent.connectRequested);
    try {
      await _transport.connect(id);
    } catch (e) {
      lastError = '$e';
      _session.fire(SessionEvent.connectFailed);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    // Сначала снять намерение, потом рвать: иначе обрыв, который мы же и
    // устроили, поднимет переподключение.
    _session.fire(SessionEvent.disconnectRequested);
    await _transport.disconnect();
  }

  // ---- переподключение --------------------------------------------------

  /// Ждущая попытка восстановить связь. null — не восстанавливаем.
  Timer? _reconnect;

  /// Номер следующей попытки: по нему растёт пауза.
  int _reconnectAttempt = 0;

  /// Связь оборвалась не по нашей воле — восстанавливать её должны мы.
  ///
  /// Пока этого не было, приложение после любого обрыва молчало до тех пор,
  /// пока человек не переподключится руками, — а обрыв посреди цикла как раз
  /// тот момент, когда смотреть на экран нужнее всего. Автоподключение на
  /// старте тут не помогало: оно срабатывает ровно один раз за запуск.
  ///
  /// Само решение «пора восстанавливать» принимает не этот метод, а таблица
  /// переходов: сюда попадают, только войдя в [SessionState.reconnecting].
  void _armReconnect() {
    final id = connectedId;
    if (id == null || _reconnect != null) return;
    final wait = reconnectDelay(_reconnectAttempt);
    _log(
      'переподключение через ${wait.inSeconds} с (попытка ${_reconnectAttempt + 1})',
    );
    _reconnect = Timer(wait, () async {
      _reconnect = null;
      if (_session.state != SessionState.reconnecting) return;
      _reconnectAttempt++;
      _session.fire(SessionEvent.reconnectDue);
      try {
        await _transport.connect(id);
      } catch (e) {
        _log('переподключение не вышло: $e');
        // Обратно в ожидание: следующая пауза будет вдвое длиннее. Таймер
        // заведёт вход в reconnecting, как и в первый раз.
        _session.fire(SessionEvent.reconnectFailed);
      }
    });
  }

  /// Идёт пересборка линии. Второй такой же ход только помешает.
  bool _relinking = false;

  /// Разорвать линию и поднять заново, не спрашивая человека.
  ///
  /// Не то же самое, что переподключение после обрыва: там линии нет, здесь
  /// она есть и по ней уходят кадры — не приходит только ответ. Такое чинится
  /// единственным способом: новой подпиской, а значит новым подключением.
  Future<void> _relink() async {
    final id = connectedId;
    if (id == null || _relinking) return;
    _relinking = true;
    _log('пересобираем линию: кадры уходят, ответов нет');
    try {
      await _transport.disconnect();
      // Обрыв, который мы устроили сами, успел завести отложенную попытку —
      // она пойдёт навстречу нашей.
      _cancelReconnect();
      await _transport.connect(id);
    } catch (e) {
      _log('пересборка линии не вышла: $e');
      _armReconnect();
    } finally {
      _relinking = false;
    }
  }

  void _cancelReconnect() {
    _reconnect?.cancel();
    _reconnect = null;
    _reconnectAttempt = 0;
  }

  /// Транспорт сказал, что стало с линией. Дальше решает таблица переходов.
  void _onLink(LinkState s) {
    _log('link ${s.name}');
    link = s;
    switch (s) {
      case LinkState.connected:
        _session.fire(SessionEvent.linkUp);
      case LinkState.disconnected:
        _session.fire(SessionEvent.linkDown);
      case LinkState.connecting:
        break;
    }
    notifyListeners();
  }

  /// Порядок после подключения. setTime обязателен, остальное — чтение.
  ///
  /// Машина обрабатывает ровно один запрос за раз: если высыпать чтения пачкой,
  /// она отвечает на первое и молча теряет остальные. Поэтому каждый запрос
  /// ждёт свой ответ и повторяется, если ответа нет.
  Future<void> _handshake() async {
    final gen = _linkGen;
    // Ей нужно время после setNotifyValue, иначе теряется и первая команда.
    await Future<void>.delayed(kHandshakeDelay);
    if (gen != _linkGen) return;
    // Телеметрию 0x00 машина шлёт сама, поэтому фазы считаем сразу, не дожидаясь
    // конца опроса: он может занять секунды.
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tick(),
    );
    // setTime — пробный камень. Спящая машина принимает GATT-подключение и
    // подписку как ни в чём не бывало, а кадры глотает молча: в живой трассе
    // за три минуты не пришло ни одного байта. Опрашивать её дальше нечем —
    // каждый из оставшихся семи запросов стоит своих четырёх секунд впустую
    // и всё это время держит линию. Ждём, пока сама заговорит: телеметрию она
    // начинает слать без спроса, и на неё мы отзовёмся в [_watchSilence].
    if (await _request(cmdSetTime(), Cmd.setTime, tries: 2) == null) {
      if (gen != _linkGen) return;
      _log('машина не отозвалась на 0x04 — опрос отложен до её пробуждения');
      _session.fire(SessionEvent.probeSilent);
      return;
    }
    if (gen != _linkGen) return;
    await _request(cmdGetTempSetting(), Cmd.getTempSetting);
    await _request(cmdGetWorkParams(), Cmd.getWorkParams);
    await _request(cmdGetAppointment(), Cmd.getAppointment);
    await _request(cmdGetDeviceInfo(), Cmd.deviceInfo);
    await _request(cmdGetTodayCups(), Cmd.todayCups);
    await _request(cmdGetCups(), Cmd.cups);
    // Спросить телеметрию, а не ждать её. Так же заканчивает рукопожатие
    // оригинал: последним шагом `initConnect` он зовёт `readRealTimeData`,
    // который шлёт тот же 0x00. Один ответ — и экран показывает состояние
    // сразу, а не через секунды; молчание же сразу видно в трассе.
    await _request(cmdGetDeviceState(), Cmd.deviceState);
    if (gen != _linkGen) return;
    _session.fire(SessionEvent.handshakeDone);
  }

  // ---- очередь записи ---------------------------------------------------

  final Queue<Uint8List> _queue = Queue();
  bool _pumping = false;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  /// Ждущие ответа запросы: cmd -> кому отдать нагрузку.
  final Map<int, Completer<Uint8List>> _waiters = {};

  /// Очередь транзакций. Оригинал держит семафор на всё «запрос → ответ»,
  /// а не только на запись: если между отправкой и ответом влезет чужой кадр,
  /// машина сбивается — теряет ответ и рвёт фрагменты длинных посылок.
  final Queue<Future<void> Function()> _txns = Queue();
  bool _txnBusy = false;

  /// Выполнить тело, когда освободится линия. Ошибки не рвут цепочку.
  ///
  /// [urgent] — встать в начало очереди. Так ходит то, что нажал человек:
  /// пуск, стоп, уставки. Чтение никуда не торопится, а вот кнопка, которая
  /// ждёт своей очереди за чужим опросом, выглядит как сломанная — в живой
  /// трассе между тапом и ушедшим кадром прошло двадцать две секунды.
  Future<T> _exclusive<T>(Future<T> Function() body, {bool urgent = false}) {
    final done = Completer<T>();
    Future<void> run() async {
      try {
        done.complete(await body());
      } catch (e, st) {
        done.completeError(e, st);
      }
    }

    if (urgent) {
      _txns.addFirst(run);
    } else {
      _txns.add(run);
    }
    unawaited(_pumpTxns());
    return done.future;
  }

  Future<void> _pumpTxns() async {
    if (_txnBusy) return;
    _txnBusy = true;
    try {
      while (_txns.isNotEmpty) {
        await _txns.removeFirst()();
      }
    } finally {
      _txnBusy = false;
    }
  }

  /// Отправить и дождаться ответа с тем же cmd. null, если машина промолчала.
  Future<Uint8List?> _request(
    Uint8List frame,
    int cmd, {
    // Машина отвечает медленно: на 0x08 в живом логе ушло 3.2 с.
    Duration timeout = const Duration(seconds: 4),
    int tries = 3,
    bool urgent = false,
  }) {
    // Поколение снимаем здесь, а не в теле: тело выполнится когда-то потом,
    // и к тому времени связь может быть уже другая — та, для которой этот
    // запрос никто не заказывал.
    final gen = _linkGen;
    return _exclusive(
      urgent: urgent,
      () =>
          _requestLocked(frame, cmd, timeout: timeout, tries: tries, gen: gen),
    );
  }

  /// Тело транзакции. Вызывать только из-под [_exclusive].
  Future<Uint8List?> _requestLocked(
    Uint8List frame,
    int cmd, {
    required Duration timeout,
    required int tries,
    required int gen,
  }) async {
    for (var attempt = 1; attempt <= tries; attempt++) {
      if (gen != _linkGen) return null;
      final c = Completer<Uint8List>();
      _waiters[cmd] = c;
      await _send(frame);
      try {
        // Ждём лесенкой: 0.6 с, 1.2 с, 2.4 с — и никогда дольше [timeout].
        // Штатный ответ приходит за 89 мс (медиана по 427 парам живой трассы),
        // p99 — 239 мс. Кадра, который не долетел, ждать нечего: первый повтор
        // должен уйти через полсекунды, а не через четыре. Но и частить слепо
        // нельзя — окно растёт, чтобы медленный ответ всё-таки успел.
        final reply = await c.future.timeout(
          retryTimeout(attempt, tries, timeout),
        );
        // Ответ пришёл — прошлая жалоба на молчание больше не про эту связь.
        if (lastError != null) {
          lastError = null;
          notifyListeners();
        }
        return reply;
      } on StateError {
        return null; // разорвали связь, дальше повторять нечего
      } on TimeoutException {
        if (identical(_waiters[cmd], c)) _waiters.remove(cmd);
        _log(
          'req  0x${cmd.toRadixString(16).padLeft(2, "0")}: '
          'нет ответа (попытка $attempt/$tries)',
        );
      }
    }
    lastError =
        'Машина не ответила на 0x${cmd.toRadixString(16).padLeft(2, "0")}';
    notifyListeners();
    return null;
  }

  Future<void> _send(Uint8List frame) async {
    _queue.add(frame);
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final gap = DateTime.now().difference(_lastWrite);
        if (gap < kMinWriteInterval) {
          await Future<void>.delayed(kMinWriteInterval - gap);
        }
        final f = _queue.removeFirst();
        _log('tx   ${_hex(f)}${_phaseTag()}');
        try {
          await _transport.write(f);
        } catch (e) {
          lastError = '$e';
          notifyListeners();
        }
        _lastWrite = DateTime.now();
      }
    } finally {
      _pumping = false;
    }
  }

  /// Фаза отправки — сколько прошло от последнего кадра телеметрии. Пустая
  /// строка, пока телеметрии не было: до неё фазы не существует, и именно там
  /// теряется большинство кадров.
  String _phaseTag() {
    final t = _lastTelemetryAt;
    if (t == null) return '';
    final ms = DateTime.now().difference(t).inMilliseconds;
    return '  ph=${(ms / 1000).toStringAsFixed(3)}';
  }

  // ---- приём ------------------------------------------------------------

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

  /// Одна строка трассы. Формат нарочно грепабельный: `k2|<сек>|<что>`.
  void _log(String s) => Trace.instance.log(s);

  void _onNotify(Uint8List chunk) {
    final frames = _decoder.push(chunk);
    // Декодер выбрасывает мусор молча, и до сих пор «байты пришли, но кадра из
    // них не вышло» выглядело в трассе ровно как «не пришло ничего». Разница
    // важная: первое — наша беда, второе — молчащая машина.
    if (frames.isEmpty) _log('rx   ЧАНК БЕЗ КАДРА ${_hex(chunk)}');
    for (final raw in frames) {
      Frame f;
      try {
        f = parseFrame(raw);
      } on FrameFormatException catch (e) {
        lastError = e.message;
        _log('rx   БИТЫЙ КАДР: ${e.message} <- ${_hex(raw)}');
        continue;
      }
      final payload = _fragments.feed(f);
      if (payload == null) continue;
      if (f.cmd != Cmd.deviceState) {
        _log(
          'rx   0x${f.cmd.toRadixString(16).padLeft(2, "0")} ${_hex(payload)}',
        );
      }
      _waiters.remove(f.cmd)?.complete(payload);
      _apply(f.cmd, payload);
    }
    notifyListeners();
  }

  void _apply(int cmd, Uint8List p) {
    try {
      switch (cmd) {
        case Cmd.deviceState:
          final s = parseDeviceStatus(p);
          final was = status;
          status = s;
          _lastTelemetryAt = _now();
          // Живой кадр — единственный признак, что машина проснулась: она сама
          // о пробуждении не сообщает, а на запросы во сне не отвечает.
          _session.fire(SessionEvent.telemetry);
          lastStateRaw = _hex(p);
          // Телеметрия идёт раз в секунду; в трассе она нужна вся — по ней
          // видно, сколько машина грела и на какой температуре сорвалась.
          _log(
            '0x00 t=${s.temperatureC}C st=${s.state.name}(${p[4]}) '
            'err=${s.error.name}(${p[5]}) bat=${s.batteryLevel}/4(${s.batteryRaw}) '
            '${s.charge.name} raw=${_hex(p)}'
            '${was != null && was.state != s.state ? '   <<< СМЕНА СОСТОЯНИЯ' : ''}',
          );
          // Ошибка живёт ровно один пакет: машина пикнула, сняла её — и в
          // телеметрии её больше нет. Запоминаем последнюю, иначе разбираться
          // потом не с чем.
          if (s.error != MachineError.none) {
            lastFault = s.error;
            lastFaultCode = s.errorCode;
            lastFaultAt = _now();
          }
          // События цикла — по смене состояния, а не по каждому кадру: пока
          // кадр пуска в пути, машина ещё повторяет прошлое состояние, и
          // принимать его за ответ нельзя.
          if (_cycleSaw != s.state) {
            _cycleSaw = s.state;
            _cycle.fire(switch (s.state) {
              final x when x.isDone => CycleEvent.machineDone,
              final x when x.isBusy => CycleEvent.machineBusy,
              _ => CycleEvent.machineIdle,
            });
          }
          if (s.error != MachineError.none) {
            _cycle.fire(CycleEvent.machineFault);
          }
          _phases.onState(s.state, now: _now());
          if (_spentAt != null) {
            if (s.state.isBusy) {
              _busySinceSpent = true;
            } else if (_busySinceSpent ||
                _now().difference(_spentAt!) > kScheduleGrace) {
              // Цикл закончился — или его не было вовсе и ждать больше нечего.
              _spentAt = null;
              _busySinceSpent = false;
              unawaited(_verifyScheduleCleared());
            }
          }
          _recompute(silent: true);
        case Cmd.getTempSetting:
          tempLimits = parseTempLimits(p);
          rangesFromDevice = true;
        case Cmd.setTempSetting:
          if (p.isNotEmpty) {
            // Машина эхом возвращает то, что приняла, — в °F.
            tempLimits = TempLimits(
              tempLimits.min,
              tempLimits.max,
              celsiusFromWire(p[0]),
            );
          }
        case Cmd.getWorkParams:
          workParams = parseWorkParams(p);
          rangesFromDevice = true;
        case Cmd.setWorkParams:
        case Cmd.reset:
          // 0x18 машина подтверждает одним байтом (01 = принято), а не эхом
          // параметров. Тогда перечитываем 0x17, чтобы знать, что внутри.
          if (p.length >= 4) {
            _applyEcho(parseWorkParamEcho(p));
          } else {
            unawaited(_refreshWorkParams());
          }
        case Cmd.getAppointment:
        case Cmd.setAppointment:
          if (p.length >= 6) {
            appointment = parseAppointment(p);
            // Машина отдаёт только hh:mm и флаг, без даты. Отсчёт ведём от
            // момента, когда узнали про взведённый будильник.
            _armedAt = appointment.enabled ? (_armedAt ?? _now()) : null;
          }
        case Cmd.deviceInfo:
          info = parseDeviceInfo(p);
        case Cmd.todayCups:
          if (p.isNotEmpty) todayCups = p[0];
        case Cmd.cups:
          history = parseCupsHistory(p);
          if (history.isNotEmpty) todayCups = history.values.first;
        case Cmd.setTime:
        case Cmd.setWorkState:
          // Голые подтверждения: машина повторяет код команды с однобайтовой
          // нагрузкой (`01` — приняла). Разбирать в них нечего, но и в
          // незапрошенные события им нельзя: мы сами их и вызвали.
          break;
        default:
          // Машина умеет присылать не только телеметрию. Такие кадры мы до
          // сих пор молча роняли — и чуть не пропустили 0x12. Больше не роняем.
          lastEventRaw = _hex(p);
          lastEventCmd = cmd;
          lastEventAt = _now();
          _log(
            '0x${cmd.toRadixString(16).padLeft(2, "0")} ${_hex(p)}'
            '   <<< НЕЗАПРОШЕННОЕ СОБЫТИЕ',
          );
      }
    } on FrameFormatException catch (e) {
      lastError = e.message;
    }
  }

  /// Пользователь прочитал ошибку — убираем её с экрана.
  void clearFault() {
    if (lastFault == MachineError.none) return;
    lastFault = MachineError.none;
    lastFaultCode = 0;
    lastFaultAt = null;
    _cycle.fire(CycleEvent.faultCleared);
    notifyListeners();
  }

  void _applyEcho(WorkParamEcho e) {
    final p = workParams;
    workParams = WorkParams(
      pressure: Range(e.pressure, p.pressure.min, p.pressure.max),
      preInfusion: Range(e.preInfusion, p.preInfusion.min, p.preInfusion.max),
      standstill: Range(e.standstill, p.standstill.min, p.standstill.max),
      extraction: Range(e.extraction, p.extraction.min, p.extraction.max),
      hasExtraction: p.hasExtraction,
    );
    final t = e.targetTemperature;
    if (t != null) {
      tempLimits = TempLimits(tempLimits.min, tempLimits.max, t);
    }
  }

  // ---- фазы -------------------------------------------------------------

  Timer? _ticker;

  /// Ближайший момент срабатывания будильника. null — будильник выключен.
  DateTime? get scheduledAt {
    final a = appointment;
    if (!a.enabled) return null;
    final from = _armedAt ?? _now();
    final today = DateTime(from.year, from.month, from.day, a.hour, a.minute);
    return today.isAfter(from) ? today : today.add(const Duration(days: 1));
  }

  /// Спросить машину, что стало с её флагом будильника после срабатывания, и
  /// свести стороны, если они разошлись.
  ///
  /// Оригинал этого не делает вовсе: он гасит переключатель у себя и уходит,
  /// а машине не говорит ничего — так что его картинка и машина после
  /// срабатывания живут каждая своей жизнью. Нам нужно, чтобы сходилось.
  Future<void> _verifyScheduleCleared() async {
    final p = await _request(cmdGetAppointment(), Cmd.getAppointment);
    if (p == null || p.length < 6) return;
    // Ответ уже разобран в _apply, так что смотрим на разобранные поля.
    if (appointment.spent) {
      _log('будильник: машина отметила «отработал» (флаг 2)');
      return;
    }
    if (!appointment.enabled) {
      _log('будильник: машина сбросила флаг сама');
      return;
    }
    _log('будильник: машина держит флаг взведённым после срабатывания — гасим');
    final off = appointment.copyWith(enabled: false);
    await _request(cmdSetAppointment(off), Cmd.setAppointment, tries: 2);
    appointment = off;
    _armedAt = null;
    notifyListeners();
  }

  void _tick() {
    _expireSchedule();
    _recompute();
    _watchSilence();
  }

  /// Заметить, что машина уснула. Пробуждение ловится по самому кадру
  /// телеметрии — см. [SessionEvent.telemetry].
  void _watchSilence() {
    if (_silent) _session.fire(SessionEvent.silenceElapsed);
  }

  /// Гасит будильник, когда его время прошло.
  ///
  /// Отдельного кадра «задача выполнена» машина не шлёт, и оригинал такого не
  /// ждёт: весь обратный отсчёт живёт у него в приложении (`redux/appoint.dart`
  /// — Timer, DateTime, ни одной отправки в BLE), и по нулю оно само пишет
  /// `isEnable = false`. Здесь ровно то же самое.
  ///
  /// Но отметка у машины всё-таки есть: после срабатывания флаг в 0x24
  /// становится 2. Просто узнать о ней можно только спросив — сама она не
  /// приходит. Спрашиваем после цикла, см. [_verifyScheduleCleared].
  void _expireSchedule() {
    final at = scheduledAt;
    if (at == null || _now().isBefore(at)) return;
    appointment = appointment.copyWith(enabled: false);
    _armedAt = null;
    _spentAt = _now();
    _busySinceSpent = false;
    _log(
      'будильник ${at.hour}:${at.minute.toString().padLeft(2, '0')} '
      'отработал — гасим переключатель',
    );
    notifyListeners();
  }

  void _recompute({bool silent = false}) {
    final s = status;
    if (s == null) return;
    final was = progress;
    progress = _phases.compute(
      state: s.state,
      error: s.error,
      currentTemperature: s.temperatureC,
      recipe: deviceRecipe,
      now: _now(),
    );
    // Смена фазы — то, ради чего экран и открыли: по этой строке в живой
    // трассе видно, что до интерфейса дошли и состояние, и секунды.
    if (was.phase != progress.phase) {
      final total = progress.total;
      _log(
        'фаза ${was.phase.name} -> ${progress.phase.name}'
        '${total == null ? '' : ' (${total.inSeconds} с)'} t=${s.temperatureC}C',
      );
    }
    if (!silent) notifyListeners();
  }

  // ---- команды ----------------------------------------------------------

  Future<void> heatAndBrew() => start(WorkMode.heatAndBrew);
  Future<void> heat() => start(WorkMode.heat);
  Future<void> brew() => start(WorkMode.brew);

  /// Пуск: уставки, затем подтверждённая команда.
  ///
  /// Весь пуск целиком живёт здесь, а не на экране, по двум причинам.
  ///
  /// Первая: ожидание должно заводиться в момент касания. Пока запись уставок
  /// стояла перед вызовом, цикл узнавал о нажатии только после неё — в живой
  /// трассе через восемь секунд, и всё это время кнопка выглядела неисправной.
  ///
  /// Вторая: пуск обязан ждать подтверждения ровно так же, как [stop]. Раньше
  /// он уходил одним кадром без ответа — и терялся молча. В трассе 22:54 видно
  /// обе половины: первый 0x02 машина проглотила, второй, точно такой же,
  /// подтвердила за 89 мс и заработала. Человек между ними жал кнопку ещё
  /// дважды, а неподтверждённые кадры копились и срабатывали потом — со
  /// стороны это выглядит как машина, которая включается сама.
  ///
  /// [apply] — уставки, которые должны лечь в машину раньше пуска.
  Future<void> start(WorkMode mode, {Recipe? apply}) async {
    _cycle.fire(CycleEvent.startRequested);
    if (apply != null) await setRecipe(apply, force: true);
    final ack = await _request(
      cmdSetWorkState(true, mode),
      Cmd.setWorkState,
      tries: 3,
      urgent: true,
    );
    if (ack == null) {
      // Отпускаем кнопку сразу, не досиживая восьмисекундный таймер цикла:
      // про этот пуск уже всё известно. Если машина всё-таки заработала, а
      // потерялось только подтверждение, ближайшая телеметрия вернёт цикл в
      // работу сама.
      lastError = 'машина не подтвердила пуск';
      _cycle.fire(CycleEvent.confirmTimeout);
      notifyListeners();
      // Спящая машина принимает кадры и молчит — но принимает не только в
      // смысле «глотает». В трассе 25.08 10:36 она запустилась от 0x02, на
      // который не ответила, и телеметрию после этого так и не прислала:
      // подписка на этой линии до неё уже не доходит. Ждать тут нечего, линию
      // надо пересобрать — на свежей она заговорит, если работает.
      if (_session.state == SessionState.dormant) unawaited(_relink());
    }
  }

  /// Стоп — единственная команда, которую нельзя терять: 0x02 машина
  /// подтверждает эхом `01`, но раньше мы его не слушали, и потерянный кадр
  /// оставлял машину греть, а человека — тянуться к кнопке на корпусе.
  /// Повтор безопасен: остановленная машина на второй стоп ничего не сделает.
  Future<void> stop() async {
    _cycle.fire(CycleEvent.stopRequested);
    final ack = await _request(
      cmdStop(),
      Cmd.setWorkState,
      tries: 3,
      urgent: true,
    );
    if (ack == null) {
      lastError = 'машина не подтвердила остановку';
      // Не подтвердила — считаем, что всё ещё работает. Ошибиться безопаснее
      // в эту сторону: показать «стоит», когда машина греет, хуже обратного.
      _cycle.fire(CycleEvent.confirmTimeout);
      notifyListeners();
    }
  }

  Future<void> setTargetTemperature(int celsius) async {
    final v = tempLimits.clamp(celsius);
    // 0x16 машина подтверждает эхом уставки, так что это полноценная транзакция.
    // Повтор безопасен: записывается то же самое число.
    await _request(
      cmdSetTargetTemperature(v),
      Cmd.setTempSetting,
      tries: 2,
      urgent: true,
    );
  }

  /// Записать рецепт: температура отдельной командой, остальное — одной.
  ///
  /// [force] — писать температуру, даже если она совпадает с известной нам.
  /// Нужно перед пуском: «известной» она может быть только по кэшу прошлого
  /// сеанса, а что на самом деле лежит в машине, мы в этот момент не знаем.
  ///
  /// Попытка при этом одна, а не две: пока запись не закончится, кадр пуска не
  /// уйдёт. На отвечающей машине это те же 30 мс, на молчащей — 1.2 с вместо
  /// 4.8. Оригинал перед пуском не пишет вовсе.
  Future<void> setRecipe(Recipe r, {bool force = false}) async {
    final p = workParams;
    final tries = force ? 1 : 2;
    final target = tempLimits.clamp(r.temperatureC);
    if (force || tempLimits.target != target) {
      await _request(
        cmdSetTargetTemperature(target),
        Cmd.setTempSetting,
        tries: tries,
        urgent: true,
      );
    }
    await _request(
      cmdSetWorkParams(
        pressure: p.pressure.clamp(r.pressure),
        preInfusionSeconds: p.preInfusion.clamp(r.preInfusionSeconds),
        standstillSeconds: p.standstill.clamp(r.standstillSeconds),
        extractionSeconds: p.hasExtraction
            ? p.extraction.clamp(r.extractionSeconds)
            : null,
      ),
      Cmd.setWorkParams,
      tries: tries,
      urgent: true,
    );
  }

  Future<void> resetToDefaults() => _exclusive(() => _send(cmdReset()));

  /// Записать будильник в машину.
  ///
  /// Отложенно и с подтверждением. Раньше каждый шаг колеса уходил отдельным
  /// кадром сразу: в живом логе за шесть секунд накрутилось двенадцать
  /// записей 0x23, машина честно приняла все промежуточные состояния (включая
  /// «нагрев и пролив» на полпути к «только проливу»), а одна запись
  /// потерялась молча — 0x23 слался через [_send], без проверки ответа.
  /// Теперь уезжает только последнее значение, и мы ждём от машины `01`.
  /// [immediate] — для отмены будильника: там ждать паузу нечего, решение
  /// принято одним нажатием, а машина тем временем идёт к своему часу.
  void setSchedule(Appointment a, {bool immediate = false}) {
    appointment = a;
    _armedAt = a.enabled ? _now() : null;
    notifyListeners();

    _scheduleDebounce?.cancel();
    _scheduleDebounce = null;
    _reconnect?.cancel();
    _reconnect = null;
    if (immediate) {
      unawaited(_pushSchedule());
      return;
    }
    _scheduleDebounce = Timer(kSettingsDebounce, () {
      _scheduleDebounce = null;
      unawaited(_pushSchedule());
    });
  }

  /// Дожать отложенную запись, не дожидаясь паузы. Вызывается, когда лист
  /// закрыли: крутить больше нечего, значение выбрано.
  Future<void> flushSchedule() async {
    if (_scheduleDebounce == null) return;
    _scheduleDebounce!.cancel();
    _scheduleDebounce = null;
    await _pushSchedule();
  }

  Future<void> _pushSchedule() async {
    if (!isConnected) return;
    await _request(
      cmdSetAppointment(appointment),
      Cmd.setAppointment,
      tries: 2,
    );
  }

  Future<void> _refreshWorkParams() async {
    await _request(cmdGetWorkParams(), Cmd.getWorkParams);
    await _request(cmdGetTempSetting(), Cmd.getTempSetting);
  }

  Future<void> refreshStatistics() async {
    await _request(cmdGetTodayCups(), Cmd.todayCups);
    await _request(cmdGetCups(), Cmd.cups);
  }

  /// Перечитать всё, что машина отдаёт по запросу.
  Future<void> refreshAll() async {
    await _refreshWorkParams();
    await _request(cmdGetAppointment(), Cmd.getAppointment);
    await _request(cmdGetDeviceInfo(), Cmd.deviceInfo);
    await refreshStatistics();
  }

  Future<void> clearStatistics() async {
    await _request(cmdGetCups(clear: true), Cmd.cups);
  }

  @override
  void dispose() {
    // Таймеры гасим синхронно, остальное — фоном.
    _ticker?.cancel();
    _ticker = null;
    _scheduleDebounce?.cancel();
    _scheduleDebounce = null;
    // Таймер переподключения переживал dispose и будил уже закрытый транспорт.
    _cancelReconnect();
    _cycle.dispose();
    unawaited(_linkSub.cancel());
    unawaited(_notifySub.cancel());
    unawaited(_scanSub.cancel());
    unawaited(_transport.dispose());
    super.dispose();
  }
}
