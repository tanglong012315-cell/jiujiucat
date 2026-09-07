import Nvwa
import SwiftUI

/// 「添加货币」弹层：按货币代码首字母分组，右侧是字母索引，顶部是关键词搜索。
///
/// 币种表是写死的（`CurrencyCatalog`），不走接口——**只收录有国旗图的法币**，
/// 这是用户 2026-09-03 的要求。搜索同时匹配代码、货币名和发行地，所以敲
/// `japan`、`yen`、`JPY` 都能找到同一条。
struct CurrencyPickerView: View {
    let currencies: [CurrencyInfo]
    let onSelect: (CurrencyCode) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    /// 视觉 QA：`SIMCTL_CHILD_PAWFOLIO_QA_CURRENCY_QUERY=<关键词>` 预填搜索词，
    /// 模拟器上打不了字，只能这样看筛选后的样子。
    @State private var query = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["PAWFOLIO_QA_CURRENCY_QUERY"] ?? ""
        #else
        return ""
        #endif
    }()

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            NvwaModalHeader("Add Currency")
                .pawSheetMeasuredPart()

            VStack(spacing: 16) {
                NvwaSearchInput(
                    placeholder: "Ex. JPY, Japan, Yen",
                    text: $query,
                    searchIcon: Image("IconSearch2"),
                    clearIcon: Image("IconCloseCircleFill"),
                    focus: $isQueryFocused,
                    onClear: {
                        query = ""
                        isQueryFocused = true
                    }
                )
                .autocorrectionDisabled()
                .submitLabel(.search)
                .pawSheetMeasuredPart()

                list
            }
            .padding(16)
            .pawSheetHeightContribution(48)
        }
        .background(Nvwa.backgroundDialogue)
        .pawSheetPresentation()
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
        .presentationBackground(Nvwa.backgroundDialogue)
    }

    @ViewBuilder
    private var list: some View {
        PawAlphabeticalList(
            sections: PawAlphabeticalList.sections(
                from: currencies.filter { $0.matches(query, locale: locale) },
                letter: { String($0.code.rawValue.prefix(1)) },
                sortKey: { $0.code.rawValue }
            ),
            showsTopContentWhenSectionsEmpty: false,
            topContent: { EmptyView() },
            row: { row($0) },
            emptyState: { emptyState }
        )
    }

    private func row(_ info: CurrencyInfo) -> some View {
        Button {
            onSelect(info.code)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(info.flagAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Nvwa.line, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 4) {
                    Text(info.code.rawValue)
                        .nvwaTextStyle(Nvwa.Typography.bodyLargeSemibold, linesFillLineHeight: false)
                        .foregroundStyle(Nvwa.grayPrimary)

                    Text(info.localizedName(locale: locale))
                        .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                        .foregroundStyle(Nvwa.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            // 设计 `154:10275`：行是 py16 + 48pt 内容，不是钉死的 64。
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(NvwaPressButtonStyle())
        .overlay(alignment: .bottom) { PawDivider() }
        .accessibilityLabel(Text("Add \(info.localizedName(locale: locale))"))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("ArtNotFound")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            Text("No currency matches “\(query)”.")
                .nvwaTextStyle(Nvwa.Typography.bodySmall)
                .foregroundStyle(Nvwa.graySecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
