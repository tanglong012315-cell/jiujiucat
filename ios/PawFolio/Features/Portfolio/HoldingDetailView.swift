import SwiftUI

struct HoldingDetailView: View {
    @ObservedObject var model: PortfolioViewModel

    let holdingID: String

    @State private var selectedSection = HoldingDetailSection.overview
    @State private var isHoldingEditorPresented = false
    @State private var dividendEditorRoute: DividendEditorRoute?
    @State private var pendingInterestSkip: InterestRecordEntry?
    @State private var pendingDividendDeletion: DividendRecord?
    @State private var localErrorMessage: String?

    var body: some View {
        Group {
            if let holding = model.holding(withID: holdingID) {
                VStack(spacing: 0) {
                    Picker("详情分类", selection: $selectedSection) {
                        ForEach(HoldingDetailSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    detailContent(for: holding)
                }
                .navigationTitle(holding.symbol)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("编辑") {
                            isHoldingEditorPresented = true
                        }
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
                        }
                    )
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
                                try await model.skipInterestSettlement(
                                    holdingID: holdingID,
                                    date: entry.date
                                )
                            } catch {
                                show(error)
                            }
                        }
                    }
                    Button("取消", role: .cancel) {
                        pendingInterestSkip = nil
                    }
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
                                try await model.deleteDividendRecord(
                                    holdingID: holdingID,
                                    recordID: record.id
                                )
                            } catch {
                                show(error)
                            }
                        }
                    }
                    Button("取消", role: .cancel) {
                        pendingDividendDeletion = nil
                    }
                } message: {
                    if let record = pendingDividendDeletion {
                        Text("删除后，已确认分红最多减少 \(record.amount.formatted(.currency(code: "USD")))。")
                    }
                }
            } else {
                ContentUnavailableView(
                    "持仓不可用",
                    systemImage: "tray",
                    description: Text("该持仓可能已经被删除。")
                )
            }
        }
        .alert("无法更新记录", isPresented: errorAlertBinding) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(localErrorMessage ?? "请稍后重试。")
        }
    }

    @ViewBuilder
    private func detailContent(for holding: Holding) -> some View {
        switch selectedSection {
        case .overview:
            overviewList(for: holding)
        case .activity:
            activityList(for: holding)
        case .income:
            incomeList(for: holding)
        }
    }

    private func overviewList(for holding: Holding) -> some View {
        let metrics = model.metrics(for: holding)
        let now = Date().timeIntervalSince1970 * 1_000

        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(holding.name)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Spacer()
                        Text(holding.holdingKind.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PawTheme.accent)
                    }

                    if let value = metrics.value {
                        Text(value, format: .currency(code: "USD"))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    } else {
                        Text("$—")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }

                    if let profit = metrics.profit {
                        Text(
                            "持仓盈亏 \(profit.formatted(.currency(code: "USD"))) "
                                + "(\(metrics.profitPercent.formatted(.number.precision(.fractionLength(2))))%)"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(profit > 0 ? PawTheme.gain : profit < 0 ? PawTheme.loss : .secondary)
                        .monospacedDigit()
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }

            Section("仓位") {
                if holding.holdingKind == .interest {
                    DetailValueRow(title: "当前本金", value: holding.principal, style: .money)
                } else {
                    DetailValueRow(title: "当前数量", value: holding.quantity, style: .number)
                    DetailValueRow(title: "单位成本", value: holding.costPerShare, style: .money)
                    DetailValueRow(title: "美元实时价", value: model.marketPrice(for: holding), style: .money)
                }

                if holding.isInterestBearing {
                    DetailValueRow(title: "年化利率", value: holding.annualRate, style: .percent)
                    LabeledContent("计息方式", value: (holding.interestMode ?? .simple).title)
                    DetailValueRow(title: "已结利息", value: metrics.accruedInterest, style: .money)
                }

                if holding.holdingKind == .dividend {
                    DetailValueRow(title: "已确认分红", value: metrics.confirmedDividends, style: .money)
                }
            }

            if holding.isInterestBearing,
               let nextSettlement = HoldingValuation.nextInterestSettlement(for: holding, at: now) {
                Section("下次结算") {
                    LabeledContent("结算日", value: Self.displayDate(nextSettlement.date))
                    DetailValueRow(title: "预计利息", value: nextSettlement.amount, style: .money)
                }
            }

            Section("资料") {
                LabeledContent("代码", value: holding.symbol)
                if !holding.exchange.isEmpty {
                    LabeledContent("交易所", value: holding.exchange)
                }
                LabeledContent("建立时间") {
                    Text(HoldingDetailDateFormatting.timestamp(holding.createdAt))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func activityList(for holding: Holding) -> some View {
        let activities = HoldingActivityItem.items(for: holding)

        return List {
            if activities.isEmpty {
                ContentUnavailableView {
                    Label("暂无调整记录", systemImage: "arrow.left.arrow.right")
                } description: {
                    Text("后续加仓、减仓或本金调整会显示在这里。")
                }
            } else {
                Section {
                    ForEach(activities) { item in
                        HoldingActivityRow(item: item)
                    }
                } header: {
                    Text("共 \(activities.count) 条")
                } footer: {
                    Text("记录用于还原历史数量和本金，不会因后续编辑而覆盖。")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func incomeList(for holding: Holding) -> some View {
        if holding.isInterestBearing {
            interestIncomeList(for: holding)
        } else if holding.holdingKind == .dividend {
            dividendIncomeList(for: holding)
        } else {
            List {
                ContentUnavailableView {
                    Label("没有收益记录", systemImage: "banknote")
                } description: {
                    Text("该持仓未启用利息或分红记录。")
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func interestIncomeList(for holding: Holding) -> some View {
        let now = Date().timeIntervalSince1970 * 1_000
        let allEntries = HoldingValuation.interestRecordEntries(for: holding, at: now)
            .sorted { $0.date > $1.date }
        let visibleEntries = Array(allEntries.prefix(15))
        let monthGroups = InterestMonthGroup.groups(visibleEntries: visibleEntries, allEntries: allEntries)
        let total = allEntries.reduce(0) { $0 + $1.amount }

        return List {
            Section {
                LabeledContent("已发放利息") {
                    Text(total, format: .currency(code: "USD"))
                        .foregroundStyle(PawTheme.gain)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                LabeledContent("有效结算", value: "\(allEntries.count) 次")
            }

            if monthGroups.isEmpty {
                Section {
                    Text((holding.annualRate ?? 0) > 0 ? "尚未到首次结算时间。" : "当前年化利率为 0%，不会生成利息记录。")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(monthGroups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            InterestRecordRow(entry: entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("未发放", role: .destructive) {
                                        pendingInterestSkip = entry
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Text(group.total, format: .currency(code: "USD"))
                                .monospacedDigit()
                        }
                    }
                }
            }

            if allEntries.count > visibleEntries.count {
                Section {
                    Text("只显示最近 15 次，共 \(allEntries.count) 次。汇总金额包含全部记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !holding.interestSkips.isEmpty {
                Section("未发放日期") {
                    ForEach(holding.interestSkips.sorted(by: >), id: \.self) { date in
                        HStack {
                            Label(Self.displayDate(date), systemImage: "calendar.badge.minus")
                            Spacer()
                            Button("恢复") {
                                Task {
                                    do {
                                        try await model.restoreInterestSettlement(
                                            holdingID: holdingID,
                                            date: date
                                        )
                                    } catch {
                                        show(error)
                                    }
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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

        return List {
            Section {
                LabeledContent("已确认分红") {
                    Text(confirmedTotal, format: .currency(code: "USD"))
                        .foregroundStyle(PawTheme.gain)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                LabeledContent("记录数量", value: "\(allRecords.count) 条")
                Button {
                    dividendEditorRoute = DividendEditorRoute(record: nil)
                } label: {
                    Label("添加分红记录", systemImage: "plus.circle.fill")
                }
            }

            if allRecords.isEmpty {
                Section {
                    Text("暂无分红记录。")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("分红记录") {
                    ForEach(visibleRecords) { record in
                        Button {
                            dividendEditorRoute = DividendEditorRoute(record: record)
                        } label: {
                            DividendRecordRow(record: record, today: today)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) {
                                pendingDividendDeletion = record
                            }
                        }
                    }
                }

                if allRecords.count > visibleRecords.count {
                    Section {
                        Text("只显示最近 15 次，共 \(allRecords.count) 次。汇总金额包含全部记录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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

private enum HoldingDetailSection: String, CaseIterable, Identifiable {
    case overview
    case activity
    case income

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "概览"
        case .activity: "调整"
        case .income: "收益"
        }
    }
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
            Image(systemName: item.type == .add ? "plus" : "minus")
                .font(.caption.bold())
                .foregroundStyle(item.type == .add ? PawTheme.accent : .secondary)
                .frame(width: 30, height: 30)
                .background(PawTheme.quietBlue, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(HoldingDetailDateFormatting.timestamp(item.occurredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let effectiveDate = item.effectiveDate {
                    Text("生效日 \(effectiveDate.replacingOccurrences(of: "-", with: "/"))")
                        .font(.caption)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.semibold))
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
                    .font(.headline)
                Text("本金 \(entry.principal.formatted(.currency(code: "USD")))")
                    .font(.caption)
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
                        .font(.headline)
                    Text(record.exDate <= today ? "已确认" : "待确认")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(record.exDate <= today ? PawTheme.gain : .secondary)
                }
                Text("\(record.frequency.recordTitle) · \(record.quantity.formatted(.number.precision(.fractionLength(0...8)))) 份")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.payDate.isEmpty ? "派息日未确定" : "派息日 \(record.payDate.replacingOccurrences(of: "-", with: "/"))")
                    .font(.caption)
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
