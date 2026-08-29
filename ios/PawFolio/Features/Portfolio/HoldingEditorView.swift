import SwiftUI

struct HoldingEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private static let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    let existingHolding: Holding?
    let marketPrice: Double?
    let onSave: (Holding) async -> Bool
    let onAdjust: (HoldingAdjustmentRequest) async throws -> Void
    /// 删除入口在弹层左上角；没传就不显示那颗按钮。
    var onDelete: ((Holding) -> Void)?

    @State private var draft: HoldingDraft
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var isAssetSearchPresented = false
    @State private var isFrequencySheetPresented = false
    @State private var isDeleteConfirmPresented = false
    @State private var adjustmentType = PositionAdjustmentKind.add
    @State private var adjustmentAmountText = ""
    @State private var adjustmentPriceText = ""
    @State private var adjustmentEffectiveDate = Date()

    init(
        holding: Holding?,
        prefilledAsset: AssetSearchResult? = nil,
        marketPrice: Double?,
        onSave: @escaping (Holding) async -> Bool,
        onAdjust: @escaping (HoldingAdjustmentRequest) async throws -> Void,
        onDelete: ((Holding) -> Void)? = nil
    ) {
        existingHolding = holding
        self.marketPrice = marketPrice
        self.onSave = onSave
        self.onAdjust = onAdjust
        self.onDelete = onDelete

        // Web 的「一键添加」是打开预填好标的的表单，而不是直接建仓
        // （`app.js` 里 `openHoldingSheet(null, asset)`）。
        var draft = HoldingDraft(holding: holding)
        if let prefilledAsset {
            draft.apply(prefilledAsset)
        }
        _draft = State(initialValue: draft)
    }

    var body: some View {
        PawSheet(
            title: existingHolding == nil ? "添加持仓" : "编辑持仓",
            // Web 把删除放在弹层左上角，和右上角的关闭对称。
            destructiveIcon: existingHolding == nil ? nil : "IconDelete",
            destructiveLabel: "删除持仓",
            onDestructive: existingHolding == nil ? nil : { isDeleteConfirmPresented = true }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if existingHolding == nil {
                    editorField("资产类型") {
                        PawSegmented(
                            options: [HoldingKind.market, .interest],
                            title: { $0 == .market ? "Stock/Crypto" : "稳定生息" },
                            selection: baseKindBinding
                        )
                    }
                }

                identityFields
                valueFields

                if let existingHolding {
                    adjustmentPanel(for: existingHolding)
                }

                if canRecordDividends {
                    incomeToggle
                }

                if draft.kind == .interest || draft.kind == .hybrid {
                    interestFields
                }

                if draft.kind == .dividend {
                    dividendPanel
                }
            }
        } footer: {
            PawPrimaryButton(title: isSaving ? "保存中…" : "保存") { save() }
                .disabled(isSaving || noteError != nil)
                .opacity(isSaving || noteError != nil ? 0.55 : 1)
        }
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $isFrequencySheetPresented) {
            DividendFrequencySheet(selection: $draft.dividendFrequency)
        }
        .sheet(isPresented: $isAssetSearchPresented) {
            AssetSearchView(initialQuery: draft.symbol) { asset in
                draft.apply(asset)
            }
        }
        .confirmationDialog(
            "删除 \(existingHolding?.symbol ?? "")？",
            isPresented: $isDeleteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("删除持仓", role: .destructive) {
                guard let existingHolding else { return }
                onDelete?(existingHolding)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这笔记录将从当前列表中移除。")
        }
        .alert("无法保存", isPresented: validationAlertBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "请检查输入内容。")
        }
        .overlay {
            if isSaving {
                ProgressView()
                    .tint(PawTheme.ink)
                    .padding(18)
                    .background(PawTheme.bg2, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .environment(\.timeZone, Self.beijingTimeZone)
    }

    private var baseKindBinding: Binding<HoldingKind> {
        Binding(
            get: { draft.kind == .interest ? .interest : .market },
            set: { draft.kind = $0 }
        )
    }

    @ViewBuilder
    private var identityFields: some View {
        if draft.kind == .interest {
            editorField("资产名称") {
                inputShell(placeholder: "例如 USDT、USD", text: $draft.symbol, keyboard: .default)
                    .textInputAutocapitalization(.characters)
            }
        } else {
            editorField("标的代码") {
                Button { isAssetSearchPresented = true } label: {
                    PawInputShell {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(PawTheme.ink40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(draft.symbol.isEmpty ? "例如 AAPL、BTC" : draft.symbol)
                                .font(PawFont.inter(16, weight: draft.symbol.isEmpty ? .regular : .medium))
                                .foregroundStyle(draft.symbol.isEmpty ? PawTheme.ink40 : PawTheme.ink)
                            if !draft.name.isEmpty, draft.name != draft.symbol {
                                Text(draft.name)
                                    .font(PawFont.inter(11))
                                    .foregroundStyle(PawTheme.ink40)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Image("IconArrowDownS")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .rotationEffect(.degrees(-90))
                            .foregroundStyle(PawTheme.ink40)
                    }
                }
                .buttonStyle(PawPressableButtonStyle())
                .accessibilityLabel(draft.symbol.isEmpty ? "搜索并选择标的" : "当前标的 \(draft.symbol)，点按重新搜索")
            }
        }
    }

    @ViewBuilder
    private var valueFields: some View {
        if draft.kind == .interest {
            editorField(
                "投资本金",
                hint: existingHolding == nil ? nil : "通过下方加仓或减仓调整本金"
            ) {
                moneyInput(text: $draft.principalText, placeholder: "0.00", disabled: existingHolding != nil)
            }
        } else {
            editorField(
                "持有数量",
                hint: existingHolding == nil ? nil : "通过下方加仓或减仓调整数量"
            ) {
                inputShell(placeholder: "0", text: $draft.quantityText, disabled: existingHolding != nil)
            }
            editorField("单位成本价（可选）", hint: "不填写时，将使用保存时的最新价格作为成本价") {
                moneyInput(text: $draft.costPerShareText, placeholder: "0.00")
            }

            noteField
        }
    }

    /// 备注。市场类挂在单位成本价下面；稳定生息没有成本价那一格，改挂在计息方式下面。
    ///
    /// 不写「最多 20 个字」这类说明：正常输入的人根本用不到，只有超了才需要被告知。
    /// 所以既不截断也不拦输入，超了就报错并挡住保存——截断会让人以为自己打漏了字。
    private var noteField: some View {
        editorField("备注（可选）", error: noteError) {
            PawTextFieldShell(
                placeholder: "例如：定投账户",
                text: $draft.note,
                keyboard: .default,
                onClear: draft.note.isEmpty ? nil : { draft.note = "" }
            )
        }
    }

    /// 超出长度时的提示。数 `Character`，和 `Holding.normalizedNote` 同一把尺子。
    private var noteError: String? {
        let count = draft.note.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard count > Holding.noteCharacterLimit else { return nil }
        return "备注最多 \(Holding.noteCharacterLimit) 个字，当前 \(count) 个"
    }

    private func adjustmentPanel(for holding: Holding) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("调整持仓")
                .font(PawFont.inter(14, weight: .semibold))
                .foregroundStyle(PawTheme.ink)

            PawSegmented(
                options: [PositionAdjustmentKind.add, .reduce],
                title: { $0 == .add ? "加仓" : "减仓" },
                selection: $adjustmentType
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { adjustmentFields(for: holding) }
                VStack(alignment: .leading, spacing: 14) { adjustmentFields(for: holding) }
            }

            Text(adjustmentHint(for: holding))
                .font(PawFont.inter(12))
                .foregroundStyle(PawTheme.ink40)

            Button { applyAdjustment(to: holding) } label: {
                Text(adjustmentType == .add ? "确认加仓" : "确认减仓")
                    .font(PawFont.inter(13, weight: .semibold))
                    .foregroundStyle(PawTheme.bg1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(PawTheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PawPressableButtonStyle())
            .disabled(isSaving || adjustmentAmountText.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(adjustmentAmountText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
        }
        .padding(16)
        .background(PawTheme.ink4, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func adjustmentFields(for holding: Holding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                PawFieldLabel(holding.holdingKind == .interest ? "调整金额" : "调整数量")
                Spacer()
                if holding.holdingKind != .interest, adjustmentType == .reduce {
                    Button("全部") { adjustmentAmountText = Self.numberText(holding.quantity) }
                        .font(PawFont.inter(12, weight: .semibold))
                        .foregroundStyle(PawTheme.accent)
                        .buttonStyle(.plain)
                }
            }
            if holding.holdingKind == .interest {
                moneyInput(text: $adjustmentAmountText, placeholder: "0.00", compact: true)
            } else {
                inputShell(placeholder: "0", text: $adjustmentAmountText, compact: true)
            }
        }
        .frame(maxWidth: .infinity)

        if holding.holdingKind == .interest {
            editorField("生效日期") {
                dateInput(selection: $adjustmentEffectiveDate, minimumDate: Self.beijingStartOfToday)
            }
            .frame(maxWidth: .infinity)
        } else {
            editorField("成交价格") {
                moneyInput(
                    text: $adjustmentPriceText,
                    placeholder: marketPrice.map { Self.numberText($0) } ?? "市场价",
                    compact: true
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var canRecordDividends: Bool {
        draft.kind != .interest && (draft.assetType == .equity || draft.assetType == .etf)
    }

    private var incomeToggle: some View {
        Button {
            draft.kind = draft.kind == .market ? .dividend : .market
        } label: {
            HStack(spacing: 12) {
                Image(draft.kind == .market ? "IconCheckboxBlank" : "IconCheckboxFill")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(PawTheme.ink)

                Text("记录分红")
                    .font(PawFont.inter(14, weight: .semibold))
                    .foregroundStyle(PawTheme.ink)

                Spacer()
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(PawPressableButtonStyle())
    }

    private var interestFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorField("年化利率（APR）") {
                PawInputShell {
                    TextField("0.00", text: $draft.annualRateText)
                        .keyboardType(.decimalPad)
                        .font(PawFont.inter(16, weight: .medium).monospacedDigit())
                        .foregroundStyle(PawTheme.ink)
                    Text("%")
                        .font(PawFont.inter(16, weight: .medium))
                        .foregroundStyle(PawTheme.ink40)
                }
            }

            editorField("计息方式") {
                PawSegmented(
                    options: InterestMode.allCases,
                    title: { $0 == .simple ? "单利" : "每日复利" },
                    selection: $draft.interestMode
                )
            }

            // 只有纯生息才在这里出现。hybrid 有成本价那一格，备注跟在那儿。
            if draft.kind == .interest {
                noteField
            }

            editorField("起息日期", hint: "首次结算为起息日次日，可选未来日期（T+1／T+2 起息）") {
                dateInput(selection: $draft.interestStartDate)
            }

            yieldPreview
        }
    }

    private var dividendPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("本次分红")
                .font(PawFont.inter(14, weight: .semibold))
                .foregroundStyle(PawTheme.ink)

            editorField(draft.assetType == .etf ? "每份分红" : "每股分红") {
                moneyInput(text: $draft.dividendPerShareText, placeholder: "0.00")
            }

            // 和分红记录弹层用同一个频率选择器，Web 那边也是同一个 overlay。
            editorField("分红频率", hint: "频率仅用于说明，不会自动推算未公告的分红") {
                Button {
                    isFrequencySheetPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Text(draft.dividendFrequency.controlTitle)
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

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    dividendDateFields
                }
                VStack(alignment: .leading, spacing: 16) {
                    dividendDateFields
                }
            }

            Text("分红在除息日确认，派息日只用于记录实际到账时间")
                .font(PawFont.inter(12))
                .foregroundStyle(PawTheme.ink40)

            dividendPreview
        }
        .padding(16)
        .background(PawTheme.bg2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(PawTheme.ink10, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dividendDateFields: some View {
        editorField("除息日") { dateInput(selection: $draft.dividendExDate) }
            .frame(maxWidth: .infinity)
        editorField("派息日（可选）") {
            if draft.hasDividendPayDate {
                dateInput(selection: $draft.dividendPayDate)
            } else {
                Button { draft.hasDividendPayDate = true } label: {
                    PawInputShell(horizontalPadding: 12) {
                        Text("选择日期")
                            .font(PawFont.inter(16))
                            .foregroundStyle(PawTheme.ink40)
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundStyle(PawTheme.ink40)
                    }
                }
                .buttonStyle(PawPressableButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var yieldPreview: some View {
        let principal = Self.number(from: draft.kind == .interest ? draft.principalText : draft.quantityText)
        let rate = Self.number(from: draft.annualRateText)
        let basis = draft.kind == .hybrid
            ? (principal ?? 0) * (Self.number(from: draft.costPerShareText) ?? marketPrice ?? 0)
            : (principal ?? 0)
        let text = basis > 0 && (rate ?? 0) > 0
            ? "预计每日收益 \(currencyText(basis * (rate ?? 0) / 100 / 365)) · 每日 16:00（北京时间）更新"
            : (draft.kind == .hybrid ? "填写数量与年化利率后显示预计收益" : "填写本金与年化利率后显示预计收益")
        return preview(text)
    }

    private var dividendPreview: some View {
        let quantity = Self.number(from: draft.quantityText) ?? 0
        let perShare = Self.number(from: draft.dividendPerShareText) ?? 0
        let text = quantity > 0 && perShare > 0
            ? "本次预计分红 \(currencyText(quantity * perShare)) · 不按日累计，不计算复利"
            : "填写数量与每股分红后显示本次收益"
        return preview(text)
    }

    private func preview(_ text: String) -> some View {
        Text(text)
            .font(PawFont.inter(12).monospacedDigit())
            .foregroundStyle(PawTheme.ink80)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PawTheme.ink4, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(PawTheme.ink10, lineWidth: 1)
            )
    }

    private func editorField<Content: View>(
        _ label: String,
        hint: String? = nil,
        error: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PawFieldLabel(label)

            // 说明贴着控件走，用嵌套的 4pt 间距而不是负 padding——
            // 负 padding 会让外层少算高度。
            VStack(alignment: .leading, spacing: 4) {
                content()
                // 错误顶掉说明：两条一起显示只会让人先读到不相干的那条。
                if let error {
                    Text(error)
                        .font(PawFont.inter(12))
                        .foregroundStyle(PawTheme.loss)
                } else if let hint {
                    Text(hint)
                        .font(PawFont.inter(12))
                        .foregroundStyle(PawTheme.ink40)
                }
            }
        }
    }

    private func inputShell(
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .decimalPad,
        disabled: Bool = false,
        compact: Bool = false
    ) -> some View {
        PawInputShell(horizontalPadding: compact ? 12 : 16) {
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(PawFont.inter(16, weight: .medium).monospacedDigit())
                .foregroundStyle(disabled ? PawTheme.ink40 : PawTheme.ink)
                .disabled(disabled)
        }
    }

    private func moneyInput(
        text: Binding<String>,
        placeholder: String,
        disabled: Bool = false,
        compact: Bool = false
    ) -> some View {
        PawInputShell(horizontalPadding: compact ? 12 : 16) {
            Text("$")
                .font(PawFont.inter(16, weight: .medium))
                .foregroundStyle(PawTheme.ink40)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(PawFont.inter(16, weight: .medium).monospacedDigit())
                .foregroundStyle(disabled ? PawTheme.ink40 : PawTheme.ink)
                .disabled(disabled)
        }
    }

    private func dateInput(selection: Binding<Date>, minimumDate: Date? = nil) -> some View {
        PawInputShell(horizontalPadding: 12) {
            if let minimumDate {
                DatePicker("", selection: selection, in: minimumDate...Date.distantFuture, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(PawTheme.ink)
            } else {
                DatePicker("", selection: selection, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(PawTheme.ink)
            }
            Spacer(minLength: 0)
        }
    }

    private func adjustmentHint(for holding: Holding) -> String {
        if holding.holdingKind == .interest {
            return "生效日次日的结算起按新本金计息，已发放的利息不变"
        }
        if adjustmentType == .add {
            return "按成交价计入成本；留空使用市场价，操作瞬间总盈亏不变"
        }
        return "按成交价卖出，卖得的金额自动转成 USDT 持仓；点「全部」即清仓"
    }

    private func currencyText(_ value: Double) -> String {
        "$" + value.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }

    private var validationAlertBinding: Binding<Bool> {
        Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )
    }

    private func save() {
        do {
            let holding = try draft.makeHolding(
                existing: existingHolding,
                fallbackPrice: marketPrice
            )
            isSaving = true
            Task {
                let didSave = await onSave(holding)
                isSaving = false
                if didSave {
                    PawToastCenter.shared.show(
                        existingHolding == nil ? "\(holding.symbol) 已添加" : "\(holding.symbol) 已更新"
                    )
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
                // Web 在加减仓完成后给一条 toast，说明动作确实生效了。
                PawToastCenter.shared.show(
                    adjustmentType == .add ? "已完成加仓" : "已完成减仓"
                )
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
    var note: String

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
        note = holding?.note ?? ""
    }

    func makeHolding(existing: Holding?, fallbackPrice: Double? = nil) throws -> Holding {
        let normalizedSymbol = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw HoldingDraftError.missingSymbol
        }

        // 界面已经挡了保存按钮，这里再拦一道：草稿还会被别的路径拿去构造持仓。
        guard note.trimmingCharacters(in: .whitespacesAndNewlines).count <= Holding.noteCharacterLimit else {
            throw HoldingDraftError.noteTooLong
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date().timeIntervalSince1970 * 1_000
        let quantity = Self.number(from: quantityText)
        // 留空时落到保存那一刻的最新价；连行情都没有就真的不带成本，
        // 由估值那边按「行情不可用」处理，而不是拦着不让保存。
        let costPerShare = Self.number(from: costPerShareText) ?? fallbackPrice
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
            // 成本可以不填——字段标签写的就是「单位成本价（可选）」，提示还承诺
            // 不填时用最新价补上。只有填了却填得不对才拦。
            if !costPerShareText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let costPerShare, costPerShare.isFinite, costPerShare > 0 else {
                    throw HoldingDraftError.invalidCost
                }
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
            note: note,
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
    case noteTooLong
    case invalidQuantity
    case invalidCost
    case invalidPrincipal
    case invalidRate
    case invalidDividend
    case invalidPayDate

    var errorDescription: String? {
        switch self {
        case .missingSymbol: "请填写资产代码或名称。"
        case .noteTooLong: "备注最多 \(Holding.noteCharacterLimit) 个字。"
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
