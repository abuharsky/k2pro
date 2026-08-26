import 'dart:async';
import 'dart:typed_data';

import 'transport.dart';

/// Транспорт, у которого можно поменять начинку под ногами.
///
/// [K2Device] и [ScaleDevice] заводятся один раз, на старте, и подписываются
/// на потоки транспорта навсегда; на них же держатся редактор уставок и мост к
/// часам. Пересобирать всё это ради демо-режима незачем — поэтому меняется не
/// устройство, а то, с чем оно говорит.
///
/// Порядок подмены важен: сначала отключить устройство, потом [swap]. Иначе
/// `linkDown` от прежней начинки уводит сеанс в `reconnecting`, и таймер
/// переподключения полезет за прежним идентификатором уже в новую начинку.
/// После `disconnectRequested` сеанс в `idle`, и обрыв там ничего не значит.
class SwitchableTransport implements K2Transport {
  SwitchableTransport(this._inner) {
    _bind();
  }

  K2Transport _inner;

  /// С чем говорим прямо сейчас.
  K2Transport get inner => _inner;

  final _scanCtl = StreamController<List<DiscoveredDevice>>.broadcast();
  final _linkCtl = StreamController<LinkState>.broadcast();
  final _notifyCtl = StreamController<Uint8List>.broadcast();

  StreamSubscription<List<DiscoveredDevice>>? _scanSub;
  StreamSubscription<LinkState>? _linkSub;
  StreamSubscription<Uint8List>? _notifySub;

  void _bind() {
    _scanSub = _inner.scanResults.listen(_scanCtl.add);
    _linkSub = _inner.linkState.listen(_linkCtl.add);
    _notifySub = _inner.notifications.listen(_notifyCtl.add);
  }

  /// Отцепиться от текущей начинки.
  ///
  /// Отмену не ждём намеренно: подписка перестаёт отдавать события сразу, а
  /// возвращённое ею ожидание относится к закрытию источника — и на широковещательном
  /// потоке оно вообще может не наступить (в тестах виджетов, где часы
  /// фальшивые, ровно так и происходит).
  void _unbind() {
    unawaited(_scanSub?.cancel() ?? Future<void>.value());
    unawaited(_linkSub?.cancel() ?? Future<void>.value());
    unawaited(_notifySub?.cancel() ?? Future<void>.value());
    _scanSub = null;
    _linkSub = null;
    _notifySub = null;
  }

  /// Подменить начинку. Прежнюю не закрываем — к ней ещё вернёмся; закрыть её
  /// может только тот, кто её создал.
  Future<void> swap(K2Transport next) async {
    if (identical(next, _inner)) return;
    await _inner.disconnect();
    _unbind();
    _inner = next;
    _bind();
    // Новая начинка своё состояние по подписке не повторяет: она молчит, пока
    // с ней не заговорят. Состояние линии — единственное, что должно доехать
    // сразу, иначе выше по стеку останется висеть прежнее.
    _linkCtl.add(_inner.currentLinkState);
  }

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _scanCtl.stream;

  @override
  Stream<LinkState> get linkState => _linkCtl.stream;

  @override
  Stream<Uint8List> get notifications => _notifyCtl.stream;

  @override
  LinkState get currentLinkState => _inner.currentLinkState;

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    bool showAll = false,
  }) => _inner.startScan(timeout: timeout, showAll: showAll);

  @override
  Future<void> stopScan() => _inner.stopScan();

  @override
  Future<void> connect(String deviceId) => _inner.connect(deviceId);

  @override
  Future<void> disconnect() => _inner.disconnect();

  @override
  Future<void> write(Uint8List frame) => _inner.write(frame);

  @override
  Future<void> dispose() async {
    _unbind();
    await _inner.dispose();
    await _scanCtl.close();
    await _linkCtl.close();
    await _notifyCtl.close();
  }
}
