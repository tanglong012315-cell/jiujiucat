import Nvwa
import SwiftUI

/// 三个标签页共用的顶部导航（用户 2026-09-03 的要求：统一顶部样式）。
///
/// 左边永远是账号入口——登录了是头像，没登录是 `IconShining` 的访客态；右边是本页
/// 自己的主操作：PawFolio 与 Calculate 都是「新增持仓」，Currency 是「添加货币」。
///
/// 这里只是把登录/未登录两态收在一处：两者的差别只有左侧槽位放头像还是访客图标，
/// 几何、配色、按压反馈全在组件里，不要在这层重描。V1.1 时这段逻辑只长在
/// `PortfolioView` 里，另外两页干脆没有顶栏。
struct PawTopNavigation: View {
    let isSignedIn: Bool
    let profileInitials: String
    let profileAvatar: CatAvatar
    /// 右上角的操作。**整组可以省略**——没有右上角操作的页面就不传：
    /// 未登录的 PawFolio 页（`164:20724`）和计算页（用户 2026-09-05 要求去掉）都是这种。
    var trailingIcon: Image?
    /// 「新增持仓」用蓝色 primary，「添加货币」用中性灰——**是故意区分的**
    /// （用户 2026-09-03）：同一个「+」图标，不同的功能靠颜色分开，别看到不一致
    /// 就顺手统一掉。设计稿 `110:3141` 的 Currency 页画的就是灰色那一档。
    var trailingTone: NvwaNavigationBarActionTone = .primary
    /// 有图标但当前状态要藏起来时用（例如未登录）。没有 `trailingIcon` 时它无关紧要。
    var showsTrailing = true
    var trailingAccessibilityLabel: String?
    let onOpenAccount: () -> Void
    let onSignIn: () -> Void
    var onTrailing: () -> Void = {}

    var body: some View {
        NvwaNavigationBar(
            leading: isSignedIn
                ? .avatar(
                    initials: profileInitials,
                    image: profileAvatar.portraitImage,
                    accessibilityLabel: "Open account",
                    action: onOpenAccount
                )
                : .icon(
                    Image("IconShining"),
                    accessibilityLabel: "Log in",
                    action: onSignIn
                ),
            trailing: {
                guard showsTrailing, let trailingIcon else { return [] }
                return [
                    .icon(
                        trailingIcon,
                        tone: trailingTone,
                        accessibilityLabel: trailingAccessibilityLabel ?? "",
                        action: onTrailing
                    )
                ]
            }()
        )
    }
}

extension View {
    /// 把顶栏挂成 `safeAreaInset` 并给它铺毛玻璃（用户 2026-09-06）。
    ///
    /// 顶栏必须挂在这里、而不是压在 `VStack` 最上面：内容要能从它底下滑过去，
    /// 玻璃才有东西可糊。状态栏那一截也归这层玻璃，否则导航条上方会露出一条实色
    /// ——跟贴底那条玻璃的做法一致（`PawTabBar`）。
    func pawGlassTopBar<Bar: View>(@ViewBuilder _ bar: @escaping () -> Bar) -> some View {
        modifier(PawGlassTopBar(bar: bar))
    }
}

/// 玻璃的染色跟着滚动走。
///
/// 只铺 `.ultraThinMaterial` 的话，浅色下偏灰、深色下会把纯黑提亮到 `#1E1E1E`
/// 左右，滚到顶时两头都是一条看得出边界的色带（用户 2026-09-06 报的）。盖一层
/// 页面底色能压平它，但**常驻的染色会把玻璃也一起糊没**：实测浅色下透出来的
/// 明暗跨度从 26/255 掉到 7/255，深色只剩 3/255。
///
/// 所以染色不是常数：到顶染满（顶栏＝纯背景色，零色带），一开始滚就降下去，
/// 露出真正的玻璃。系统导航栏走的也是这个路子。
private struct PawGlassTopBar<Bar: View>: ViewModifier {
    @ViewBuilder let bar: () -> Bar
    @Environment(\.colorScheme) private var colorScheme
    /// 0＝贴在顶上，1＝已经滚开。
    @State private var scrolled: CGFloat = 0

    func body(content: Content) -> some View {
        tracking(content)
            .safeAreaInset(edge: .top, spacing: 0) {
                bar()
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Nvwa.backgroundMain.opacity(tint))
                            .ignoresSafeArea(edges: .top)
                    }
            }
    }

    @ViewBuilder
    private func tracking(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                let next = min(max(offset / Self.rampDistance, 0), 1)
                guard abs(next - scrolled) > 0.001 else { return }
                scrolled = next
            }
        } else {
            content
        }
    }

    /// 滚过这么多点玻璃就全露出来。给一小段过渡，免得刚一动就「啪」地变色；
    /// 再长就会觉得糊得慢半拍。
    private static var rampDistance: CGFloat { 24 }

    private var tint: Double {
        guard #available(iOS 18.0, *) else {
            // 17 上拿不到滚动偏移，退回常驻染色：静止时看不出色带
            // （`#FCFCFC` vs `#FFFFFF`，差 3/255），代价是玻璃一直偏弱。
            return colorScheme == .dark ? 0.88 : 0.7
        }
        // 滚开之后留的这点染色只为压住材质自身的灰，不再遮内容。深色那头材质
        // 把黑底提得更亮，所以留得多一些。
        let scrolledTint = colorScheme == .dark ? 0.55 : 0.28
        return 1 - (1 - scrolledTint) * Double(scrolled)
    }
}
