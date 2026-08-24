# K2 Pro — минимальный клиент кофемашины

Flutter-приложение для Timeyaa PCM03 / K2 Pro поверх реконструированного
BLE-протокола (см. [`../docs/happygo-ble-protocol.md`](../docs/happygo-ble-protocol.md)).

Один экран управления + настройки. Цель — чтобы за секунду было видно
состояние машины и чтобы запуск был в один тап.

## Запуск

Симулятор машины — работает без железа, удобно для UI:

```
flutter run -d macos --dart-define=MOCK=true
```

Настоящая машина:

```
flutter run -d macos          # macOS
flutter run -d <iphone>       # iOS
```

Проверки:

```
flutter analyze
flutter test                          # 24 теста: протокол + UI
flutter test tool/screenshots --update-goldens   # перерисовать скриншоты
```

Скриншоты рендерятся в `tool/screenshots/goldens/`. Каталог лежит **вне**
`test/`, поэтому в обычный `flutter test` не попадает.

## Разрешения

Уже прописаны:

* `macos/Runner/*.entitlements` — `com.apple.security.device.bluetooth`;
* `macos/Runner/Info.plist`, `ios/Runner/Info.plist` — `NSBluetoothAlwaysUsageDescription`.

При первом запуске macOS спросит доступ к Bluetooth. Если окно не появилось,
проверьте Системные настройки → Конфиденциальность → Bluetooth.

## Архитектура

BLE смоделирован отдельно от UI — как и просили.

```
lib/
  ble/
    protocol.dart        чистый Dart: кадры, контрольная сумма, команды, парсеры
    transport.dart       интерфейс транспорта (скан / коннект / write / notify)
    ble_transport.dart   реализация на flutter_blue_plus
    mock_transport.dart  симулятор машины, отвечает настоящими кадрами
    k2_device.dart       фасад: DeviceState + команды + очередь записи
  model/
    recipe.dart          рецепт (то, что машина умеет хранить)
    brew_phase.dart      оценка фазы цикла
  store/prefs.dart       локальное: имя, °C/°F, пресеты
  ui/                    экраны и виджеты
```

`K2Device` — единственное, что видит UI:

```dart
device.status        // заряд, температура, состояние, ошибка
device.tempLimits    // min / max / уставка
device.workParams    // диапазоны параметров заваривания
device.deviceRecipe  // текущий рецепт машины
device.progress      // фаза цикла

device.heatAndBrew();
device.heat();
device.brew();
device.stop();
device.setTargetTemperature(92);
device.setRecipe(recipe);
device.setSchedule(appointment);
device.resetToDefaults();
```

Очередь записи держит паузу ≥ 20 мс между кадрами — машина принимает Write
Without Response и без паузы теряет команды.

## Что важно знать про поведение

**Фазы цикла — оценка, а не телеметрия.** Машина сообщает только общее
состояние (нагрев / экстракция / готово) и температуру. Разбивка
«предсмачивание → выдержка → экстракция» строится в
`BrewPhaseEstimator` из рецепта и момента, когда температура дошла до
уставки. Если машина отработает не по заданным секундам, таймер разойдётся с
реальностью.

**Два разных нумерования режимов.** Команда запуска `0x02` использует
`WorkMode` (0 кипяток, 1 нагрев+экстракция, 2 экстракция), а таймер
`0x23`/`0x24` — `ScheduleMode` (0 нагрев+экстракция, 1 кипяток, 2 экстракция).
В коде это два разных enum, чтобы их нельзя было перепутать.

**Имя, °C/°F и пресеты живут только в приложении.** В протоколе таких команд
нет: машина не хранит ни имени, ни единиц, ни рецептов сверх одного текущего.

**Отложенный запуск — это будильник.** Машина сама стартует выбранный режим в
заданное время суток и, если включён звук, пикает. Отсчёта «N секунд после
старта экстракции» в протоколе нет.

**Заряд.** В UI четыре деления, но в `0x00` приходит точный процент — он и
показывается цифрой рядом.

## Скриншоты

`tool/screenshots/goldens/`:

| Файл | Состояние |
|---|---|
| `01_disconnected.png` | нет подключения |
| `02_idle.png` | подключено, Sleep |
| `03_heating.png` | нагрев, 34 → 92 °C |
| `04_brewing.png` | цикл, таймлайн фаз |
| `05_scan.png` | поиск устройств |
| `06_settings.png` | настройки |
