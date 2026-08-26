import SwiftUI
import WatchKit

/// Стартовый экран: что телефон знает и что видит в эфире.
///
/// Здесь и машина, и весы — одним столбцом, как на телефоне. Куда ведёт тап,
/// решает род устройства: машина открывает пайплайн, весы — свой прибор с
/// крупной цифрой. Настраивать в весах нечего, взвешивать ими — всё.
///
/// Сканирует телефон — он же владеет BLE. Открытие экрана поэтому не ждёт
/// данных, а просит их: без этого список остался бы пустым навсегда.
struct MachinesView: View {
  @EnvironmentObject private var link: WatchLink
  @Binding var path: [Route]

  var body: some View {
    Group {
      if let snap = link.snapshot {
        list(snap)
      } else {
        NoPhoneView()
      }
    }
    .navigationTitle(link.string("machines"))
    // Крупный заголовок переносится на две строки и съедает треть экрана.
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { link.send("scan") }
  }

  private func list(_ snap: Snapshot) -> some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        ForEach(snap.devices) { d in
          Button {
            open(d)
          } label: {
            row(d, accent: snap.accent)
          }
          .buttonStyle(.plain)
        }

        if snap.devices.isEmpty {
          Text(snap.scanning ? link.string("searching") : link.string("empty"))
            .font(K.F.hint)
            .foregroundStyle(K.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 24)
        }
      }
      .padding(.horizontal, 4)
    }
    .background(K.bg)
    // Машина подключилась — сразу к делу, отдельного подтверждения не нужно.
    .onChange(of: snap.isConnected) { _, connected in
      // Машина подключилась — сразу к делу. Но только если человек всё ещё
      // здесь: он мог уйти в весы, и выдёргивать его оттуда нельзя.
      if connected, path.isEmpty { path.append(.pipeline) }
    }
  }

  /// Куда ведёт строка.
  ///
  /// Весы открываются сразу, не дожидаясь связи: на их экране и написано, что
  /// с ними происходит. Ждать на списке, глядя в неподвижную строку, — хуже.
  private func open(_ d: DeviceRow) {
    WKInterfaceDevice.current().play(.click)
    if !d.connected { link.send("connect", ["id": d.id, "kind": d.kind]) }
    if d.isScale {
      path.append(.scale)
    } else if d.connected {
      path.append(.pipeline)
    }
  }

  private func row(_ d: DeviceRow, accent: String) -> some View {
    HStack(spacing: 8) {
      StatusDot(color: d.connected ? K.ready : Color.white.opacity(0.25))
      // Род устройства виден до чтения имени: весы человек зовёт как угодно,
      // а значок один и тот же.
      PipeIcon(name: d.isScale ? "scale" : "coil", size: 17, color: K.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(d.name).font(K.F.deviceName).foregroundStyle(K.text)
        Text(d.status).font(K.F.rowLabel).foregroundStyle(K.secondary)
      }
      Spacer(minLength: 4)
      if let level = d.battery {
        BatteryGauge(level: level, percent: d.batteryPercent, charging: d.charging)
      } else if let percent = d.batteryPercent {
        // У весов делений нет — только процент, как они его и отдают.
        Text("\(percent)%").font(K.F.battery).foregroundStyle(K.secondary)
      }
    }
    .padding(K.M.cellPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: K.M.cellRadius)
        .fill(d.connected ? K.ready.opacity(0.12) : K.cell)
    )
  }
}
