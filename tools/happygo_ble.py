"""
Кодек BLE-протокола кофемашины HappyGo / Timeyaa PCM03 (и кружки M14).

Реконструирован из APK com.timeyaa.flutter_coffeecup2 1.0.6.
Подробное описание — docs/happygo-ble-protocol.md

Зависимостей нет; транспорт (bleak / gatt) подключается отдельно.
"""

from __future__ import annotations

import datetime as _dt
import enum
from dataclasses import dataclass, field

# --------------------------------------------------------------------------
# GATT
# --------------------------------------------------------------------------

SERVICE_UUID = "0000fff0-0000-1000-8000-00805f9b34fb"
WRITE_UUID = "0000fff2-0000-1000-8000-00805f9b34fb"   # write without response
NOTIFY_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"  # notify

NAME_PREFIXES_PCM = ("BL_PCM03",)
NAME_PREFIXES_MUG = ("SmartMug", "Hi-t-1")

REQUEST_MTU = 105
MIN_WRITE_INTERVAL_S = 0.020

START_TX = 0x7F   # телефон -> устройство
START_RX = 0x7E   # устройство -> телефон
HEADER_LEN = 5
MAX_FRAME_LEN = 0x1000


# --------------------------------------------------------------------------
# Команды
# --------------------------------------------------------------------------

class Pcm(enum.IntEnum):
    """Команды кофемашины PCM03."""
    GET_DEVICE_STATE = 0x00
    SET_WORK_STATE = 0x02
    SET_TIME = 0x04
    GET_CUPS = 0x06
    GET_DEVICE_INFO = 0x08
    GET_TEMP_SETTING = 0x15
    SET_TEMP_SETTING = 0x16
    GET_DEVICE_WORK_PARAM = 0x17
    SET_DEVICE_WORK_PARAM = 0x18
    GET_TODAY_CUPS = 0x19
    RESET = 0x20
    SET_APPOINTMENT = 0x23
    GET_APPOINTMENT = 0x24
    SET_UPDATE = 0xA0


class Mug(enum.IntEnum):
    """Команды кружки M14 / SmartMug."""
    GET_DEVICE_STATE = 0x00
    ACK_01 = 0x01
    SET_TEMP_SETTING = 0x02
    SET_APPOINTMENT = 0x03
    SET_TIME = 0x04
    GET_APPOINTMENT = 0x05
    GET_CUPS = 0x06
    SET_WORK_STATE = 0x07
    GET_DEVICE_INFO = 0x08
    GET_TODAY_CUPS = 0x09
    SET_UPDATE = 0xA0


class Frag(enum.IntEnum):
    NO_FRAG = 0
    FIRST = 1
    MIDDLE = 2
    LAST = 3


class PcmDeviceState(enum.IntEnum):
    STANDBY = 0
    HOT_EXTRACTIONING = 1
    HOT_EXTRACTION_COMPLETE = 2
    COLD_EXTRACTIONING = 3
    COLD_EXTRACTION_COMPLETE = 4
    HOT_WATERING = 5
    HOT_WATER_COMPLETE = 6


class PcmWorkErrorCode(enum.IntEnum):
    NORMAL = 0
    DRY_BURNING = 1
    BATTERY_OVERHEATING = 2
    HEATING_SHORT_CIRCUIT = 3
    LOW_BATTERY_HOT = 4
    LOW_BATTERY = 5


class WorkMode(enum.IntEnum):
    """Режим в команде 0x02 (setWorkState). Нумерация НЕ совпадает с PcmMode."""
    HOT_WATER = 0          # кнопка "Heating"  — нагрев воды без пролива
    HOT_EXTRACTION = 1     # кнопка "Heating&Extraction"
    EXTRACTION = 2         # кнопка "Extraction" — пролив без нагрева


class PcmMode(enum.IntEnum):
    """Режим в командах таймера 0x23/0x24. Нумерация НЕ совпадает с WorkMode."""
    HOT_EXTRACTION = 0     # кнопка "Heating&Extraction"
    HOT_WATER = 1          # кнопка "Heating"
    ONLY_EXTRACTION = 2    # кнопка "Extraction"


class BeepSound(enum.IntEnum):
    DING_DONG = 0
    DI_DI = 1
    BU_GU = 2
    BI_BI = 3


class TipMode(enum.IntEnum):
    SILENT = 0
    ALARM = 1


class ChargeState(enum.IntEnum):
    NO_CHARGING = 0
    CHARGING = 1
    CHARGING_FULL = 2


# --------------------------------------------------------------------------
# Кадр
# --------------------------------------------------------------------------

class PackFormatError(ValueError):
    pass


