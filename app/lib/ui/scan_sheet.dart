import 'package:flutter/material.dart';

import '../ble/demo.dart';
import '../ble/k2_device.dart';
import '../ble/scale/scale_device.dart';
import '../ble/transport.dart';
import '../l10n/l10n_ext.dart';
import '../store/prefs.dart';
import 'sheets/sheet.dart';
import 'theme.dart';
import 'widgets/k_icons.dart';
import 'widgets/spinner.dart';

/// Модальный лист подключения. Возвращает id подключённого устройства.
///
/// Сверху — машины, которые уже добавляли: они остаются в списке, даже когда
/// их нет в эфире, и убрать их можно только из настроек. Ниже — то, что нашёл
/// поиск. Тап по ряду всегда значит одно и то же: подключиться.
///
/// В самом низу, отдельно от всего, — демо. Оно живёт именно здесь, а не в
/// настройках: демо это не параметр приложения, а ответ на вопрос «к чему
/// подключиться», просто понарошку. Ряд у него приглушённый и последний:
/// функция второстепенная, перетягивать внимание с настоящих машин ей нечего.
Future<String?> showScanSheet(
  BuildContext context,
  K2Device device,
  ScaleDevice scale,
  Prefs prefs, {
  Demo? demo,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: K.overlay,
    isScrollControlled: true,
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (_) =>
        _ScanSheet(device: device, scale: scale, prefs: prefs, demo: demo),
  );
}

class _ScanSheet extends StatefulWidget {
  const _ScanSheet({
    required this.device,
    required this.scale,
    required this.prefs,
    this.demo,
  });

  final K2Device device;
  final ScaleDevice scale;
  final Prefs prefs;

  /// null — демо в этой сборке недоступно, ряда не будет.
  final Demo? demo;

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  String? _error;
  bool _showAll = false;

  /// К кому идёт подключение прямо сейчас — чтобы крутить спиннер в его ряду.
  String? _connecting;

