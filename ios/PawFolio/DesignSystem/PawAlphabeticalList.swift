import Nvwa
import SwiftUI

private enum Metrics {
    static let sectionHeaderHeight: CGFloat = 28
    static let indexWidth: CGFloat = 20
    /// 字母的热区是 20×20（用户 2026-09-03 的要求：点得准一点）。
    static let indexLetterHeight: CGFloat = 20
    static let scrollSpace = "paw.alphabetical.scroll"
}

/// 按首字母分组的长列表 + 右侧字母索引条，设计 `154:10266`「Add Currency」那一套。
///
/// 汇率页的币种选择器和 V2.1.0 Fiat / Spot 的资产选择器用的是同一个设计，
/// 所以分组表头、索引条、End 收尾都收在这里，两边只各自提供「行」怎么画。
/// 别再在业务页里重描一遍——第一版的 `LedgerAssetPicker` 就是那么写的，
/// 结果分组、索引条、行描边全丢了。
struct PawAlphabeticalList<Item: Identifiable, TopContent: View, Row: View, Empty: View>: View {
    struct Section: Identifiable {
        let letter: String
        let items: [Item]
        var id: String { letter }
    }

    let sections: [Section]
    let showsTopContentWhenSectionsEmpty: Bool
    @ViewBuilder let topContent: () -> TopContent
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let emptyState: () -> Empty

    @State private var activeLetter: String?

    var body: some View {
        if sections.isEmpty, !showsTopContentWhenSectionsEmpty {
            emptyState()
                .pawSheetMeasuredPart()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        topContent()

                        ForEach(sections) { section in
                            SwiftUI.Section {
                                ForEach(section.items) { item in
                                    row(item)
                                }
                            } header: {
                                sectionHeader(section.letter)
                            }
                            .id(section.letter)
                        }

                        // 设计 `27:1404`：列表末尾有一条 End 收尾。
                        Text("End")
                            .nvwaTextStyle(Nvwa.Typography.bodySmall, linesFillLineHeight: false)
                            .foregroundStyle(Nvwa.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .pawSheetMeasuredPart()
                }
                .coordinateSpace(name: Metrics.scrollSpace)
                .scrollDismissesKeyboard(.immediately)
                .onPreferenceChange(PawSectionOffsetKey.self) { offsets in
                    let passed = offsets
                        .filter { $0.value <= 0.5 }
                        .max { $0.value < $1.value }?
                        .key
                    activeLetter = passed ?? sections.first?.letter
                }
                .overlay(alignment: .trailing) {
                    // 搜到只剩一两组时索引条没有意义，藏起来别挡内容。
                    if sections.count > 2 {
                        alphabetIndex(proxy: proxy)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ letter: String) -> some View {
        Text(letter)
            .font(Nvwa.bodySmallSemibold)
            .tracking(0.12)
            .foregroundStyle(Nvwa.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Metrics.sectionHeaderHeight)
            .background(Nvwa.backgroundDialogue)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: PawSectionOffsetKey.self,
                        value: [letter: geometry.frame(in: .named(Metrics.scrollSpace)).minY]
                    )
                }
            }
    }

    /// 右侧字母索引：点一下跳到那一组，按住上下滑也能连续跳（和系统通讯录一致）。
    private func alphabetIndex(proxy: ScrollViewProxy) -> some View {
        let letters = sections.map(\.letter)

        return VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(Nvwa.font(11, weight: .semibold))
                    // 只有列表当前停着的那一组是蓝的，其余是灰的。
                    .foregroundStyle(letter == activeLetter ? Nvwa.primaryGreen : Nvwa.textSecondary)
                    .frame(width: Metrics.indexWidth, height: Metrics.indexLetterHeight)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let index = Int(value.location.y / Metrics.indexLetterHeight)
                    guard letters.indices.contains(index) else { return }
                    activeLetter = letters[index]
                    proxy.scrollTo(letters[index], anchor: .top)
                }
        )
        .accessibilityHidden(true)
    }
}

extension PawAlphabeticalList {
    /// 把一串条目按 `letter` 分组、组内按 `sortKey` 排序，组间按字母排。
    static func sections(
        from items: [Item],
        letter: (Item) -> String,
        sortKey: (Item) -> String
    ) -> [Section] {
        Dictionary(grouping: items, by: letter)
            .sorted { $0.key < $1.key }
            .map { Section(letter: $0.key, items: $0.value.sorted { sortKey($0) < sortKey($1) }) }
    }
}

/// 每个分组表头在滚动坐标系里的纵向位置。表头是 pinned 的，贴在顶上的那一个 `minY`
/// 停在 0，已经划过去的是负数——所以「`minY` ≤ 0 里最靠下的那个」就是当前分组。
struct PawSectionOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
