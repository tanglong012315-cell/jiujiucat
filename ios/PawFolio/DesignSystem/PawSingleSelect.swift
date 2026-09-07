import Nvwa
import SwiftUI

/// 设计里所有「单选」都是同一个底部弹层组件（Figma 上叫 `Simple Single Select`）：
/// `154:10896` Account、`158:17517` Type、`154:11562` Balance、`155:16083`、`155:16160`、
/// `158:18414`、`158:18491` 用的都是它。
///
/// 每行 `py16`、两端对齐；左边是 gap 8 的「可选 24pt 图标 + B-L Semi Bold 标签」，
/// 选中行右边一枚 24pt check。
///
/// **不要用原生 `Menu` 代替它。** 系统菜单没有图标、没有勾、也不是弹层，
/// V2.1.0 第一版就是这么写的，和设计对不上。
struct PawSingleSelectSheet<Option: Hashable, Icon: View>: View {
    let title: String
    let options: [Option]
    let selection: Option?
    let optionTitle: (Option) -> String
    let onSelect: (Option) -> Void
    @ViewBuilder let icon: (Option) -> Icon

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PawSheet(title: title, showsCloseButton: false) {
            LazyVStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(option)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            icon(option)
                            Text(LocalizedStringKey(optionTitle(option)))
                                .nvwaTextStyle(
                                    Nvwa.Typography.bodyLargeSemibold,
                                    linesFillLineHeight: false
                                )
                            Spacer(minLength: 8)
                            if option == selection {
                                Image("IconCheck")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .foregroundStyle(Nvwa.ink)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == selection ? [.isSelected] : [])
                }
            }
        }
    }
}

extension PawSingleSelectSheet where Icon == EmptyView {
    init(
        title: String,
        options: [Option],
        selection: Option?,
        optionTitle: @escaping (Option) -> String,
        onSelect: @escaping (Option) -> Void
    ) {
        self.init(
            title: title,
            options: options,
            selection: selection,
            optionTitle: optionTitle,
            onSelect: onSelect,
            icon: { _ in EmptyView() }
        )
    }
}

/// 表单里那种「label + 一行取值 + 尾部三角」的字段（设计 `154:10884` Account、
/// `155:13901` To Account）。点开的是上面那个单选弹层，不是系统菜单。
///
/// 字段本身就是 Nvwa 的 `NvwaSelect`（`2277:899`，`Search=No`），这里只负责把它
/// 和弹层接起来——几何和排版都别在这层重描。
struct PawSingleSelectField<Option: Hashable, Icon: View>: View {
    let label: String
    let sheetTitle: String
    let options: [Option]
    @Binding var selection: Option
    let optionTitle: (Option) -> String
    @ViewBuilder let icon: (Option) -> Icon

    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NvwaSelect(
                label: label,
                value: optionTitle(selection),
                dropdownIcon: Image("IconArrowDropDownFill")
            ) { isPresented = true }
            .accessibilityLabel(Text(LocalizedStringKey(label)))
            .accessibilityValue(optionTitle(selection))
        }
        .sheet(isPresented: $isPresented) {
            PawSingleSelectSheet(
                title: sheetTitle,
                options: options,
                selection: selection,
                optionTitle: optionTitle,
                onSelect: { selection = $0 },
                icon: icon
            )
        }
    }
}

extension PawSingleSelectField where Icon == EmptyView {
    init(
        label: String,
        sheetTitle: String,
        options: [Option],
        selection: Binding<Option>,
        optionTitle: @escaping (Option) -> String
    ) {
        self.init(
            label: label,
            sheetTitle: sheetTitle,
            options: options,
            selection: selection,
            optionTitle: optionTitle,
            icon: { _ in EmptyView() }
        )
    }
}
