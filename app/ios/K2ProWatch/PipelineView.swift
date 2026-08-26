import SwiftUI
import WatchKit

/// Главный экран: весь цикл одним списком и одна кнопка внизу.
///
/// Список — он же настройка: тап по ряду открывает его экран. Порядок рядов
/// равен порядку исполнения, поэтому таймер стоит первым, а режим вторым —
/// он решает, что будет ниже.
struct PipelineView: View {
  @EnvironmentObject private var link: WatchLink
  @Binding var path: [Route]

  /// Какой ряд был активен в прошлый раз. По смене играем отклик: на часах
  /// это единственный способ заметить переход, не глядя на экран.
  @State private var lastActive: String?

  /// Нажали, снимок ещё не пришёл.
  @State private var pending = false

  /// Страховка на случай, если ответа не будет вовсе.
  @State private var watchdog: Task<Void, Never>?

  var body: some View {
    Group {
      if let snap = link.snapshot {
        // Пока машина работает, настраивать нечего: на экране остаётся один
        // текущий шаг и крупный «Стоп», в который легко попасть не глядя.
        if snap.device?.running == true {
          RunningView(snap: snap, pending: pending) { tapCta(snap) }
        } else {
          content(snap)
        }
      } else {
        NoPhoneView()
      }
    }
    .navigationBarBackButtonHidden(link.snapshot?.device?.running ?? false)
    // Ожидание снимается здесь, а не внутри ветки списка. Пуск как раз и
    // подменяет ветку на RunningView — отметка, поставленная на исчезнувшем
    // экране, снималась бы наблюдателем, которого в иерархии уже нет, и
    // висела бы вечно поверх «Стопа».
    .onChange(of: link.snapshot?.cta.kind) { _, _ in clearPending() }
    .onChange(of: link.snapshot?.device?.running) { _, _ in clearPending() }
  }

  /// Нажатие ушло. Ждём ответа, но не дольше телефонного таймаута: там команда
  /// к этому моменту уже признана потерянной.
  private func markPending() {
    pending = true
    watchdog?.cancel()
    watchdog = Task { @MainActor in
      try? await Task.sleep(for: .seconds(9))
      guard !Task.isCancelled else { return }
      pending = false
    }
  }

  private func clearPending() {
    watchdog?.cancel()
    watchdog = nil
    pending = false
  }

  private func content(_ snap: Snapshot) -> some View {
    VStack(spacing: 0) {
      ScrollView {
        LazyVStack(spacing: 5) {
          ForEach(snap.steps) { step in
            StepRow(step: step) { open(step) }
          }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
      }

      CtaButton(cta: snap.cta, pending: pending) { tapCta(snap) }
        // Внизу экран уже сужается скруглением: без этих полей капсулу
        // срезает по краям. Меньше нельзя, больше — уже пустая трата высоты.
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
    // Системная шапка скрыта, поэтому верхнюю кромку забираем себе целиком:
    // на 45 мм каждая отвоёванная строка — это ещё один ряд пайплайна.
    .background(K.bg)
    // Нижняя безопасная зона на часах отдана системе зря: своя капсула
    // держит отступ сама.
    .ignoresSafeArea(edges: .bottom)
    .navigationTitle(snap.device?.name ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        HStack(spacing: 3) {
          StatusDot(
            color: snap.device?.running == true
              ? Color(hex: snap.accentText) : K.ready,
            size: K.M.headerDot
          )
          if let level = snap.device?.battery {
            BatteryGauge(
              level: level,
              percent: nil,
              charging: snap.device?.charging == true
            )
          }
        }
      }
    }
    .onChange(of: snap.steps.first(where: { $0.isActive })?.id) { _, now in
      // Каждая смена шага — короткий щелчок.
      if now != nil, now != lastActive { WKInterfaceDevice.current().play(.click) }
      lastActive = now
    }
    .onChange(of: snap.device?.running ?? false) { _, running in
      WKInterfaceDevice.current().play(running ? .start : .stop)
    }
    .onChange(of: snap.cta.kind) { _, kind in
      if kind == "done" { WKInterfaceDevice.current().play(.success) }
    }
  }

  /// Куда ведёт тап по ряду. Часы не знают, что за шаг перед ними, — только
  /// каким экраном он настраивается.
  private func open(_ step: Step) {
    guard step.editable else { return }
    WKInterfaceDevice.current().play(.click)
    switch step.editor {
    case "timer": path.append(.timer)
    case "mode": path.append(.mode)
    case "stepper": path.append(.step(step.id))
    case "group": path.append(.group(step.id))
    case "weight": path.append(.weight)
    default: break
    }
  }

  private func tapCta(_ snap: Snapshot) {
    switch snap.cta.kind {
    case "start":
      link.send("start")
      markPending()
    case "stop":
      link.send("stop")
      markPending()
    case "cancelAlarm": link.send("setTimer", ["on": false])
    case "connect": path.removeAll()
    default: return
    }
    WKInterfaceDevice.current().play(.click)
  }
}

/// Один ряд пайплайна: значок, подпись, значение и — во время работы —
/// полоса прогресса по нижней кромке.
struct StepRow: View {
  let step: Step
  let onTap: () -> Void

