import SwiftUI

/// Web `#panel-fx` 的复刻。该面板下 `.card` 的外观被整体去掉
/// （`#panel-fx > .card { padding: 0; background: transparent }`），所以这里没有卡片，
/// 只有输入壳和结果行自带 `--ink-4` 填充。
struct ExchangeRateView: View {
    @StateObject private var model = ExchangeRateViewModel()
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PawLayout.blockSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    PawFieldLabel("输入金额")

                    // Web `.fx-input-shell` 把 gap 从 8 改成 12。
                    PawInputShell(horizontalPadding: 16, spacing: 12) {
                        flag(for: model.baseCurrency)

                        TextField("", text: $model.amountText)
                            .font(PawFont.inter(24, weight: .semibold).monospacedDigit())
                            .foregroundStyle(PawTheme.ink)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                            .accessibilityLabel("输入金额")

                        Text(model.baseCurrency.rawValue)
                            .font(PawFont.inter(12))
                            .foregroundStyle(PawTheme.ink40)
                    }
                }

                // Web 的 `.fx-swap-hint`：输入框与结果之间的连接符，纯装饰。
                Image("IconArrowUpDown")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(PawTheme.ink40)
                    .frame(width: 28, height: 28)
                    .background(
                        PawTheme.ink4,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    ForEach(model.conversions) { conversion in
                        Button {
                            isAmountFocused = false
                            model.chooseBase(conversion.currency)
                        } label: {
                            resultRow(conversion)
                        }
                        .buttonStyle(PawPressableButtonStyle())
                        .accessibilityLabel(
                            "\(amountText(conversion.amount)) \(conversion.currency.displayName)，点按设为基准货币"
                        )
                    }
                }

                Text(updatedCaption)
                    .font(PawFont.inter(12).monospacedDigit())
                    .foregroundStyle(PawTheme.ink40)
            }
            .padding(.horizontal, PawLayout.pageHorizontal)
            .padding(.top, 16)
            .padding(.bottom, PawLayout.pageHorizontal)
        }
        // 贴底导航是浮层，滚动内容要自己留出它的高度。
        .contentMargins(.bottom, PawLayout.tabBarHeight, for: .scrollContent)
        .background(PawTheme.bg1)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refresh() }
        .task { await model.loadIfNeeded() }
        .onChange(of: isAmountFocused) { _, focused in
            if !focused { model.formatInput() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { isAmountFocused = false }
            }
        }
    }

    /// Web `.fx-row`。
    private func resultRow(_ conversion: ExchangeRateViewModel.Conversion) -> some View {
        HStack(spacing: 12) {
            flag(for: conversion.currency)

            VStack(alignment: .leading, spacing: 2) {
                Text(amountText(conversion.amount))
                    .font(PawTheme.moneyMedium)
                    .foregroundStyle(PawTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(
                    "1 \(model.baseCurrency.rawValue) = "
                        + conversion.unitRate.formatted(.number.precision(.fractionLength(4)))
                        + " \(conversion.currency.rawValue)"
                )
                .font(PawFont.inter(12).monospacedDigit())
                .foregroundStyle(PawTheme.ink.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            Text(conversion.currency.rawValue)
                .font(PawFont.inter(12, weight: .semibold))
                .foregroundStyle(PawTheme.ink.opacity(0.5))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PawTheme.ink4,
            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
        )
    }

    /// Web 用 `public/flags/*.svg`，同样的四面旗已打包进 Asset Catalog。
    private func flag(for currency: CurrencyCode) -> some View {
        Image(currency.flagAssetName)
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .accessibilityHidden(true)
    }

    private func amountText(_ amount: Double) -> String {
        amount.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }

    private var updatedCaption: String {
        guard let updatedAt = model.updatedAt else { return "正在获取实时汇率…" }
        return "实时汇率 · 更新于 \(Self.clockFormat.string(from: updatedAt))"
    }

    /// Web 用 24 小时制。
    private static let clockFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

extension CurrencyCode {
    /// Web 用真实国旗图，不是 emoji。
    var flagAssetName: String {
        switch self {
        case .cny: "FlagCN"
        case .usd: "FlagUS"
        case .thb: "FlagTH"
        case .myr: "FlagMY"
        }
    }
}
