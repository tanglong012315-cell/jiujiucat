import SwiftUI

enum NvwaScrollButtonMetrics {
    static let height: CGFloat = 56
    static let knobDiameter: CGFloat = 56
    /// 稿子画的是 345——页面左右各留 16 之后的宽度。组件本身撑满可用宽度，
    /// 这个值只用来记录来源和给目录页示例用。
    static let authoredWidth: CGFloat = 345
    static let spinnerSize: CGFloat = 24
    /// 已滑过的部分，`2243:654` 的 BG/Vessel 覆盖层：左端到滑块**右**沿，
    /// 不是到滑块中心。
    static let trailExtendsToKnobTrailingEdge = true
    /// 拖到多远算确认。稿子只画了 Start / Scrolling / Finish 三个静态状态，没有标
    /// 阈值——这是代码定的：0.9 让最后一小段可以甩过去，又不至于半路松手就触发。
    static let confirmationProgress: CGFloat = 0.9

    static func travel(inWidth width: CGFloat) -> CGFloat {
        max(0, width - knobDiameter)
    }
}

/// Nvwa 的滑动确认条（`2243:704` Scroll button），三个状态对应同一个组件的三段过程：
///
/// - `Start` `2243:703`：滑块停在左端，轨道上是居中的提示文案；
/// - `Scrolling` `2243:702`：滑块跟手，左侧覆盖层保持 BG/Vessel；
/// - `Finish` `2243:701`：滑块停在右端，箭头换成菊花，轨迹铺满。
///
/// 滑块本身就是 Key Feature 的 `Send`（`2029:9081`，56pt 容器 + 28pt 字形），
/// 不要另画一枚箭头。
///
/// 确认之后滑块会**留在右端**——这一步是不可撤销的操作，弹回去会让人以为没生效。
/// 宿主把 `isLoading` 置回 `false` 时组件才回到 `Start`（通常是请求失败、要重来）；
/// 成功的话宿主一般会直接离开这个页面。
public struct NvwaScrollButton: View {
    private let title: LocalizedStringKey
    private let isLoading: Bool
    private let onConfirm: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var hasConfirmed = false
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: LocalizedStringKey,
        isLoading: Bool = false,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.onConfirm = onConfirm
    }

    public var body: some View {
        GeometryReader { proxy in
            let travel = NvwaScrollButtonMetrics.travel(inWidth: proxy.size.width)
            let offset = isSettled ? travel : min(dragOffset, travel)

            ZStack(alignment: .leading) {
                Text(title)
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium)
                    .foregroundStyle(Nvwa.graySecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(Nvwa.backgroundVessel)
                    .frame(width: offset + NvwaScrollButtonMetrics.knobDiameter)

                knob(travel: travel)
                    .offset(x: offset)
            }
            .frame(width: proxy.size.width, height: NvwaScrollButtonMetrics.height)
        }
        .frame(height: NvwaScrollButtonMetrics.height)
        .background(Nvwa.backgroundVessel, in: Capsule())
        .opacity(isEnabled ? 1 : 0.45)
        // 单参数写法：包同时支持 macOS 13，双参数的 `onChange` 要 macOS 14。
        .onChange(of: isLoading) { isLoadingNow in
            // 宿主把进行中收回去 = 这次没成，退回起点重来。
            guard !isLoadingNow, hasConfirmed else { return }
            withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                hasConfirmed = false
                dragOffset = 0
            }
        }
        // 拖拽对 VoiceOver 不可用，所以整条对外是一个按钮，双击等价于滑到底。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isLoading ? "In progress" : "")
        .accessibilityAction {
            guard isInteractive else { return }
            confirm()
        }
    }

    /// 滑块落定：拖到底之后，或者进行中。
    private var isSettled: Bool {
        hasConfirmed || isLoading
    }

    private var isInteractive: Bool {
        isEnabled && !isSettled
    }

    @ViewBuilder
    private func knob(travel: CGFloat) -> some View {
        Group {
            if isSettled {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Nvwa.colorOnBlue)
                    .frame(
                        width: NvwaScrollButtonMetrics.spinnerSize,
                        height: NvwaScrollButtonMetrics.spinnerSize
                    )
                    .frame(
                        width: NvwaScrollButtonMetrics.knobDiameter,
                        height: NvwaScrollButtonMetrics.knobDiameter
                    )
                    .background(Nvwa.primaryGreen, in: Circle())
            } else {
                // `Send` 本身是朝上的箭头；稿子把整枚实例转了 -90°（`2243:640`）
                // 让它指向滑动方向。圆底是对称的，转整枚不影响其它。
                NvwaKeyFeatureIcon(.send)
                    .rotationEffect(.degrees(90))
            }
        }
        .contentShape(Circle())
        .gesture(
            // 滑块本身会随 `dragOffset` 移动。在它的 local coordinate space
            // 里读 translation，真机上会因视图同时移动而抖动甚至到不了终点；
            // global 坐标从按下到松手始终稳定。
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    guard isInteractive else { return }
                    dragOffset = min(max(0, value.translation.width), travel)
                }
                .onEnded { _ in
                    guard isInteractive else { return }
                    let reached = travel > 0
                        && dragOffset >= travel * NvwaScrollButtonMetrics.confirmationProgress
                    if reached {
                        confirm()
                    } else {
                        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private func confirm() {
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            hasConfirmed = true
        }
        onConfirm()
    }
}
