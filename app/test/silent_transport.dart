import 'dart:async';
import 'dart:typed_data';

import 'package:k2pro/ble/transport.dart';

/// Транспорт вместо живого BLE: эфира в тесте нет, а вернуться после демо
/// нужно ровно к тому, что стояло до него.
class SilentTransport implements K2Transport {
  final _scan = StreamController<List<DiscoveredDevice>>.broadcast();
  final _link = StreamController<LinkState>.broadcast();
  final _notify = StreamController<Uint8List>.broadcast();

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _scan.stream;
  @override
  Stream<LinkState> get linkState => _link.stream;
  @override
  Stream<Uint8List> get notifications => _notify.stream;
  @override
  LinkState get currentLinkState => LinkState.disconnected;

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    bool showAll = false,
  }) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> write(Uint8List frame) async {}

  @override
  Future<void> dispose() async {
    await _scan.close();
    await _link.close();
    await _notify.close();
  }
}
