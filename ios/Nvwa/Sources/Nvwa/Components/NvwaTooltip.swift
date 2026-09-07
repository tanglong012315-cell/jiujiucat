import SwiftUI

public enum NvwaTooltipPlacement: Sendable {
    /// The bubble sits above its anchor, with the arrow on the bottom edge.
    case top
    /// The bubble sits below its anchor, with the arrow on the top edge.
    case bottom
    /// The bubble sits left of its anchor, with the arrow on the right edge.
    case left
    /// The bubble sits right of its anchor, with the arrow on the left edge.
    case right
}

public struct NvwaTooltip: View {
    private let title: String
    private let message: String
    private let placement: NvwaTooltipPlacement
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        title: String,
        message: String,
        placement: NvwaTooltipPlacement = .top,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.placement = placement
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        Group {
            switch placement {
            case .top:
                VStack(spacing: 0) {
                    bubble
                    arrow.scaleEffect(x: -1, y: 1)
                }
            case .bottom:
                VStack(spacing: 0) {
                    arrow.rotationEffect(.degrees(180))
                    bubble
                }
            case .left:
                HStack(spacing: 0) {
                    bubble
                    arrow
                        .scaleEffect(x: -1, y: 1)
                        .rotationEffect(.degrees(-90))
                }
            case .right:
                HStack(spacing: 0) {
                    arrow
                        .scaleEffect(x: -1, y: 1)
                        .rotationEffect(.degrees(90))
                    bubble
                }
            }
        }
        .shadow(
            color: Color(.sRGB, red: 69 / 255, green: 71 / 255, blue: 69 / 255, opacity: 0.2),
            radius: 20
        )
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(title))
                    .font(Nvwa.titleBody)
                    .tracking(-0.18)
                    .foregroundStyle(Nvwa.grayPrimary)
                    .frame(minHeight: 24, alignment: .topLeading)

                Text(LocalizedStringKey(message))
                    .font(Nvwa.bodyMedium)
                    .tracking(0.14)
                    .lineSpacing(5)
                    .foregroundStyle(Nvwa.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(LocalizedStringKey(actionTitle))
                        .font(Nvwa.bodyMediumSemibold)
                        .tracking(0.175)
                        .underline()
                        .frame(minHeight: 22)
                }
                .foregroundStyle(Nvwa.grayPrimary)
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 283, alignment: .leading)
        .background(
            Nvwa.backgroundMain,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var arrow: some View {
        NvwaInternalAsset.tooltipArrow.image
            .renderingMode(.template)
            .resizable()
            // Figma lays the 19.5×9.75 exported leaf outside a 17×9 slot.
            // Preserve both boxes instead of stretching the SVG into the slot.
            .frame(width: 19.5, height: 9.75001)
            .offset(x: -0.5, y: -0.375)
            .frame(width: 17, height: 9)
            .foregroundStyle(Nvwa.backgroundMain)
            .frame(
                width: placement == .left || placement == .right ? 9 : 17,
                height: placement == .left || placement == .right ? 17 : 9
            )
    }
}
