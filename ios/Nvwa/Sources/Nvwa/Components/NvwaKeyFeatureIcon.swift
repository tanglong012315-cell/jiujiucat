import SwiftUI

/// The nine illustration-like Key Feature icons authored in Figma node
/// `2029:9063`. Unlike general UI icons, their glyph geometry belongs to Nvwa.
public enum NvwaKeyFeatureIconKind: CaseIterable, Hashable, Sendable {
    case invest
    case keep
    case convert
    case send
    case receive
    case add
    case close
    case tick
    case warning

    var glyphSize: CGFloat {
        switch self {
        case .invest, .keep, .convert, .send, .receive, .add:
            28
        case .close, .tick, .warning:
            24
        }
    }

    var containerSize: CGFloat {
        switch self {
        case .invest, .keep, .convert, .send, .receive, .add:
            56
        case .close, .tick, .warning:
            48
        }
    }

    var backgroundRole: NvwaKeyFeatureColorRole {
        switch self {
        case .invest, .keep, .convert, .send, .receive, .tick:
            .primaryGreen
        case .add:
            .backgroundVessel
        case .close:
            .sentimentNegative
        case .warning:
            .sentimentWarning
        }
    }

    var foregroundRole: NvwaKeyFeatureColorRole {
        switch self {
        case .invest, .keep, .convert, .send, .receive:
            .colorOnBlue
        case .add:
            .grayPrimary
        case .close, .tick:
            .literalWhite
        case .warning:
            .black
        }
    }

    fileprivate var asset: NvwaInternalAsset {
        switch self {
        case .invest: .keyFeatureInvest
        case .keep: .keyFeatureKeep
        case .convert: .keyFeatureConvert
        case .send, .receive: .keyFeatureSend
        case .add: .keyFeatureAdd
        case .close: .keyFeatureClose
        case .tick: .keyFeatureTick
        case .warning: .keyFeatureWarning
        }
    }

    fileprivate var flipsVertically: Bool {
        self == .receive
    }

    fileprivate var background: Color {
        backgroundRole.color
    }

    fileprivate var foreground: Color {
        foregroundRole.color
    }
}

enum NvwaKeyFeatureColorRole: Equatable, Sendable {
    case primaryGreen
    case colorOnBlue
    case backgroundVessel
    case grayPrimary
    case sentimentNegative
    case sentimentWarning
    case black
    case literalWhite

    fileprivate var color: Color {
        switch self {
        case .primaryGreen: Nvwa.primaryGreen
        case .colorOnBlue: Nvwa.colorOnBlue
        case .backgroundVessel: Nvwa.backgroundVessel
        case .grayPrimary: Nvwa.grayPrimary
        case .sentimentNegative: Nvwa.sentimentNegative
        case .sentimentWarning: Nvwa.sentimentWarning
        case .black: Nvwa.textBlack
        case .literalWhite: .white
        }
    }
}

/// Renders the exact Figma-authored glyph inside its token-bound container.
/// General-purpose icons elsewhere in Nvwa continue to be supplied by hosts.
public struct NvwaKeyFeatureIcon: View {
    private let kind: NvwaKeyFeatureIconKind
    private let containerSize: CGFloat
    private let background: Color

    public init(_ kind: NvwaKeyFeatureIconKind) {
        self.init(kind, containerSize: kind.containerSize, background: kind.background)
    }

    /// 缩放版：`NvwaHint` 的提示标记就是这枚 Warning 插画缩到 12pt，底色改成
    /// 提示等级的颜色。字形与容器的比例按稿子锁死（24/48 = 12/24），不要各画一套。
    init(
        _ kind: NvwaKeyFeatureIconKind,
        containerSize: CGFloat,
        background: Color
    ) {
        self.kind = kind
        self.containerSize = containerSize
        self.background = background
    }

    private var glyphSize: CGFloat {
        containerSize * (kind.glyphSize / kind.containerSize)
    }

    public var body: some View {
        kind.asset.image
            .renderingMode(.template)
            .resizable()
            .frame(width: glyphSize, height: glyphSize)
            .scaleEffect(x: 1, y: kind.flipsVertically ? -1 : 1)
            .foregroundStyle(kind.foreground)
            .frame(width: containerSize, height: containerSize)
            .background(background, in: Circle())
    }
}
