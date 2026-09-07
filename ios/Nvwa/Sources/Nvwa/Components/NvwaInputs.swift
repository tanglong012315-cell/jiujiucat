import SwiftUI

/// Figma `2052:7150`（Input Fields）2026-09-06 改版后的几何。
///
/// 这一版把组件收到了最小单元：Text Input、Search Input、Date Input、Select 四个，
/// 每个只留稿子上真的画出来的状态。**去掉的**是 Error 态、`Size=Small` 和旧的
/// Flag 变体——前两个稿子上已经没有，Flag 整个改成了 Select。
enum NvwaInputMetrics {
    static let fieldHeight = Nvwa.inputHeight
    static let supportingLineHeight: CGFloat = 20
    static let verticalSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 10
    static let iconSize: CGFloat = 20
    /// 输入值与右侧单位组之间（`2014:7306` gap 32）。
    static let valueSpacing: CGFloat = 32
    /// 单位组内部，一键清除与单位之间（`2276:634` gap 10）。
    static let unitSpacing: CGFloat = 10
    /// 可下拉的单位与三角之间（`2276:639` gap 2）。
    static let dropdownSpacing: CGFloat = 2
    /// Search / Select 里图标与文字之间（`2052:7632` / `2276:616` gap 4）。
    static let contentSpacing: CGFloat = 4
    static let valueTypography = Nvwa.Typography.titleGroup
    /// 可下拉的单位是 B-M Regular（`2276:640`），比不可下拉那档轻一号——
    /// 它是个能被改的取值，不是固定后缀。
    static let dropdownUnitTypography = Nvwa.Typography.bodyMedium
    /// Select 的 `Status=Aseets` 第二行（`2277:918`）。
    static let secondaryTypography = Nvwa.Typography.caption2
    static let supportingTypography = Nvwa.Typography.bodySmall
}

public extension View {
    /// Figma `2052:7150` 里输入值与占位符的排版：T-G Medium（14/20，字距 1.5%）。
    /// 产品里手搓的输入格也走这个 modifier，免得和组件悄悄跑偏。
    @ViewBuilder
    func nvwaInputTextStyle(monospacedDigits: Bool = false) -> some View {
        if monospacedDigits {
            nvwaTextStyle(
                NvwaInputMetrics.valueTypography,
                linesFillLineHeight: false
            )
            .monospacedDigit()
        } else {
            nvwaTextStyle(
                NvwaInputMetrics.valueTypography,
                linesFillLineHeight: false
            )
        }
    }
}

private struct NvwaInputClearIconKey: EnvironmentKey {
    static let defaultValue: Image? = nil
}

public extension EnvironmentValues {
    /// 一键清除用的图标。Nvwa 不自带图标集（`AGENTS.md`），但 Active 态在稿子上
    /// 不是可选项——每个输入框有字就该有它。所以宿主在根上注入一次，组件自己取，
    /// 免得每个调用点都抄一遍同一个图标名。
    var nvwaInputClearIcon: Image? {
        get { self[NvwaInputClearIconKey.self] }
        set { self[NvwaInputClearIconKey.self] = newValue }
    }
}

public extension View {
    /// 见 `EnvironmentValues.nvwaInputClearIcon`。
    func nvwaInputClearIcon(_ image: Image?) -> some View {
        environment(\.nvwaInputClearIcon, image)
    }
}

/// 四个输入组件共用的外壳：`bg/input` 底、10 圆角、48 高、左右 16。
private struct NvwaInputShell<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, NvwaInputMetrics.horizontalPadding)
            .frame(height: NvwaInputMetrics.fieldHeight)
            .background(
                Nvwa.backgroundInput,
                in: RoundedRectangle(cornerRadius: NvwaInputMetrics.cornerRadius, style: .continuous)
            )
    }
}

/// 20pt 的模板图标。图标由宿主注入，Nvwa 不自带图标集（`AGENTS.md`）。
private struct NvwaInputIcon: View {
    let image: Image

