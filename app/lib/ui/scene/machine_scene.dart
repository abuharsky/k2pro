import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'scene_state.dart';

/// Машина из макета `export/machine-layer-v2`: база с корпусом и стендом плюс
/// четыре слоя-стопки (бак, помпа, таблетка, чашка). У каждого слоя все кадры
/// лежат друг на друге, активный держит opacity 1 — переход состояний это
/// кроссфейд, ничего больше не двигается.
class MachineScene extends StatelessWidget {
  const MachineScene({super.key, required this.state, this.accent = K.accent});

  final SceneState state;

  /// Цвет подсветки работающей секции.
  final Color accent;

  /// Аспект базовой картинки: 800×1200.
  static const double aspect = SceneLayer.baseAspect;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, c) {
          // Сцена — один жёсткий холст: сначала берём наибольший бокс 2:3,
          // который влезает в отведённое место, и уже от него считаем всё
          // остальное. Раньше пропорцию держал AspectRatio, но под тугими
          // констрейнтами (а их даёт, например, FractionallySizedBox) он
          // отдаёт их как есть — бокс переставал быть 2:3, база внутри него
          // центровалась сама, а слои считались от всего бокса, и при ресайзе
          // окна они разъезжались.
          final box = _fit(c.biggest);
          return Center(
            child: SizedBox.fromSize(
              size: box,
              child: AnimatedOpacity(
                // Пока связи нет, показываем машину в покое и приглушённой.
                opacity: state.connected ? 1 : 0.55,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // База задаёт систему координат: её бокс и есть холст.
                      // BoxFit.fill, а не contain: бокс уже ровно её пропорции,
                      // и так картинка не может съехать на полпикселя от слоёв.
                      Image.asset(
                        'assets/machine/base.png',
                        fit: BoxFit.fill,
                        cacheWidth: _cache(box.width, dpr, 800),
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      ),
                      _Glow(zone: state.zone, color: accent),
                      for (final layer in SceneLayer.values)
                        _LayerStack(
                          layer: layer,
                          frame: state.frameOf(layer),
                          box: box,
                          dpr: dpr,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Наибольший бокс пропорции базы, влезающий в [limit]. Машина всегда
  /// показывается целиком: тесное окно — просто маленькая машина.
  static Size _fit(Size limit) {
    // Сцену могут поставить и без ограничения по одной из сторон — тогда её
    // задаёт вторая, а если не задана ни одна, берём натуральный размер базы.
    final w = limit.width.isFinite
        ? limit.width
        : limit.height.isFinite
        ? limit.height * aspect
        : 800.0;
    final h = limit.height.isFinite ? limit.height : w / aspect;
    return w / h > aspect ? Size(h * aspect, h) : Size(w, w / aspect);
  }
}

/// Стопка кадров одного слоя, поставленная по координатам макета.
class _LayerStack extends StatelessWidget {
  const _LayerStack({
    required this.layer,
    required this.frame,
    required this.box,
    required this.dpr,
  });

  final SceneLayer layer;
  final int frame;
  final Size box;
  final double dpr;

  @override
  Widget build(BuildContext context) {
    final width = box.width * layer.w;
    // Кадры слоя одинакового размера, так что кэш-ширину считаем один раз.
    final cache = _cache(width, dpr, _sourceWidth[layer]!);
    return Positioned(
      left: box.width * (layer.x - layer.w / 2),
      top: box.height * layer.y,
      width: width,
      height: width / layer.aspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < layer.frames; i++)
            AnimatedOpacity(
              opacity: i == frame ? 1 : 0,
              duration: Duration(milliseconds: layer.ms),
              curve: Curves.easeInOut,
              child: Image.asset(
                layer.assetOf(i),
                // Бокс слоя уже ровно пропорции кадра — см. базу выше.
                fit: BoxFit.fill,
                cacheWidth: cache,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
        ],
      ),
    );
  }

  /// Ширина исходников: больше неё декодировать бессмысленно.
  static const Map<SceneLayer, int> _sourceWidth = {
    SceneLayer.tank: 381,
    SceneLayer.pump: 448,
    SceneLayer.puck: 414,
    SceneLayer.cup: 375,
  };
}

/// Мягкое пятно света на работающем узле: цвет берётся от фазы, так что
/// сцена показывает статус сама, без подписи.
class _Glow extends StatelessWidget {
  const _Glow({required this.zone, required this.color});

  final SceneLayer? zone;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final z = zone;
    if (z == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: c.maxHeight * z.y,
            height: c.maxHeight * z.h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.75,
                  colors: [
                    color.withValues(alpha: 0.24),
                    color.withValues(alpha: 0.08),
                    color.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ширина декодирования кадра: под фактический размер, но не больше исходника.
/// Полный кадр базы — 800×1200, и без этого каждый слой держал бы в памяти
/// заметно больше, чем реально видно на экране.
int _cache(double width, double dpr, int source) =>
    math.max(1, math.min((width * dpr).round(), source));