def checksum(start: int, len_hi: int, len_lo: int, cmd: int, payload: bytes) -> int:
    return (start + len_hi + len_lo + cmd + sum(payload)) & 0xFF


def build_frame(cmd: int, payload: bytes = b"", *, frag: int = Frag.NO_FRAG) -> bytes:
    """Собрать кадр телефон -> устройство."""
    total = HEADER_LEN + len(payload)
    if total > 0x3FFF:
        raise ValueError("payload too long")
    len_hi = ((frag & 0x03) << 6) | ((total >> 8) & 0x3F)
    len_lo = total & 0xFF
    cs = checksum(START_TX, len_hi, len_lo, cmd, payload)
    return bytes([START_TX, len_hi, len_lo, cs, cmd]) + payload


@dataclass
class Frame:
    cmd: int
    payload: bytes
    frag: Frag

    def __repr__(self) -> str:  # pragma: no cover - удобство отладки
        return f"Frame(cmd=0x{self.cmd:02X}, frag={self.frag.name}, payload={self.payload.hex(' ')})"


def parse_frame(raw: bytes) -> Frame:
    """Разобрать один принятый кадр (устройство -> телефон)."""
    if len(raw) < HEADER_LEN or raw[0] != START_RX:
        raise PackFormatError("bad start byte")
    total = ((raw[1] & 0x3F) << 8) | raw[2]
    if total != len(raw):
        raise PackFormatError(f"length mismatch: header={total} actual={len(raw)}")
    cmd = raw[4]
    payload = raw[5:]
    if raw[3] != checksum(raw[0], raw[1], raw[2], cmd, payload):
        raise PackFormatError("bad checksum")
    return Frame(cmd=cmd, payload=payload, frag=Frag(raw[1] >> 6))


class FrameDecoder:
    """Склейка notify-чанков в кадры (порт BleFrameDecoder.push)."""

    def __init__(self) -> None:
        self._buf = bytearray()

    def reset(self) -> None:
        self._buf.clear()

    def push(self, chunk: bytes) -> list[bytes]:
        self._buf += chunk
        out: list[bytes] = []
        while self._buf:
            idx = self._buf.find(START_RX)
            if idx < 0:
                self._buf.clear()
                break
            if idx > 0:
                del self._buf[:idx]
                continue
            if len(self._buf) < 3:
                break
            total = ((self._buf[1] & 0x3F) << 8) | self._buf[2]
            if total < HEADER_LEN or total > MAX_FRAME_LEN:
                del self._buf[:1]
                continue
            if len(self._buf) < total:
                break
            out.append(bytes(self._buf[:total]))
            del self._buf[:total]
        return out


class FragmentAssembler:
    """Сборка фрагментированных ответов (cmd 0x06 и 0x08)."""

    def __init__(self) -> None:
        self._buf = bytearray()

    def feed(self, frame: Frame) -> bytes | None:
        """Вернуть собранную нагрузку, когда она готова, иначе None."""
        if frame.frag is Frag.NO_FRAG:
            return frame.payload
        if frame.frag is Frag.FIRST:
            self._buf.clear()
        self._buf += frame.payload
        if frame.frag is Frag.LAST:
            data = bytes(self._buf)
            self._buf.clear()
            return data
        return None


# --------------------------------------------------------------------------
# Конструкторы команд PCM03
# --------------------------------------------------------------------------

def pcm_get_device_state() -> bytes:
    return build_frame(Pcm.GET_DEVICE_STATE)


def pcm_get_device_info() -> bytes:
    return build_frame(Pcm.GET_DEVICE_INFO)


def pcm_get_temp_setting() -> bytes:
    return build_frame(Pcm.GET_TEMP_SETTING)


def pcm_set_temp_setting(celsius: int) -> bytes:
    return build_frame(Pcm.SET_TEMP_SETTING, bytes([celsius & 0xFF]))


def pcm_get_device_work_param() -> bytes:
    return build_frame(Pcm.GET_DEVICE_WORK_PARAM)


def pcm_set_device_work_param(
    pressure: int,
    soaking_time: int,
    standstill_time: int,
    extraction_time: int | None = None,
) -> bytes:
    """Команда 0x18.

    Порядок байт: [давление, замачивание, выстаивание, экстракция].
    extraction_time=None -> короткий 3-байтовый вариант; оригинал использует его,
    когда устройство не прислало параметры времени экстракции в ответе 0x17
    (флаг PcmDevice.field_6f). Отбрасывается именно последний байт.
    """
    body = bytes([pressure & 0xFF, soaking_time & 0xFF, standstill_time & 0xFF])
    if extraction_time is not None:
        body += bytes([extraction_time & 0xFF])
    return build_frame(Pcm.SET_DEVICE_WORK_PARAM, body)