    var body: some View {
        image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: NvwaInputMetrics.iconSize, height: NvwaInputMetrics.iconSize)
    }
}

/// Figma `2014:7294` Text Input Field。
///
/// 状态轴只有 Default / Active：**Active 不改配色，只是多出一枚一键清除**
/// （`2276:630` 的批注写着「一键清除数字」），所以这里不需要状态入参——
/// 传了 `clearIcon` 且框里有字，就画它。
///
/// 另外两根轴是 `Unit`（右侧固定单位）和 `Dropdown`（单位可点开换）。
public struct NvwaInputField: View {
    private let label: String?
    private let isRequired: Bool
    private let placeholder: String
    @Binding private var text: String
    private let unit: String?
    private let helpText: String?
    /// 金额一律等宽数字（`AGENTS.md`）。这不是稿子上的一根变体轴，只是排版细节，
    /// 所以做成开关而不是新变体。
    private let monospacedDigits: Bool
    private let clearIcon: Image?
    private let dropdownIcon: Image?
    private let onUnitTap: (() -> Void)?
    @Environment(\.nvwaInputClearIcon) private var environmentClearIcon

    public init(
        label: String? = nil,
        isRequired: Bool = false,
        placeholder: String,
        text: Binding<String>,
        unit: String? = nil,
        helpText: String? = nil,
        monospacedDigits: Bool = false,
        clearIcon: Image? = nil,
        dropdownIcon: Image? = nil,
        onUnitTap: (() -> Void)? = nil
    ) {
        self.label = label
        self.isRequired = isRequired
        self.placeholder = placeholder
        _text = text
        self.unit = unit
        self.helpText = helpText
        self.monospacedDigits = monospacedDigits
        self.clearIcon = clearIcon
        self.dropdownIcon = dropdownIcon
        self.onUnitTap = onUnitTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NvwaInputMetrics.verticalSpacing) {
            if let label {
                NvwaInputLabel(label, isRequired: isRequired)
            }

            NvwaInputShell {
                HStack(spacing: NvwaInputMetrics.valueSpacing) {
                    TextField("", text: $text, prompt: Text(LocalizedStringKey(placeholder)))
                        .nvwaInputTextStyle(monospacedDigits: monospacedDigits)
                        .foregroundStyle(Nvwa.grayPrimary)

                    trailing
                }
            }

            NvwaInputHint(helpText)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let unit, let dropdownIcon, let onUnitTap {
            Button(action: onUnitTap) {
                HStack(spacing: NvwaInputMetrics.dropdownSpacing) {
                    Text(unit)
                        .nvwaTextStyle(
                            NvwaInputMetrics.dropdownUnitTypography,
                            linesFillLineHeight: false
                        )
                    NvwaInputIcon(image: dropdownIcon)
                }
                .foregroundStyle(Nvwa.grayPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if unit != nil || showsClearButton {
            HStack(spacing: NvwaInputMetrics.unitSpacing) {
                if showsClearButton, let icon = resolvedClearIcon {
                    NvwaInputClearButton(icon: icon) { text = "" }
                }
                if let unit {
                    Text(unit)
                        .nvwaInputTextStyle()
                        .foregroundStyle(Nvwa.grayPrimary)
                }
            }
        }
    }

    private var resolvedClearIcon: Image? { clearIcon ?? environmentClearIcon }

    private var showsClearButton: Bool {
        resolvedClearIcon != nil && !text.isEmpty
    }
}

/// Figma `2052:7628` Search Input：搜索图标 + 输入 + 一键清除。
///
/// 稿子上只有 Default / Active 两态。旧实现的 `unit` 和 `secondaryText` 这一版
/// **去掉了**——带单位的格子在稿子上是 Text Input Field 的 `Unit=Yes`，
/// 带副标题的是 Select 的 `Status=Aseets`，都不该由搜索框兼任。
public struct NvwaSearchInput: View {
    private let label: String?
    private let isRequired: Bool
    private let placeholder: String
    @Binding private var text: String
    private let helpText: String?
    private let searchIcon: Image?
    private let clearIcon: Image?
    private let onClear: (() -> Void)?
    /// 宿主要在弹层打开时自动聚焦，而 `.focused` 只能挂在真正的 `TextField` 上，
    /// 从外面套在组件上不生效，所以焦点绑定得由组件自己转交。
    private let focus: FocusState<Bool>.Binding?
    @Environment(\.nvwaInputClearIcon) private var environmentClearIcon

    public init(
        label: String? = nil,
        isRequired: Bool = false,
        placeholder: String,
        text: Binding<String>,
        helpText: String? = nil,
        searchIcon: Image? = nil,
        clearIcon: Image? = nil,
        focus: FocusState<Bool>.Binding? = nil,
        onClear: (() -> Void)? = nil
    ) {
        self.label = label
        self.isRequired = isRequired
        self.placeholder = placeholder
        _text = text
        self.helpText = helpText
        self.searchIcon = searchIcon
        self.clearIcon = clearIcon
        self.focus = focus
        self.onClear = onClear
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NvwaInputMetrics.verticalSpacing) {
            if let label {
                NvwaInputLabel(label, isRequired: isRequired)
            }

            NvwaInputShell {
                // 图标是 Text Secondary，只有文字是 Primary，所以不能整块
                // `foregroundStyle`（`2052:7632`）。
                HStack(spacing: NvwaInputMetrics.contentSpacing) {
                    if let searchIcon {
                        NvwaInputIcon(image: searchIcon)
                            .foregroundStyle(Nvwa.graySecondary)
                    }

                    searchField
                        .foregroundStyle(Nvwa.grayPrimary)

                    if !text.isEmpty, let icon = clearIcon ?? environmentClearIcon {
                        NvwaInputClearButton(icon: icon) {
                            if let onClear { onClear() } else { text = "" }
                        }
                    }
                }
            }

            NvwaInputHint(helpText)
        }
    }

    @ViewBuilder
    private var searchField: some View {
        let field = TextField("", text: $text, prompt: Text(LocalizedStringKey(placeholder)))
            .nvwaInputTextStyle()

        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }
}

/// Figma `2058:307` Date Input：不可编辑的日期 + 日历图标，点开走宿主的日历。
public struct NvwaDateInput: View {
    private let label: String?
    private let isRequired: Bool
    private let value: String
    private let helpText: String?
    private let calendarIcon: Image
    private let action: () -> Void

    public init(
        label: String? = nil,
        isRequired: Bool = false,
        value: String,
        helpText: String? = nil,
        calendarIcon: Image,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isRequired = isRequired
        self.value = value
        self.helpText = helpText
        self.calendarIcon = calendarIcon
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NvwaInputMetrics.verticalSpacing) {
            if let label {
                NvwaInputLabel(label, isRequired: isRequired)
            }

            Button(action: action) {
                NvwaInputShell {
                    HStack(spacing: NvwaInputMetrics.contentSpacing) {
                        Text(value)
                            .nvwaInputTextStyle()
                            .foregroundStyle(Nvwa.grayPrimary)
                        Spacer(minLength: 0)
                        NvwaInputIcon(image: calendarIcon)
                            .foregroundStyle(Nvwa.graySecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NvwaInputHint(helpText)
        }
    }
}

/// Figma `2074:894` Select（这一版把旧的 Flag 换成了它）。
///
/// 三种形态由入参组合出来，不再各画一个变体：
/// - `Search=Yes`：左边带搜索图标，点开跳搜索页（`2276:616` 的批注）。
/// - `Status=Aseets`：选中之后变成两行，代码在上、全名在下（`2277:916`）。
/// - `Search=No`：只有取值和三角，就是普通的单选（`2277:901`）。
public struct NvwaSelect: View {
    private let label: String?
    private let isRequired: Bool
    private let value: String
    private let placeholder: String
    private let secondaryText: String?
    private let helpText: String?
    private let searchIcon: Image?
    private let dropdownIcon: Image
    private let action: () -> Void

    public init(
        label: String? = nil,
        isRequired: Bool = false,
        value: String,
        placeholder: String = "",
        secondaryText: String? = nil,
        helpText: String? = nil,
        searchIcon: Image? = nil,
        dropdownIcon: Image,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isRequired = isRequired
        self.value = value
        self.placeholder = placeholder
        self.secondaryText = secondaryText
        self.helpText = helpText
        self.searchIcon = searchIcon
        self.dropdownIcon = dropdownIcon
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NvwaInputMetrics.verticalSpacing) {
            if let label {
                NvwaInputLabel(label, isRequired: isRequired)
            }

            Button(action: action) {
                NvwaInputShell {
                    HStack(spacing: NvwaInputMetrics.contentSpacing) {
                        if let searchIcon {
                            NvwaInputIcon(image: searchIcon)
                                .foregroundStyle(Nvwa.graySecondary)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(isEmpty ? LocalizedStringKey(placeholder) : LocalizedStringKey(value))
                                .nvwaInputTextStyle()
                                .foregroundStyle(isEmpty ? Nvwa.graySecondary : Nvwa.grayPrimary)
                                .lineLimit(1)

                            if let secondaryText, !isEmpty {
                                Text(secondaryText)
                                    .nvwaTextStyle(
                                        NvwaInputMetrics.secondaryTypography,
                                        linesFillLineHeight: false
                                    )
                                    .foregroundStyle(Nvwa.graySecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        NvwaInputIcon(image: dropdownIcon)
                            .foregroundStyle(Nvwa.graySecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NvwaInputHint(helpText)
        }
    }

    private var isEmpty: Bool {
        value.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// 一键清除（`close-circle-fill`）。图标 20 太小点不准，撑出 44 的热区但不占版面。
private struct NvwaInputClearButton: View {
    let icon: Image
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NvwaInputIcon(image: icon)
                .foregroundStyle(Nvwa.graySecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: NvwaInputMetrics.iconSize, height: NvwaInputMetrics.iconSize)
        .accessibilityLabel("Clear")
    }
}

/// Hint Text（`2014:7309`）。没内容就整行不画，不占位。
private struct NvwaInputHint: View {
    let text: String?

    init(_ text: String?) {
        self.text = text
    }

    var body: some View {
        if let text {
            Text(LocalizedStringKey(text))
                .nvwaTextStyle(NvwaInputMetrics.supportingTypography, linesFillLineHeight: false)
                .foregroundStyle(Nvwa.graySecondary)
                .frame(minHeight: NvwaInputMetrics.supportingLineHeight)
        }
    }
}

private struct NvwaInputLabel: View {
    let title: String
    let isRequired: Bool

    init(_ title: String, isRequired: Bool = false) {
        self.title = title
        self.isRequired = isRequired
    }

    var body: some View {
        // 拼接 `Text` 的 `foregroundStyle` 要 iOS 17/macOS 14，包还支持更低的
        // macOS，所以用 HStack 拼两段，视觉一致。
        HStack(spacing: 0) {
            if isRequired {
                Text("*").foregroundColor(Nvwa.sentimentNegative)
            }
            Text(LocalizedStringKey(title)).foregroundColor(Nvwa.graySecondary)
        }
        .nvwaTextStyle(NvwaInputMetrics.supportingTypography, linesFillLineHeight: false)
        .frame(minHeight: NvwaInputMetrics.supportingLineHeight)
        .accessibilityElement()
        .accessibilityLabel(Text(LocalizedStringKey(title)))
    }
}
