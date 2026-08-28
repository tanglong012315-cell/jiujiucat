import SwiftUI

struct HoldingEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private static let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    let existingHolding: Holding?
    let marketPrice: Double?
    let onSave: (Holding) async -> Bool
    let onAdjust: (HoldingAdjustmentRequest) async throws -> Void

    @State private var draft: HoldingDraft
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var isAssetSearchPresented = false
    @State private var adjustmentType = PositionAdjustmentKind.add
    @State private var adjustmentAmountText = ""
    @State private var adjustmentPriceText = ""
    @State private var adjustmentEffectiveDate = Date()

    init(
        holding: Holding?,
        marketPrice: Double?,
        onSave: @escaping (Holding) async -> Bool,
        onAdjust: @escaping (HoldingAdjustmentRequest) async throws -> Void
    ) {
        existingHolding = holding
        self.marketPrice = marketPrice
        self.onSave = onSave
        self.onAdjust = onAdjust
        _draft = State(initialValue: HoldingDraft(holding: holding))
    }

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                identitySection
                valueSection

                if let existingHolding {
                    adjustmentSection(for: existingHolding)
                }

                if draft.kind == .interest || draft.kind == .hybrid {
                    interestSection
                }

                if draft.kind == .dividend {
                    dividendSection
                }
            }
            .navigationTitle(existingHolding == nil ? "添加持仓" : "编辑持仓")
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
            .sheet(isPresented: $isAssetSearchPresented) {
                AssetSearchView(initialQuery: draft.symbol) { asset in
                    draft.apply(asset)
                }
            }
            .alert("无法保存", isPresented: validationAlertBinding) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(validationMessage ?? "请检查输入内容。")
            }
            .overlay {
                if isSaving {
                    ProgressView("正在保存…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .environment(\.timeZone, Self.beijingTimeZone)
        }
    }

    @ViewBuilder
    private var kindSection: some View {
        Section {
            if existingHolding == nil {
                Picker("持仓类型", selection: $draft.kind) {
                    ForEach(HoldingKind.allCases, id: \.rawValue) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.navigationLink)
            } else {
                LabeledContent("持仓类型", value: draft.kind.title)
            }
        } footer: {
            Text(draft.kind.explanation)
        }
    }

    private var identitySection: some View {
        Section("资产信息") {
            if draft.kind == .interest {
                TextField("例如：美元定存", text: $draft.symbol)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } else {
                Button {
                    isAssetSearchPresented = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(draft.symbol.isEmpty ? "选择标的" : draft.symbol)
                                .foregroundStyle(draft.symbol.isEmpty ? .secondary : .primary)
                            if !draft.name.isEmpty {
                                Text(draft.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(PawTheme.accent)
                    }
                }
                .accessibilityLabel(draft.symbol.isEmpty ? "搜索并选择标的" : "当前标的 \(draft.symbol)，点按重新搜索")
            }

            TextField("资产名称（选填）", text: $draft.name)

            if draft.kind != .interest, !draft.symbol.isEmpty, draft.exchange == "手动" {
                Picker("资产类别", selection: $draft.assetType) {
                    Text("股票").tag(AssetType.equity)
                    Text("ETF").tag(AssetType.etf)
                    Text("加密货币").tag(AssetType.cryptocurrency)
                }
            } else if draft.kind != .interest, !draft.symbol.isEmpty {
                LabeledContent("资产类别", value: draft.assetType.title)
            }
        }
    }

    @ViewBuilder
    private var valueSection: some View {
        if draft.kind == .interest {
            Section {
                if let principal = existingHolding?.principal {
                    LabeledContent("当前本金") {
                        Text(principal, format: .currency(code: "USD"))
                            .monospacedDigit()
                    }
                } else {
                    moneyField("投资本金", text: $draft.principalText)
                }
            } header: {
                Text("本金")
            } footer: {
                if existingHolding != nil {
                    Text("本金变化请使用“调整持仓”，以保留历史计息区间。")
                }
            }
        } else {
            Section {
                if let quantity = existingHolding?.quantity {
                    LabeledContent("当前数量") {
                        Text(quantity, format: .number.precision(.fractionLength(0...8)))
                            .monospacedDigit()
                    }
                } else {
                    decimalField("持有数量", text: $draft.quantityText)
                }
                moneyField("单位成本", text: $draft.costPerShareText)
            } header: {
                Text("仓位")
            } footer: {
                Text(
                    existingHolding == nil
                        ? "单位成本用于计算持仓盈亏；当前市值会按实时行情自动更新。"
                        : "数量变化请使用“调整持仓”；单位成本可用于修正录入错误。"
                )
            }
        }
    }

    private func adjustmentSection(for holding: Holding) -> some View {
        Section {
            Picker("调整方向", selection: $adjustmentType) {
                Text("加仓").tag(PositionAdjustmentKind.add)
                Text("减仓").tag(PositionAdjustmentKind.reduce)
            }
            .pickerStyle(.segmented)

            if holding.holdingKind == .interest {
                moneyField("调整金额", text: $adjustmentAmountText)
                DatePicker(
                    "生效日期",
                    selection: $adjustmentEffectiveDate,
                    in: Self.beijingStartOfToday...,
                    displayedComponents: .date
                )
            } else {
                HStack {
                    decimalField("调整数量", text: $adjustmentAmountText)
                    if adjustmentType == .reduce {
                        Button("全部") {
                            adjustmentAmountText = Self.numberText(holding.quantity)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                moneyField("成交价格", text: $adjustmentPriceText)

                if let marketPrice {
                    LabeledContent("美元实时价") {
                        Text(marketPrice, format: .currency(code: "USD"))
                            .monospacedDigit()
                    }
                }
            }

            Button {
                applyAdjustment(to: holding)
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView()
                    }
                    Text(adjustmentType == .add ? "确认加仓" : "确认减仓")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(isSaving || adjustmentAmountText.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("调整持仓")
        } footer: {
            if holding.holdingKind == .interest {
                Text("新本金从生效日次日 16:00（北京时间）的结算起参与计息，历史利息不变。")
            } else if adjustmentType == .add {
                Text(
                    marketPrice == nil
                        ? "当前没有可用的美元实时价，请填写成交价格；加仓会重新计算加权平均成本。"
                        : "成交价格留空时使用上方美元实时价；加仓会重新计算加权平均成本。"
                )
            } else {
                Text(
                    (marketPrice == nil ? "当前没有可用的美元实时价，请填写成交价格。" : "")
                        + "卖出所得会在同一时刻转入 0% APR 的 USDT 持仓；选择“全部”会保留清仓历史。"
                )
            }
        }
    }

    private var interestSection: some View {
        Section("收益设置") {
            HStack {
                TextField("年化利率", text: $draft.annualRateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("%")
                    .foregroundStyle(.secondary)
            }

            Picker("计息方式", selection: $draft.interestMode) {
                ForEach(InterestMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            DatePicker(
                "起息日期",
                selection: $draft.interestStartDate,
                displayedComponents: .date
            )
        }
    }

    private var dividendSection: some View {
        Section("分红设置") {
            moneyField("每股／份分红", text: $draft.dividendPerShareText)

            Picker("频率", selection: $draft.dividendFrequency) {
                ForEach(DividendFrequency.allCases, id: \.rawValue) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }

            DatePicker(
                "除息日",
                selection: $draft.dividendExDate,
                displayedComponents: .date
            )
            Toggle("已确定派息日", isOn: $draft.hasDividendPayDate)
            if draft.hasDividendPayDate {
                DatePicker(
                    "派息日",
                    selection: $draft.dividendPayDate,
                    displayedComponents: .date
                )
            }
        }
    }

    private func decimalField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
    }

    private func moneyField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack {
            Text("$")
                .foregroundStyle(.secondary)
            decimalField(title, text: text)
        }
    }

    private var validationAlertBinding: Binding<Bool> {
        Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )
    }

    private func save() {
        do {
            let holding = try draft.makeHolding(existing: existingHolding)
            isSaving = true
            Task {
                let didSave = await onSave(holding)
                isSaving = false
                if didSave {
                    dismiss()
                } else {
                    validationMessage = "本地数据暂时无法写入，请重试。"
                }
            }
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? "请检查输入内容。"
        }
    }

    private func applyAdjustment(to holding: Holding) {
        guard let amount = Self.number(from: adjustmentAmountText),
              amount.isFinite,
              amount > 0 else {
            validationMessage = HoldingAdjustmentError.invalidAmount.errorDescription
            return
        }

        var transactionPrice: Double?
        var effectiveDate: String?
        if holding.holdingKind == .interest {
            effectiveDate = Self.dateString(adjustmentEffectiveDate)
        } else {
            let enteredPrice = adjustmentPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
            transactionPrice = enteredPrice.isEmpty ? marketPrice : Self.number(from: enteredPrice)
        }

        let request = HoldingAdjustmentRequest(
            holdingID: holding.id,
            type: adjustmentType,
            amount: amount,
            transactionPrice: transactionPrice,
            effectiveDate: effectiveDate,
            occurredAt: Date().timeIntervalSince1970 * 1_000
        )

        isSaving = true
        Task {
            do {
                try await onAdjust(request)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                validationMessage = (error as? LocalizedError)?.errorDescription
                    ?? "持仓调整失败，请重试。"
            }
        }
    }

    private static func number(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private static func numberText(_ number: Double?) -> String {
        guard let number else { return "" }
        return number.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0...8))
        )
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static var beijingStartOfToday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = beijingTimeZone
        return calendar.startOfDay(for: Date())
    }
}

private struct HoldingDraft {
    var kind: HoldingKind
    var symbol: String
    var quoteSymbol: String
    var name: String
    var assetType: AssetType
    var exchange: String
    var quantityText: String
    var costPerShareText: String
    var principalText: String
    var annualRateText: String
    var interestMode: InterestMode
    var interestStartDate: Date
    var dividendPerShareText: String
    var dividendFrequency: DividendFrequency
    var dividendExDate: Date
    var hasDividendPayDate: Bool
    var dividendPayDate: Date

    init(holding: Holding?) {
        kind = holding?.holdingKind ?? .market
        symbol = holding?.symbol ?? ""
        quoteSymbol = holding?.quoteSymbol ?? ""
        name = holding?.name == holding?.symbol ? "" : (holding?.name ?? "")
        if let existingAssetType = holding?.assetType, existingAssetType != .stable {
            assetType = existingAssetType
        } else {
            assetType = .equity
        }
        exchange = holding?.exchange ?? ""
        quantityText = Self.numberText(holding?.quantity)
        costPerShareText = Self.numberText(holding?.costPerShare)
        principalText = Self.numberText(holding?.principal)
        annualRateText = Self.numberText(holding?.annualRate)
        interestMode = holding?.interestMode ?? .simple
        interestStartDate = Self.date(from: holding?.interestStartDate) ?? Date()
        dividendPerShareText = Self.numberText(holding?.dividendPerShare)
        dividendFrequency = holding?.dividendFrequency ?? .quarterly
        dividendExDate = Self.date(from: holding?.dividendExDate) ?? Date()
        hasDividendPayDate = !(holding?.dividendPayDate ?? "").isEmpty
        dividendPayDate = Self.date(from: holding?.dividendPayDate) ?? Date()
    }

    func makeHolding(existing: Holding?) throws -> Holding {
        let normalizedSymbol = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw HoldingDraftError.missingSymbol
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date().timeIntervalSince1970 * 1_000
        let quantity = Self.number(from: quantityText)
        let costPerShare = Self.number(from: costPerShareText)
        let principal = Self.number(from: principalText)
        let annualRate = Self.number(from: annualRateText)
        let dividendPerShare = Self.number(from: dividendPerShareText)

        if kind == .interest {
            guard let principal, principal.isFinite, principal > 0 else {
                throw HoldingDraftError.invalidPrincipal
            }
        } else {
            guard let quantity, quantity.isFinite, quantity > 0 else {
                throw HoldingDraftError.invalidQuantity
            }
            guard let costPerShare, costPerShare.isFinite, costPerShare > 0 else {
                throw HoldingDraftError.invalidCost
            }
        }

        if kind == .interest || kind == .hybrid {
            guard let annualRate, annualRate.isFinite, annualRate > 0, annualRate <= 1_000 else {
                throw HoldingDraftError.invalidRate
            }
        }

        if kind == .dividend {
            guard let dividendPerShare, dividendPerShare.isFinite, dividendPerShare > 0 else {
                throw HoldingDraftError.invalidDividend
            }
            guard !hasDividendPayDate || dividendPayDate >= dividendExDate else {
                throw HoldingDraftError.invalidPayDate
            }
        }

        let resolvedAssetType: AssetType? = kind == .interest ? .stable : assetType
        let resolvedQuoteSymbol = kind == .interest
            ? normalizedSymbol
            : (quoteSymbol.isEmpty
                ? Self.quoteSymbol(for: normalizedSymbol, assetType: assetType)
                : quoteSymbol.uppercased())

        var dividendRecords = existing?.dividendRecords ?? []
        var dividendRecordID = existing?.dividendRecordId
        if kind == .dividend, let quantity, let dividendPerShare {
            let exDate = Self.dateString(dividendExDate)
            let payDate = hasDividendPayDate ? Self.dateString(dividendPayDate) : ""

            if let recordID = dividendRecordID,
               let index = dividendRecords.firstIndex(where: { $0.id == recordID && $0.exDate == exDate }) {
                let frozenQuantity = dividendRecords[index].quantity > 0
                    ? dividendRecords[index].quantity
                    : quantity
                dividendRecords[index].perShare = dividendPerShare
                dividendRecords[index].quantity = frozenQuantity
                dividendRecords[index].amount = frozenQuantity * dividendPerShare
                dividendRecords[index].frequency = dividendFrequency
                dividendRecords[index].payDate = payDate
            } else {
                let recordID = "d_\(Int(now))_\(UUID().uuidString.prefix(5).lowercased())"
                dividendRecords.append(
                    DividendRecord(
                        id: recordID,
                        perShare: dividendPerShare,
                        quantity: quantity,
                        amount: quantity * dividendPerShare,
                        frequency: dividendFrequency,
                        exDate: exDate,
                        payDate: payDate,
                        createdAt: now
                    )
                )
                dividendRecordID = recordID
            }
        }

        let id = existing?.id ?? "h_\(Int(now))_\(UUID().uuidString.prefix(5).lowercased())"

        return Holding(
            id: id,
            symbol: normalizedSymbol,
            quoteSymbol: resolvedQuoteSymbol,
            name: normalizedName.isEmpty ? normalizedSymbol : normalizedName,
            assetType: resolvedAssetType,
            exchange: kind == .interest ? "手动" : exchange,
            holdingKind: kind,
            quantity: kind == .interest ? nil : quantity,
            costPerShare: kind == .interest ? nil : costPerShare,
            priceOverride: nil,
            principal: kind == .interest ? principal : nil,
            annualRate: (kind == .interest || kind == .hybrid) ? annualRate : nil,
            interestMode: (kind == .interest || kind == .hybrid) ? interestMode : nil,
            interestStartDate: (kind == .interest || kind == .hybrid)
                ? Self.dateString(interestStartDate)
                : nil,
            dividendPerShare: kind == .dividend ? dividendPerShare : nil,
            dividendFrequency: kind == .dividend ? dividendFrequency : nil,
            dividendExDate: kind == .dividend ? Self.dateString(dividendExDate) : nil,
            dividendPayDate: kind == .dividend && hasDividendPayDate
                ? Self.dateString(dividendPayDate)
                : nil,
            positionAdjustments: existing?.positionAdjustments ?? [],
            principalAdjustments: (kind == .interest || kind == .hybrid)
                ? (existing?.principalAdjustments ?? [])
                : [],
            interestSkips: existing?.interestSkips ?? [],
            dividendRecords: dividendRecords,
            dividendRecordId: dividendRecordID,
            createdAt: existing?.createdAt ?? now,
            updatedAt: existing?.updatedAt,
            closedAt: existing?.closedAt,
            deletedAt: existing?.deletedAt
        )
    }

    mutating func apply(_ asset: AssetSearchResult) {
        symbol = asset.symbol
        quoteSymbol = asset.quoteSymbol
        name = asset.name
        assetType = asset.assetType
        exchange = asset.exchange
    }

    private static func number(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private static func numberText(_ number: Double?) -> String {
        guard let number else { return "" }
        return number.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0...8))
        )
    }

    private static func quoteSymbol(for symbol: String, assetType: AssetType) -> String {
        guard assetType == .cryptocurrency, !symbol.hasSuffix("-USD") else { return symbol }
        return "\(symbol)-USD"
    }

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return dateFormatter().date(from: string)
    }

    private static func dateString(_ date: Date) -> String {
        dateFormatter().string(from: date)
    }

    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private enum HoldingDraftError: LocalizedError {
    case missingSymbol
    case invalidQuantity
    case invalidCost
    case invalidPrincipal
    case invalidRate
    case invalidDividend
    case invalidPayDate

    var errorDescription: String? {
        switch self {
        case .missingSymbol: "请填写资产代码或名称。"
        case .invalidQuantity: "持有数量必须大于 0。"
        case .invalidCost: "单位成本必须大于 0。"
        case .invalidPrincipal: "投资本金必须大于 0。"
        case .invalidRate: "请输入 0–1000% 的年化利率。"
        case .invalidDividend: "每股或每份分红必须大于 0。"
        case .invalidPayDate: "派息日不能早于除息日。"
        }
    }
}

extension HoldingKind {
    var title: String {
        switch self {
        case .market: "市场资产"
        case .interest: "稳定生息"
        case .hybrid: "市场 + 利息"
        case .dividend: "分红资产"
        }
    }

    var explanation: String {
        switch self {
        case .market: "记录股票、ETF 或加密货币的数量与成本。"
        case .interest: "记录定存、现金管理等按本金计息的资产。"
        case .hybrid: "同时记录市场价格变化和按成本本金产生的利息。"
        case .dividend: "记录市场资产及每次除息对应的分红。"
        }
    }
}

private extension DividendFrequency {
    var title: String {
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
