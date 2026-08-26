import SwiftUI

/// Значки пайплайна. Рисуются кодом в системе координат 24×24 из
/// спецификации и масштабируются под нужный размер.
///
/// Имя приезжает с телефона строкой. Неизвестное имя рисуется точкой, а не
/// падает: контракт может обогнать эту сборку.
struct PipeIcon: View {
  let name: String
  var size: CGFloat = K.M.rowIcon
  var color: Color = K.text

  var body: some View {
    IconShape(name: name)
      .stroke(
        color,
        style: StrokeStyle(lineWidth: size * 1.9 / 36, lineCap: .round, lineJoin: .round)
      )
      .frame(width: size, height: size)
  }
}

private struct IconShape: Shape {
  let name: String

  func path(in rect: CGRect) -> Path {
    var p = Path()
    let k = min(rect.width, rect.height) / 24
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + x * k, y: rect.minY + y * k)
    }

    switch name {
    case "coil":
      coil(&p, pt, at: 8)
      coil(&p, pt, at: 13)

    case "droplet":
      droplet(&p, pt, scale: 1, center: nil)

    case "heatbrew":
      // Режим «нагрев и пролив»: та же спираль, что у нагрева, — обе её
      // волны, — и капля под ней. С одной волной значок читался как другой
      // режим: пары волн у нагрева и одной у смеси глазу не различить.
      coil(&p, pt, at: 2.5)
      coil(&p, pt, at: 7)
      droplet(&p, pt, scale: 0.52, center: CGPoint(x: 12, y: 17.5))

    case "pause":
      p.move(to: pt(9.5, 6)); p.addLine(to: pt(9.5, 18))
      p.move(to: pt(14.5, 6)); p.addLine(to: pt(14.5, 18))

    case "streams":
      // Три струи разной длины и капли под ними.
      for (x, len) in [(8.0, 7.0), (12.0, 10.0), (16.0, 7.0)] {
        p.move(to: pt(x, 4)); p.addLine(to: pt(x, 4 + len))
        p.move(to: pt(x, 4 + len + 4.5))
        p.addLine(to: pt(x, 4 + len + 4.6))
      }

    case "speedometer":
      // Шкала — ровно верхняя половина круга, а не дуга с подобранными на
      // глаз углами. Начинаем с её левого конца: без этого дуга дорисовывала
      // себе подводку от кончика стрелки, и значок выходил кривым.
      p.move(to: pt(4, 17))
      p.addArc(
        center: pt(12, 17),
        radius: 8 * k,
        startAngle: .degrees(180),
        endAngle: .degrees(360),
        clockwise: false
      )
      // Стрелка от оси вправо-вверх: приборы показывают «много» именно так.
      p.move(to: pt(12, 17))
      p.addLine(to: pt(16.2, 11.2))

    case "scale":
      // Кухонные весы: площадка, под ней корпус с окошком.
      p.move(to: pt(3.5, 7)); p.addLine(to: pt(20.5, 7))
      p.move(to: pt(12, 7)); p.addLine(to: pt(12, 10))
      p.addRoundedRect(
        in: CGRect(origin: pt(4, 10), size: CGSize(width: 16 * k, height: 9 * k)),
        cornerSize: CGSize(width: 2 * k, height: 2 * k)
      )
      p.move(to: pt(9, 14.5)); p.addLine(to: pt(15, 14.5))

    case "alarm":
      p.addEllipse(in: CGRect(origin: pt(5, 6), size: CGSize(width: 14 * k, height: 14 * k)))
      p.move(to: pt(12, 10)); p.addLine(to: pt(12, 13)); p.addLine(to: pt(14.2, 14.4))
      p.move(to: pt(4.5, 5.5)); p.addLine(to: pt(7, 3.5))
      p.move(to: pt(19.5, 5.5)); p.addLine(to: pt(17, 3.5))

    default:
      p.addEllipse(in: CGRect(origin: pt(10.5, 11.5), size: CGSize(width: 3 * k, height: 3 * k)))
    }
    return p
  }

  /// Волна нагревателя от (4, y) до (20, y+3).
  private func coil(_ p: inout Path, _ pt: (CGFloat, CGFloat) -> CGPoint, at y: CGFloat) {
    p.move(to: pt(4, y))
    p.addCurve(to: pt(9.3, y + 3), control1: pt(6.7, y), control2: pt(6.7, y + 3))
    p.addCurve(to: pt(14.7, y), control1: pt(11.9, y + 3), control2: pt(12, y))
    p.addCurve(to: pt(20, y + 3), control1: pt(17.4, y), control2: pt(17.4, y + 3))
  }

  /// Капля: клин сверху, полукруг снизу.
  private func droplet(
    _ p: inout Path,
    _ pt: (CGFloat, CGFloat) -> CGPoint,
    scale: CGFloat,
    center: CGPoint?
  ) {
    let c = center ?? CGPoint(x: 12, y: 13)
    func s(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      pt(c.x + (x - 12) * scale, c.y + (y - 13) * scale)
    }
    let k = (pt(1, 0).x - pt(0, 0).x)
    p.move(to: s(12, 3.5))
    p.addCurve(to: s(17.5, 13), control1: s(15.2, 7.4), control2: s(17.5, 10.3))
    p.addArc(
      center: s(12, 13),
      radius: 5.5 * scale * k,
      startAngle: .degrees(0),
      endAngle: .degrees(180),
      clockwise: false
    )
    p.addCurve(to: s(12, 3.5), control1: s(6.5, 10.3), control2: s(8.8, 7.4))
  }
}
