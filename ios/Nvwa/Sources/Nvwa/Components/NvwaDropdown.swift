import SwiftUI

/// Text-only dropdown trigger variants from Figma `2285:342`.
public enum NvwaTextDropdownButtonStyle: Sendable, CaseIterable, Hashable {
    case small
    case smallSemibold
    case medium
    case large
}

enum NvwaTextDropdownButtonMetrics {
    static let spacing: CGFloat = 2

    static func typography(for style: NvwaTextDropdownButtonStyle) -> NvwaTypographyToken {
        switch style {
        case .small: Nvwa.Typography.bodySmall
        case .smallSemibold: Nvwa.Typography.bodySmallSemibold
        case .medium: Nvwa.Typography.bodyMediumSemibold
        case .large: Nvwa.Typography.bodyLargeSemibold
        }
    }

    static func iconSize(for style: NvwaTextDropdownButtonStyle) -> CGFloat {
        switch style {
        case .small, .smallSemibold: 12
        case .medium, .large: 14
        }
    }
}

/// A content-hugging dropdown trigger without a background.
///
/// Nvwa does not bundle general-purpose icons. Pass Remix Icon's
/// `arrow-down-s-fill` from the host application.
public struct NvwaTextDropdownButton: View {
    private let title: String
    private let style: NvwaTextDropdownButtonStyle
    private let dropdownIcon: Image
    private let action: () -> Void

    public init(
        _ title: String,
        style: NvwaTextDropdownButtonStyle = .small,
        dropdownIcon: Image,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.dropdownIcon = dropdownIcon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: NvwaTextDropdownButtonMetrics.spacing) {
                Text(verbatim: title)
                    .nvwaTextStyle(NvwaTextDropdownButtonMetrics.typography(for: style))
                    .lineLimit(1)

                dropdownIcon
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: NvwaTextDropdownButtonMetrics.iconSize(for: style),
                        height: NvwaTextDropdownButtonMetrics.iconSize(for: style)
                    )
            }
            .foregroundStyle(Nvwa.grayPrimary)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Filled dropdown trigger variants from Figma `2285:355`.
public enum NvwaBackgroundDropdownButtonSize: Sendable, CaseIterable, Hashable {
    case large
    case small
}

enum NvwaBackgroundDropdownButtonMetrics {
    static func height(for size: NvwaBackgroundDropdownButtonSize) -> CGFloat {
        size == .large ? 40 : 24
    }

    static func horizontalPadding(for size: NvwaBackgroundDropdownButtonSize) -> CGFloat {
        size == .large ? 12 : 8
    }

    static func verticalPadding(for size: NvwaBackgroundDropdownButtonSize) -> CGFloat {
        size == .large ? 0 : 3
    }

    static func spacing(for size: NvwaBackgroundDropdownButtonSize) -> CGFloat {
        size == .large ? 8 : 0
    }

    static func cornerRadius(for size: NvwaBackgroundDropdownButtonSize) -> CGFloat {
        size == .large ? 8 : 6
    }

    static func iconSize(for size: NvwaBackgroundDropdownButtonSize) -> CGFloat {
        size == .large ? 20 : 16
    }

    /// `2285:355` still references legacy Mobile/Binance Nova text styles inside the Nvwa file.
    /// The package has no licensed Binance Nova asset, so these component-local tokens preserve
    /// the authored size, weight, line height, and tracking with Nvwa's bundled Inter family.
    static func typography(for size: NvwaBackgroundDropdownButtonSize) -> NvwaTypographyToken {
        switch size {
        case .large:
            NvwaTypographyToken(
                "Mobile/subtitle2,14 Medium",
                size: 14,
                lineHeight: 22,
                letterSpacingPercent: 0,
                weight: .medium,
                scaleRole: .body
            )
        case .small:
            NvwaTypographyToken(
                "Mobile/subtitle3,12 Medium",
                size: 12,
                lineHeight: 18,
                letterSpacingPercent: 0,
                weight: .medium,
                scaleRole: .footnote
            )
        }
    }
}

/// A compact dropdown trigger on the Nvwa `BG/Input` surface.
public struct NvwaBackgroundDropdownButton: View {
    private let title: String
    private let size: NvwaBackgroundDropdownButtonSize
    private let dropdownIcon: Image
    private let action: () -> Void

