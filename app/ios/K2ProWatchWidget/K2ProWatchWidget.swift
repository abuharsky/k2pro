import SwiftUI
import WidgetKit

/// Виджет Smart Stack. Читает статус из общего контейнера и рисует его; тап
/// запускает приложение (у виджета часового приложения это поведение по
/// умолчанию). Начинку рисуют общие вьюхи — те же снимаются на скриншот.
struct K2ProWatchWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetStatus.kind, provider: Provider()) { entry in
      WidgetView(status: entry.status)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("BetterCup")
    .description("Статус пролива и быстрый запуск")
    .supportedFamilies([
      .accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner,
    ])
  }
}

struct WidgetEntry: TimelineEntry {
  let date: Date
  let status: WidgetStatus?
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> WidgetEntry {
    WidgetEntry(date: Date(), status: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
    completion(WidgetEntry(date: Date(), status: WidgetStatus.load()))
  }

  /// Два кадра: что мы знаем сейчас — и запускалка на час, когда верить этому
  /// уже нельзя.
  ///
  /// Живого здесь нет намеренно. Поправку виджету не доставить: пока
  /// приложение не стоит на активном циферблате, телефон лишён первоклассного
  /// пробуждения, а обычная очередь доезжает когда доедет — заметно позже, чем
  /// кончается пролив. Карточка, которая продолжала бы отыгрывать расписание,
  /// просто врала бы уверенным голосом. Пусть лучше молчит и открывает
  /// приложение по тапу.
  func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
    let now = Date()
    let status = WidgetStatus.load()
    var entries = [WidgetEntry(date: now, status: status)]
    var horizon = now.addingTimeInterval(WidgetStatus.staleAfter)

    if let status, !status.isStale {
      // Погаснуть карточка умеет сама: кадр на час устаревания не требует
      // ни доставки, ни пробуждения.
      entries.append(WidgetEntry(date: status.expiresAt, status: status.faded))
      horizon = status.expiresAt.addingTimeInterval(60)
    }

    completion(Timeline(entries: entries, policy: .after(horizon)))
  }
}

/// Выбор формата по семейству. Начинки — общие вьюхи из приложения.
struct WidgetView: View {
  @Environment(\.widgetFamily) private var family
  let status: WidgetStatus?

  var body: some View {
    switch family {
    case .accessoryCircular: WidgetCircular(status: status)
    case .accessoryInline: WidgetInline(status: status)
    case .accessoryCorner: WidgetCorner(status: status)
    default: WidgetRectangular(status: status)
    }
  }
}
