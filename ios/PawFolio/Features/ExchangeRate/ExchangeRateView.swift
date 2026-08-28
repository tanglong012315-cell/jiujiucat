import SwiftUI

struct ExchangeRateView: View {
    @StateObject private var model = ExchangeRateViewModel()
    @FocusState private var amountIsFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    introduction
                    converterCard
                    statusFooter
                }
                .frame(maxWidth: PawTheme.contentWidth)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("汇率换算")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await model.refresh()
            }
            .task {
                await model.loadIfNeeded()
            }
        }
    }

    private var introduction: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PawTheme.accent)
                .frame(width: 42, height: 42)
                .background(PawTheme.quietBlue, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("同一个数字，换一种货币看看")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("支持人民币、美元、泰铢与马来西亚令吉。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var converterCard: some View {
        PawCard {
            VStack(alignment: .leading, spacing: 18) {
                PawSectionHeading(title: "输入金额", detail: "点结果可切换基准货币")

                HStack(spacing: 10) {
                    Menu {
                        ForEach(CurrencyCode.allCases) { currency in
                            Button {
                                model.chooseBase(currency)
                            } label: {
                                Label("\(currency.displayName) · \(currency.rawValue)", systemImage: currency == model.baseCurrency ? "checkmark" : "circle")
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Text(model.baseCurrency.flag)
                                .font(.title3)
                            Text(model.baseCurrency.rawValue)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 52)
                        .background(PawTheme.quietBlue)
                        .clipShape(RoundedRectangle(cornerRadius: PawTheme.controlRadius, style: .continuous))
                    }
                    .accessibilityLabel("基准货币，当前为\(model.baseCurrency.displayName)")

                    TextField("1,000", text: $model.amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountIsFocused)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: PawTheme.controlRadius, style: .continuous))
                        .onSubmit(model.formatInput)
                        .accessibilityLabel("输入金额")
                }

                switch model.loadState {
                case .idle, .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在获取最新汇率…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)

                case .failed(let message):
                    ContentUnavailableView {
                        Label("汇率暂不可用", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重新获取") {
                            Task { await model.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case .ready:
                    VStack(spacing: 10) {
                        ForEach(model.conversions) { conversion in
                            ConversionRow(
                                conversion: conversion,
                                baseCurrency: model.baseCurrency
                            ) {
                                model.chooseBase(conversion.currency)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let updatedAt = model.updatedAt {
            HStack(spacing: 6) {
                if case .ready(isCached: true) = model.loadState {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("正在使用最近一次汇率")
                } else {
                    Image(systemName: "checkmark.circle")
                    Text("汇率已更新")
                }
                Text(updatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ConversionRow: View {
    let conversion: ExchangeRateViewModel.Conversion
    let baseCurrency: CurrencyCode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(conversion.currency.flag)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(conversion.amount, format: .number.precision(.fractionLength(2)))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("1 \(baseCurrency.rawValue) = \(conversion.unitRate.formatted(.number.precision(.fractionLength(4)))) \(conversion.currency.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                Text(conversion.currency.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PawTheme.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(PawTheme.quietBlue.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: PawTheme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PawTheme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(conversion.amount.formatted(.number.precision(.fractionLength(2)))) \(conversion.currency.displayName)，点按设为基准货币")
    }
}
