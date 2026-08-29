import SwiftUI

struct DividendRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private static let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    let holding: Holding
    let record: DividendRecord?
    let onSave: (DividendRecordRequest) async throws -> Void

    @State private var perShareText: String
    @State private var frequency: DividendFrequency
    @State private var exDate: Date
    @State private var hasPayDate: Bool
    @State private var payDate: Date
    @State private var isSaving = false
    @State private var isFrequencySheetPresented = false
    @State private var errorMessage: String?

    init(
        holding: Holding,
        record: DividendRecord?,
        onSave: @escaping (DividendRecordRequest) async throws -> Void
    ) {
        self.holding = holding
        self.record = record
        self.onSave = onSave
        _perShareText = State(initialValue: Self.numberText(record?.perShare))
        _frequency = State(initialValue: record?.frequency ?? .quarterly)
        _exDate = State(initialValue: Self.date(from: record?.exDate) ?? Date())
        _hasPayDate = State(initialValue: !(record?.payDate ?? "").isEmpty)
        _payDate = State(initialValue: Self.date(from: record?.payDate) ?? Date())
    }

    var body: some View {
        PawSheet(title: record == nil ? "添加分红" : "编辑分红") {
            VStack(alignment: .leading, spacing: 16) {
                // 数量在创建时冻结，之后加减仓只影响未来的记录。
                PawEditorField(
                    record == nil ? "当前数量" : "记录数量",
                    hint: record == nil
                        ? "创建后数量会冻结；后续加减仓只影响未来记录。"
                        : "编辑金额或日期不会改写该记录冻结的数量。"
                ) {
                    HStack(spacing: 8) {
                        Text(holding.symbol)
                            .font(PawFont.inter(16, weight: .medium))
                            .foregroundStyle(PawTheme.ink)

                        Spacer(minLength: 0)

                        Text(recordQuantity.formatted(.number.precision(.fractionLength(0...8))))
                            .font(PawFont.inter(16, weight: .medium).monospacedDigit())
                            .foregroundStyle(PawTheme.ink40)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(
                        PawTheme.ink4,
                        in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
                    )
                }

                PawEditorField("每股／份分红") {
                    PawTextFieldShell(
                        placeholder: "0.00",
                        text: $perShareText,
                        showsCurrencyPrefix: true
                    )
                }

                // Web 把频率放进独立弹层选，字段这里只显示当前值。
                PawEditorField("分红频率") {
                    Button {
                        isFrequencySheetPresented = true
                    } label: {
                        HStack(spacing: 8) {
                            Text(frequency.controlTitle)
                                .font(PawFont.inter(16, weight: .medium))
                                .foregroundStyle(PawTheme.ink)

                            Spacer(minLength: 0)

                            Image("IconArrowRightS")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(PawTheme.ink40)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(
                            PawTheme.ink4,
                            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
                        )
                    }
                    .buttonStyle(PawPressableButtonStyle())
                }

                PawEditorField("除息日", hint: "到这一天这笔分红才算确认。") {
                    PawDateFieldShell(selection: $exDate)
                }

                PawToggleRow(title: "已确定派息日", isOn: $hasPayDate)

                if hasPayDate {
                    PawEditorField("派息日") {
                        PawDateFieldShell(selection: $payDate)
                    }
                }
            }
        } footer: {
            PawPrimaryButton(title: isSaving ? "保存中…" : "保存") { save() }
                .disabled(isSaving)
                .opacity(isSaving ? 0.55 : 1)
        }
        .sheet(isPresented: $isFrequencySheetPresented) {
            DividendFrequencySheet(selection: $frequency)
        }
        .interactiveDismissDisabled(isSaving)
        .environment(\.timeZone, Self.beijingTimeZone)
        .alert("无法保存", isPresented: errorAlertBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请检查输入内容。")
        }
        .overlay {
            if isSaving {
                ProgressView()
                    .tint(PawTheme.ink)
                    .padding(18)
                    .background(PawTheme.bg2, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var recordQuantity: Double {
        if let quantity = record?.quantity, quantity > 0 { return quantity }
        return max(0, holding.quantity ?? 0)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard let perShare = Self.number(from: perShareText), perShare > 0 else {
            errorMessage = HoldingRecordError.invalidDividendAmount.errorDescription
            return
        }

        let request = DividendRecordRequest(
            holdingID: holding.id,
            recordID: record?.id,
            perShare: perShare,
            frequency: frequency,
            exDate: Self.dateString(exDate),
            payDate: hasPayDate ? Self.dateString(payDate) : "",
            occurredAt: Date().timeIntervalSince1970 * 1_000
        )

        isSaving = true
        Task {
            do {
                try await onSave(request)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "分红记录保存失败，请重试。"
            }
        }
    }

    private static func number(from text: String) -> Double? {
        Double(
            text.replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func numberText(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(
            .number.grouping(.never).precision(.fractionLength(0...8))
        )
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return dateFormatter().date(from: value)
    }

    private static func dateString(_ date: Date) -> String {
        dateFormatter().string(from: date)
    }

    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = beijingTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

// 频率的措辞现在也给持仓编辑用（两处共用同一个选择弹层），不再是 fileprivate。
extension DividendFrequency {
    var recordEditorTitle: String {
        switch self {
        case .quarterly: "每季度"
        case .monthly: "每月"
        case .semimonthly: "每月两次"
        case .semiannual: "每半年"
        case .annual: "每年"
        case .irregular: "不固定"
        }
    }

    /// 对应 `app.js` 的 `DIVIDEND_FREQUENCY_CONTROL_LABELS`，用于频率选择弹层。
    var controlTitle: String {
        switch self {
        case .quarterly: "每季度一次"
        case .monthly: "每月一次"
        case .semimonthly: "每月两次"
        case .semiannual: "每半年一次"
        case .annual: "每年一次"
        case .irregular: "不固定"
        }
    }
}

/// Web `#dividend-frequency-overlay`：一个独立弹层，每行一个选项，选中的打勾。
struct DividendFrequencySheet: View {
    @Binding var selection: DividendFrequency

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PawSheet(title: "选择分红频率") {
            VStack(spacing: 0) {
                ForEach(DividendFrequency.allCases, id: \.rawValue) { item in
                    let isSelected = selection == item

                    Button {
                        selection = item
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(item.controlTitle)
                                .font(PawFont.inter(14, weight: .medium))
                                .foregroundStyle(PawTheme.ink)

                            Spacer(minLength: 0)

                            if isSelected {
                                Image("IconCheck")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(PawTheme.ink)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PawPressableButtonStyle())
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}
