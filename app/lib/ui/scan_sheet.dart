import 'package:flutter/material.dart';

import '../ble/k2_device.dart';
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
Future<String?> showScanSheet(
  BuildContext context,
  K2Device device,
  Prefs prefs,
) {
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
    builder: (_) => _ScanSheet(device: device, prefs: prefs),
  );
}

class _ScanSheet extends StatefulWidget {
  const _ScanSheet({required this.device, required this.prefs});

  final K2Device device;
  final Prefs prefs;

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

  /// Подключиться и запомнить. Уже подключённый ряд просто закрывает лист:
  /// отключение — осознанное действие и живёт в меню машины.
  Future<void> _connect(String id, String advertisedName) async {
    final d = widget.device;
    if (d.isConnected && d.connectedId == id) {
      Navigator.pop(context, id);
      return;
    }
    setState(() {
      _error = null;
      _connecting = id;
    });
    try {
      await d.connect(id);
      widget.prefs.remember(id, advertisedName);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _connecting = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.device, widget.prefs]),
      builder: (context, _) {
        final t = context.t;
        final d = widget.device;
        final saved = widget.prefs.devices;
        // В «рядом» показываем только новые: добавленные уже стоят выше.
        final fresh = [
          for (final dev in d.discovered)
            if (!saved.any((s) => s.id == dev.id)) dev,
        ];

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
                        title: s.name,
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
              if (fresh.isEmpty)
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
          ),
        );
      },
    );
  }
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
  });

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
                    KIcon.bluetooth,
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
