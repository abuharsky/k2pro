import 'dart:async';
import 'dart:typed_data';

/// Найденное устройство.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.advertisedName,
    this.rssi,
    this.known = true,
  });

  final String id;
  final String advertisedName;
  final int? rssi;

  /// Имя совпало с одним из [kNamePrefixes]; в режиме «показать все»
  /// остальные устройства тоже попадают в список, но помечены false.
  final bool known;
}

enum LinkState { disconnected, connecting, connected }

/// Транспорт, спрятанный за интерфейсом: реальный BLE или симулятор.
///
/// Всё, что выше по стеку, о flutter_blue_plus не знает.
abstract class K2Transport {
  Stream<List<DiscoveredDevice>> get scanResults;
  Stream<LinkState> get linkState;
  Stream<Uint8List> get notifications;

  LinkState get currentLinkState;

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    bool showAll = false,
  });
  Future<void> stopScan();

  Future<void> connect(String deviceId);
  Future<void> disconnect();

  /// Запись в FFF2 без подтверждения. Темп регулирует вызывающий.
  Future<void> write(Uint8List frame);

  Future<void> dispose();
}
