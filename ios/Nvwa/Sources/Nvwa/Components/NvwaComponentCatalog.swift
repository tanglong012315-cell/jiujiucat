#if DEBUG
  import SwiftUI

  public struct NvwaComponentCatalogIcons {
    public let check: Image
    public let search: Image
    public let close: Image
    public let checkboxChecked: Image
    public let checkboxUnchecked: Image
    public let calendar: Image
    public let previous: Image
    public let next: Image
    public let hintRight: Image
    public let navigationGuest: Image
    public let navigationAdd: Image
    public let navigationBack: Image
    /// 个人中心导航的主题切换图标（`2224:71` 的 moon-fill）。
    public let navigationTheme: Image
    public let logout: Image
    public let flagUS: Image
    /// Select 的下拉三角（`arrow-drop-down-fill`）。
    public let dropdown: Image
    /// Dropdown Button 的折角箭头（`arrow-down-s-fill`）。
    public let dropdownChevron: Image
    /// 输入框的一键清除（`close-circle-fill`）。
    public let closeCircle: Image

    public init(
      check: Image,
      search: Image,
      close: Image,
      checkboxChecked: Image,
      checkboxUnchecked: Image,
      calendar: Image,
      previous: Image,
      next: Image,
      hintRight: Image,
      navigationGuest: Image,
      navigationAdd: Image,
      navigationBack: Image,
      navigationTheme: Image,
      logout: Image,
      flagUS: Image,
      dropdown: Image,
      dropdownChevron: Image,
      closeCircle: Image
    ) {
      self.check = check
      self.search = search
      self.close = close
      self.checkboxChecked = checkboxChecked
      self.checkboxUnchecked = checkboxUnchecked
      self.calendar = calendar
      self.previous = previous
      self.next = next
      self.hintRight = hintRight
      self.navigationGuest = navigationGuest
      self.navigationAdd = navigationAdd
      self.navigationBack = navigationBack
      self.navigationTheme = navigationTheme
      self.logout = logout
      self.flagUS = flagUS
      self.dropdown = dropdown
      self.dropdownChevron = dropdownChevron
      self.closeCircle = closeCircle
    }
  }

  public struct NvwaComponentCatalog: View {
    private let icons: NvwaComponentCatalogIcons
    private let initialSection: String?
    @State private var toggle = true
    @State private var checkedCheckbox = true
    @State private var uncheckedCheckbox = false
    @State private var segment = CatalogSegment.first
    @State private var section = CatalogSection.overview
    @State private var currencySelected = true
    @State private var dropdownSelection = CatalogDropdownOption.btc
    @State private var slider = 0.5
    @State private var input = "Nvwa"
    @State private var errorInput = "Invalid value"
    @State private var searchInput = "PawFolio"
    @State private var date = Date()

    public init(icons: NvwaComponentCatalogIcons, initialSection: String? = nil) {
      self.icons = icons
      self.initialSection = initialSection
    }

    public var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 28) {
            Text("Nvwa")
              .font(Nvwa.font(30, weight: .semibold))
              .foregroundStyle(Nvwa.grayPrimary)

            catalogSection("Navigation") {
              VStack(spacing: 12) {
                // 添加持仓 `2102:1169`
                NvwaNavigationBar(
                  leading: .avatar(
                    initials: "NV",
                    accessibilityLabel: "Open profile",
                    action: {}
                  ),
                  trailing: [
                    .icon(
                      icons.navigationAdd,
                      tone: .primary,
                      accessibilityLabel: "Add item",
                      action: {}
                    )
                  ]
                )

                // 未登录态是代码扩展：Figma 只画了头像那一档。
                NvwaNavigationBar(
                  leading: .icon(
                    icons.navigationGuest,
                    accessibilityLabel: "Log in",
                    action: {}
                  ),
                  trailing: [
                    .icon(
                      icons.navigationAdd,
                      tone: .primary,
                      accessibilityLabel: "Add item",
                      action: {}
                    )
                  ]
                )

                // 二级导航 / Icon=Left `2102:1102`
                NvwaNavigationBar(
                  leading: .icon(
                    icons.navigationBack,
                    accessibilityLabel: "Back",
                    action: {}
                  ),
                  title: "Title"
                )

                // 二级导航 / Icon=Right `2238:574`
                NvwaNavigationBar(
                  title: "Title",
                  trailing: [
                    .icon(icons.close, accessibilityLabel: "Close", action: {})
                  ]
                )

                // 二级导航 / Icon=L+R `2238:582`
                NvwaNavigationBar(
                  leading: .icon(
                    icons.navigationBack,
                    accessibilityLabel: "Back",
                    action: {}
                  ),
                  title: "Title",
                  trailing: [
                    .icon(icons.close, accessibilityLabel: "Close", action: {})
                  ]
                )

                // 个人中心 `2224:66`：尾随两枚图标时自动降到 20pt。
                NvwaNavigationBar(
                  leading: .icon(
                    icons.close,
                    accessibilityLabel: "Close",
                    action: {}
                  ),
                  trailing: [
                    .icon(
                      icons.navigationTheme,
                      accessibilityLabel: "Toggle appearance",
                      action: {}
                    ),
                    .artwork(
                      icons.flagUS,
                      accessibilityLabel: "Change language",
                      action: {}
                    )
                  ]
                )
              }
              .frame(width: 375)
            }

            catalogSection("Colors") {
              LazyVGrid(columns: [GridItem(.adaptive(minimum: 68))], spacing: 12) {
                colorChip("Core bright blue", Nvwa.coreBrightBlue)
                colorChip("Primary green", Nvwa.primaryGreen)
                colorChip("Text primary", Nvwa.grayPrimary)
                colorChip("Text secondary", Nvwa.graySecondary)
                colorChip("Text blue", Nvwa.textBlue)
                colorChip("Color on blue", Nvwa.colorOnBlue)
                colorChip("Text black", Nvwa.textBlack)
                colorChip("BG main", Nvwa.backgroundMain)
                colorChip("BG container", Nvwa.backgroundContainer)
                colorChip("BG dialogue", Nvwa.backgroundDialogue)
                colorChip("BG vessel", Nvwa.backgroundVessel)
                colorChip("BG input", Nvwa.backgroundInput)
                colorChip("BG card", Nvwa.backgroundCard)
                colorChip("Button gray", Nvwa.buttonGray)
                colorChip("Line", Nvwa.line)
                colorChip("Buy", Nvwa.marketBuy)
                colorChip("Sell", Nvwa.marketSell)
                colorChip("Warning", Nvwa.sentimentWarning)
                colorChip("Positive", Nvwa.sentimentPositive)
                colorChip("Negative", Nvwa.sentimentNegative)
                colorChip("Orange", Nvwa.brightOrange)
                colorChip("Yellow", Nvwa.brightYellow)
                colorChip("Blue", Nvwa.brightBlue)
                colorChip("Pink", Nvwa.pink)
                colorChip("Alpha blue 10", Nvwa.alphaBlue10)
                colorChip("Alpha green 20", Nvwa.alphaGreen20)
                colorChip("Alpha red 20", Nvwa.alphaRed20)
                colorChip("Alpha yellow 20", Nvwa.alphaYellow20)
              }
            }

            catalogSection("Buttons") {
              VStack(alignment: .leading, spacing: 12) {
                NvwaButton("Primary huge", size: .huge) {}
                NvwaButton("Primary large") {}
                NvwaButton("Secondary", kind: .secondary, size: .small) {}
                NvwaButton("Outline", kind: .outline, size: .small) {}
                NvwaButton("Warning", kind: .warning, size: .tiny) {}
                NvwaButton("Outline warning", kind: .outlineWarning, size: .small) {}
                NvwaButton("Outline leading", kind: .outline, leadingIcon: icons.check) {}
                NvwaButton("Disabled") {}
                  .disabled(true)
              }
            }

            catalogSection("Controls") {
              VStack(alignment: .leading, spacing: 16) {
                NvwaToggle(isOn: $toggle, accessibilityLabel: "Example toggle")
                NvwaAvatar(initials: "JS", flag: icons.flagUS)
                HStack {
                  NvwaTag("Tag")
                  NvwaTag(
                    "Verified",
                    tone: .green,
                    icon: icons.check,
                    iconPlacement: .leading
                  )
                  NvwaTag("Tag", tone: .red)
                  NvwaTag("Tag", tone: .blue)
                }
                NvwaSegmentControl(
                  options: CatalogSegment.allCases,
                  selection: $segment,
                  title: \.title
                )
                NvwaSegmentControl(
                  options: CatalogSegment.allCases,
                  selection: $segment,
                  size: .small,
                  title: \.title
                )
                HStack(spacing: 20) {
                  NvwaCheckbox(
                    "Checked",
                    isChecked: $checkedCheckbox,
                    checkedIcon: icons.checkboxChecked,
                    uncheckedIcon: icons.checkboxUnchecked
                  )
                  NvwaCheckbox(
                    "Unchecked",
                    isChecked: $uncheckedCheckbox,
                    checkedIcon: icons.checkboxChecked,
                    uncheckedIcon: icons.checkboxUnchecked
                  )
                }
                // Section 一族四档（`2070:825`）：Primary / Sec / Currency / Text。
                VStack(alignment: .leading, spacing: 12) {
                  HStack(spacing: 8) {
                    ForEach(CatalogSection.allCases, id: \.self) { option in
                      NvwaSection(option.title, isSelected: section == option) {
                        section = option
                      }
                    }
                  }

                  HStack(spacing: 8) {
                    ForEach(CatalogSection.allCases, id: \.self) { option in
                      NvwaSection(
                        option.title,
                        style: .secondary,
                        isSelected: section == option
                      ) {
                        section = option
                      }
                    }
                  }

                  // 目录里只带了一面国旗，所以 Currency 用一枚可点的 chip
                  // 同时演示选中和未选中，而不是并排两个不同币种。
                  NvwaSection(
                    "USD",
                    style: .currency,
                    isSelected: currencySelected,
                    icon: { icons.flagUS },
                    action: { currencySelected.toggle() }
                  )

                  HStack(spacing: 16) {
                    ForEach(CatalogSection.allCases, id: \.self) { option in
                      NvwaSection(
                        option.title,
                        style: .text,
                        isSelected: section == option,
                        // `.text` 的图标跟着文字色走，所以宿主要传模板图。
                        icon: {
                          icons.search
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                        },
                        action: { section = option }
                      )
                    }
                  }
                }

                // `2070:825` 在四档 Section 后新增的三组 Dropdown 组件。
                VStack(alignment: .leading, spacing: 12) {
                  HStack(spacing: 24) {
                    NvwaTextDropdownButton(
                      "BTC",
                      dropdownIcon: icons.dropdownChevron,
                      action: {}
                    )
                    NvwaTextDropdownButton(
                      "BTC",
                      style: .smallSemibold,
                      dropdownIcon: icons.dropdownChevron,
                      action: {}
                    )
                    NvwaTextDropdownButton(
                      "BTC",
                      style: .medium,
                      dropdownIcon: icons.dropdownChevron,
                      action: {}
                    )
                    NvwaTextDropdownButton(
                      "BTC",
                      style: .large,
                      dropdownIcon: icons.dropdownChevron,
                      action: {}
                    )
                  }

                  HStack(spacing: 24) {
                    NvwaBackgroundDropdownButton(
                      "10%",
                      dropdownIcon: icons.dropdownChevron,
                      action: {}
                    )
                    NvwaBackgroundDropdownButton(
                      "Symbol",
                      size: .small,
                      dropdownIcon: icons.dropdownChevron,
                      action: {}
                    )
                  }

                  NvwaDropdownMenu(
                    options: CatalogDropdownOption.allCases,
                    selection: $dropdownSelection,
                    checkIcon: icons.check,
                    title: \.title
                  )
                }
                NvwaSlider(value: $slider)
                  .frame(width: 218)
              }
            }

            catalogSection("Key feature icons") {
              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 56), spacing: 16)],
                alignment: .leading,
                spacing: 16
              ) {
                ForEach(NvwaKeyFeatureIconKind.allCases, id: \.self) { kind in
                  NvwaKeyFeatureIcon(kind)
                    .accessibilityLabel(keyFeatureAccessibilityLabel(kind))
                }
              }
            }

            catalogSection("Scroll button") {
              VStack(alignment: .leading, spacing: 16) {
                NvwaScrollButton("Scroll to Confirm") {}
                // Finish 态：宿主把 isLoading 打开，滑块停在右端转菊花。
                NvwaScrollButton("Scroll to Confirm", isLoading: true) {}
                NvwaScrollButton("Disabled") {}
                  .disabled(true)
              }
              .frame(width: NvwaScrollButtonMetrics.authoredWidth)
            }

            catalogSection("Messages") {
              VStack(alignment: .leading, spacing: 8) {
                NvwaHint("Neutral hint")
                NvwaHint("Positive hint", level: .positive)
                NvwaHint("Warning hint", level: .warning)
                NvwaHint("Negative hint", level: .negative)
                NvwaHint(
                  "Hint with a trailing action indicator",
                  rightIcon: icons.hintRight,
                  rightIconAccessibilityLabel: "More"
                )
                .frame(width: 190)
                NvwaToast("Saved successfully")
                NvwaToast(
                  "Your changes couldn't be uploaded. Check your connection and try again."
                )
              }
            }

            catalogSection("Inputs") {
              VStack(spacing: 16) {
                NvwaInputField(
                  label: "Label",
                  placeholder: "Placeholder",
                  text: $input,
                  helpText: "Help text"
                )
                NvwaInputField(
                  label: "Unit",
                  placeholder: "0",
                  text: $errorInput,
                  unit: "USD",
                  helpText: "Help text",
                  clearIcon: icons.closeCircle
                )
                NvwaInputField(
                  label: "Dropdown unit",
                  placeholder: "0",
                  text: $input,
                  unit: "USD",
                  dropdownIcon: icons.dropdown,
                  onUnitTap: {}
                )
                NvwaSearchInput(
                  label: "Search",
                  placeholder: "Search",
                  text: $searchInput,
                  searchIcon: icons.search,
                  clearIcon: icons.closeCircle,
                  onClear: { searchInput = "" }
                )
                NvwaDateInput(
                  label: "Date",
                  value: date.formatted(date: .abbreviated, time: .omitted),
                  calendarIcon: icons.calendar
                ) {}
                NvwaSelect(
                  label: "Select",
                  value: "",
                  placeholder: "Select",
                  searchIcon: icons.search,
                  dropdownIcon: icons.dropdown
                ) {}
                NvwaSelect(
                  label: "Assets",
                  value: "BTC",
                  secondaryText: "Bitcoin",
                  searchIcon: icons.search,
                  dropdownIcon: icons.dropdown
                ) {}
                NvwaSelect(
                  label: "Currency",
                  value: "USD",
                  helpText: "United States dollar",
                  dropdownIcon: icons.dropdown
                ) {}
              }
              .frame(width: 318)
            }

            catalogSection("Modal header") {
              VStack(spacing: 8) {
                NvwaModalHeader("Details")
                NvwaModalHeader(
                  "Details",
                  trailing: NvwaModalHeaderAction(
                    icon: icons.hintRight,
                    accessibilityLabel: "More",
                    action: {}
                  )
                )
                NvwaModalHeader(
                  "Details",
                  leading: NvwaModalHeaderAction(
                    icon: icons.logout,
                    accessibilityLabel: "Log out",
                    tone: .destructive,
                    action: {}
                  )
                )
              }
              .frame(width: 373)
            }

            catalogSection("Tooltip") {
              NvwaTooltip(
                title: "Tooltip title",
                message: "Use this space for concise supporting information.",
                actionTitle: "Learn more"
              ) {}
            }

            catalogSection("Calendar") {
              NvwaCalendar(
                selection: $date,
                previousIcon: icons.previous,
                nextIcon: icons.next
              )
            }
          }
          .padding(24)
        }
        .background(Nvwa.backgroundMain)
        .onAppear {
          guard let initialSection else { return }
          DispatchQueue.main.async {
            proxy.scrollTo(initialSection, anchor: .top)
          }
        }
      }
    }

    private func catalogSection<Content: View>(
      _ title: String,
      @ViewBuilder content: () -> Content
    ) -> some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(Nvwa.titleBody)
          .foregroundStyle(Nvwa.grayPrimary)
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .id(title)
    }

    private func colorChip(_ title: String, _ color: Color) -> some View {
      VStack(spacing: 6) {
        Circle()
          .fill(color)
          .frame(width: 40, height: 40)
          .overlay(Circle().strokeBorder(Nvwa.line, lineWidth: 1))
        Text(title)
          .font(Nvwa.caption2)
          .foregroundStyle(Nvwa.graySecondary)
      }
    }

    private func keyFeatureAccessibilityLabel(_ kind: NvwaKeyFeatureIconKind) -> String {
      switch kind {
      case .invest: "Invest"
      case .keep: "Keep"
      case .convert: "Convert"
      case .send: "Send"
      case .receive: "Receive"
      case .add: "Add"
      case .close: "Close"
      case .tick: "Tick"
      case .warning: "Warning"
      }
    }
  }

  private enum CatalogSegment: String, CaseIterable {
    case first
    case second
    case third

    var title: String { rawValue.capitalized }
  }

  private enum CatalogSection: String, CaseIterable {
    case overview
    case activity

    var title: String { rawValue.capitalized }
  }

  private enum CatalogDropdownOption: String, CaseIterable {
    case eth
    case btc
    case bnb
    case usdt

    var title: String { rawValue.uppercased() }
  }
#endif