    public init(
        _ title: String,
        size: NvwaBackgroundDropdownButtonSize = .large,
        dropdownIcon: Image,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.size = size
        self.dropdownIcon = dropdownIcon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: NvwaBackgroundDropdownButtonMetrics.spacing(for: size)) {
                Text(verbatim: title)
                    .nvwaTextStyle(
                        NvwaBackgroundDropdownButtonMetrics.typography(for: size),
                        linesFillLineHeight: false
                    )
                    .lineLimit(1)

                dropdownIcon
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: NvwaBackgroundDropdownButtonMetrics.iconSize(for: size),
                        height: NvwaBackgroundDropdownButtonMetrics.iconSize(for: size)
                    )
                    .foregroundStyle(Nvwa.graySecondary)
            }
            .padding(.horizontal, NvwaBackgroundDropdownButtonMetrics.horizontalPadding(for: size))
            .padding(.vertical, NvwaBackgroundDropdownButtonMetrics.verticalPadding(for: size))
            .frame(height: NvwaBackgroundDropdownButtonMetrics.height(for: size))
            .foregroundStyle(Nvwa.grayPrimary)
            .background(
                Nvwa.backgroundInput,
                in: RoundedRectangle(
                    cornerRadius: NvwaBackgroundDropdownButtonMetrics.cornerRadius(for: size),
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum NvwaDropdownMenuMetrics {
    static let authoredWidth: CGFloat = 113
    static let cornerRadius: CGFloat = 12
    static let verticalPadding: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 8
    static let rowSpacing: CGFloat = 4
    static let checkIconSize: CGFloat = 20
    static let secondaryTextLightHex: UInt32 = 0x757575
    static let firstShadowHex: UInt32 = 0x181A20
    static let firstShadowOpacity = 0.10
    static let firstShadowRadius: CGFloat = 3
    static let firstShadowY: CGFloat = 2
    static let secondShadowHex: UInt32 = 0x474D57
    static let secondShadowOpacity = 0.08
    static let secondShadowRadius: CGFloat = 7
    static let secondShadowY: CGFloat = 8

    static func height(itemCount: Int) -> CGFloat {
        verticalPadding * 2
            + CGFloat(max(itemCount, 0))
            * (Nvwa.Typography.bodyMedium.lineHeight + rowVerticalPadding * 2)
    }
}

/// A single-selection dropdown menu from Figma `2286:449`.
///
/// The host supplies Remix Icon's `check-line`; Nvwa owns row geometry, selection colours,
/// the card surface, and the two-layer `shadow2` effect.
public struct NvwaDropdownMenu<Option: Hashable>: View {
    private let options: [Option]
    @Binding private var selection: Option
    private let width: CGFloat
    private let checkIcon: Image
    private let title: (Option) -> String
    private let onSelection: ((Option) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    public init(
        options: [Option],
        selection: Binding<Option>,
        width: CGFloat = 113,
        checkIcon: Image,
        title: @escaping (Option) -> String,
        onSelection: ((Option) -> Void)? = nil
    ) {
        self.options = options
        _selection = selection
        self.width = width
        self.checkIcon = checkIcon
        self.title = title
        self.onSelection = onSelection
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                item(option)
            }
        }
        .padding(.vertical, NvwaDropdownMenuMetrics.verticalPadding)
        .frame(width: width)
        .background(
            Nvwa.backgroundMain,
            in: RoundedRectangle(
                cornerRadius: NvwaDropdownMenuMetrics.cornerRadius,
                style: .continuous
            )
        )
        .shadow(
            color: shadowColor(
                hex: NvwaDropdownMenuMetrics.firstShadowHex,
                opacity: NvwaDropdownMenuMetrics.firstShadowOpacity
            ),
            radius: NvwaDropdownMenuMetrics.firstShadowRadius,
            y: NvwaDropdownMenuMetrics.firstShadowY
        )
        .shadow(
            color: shadowColor(
                hex: NvwaDropdownMenuMetrics.secondShadowHex,
                opacity: NvwaDropdownMenuMetrics.secondShadowOpacity
            ),
            radius: NvwaDropdownMenuMetrics.secondShadowRadius,
            y: NvwaDropdownMenuMetrics.secondShadowY
        )
    }

    private func item(_ option: Option) -> some View {
        let selected = option == selection
        return Button {
            selection = option
            onSelection?(option)
        } label: {
            HStack(spacing: NvwaDropdownMenuMetrics.rowSpacing) {
                Text(verbatim: title(option))
                    .nvwaTextStyle(Nvwa.Typography.bodyMedium)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if selected {
                    checkIcon
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: NvwaDropdownMenuMetrics.checkIconSize,
                            height: NvwaDropdownMenuMetrics.checkIconSize
                        )
                }
            }
            .foregroundStyle(selected ? Nvwa.grayPrimary : secondaryText)
            .padding(.horizontal, NvwaDropdownMenuMetrics.rowHorizontalPadding)
            .padding(.vertical, NvwaDropdownMenuMetrics.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var secondaryText: Color {
        if colorScheme == .dark {
            return Nvwa.graySecondary
        }
        return color(hex: NvwaDropdownMenuMetrics.secondaryTextLightHex)
    }

    private func color(hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    private func shadowColor(hex: UInt32, opacity: Double) -> Color {
        color(hex: hex, opacity: opacity)
    }
}
