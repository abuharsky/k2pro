import 'dart:ui';

import 'package:flutter/material.dart';

import '../ble/scale/scale_device.dart';
import '../l10n/l10n_ext.dart';
import '../store/prefs.dart';
import 'theme.dart';
import 'widgets/k_icons.dart';
import 'widgets/round_button.dart';

/// Взвешивание — диалогом по центру, а не экраном.
///
/// Положил зерно, посмотрел, закрыл: занятие на десять секунд, и целого экрана
/// оно не стоит. Стекло, размытие и скругление те же, что у листов, — это тот
/// же модальный слой, просто по центру: лист снизу оказывался бы под пальцем и
/// закрывал собой цифру, ради которой его и открыли.
///
/// Журнала здесь нет намеренно: он про машину — сколько лилось и при какой
/// температуре — и живёт в её настройках. Диалог остаётся чистым прибором.
Future<void> showWeightDialog(
  BuildContext context, {
  required ScaleDevice scale,
  required Prefs prefs,
}) => showDialog<void>(
  context: context,
  // Затемнение слабее обычного. Под диалогом машина, и если гасить её на 55 %,
  // как под листом, сквозь стекло уже нечего разглядывать: размытие есть, а
  // видно его не будет.
  barrierColor: K.overlayLight,
  builder: (ctx) => Stack(
    children: [
      // Весь экран за диалогом уходит из фокуса: слегка размывается, а
      // затемняет его барьер. Без этого карточка висит на резкой машине и
      // читается как наклейка поверх неё, а не как то единственное, с чем
      // сейчас имеют дело.
      //
      // Размытие здесь слабое нарочно: сильное съело бы машину целиком, а она
      // должна остаться узнаваемой — человек не ушёл с экрана, он открыл над
      // ним прибор. Стекло самой карточки размывает этот фон ещё раз, оттого
      // внутри неё картинка глуше, чем вокруг.
      //
      // IgnorePointer — чтобы тап мимо карточки по-прежнему долетал до
      // барьера и закрывал диалог.
      Positioned.fill(
        child: IgnorePointer(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: K.blurBackdrop,
              sigmaY: K.blurBackdrop,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      Center(
        child: Padding(
          // Уже, чем у диалогов-вопросов: этому нужно место под крупную цифру,
          // и чем ближе он к квадрату, тем меньше похож на подсказку и больше
          // — на прибор.
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Крестик над карточкой, а не в ней: внутри он отнимал бы
                // место у цифры и спорил бы с тарой за правый край.
                RoundIconButton(
                  icon: KIcon.close,
                  size: 38,
                  iconSize: 15,
                  onTap: () => Navigator.of(ctx).pop(),
                  semanticLabel: MaterialLocalizations.of(ctx).closeButtonLabel,
                ),
                const SizedBox(height: 10),
                // Рамка рисуется поверх содержимого тем же скруглением,
                // которым оно обрезано: обычная рамка внутри Container легла
                // бы прямым прямоугольником и на углах разошлась бы со стеклом.
                Container(
                  foregroundDecoration: ShapeDecoration(
                    shape: kSquircle(
                      K.rSheet,
                      side: const BorderSide(color: K.sheetBorder),
                    ),
                  ),
                  child: ClipRSuperellipse(
                    borderRadius: BorderRadius.circular(K.rSheet),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: K.blurSheet,
                        sigmaY: K.blurSheet,
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          // Легче, чем у листа: лист закрывает нижнюю треть,
                          // где смотреть особо не на что, а диалог висит
                          // посреди картинки — там плотная подложка убивает
                          // всё стекло.
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [K.dialogTop, K.dialogBottom],
                          ),
                        ),
                        child: _Body(scale: scale, prefs: prefs),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);

class _Body extends StatelessWidget {
  const _Body({required this.scale, required this.prefs});

  final ScaleDevice scale;
  final Prefs prefs;

  /// Сторона кнопки тары. Столько же пустого места держим слева, иначе цифра
  /// съезжает влево и перестаёт быть центром карточки.
  static const double _tare = 46;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: Listenable.merge([scale, prefs]),
      builder: (context, _) {
        // Пока весы спят, число врать не должно: оно осталось с последнего
        // кадра и с тех пор не проверялось.
        final live = scale.isLive;
        final battery = scale.batteryPercent;

        return Padding(
          // Высоты не жалеем: это прибор, а не подсказка. Приземистая
          // карточка читается как всплывшее сообщение, которое сейчас
          // закроют, — а на эту цифру смотрят.
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: live
                          ? K.success
                          : K.success.withValues(alpha: 0.28),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      prefs.scaleName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: K.caption.copyWith(color: K.textDim),
                    ),
                  ),
                  Text(
                    !live
                        ? t.scaleAsleep
                        : battery == null
                        ? ''
                        : t.scaleBattery(battery),
                    style: K.caption.copyWith(color: K.textDim2),
                  ),
                ],
              ),
              const SizedBox(height: 38),

              Row(
                children: [
                  // Пустое место, равное кнопке справа: цифра остаётся ровно
                  // посередине карточки, а не уезжает от тары.
                  const SizedBox(width: _tare),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              scale.grams.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 88,
                                height: 1.05,
                                fontWeight: FontWeight.w200,
                                letterSpacing: -2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: live ? K.textBright : K.textDisabled,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t.gramsUnit,
                          style: TextStyle(
                            fontSize: 20,
                            color: live ? K.textDim : K.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Тара одной буквой: подпись словом рядом с шестидесятым
                  // кеглем читалась бы как вторая цифра.
                  SizedBox(
                    width: _tare,
                    child: _TareButton(size: _tare, onTap: scale.tare),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }
}

class _TareButton extends StatelessWidget {
  const _TareButton({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KTap(
    onTap: onTap,
    semanticLabel: context.t.weightTare,
    child: Glass(
      shape: BoxShape.circle,
      radius: size,
      blur: K.blurCell,
      child: SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: Text(
            'T',
            style: TextStyle(
              color: K.amber,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}
