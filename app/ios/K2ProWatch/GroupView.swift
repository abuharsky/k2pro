import SwiftUI

/// Экран группы: ряды, свёрнутые на главном в одну строку.
///
/// Сейчас такая группа одна — пролив с его смачиванием, паузой, экстракцией и
/// напором. Но экран про это не знает: он рисует то, что приехало вложенным.
struct GroupView: View {
  @EnvironmentObject private var link: WatchLink
  let groupId: String
  @Binding var path: [Route]

  private var group: Step? { link.snapshot?.step(groupId) }

  var body: some View {
    Group {
      if let group, let children = group.children {
        ScrollView {
          LazyVStack(spacing: 5) {
            ForEach(children) { child in
              StepRow(step: child) {
                guard child.editable else { return }
                path.append(.step(child.id))
              }
            }
          }
          .padding(.horizontal, 4)
          .padding(.bottom, 4)
        }
        .background(K.bg)
      } else {
        NoPhoneView()
      }
    }
    .navigationTitle(group?.label.capitalizedFirst ?? "")
    .navigationBarTitleDisplayMode(.inline)
  }
}
