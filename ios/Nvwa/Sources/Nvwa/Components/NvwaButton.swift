import SwiftUI

public enum NvwaButtonKind: Sendable {
    case primary
    case secondary
    case outline
    case warning
    case outlineWarning
    /// 交易页的买入/卖出主按钮。产品稿 `154:11963` / `154:12261` 把它们画成
    /// Market Buy / Market Sell 实心按钮——涨跌色是语义色，不跟随品牌色。
    case buy
    case sell
}

enum NvwaButtonBackgroundRole: Equatable, Sendable {
    case primaryGreen
    case buttonGray
    case backgroundMain
    case alphaRed20
    case marketBuy
    case marketSell

    fileprivate var color: Color {
        switch self {
        case .primaryGreen: Nvwa.primaryGreen
        case .buttonGray: Nvwa.buttonGray
        case .backgroundMain: Nvwa.backgroundMain
        case .alphaRed20: Nvwa.alphaRed20
        case .marketBuy: Nvwa.marketBuy
        case .marketSell: Nvwa.marketSell
        }
    }
}

extension NvwaButtonKind {
    var backgroundRole: NvwaButtonBackgroundRole {
        switch self {
        case .primary: .primaryGreen
        case .secondary: .buttonGray
        case .outline, .outlineWarning: .backgroundMain
        case .warning: .alphaRed20
        case .buy: .marketBuy
        case .sell: .marketSell
        }
    }
}

enum NvwaButtonMetrics {
    /// Nvwa Outline Button 使用 1pt 边框；产品实例 `173:22749` 标注的 0.5pt
    /// 已由用户在 2026-09-06 确认为设计稿错误。
    static let outlineWidth: CGFloat = 1

    static func isFigmaAuthored(
        kind: NvwaButtonKind,
        size: NvwaControlSize,
        hasLeadingIcon: Bool
    ) -> Bool {
        guard hasLeadingIcon else { return true }
        return switch size {
        case .huge, .large:
            kind == .outline
        case .small, .tiny:
            true
        }
    }

    static func iconSpacing(kind: NvwaButtonKind, size: NvwaControlSize) -> CGFloat {
        kind == .outline && size == .huge ? 4 : 8
    }

    static func typography(kind: NvwaButtonKind, size: NvwaControlSize) -> NvwaTypographyToken {
        switch size {
        case .huge:
            Nvwa.Typography.bodyLargeSemibold
        case .large:
            Nvwa.Typography.bodyMediumSemibold
        case .small:
            kind == .outlineWarning
                ? Nvwa.Typography.bodyMedium
                : Nvwa.Typography.bodyMediumSemibold
        case .tiny:
            Nvwa.Typography.bodySmall
        }
    }

    static func fontSize(kind: NvwaButtonKind, size: NvwaControlSize) -> CGFloat {
        typography(kind: kind, size: size).size
    }

    static func usesSemibold(kind: NvwaButtonKind, size: NvwaControlSize) -> Bool {
        typography(kind: kind, size: size).weight == .semibold
    }

    static func tracking(kind: NvwaButtonKind, size: NvwaControlSize) -> CGFloat {
        typography(kind: kind, size: size).tracking
    }
}

public struct NvwaButton: View {
    private let title: LocalizedStringKey
    private let kind: NvwaButtonKind
    private let size: NvwaControlSize
    private let leadingIcon: Image?
    private let expandsHorizontally: Bool
    /// 进行中态：标题和图标让位给一枚菊花，按钮尺寸、颜色、形状原样不变。
    /// 不额外接管 `disabled`——那仍然由调用方自己控制（通常本来就已经在控制）。
    private let isLoading: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: LocalizedStringKey,
        kind: NvwaButtonKind = .primary,
        size: NvwaControlSize = .large,
        leadingIcon: Image? = nil,
        expandsHorizontally: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.size = size
        self.leadingIcon = leadingIcon
        self.expandsHorizontally = expandsHorizontally
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(
                spacing: leadingIcon == nil
                    ? 0
                    : NvwaButtonMetrics.iconSpacing(kind: kind, size: size)
            ) {
                if isLoading {
                    // 用户 2026-09-03：进行中不要写「Saving…」这类文案，换成原生菊花。
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(foreground)
                        .frame(width: 16, height: 16)
                } else {
                    if let leadingIcon {
                        leadingIcon
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }

                    Text(title)
                        .font(textFont)
                        .tracking(tracking)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: expandsHorizontally ? .infinity : nil)
            .frame(height: size.height)
            .background(background, in: Capsule())
            .overlay {
                if let stroke {
                    Capsule().strokeBorder(stroke, lineWidth: NvwaButtonMetrics.outlineWidth)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(NvwaPressButtonStyle())
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var textFont: Font {
        Nvwa.font(
            NvwaButtonMetrics.fontSize(kind: kind, size: size),
            weight: NvwaButtonMetrics.usesSemibold(kind: kind, size: size)
                ? .semibold
                : .regular
        )
    }

    private var tracking: CGFloat {
        NvwaButtonMetrics.tracking(kind: kind, size: size)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .buy, .sell: Nvwa.colorOnBlue
        case .secondary, .outline: Nvwa.grayPrimary
        case .warning, .outlineWarning: Nvwa.sentimentNegative
        }
    }

    private var background: Color {
        kind.backgroundRole.color
    }

    private var stroke: Color? {
        switch kind {
        case .outline: Nvwa.line
        case .outlineWarning: Nvwa.sentimentNegative
        default: nil
        }
    }
}

public struct NvwaPressButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.12, extraBounce: 0), value: configuration.isPressed)
    }
}
