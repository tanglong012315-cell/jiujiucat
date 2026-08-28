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
        NavigationStack {
            Form {
                Section {
                    LabeledContent("资产", value: holding.symbol)
                    LabeledContent(record == nil ? "当前数量" : "记录数量") {
                        Text(recordQuantity, format: .number.precision(.fractionLength(0...8)))
                            .monospacedDigit()
                    }
                } footer: {
                    Text(record == nil ? "创建后数量会冻结；后续加减仓只影响未来记录。" : "编辑金额或日期不会改写该记录冻结的数量。")
                }

                Section("分红信息") {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("每股／份分红", text: $perShareText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }

                    Picker("频率", selection: $frequency) {
                        ForEach(DividendFrequency.allCases, id: \.rawValue) { item in
                            Text(item.recordEditorTitle).tag(item)
                        }
                    }

                    DatePicker("除息日", selection: $exDate, displayedComponents: .date)
                    Toggle("已确定派息日", isOn: $hasPayDate)
                    if hasPayDate {
                        DatePicker(
                            "派息日",
                            selection: $payDate,
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle(record == nil ? "添加分红" : "编辑分红")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
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
                    ProgressView("正在保存…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
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

private extension DividendFrequency {
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
}
