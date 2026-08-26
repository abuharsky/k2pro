import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/demo.dart';
import '../ble/k2_device.dart';
import '../ble/scale/scale_device.dart';
import '../l10n/l10n_ext.dart';
import '../store/prefs.dart';
import 'scan_sheet.dart';
import 'scene/machine_scene.dart';
import 'scene/scene_state.dart';
import 'sheets/device_sheet.dart';
import 'theme.dart';

/// Первый экран: машины ещё нет.
///
/// Показывается, пока в списке ни одной машины и демо не идёт. Дальше он
/// исчезает навсегда — подключился однажды, и главный экран сам решает, что
/// показать: [prefs.remember] пополняет список, и развилка в `K2App`
/// переключается без чьей-либо помощи.
///
/// Настроек здесь нет ни одной, кроме языка: остальные — про машину, а машины
/// пока нет.
class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.device,
    required this.scale,
    required this.prefs,
    required this.demo,
  });

  final K2Device device;
  final ScaleDevice scale;
  final Prefs prefs;
  final Demo demo;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final safe = MediaQuery.paddingOf(context);

    return Scaffold(
      body: AppBackground(
        child: Padding(
          padding: EdgeInsets.only(
            top: math.max(safe.top, 20) + 8,
            bottom: math.max(safe.bottom, 12) + 14,
            left: 24,
            right: 24,
          ),
          child: Column(
            children: [
              // Машина в покое: смотреть на пустой экран, решая, подключаться
              // или нет, не на что.
              const Expanded(
                child: Center(child: MachineScene(state: SceneState.idle)),
              ),
              Text(
                t.appTitle,
                style: K.title.copyWith(fontSize: 22, color: K.textBright),
              ),
              const SizedBox(height: 10),
              Text(
                t.welcomeSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: K.textDim,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 26),
              _Connect(
                label: t.connectDevice,
                onTap: () =>
                    showScanSheet(context, device, scale, prefs, demo: demo),
              ),
              // Демо — тихой строчкой, а не второй кнопкой: функция
              // второстепенная, и вес наравне с главной ей не по чину. Совсем
              // убирать нельзя — иначе человек без железа обязан сперва
              // открыть поиск и посмотреть на «Ищем…».
              const SizedBox(height: 6),
              KTap(
                onTap: () => unawaited(demo.enter()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Text(
                    t.demoStart,
                    style: const TextStyle(
                      color: K.textDim,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              KTap(
                onTap: () => showLanguageSheet(context, prefs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    '${t.language} · ${languageLabel(t, prefs.localeCode)}',
                    // Тусклее демо: там второстепенное действие, здесь —
                    // и вовсе служебное.
                    style: const TextStyle(color: K.textDisabled, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Единственное действие первого экрана — то, ради чего приложение ставили.
class _Connect extends StatelessWidget {
  const _Connect({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    child: Glass(
      radius: K.rCta,
      tone: GlassTone.panel,
      border: K.amber.withValues(alpha: 0.55),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 17),
          child: Center(
            child: Text(label, style: K.ctaLabel.copyWith(color: K.amber)),
          ),
        ),
      ),
    ),
  );
}