def parse_work_param_echo(payload: bytes) -> dict[str, int]:
    """Ответ на 0x18 (4 байта) или на 0x20 (5 байт) — форматы разные."""
    if len(payload) >= 5:
        return {
            "pressure": payload[0],
            "soaking_time": payload[1],
            "standstill_time": payload[2],
            "preset_temperature": payload[3],
            "extraction_time": payload[4],
        }
    if len(payload) >= 4:
        return {
            "pressure": payload[0],
            "soaking_time": payload[1],
            "standstill_time": payload[2],
            "extraction_time": payload[3],
        }
    raise PackFormatError("work param echo too short")


def pcm_set_work_state(start: bool, mode: WorkMode | int = WorkMode.HOT_EXTRACTION) -> bytes:
    """Команда 0x02. Внимание: здесь WorkMode, а не PcmMode.

    Порядок байтов — [mode, start], проверено на живой машине: со старым
    порядком [start, mode] режим "только нагрев" (01 00) читался как стоп,
    а "только пролив" (01 02) — как пуск нагрева с проливом.
    """
    return build_frame(Pcm.SET_WORK_STATE, bytes([int(mode) & 0xFF, 1 if start else 0]))


def pcm_reset() -> bytes:
    return build_frame(Pcm.RESET)


def pcm_get_today_cups() -> bytes:
    return build_frame(Pcm.GET_TODAY_CUPS)


def pcm_get_cups(clear: bool = False) -> bytes:
    return build_frame(Pcm.GET_CUPS, bytes([1 if clear else 0]))


def pcm_get_appointment() -> bytes:
    return build_frame(Pcm.GET_APPOINTMENT)


def pcm_set_appointment(
    mode: PcmMode | int,
    hour: int,
    minute: int,
    tip_mode: TipMode | int = TipMode.SILENT,
    beep_index: BeepSound | int = BeepSound.DING_DONG,
    enable: bool = True,
) -> bytes:
    body = bytes([int(mode) & 0xFF, hour & 0xFF, minute & 0xFF,
                  int(tip_mode) & 0xFF, int(beep_index) & 0xFF, 1 if enable else 0])
    return build_frame(Pcm.SET_APPOINTMENT, body)


def encode_time_payload(now: _dt.datetime | None = None) -> bytes:
    """7-байтовая нагрузка команды 0x04 (одинаково для PCM03 и M14)."""
    now = now or _dt.datetime.now()
    return bytes([
        now.isoweekday(),          # Dart DateTime.weekday: 1 = Mon .. 7 = Sun
        now.month,
        now.day,
        (now.year - 2020) & 0xFF,
        now.hour,
        now.minute,
        now.second,
    ])


def pcm_set_time(now: _dt.datetime | None = None) -> bytes:
    return build_frame(Pcm.SET_TIME, encode_time_payload(now))


def pcm_enter_ota() -> bytes:
    return build_frame(Pcm.SET_UPDATE)


# --------------------------------------------------------------------------
# Парсеры ответов PCM03
# --------------------------------------------------------------------------

def _battery_level(percent: int) -> int:
    if percent == 0:
        return 0
    if 1 <= percent < 25:
        return 1
    if 25 <= percent <= 50:
        return 2
    if 50 <= percent <= 75:
        return 3
    return 4


@dataclass
class DeviceStatus:
    raw0: int
    battery_percent: int
    battery_level: int
    charge_state: ChargeState
    charging_full: bool
    flag_0x20: bool
    temperature_c: int
    state: PcmDeviceState | int
    error: PcmWorkErrorCode | int


def parse_device_state(payload: bytes) -> DeviceStatus:
    """Ответ / push команды 0x00 (6 байт)."""
    if len(payload) < 6:
        raise PackFormatError("device state payload too short")
    pct = payload[1] & 0x7F
    flags = payload[2]
    charging = bool(flags & 0x80)
    full = bool(flags & 0x40)
    if full:
        charge = ChargeState.CHARGING_FULL
    elif charging:
        charge = ChargeState.CHARGING
    else:
        charge = ChargeState.NO_CHARGING
    try:
        state = PcmDeviceState(payload[4])
    except ValueError:
        state = payload[4]
    try:
        err = PcmWorkErrorCode(payload[5])
    except ValueError:
        err = payload[5]
    return DeviceStatus(
        raw0=payload[0],
        battery_percent=pct,
        battery_level=_battery_level(pct),
        charge_state=charge,
        charging_full=full,
        flag_0x20=bool(flags & 0x20),
        temperature_c=payload[3],
        state=state,
        error=err,
    )


