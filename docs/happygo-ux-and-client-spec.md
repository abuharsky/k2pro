# HappyGo — функциональность, UI/UX и минимальный клиент

Разбор того, что приложение реально даёт пользователю, как экраны ложатся на
BLE-протокол и что из этого нужно повторить в своём клиенте.

Протокол описан отдельно: [`happygo-ble-protocol.md`](happygo-ble-protocol.md).

Источники: локализация `messages_en.dart` (274 строки), таблица маршрутов
`routers/routes.dart`, виджеты `widget/pcm_*.dart` и страницы `pages/pcm/*`,
вызовы методов `PcmDevice` из UI.

---

## 1. Что это за приложение

Бренд **CERA+**, приложение **HappyGo**. Обслуживает два устройства:

* **PCM03** — портативная кофемашина (`BL_PCM03…`), основной сценарий;
* **M14 / SmartMug** — умная кружка (`SmartMug…`, `Hi-t-1…`), другой набор экранов.

Ниже — только PCM03.

Половина приложения к устройству отношения не имеет: аккаунт (логин, регистрация,
смена пароля), обратная связь, описание продукта, юридические документы, экспорт
истории в Excel. Для своего клиента это всё не нужно.

## 2. Карта экранов

```
/                        welcome — соглашение о приватности, инициализация
/main                    список устройств: скан, подключение, удаление
  /baseConnect           обёртка «подключаюсь…»
  ├── главный экран PCM03 (widget/pcm_main_screen.dart)
  │     ├── /pcmDeviceSet         Person Setting — параметры заваривания
  │     ├── /pcmReserve           Time Preset — отложенный запуск
  │     ├── /pcmHistory           Health Management — статистика чашек
  │     ├── /pcmProductDescription  (webview)
  │     ├── /email                обратная связь
  │     ├── /deviceEdit           переименование (локально)
  │     └── /setting              настройки приложения
  │           ├── /language
  │           ├── /deviceinfo → /deviceVersion
  │           ├── /protocolPrivacy
  │           └── /device/device_upgrade   OTA
  └── /login /registe /change_password /userCenter /forgetPassword
```

`/history`, `/reserve`, `/tempList`, `/tempListSet`, `/device` — экраны кружки M14.

## 3. Главный экран (`pcm_main_screen.dart`)

Что на нём:

* **круговой слайдер** (`pcm_circular_slider.dart`) — крупная цифра текущей
  температуры, вокруг — регулировка уставки. Подписи: `presetTemperature`,
  `standby`, `notConnect`;
* **статус подключения** сверху (`Connected` / `Connecting` / `Disconnected`);
* **кнопка Start** → всплывает меню из трёх режимов;
* когда устройство работает — кнопка превращается в **Stop**;
* иконки: заряд батареи (5 уровней), значок зарядки;
* нижнее меню: Time Preset, Health Management, More Settings, Firmware Upgrade
  (с бейджем `newVersionAvailable`).

### Три режима работы

Одни и те же три функции, но в UI и в двух командах протокола пронумерованы
**по-разному** — это главная ловушка при написании клиента.

| Кнопка (en) | Диалог подтверждения | `WorkMode` в `0x02` | `PcmMode` в `0x23`/`0x24` |
|---|---|---|---|
| Heating&Extraction | «Does it start heating & extraction?» | **1** `hotExtraction` | **0** `hotExtraction` |
| Heating | «Does it start heating?» | **0** `hotWater` | **1** `hotWater` |
| Extraction | «Does it start direct extraction?» | **2** `extraction` | **2** `onlyExtraction` |

«Heating» — это нагрев воды без пролива (кипяток), «Extraction» — пролив без
нагрева (холодная экстракция).

Перед запуском режима, требующего нагрева (`hotExtraction` или `hotWater`),
приложение при низком заряде показывает `lowBatteryHeatingWarning` —
«батареи может не хватить на полный нагрев, но экстракция горячей водой
доступна».

### Логика «занято»

`PcmDevice.isWorking` = состояние **не** входит в
`{standby, hotExtractionComplete, coldExtractionComplete, hotWaterComplete}`.
Пока `isWorking`, приложение блокирует изменение уставки и параметров и
показывает `markingTip` / `deviceIsWorkTip` («устройство работает, попробуйте
позже»). Остановка требует подтверждения (`deviceWorkStopTip`).

### Обновление UI

Нотификации `0x00` прилетают часто, но экран перерисовывается **не чаще раза в
800 мс** (`_onGetDeviceState` сравнивает метку времени с `field_9f`).

## 4. Person Setting — параметры заваривания (`/pcmDeviceSet`)

Четыре регулятора + кнопка Save:

