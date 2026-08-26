/// «Баристовские» правила подстройки эспрессо: по вкусу и телу чашки — что и в
/// каком порядке крутить, от самого сильного рычага к самому слабому.
///
/// Порядок здесь — не украшение, а суть. На результат сильнее всего влияет
/// помол, затем закладка (доза), затем выход (соотношение — точно задаётся лишь
/// отсечкой по весам), и лишь потом, слабо, — температура. Пред-смачивание и
/// длительность пролива на этой машине вкус почти не двигают и в советах не
/// участвуют вовсе. Показываем только те рычаги, что реально помогут этой
/// проблеме, — и по убыванию силы.
library;

/// Как чашка на вкус.
enum Taste { sour, salty, empty, sweet, bitter, astringent }

/// Тело — плотность, «вес» напитка во рту.
enum BrewBody { thin, full }

/// Рычаг, к которому относится совет. Нужен для сортировки по силе и чтобы
/// отличить единственную ручку в приложении (температуру) от подсказок про
/// помол и дозу, которые крутят руками.
enum Lever { grind, dose, ratio, temperature }

/// Насколько сильно рычаг влияет — он же порядок показа.
enum Tier { primary, secondary, lastResort }

/// Конкретная рекомендация.
enum Fix {
  grindFiner,
  grindCoarser,
  doseMore,
  ratioShorter,
  tempUp,
  tempDown,
}

extension FixInfo on Fix {
  Lever get lever => switch (this) {
    Fix.grindFiner || Fix.grindCoarser => Lever.grind,
    Fix.doseMore => Lever.dose,
    Fix.ratioShorter => Lever.ratio,
    Fix.tempUp || Fix.tempDown => Lever.temperature,
  };
}

/// Один пункт совета: что сделать и насколько это сильный рычаг.
class Rec {
  const Rec(this.fix, this.tier);
  final Fix fix;
  final Tier tier;
}

int _leverOrder(Lever l) => switch (l) {
  Lever.grind => 0,
  Lever.dose => 1,
  Lever.ratio => 2,
  Lever.temperature => 3,
};

/// Собрать совет: список рекомендаций от сильных к слабым, только подходящие.
///
/// [hasScale] — подключены ли весы. Выход (соотношение) точно задаётся только
/// отсечкой по весам, поэтому без весов этот рычаг недоступен и в список не
/// попадает.
List<Rec> adviceFor({
  Taste? taste,
  BrewBody? body,
  required bool hasScale,
}) {
  final raw = <Rec>[..._tasteRecs(taste), ..._bodyRecs(body)];

  // Без весов выходом управлять нечем — убираем.
  final gated = raw.where((r) => r.fix != Fix.ratioShorter || hasScale);

  // Схлопываем повторы: у одной поправки остаётся сильнейший тир.
  final best = <Fix, Tier>{};
  for (final r in gated) {
    final cur = best[r.fix];
    if (cur == null || r.tier.index < cur.index) best[r.fix] = r.tier;
  }

  // Помол мельче и крупнее одновременно — это конфликт вкуса и тела
  // (переэкстракция при жидком теле). Помол тогда не трогаем вовсе: честный
  // ответ — больше кофе и короче выход, а не крутить помол в обе стороны.
  if (best.containsKey(Fix.grindFiner) && best.containsKey(Fix.grindCoarser)) {
    best.remove(Fix.grindFiner);
    best.remove(Fix.grindCoarser);
    best[Fix.doseMore] = Tier.primary;
    if (hasScale) best.putIfAbsent(Fix.ratioShorter, () => Tier.secondary);
  }

  final recs = [for (final e in best.entries) Rec(e.key, e.value)];
  recs.sort((a, b) {
    final byTier = a.tier.index.compareTo(b.tier.index);
    if (byTier != 0) return byTier;
    return _leverOrder(a.fix.lever).compareTo(_leverOrder(b.fix.lever));
  });
  return recs;
}

/// Понадобился бы выход, будь весы, — но их нет. По этому экран предлагает их
/// подключить, а не молчит о рычаге.
bool wantsScale({Taste? taste, BrewBody? body, required bool hasScale}) {
  if (hasScale) return false;
  return adviceFor(
    taste: taste,
    body: body,
    hasScale: true,
  ).any((r) => r.fix == Fix.ratioShorter);
}

List<Rec> _tasteRecs(Taste? taste) => switch (taste) {
  // Недоэкстракция — вода прошла слишком быстро.
  Taste.sour => const [
    Rec(Fix.grindFiner, Tier.primary),
    Rec(Fix.tempUp, Tier.lastResort),
  ],
  Taste.salty => const [
    Rec(Fix.grindFiner, Tier.primary),
    Rec(Fix.tempUp, Tier.lastResort),
  ],
  // Переэкстракция — вода шла слишком долго.
  Taste.bitter => const [
    Rec(Fix.grindCoarser, Tier.primary),
    Rec(Fix.ratioShorter, Tier.secondary),
    Rec(Fix.tempDown, Tier.lastResort),
  ],
  // Вяжет — переэкстракция и пересушенная таблетка: крупнее и прохладнее.
  Taste.astringent => const [
    Rec(Fix.grindCoarser, Tier.primary),
    Rec(Fix.tempDown, Tier.secondary),
    Rec(Fix.ratioShorter, Tier.lastResort),
  ],
  // Слабо и водянисто — кофе мало на объём воды.
  Taste.empty => const [
    Rec(Fix.doseMore, Tier.primary),
    Rec(Fix.grindFiner, Tier.secondary),
    Rec(Fix.ratioShorter, Tier.lastResort),
  ],
  Taste.sweet || null => const [],
};

List<Rec> _bodyRecs(BrewBody? body) => switch (body) {
  BrewBody.thin => const [
    Rec(Fix.doseMore, Tier.primary),
    Rec(Fix.grindFiner, Tier.secondary),
    Rec(Fix.ratioShorter, Tier.lastResort),
  ],
  BrewBody.full || null => const [],
};