@dataclass
class Range:
    value: int
    min: int
    max: int


@dataclass
class WorkParams:
    pressure: Range
    soaking_time: Range
    standstill_time: Range
    extraction_time: Range


def parse_work_params(payload: bytes) -> WorkParams:
    """Ответ команды 0x17 (10 или 12 байт)."""
    if len(payload) < 10:
        raise PackFormatError("work param payload too short")
    p_min, p_max = (payload[10], payload[11]) if len(payload) >= 12 else (0, 0)
    return WorkParams(
        pressure=Range(payload[0], p_min, p_max),
        soaking_time=Range(payload[1], payload[2], payload[3]),
        standstill_time=Range(payload[4], payload[5], payload[6]),
        extraction_time=Range(payload[7], payload[8], payload[9]),
    )


@dataclass
class TempSetting:
    min_c: int
    max_c: int
    preset_c: int


def parse_temp_setting(payload: bytes) -> TempSetting:
    """Ответ команды 0x15 (3 байта)."""
    if len(payload) < 3:
        raise PackFormatError("temp setting payload too short")
    return TempSetting(min_c=payload[0], max_c=payload[1], preset_c=payload[2])


@dataclass
class Appointment:
    mode: PcmMode | int
    hour: int
    minute: int
    tip_mode: TipMode | int
    beep_index: int
    enabled: bool


def parse_appointment(payload: bytes) -> Appointment:
    """Ответ команды 0x24 (6 байт)."""
    if len(payload) < 6:
        raise PackFormatError("appointment payload too short")
    try:
        mode = PcmMode(payload[0])
    except ValueError:
        mode = payload[0]
    try:
        tip = TipMode(payload[3])
    except ValueError:
        tip = payload[3]
    return Appointment(mode=mode, hour=payload[1], minute=payload[2],
                       tip_mode=tip, beep_index=payload[4],
                       enabled=payload[5] == 1)


def parse_cups_history(payload: bytes, today: _dt.date | None = None) -> list[tuple[_dt.date, int]]:
    """Собранная нагрузка команды 0x06: payload[2] — сегодня, [3] — вчера, ..."""
    if len(payload) < 3:
        raise PackFormatError("cups payload too short")
    today = today or _dt.date.today()
    return [(today - _dt.timedelta(days=i - 2), payload[i]) for i in range(2, len(payload))]


@dataclass
class DeviceInfo:
    version_a: str
    version_b: str
    model: str
    trailing: bytes = field(default=b"", repr=False)


def parse_device_info(payload: bytes) -> DeviceInfo:
    """Собранная нагрузка команды 0x08: [reserved][len][ascii] x3."""
    if len(payload) < 2:
        raise PackFormatError("device info payload too short")
    strings: list[str] = []
    lengths: list[int] = []
    i = 1
    for _ in range(3):
        if i >= len(payload):
            break
        n = payload[i]
        lengths.append(n)
        strings.append(payload[i + 1:i + 1 + n].decode("ascii", "replace"))
        i += 1 + n
    while len(strings) < 3:
        strings.append("")
        lengths.append(0)
    model = strings[2]
    if lengths[2] == 0:
        model = "PCM03"
    elif lengths[2] == 1:
        model = "PCM03S"
    return DeviceInfo(version_a=strings[0], version_b=strings[1],
                      model=model, trailing=payload[i:])


# --------------------------------------------------------------------------
# OTA
# --------------------------------------------------------------------------

OTA_START = 0x08
OTA_BLOCK_SIZE = 512


class Ota(enum.IntEnum):
    START_TRANSFER_INFO = 0xC2
    START_TRANSFER_END_CHECK = 0xC4
    START_TRANSFER_END = 0xC5
    START_UPDATE_PREPARE = 0xC7
    ONE_PACKET_DATA_TRANSFER_CHECK = 0xC8
    START_UPDATE_CHECK = 0xCC
    GET_DEVICE_PARAMS = 0xCD
    DEVICE_ERROR = 0xE1


def build_ota_frame(cmd: int, payload: bytes = b"") -> bytes:
    return bytes([OTA_START, cmd]) + payload


def parse_ota_frame(raw: bytes) -> Frame:
    if len(raw) < 2 or raw[0] != OTA_START:
        raise PackFormatError("bad OTA start byte")
    return Frame(cmd=raw[1], payload=raw[2:], frag=Frag.NO_FRAG)


def ota_start_update_check() -> bytes:
    return build_ota_frame(Ota.START_UPDATE_CHECK)


def ota_get_device_params() -> bytes:
    return build_ota_frame(Ota.GET_DEVICE_PARAMS)