| Контрол в UI | Единицы / шаг | Откуда границы |
|---|---|---|
| `preSoakTime` «Pre-soak Time (S)» | сек., шаг 1 | `soakingTime.min/max` из `0x17` |
| `standstillTime` «Standstill Time (S)» | сек., шаг 1 | `standstillTime.min/max` из `0x17` |
| `extractionTime` «Extraction Time (S)» | сек., **шаг 10** | `extractionTime.min/max` из `0x17` |
| `extractionPressure` «Flow Speed» | шаг 1 | `pressure.min/max`, при `max < min` → `0..2` |

`Low` / `Medium` / `High` — это не три градации, а подпись под ползунком:
приложение делит диапазон `[min..max]` на трети и показывает, в какую попало
текущее значение. Количество делений задаёт устройство ответом `0x17`.

Плюс подсказка `referenceValue` / `altitude` (рекомендуемые значения в
зависимости от высоты над уровнем моря) — чисто информационная,
в протоколе её нет.

Отдельная кнопка **Restore Default Settings** (`resetSet`) с подтверждением →
команда `0x20`.

Save (`_DeviceSetPageState._save`) делает две вещи по очереди:

1. если уставка температуры менялась и устройство не в состоянии
   `standby`/`*Complete` — отправляет `0x16`, ждёт ответ, сверяет эхо
   (иначе в лог `presetTemperature not updated`);
2. отправляет `0x18` с четырьмя (или тремя) байтами параметров, сверяет эхо
   (`deviceWorkParam not updated`).

## 5. Time Preset — отложенный запуск (`/pcmReserve`)

Экран собирает `DeviceAppoint` и шлёт его одной командой `0x23`:

* **Preset Model** — режим: Heating&Extraction / Heating / Extraction → `PcmMode` 0/1/2;
* **Preset Time** — часы и минуты;
* **Reminder Mode** — `Silent mode` (0) / `Alarm mode` (1) → `TipMode`;
* **Beep Settings** — мелодия, порядок в списке: `dingDong` 0, `didi` 1,
  `bugu` 2, `bibi` 3 (соответствуют `assets/audio/*.mp3`);
* кнопки **Start** / **Stop** → тот же `0x23` с последним байтом 1 или 0.

UX-деталь: если выбранное время совпадает с текущим до минуты, приложение
показывает «предустановка будет выполнена завтра» — на уровне протокола это
никак не кодируется, устройству уходят те же час и минута.

Отмена активного таймера подтверждается диалогом `closeReserveTip`.

## 6. Health Management — статистика (`/pcmHistory`)

* вкладки **Week / Month / Year**, счётчик `totalCups`;
* график/список по дням;
* **Clear Records** — `0x06` с байтом `1`, с предупреждением, что данные
  не восстановить;
* **Export** — выгрузка в `.xlsx` и «поделиться» (колонки: №, Device ID,
  Date, Cups). Полностью локальная функция.

Важно: приложение хранит историю в своей SQLite-базе. Устройство отдаёт
только **посуточные счётчики за последние N дней** (`0x06`) и **счётчик за
сегодня** (`0x19`); недели/месяцы/годы считает приложение.

## 7. Что делается локально, а не по BLE

Чтобы не искать эти команды в протоколе — их там нет:

* **имя устройства** (`/deviceEdit`) — пишется только в локальную SQLite,
  проверка `nameIsExit` тоже локальная;
* **°C / °F** — флаг `TemperatureUnitIsF` в SharedPreferences; протокол всегда
  в градусах Цельсия, пересчёт `F = round(C * 1.8 + 32)` делает приложение;
* **вся история** сверх посуточных счётчиков, экспорт, графики;
* **аккаунт, обратная связь, описание продукта, соглашения** — HTTP к
  `service-*.apigw.tencentcs.com` и `cdn.timeyaa.com`;
* **проверка новой прошивки** — HTTP; по BLE идёт только сама заливка.

## 8. Матрица «экран → команда»

| Экран / действие | Команда | Направление |
|---|---|---|
| подключение (авто) | `0x04` setTime | → |
| подключение (авто) | `0x15`, `0x17`, `0x24`, `0x08`, `0x06` | ↔ |
| главный экран, телеметрия | `0x00` | ← push |
| Start / Stop | `0x02` | → |
| круговой слайдер температуры | `0x16` | → |
| Person Setting → Save | `0x16` (при необходимости) + `0x18` | → |
| Person Setting → Restore Default | `0x20` | → |
| Time Preset → Confirm / Start / Stop | `0x23` | → |
| Time Preset (открытие) | `0x24` | ↔ |
| Health Management (открытие) | `0x06`, `0x19` | ↔ |
| Health Management → Clear Records | `0x06` с `[1]` | → |
| Firmware Upgrade | `0xA0`, далее OTA-протокол | → |
| Device Information | из кеша ответа `0x08` | — |
| переименование, °C/°F, экспорт | — | локально |

