import SwiftUI

/// Стартовый экран: какие машины видит телефон.
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
    .navigationTitle(link.string("machines", "K2 Pro"))
    // Крупный заголовок переносится на две строки и съедает треть экрана.
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { link.send("scan") }
  }

  private func list(_ snap: Snapshot) -> some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        ForEach(snap.devices) { d in
          Button {
            if d.connected {
              path.append(.pipeline)
            } else {
              link.send("connect", ["id": d.id])
            }
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
      if connected, !path.contains(.pipeline) { path.append(.pipeline) }
    }
  }

  private func row(_ d: DeviceRow, accent: String) -> some View {
    HStack(spacing: 8) {
      StatusDot(color: d.connected ? K.ready : Color.white.opacity(0.25))
      VStack(alignment: .leading, spacing: 1) {
        Text(d.name).font(K.F.deviceName).foregroundStyle(K.text)
        Text(d.status).font(K.F.rowLabel).foregroundStyle(K.secondary)
      }
      Spacer(minLength: 4)
      if let level = d.battery {
        BatteryGauge(level: level, percent: d.batteryPercent, charging: d.charging)
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
