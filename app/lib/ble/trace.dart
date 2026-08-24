import 'dart:io';

import 'package:flutter/foundation.dart';

/// Трасса протокола в файл.
///
/// Консоль запуска доступна не всегда (приложение запускают из IDE), а разбирать
/// поведение машины надо по кадрам и по времени между ними. Поэтому каждая
/// строка дублируется в файл. Приложение в песочнице, её HOME — это
/// `~/Library/Containers/com.k2pro.k2pro/Data`, туда и пишем: снаружи путь
/// известен и читается обычным `tail`.
///
/// Пишем синхронно и по строке за раз. Асинхронный [IOSink] тут не годится:
/// два незавершённых `flush()` подряд роняют его, а следующая запись бросает
/// исключение — прямо в ту цепочку, из которой её позвали. Трасса не имеет
/// права влиять на работу приложения, поэтому любая ошибка гасит только файл.
class Trace {
  Trace._();

  static final Trace instance = Trace._();

  /// В юнит-тестах ни файловая трасса, ни диагностические прогоны не нужны.
  static bool get inTest => Platform.environment['FLUTTER_TEST'] == 'true';

  final _t0 = DateTime.now();
  RandomAccessFile? _file;
  bool _broken = false;

  /// Секунды от старта процесса — по ним видно длительности фаз.
  String get _stamp => (DateTime.now().difference(_t0).inMilliseconds / 1000)
      .toStringAsFixed(3)
      .padLeft(9);

  void _open() {
    final home = Platform.environment['HOME'];
    if (home == null) {
      _broken = true;
      return;
    }
    final f = File('$home/k2_trace.log');
    _file = f.openSync(mode: FileMode.writeOnlyAppend)
      ..writeStringSync(
        '\n===== старт ${DateTime.now().toIso8601String()} =====\n',
      )
      ..flushSync();
    debugPrint('k2: трасса пишется в ${f.path}');
  }

  /// Событие интерфейса — в ту же трассу и на те же часы, что и кадры BLE.
  ///
  /// Без этого по логу видно только половину картины: кадры есть, а что их
  /// вызвало и что после них увидел человек — нет. Разбирать «нажал, а оно не
  /// сработало» приходилось на живой машине; с этой строкой видно прямо в
  /// файле, сколько прошло от тапа до `tx` и от `rx` до перерисовки.
  void ui(String what) => log('ui   $what');

  void log(String message) {
    if (!kDebugMode || inTest) return;
    final line = 'k2|$_stamp|$message';
    debugPrint(line);
    if (_broken) return;
    try {
      if (_file == null) _open();
      _file
        ?..writeStringSync('$line\n')
        ..flushSync();
    } catch (e) {
      // Файл мог пропасть или дескриптор пережить hot reload битым — пробуем
      // открыть заново на следующей строке, и только потом сдаёмся.
      debugPrint('k2: трасса недоступна: $e');
      try {
        _file?.closeSync();
      } catch (_) {}
      if (_file == null) _broken = true;
      _file = null;
    }
  }
}