def ota_start_transfer_end_check() -> bytes:
    return build_ota_frame(Ota.START_TRANSFER_END_CHECK)


def ota_start_update_prepare(total_size: int, file_crc: int, sub_packet_param: int) -> bytes:
    body = total_size.to_bytes(4, "little") + file_crc.to_bytes(4, "little") \
        + bytes([sub_packet_param & 0xFF])
    return build_ota_frame(Ota.START_UPDATE_PREPARE, body)


def ota_start_transfer_info(value16: int, extra: bytes = b"") -> bytes:
    return build_ota_frame(Ota.START_TRANSFER_INFO, value16.to_bytes(2, "little") + extra)


def ota_one_packet_check(value32: int, extra: bytes = b"") -> bytes:
    return build_ota_frame(Ota.ONE_PACKET_DATA_TRANSFER_CHECK,
                           value32.to_bytes(4, "little") + extra)


def ota_start_transfer_end(flag: bool) -> bytes:
    return build_ota_frame(Ota.START_TRANSFER_END,
                           bytes([1 if flag else 0]) + b"Timeyaa" + b"\x00")


_CRC_TABLE: list[int] = []


def _build_crc_table() -> list[int]:
    table = []
    for i in range(256):
        c = i
        for _ in range(8):
            c = (c >> 1) ^ 0xEDB88320 if c & 1 else c >> 1
        table.append(c)
    return table


def get_crc(data: bytes) -> int:
    """CRC-32 (poly 0xEDB88320, init 0xFFFFFFFF, БЕЗ финальной инверсии)."""
    global _CRC_TABLE
    if not _CRC_TABLE:
        _CRC_TABLE = _build_crc_table()
    crc = 0xFFFFFFFF
    for b in data:
        crc = _CRC_TABLE[(crc ^ b) & 0xFF] ^ (crc >> 8)
    return crc & 0xFFFFFFFF


# --------------------------------------------------------------------------

if __name__ == "__main__":
    import zlib

    # Кадры из §4 документации.
    assert build_frame(Pcm.GET_DEVICE_STATE) == bytes.fromhex("7f0005 84 00".replace(" ", ""))
    assert pcm_set_work_state(True, WorkMode.HOT_EXTRACTION) == bytes.fromhex("7f00078a020101")
    # 0x02 использует WorkMode, 0x23/0x24 — PcmMode; нумерация разная
    assert WorkMode.HOT_WATER == 0 and PcmMode.HOT_WATER == 1
    assert build_frame(Pcm.GET_DEVICE_INFO).hex(" ") == "7f 00 05 8c 08"

    # Приёмный автомат: разрезаем ответ пополам и склеиваем обратно.
    body = bytes([0x00, 0x64, 0x80, 0x5A, 0x01, 0x00])
    lo = HEADER_LEN + len(body)
    cs = checksum(START_RX, 0x00, lo, Pcm.GET_DEVICE_STATE, body)
    rx = bytes([START_RX, 0x00, lo, cs, Pcm.GET_DEVICE_STATE]) + body
    dec = FrameDecoder()
    assert dec.push(b"\xaa\xbb" + rx[:4]) == []
    frames = dec.push(rx[4:])
    assert frames == [rx]
    st = parse_device_state(parse_frame(frames[0]).payload)
    assert st.battery_percent == 100 and st.temperature_c == 0x5A
    assert st.state is PcmDeviceState.HOT_EXTRACTIONING
    assert st.charge_state is ChargeState.CHARGING

    assert get_crc(b"123456789") == (~zlib.crc32(b"123456789")) & 0xFFFFFFFF

    # 0x18: порядок [давление, замачивание, выстаивание, экстракция]
    assert pcm_set_device_work_param(2, 30, 15, 60)[4:] == bytes([0x18, 2, 30, 15, 60])
    assert pcm_set_device_work_param(2, 30, 15)[4:] == bytes([0x18, 2, 30, 15])
    assert parse_work_param_echo(bytes([2, 30, 15, 60]))["extraction_time"] == 60
    assert parse_work_param_echo(bytes([2, 30, 15, 92, 60]))["preset_temperature"] == 92

    print("self-check OK")
    print("state :", build_frame(Pcm.GET_DEVICE_STATE).hex(" "))
    print("start :", pcm_set_work_state(True, PcmMode.HOT_EXTRACTION).hex(" "))
    print("stop  :", pcm_set_work_state(False, PcmMode.HOT_EXTRACTION).hex(" "))
    print("time  :", pcm_set_time(_dt.datetime(2026, 8, 23, 9, 41, 5)).hex(" "))
