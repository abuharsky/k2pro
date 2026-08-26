/// Профили устройств, с которыми приложение умеет говорить.
///
/// Вынесены отдельно от транспорта: сам транспорт про кофе ничего не знает,
/// а протоколы про транспорт — тем более.
library;

import 'protocol.dart';
import 'scale/timemore_dot.dart';
import 'transport.dart';

/// Кофемашина K2 Pro (Timeyaa PCM03).
final BleProfile kMachineProfile = BleProfile(
  kind: DeviceKind.machine,
  serviceUuid: kServiceUuid,
  notifyUuid: kNotifyUuid,
  writeUuid: kWriteUuid,
  matches: (n) => kNamePrefixes.any(n.startsWith),
  requestMtu: kRequestMtu,
);

/// Весы Timemore Black Mirror DOT.
///
/// MTU не трогаем: кадр весов — шестнадцать байт в худшем случае, влезает в
/// любой умолчательный.
final BleProfile kScaleProfile = BleProfile(
  kind: DeviceKind.scale,
  serviceUuid: kScaleServiceUuid,
  notifyUuid: kScaleNotifyUuid,
  writeUuid: kScaleWriteUuid,
  matches: isScaleName,
);

/// Чем себя называет устройство с таким именем.
DeviceKind kindOfName(String advertisedName) {
  if (kMachineProfile.matches(advertisedName)) return DeviceKind.machine;
  if (kScaleProfile.matches(advertisedName)) return DeviceKind.scale;
  return DeviceKind.other;
}
