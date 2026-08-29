import SwiftUI

/// Web 的「盈亏明细」弹层（`#profit-sheet-overlay`）。
///
/// Web 这里只有一张明细清单加两个记录入口——调整是一次性操作，Web 不给它做历史列表。
/// 原生多做了一个调整记录列表，作为第三个入口保留（见 `MIGRATION_PLAN.md`）。
struct HoldingDetailView: View {
    @ObservedObject var model: PortfolioViewModel

    let holdingID: String

    @Environment(\.dismiss) private var dismiss

    @State private var isHoldingEditorPresented = false
    @State private var recordsRoute: RecordsRoute?
    @State private var dividendEditorRoute: DividendEditorRoute?
    @State private var pendingInterestSkip: InterestRecordEntry?
    @State private var pendingDividendDeletion: DividendRecord?
    @State private var localErrorMessage: String?

    private var now: TimeInterval { Date().timeIntervalSince1970 * 1_000 }

    var body: some View {
        Group {
            if let holding = model.holding(withID: holdingID) {
                sheet(for: holding)
            } else {
                PawSheet(title: "盈亏明细") {
                    Text("该持仓可能已经被删除。")
                        .font(PawFont.inter(13))
                        .foregroundStyle(PawTheme.ink40)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
            }
        }
        .alert("无法更新记录", isPresented: errorAlertBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(localErrorMessage ?? "请稍后重试。")
        }
    }

    private func sheet(for holding: Holding) -> some View {
        PawSheet(title: "盈亏明细") {
            VStack(alignment: .leading, spacing: 16) {
                summary(for: holding)
                breakdown(for: holding)

                if holding.holdingKind == .dividend, let record = latestDividendRecord(of: holding) {
                    latestDividendCard(record: record, holding: holding)
                }

                recordEntries(for: holding)
            }
        } footer: {
            PawPrimaryButton(title: "编辑持仓") {
                isHoldingEditorPresented = true
            }
        }
        .sheet(isPresented: $isHoldingEditorPresented) {
            HoldingEditorView(
                holding: holding,
                marketPrice: model.marketPrice(for: holding),
                onSave: { updatedHolding in
                    await model.upsert(updatedHolding)
                },
                onAdjust: { request in
                    try await model.adjust(request)
                },
                onDelete: { holding in
                    Task {
                        await model.delete(holding)
                        PawToastCenter.shared.show("\(holding.symbol) 已删除")
                    }
                    dismiss()
                }
            )
        }
        .sheet(item: $recordsRoute) { route in
            PawSheet(title: route.title) {
                switch route.kind {
                case .dividend: dividendIncomeList(for: holding)
                case .interest: interestIncomeList(for: holding)
                case .adjustment: activityList(for: holding)
                }
            }
        }
        .sheet(item: $dividendEditorRoute) { route in
            DividendRecordEditorView(
                holding: holding,
                record: route.record
            ) { request in
                try await model.upsertDividendRecord(request)
            }
        }
        .confirmationDialog(
            "将这一天标记为未发放？",
            isPresented: interestSkipDialogBinding,
            titleVisibility: .visible
        ) {
            Button("标记未发放", role: .destructive) {
                guard let entry = pendingInterestSkip else { return }
                pendingInterestSkip = nil
                Task {
                    do {
                        try await model.skipInterestSettlement(holdingID: holdingID, date: entry.date)
                        PawToastCenter.shared.show("该日利息已删除，总利息已更新")
                    } catch {
                        show(error)
                    }
                }
            }
            Button("取消", role: .cancel) { pendingInterestSkip = nil }
        } message: {
            if let entry = pendingInterestSkip {
                Text(interestSkipMessage(for: entry, holding: holding))
            }
        }
        .confirmationDialog(
            "删除这条分红记录？",
            isPresented: dividendDeletionDialogBinding,
            titleVisibility: .visible
        ) {
            Button("删除记录", role: .destructive) {
                guard let record = pendingDividendDeletion else { return }
                pendingDividendDeletion = nil
                Task {
                    do {
                        try await model.deleteDividendRecord(holdingID: holdingID, recordID: record.id)
                        PawToastCenter.shared.show("分红记录已删除，总盈亏已更新")
                    } catch {
                        show(error)
                    }
                }
            }
            Button("取消", role: .cancel) { pendingDividendDeletion = nil }
        } message: {
            if let record = pendingDividendDeletion {
                Text("删除后，已确认分红最多减少 \(currency(record.amount))。")
            }
        }
    }

    // MARK: 顶部汇总（Web `.profit-sheet-summary`）

    private func summary(for holding: Holding) -> some View {
        let metrics = model.metrics(for: holding)
        let profit = metrics.profit

        return VStack(spacing: 3) {
            Text(holding.symbol)
                .font(PawFont.inter(13, weight: .semibold))
                .foregroundStyle(PawTheme.ink40)

            Text(profit.map(signedCurrency) ?? "$—")
                .font(PawFont.inter(30, weight: .semibold).monospacedDigit())
                .foregroundStyle(tone(for: profit))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(holding.holdingKind == .interest ? "总利息" : "总盈亏")
                .font(PawFont.inter(12))
                .foregroundStyle(PawTheme.ink40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: 明细清单（Web `.profit-breakdown-list`）

    private func breakdown(for holding: Holding) -> some View {
        let metrics = model.metrics(for: holding)
        let isMarketBased = holding.holdingKind != .interest
        let earnsInterest = holding.holdingKind == .interest || holding.holdingKind == .hybrid
        let next = HoldingValuation.nextInterestSettlement(for: holding, at: now)
        let last = HoldingValuation.lastInterestSettlement(for: holding, at: now)

        var rows: [BreakdownRow] = [
            BreakdownRow(
                title: "总资产",
                detail: "按最新价计算",
                value: metrics.value.map(currency) ?? "$—"
            ),
            BreakdownRow(
                title: "持仓盈亏",
                detail: "当前市值减去持仓成本",
                value: metrics.profit.map(signedCurrency) ?? "$—",
                tone: tone(for: metrics.profit)
            )
        ]

        if isMarketBased, metrics.quantity > 0 {
            rows.append(
                BreakdownRow(
                    title: "持有份数",
                    detail: "当前持有数量",
                    value: metrics.quantity.formatted(.number.precision(.fractionLength(0...6)))
                )
            )
            if let cost = holding.costPerShare {
                rows.append(
                    BreakdownRow(title: "成本价", detail: "每份买入成本", value: currency(cost))
                )
            }
            if let price = metrics.marketPrice {
                rows.append(
                    BreakdownRow(title: "最新价", detail: "按最新成交价", value: currency(price))
                )
            }
        }

        if earnsInterest {
            if let rate = holding.annualRate {
                rows.append(
                    BreakdownRow(
                        title: "年化收益率（APR）",
                        detail: "当前持仓设置",
                        value: rate.formatted(.number.precision(.fractionLength(2))) + "%"
                    )
                )
            }
            rows.append(
                BreakdownRow(
                    title: "每日预计利息",
                    detail: "下次结算北京时间 16:00",
                    value: signedCurrency(next?.amount ?? 0),
                    tone: tone(for: next?.amount)
                )
            )
            rows.append(
                BreakdownRow(
                    title: "昨日实现利息",
                    detail: last.map { "已于 \($0.date) 结算" } ?? "暂无已结算利息",
                    value: signedCurrency(last?.amount ?? 0),
                    tone: tone(for: last?.amount)
                )
            )
            rows.append(
                BreakdownRow(
                    title: "总实现利息",
                    detail: "收益每日于北京时间 16:00 更新",
                    value: signedCurrency(metrics.accruedInterest),
                    tone: tone(for: metrics.accruedInterest)
                )
            )
        }

        if holding.holdingKind == .dividend || metrics.confirmedDividends > 0 {
            rows.append(
                BreakdownRow(
                    title: "分红收益",
                    detail: metrics.confirmedDividends > 0 ? "已确认分红合计" : "暂无已确认分红",
                    value: signedCurrency(metrics.confirmedDividends),
                    tone: tone(for: metrics.confirmedDividends)
                )
            )
        }

        // 没写备注就整行不出现——这是用户明确要的：空备注不占位。
        if let note = holding.note {
            rows.append(
                BreakdownRow(
                    title: "备注",
                    detail: "",
                    value: note,
                    isProse: true
                )
            )
        }

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.title) { index, row in
                if index > 0 {
                    PawDivider()
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(PawFont.inter(14, weight: .semibold))
                            .foregroundStyle(PawTheme.ink)

                        if !row.detail.isEmpty {
                            Text(row.detail)
                                .font(PawFont.inter(11))
                                .foregroundStyle(PawTheme.ink40)
                        }
                    }

                    Spacer(minLength: 0)

                    Text(row.value)
                        .font(
                            row.isProse
                                ? PawFont.inter(14)
                                : PawFont.inter(14, weight: .semibold).monospacedDigit()
                        )
                        .foregroundStyle(row.tone ?? PawTheme.ink)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(row.isProse ? 2 : 1)
                        .minimumScaleFactor(row.isProse ? 1 : 0.6)
                }
                .frame(minHeight: 64)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .background(
            PawTheme.bg2,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private struct BreakdownRow {
        let title: String
        let detail: String
        let value: String
        var tone: Color?
        /// 备注这类右侧是文字而不是数字的行：不用等宽数字、不缩字号，允许折成两行。
        var isProse = false
    }

    // MARK: 最近一次分红（Web `.profit-event-card`）

    private func latestDividendRecord(of holding: Holding) -> DividendRecord? {
        holding.dividendRecords.max { $0.exDate < $1.exDate }
    }

    private func latestDividendCard(record: DividendRecord, holding: Holding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近一次分红")
                .font(PawFont.inter(13, weight: .semibold))
                .foregroundStyle(PawTheme.ink)

            // 固定两列，四个字段排成 2×2——auto-fit 在窄屏下会把第四个吊在第二行。
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 12
            ) {
                eventCell("分红频率", frequencyText(record: record, holding: holding))
                eventCell("每股分红", currency(record.perShare))
                eventCell("除息日", record.exDate.isEmpty ? "—" : record.exDate)
                eventCell("派息日", record.payDate.isEmpty ? "待定" : record.payDate)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(PawTheme.ink10, lineWidth: 1)
        )
    }

    /// Web 写成「季度分红」这种形式（`DIVIDEND_FREQUENCY_LABELS` 后面直接接「分红」）。
    private func frequencyText(record: DividendRecord, holding: Holding) -> String {
        record.frequency.webLabel + "分红"
    }

    private func eventCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(PawFont.inter(11))
                .foregroundStyle(PawTheme.ink40)

            Text(value)
                .font(PawFont.inter(12, weight: .semibold).monospacedDigit())
                .foregroundStyle(PawTheme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: 记录入口（Web `.profit-records-btn`）

    @ViewBuilder
    private func recordEntries(for holding: Holding) -> some View {
        let interestCount = HoldingValuation.interestRecordEntries(for: holding, at: now).count
        let adjustmentCount = holding.positionAdjustments.count + holding.principalAdjustments.count

        VStack(spacing: 8) {
            if holding.holdingKind == .dividend || !holding.dividendRecords.isEmpty {
                recordButton(
                    title: "分红记录",
                    count: holding.dividendRecords.count,
                    kind: .dividend
                )
            }

            if interestCount > 0 {
                recordButton(title: "利息发放记录", count: interestCount, kind: .interest)
            }

            if adjustmentCount > 0 {
                recordButton(title: "调整记录", count: adjustmentCount, kind: .adjustment)
            }
        }
    }

    private func recordButton(title: String, count: Int, kind: RecordsRoute.Kind) -> some View {
        Button {
            recordsRoute = RecordsRoute(kind: kind, title: title)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PawFont.inter(14, weight: .semibold))
                        .foregroundStyle(PawTheme.ink)

                    Text("\(count) 条记录")
                        .font(PawFont.inter(11))
                        .foregroundStyle(PawTheme.ink40)
                }

                Spacer(minLength: 0)

                Image("IconArrowDownS")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(PawTheme.ink40)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                PawTheme.ink4,
                in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
            )
        }
        .buttonStyle(PawPressableButtonStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: 格式化

    private func tone(for value: Double?) -> Color {
        guard let value else { return PawTheme.ink }
        if value > 0 { return PawTheme.gain }
        if value < 0 { return PawTheme.loss }
        return PawTheme.flat
    }

    private func currency(_ amount: Double) -> String {
        "$" + amount.formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }

    private func signedCurrency(_ amount: Double) -> String {
        (amount > 0 ? "+" : amount < 0 ? "-" : "") + currency(abs(amount))
    }

    private func activityList(for holding: Holding) -> some View {
        let activities = HoldingActivityItem.items(for: holding)

        return VStack(alignment: .leading, spacing: 16) {
            if activities.isEmpty {
                recordEmptyState(
                    art: "ArtNoData",
                    title: "暂无调整记录",
                    detail: "后续加仓、减仓或本金调整会显示在这里。"
                )
            } else {
                Text("共 \(activities.count) 条 · 记录用于还原历史数量和本金，不会因后续编辑而覆盖")
                    .font(PawFont.inter(12))
                    .foregroundStyle(PawTheme.ink40)

                VStack(spacing: 8) {
                    ForEach(activities) { item in
                        HoldingActivityRow(item: item)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                PawTheme.ink4,
                                in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
                            )
                    }
                }
            }
        }
    }

    /// 二级记录弹层的空状态，沿用 Web 的插画写法。
    private func recordEmptyState(art: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(art)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            Text(title)
                .font(PawFont.inter(14, weight: .semibold))
                .foregroundStyle(PawTheme.ink)

            Text(detail)
                .font(PawFont.inter(12))
                .foregroundStyle(PawTheme.ink40)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    /// 记录弹层顶部的两枚汇总数字。
    private func recordSummary(_ pairs: [(String, String, Color)]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 3) {
                    Text(pair.0)
                        .font(PawFont.inter(11))
                        .foregroundStyle(PawTheme.ink40)

                    Text(pair.1)
                        .font(PawFont.inter(15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(pair.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    PawTheme.ink4,
                    in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
                )
            }
        }
    }

    @ViewBuilder
    private func interestIncomeList(for holding: Holding) -> some View {
        let now = Date().timeIntervalSince1970 * 1_000
        let allEntries = HoldingValuation.interestRecordEntries(for: holding, at: now)
            .sorted { $0.date > $1.date }
        let visibleEntries = Array(allEntries.prefix(15))
        let monthGroups = InterestMonthGroup.groups(visibleEntries: visibleEntries, allEntries: allEntries)
        let total = allEntries.reduce(0) { $0 + $1.amount }

        VStack(alignment: .leading, spacing: 16) {
            recordSummary([
                ("已发放利息", currency(total), PawTheme.gain),
                ("有效结算", "\(allEntries.count) 次", PawTheme.ink)
            ])

            if monthGroups.isEmpty {
                recordEmptyState(
                    art: "ArtNoData",
                    title: "还没有利息记录",
                    detail: (holding.annualRate ?? 0) > 0
                        ? "尚未到首次结算时间。"
                        : "当前年化利率为 0%，不会生成利息记录。"
                )
            } else {
                ForEach(monthGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.title)
                                .font(PawFont.inter(12, weight: .semibold))
                                .foregroundStyle(PawTheme.ink40)

                            Spacer(minLength: 0)

                            Text(currency(group.total))
                                .font(PawFont.inter(12).monospacedDigit())
                                .foregroundStyle(PawTheme.ink40)
                        }

                        VStack(spacing: 8) {
                            ForEach(group.entries) { entry in
                                InterestRecordRow(entry: entry)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        PawTheme.ink4,
                                        in: RoundedRectangle(
                                            cornerRadius: PawTheme.radiusCard, style: .continuous
                                        )
                                    )
                                    .contextMenu {
                                        Button("标记未发放", role: .destructive) {
                                            pendingInterestSkip = entry
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            if allEntries.count > visibleEntries.count {
                Text("只显示最近 15 次，共 \(allEntries.count) 次。汇总金额包含全部记录。")
                    .font(PawFont.inter(11))
                    .foregroundStyle(PawTheme.ink40)
            }

            if !holding.interestSkips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未发放日期")
                        .font(PawFont.inter(12, weight: .semibold))
                        .foregroundStyle(PawTheme.ink40)

                    ForEach(holding.interestSkips.sorted(by: >), id: \.self) { date in
                        HStack {
                            Text(Self.displayDate(date))
                                .font(PawFont.inter(13).monospacedDigit())
                                .foregroundStyle(PawTheme.ink)

                            Spacer(minLength: 0)

                            Button("恢复") {
                                Task {
                                    do {
                                        try await model.restoreInterestSettlement(
                                            holdingID: holdingID, date: date
                                        )
                                    } catch {
                                        show(error)
                                    }
                                }
                            }
                            .font(PawFont.inter(13, weight: .medium))
                            .foregroundStyle(PawTheme.accent)
                            .buttonStyle(PawPressableButtonStyle())
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(
                            PawTheme.ink4,
                            in: RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
                        )
                    }
                }
            }
        }
    }

    private func dividendIncomeList(for holding: Holding) -> some View {
        let today = HoldingValuation.beijingDateString(
            timestampMilliseconds: Date().timeIntervalSince1970 * 1_000
        )
        let allRecords = holding.dividendRecords.sorted {
            $0.exDate == $1.exDate ? $0.createdAt > $1.createdAt : $0.exDate > $1.exDate
        }
        let visibleRecords = Array(allRecords.prefix(15))
        let confirmedTotal = allRecords.reduce(0) { total, record in
            record.exDate <= today ? total + record.amount : total
        }

        return VStack(alignment: .leading, spacing: 16) {
            recordSummary([
                ("已确认分红", currency(confirmedTotal), PawTheme.gain),
                ("记录数量", "\(allRecords.count) 条", PawTheme.ink)
            ])

            Button {
                dividendEditorRoute = DividendEditorRoute(record: nil)
            } label: {
                HStack(spacing: 6) {
                    Image("IconAdd")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)

                    Text("添加分红记录")
                        .font(PawFont.inter(13, weight: .medium))
                }
                .foregroundStyle(PawTheme.ink40)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: PawTheme.radiusCard, style: .continuous)
                        .strokeBorder(PawTheme.ink20, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
            }
            .buttonStyle(PawPressableButtonStyle())

            if allRecords.isEmpty {
                recordEmptyState(
                    art: "ArtNoData",
                    title: "暂无分红记录",
                    detail: "添加一条后，确认的分红会计入总收益。"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleRecords) { record in
                        Button {
                            dividendEditorRoute = DividendEditorRoute(record: record)
                        } label: {
                            DividendRecordRow(record: record, today: today)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    PawTheme.ink4,
                                    in: RoundedRectangle(
                                        cornerRadius: PawTheme.radiusCard, style: .continuous
                                    )
                                )
                        }
                        .buttonStyle(PawPressableButtonStyle())
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                pendingDividendDeletion = record
                            }
                        }
                    }
                }

                if allRecords.count > visibleRecords.count {
                    Text("只显示最近 15 次，共 \(allRecords.count) 次。汇总金额包含全部记录。")
                        .font(PawFont.inter(11))
                        .foregroundStyle(PawTheme.ink40)
                }
            }
        }
    }

    private var interestSkipDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingInterestSkip != nil },
            set: { if !$0 { pendingInterestSkip = nil } }
        )
    }

    private var dividendDeletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDividendDeletion != nil },
            set: { if !$0 { pendingDividendDeletion = nil } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { localErrorMessage != nil },
            set: { if !$0 { localErrorMessage = nil } }
        )
    }

    private func interestSkipMessage(
        for entry: InterestRecordEntry,
        holding: Holding
    ) -> String {
        let amount = entry.amount.formatted(.currency(code: "USD"))
        if (holding.interestMode ?? .simple) == .compound {
            return "\(Self.displayDate(entry.date)) 起将少复利一天，总利息至少减少 \(amount)。"
        }
        return "标记后，总利息将减少 \(amount)。可在未发放日期中恢复。"
    }

    private func show(_ error: Error) {
        localErrorMessage = (error as? LocalizedError)?.errorDescription ?? "记录保存失败，请重试。"
    }

    private static func displayDate(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "/")
    }

}

