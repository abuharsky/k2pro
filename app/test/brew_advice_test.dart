import 'package:flutter_test/flutter_test.dart';
import 'package:k2pro/model/brew_advice.dart';

void main() {
  List<Fix> fixes(List<Rec> r) => [for (final x in r) x.fix];
  Tier? tierOf(List<Rec> r, Fix f) {
    for (final x in r) {
      if (x.fix == f) return x.tier;
    }
    return null;
  }

  test('кисло — главный рычаг помол мельче, температура в крайнем случае', () {
    final r = adviceFor(taste: Taste.sour, hasScale: false);
    expect(r.first.fix, Fix.grindFiner);
    expect(r.first.tier, Tier.primary);
    expect(tierOf(r, Fix.tempUp), Tier.lastResort);
    expect(fixes(r), isNot(contains(Fix.ratioShorter)));
  });

  test('горько с весами — помол крупнее, короче выход, потом температура', () {
    final r = adviceFor(taste: Taste.bitter, hasScale: true);
    expect(fixes(r), [Fix.grindCoarser, Fix.ratioShorter, Fix.tempDown]);
    expect(r.first.tier, Tier.primary);
  });

  test('без весов рычаг выхода пропадает', () {
    final r = adviceFor(taste: Taste.bitter, hasScale: false);
    expect(fixes(r), isNot(contains(Fix.ratioShorter)));
    expect(fixes(r), [Fix.grindCoarser, Fix.tempDown]);
  });

  test('терпкий — крупнее помол и прохладнее', () {
    final r = adviceFor(taste: Taste.astringent, hasScale: true);
    expect(r.first.fix, Fix.grindCoarser);
    expect(tierOf(r, Fix.tempDown), Tier.secondary);
  });

  test('пусто — главный рычаг доза, помол вторым', () {
    final r = adviceFor(taste: Taste.empty, hasScale: true);
    expect(r.first.fix, Fix.doseMore);
    expect(tierOf(r, Fix.grindFiner), Tier.secondary);
  });

  test('нет тела — доза больше', () {
    final r = adviceFor(body: BrewBody.thin, hasScale: false);
    expect(r.first.fix, Fix.doseMore);
  });

  test('сладко и с телом — трогать нечего', () {
    expect(adviceFor(taste: Taste.sweet, body: BrewBody.full, hasScale: true),
        isEmpty);
  });

  test('горько + жидкое тело — конфликт помола, помол не трогаем', () {
    final r = adviceFor(taste: Taste.bitter, body: BrewBody.thin, hasScale: true);
    expect(fixes(r), isNot(contains(Fix.grindFiner)));
    expect(fixes(r), isNot(contains(Fix.grindCoarser)));
    expect(tierOf(r, Fix.doseMore), Tier.primary);
  });

  test('пункты идут по убыванию силы', () {
    final r = adviceFor(taste: Taste.bitter, hasScale: true);
    for (var i = 1; i < r.length; i++) {
      expect(r[i].tier.index, greaterThanOrEqualTo(r[i - 1].tier.index));
    }
  });

  test('выход нужен, но весов нет — зовём подключить', () {
    expect(wantsScale(taste: Taste.empty, hasScale: false), isTrue);
    expect(wantsScale(taste: Taste.empty, hasScale: true), isFalse);
    // Кисло весами не лечат — звать их незачем.
    expect(wantsScale(taste: Taste.sour, hasScale: false), isFalse);
  });

  test('ничего не выбрано — совета нет', () {
    expect(adviceFor(hasScale: true), isEmpty);
  });
}
