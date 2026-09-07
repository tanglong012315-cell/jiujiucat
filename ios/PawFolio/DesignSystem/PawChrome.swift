import Nvwa
import SwiftUI

// Web 的固定框架：顶部 `.topbar` 与贴底 `.tabbar`。三个标签页与 Web 一致，
// 账号入口在头部头像上，不是第四个标签页——见 `AGENTS.md` 的 Design direction。

/// Web 的三个标签页。
enum PawTab: String, CaseIterable, Hashable {
    case portfolio
    case calculator
    case exchangeRate

    /// Figma `63:7007` 等页面的底部导航写的是 PawFolio / Calculate / Currency。
    /// 控件本身按 AGENTS.md 仍是系统 `TabView`、不照 Figma 复刻，这里改的只是文案。
    var title: LocalizedStringKey {
        switch self {
        case .portfolio: "tab.portfolio"
        case .calculator: "tab.calculate"
        case .exchangeRate: "tab.currency"
        }
    }

    /// Web 用的 Remix Icon，同名 SVG 已打包进 Asset Catalog。
    var iconName: String {
        switch self {
        case .portfolio: "IconCoin"                 // ri-coin-line
        case .calculator: "IconIncreaseDecrease"    // ri-increase-decrease-line
        case .exchangeRate: "IconMoneyDollarCircle" // ri-money-dollar-circle-line
        }
    }
}

/// Web 的主题切换：手动选择存本地，未选择时跟随系统。
@MainActor
final class NvwaThemeController: ObservableObject {
    private enum Storage {
        static let key = "pawfolio.theme"
    }

    @Published var preference: ColorScheme? {
        didSet { persist() }
    }

    init() {
        // 直接初始化底层存储：`preference` 是 Optional，声明时就隐式是 nil，
        // 在 init 里再赋值会触发 didSet，把「跟随系统」当成一次显式选择写进本地，
        // 结果是首次启动后就被锁在当时的外观上。
        let stored = UserDefaults.standard.string(forKey: Storage.key)
        _preference = Published(
            initialValue: stored == "light" ? .light : stored == "dark" ? .dark : nil
        )
    }

    func toggle(systemScheme: ColorScheme) {
        let current = preference ?? systemScheme
        preference = current == .dark ? .light : .dark
    }

    private func persist() {
        switch preference {
        case .light: UserDefaults.standard.set("light", forKey: Storage.key)
        case .dark: UserDefaults.standard.set("dark", forKey: Storage.key)
        case .none: UserDefaults.standard.removeObject(forKey: Storage.key)
        @unknown default: break
        }
    }

    /// 目标模式的图标：显示「点了会变成什么」而不是「现在是什么」——
    /// 浅色下显示月亮（点它变深色），深色下显示太阳（点它变浅色）。
    /// 两种读法都说得通，这是用户 2026-09-03 定的那一种（V1.2.2 顶栏新增
    /// 图标 `107:2598`「Theme」参考图里画了两枚图标，没写清映射关系）。
    func targetAppearanceIconName(systemScheme: ColorScheme) -> String {
        (preference ?? systemScheme) == .dark ? "IconSun" : "IconMoonFill"
    }
}

/// App 内语言。rawValue 保持旧偏好兼容，`localeIdentifier` 使用标准 BCP-47 标识。
enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh"
    case english = "en"

    var id: Self { self }

    var localeIdentifier: String {
        switch self {
        case .chinese: "zh-Hans"
        case .english: "en"
        }
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        }
    }

    /// 对应的货币代码——只用来去 `CurrencyCatalog` 里查现成的国旗，不是说
    /// 这门语言等于这个货币。
    private var currencyCode: CurrencyCode {
        switch self {
        case .chinese: "CNY"
        case .english: "GBP"
        }
    }

    /// `Assets.xcassets` 里的圆形国旗。**直接问 `CurrencyCatalog` 要**，不在这里
    /// 另存一份 "FlagCN"/"FlagGB" 字符串——货币页已经是这两个资源名的唯一出处，
    /// 两处各写一份迟早会分叉（用户 2026-09-03：国旗资源要从货币页那边取现成的）。
    var flagAssetName: String {
        CurrencyCatalog.info(for: currencyCode)?.flagAssetName ?? CurrencyCatalog.unknownFlagAssetName
    }
}

@MainActor
final class LanguagePreferenceStore: ObservableObject {
    private enum Storage {
        static let key = "pawfolio.language"
    }

    private let defaults: UserDefaults

    @Published var selected: AppLanguage {
        didSet { defaults.set(selected.rawValue, forKey: Storage.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Storage.key)
        // 保持既有默认值，不擅自改动老用户的语言；用户在 App 内选择后立即生效并持久化。
        _selected = Published(initialValue: stored.flatMap(AppLanguage.init(rawValue:)) ?? .english)
    }
}

/// Web `.tabbar` 的 iOS 17–25 回退实现：贴底毛玻璃条，顶部一条发丝线。
///
/// iOS 26 起**不再走这里**。系统的 `TabView` 自带 Liquid Glass 标签栏——跟手拖动的
/// 玻璃胶囊、边缘色散、松手回弹全部由系统渲染，手搓版做不到同等效果（尤其是色散，
/// 那是 Apple 玻璃 shader 的逐通道采样，第三方拿不到）。见 `RootTabView.nativeShell`
/// 和 `AGENTS.md` 的 Design direction（2026-08-31 的决定）。
struct PawTabBar: View {
    @Binding var selection: PawTab

    /// 切换标签时给一次轻震动。
    @State private var haptics = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PawTab.allCases, id: \.self) { tab in
                Button { select(tab) } label: {
                    tabLabel(tab)
                        .frame(maxWidth: 168)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selection == tab ? [.isButton, .isSelected] : .isButton
                )
            }
        }
        // 条压在安全区之上（Home Indicator），玻璃铺满到屏幕物理边缘，
        // 图标和文字由 safeAreaInset 顶回安全区内——Web 的做法也是这样。
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { PawDivider() }
        .onAppear { haptics.prepare() }
    }

    private func select(_ tab: PawTab) {
        guard selection != tab else { return }
        haptics.impactOccurred()
        selection = tab
    }

    private func tabLabel(_ tab: PawTab) -> some View {
        let isSelected = selection == tab
        return VStack(spacing: 2) {
            Image(tab.iconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            Text(tab.title)
                .font(PawFont.inter(12, weight: isSelected ? .medium : .regular))
        }
        .foregroundStyle(isSelected ? Nvwa.ink : Nvwa.ink40)
    }
}

extension View {
    /// 顶部安全区铺一层不透明底色。
    ///
    /// PawFolio 页顶上有不透明的导航条挡着，Calculate 和 Currency 没有，滚上去
    /// 内容会压在时间和电量后面。三页统一走实心底色而不是渐变遮罩：首页那条
    /// 导航本来就是实心的，用渐变反而两套观感。
    ///
    /// 试过 iOS 26 的 `scrollEdgeEffectStyle(.soft, for: .top)`——它是底部浮动
    /// 标签栏那道渐变的同一套机制，但这两页的滚动容器外面还包了一层，效果传不
    /// 进去，重叠依旧。零高度的 `safeAreaInset` 不占版面，只让背景顶进安全区，
    /// 行为确定。
    func pawStatusBarBackground(_ color: Color = Nvwa.backgroundMain) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .frame(maxWidth: .infinity)
                .background(color.ignoresSafeArea(edges: .top))
        }
    }
}