  @override
  void initState() {
    super.initState();
    // startScan сразу дёргает notifyListeners; во время build это запрещено.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    setState(() => _error = null);
    // В демо искать нечего: симулятор объявляет сам себя, и его находки только
    // засоряют список — настоящий эфир в это время не слышен.
    if (widget.demo?.on ?? false) return;
    try {
      await widget.device.startScan(showAll: _showAll);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    widget.device.stopScan();
    super.dispose();
  }

  /// Закрыть лист — и ровно его.
  ///
  /// Голый `Navigator.pop` закрывает то, что сейчас наверху, а наверху может
  /// быть уже не этот лист. Подключение идёт секундами, кадры в это время
  /// выходят рывками, и человек, не увидев отклика, жмёт ещё раз: первый
  /// лишний тап уносит лист, второй — главный экран. Навигатор пустеет, и
  /// остаётся чёрное поле, из которого нет выхода даже кнопкой «назад».
  /// Поэтому закрываемся по своему маршруту и только пока он наверху.
  void _close([String? id]) {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.pop(context, id);
  }

  /// Войти в демо. Тот же смысл, что у обычного ряда: подключиться — только к
  /// симулятору. Выход отсюда не делается: он живёт там же, где у настоящей
  /// машины, — «Отключиться» в её шторке.
  Future<void> _enterDemo() async {
    final demo = widget.demo;
    if (demo == null) return;
    // Пока подключение идёт, ряды не отвечают: тап во второй раз значит не
    // «ещё раз», а «я не понял, что происходит».
    if (_connecting != null) return;
    if (demo.on) {
      _close();
      return;
    }
    setState(() {
      _error = null;
      _connecting = _kDemoRowId;
    });
    await demo.enter();
    if (!mounted) return;
    setState(() => _connecting = null);
    _close();
  }

  /// Подключиться и запомнить. Уже подключённый ряд просто закрывает лист:
  /// отключение — осознанное действие и живёт в меню машины.
  Future<void> _connect(String id, String advertisedName) async {
    final d = widget.device;
    if (_connecting != null) return;
    if (d.isConnected && d.connectedId == id) {
      _close(id);
      return;
    }
    setState(() {
      _error = null;
      _connecting = id;
    });
    try {
      // Тап по ряду всегда значит «подключись» — в том числе из демо. Сначала
      // выйти из него: иначе настоящий идентификатор ушёл бы в симулятор.
      final demo = widget.demo;
      if (demo?.on ?? false) await demo!.leave();
      if (!mounted) return;
      await d.connect(id);
      widget.prefs.remember(id, advertisedName);
      if (mounted) setState(() => _connecting = null);
      _close(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _connecting = null;
        });
      }
    }
  }

  /// Подключить весы. Лист при этом не закрывается: устройств два, и человек,
  /// открывший список, чаще всего хочет поднять оба.
  Future<void> _connectScale(String id, String advertisedName) async {
    final sc = widget.scale;
    if (_connecting != null) return;
    if (sc.isConnected && sc.connectedId == id) return;
    setState(() {
      _error = null;
      _connecting = id;
    });
    try {
      await sc.connect(id);
      widget.prefs.rememberScale(id, advertisedName);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _connecting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.device, widget.scale, widget.prefs]),
      builder: (context, _) {
        final t = context.t;
        final d = widget.device;
        final demo = widget.demo;
        final inDemo = demo?.on ?? false;
        final saved = widget.prefs.devices;
        // В «рядом» показываем только новые: добавленные уже стоят выше.
        final sc = widget.scale;
        final savedScale = widget.prefs.lastScaleId;
        final fresh = [
          for (final dev in d.discovered)
            if (dev.kind != DeviceKind.scale &&
                !saved.any((s) => s.id == dev.id))
              dev,
        ];
        // Весы — второе устройство, а не второй сорт: тот же список, тот же
        // тап. Отличает их только значок и то, что подключение к ним не
        // закрывает лист.
        final scales = [
          for (final dev in d.discovered)
            if (dev.kind == DeviceKind.scale && dev.id != savedScale) dev,
        ];

        String scaleSubtitle(String id, {DiscoveredDevice? seen}) {
          if (sc.isConnected && sc.connectedId == id) return t.deviceConnected;
          if (_connecting == id) return t.connecting;
          if (seen == null) return t.notInRange;
          return seen.rssi == null ? t.tapToConnect : t.rssi(seen.rssi!);
        }

        String subtitle(String id, {DiscoveredDevice? seen}) {
          if (d.isConnected && d.connectedId == id) return t.deviceConnected;
          if (_connecting == id) return t.connecting;
          if (seen == null) return t.notInRange;
          return seen.rssi == null ? t.tapToConnect : t.rssi(seen.rssi!);
        }

        return SheetShell(
          title: t.devices,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.showAll,
                style: const TextStyle(color: K.textDim, fontSize: 12),
              ),
              const SizedBox(width: 8),
              KSwitch(
                value: _showAll,
                semanticLabel: t.showAll,
                onChanged: (v) {
                  setState(() => _showAll = v);
                  _scan();
                },
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                SheetCaption(_error!, align: TextAlign.start),
                const SizedBox(height: 12),
              ],
              if (saved.isNotEmpty) ...[
                _SectionTitle(t.myDevices),
                for (final s in saved) ...[
                  Builder(
                    builder: (_) {
                      final seen = d.discovered
                          .where((x) => x.id == s.id)
                          .firstOrNull;
                      return _DeviceRow(
                        // В списке машина под своим именем, а если его не
                        // давали — под тем, чем она представилась в эфире.
                        title: s.title,
                        subtitle: subtitle(s.id, seen: seen),
                        connected: d.isConnected && d.connectedId == s.id,
                        busy: _connecting == s.id,
                        // Пока машины нет в эфире, ряд приглушён — но остаётся
                        // на месте и остаётся нажимаемым.
                        away: seen == null,
                        onTap: () => _connect(s.id, s.name),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 10),
              ],
              if (savedScale != null) ...[
                if (saved.isEmpty) _SectionTitle(t.myDevices),
                Builder(
                  builder: (_) {
                    final seen = d.discovered
                        .where((x) => x.id == savedScale)
                        .firstOrNull;
                    return _DeviceRow(
                      icon: KIcon.scale,
                      title: widget.prefs.scaleName,
                      subtitle: scaleSubtitle(savedScale, seen: seen),
                      connected: sc.isConnected && sc.connectedId == savedScale,
                      busy: _connecting == savedScale,
                      away: seen == null,
                      onTap: () =>
                          _connectScale(savedScale, widget.prefs.scaleName),
                    );
                  },
                ),
                const SizedBox(height: 18),
              ],
              // В демо эфир не слушают, и раздела «рядом» просто нет: иначе в
              // нём висят симуляторы, объявленные тем же симулятором.
              if (!inDemo) ...[
                _SectionTitle(t.devicesNearby),
                for (final dev in fresh) ...[
                  _DeviceRow(
                    title: dev.advertisedName,
                    subtitle: subtitle(dev.id, seen: dev),
                    connected: d.isConnected && d.connectedId == dev.id,
                    busy: _connecting == dev.id,
                    away: false,
                    onTap: () => _connect(dev.id, dev.advertisedName),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final dev in scales) ...[
                  _DeviceRow(
                    icon: KIcon.scale,
                    title: dev.advertisedName,
                    subtitle: scaleSubtitle(dev.id, seen: dev),
                    connected: sc.isConnected && sc.connectedId == dev.id,
                    busy: _connecting == dev.id,
                    away: false,
                    onTap: () => _connectScale(dev.id, dev.advertisedName),
                  ),
                  const SizedBox(height: 8),
                ],
                if (fresh.isEmpty && scales.isEmpty)
                  Row(
                    children: [
                      const KSpinner(color: K.btBlue, size: 16, stroke: 2),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          saved.isEmpty ? t.searchNearby : t.searching,
                          style: const TextStyle(color: K.text2, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                _Action(label: t.search, onTap: _scan),
              ],
              // Демо — последним, ниже всего, чем человек занимается на самом
              // деле. Отдельной секцией и приглушённым рядом: это не машина, и
              // притворяться ею в списке настоящих оно не должно.
              if (demo != null) ...[
                const SizedBox(height: 22),
                _SectionTitle(t.demoSection),
                _DemoRow(
                  title: t.demoTitle,
                  subtitle: inDemo
                      ? t.deviceConnected
                      : _connecting == _kDemoRowId
                      ? t.connecting
                      : t.demoAbout,
                  connected: inDemo,
                  busy: _connecting == _kDemoRowId,
                  onTap: _enterDemo,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Идентификатор ряда демо. Настоящим устройством оно не притворяется, но
/// спиннер в ряду крутится по тому же признаку, что и у остальных.
const String _kDemoRowId = '__demo__';

/// Ряд демо-режима.
///
/// Нарочно тише соседей: серый значок вместо синего, серая подпись вместо
/// «Нажмите, чтобы подключиться». Синий в этом листе значит связь, и вешать
/// его на симулятор нечестно — а перетягивать внимание с настоящих машин
/// второстепенной функции незачем.
class _DemoRow extends StatelessWidget {
  const _DemoRow({
    required this.title,
    required this.subtitle,
    required this.connected,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool connected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    scale: 0.98,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // Даже подключённое демо не красится синим: связь здесь ни при чём.
        color: connected ? const Color(0x14FFB000) : K.rowBg,
        borderRadius: BorderRadius.circular(K.rRow),
        border: Border.all(
          color: connected ? K.amber.withValues(alpha: 0.4) : K.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0x0DFFFFFF),
              shape: BoxShape.circle,
            ),
            child: busy
                ? const KSpinner(color: K.textMuted, size: 16, stroke: 2)
                : KIconView(
                    KIcon.play,
                    size: 15,
                    color: connected ? K.amber : K.textMuted,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: K.text2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: connected ? K.amber : K.textDim,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Подпись секции: «Мои устройства», «Устройства рядом».
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: K.textDim,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// Ряд устройства: значок связи в круге, имя и статус.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.title,
    required this.subtitle,
    required this.connected,
    required this.busy,
    required this.away,
    required this.onTap,
    this.icon = KIcon.bluetooth,
  });

  /// Чем устройство себя называет. Синий значок связи — у машины, весы со
  /// своим: в одном списке они различаются с одного взгляда.
  final KIcon icon;

  final String title;
  final String subtitle;
  final bool connected;

  /// Идёт подключение именно к этой машине.
  final bool busy;

  /// Машина из списка, которой сейчас нет в эфире.
  final bool away;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    scale: 0.98,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: connected ? const Color(0x124DA3FF) : K.rowBg,
        borderRadius: BorderRadius.circular(K.rRow),
        border: Border.all(
          color: connected ? K.btBlue.withValues(alpha: 0.55) : K.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0x0DFFFFFF),
              shape: BoxShape.circle,
            ),
            child: busy
                ? const KSpinner(color: K.btBlue, size: 16, stroke: 2)
                : KIconView(
                    icon,
                    size: 17,
                    color: away ? K.textMuted : K.btBlue,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: away ? K.text2 : K.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: connected ? K.btBlue : K.textDim,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Стеклянная кнопка на всю ширину.
class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    child: Glass(
      radius: K.rCta,
      // Внутри листа размывать нечего: под кнопкой сам лист, уже размытый.
      blur: 0,
      tone: GlassTone.panel,
      // Кнопка лежит внутри листа: тень под ней лёгкая, иначе лист выглядит
      // многослойным пирогом.
      lifted: false,
      child: SizedBox(
        height: 48,
        child: Center(
          child: Text(label, style: K.ctaLabel.copyWith(color: K.text)),
        ),
      ),
    ),
  );
}