## 9. Минимальный клиент

### 9.1 Что реализовать

Обязательный минимум, чтобы управлять машиной:

1. скан + фильтр по имени `BL_PCM03`;
2. connect → discoverServices → notify на `FFF1`;
3. кодек кадров (`0x7F`/`0x7E`, длина, контрольная сумма);
4. очередь записи «одна команда за раз, пауза ≥ 20 мс»;
5. обработка push-нотификаций `0x00`;
6. команды `0x02` (пуск/стоп) и `0x16` (уставка температуры).

Всё остальное — по желанию: `0x17`/`0x18` (параметры заваривания),
`0x23`/`0x24` (таймер), `0x06`/`0x19` (счётчики), `0x08` (версии), OTA.

### 9.2 Порядок после подключения

Можно упростить оригинал: обязателен только `setTime`, остальное — чтение
начального состояния.

```
setTime(0x04)                      -> синхронизировать часы устройства
getTempSetting(0x15)               -> min/max/уставка температуры
getDeviceWorkParam(0x17)           -> границы параметров заваривания
getAppointment(0x24)               -> состояние таймера          [опционально]
getDeviceInfo(0x08)                -> версии и модель            [опционально]
```

Между командами держать паузу ~40 мс, как в оригинале. Дальше просто слушать
`0x00`.

### 9.3 Модель состояния

Из `0x00` (6 байт) получаете всё, что нужно экрану:

```
батарея %      = b[1] & 0x7F
зарядка        = b[2] & 0x80,  заряжено = b[2] & 0x40
температура °C = b[3]
состояние      = b[4]  -> standby | hot/coldExtractioning | hotWatering | *Complete
ошибка         = b[5]  -> normal | dryBurning | batteryOverheating |
                          heatingShortCircuit | lowBatteryHot | lowBattery
```

Кнопка Start активна, когда `состояние ∈ {standby, *Complete}`; иначе показываем
Stop. Уставка температуры и параметры заваривания редактируются только в этом же
состоянии.

### 9.4 Пуск и остановка

```
пуск   -> 0x02  [1, WorkMode]      WorkMode: 0 кипяток, 1 нагрев+экстракция, 2 экстракция
стоп   -> 0x02  [0, 0]
```

Устройство подтверждает той же командой; фактическое состояние всё равно
приедет в ближайшем `0x00`, так что можно на подтверждение не завязываться.

### 9.5 Грабли

* **Два разных нумерования режимов.** `0x02` использует `WorkMode`,
  `0x23`/`0x24` — `PcmMode`. Перепутать легко, поведение будет неверным молча.
* **Write Without Response.** Ответа на уровне ATT нет, поэтому темп держите
  сами: очередь + пауза ≥ 20 мс. Без паузы устройство теряет кадры.
* **Фрагментация только у устройства** и только для `0x06` и `0x08`.
  Свои кадры всегда шлите с `frag = 0`.
* **Ответы `0x18` и `0x20` разного формата** — у `reset` пять байт, температура
  вставлена в середину.
* **Время экстракции идёт с шагом 10**, остальные параметры — с шагом 1.
* **Контрольная сумма считается по трём байтам заголовка, команде и
  нагрузке**, но не по себе самой.
* **Длина в кадре — полная**, включая заголовок (`5 + len(payload)`),
  а не длина нагрузки.
* **Не опрашивайте состояние поллингом** — устройство само шлёт `0x00`.
  Оригинал даже прореживает перерисовку до 800 мс.

### 9.6 Каркас

```python
from tools.happygo_ble import *          # см. репозиторий

dec = FrameDecoder()
frags = FragmentAssembler()

def on_notify(_, chunk: bytes):
    for raw in dec.push(chunk):
        f = parse_frame(raw)
        payload = frags.feed(f)          # None, пока фрагменты не собраны
        if payload is None:
            continue
        if f.cmd == Pcm.GET_DEVICE_STATE:
            ui.update(parse_device_state(payload))
        elif f.cmd == Pcm.GET_TEMP_SETTING:
            ui.limits(parse_temp_setting(payload))
        elif f.cmd == Pcm.GET_DEVICE_WORK_PARAM:
            ui.params(parse_work_params(payload))

await client.start_notify(NOTIFY_UUID, on_notify)
await write(pcm_set_time())
await write(pcm_get_temp_setting())
await write(pcm_get_device_work_param())
# пуск: нагрев + экстракция
await write(pcm_set_work_state(True, 1))
```

где `write` — обёртка, которая сериализует запись и выдерживает паузу:

```python
async def write(frame: bytes):
    async with lock:
        await asyncio.sleep(max(0, MIN_WRITE_INTERVAL_S - (now() - last_write)))
        await client.write_gatt_char(WRITE_UUID, frame, response=False)
        last_write = now()
```
