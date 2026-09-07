import Nvwa
import SwiftUI

/// 全 App 的加载指示器。视觉保持 iOS 原生圆形 `ProgressView`，只统一语义色和
/// VoiceOver 文案；业务页面不要再引入自绘帧动画或加载插画。
struct PawLoadingIndicator: View {
    private let label: String
    private let size: ControlSize
    private let tint: Color

    init(
        _ label: String = "Loading",
        size: ControlSize = .regular,
        tint: Color = Nvwa.ink
    ) {
        self.label = label
        self.size = size
        self.tint = tint
    }

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(size)
            .tint(tint)
            .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}

/// Figma `173:22196` 的页面级等待态：64×48pt 的 Nvwa Outline Button 外壳，
/// 内部保持 16pt iOS 原生圆形 `ProgressView`。页面只负责把它放到屏幕中央，
/// 不要在各业务页重复拼按钮尺寸或自定义 spinner。
struct PawAppLoadingIndicator: View {
    private let label: LocalizedStringKey

    init(_ label: LocalizedStringKey = "Loading") {
        self.label = label
    }

    var body: some View {
        NvwaButton(
            "",
            kind: .outline,
            size: .huge,
            isLoading: true,
            action: {}
        )
        .allowsHitTesting(false)
        .accessibilityLabel(Text(label))
    }
}

enum PawMotion {
    static let expand: Animation = .snappy(duration: 0.28, extraBounce: 0)
    static let selection: Animation = .snappy(duration: 0.16, extraBounce: 0)
    static let appear: Animation = .snappy(duration: 0.3, extraBounce: 0.08)
    static let disappear: Animation = .smooth(duration: 0.18)
    static let press: Animation = .snappy(duration: 0.12, extraBounce: 0)
}

enum PawFont {
    enum Weight {
        case regular
        case medium
        case semibold
        case bold

        var postScriptName: String {
            switch self {
            case .regular: "Inter-Regular"
            case .medium: "Inter-Medium"
            case .semibold: "Inter-SemiBold"
            case .bold: "Inter-Bold"
            }
        }
    }

    static func inter(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }
}
