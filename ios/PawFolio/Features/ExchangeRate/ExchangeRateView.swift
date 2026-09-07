import Nvwa
import SwiftUI

/// PawFolio V1.2.0 Currency screen（V1.1 是 `63:7007`）。每一行的金额都能改，正在
/// 编辑的那一行成为基准，其余行跟着它换算。货币可增、可右滑删除、可拖动排序。
struct ExchangeRateView: View {
    @StateObject private var model = ExchangeRateViewModel()
    @Environment(\.locale) private var locale
    @FocusState private var focusedCurrency: CurrencyCode?

    /// 视觉 QA：`SIMCTL_CHILD_PAWFOLIO_QA_CURRENCY_PICKER=1` 直接把添加货币弹层打开。
    @State private var isPickerPresented = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PAWFOLIO_QA_CURRENCY_PICKER"] == "1"
        #else
        return false
        #endif
    }()

    /// 右滑露出删除按钮的那一行。同一时间只允许一行是打开的。
    ///
    /// 视觉 QA：右滑是手势，模拟器上截不到，
    /// `SIMCTL_CHILD_PAWFOLIO_QA_CURRENCY_SWIPE=<代码>` 直接停在露出删除的样子。
    @State private var revealedCurrency: CurrencyCode? = {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["PAWFOLIO_QA_CURRENCY_SWIPE"] else {
            return nil
        }
        return CurrencyCode(raw)
        #else
        return nil
        #endif
    }()

    /// 正在右滑的那一行与它的实时位移。跟排序分开记，两套手势互不共享状态。
    @State private var swipingCurrency: CurrencyCode?
    @State private var swipeOffset: CGFloat = 0

    /// Nvwa 统一管理拖动项、目标下标、让位和松手提交；页面只保留一份列表级状态。
    @State private var reorderState = NvwaReorderState<CurrencyCode>()

    let isSignedIn: Bool
    let profileInitials: String
    let profileAvatar: CatAvatar
    let onOpenAccount: () -> Void
    let onSignIn: () -> Void

    init(
        isSignedIn: Bool = true,
        profileInitials: String = "",
        profileAvatar: CatAvatar = .faceHappy,
        onOpenAccount: @escaping () -> Void = {},
        onSignIn: @escaping () -> Void = {}
    ) {
        self.isSignedIn = isSignedIn
        self.profileInitials = profileInitials
        self.profileAvatar = profileAvatar
        self.onOpenAccount = onOpenAccount
        self.onSignIn = onSignIn
    }

    /// 全部照 `110:3141`「汇率」量的。
    private enum Metrics {
        static let flagSize: CGFloat = 42
        /// 行内容上下各留这么多。行高是定值，拖动排序按整数格数换位要用。
        static let rowVerticalPadding: CGFloat = 24
        /// 金额那一行：30/Semibold，行高 34。
        static let amountLineHeight: CGFloat = 34
        static let subtitleHeight: CGFloat = 20
        static let amountToSubtitle: CGFloat = 4
        static var rowHeight: CGFloat {
            let text = amountLineHeight + amountToSubtitle + subtitleHeight
            return max(text, flagSize) + rowVerticalPadding * 2
        }

        /// 页面左右边距。它加在**行内容**上而不是列表外面，这样右滑时删除按钮
        /// 能一直贴到屏幕边，跟系统的滑动删除一致，右侧不会剩一条白边。
        static let pagePadding: CGFloat = 16
        static let deleteWidth: CGFloat = 88
        /// 超过这个位移才认为用户是要删，否则松手弹回去。
        static let revealThreshold: CGFloat = 36
    }

    private var isReordering: Bool { reorderState.isReordering }

    var body: some View {
        // 顶栏由 `pawGlassTopBar` 挂成 safe-area inset，内容从它底下滑过去。
        // 状态栏那一截由那层玻璃自己铺满，不再叠 `pawStatusBarBackground()`。
        content
            .background(Nvwa.backgroundMain)
            .pawGlassTopBar {
                PawTopNavigation(
                    isSignedIn: isSignedIn,
                    profileInitials: profileInitials,
                    profileAvatar: profileAvatar,
                    trailingIcon: Image("IconAdd"),
                    trailingTone: .neutral,
                    trailingAccessibilityLabel: "Add currency",
                    onOpenAccount: onOpenAccount,
                    onSignIn: onSignIn,
                    onTrailing: { isPickerPresented = true }
                )
            }
        .task { await model.loadIfNeeded() }
            .onChange(of: focusedCurrency) { oldValue, newValue in
            if let oldValue, oldValue != newValue {
                model.finishEditing(oldValue)
            }
            if let newValue {
                model.beginEditing(newValue)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedCurrency = nil }
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            CurrencyPickerView(currencies: model.availableCurrencies) { code in
                model.add(code)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.currencies) { currency in
                    currencyRow(currency)
                }

                updatedCaption
            }
            .padding(.vertical, 16)
            .pawScrollBounceDisabled()
        }
        // Currency 不提供下拉刷新，也不允许顶端/底端回弹；列表超出屏幕时仍可正常滚动。
        // 拿起一行之后才锁滚动。在此之前手指的纵向位移仍归列表滚动。
        .scrollDisabled(isReordering)
        .pawTabBarBottomMargin()
        .scrollDismissesKeyboard(.interactively)
    }

    /// 列表末尾那行 `Updated 13:21`（`110:3679`）：10/Regular，颜色是
    /// `nvwa/line/line`——比副标题还淡，设计上就是这么定的。
    @ViewBuilder
    private var updatedCaption: some View {
        Group {
            if let updatedAt = model.updatedAt {
                Text("Updated \(Self.clockFormat.string(from: updatedAt))")
            } else {
                Text("Rates unavailable")
            }
        }
            .font(Nvwa.caption2)
            .tracking(0.1)
            .foregroundStyle(Nvwa.line)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }

    private static let clockFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - 行

    private func currencyRow(_ currency: CurrencyCode) -> some View {
        let isRevealed = revealedCurrency == currency
        let restingOffset = isRevealed ? -Metrics.deleteWidth : 0

        return ZStack(alignment: .trailing) {
            deleteButton(currency)

            rowBody(currency)
                .background(Nvwa.backgroundMain)
                .offset(x: swipingCurrency == currency ? swipeOffset : restingOffset)
        }
        .frame(height: Metrics.rowHeight)
        .overlay(alignment: .bottom) { PawDivider(insets: Metrics.pagePadding) }
        // 轻点、横滑、长按和拖动中的逐帧位移由同一个 Nvwa 组件仲裁。
        .nvwaReorderable(
            item: currency,
            items: model.currencies,
            state: $reorderState,
            layout: .vertical(itemExtent: Metrics.rowHeight),
            onTap: { activate(currency) },
            onHorizontalSwipeChanged: { updateSwipe(currency, translation: $0) },
            onHorizontalSwipeEnded: { _ in finishSwipe(currency) },
            onLift: prepareForReorder,
            onMove: { model.move($0, to: $1) }
        )
        .animation(.snappy(duration: 0.22), value: revealedCurrency)
    }

    /// 左边只有国旗，右边是右对齐的两行：金额 + 灰色币种代码，下面是副标题。
    /// 代码**跟在金额后面**、不在左侧——这是 `110:3141` 的版式。
    private func rowBody(_ currency: CurrencyCode) -> some View {
        HStack(spacing: 10) {
            flag(for: currency)

            VStack(alignment: .trailing, spacing: Metrics.amountToSubtitle) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    amountField(currency)

                    Text(" " + currency.rawValue)
                        .font(Nvwa.font(30, weight: .semibold))
                        .tracking(-0.75)
                        .foregroundStyle(Nvwa.textSecondary)
                        .fixedSize()
                }
                .frame(height: Metrics.amountLineHeight)

                Text(LocalizedStringKey(model.subtitle(for: currency, locale: locale)))
                    .font(Nvwa.bodySmall)
                    .tracking(0.12)
                    .foregroundStyle(Nvwa.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: Metrics.subtitleHeight, alignment: .trailing)
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.vertical, Metrics.rowVerticalPadding)
        .frame(height: Metrics.rowHeight)
        .contentShape(Rectangle())
    }

    private func amountField(_ currency: CurrencyCode) -> some View {
        let isBase = model.baseCurrency == currency
        let isAwaitingInput = model.isAwaitingInput(currency)

        return TextField(
            "",
            text: Binding(
                get: { model.text(for: currency) },
                set: { model.updateAmountText($0, for: currency) }
            ),
            prompt: Text(model.placeholder(for: currency))
                .foregroundColor(Nvwa.textSecondary)
        )
        .font(Nvwa.font(30, weight: .semibold).monospacedDigit())
        .tracking(-0.75)
        // TextField 编辑器会短暂保留旧字符串；文字由覆盖层统一从模型渲染，避免
        // 首次覆盖/删除时出现一帧旧值回跳。原生光标与键盘仍由 TextField 提供。
        .foregroundStyle(Color.clear)
        .overlay(alignment: .trailing) {
            Text(model.text(for: currency).isEmpty ? "0" : model.text(for: currency))
                .font(Nvwa.font(30, weight: .semibold).monospacedDigit())
                .tracking(-0.75)
                .foregroundStyle(
                    isAwaitingInput
                        ? Nvwa.textSecondary
                        : (isBase ? Nvwa.primaryGreen : Nvwa.grayPrimary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .focused($focusedCurrency, equals: currency)
        // 输入只由整行的短按激活。这样长按由排序手势独占，不会先唤起键盘或文本选择。
        .allowsHitTesting(false)
        // 输入框吃掉剩下的宽度并右对齐，代码贴在它右边，于是各行的代码右缘对齐、
        // 数字紧挨着代码——`110:3141` 就是这个关系。
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("Amount in \(currency.displayName)")
        .accessibilityValue(model.text(for: currency).isEmpty ? "0" : model.text(for: currency))
    }

    private func deleteButton(_ currency: CurrencyCode) -> some View {
        Button {
            focusedCurrency = nil
            revealedCurrency = nil
            model.remove(currency)
        } label: {
            Image("IconDelete")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Nvwa.colorOnBlue)
                .frame(width: Metrics.deleteWidth, height: Metrics.rowHeight)
                .background(Nvwa.sentimentNegative)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(currency.displayName)")
    }

    private func flag(for currency: CurrencyCode) -> some View {
        Image(currency.flagAssetName)
            .resizable()
            .scaledToFill()
            .frame(width: Metrics.flagSize, height: Metrics.flagSize)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Nvwa.line, lineWidth: 1))
            .accessibilityHidden(true)
    }

    // MARK: - 右滑删除

    private func activate(_ currency: CurrencyCode) {
        guard revealedCurrency == nil else {
            revealedCurrency = nil
            return
        }
        focusedCurrency = currency
    }

    private func updateSwipe(_ currency: CurrencyCode, translation: CGSize) {
        guard !isReordering, focusedCurrency == nil else { return }
        swipingCurrency = currency
        let base = revealedCurrency == currency ? -Metrics.deleteWidth : 0
        // 只能向左拉，而且拉不过删除按钮的宽度。
        swipeOffset = min(0, max(-Metrics.deleteWidth, base + translation.width))
    }

    private func finishSwipe(_ currency: CurrencyCode) {
        guard swipingCurrency == currency else { return }
        revealedCurrency = swipeOffset < -Metrics.revealThreshold ? currency : nil
        swipingCurrency = nil
        swipeOffset = 0
    }

    // MARK: - 拖动排序

    private func prepareForReorder() {
        focusedCurrency = nil
        revealedCurrency = nil
        swipingCurrency = nil
        swipeOffset = 0
    }
}
