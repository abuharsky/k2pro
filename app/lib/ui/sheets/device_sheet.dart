import 'package:flutter/material.dart';

import '../../ble/demo.dart';
import '../../ble/k2_device.dart';
import '../../ble/session.dart';
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
enum DeviceAction {
  rename,
  disconnect,
  choose,
  forget,
  factoryReset,
  language,

  /// Журнал проливов. Живёт здесь всегда: он про машину — сколько лилось и
  /// при какой температуре, — а весы лишь добавляют к записям вес.
  journal,

  /// Советы по приготовлению — разбор чашки и подстройка рецепта по вкусу.
  advice,
}

Future<DeviceAction?> showDeviceSheet(
  BuildContext context, {
  required K2Device device,
  required Prefs prefs,
  required Recipe recipe,
  Demo? demo,
}) {
  final t = context.t;
  return showAppSheet<DeviceAction>(
    context,
    title: prefs.deviceName,
    builder: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([device, prefs, demo]),
      builder: (ctx, _) {
        final info = device.info;
        final week = device.history.values.fold(0, (a, b) => a + b);
        final fullPour =
            recipe.preInfusionSeconds +
            recipe.standstillSeconds +
            recipe.extractionSeconds;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              // Подпись — про связь, а не про то, успела ли доехать анкета
              // устройства. Раньше здесь стояло `info == null`, и пока машина
              // не ответила на 0x08 — а это доли секунды после подключения, но
              // и вечность, если ответ потерялся, — шторка честно подключённой
              // машины писала «нет связи».
              switch (device.sessionState) {
                // В демо ни модели, ни прошивки нет: их называет симулятор, и
                // выдавать его ответ за анкету устройства нечестно.
                _ when demo?.on ?? false => t.demoTitle,
                SessionState.idle => t.notConnected,
                SessionState.connecting ||
                SessionState.reconnecting => t.connecting,
                SessionState.dormant => t.connected,
                _ when info == null => t.connected,
                _ => '${info.model} · ${t.firmware} ${info.firmware}',
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: K.textDim, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SheetSectionTitle(t.sectionOverview),
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
                    value:
                        '${toDisplayTemp(recipe.temperatureC, prefs.fahrenheit)}'
                        '${prefs.fahrenheit ? '°F' : '°C'}',
                    label: t.temperature,
                    color: K.textBright,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    value: t.seconds(fullPour),
                    label: t.pourTitle,
                    color: K.textBright,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SheetSectionTitle(t.sectionApp),
            // Переименовать можно только настоящую машину: имя живёт в списке
            // добавленных, а демо в него не попадает.
            if (!(demo?.on ?? false))
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
              title: t.temperatureUnit,
              trailing: prefs.fahrenheit ? '°F' : '°C',
              onTap: () => prefs.fahrenheit = !prefs.fahrenheit,
            ),
            // Разбор чашки — не про машину и не про один пролив: это
            // справочник, к которому возвращаются между чашками. Поэтому он
            // здесь, а не в разделе устройства, и открывается пустым.
            SheetOption(
              title: t.brewAdvice,
              onTap: () => Navigator.pop(ctx, DeviceAction.advice),
            ),
            SheetSwitch(
              title: t.adviceAfterShot,
              value: prefs.adviceBanner,
              onChanged: (v) => prefs.adviceBanner = v,
            ),
            SheetSectionTitle(t.sectionDevice),
            SheetOption(
              title: t.weightJournal,
              trailing: prefs.shots.isEmpty ? null : '${prefs.shots.length}',
              onTap: () => Navigator.pop(ctx, DeviceAction.journal),
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
            SheetSectionTitle(t.sectionMaintenance),
            if (device.isConnected && !device.isBusy)
              SheetOption(
                title: t.restoreDefaults,
                onTap: () => Navigator.pop(ctx, DeviceAction.factoryReset),
              ),
            // В демо это и есть выход из него: вошли через ряд в списке
            // устройств — выходим тем же «отключиться», что и с живой машины.
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
            title: d.title,
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