  @State private var pulse = false

  private var tone: Color { Color(hex: step.tone) }
  private var danger: Color { Color(hex: "#E0352B") }

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 8) {
        PipeIcon(name: step.icon, color: iconColor)
        VStack(alignment: .leading, spacing: 0) {
          Text(step.label)
            .font(K.F.rowLabel)
            .foregroundStyle(step.isActive ? tone : K.secondary)
          Text(step.value)
            .font(K.F.rowValue)
            .foregroundStyle(valueColor)
        }
        Spacer(minLength: 2)
        if step.editable {
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(K.dim)
        }
      }
      .padding(K.M.cellPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(background)
      .overlay(alignment: .bottomLeading) { progress }
      .clipShape(RoundedRectangle(cornerRadius: K.M.cellRadius))
      .opacity(step.isActive && pulse ? 0.75 : 1)
    }
    .buttonStyle(.plain)
    .disabled(!step.editable)
    .onAppear {
      guard step.isActive else { return }
      withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
        pulse = true
      }
    }
  }

  private var iconColor: Color {
    if step.isError { return danger }
    if step.isActive || step.highlighted { return tone }
    return K.secondary
  }

  private var valueColor: Color {
    if step.isError { return danger }
    if step.isActive || step.highlighted { return tone }
    return K.text
  }

  @ViewBuilder private var background: some View {
    ZStack {
      RoundedRectangle(cornerRadius: K.M.cellRadius)
        .fill(step.isPassed ? K.cellPassed : K.cell)
      // Активный шаг и взведённый таймер подсвечены изнутри цветом фазы.
      if step.isActive || step.highlighted {
        RoundedRectangle(cornerRadius: K.M.cellRadius).fill(tone.opacity(0.16))
      }
    }
  }

  @ViewBuilder private var progress: some View {
    if step.isActive, let fraction = step.progress {
      GeometryReader { geo in
        Rectangle()
          .fill(tone)
          .frame(width: max(0, geo.size.width * fraction), height: K.M.progressBar)
          .position(
            x: max(0, geo.size.width * fraction) / 2,
            y: geo.size.height - K.M.progressBar / 2
          )
          .animation(.linear(duration: 0.3), value: fraction)
      }
    }
  }
}

/// Единственная кнопка внизу. Что она делает и какого цвета — решает телефон.
struct CtaButton: View {
  let cta: Cta
  var height: CGFloat = K.M.ctaHeight
  var font: Font = K.F.cta

  /// Нажатие уже засчитано, но снимок с телефона ещё не приехал.
  ///
  /// Своё ожидание нужно вдобавок к телефонному: до него команде ещё лететь
  /// через WatchConnectivity, и всё это время кнопка выглядела бы так, будто
  /// нажатие не прошло.
  var pending = false
  let onTap: () -> Void

  private var waiting: Bool { cta.busy || pending }

  /// Пуск требует намеренного жеста — сдвига, а не касания.
  ///
  /// В контракте это поле называется `hold` с тех пор, как жестом было
  /// удержание. Смысл у него прежний: «случайно не должно сработать».
  private var needsSlide: Bool { cta.hold == true }

  /// Остановка не блокируется ожиданием никогда.
  ///
  /// Это единственный способ прервать машину, и экран работы не даёт уйти
  /// назад. Если ответ на первое нажатие потеряется, заблокированная кнопка
  /// запрёт человека наедине с работающим кипятильником. Повторный «Стоп»
  /// безвреден: команда идемпотентна.
  private var locked: Bool {
    cta.kind == "done" || cta.kind == "blocked" || (waiting && cta.kind != "stop")
  }

  var body: some View {
    // Сдвигом пускаем только тогда, когда ждать нечего: под ожиданием ручка
    // ездила бы, ничего не запуская, — а выглядело бы это как рабочий орган.
    if needsSlide && !waiting {
      // Высота приезжает снаружи: «Стоп» на экране работы крупнее прочего, и
      // ручка должна вырасти вместе с ним.
      SlideToConfirm(cta: cta, height: max(height, K.M.slideHeight), font: font) {
        onTap()
      }
    } else {
      // Под ожиданием — обычная кнопка. Это и есть тот запасной выход, из-за
      // которого «Стоп» когда-то не делали сдвигом: если первый ответ
      // потеряется, второй раз остановить можно простым касанием.
      button
    }
  }