/// 二级记录弹层的路由。Web 的分红记录也是从明细弹层再推一层。
private struct RecordsRoute: Identifiable {
    enum Kind {
        case dividend
        case interest
        /// Web 没有这一项：调整在那边是一次性操作，不做历史列表。原生保留它。
        case adjustment
    }

    let id = UUID()
    let kind: Kind
    let title: String
}

private struct DividendEditorRoute: Identifiable {
    let id = UUID()
    let record: DividendRecord?
}

private struct DetailValueRow: View {
    enum Style {
        case money
        case number
        case percent
    }

    let title: String
    let value: Double?
    let style: Style

    var body: some View {
        LabeledContent(title) {
            if let value {
                switch style {
                case .money:
                    Text(value, format: .currency(code: "USD"))
                case .number:
                    Text(value, format: .number.precision(.fractionLength(0...8)))
                case .percent:
                    Text("\(value.formatted(.number.precision(.fractionLength(0...2))))%")
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

private struct HoldingActivityItem: Identifiable {
    enum ValueKind {
        case quantity
        case money
    }

    let id: String
    let title: String
    let type: PositionAdjustmentKind
    let amount: Double
    let valueKind: ValueKind
    let price: Double?
    let effectiveDate: String?
    let occurredAt: TimeInterval

    static func items(for holding: Holding) -> [HoldingActivityItem] {
        let positions = holding.positionAdjustments.map { record in
            HoldingActivityItem(
                id: "position_\(record.id)",
                title: record.type == .add ? "加仓" : "减仓",
                type: record.type,
                amount: record.quantity,
                valueKind: .quantity,
                price: record.price,
                effectiveDate: nil,
                occurredAt: record.createdAt
            )
        }
        let principals = holding.principalAdjustments.map { record in
            HoldingActivityItem(
                id: "principal_\(record.id)",
                title: record.type == .add ? "增加本金" : "减少本金",
                type: record.type,
                amount: record.amount,
                valueKind: .money,
                price: nil,
                effectiveDate: record.date,
                occurredAt: record.at ?? record.createdAt
            )
        }
        return (positions + principals).sorted { $0.occurredAt > $1.occurredAt }
    }
}

private struct HoldingActivityRow: View {
    let item: HoldingActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PawBadge(base: 30) {
                Image(systemName: item.type == .add ? "plus" : "minus")
                    .font(PawFont.inter(11, weight: .bold))
                    .foregroundStyle(item.type == .add ? PawTheme.accent : .secondary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(PawFont.inter(14, weight: .semibold))
                Text(HoldingDetailDateFormatting.timestamp(item.occurredAt))
                    .font(PawFont.inter(11))
                    .foregroundStyle(.secondary)
                if let effectiveDate = item.effectiveDate {
                    Text("生效日 \(effectiveDate.replacingOccurrences(of: "-", with: "/"))")
                        .font(PawFont.inter(11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                switch item.valueKind {
                case .quantity:
                    Text(item.amount, format: .number.precision(.fractionLength(0...8)))
                case .money:
                    Text(item.amount, format: .currency(code: "USD"))
                }
                if let price = item.price {
                    Text("@ \(price.formatted(.currency(code: "USD")))")
                        .font(PawFont.inter(11))
                        .foregroundStyle(.secondary)
                }
            }
            .font(PawFont.inter(13, weight: .semibold))
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct InterestMonthGroup: Identifiable {
    let id: String
    let title: String
    let total: Double
    let entries: [InterestRecordEntry]

    static func groups(
        visibleEntries: [InterestRecordEntry],
        allEntries: [InterestRecordEntry]
    ) -> [InterestMonthGroup] {
        let monthOrder = visibleEntries.reduce(into: [String]()) { order, entry in
            let month = String(entry.date.prefix(7))
            if !order.contains(month) { order.append(month) }
        }
        return monthOrder.map { month in
            let parts = month.split(separator: "-")
            let title = parts.count == 2 ? "\(parts[0]) 年 \(Int(parts[1]) ?? 0) 月" : month
            return InterestMonthGroup(
                id: month,
                title: title,
                total: allEntries.filter { $0.date.hasPrefix(month) }.reduce(0) { $0 + $1.amount },
                entries: visibleEntries.filter { $0.date.hasPrefix(month) }
            )
        }
    }
}

private struct InterestRecordRow: View {
    let entry: InterestRecordEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.replacingOccurrences(of: "-", with: "/"))
                    .font(PawFont.inter(14, weight: .semibold))
                Text("本金 \(entry.principal.formatted(.currency(code: "USD")))")
                    .font(PawFont.inter(11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(entry.amount, format: .currency(code: "USD"))
                .foregroundStyle(PawTheme.gain)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("左滑可标记为未发放")
    }
}

private struct DividendRecordRow: View {
    let record: DividendRecord
    let today: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.exDate.replacingOccurrences(of: "-", with: "/"))
                        .font(PawFont.inter(14, weight: .semibold))
                    Text(record.exDate <= today ? "已确认" : "待确认")
                        .font(PawFont.inter(10, weight: .semibold))
                        .foregroundStyle(record.exDate <= today ? PawTheme.gain : .secondary)
                }
                Text("\(record.frequency.recordTitle) · \(record.quantity.formatted(.number.precision(.fractionLength(0...8)))) 份")
                    .font(PawFont.inter(11))
                    .foregroundStyle(.secondary)
                Text(record.payDate.isEmpty ? "派息日未确定" : "派息日 \(record.payDate.replacingOccurrences(of: "-", with: "/"))")
                    .font(PawFont.inter(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.amount, format: .currency(code: "USD"))
                .foregroundStyle(record.exDate <= today ? PawTheme.gain : .secondary)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("点按编辑，左滑可删除")
    }
}

private extension DividendFrequency {
    /// 对应 `app.js` 的 `DIVIDEND_FREQUENCY_LABELS`。
    var webLabel: String {
        switch self {
        case .quarterly: "季度"
        case .monthly: "月度"
        case .semimonthly: "每月两次"
        case .semiannual: "半年"
        case .annual: "年度"
        case .irregular: "不固定"
        }
    }

    var recordTitle: String {
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

private enum HoldingDetailDateFormatting {
    static func timestamp(_ milliseconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1_000))
    }
}
