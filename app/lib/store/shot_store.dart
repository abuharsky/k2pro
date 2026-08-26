/// Кривые проливов на диске: по файлу на пролив.
///
/// Отдельно от [Prefs] нарочно. Настройки читаются целиком и на старте, а
/// кривая нужна ровно тогда, когда открыли конкретный пролив, — и весит она в
/// сотни раз больше. Складывать их вместе значило бы платить за графики при
/// каждом запуске приложения.
library;

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ble/trace.dart';
import '../model/shot_curve.dart';

class ShotStore {
  ShotStore({Directory? dir}) : _fixed = dir;

  final Directory? _fixed;
  Directory? _dir;

  /// Папка под кривые. В поддержке приложения, а не в документах: это кэш
  /// показаний, а не то, что человек создавал сам и захочет увидеть в файлах.
  Future<Directory?> _resolve() async {
    if (_dir != null) return _dir;
    try {
      final base = _fixed ?? await getApplicationSupportDirectory();
      final d = Directory('${base.path}/shots');
      if (!d.existsSync()) await d.create(recursive: true);
      return _dir = d;
    } catch (e) {
      // Без диска приложение обязано работать: кривых просто не будет.
      Trace.instance.log('кривые: папка недоступна — $e');
      return null;
    }
  }

  File? _file(Directory dir, String id) =>
      // Имя собираем сами из цифр: id — это отметка времени, и ничего, кроме
      // неё, в путь попасть не должно.
      RegExp(r'^\d+$').hasMatch(id) ? File('${dir.path}/$id.json') : null;

  Future<void> save(String id, ShotCurve curve) async {
    if (curve.isEmpty) return;
    final dir = await _resolve();
    if (dir == null) return;
    try {
      await _file(dir, id)?.writeAsString(curve.encode());
    } catch (e) {
      Trace.instance.log('кривые: не записалась $id — $e');
    }
  }

  Future<ShotCurve?> load(String id) async {
    final dir = await _resolve();
    if (dir == null) return null;
    try {
      final f = _file(dir, id);
      if (f == null || !f.existsSync()) return null;
      return ShotCurve.decode(await f.readAsString());
    } catch (e) {
      Trace.instance.log('кривые: не прочиталась $id — $e');
      return null;
    }
  }

  /// Убрать всё, чего нет в [keep]. Зовётся после записи новой кривой: список
  /// проливов и так уже подрезан, и лишние файлы остались бы висеть навсегда.
  Future<void> prune(Set<String> keep) async {
    final dir = await _resolve();
    if (dir == null) return;
    try {
      for (final f in dir.listSync().whereType<File>()) {
        final id = f.uri.pathSegments.last.replaceAll('.json', '');
        if (!keep.contains(id)) await f.delete();
      }
    } catch (e) {
      Trace.instance.log('кривые: уборка не удалась — $e');
    }
  }

  Future<void> clear() => prune(const {});
}
