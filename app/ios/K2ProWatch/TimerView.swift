import SwiftUI
import WatchKit

/// Таймер готовности: «кофе в чашке через N минут».
///
/// Будильника по часам суток здесь больше нет как главного: эспрессо к утру
/// выдохнется, а рабочий сценарий — «поставил, пока готовлю завтрак, вернулся,
/// а он свежий». Поэтому наверху четыре пресета, тап по любому — и пошёл
/// отсчёт. Точное время осталось ниже, для тех, кому нужно ровно к 7:20.
///
/// Считает всё телефон: «через N» превращается в час старта на той стороне
/// (машина умеет только будильник), сюда приезжает готовый остаток. Отсчёт
/// тикает на часах сам — пока машина ждёт, телефон снимок не шлёт.
struct TimerView: View {
  @EnvironmentObject private var link: WatchLink
  @Environment(\.dismiss) private var dismiss

  private var timer: Timer? { link.snapshot?.timer }

  var body: some View {
    Group {
      if let timer {
        if timer.armed {
          armed(timer)
        } else {
          setup(timer)
        }
      } else {
        NoPhoneView()
      }
    }
    .navigationTitle(link.string("timer"))
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - Взведён

  private func armed(_ timer: Timer) -> some View {
    ScrollView {
      VStack(spacing: 8) {
        Text(timer.readyLabel)
          .font(K.F.hint)
          .foregroundStyle(K.secondary)

        Countdown(seconds: timer.readyInSeconds ?? 0)

        if let line = timer.startLine {
          Text(line)
            .font(K.F.rowLabel)
            .foregroundStyle(K.secondary)
            .multilineTextAlignment(.center)
        }

        Button {
          WKInterfaceDevice.current().play(.stop)
          link.send("setTimer", ["on": false])
          dismiss()
        } label: {
          Text(timer.cancel)
            .font(K.F.cta)
            .foregroundStyle(K.text)
            .frame(maxWidth: .infinity)
            .frame(height: K.M.ctaHeight)
            .background(K.control, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
      }
      .padding(.horizontal, 6)
      .padding(.top, 8)
    }
    .background(K.bg)
  }

  // MARK: - Настройка

  private func setup(_ timer: Timer) -> some View {
    ScrollView {
      VStack(spacing: 10) {
        Text(timer.hint)
          .font(K.F.hint)
          .foregroundStyle(K.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 4)

        // Два ряда по два: на 45 мм четыре пресета в строку сжались бы в
        // нечитаемые полоски, а промах по ним стоит пустой чашки.
        let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        LazyVGrid(columns: cols, spacing: 6) {
          ForEach(timer.presets, id: \.self) { m in
            PresetButton(minutes: m, unit: timer.presetUnit, tone: link.snapshot?.accent ?? "#FFB100") {
              WKInterfaceDevice.current().play(.start)
              link.send("armPreset", ["minutes": m])
              dismiss()
            }
          }
        }

        NavigationLink {
          ByTimeView(timer: timer)
        } label: {
          HStack {
            Text(link.string("byTime"))
              .font(K.F.rowLabel)
              .foregroundStyle(K.text)
            Spacer()
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(K.secondary)
          }
          .padding(.horizontal, 14)
          .frame(height: K.M.ctaHeight)
          .background(K.control, in: Capsule())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 6)
      .padding(.top, 6)
      .padding(.bottom, 8)
    }
    .background(K.bg)
  }
}

/// Пресет готовности: крупное число и «мин» под ним.
private struct PresetButton: View {
  let minutes: Int
  let unit: String
  let tone: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 0) {
        Text("\(minutes)")
          .font(.system(size: 28, weight: .bold).monospacedDigit())
          .foregroundStyle(Color(hex: tone))
        Text(unit)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(K.secondary)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 60)
      .background(K.control, in: RoundedRectangle(cornerRadius: K.M.cellRadius))
    }
    .buttonStyle(.plain)
  }
}

/// Живой отсчёт до готовности. Тикает сам, от числа из снимка: до часа —
/// «M:SS», дальше — «1 ч 32 мин».
private struct Countdown: View {
  @EnvironmentObject private var link: WatchLink
  let seconds: Int

  /// Момент готовности в часах локально. Ставится от `seconds` при каждом его
  /// изменении: телефон присылает остаток, а отмеряем мы уже своими часами.
  @State private var deadline = Date()

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { ctx in
      Text(text(max(0, Int(deadline.timeIntervalSince(ctx.date).rounded()))))
        .font(K.F.bigTime)
        .foregroundStyle(Color(hex: "#FFB000"))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
    .onAppear { deadline = Date().addingTimeInterval(TimeInterval(seconds)) }
    .onChange(of: seconds) { _, now in
      deadline = Date().addingTimeInterval(TimeInterval(now))
    }
  }

  private func text(_ s: Int) -> String {
    if s >= 3600 {
      let h = s / 3600
      let m = (s % 3600) / 60
      return "\(h) \(link.string("hours")) \(String(format: "%02d", m)) \(link.string("minutes"))"
    }
    return "\(s / 60):\(String(format: "%02d", s % 60))"
  }
}

/// Точное время: два колеса, часы и минуты, и кнопка «Запланировать».
///
/// Подписи над колёсами свои: часы и минуты в системном поле разделяются
/// двоеточиями, и второе на узком экране читалось так, будто у минут отрезали
/// секунды.
struct ByTimeView: View {
  @EnvironmentObject private var link: WatchLink
  @Environment(\.dismiss) private var dismiss
  let timer: Timer

  @State private var hour = 7
  @State private var minute = 0

  var body: some View {
    VStack(spacing: 6) {
      Spacer(minLength: 0)

      HStack(spacing: 4) {
        wheel($hour, upTo: 24, caption: link.string("hours"))
        wheel($minute, upTo: 60, caption: link.string("minutes"))
      }
      .frame(height: 84)

      Spacer(minLength: 0)

      Button {
        WKInterfaceDevice.current().play(.start)
        link.send("setTimer", ["minutes": hour * 60 + minute, "on": true])
        dismiss()
      } label: {
        Text(timer.enable)
          .font(K.F.cta)
          .foregroundStyle(Color(hex: "#0D0F12"))
          .frame(maxWidth: .infinity)
          .frame(height: K.M.ctaHeight)
          .background(Color(hex: link.snapshot?.accent ?? "#FFB100"), in: Capsule())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 4)
    .padding(.bottom, 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(K.bg)
    .navigationTitle(link.string("byTime"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      hour = (timer.byTime / 60) % 24
      minute = timer.byTime % 60
    }
  }

  private func wheel(
    _ value: Binding<Int>,
    upTo count: Int,
    caption: String
  ) -> some View {
    VStack(spacing: 0) {
      Text(caption)
        .font(K.F.hint)
        .foregroundStyle(K.secondary)
      Picker(selection: value) {
        ForEach(0..<count, id: \.self) { v in
          Text(String(format: "%02d", v))
            .font(K.F.bigTime)
            .tag(v)
        }
      } label: {
        EmptyView()
      }
      .labelsHidden()
      .pickerStyle(.wheel)
    }
  }
}
