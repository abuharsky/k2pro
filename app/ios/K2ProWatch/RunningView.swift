import SwiftUI

/// Экран работающей машины: один текущий шаг и крупный «Стоп».
///
/// Пока идёт цикл, настраивать нечего — список рядов только мешал бы. Здесь
/// остаётся то единственное, что важно на ходу: где машина сейчас, сколько
/// осталось и как её остановить, не целясь.
struct RunningView: View {
  let snap: Snapshot
  var pending = false
  let onStop: () -> Void

  /// Шаг, который машина отрабатывает прямо сейчас. Ищем и во вложенных: в
  /// пайплайне пролив свёрнут, а его составляющие — настоящие фазы.
  private var active: Step? {
    for row in snap.steps {
      if row.isActive, row.children == nil { return row }
      if let hit = row.children?.first(where: { $0.isActive }) { return hit }
    }
    // Свёрнутый ряд помечается активным сам, если активна любая его часть.
    return snap.steps.first { $0.isActive }
  }

  private var tone: Color {
    Color(hex: active?.tone ?? snap.accentText)
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 2)

      Text(active?.label ?? snap.device?.state?.uppercased() ?? "")
        .font(K.F.rowLabel)
        .foregroundStyle(tone)
        .lineLimit(1)

      Text(active?.value ?? "")
        .font(K.F.bigValue)
        .foregroundStyle(K.text)
        .minimumScaleFactor(0.5)
        .lineLimit(1)

      // Полоса ровно та же, что на ряду пайплайна: одна и та же доля,
      // показанная крупнее.
      ProgressBar(fraction: active?.progress, tone: tone)
        .padding(.horizontal, 14)
        .padding(.top, 6)

      Spacer(minLength: 4)

      CtaButton(
        cta: snap.cta,
        height: K.M.stopHeight,
        font: K.F.stop,
        pending: pending,
        onTap: onStop
      )
      .padding(.horizontal, 10)
      .padding(.bottom, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(K.bg)
    .ignoresSafeArea(edges: .bottom)
    .navigationTitle(snap.device?.name ?? "")
    .navigationBarTitleDisplayMode(.inline)
    // Уйти с экрана работающей машины некуда — назад ведёт только «Стоп».
    .navigationBarBackButtonHidden(true)
  }
}

/// Доля пройденного. Нет доли — ровная приглушённая полоса: так выглядит
/// нагрев, длительность которого машина заранее не знает.
struct ProgressBar: View {
  let fraction: Double?
  let tone: Color

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(tone.opacity(0.22))
        if let fraction {
          Capsule()
            .fill(tone)
            .frame(width: max(0, geo.size.width * fraction))
            .animation(.linear(duration: 0.3), value: fraction)
        }
      }
    }
    .frame(height: 6)
  }
}