  private var button: some View {
    Button(action: { if !needsSlide { onTap() } }) {
      Group {
        if locked {
          spinner
        } else if waiting {
          // Ждём, но подпись оставляем: в неё целятся, и она должна быть
          // на месте всё время, пока команда в пути.
          HStack(spacing: 6) {
            spinner
            label
          }
        } else {
          label
        }
      }
      .foregroundStyle(Color(hex: cta.fg))
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background(Color(hex: cta.bg), in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(locked)
  }

  private var label: some View {
    // Подпись приезжает с телефона и на 41 мм бывает длиннее капсулы. Резать
    // её посреди слова нельзя: это единственное, что говорит, что случится.
    Text(cta.label)
      .font(font)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
  }

  private var spinner: some View {
    ProgressView()
      .progressViewStyle(.circular)
      .tint(Color(hex: cta.fg))
      .scaleEffect(0.6)
      .frame(width: 20, height: 20)
  }
}

/// Пуск сдвигом.
///
/// Штатного контрола для этого на watchOS нет: свой слайдер выключения Apple
/// рисует приватным API, а публично есть только кнопка и жесты. Удержание мы
/// пробовали — оно требует объяснения словами («удерживайте для запуска»), а
/// таких слов в капсулу на 41 мм не помещается. Сдвиг объясняет себя сам:
/// ручка слева, ехать вправо.
///
/// Смысл тот же, что был у удержания: кипятильник не должен включаться от
/// случайного касания запястьем о рукав.
struct SlideToConfirm: View {
  let cta: Cta
  var height: CGFloat = K.M.slideHeight
  var font: Font = K.F.cta
  let onConfirm: () -> Void

  /// Насколько ручка уехала вправо, в точках.
  @State private var offset: CGFloat = 0

  /// Порог пройден — щёлкнуть об этом надо один раз, а не каждый кадр.
  @State private var armed = false

  /// Сработало. Дальше жест игнорируем: экран вот-вот сменится на «Стоп», и
  /// второй пуск по дороге туда никому не нужен.
  @State private var fired = false

  /// Доехать надо почти до конца, но не ровно: последние точки хода пальцем
  /// не отмеряются, а отменённый по недоезду пуск раздражает сильнее, чем
  /// лишние пять процентов запаса.
  private static let threshold: CGFloat = 0.85

  private static let inset: CGFloat = 3

  var body: some View {
    GeometryReader { geo in
      let knob = height - Self.inset * 2
      let travel = max(1, geo.size.width - knob - Self.inset * 2)
      let progress = min(1, offset / travel)

      ZStack(alignment: .leading) {
        Capsule().fill(Color(hex: cta.bg))

        HStack(spacing: 0) {
          // Место ручки: под ней подпись всё равно не читается.
          Color.clear.frame(width: knob + Self.inset * 2)
          Text(cta.label)
            .font(font)
            .foregroundStyle(Color(hex: cta.fg))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.trailing, 8)
        }
        // Подпись гаснет быстрее, чем едет ручка: догоняя её, она бы
        // читалась как надпись на самой ручке.
        .opacity(Double(max(0, 1 - progress * 1.6)))

        knobView(size: knob)
          .offset(x: Self.inset + offset)
      }
      .frame(height: height)
      .contentShape(Capsule())
      .gesture(drag(travel: travel))
    }
    .frame(height: height)
    // Кнопка сменилась — ручку вернуть. Иначе «Стоп» приедет уже сдвинутым.
    .onChange(of: cta.kind) { _, _ in reset() }
  }

  private func knobView(size: CGFloat) -> some View {
    ZStack {
      Circle().fill(Color(hex: cta.fg))
      Image(systemName: "chevron.right")
        .font(.system(size: size * 0.42, weight: .bold))
        .foregroundStyle(Color(hex: cta.bg))
    }
    .frame(width: size, height: size)
  }

  private func drag(travel: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { v in
        guard !fired else { return }
        offset = min(travel, max(0, v.translation.width))

        // Щелчок на пороге — чтобы отпускать можно было, не глядя на экран.
        let past = offset >= travel * Self.threshold
        if past != armed {
          armed = past
          if past { WKInterfaceDevice.current().play(.click) }
        }
      }
      .onEnded { _ in
        guard !fired else { return }
        guard armed else {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            offset = 0
          }
          return
        }
        fired = true
        WKInterfaceDevice.current().play(.success)
        withAnimation(.easeOut(duration: 0.12)) { offset = travel }
        onConfirm()
      }
  }

  private func reset() {
    fired = false
    armed = false
    offset = 0
  }
}
