#if DEBUG
import SwiftUI

/// Съёмочный стенд экранов таймера.
///
/// Экраны часов — проекция снимка с телефона, и без пары рядом показали бы
/// «нет телефона». Чтобы отснять таймер в симуляторе, здесь лежат два готовых
/// снимка (свёрнутый и взведённый), снятые тем же билдером `watch_snapshot.dart`,
/// что и в бою, — так картинка гарантированно совпадает с контрактом.
///
/// Весь файл — под `#if DEBUG`: в релиз не попадает ни строкой. Выбор экрана
/// приходит переменной окружения `WATCH_PREVIEW`, чтобы каждый кадр снимался
/// отдельным запуском, без автоматизации касаний.
enum PreviewHarness {
  static var route: String? {
    let v = ProcessInfo.processInfo.environment["WATCH_PREVIEW"] ?? ""
    return v.isEmpty ? nil : v
  }

  static let setupJSON = #"""
{"v":3,"link":"connected","scanning":false,"accent":"#FFB100","accentText":"#FFB000","devices":[{"id":"mock-k2pro","kind":"machine","name":"Моя K2","rssi":null,"connected":true,"known":true,"status":"Подключено","battery":4,"batteryPercent":null,"charging":false}],"device":{"id":"mock-k2pro","name":"Моя K2","battery":4,"batteryPercent":null,"charging":false,"state":"Сон","running":false,"model":"PCM03SPRO","error":null},"scale":null,"steps":[{"id":"alarm","icon":"alarm","label":"ЗАПУСК","value":"Выкл","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":true,"editor":"timer","editValue":420,"min":0,"max":1439,"step":15,"unit":"","hint":"В это время машина начнёт выбранный цикл."},{"id":"mode","icon":"heatbrew","label":"РЕЖИМ","value":"Нагрев + пролив","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":true,"editor":"mode","editValue":1,"min":0,"max":0,"step":1,"unit":"","hint":"Что запускает кнопка"},{"id":"heat","icon":"coil","label":"НАГРЕВ","value":"24 → 92°C","tone":"#FF9E70","mark":"upcoming","progress":null,"highlighted":false,"editable":true,"editor":"stepper","editValue":92,"min":38,"max":95,"step":1,"unit":"°C","hint":"температура воды"},{"id":"pour","icon":"streams","label":"ВЕСЬ ПРОЛИВ","value":"80 сек","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":true,"editor":"group","editValue":0,"min":0,"max":0,"step":1,"unit":"","hint":"","children":[{"id":"wetting","icon":"droplet","label":"СМАЧИВАНИЕ","value":"5 сек","tone":"#7CBBFF","mark":"upcoming","progress":null,"highlighted":false,"editable":true,"editor":"stepper","editValue":5,"min":3,"max":30,"step":1,"unit":"сек","hint":"вода смачивает таблетку кофе"},{"id":"pause","icon":"pause","label":"ПАУЗА","value":"5 сек","tone":"#7CBBFF","mark":"upcoming","progress":null,"highlighted":false,"editable":true,"editor":"stepper","editValue":5,"min":0,"max":60,"step":1,"unit":"сек","hint":"кофе набухает перед проливом"},{"id":"extraction","icon":"streams","label":"ЭКСТРАКЦИЯ","value":"70 сек","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":true,"editor":"stepper","editValue":70,"min":20,"max":120,"step":1,"unit":"сек","hint":"основной пролив в чашку"},{"id":"flow","icon":"speedometer","label":"ДАВЛЕНИЕ","value":"7 / 15","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":true,"editor":"stepper","editValue":7,"min":1,"max":15,"step":1,"unit":"","hint":"ступень 1–15, скорость подачи воды"}]}],"modes":[{"value":0,"label":"Нагрев","icon":"coil","accent":"#FF7A3D","accentText":"#FF9E70","selected":false},{"value":1,"label":"Нагрев + пролив","icon":"heatbrew","accent":"#FFB100","accentText":"#FFB000","selected":true},{"value":2,"label":"Пролив","icon":"droplet","accent":"#3D9BFF","accentText":"#7CBBFF","selected":false}],"cta":{"kind":"start","label":"Старт","bg":"#FFB100","fg":"#0D0F12","busy":false,"hold":true},"timer":{"armed":false,"presets":[5,10,20,30],"presetUnit":"мин","hint":"Машина начнёт заранее, чтобы кофе был готов точно к сроку.","byTime":420,"readyLabel":"Готов через","readyInSeconds":null,"startLine":null,"cancel":"Отменить запуск","enable":"Включить"},"strings":{"machines":"Машины","searching":"Ищем…","noPhone":"Нет связи","connected":"Подключено","timer":"Таймер","timerOff":"Выкл","byTime":"Ко времени","hours":"ч","minutes":"мин","mode":"Что запускать","enable":"Включён","disable":"Отмена","connecting":"Подключение…","empty":"Поиск устройств поблизости…","scale":"Весы","tare":"Тара","weight":"Вес","target":"Цель","autoStop":"Отсечка по весу","noScale":"Весов нет","asleep":"спят"}}
"""#

  static let armedJSON = #"""
{"v":3,"link":"connected","scanning":false,"accent":"#FFB100","accentText":"#FFB000","devices":[{"id":"mock-k2pro","kind":"machine","name":"Моя K2","rssi":null,"connected":true,"known":true,"status":"Подключено","battery":4,"batteryPercent":null,"charging":false}],"device":{"id":"mock-k2pro","name":"Моя K2","battery":4,"batteryPercent":null,"charging":false,"state":"Сон","running":false,"model":"PCM03SPRO","error":null},"scale":null,"steps":[{"id":"alarm","icon":"alarm","label":"ЗАПУСК","value":"22:56","tone":"#FFB000","mark":"active","progress":1.0,"highlighted":true,"editable":false,"editor":"timer","editValue":1376,"min":0,"max":1439,"step":15,"unit":"","hint":"В это время машина начнёт выбранный цикл."},{"id":"mode","icon":"heatbrew","label":"РЕЖИМ","value":"Нагрев + пролив","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":false,"editor":"mode","editValue":1,"min":0,"max":0,"step":1,"unit":"","hint":"Что запускает кнопка"},{"id":"heat","icon":"coil","label":"НАГРЕВ","value":"24 → 92°C","tone":"#FF9E70","mark":"upcoming","progress":null,"highlighted":false,"editable":false,"editor":"stepper","editValue":92,"min":38,"max":95,"step":1,"unit":"°C","hint":"температура воды"},{"id":"pour","icon":"streams","label":"ВЕСЬ ПРОЛИВ","value":"80 сек","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":false,"editor":"group","editValue":0,"min":0,"max":0,"step":1,"unit":"","hint":"","children":[{"id":"wetting","icon":"droplet","label":"СМАЧИВАНИЕ","value":"5 сек","tone":"#7CBBFF","mark":"upcoming","progress":null,"highlighted":false,"editable":false,"editor":"stepper","editValue":5,"min":3,"max":30,"step":1,"unit":"сек","hint":"вода смачивает таблетку кофе"},{"id":"pause","icon":"pause","label":"ПАУЗА","value":"5 сек","tone":"#7CBBFF","mark":"upcoming","progress":null,"highlighted":false,"editable":false,"editor":"stepper","editValue":5,"min":0,"max":60,"step":1,"unit":"сек","hint":"кофе набухает перед проливом"},{"id":"extraction","icon":"streams","label":"ЭКСТРАКЦИЯ","value":"70 сек","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":false,"editor":"stepper","editValue":70,"min":20,"max":120,"step":1,"unit":"сек","hint":"основной пролив в чашку"},{"id":"flow","icon":"speedometer","label":"ДАВЛЕНИЕ","value":"7 / 15","tone":"#FFB000","mark":"upcoming","progress":null,"highlighted":false,"editable":false,"editor":"stepper","editValue":7,"min":1,"max":15,"step":1,"unit":"","hint":"ступень 1–15, скорость подачи воды"}]}],"modes":[{"value":0,"label":"Нагрев","icon":"coil","accent":"#FF7A3D","accentText":"#FF9E70","selected":false},{"value":1,"label":"Нагрев + пролив","icon":"heatbrew","accent":"#FFB100","accentText":"#FFB000","selected":true},{"value":2,"label":"Пролив","icon":"droplet","accent":"#3D9BFF","accentText":"#7CBBFF","selected":false}],"cta":{"kind":"cancelAlarm","label":"Отменить запуск","bg":"#E0352B","fg":"#FFFFFF","busy":false,"hold":false},"timer":{"armed":true,"presets":[5,10,20,30],"presetUnit":"мин","hint":"Машина начнёт заранее, чтобы кофе был готов точно к сроку.","byTime":1376,"readyLabel":"Готов через","readyInSeconds":350,"startLine":"Старт в 22:56 · Нагрев + пролив","cancel":"Отменить запуск","enable":"Включить"},"strings":{"machines":"Машины","searching":"Ищем…","noPhone":"Нет связи","connected":"Подключено","timer":"Таймер","timerOff":"Выкл","byTime":"Ко времени","hours":"ч","minutes":"мин","mode":"Что запускать","enable":"Включён","disable":"Отмена","connecting":"Подключение…","empty":"Поиск устройств поблизости…","scale":"Весы","tare":"Тара","weight":"Вес","target":"Цель","autoStop":"Отсечка по весу","noScale":"Весов нет","asleep":"спят"}}
"""#

  static func snapshot(_ json: String) -> Snapshot? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
  }
}

/// Корневой экран стенда: подставляет снимок и открывает нужный экран.
struct PreviewRoot: View {
  @EnvironmentObject private var link: WatchLink
  let route: String

  var body: some View {
    NavigationStack {
      screen
    }
    .tint(K.text)
    .onAppear {
      let json = route == "timerArmed"
        ? PreviewHarness.armedJSON : PreviewHarness.setupJSON
      if let snap = PreviewHarness.snapshot(json) { link.injectPreview(snap) }
    }
  }

  @ViewBuilder private var screen: some View {
    switch route {
    case "timerByTime":
      if let timer = link.snapshot?.timer { ByTimeView(timer: timer) }
    case "widget":
      WidgetGallery()
    case "icons":
      IconGallery()
    default:
      TimerView()
    }
  }
}

/// Стенд значков пайплайна: все глифы разом, крупно, чтобы судить о форме.
struct IconGallery: View {
  private let items: [(String, String)] = [
    ("coil", "Нагрев"),
    ("heatbrew", "Нагрев+пролив"),
    ("droplet", "Пролив"),
    ("streams", "Экстракция"),
    ("speedometer", "Давление"),
    ("pause", "Пауза"),
    ("alarm", "Таймер"),
    ("scale", "Весы"),
  ]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
        ForEach(items, id: \.0) { name, label in
          VStack(spacing: 3) {
            PipeIcon(name: name, size: 26, color: K.text)
            Text(label)
              .font(.system(size: 11))
              .foregroundStyle(K.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
          .background(K.control, in: RoundedRectangle(cornerRadius: 10))
        }
      }
      .padding(6)
    }
    .background(K.bg)
    .navigationTitle("Значки")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Стенд Smart Stack: те же вьюхи виджета, что и в расширении, в подобии
/// карточек стопки — по одной на каждое состояние.
struct WidgetGallery: View {
  private var running: WidgetStatus {
    WidgetStatus(
      updatedAt: Date(), kind: "running", title: "Моя K2", line: "Пролив",
      symbol: "drop.fill", accentHex: "#FFB100", deadline: nil
    )
  }
  private var armed: WidgetStatus {
    WidgetStatus(
      updatedAt: Date(), kind: "armed", title: "Моя K2", line: "Готов через",
      symbol: "clock", accentHex: "#FFB100",
      deadline: Date().addingTimeInterval(350)
    )
  }
  /// Устаревший — виджет становится запускалкой.
  private var stale: WidgetStatus {
    WidgetStatus(
      updatedAt: Date().addingTimeInterval(-3600), kind: "running", title: "Моя K2",
      line: "Пролив", symbol: "drop.fill", accentHex: "#FFB100", deadline: nil
    )
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        card { WidgetRectangular(status: running) }
        card { WidgetRectangular(status: armed) }
        card { WidgetRectangular(status: stale) }
        HStack(spacing: 10) {
          circle { WidgetCircular(status: running) }
          circle { WidgetCircular(status: stale) }
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
    }
    .background(K.bg)
    .navigationTitle("Smart Stack")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
    content()
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(K.control, in: RoundedRectangle(cornerRadius: 12))
  }

  private func circle<V: View>(@ViewBuilder _ content: () -> V) -> some View {
    content()
      .frame(width: 52, height: 52)
      .padding(6)
      .background(K.control, in: RoundedRectangle(cornerRadius: 12))
  }
}
#endif
