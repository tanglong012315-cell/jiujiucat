import SwiftUI

enum NvwaModalHeaderMetrics {
  static let height: CGFloat = 66
  static let dragAreaHeight: CGFloat = 16
  static let handleWidth: CGFloat = 40
  static let handleHeight: CGFloat = 4
  static let titleRowHeight: CGFloat = 50
  static let horizontalPadding: CGFloat = 15
  static let iconSize: CGFloat = 16
  static let hitTargetSize: CGFloat = 44
  static let actionOffset: CGFloat = (hitTargetSize - iconSize) / 2
  static let topRadius: CGFloat = 16
}

/// One of the modal header's two icon slots.
///
/// Figma node `2052:7350` authors the slots as `icon: No | Left | Right` and
/// fills them with placeholder glyphs (a close and an information mark) — the
/// component makes no claim about *what* the action is, so the host supplies the
/// icon, the label, and the tone. Do not reintroduce named variants such as
/// "close": the product's sheets are dismissed by swiping the handle, and none
/// of them carries a close button (the user's decision of 2026-09-03).
public struct NvwaModalHeaderAction {
  public enum Tone {
    case normal
    case destructive
  }

  let icon: Image
  let accessibilityLabel: String
  let tone: Tone
  let action: () -> Void

  public init(
    icon: Image,
    accessibilityLabel: String,
    tone: Tone = .normal,
    action: @escaping () -> Void
  ) {
    self.icon = icon
    self.accessibilityLabel = accessibilityLabel
    self.tone = tone
    self.action = action
  }

  var foreground: Color {
    tone == .destructive ? Nvwa.sentimentNegative : Nvwa.grayPrimary
  }
}

/// Nvwa's 66-point sheet header (`2052:7350`): a drag handle over a centred
/// title, with an optional action in either side slot.
///
/// 底色是 `nvwa/bg/dialogue`，和弹层本体同一枚 token（设计 2026-09-03 的改动）。
/// **不要换回 `bg/main`**：两者在浅色下都是 `#FFFFFF`，看不出区别，但在深色下
/// `bg/main` 是纯黑 `#000000`、弹层本体是 `#262626`，头部会变成一条黑带。
public struct NvwaModalHeader: View {
  private let title: LocalizedStringKey
  private let leading: NvwaModalHeaderAction?
  private let trailing: NvwaModalHeaderAction?

  public init(
    _ title: LocalizedStringKey,
    leading: NvwaModalHeaderAction? = nil,
    trailing: NvwaModalHeaderAction? = nil
  ) {
    self.title = title
    self.leading = leading
    self.trailing = trailing
  }

  public var body: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(Nvwa.backgroundVessel)
        .frame(
          width: NvwaModalHeaderMetrics.handleWidth,
          height: NvwaModalHeaderMetrics.handleHeight
        )
        .frame(height: NvwaModalHeaderMetrics.dragAreaHeight)

      ZStack {
        Text(title)
          .font(Nvwa.titleBody)
          .tracking(-0.18)
          .foregroundStyle(Nvwa.grayPrimary)

        HStack(spacing: 20) {
          if let leading {
            iconButton(leading, edge: .leading)
          }

          Spacer(minLength: 0)

          if let trailing {
            iconButton(trailing, edge: .trailing)
          }
        }
      }
      .padding(.horizontal, NvwaModalHeaderMetrics.horizontalPadding)
      .frame(height: NvwaModalHeaderMetrics.titleRowHeight)
    }
    .frame(height: NvwaModalHeaderMetrics.height)
    .background(
      UnevenRoundedRectangle(
        topLeadingRadius: NvwaModalHeaderMetrics.topRadius,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: NvwaModalHeaderMetrics.topRadius,
        style: .continuous
      )
      .fill(Nvwa.backgroundDialogue)
    )
  }

  private func iconButton(
    _ action: NvwaModalHeaderAction,
    edge: HorizontalEdge
  ) -> some View {
    Button(action: action.action) {
      action.icon
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(
          width: NvwaModalHeaderMetrics.iconSize,
          height: NvwaModalHeaderMetrics.iconSize
        )
        .frame(
          width: NvwaModalHeaderMetrics.hitTargetSize,
          height: NvwaModalHeaderMetrics.hitTargetSize
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Figma anchors the visible 16pt glyph at the 15pt content inset.
    // Offset only the 44pt hit target so accessibility size does not move
    // the artwork 14pt toward the title.
    .offset(
      x: edge == .leading
        ? -NvwaModalHeaderMetrics.actionOffset
        : NvwaModalHeaderMetrics.actionOffset
    )
    .foregroundStyle(action.foreground)
    .accessibilityLabel(action.accessibilityLabel)
  }
}
