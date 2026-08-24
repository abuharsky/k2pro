import 'package:flutter/material.dart';

import '../../ble/k2_device.dart';
import '../../l10n/app_l10n.dart';
import '../../l10n/l10n_ext.dart';
import '../../model/recipe.dart';
import '../../store/prefs.dart';
import '../theme.dart';
import 'sheet.dart';

/// Что можно сделать с машиной и что про неё известно.
///
/// Отдельного экрана настроек больше нет: параметры пролива правятся тапом по
/// времени, температура — тапом по градусам, а всё, что относится к самому
/// устройству, собрано здесь.
enum DeviceAction { rename, disconnect, choose, forget, factoryReset, language }

Future<DeviceAction?> showDeviceSheet(
  BuildContext context, {
  required K2Device device,
  required Prefs prefs,
  required Recipe recipe,
}) {
  final t = context.t;
  return showAppSheet<DeviceAction>(
    context,
    title: prefs.deviceName,
    builder: (ctx) => ListenableBuilder(
      listenable: device,
      builder: (ctx, _) {
        final info = device.info;
        final week = device.history.values.fold(0, (a, b) => a + b);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              info == null
                  ? t.notConnected
                  : '${info.model} · ${t.firmware} ${info.versionA}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: K.textDim, fontSize: 12),
            ),
            const SizedBox(height: 18),
            // Статистика — только то, что машина сама про себя рассказала.
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    value: '${device.todayCups ?? t.dash}',
                    label: t.cupsToday,
                    color: K.amber,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    value: device.history.isEmpty ? t.dash : '$week',
                    label: t.statPoursWeek,
                    color: K.btBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    value: '${recipe.temperatureC}°C',
                    label: t.temperature,
                    color: K.textBright,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    value: t.seconds(recipe.extractionSeconds),
                    label: t.pourTitle,
                    color: K.textBright,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SheetOption(
              title: t.renameDevice,
              onTap: () => Navigator.pop(ctx, DeviceAction.rename),
            ),
            SheetOption(
              title: t.language,
              trailing: languageLabel(t, prefs.localeCode),
              onTap: () => Navigator.pop(ctx, DeviceAction.language),
            ),
            SheetOption(
              title: t.otherDevice,
              onTap: () => Navigator.pop(ctx, DeviceAction.choose),
            ),
            // Список добавленных машин правится только отсюда: в поиске тап
            // по ряду всегда значит «подключись».
            if (prefs.devices.isNotEmpty)
              SheetOption(
                title: t.forgetDevice,
                onTap: () => Navigator.pop(ctx, DeviceAction.forget),
              ),
            if (device.isConnected && !device.isBusy)
              SheetOption(
                title: t.restoreDefaults,
                onTap: () => Navigator.pop(ctx, DeviceAction.factoryReset),
              ),
            if (device.isConnected)
              SheetOption(
                title: t.disconnect,
                danger: true,
                onTap: () => Navigator.pop(ctx, DeviceAction.disconnect),
              ),
          ],
        );
      },
    ),
  );
}

/// Какую машину забыть. Если добавлена одна — спрашивать нечего.
Future<SavedDevice?> pickDeviceToForget(
  BuildContext context,
  Prefs prefs,
) async {
  final list = prefs.devices;
  if (list.isEmpty) return null;
  if (list.length == 1) return list.first;

  final id = await showAppSheet<String>(
    context,
    title: context.t.forgetDevice,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in list)
          SheetOption(
            title: d.name,
            danger: true,
            onTap: () => Navigator.pop(ctx, d.id),
          ),
      ],
    ),
  );
  if (id == null) return null;
  return list.where((d) => d.id == id).firstOrNull;
}

/// Выбор языка. Возвращает true, если язык сменили.
Future<void> showLanguageSheet(BuildContext context, Prefs prefs) async {
  final t = context.t;
  final code = await showAppSheet<String>(
    context,
    title: t.language,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in <String?>[null, 'en', 'ru'])
          SheetOption(
            title: languageLabel(t, c),
            selected: prefs.localeCode == c,
            // null нельзя вернуть из Navigator.pop как значение — оно
            // неотличимо от закрытия свайпом, поэтому «системный» едет строкой.
            onTap: () => Navigator.pop(ctx, c ?? ''),
          ),
      ],
    ),
  );
  if (code == null) return;
  prefs.localeCode = code.isEmpty ? null : code;
}

/// Язык интерфейса. null — как в системе.
String languageLabel(AppL10n t, String? code) => switch (code) {
  'en' => 'English',
  'ru' => 'Русский',
  _ => t.languageSystem,
};

/// Карточка статистики в сетке 2×2.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
    decoration: ShapeDecoration(
      color: const Color(0x0AFFFFFF),
      shape: kSquircle(K.rCard),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: K.statValue.copyWith(color: color)),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: K.textDim, fontSize: 11),
        ),
      ],
    ),
  );
}
