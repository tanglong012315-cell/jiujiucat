import Charts
import SwiftUI

struct CalculatorView: View {
    @StateObject private var model = CalculatorViewModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case principal
    }

    private let metricColumns = [
        GridItem(.adaptive(minimum: 96), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    introduction
                    planCard
                    resultCard
                }
                .frame(maxWidth: PawTheme.contentWidth)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("收益计算")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var introduction: some View {
        HStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PawTheme.accent)
                .frame(width: 42, height: 42)
                .background(PawTheme.quietBlue, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("让每一笔投入更清楚")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("比较单利与复利，查看未来的资产变化。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var planCard: some View {
        PawCard {
            VStack(alignment: .leading, spacing: 20) {
                PawSectionHeading(title: "投资计划", detail: "所有金额暂以美元计算")

                VStack(alignment: .leading, spacing: 8) {
                    Text("总投资")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 8) {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("10,000", text: $model.principalText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .principal)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                        Text("USD")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: PawTheme.controlRadius, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("总投资，美元")

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(model.quickAmounts, id: \.self) { amount in
                                Button(shortAmount(amount)) {
                                    model.selectQuickAmount(amount)
                                    focusedField = nil
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("年化收益率")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(model.annualRatePercent, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text("%")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $model.annualRatePercent, in: 0.01...30, step: 0.01)
                        .accessibilityLabel("年化收益率")
                        .accessibilityValue("\(model.annualRatePercent.formatted(.number.precision(.fractionLength(2)))) 百分比")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("计息方式")
                        .font(.subheadline.weight(.medium))
                    Picker("计息方式", selection: $model.selectedMode) {
                        ForEach(InterestMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    model.calculate()
                    focusedField = nil
                } label: {
                    Text("计算收益")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: PawTheme.controlRadius))
            }
        }
    }

    private var resultCard: some View {
        PawCard {
            VStack(alignment: .leading, spacing: 18) {
                PawSectionHeading(title: "收益预估", detail: "按当前参数计算，不构成投资建议")

                LazyVGrid(columns: metricColumns, spacing: 10) {
                    MetricTile(title: "日收益", value: model.summary.dailyProfit)
                    MetricTile(title: "月收益", value: model.summary.monthlyProfit)
                    MetricTile(title: "年收益", value: model.summary.yearlyProfit)
                }

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("总资产变化")
                            .font(.subheadline.weight(.medium))
                        Text(model.selectedPeriod.caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("预测周期", selection: Binding(
                        get: { model.selectedPeriod },
                        set: { model.selectedPeriod = $0 }
                    )) {
                        ForEach(ForecastPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.totalAtForecastEnd, format: .currency(code: "USD"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                    Text("预计增加 \(model.forecastProfit.formatted(.currency(code: "USD")))")
                        .font(.subheadline)
                        .foregroundStyle(PawTheme.gain)
                        .monospacedDigit()
                }

                Chart(model.forecast) { point in
                    LineMark(
                        x: .value("时间", point.index),
                        y: .value("总资产", point.amount)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(PawTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .chartXAxis {
                    AxisMarks(values: axisValues(for: model.selectedPeriod)) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self),
                               let label = model.selectedPeriod.axisLabel(at: index) {
                                Text(label)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisValueLabel()
                    }
                }
                .frame(height: 210)
                .accessibilityLabel("\(model.selectedPeriod.caption)总资产预测")
                .accessibilityValue("期末预计 \(model.totalAtForecastEnd.formatted(.currency(code: "USD")))")
            }
        }
    }

    private func axisValues(for period: ForecastPeriod) -> [Int] {
        switch period {
        case .day: [0, 365]
        case .month: [0, 12, 24, 36]
        case .year: [0, 3, 6, 9, 12]
        }
    }

    private func shortAmount(_ amount: Double) -> String {
        let value = Int(amount / 10_000)
        return "\(value)万"
    }
}

private struct MetricTile: View {
    let title: LocalizedStringKey
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD"))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(PawTheme.quietBlue.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: PawTheme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

