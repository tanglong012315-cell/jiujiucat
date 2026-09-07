import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Nvwa's public design-token namespace.
public enum Nvwa {}

public extension Nvwa {
    /// Raw sRGB values from the Figma variables. Keeping these public makes
    /// token drift testable without depending on platform colour resolution.
    enum Hex {
        public static let coreBrightBlueLight: UInt32 = 0x6999FF
        public static let coreBrightBlueDark: UInt32 = 0x4782FF
        public static let primaryGreenLight: UInt32 = 0x0051FE
        public static let primaryGreenDark: UInt32 = 0x2D66F0

        // Source-compatible raw aliases from the package's first release.
        public static let primaryGreen = primaryGreenLight

        public static let grayPrimaryLight: UInt32 = 0x000000
        public static let grayPrimaryDark: UInt32 = 0xFFFFFF
        public static let graySecondary: UInt32 = 0x868685
        public static let textBlueLight: UInt32 = 0x0051FE
        public static let textBlueDark: UInt32 = 0x4782FF
        public static let colorOnBlue: UInt32 = 0xFFFFFF
        public static let textBlack: UInt32 = 0x000000

        public static let backgroundMainLight: UInt32 = 0xFFFFFF
        public static let backgroundMainDark: UInt32 = 0x000000
        public static let backgroundVesselLight: UInt32 = 0xEFEFEF
        public static let backgroundVesselDark: UInt32 = 0x212121
        public static let backgroundInputLight: UInt32 = 0xEFEFEF
        public static let backgroundInputDark: UInt32 = 0x1D1D1D
        public static let backgroundCardLight: UInt32 = 0xF6F6F6
        public static let backgroundCardDark: UInt32 = 0x212121
        public static let backgroundContainerLight: UInt32 = 0xFFFFFF
        public static let backgroundContainerDark: UInt32 = 0x373737
        public static let backgroundDialogueLight: UInt32 = 0xFFFFFF
        public static let backgroundDialogueDark: UInt32 = 0x262626
        public static let lineLight: UInt32 = 0xDEDEDD
        public static let lineDark: UInt32 = 0x2B2B2B
        public static let buttonGrayLight: UInt32 = 0xDEDEDD
        public static let buttonGrayDark: UInt32 = 0x3C3C3C

        // Source-compatible aliases for callers that adopted the package
        // before the Figma background roles were named explicitly.
        public static let backgroundLight = backgroundMainLight
        public static let backgroundDark = backgroundMainDark
        public static let backgroundNeutralLight = backgroundVesselLight
        public static let backgroundNeutralDark = backgroundVesselDark
        public static let backgroundLightLight = backgroundInputLight
        public static let backgroundLightDark = backgroundInputDark

        public static let marketBuyLight: UInt32 = 0x1D7353
        public static let marketBuyDark: UInt32 = 0x2CC094
        public static let marketSellLight: UInt32 = 0xCE2632
        public static let marketSellDark: UInt32 = 0xF0616D

        public static let sentimentWarning: UInt32 = 0xEDC843
        public static let sentimentPositive: UInt32 = 0x2F5711
        public static let sentimentNegativeLight: UInt32 = 0xA8200D
        public static let sentimentNegativeDark: UInt32 = 0xDC432D
        public static let sentimentNegative = sentimentNegativeLight

        public static let alphaGreen20LightRGBA: UInt32 = 0x4AB18B33
        public static let alphaGreen20DarkRGBA: UInt32 = 0x2CC09433
        public static let alphaRed20RGBA: UInt32 = 0xCE263233
        public static let alphaYellow20RGBA: UInt32 = 0xEDC84333
        public static let alphaBlue10LightRGBA: UInt32 = 0x0051FE1A
        public static let alphaBlue10DarkRGBA: UInt32 = 0x4782FF33

        // Source-compatible raw aliases resolve to the Light mode value.
        public static let alphaGreen20RGBA = alphaGreen20LightRGBA
        public static let alphaBlue10RGBA = alphaBlue10LightRGBA

        public static let brightOrange: UInt32 = 0xFFC091
        public static let brightYellow: UInt32 = 0xFFEB69
        public static let secondaryBrightBlue: UInt32 = 0xA0E1E1
        public static let brightBlue = secondaryBrightBlue
        public static let pink: UInt32 = 0xFFD7EF
    }

    // MARK: Figma primitives

    static let coreBrightBlue = nvwaThemed(
        light: Hex.coreBrightBlueLight,
        dark: Hex.coreBrightBlueDark
    )
    static let primaryGreen = nvwaThemed(
        light: Hex.primaryGreenLight,
        dark: Hex.primaryGreenDark
    )

    static let grayPrimary = nvwaThemed(
        light: Hex.grayPrimaryLight,
        dark: Hex.grayPrimaryDark
    )
    static let graySecondary = nvwaFixed(Hex.graySecondary)
    static let textBlue = nvwaThemed(
        light: Hex.textBlueLight,
        dark: Hex.textBlueDark
    )
    static let colorOnBlue = nvwaFixed(Hex.colorOnBlue)
    static let textBlack = nvwaFixed(Hex.textBlack)

    static let backgroundMain = nvwaThemed(
        light: Hex.backgroundMainLight,
        dark: Hex.backgroundMainDark
    )
    static let backgroundVessel = nvwaThemed(
        light: Hex.backgroundVesselLight,
        dark: Hex.backgroundVesselDark
    )
    static let backgroundInput = nvwaThemed(
        light: Hex.backgroundInputLight,
        dark: Hex.backgroundInputDark
    )
    static let backgroundCard = nvwaThemed(
        light: Hex.backgroundCardLight,
        dark: Hex.backgroundCardDark
    )
    static let backgroundContainer = nvwaThemed(
        light: Hex.backgroundContainerLight,
        dark: Hex.backgroundContainerDark
    )
    static let backgroundDialogue = nvwaThemed(
        light: Hex.backgroundDialogueLight,
        dark: Hex.backgroundDialogueDark
    )
    static let line = nvwaThemed(light: Hex.lineLight, dark: Hex.lineDark)
    static let buttonGray = nvwaThemed(
        light: Hex.buttonGrayLight,
        dark: Hex.buttonGrayDark
    )

    static let marketBuy = nvwaThemed(
        light: Hex.marketBuyLight,
        dark: Hex.marketBuyDark
    )
    static let marketSell = nvwaThemed(
        light: Hex.marketSellLight,
        dark: Hex.marketSellDark
    )

    static let sentimentWarning = nvwaFixed(Hex.sentimentWarning)
    static let sentimentPositive = nvwaFixed(Hex.sentimentPositive)
    static let sentimentNegative = nvwaThemed(
        light: Hex.sentimentNegativeLight,
        dark: Hex.sentimentNegativeDark
    )

    static let alphaGreen20 = nvwaThemedRGBA(
        light: Hex.alphaGreen20LightRGBA,
        dark: Hex.alphaGreen20DarkRGBA
    )
    static let alphaRed20 = nvwaRGBA(Hex.alphaRed20RGBA)
    static let alphaYellow20 = nvwaRGBA(Hex.alphaYellow20RGBA)
    static let alphaBlue10 = nvwaThemedRGBA(
        light: Hex.alphaBlue10LightRGBA,
        dark: Hex.alphaBlue10DarkRGBA
    )

    static let brightOrange = nvwaFixed(Hex.brightOrange)
    static let brightYellow = nvwaFixed(Hex.brightYellow)
    static let brightBlue = nvwaFixed(Hex.brightBlue)
    static let pink = nvwaFixed(Hex.pink)

    // Source-compatible aliases for the package's first public naming pass.
    static let background = backgroundMain
    static let backgroundNeutral = backgroundVessel
    static let backgroundLight = backgroundInput

    // MARK: PawFolio compatibility semantics

    static let textSecondary = graySecondary
    static let chartGrid = line
    static let catFemale = pink
    static let catMale = brightBlue

    static let bg = backgroundMain
    static let bgNeutral = backgroundVessel
    static let bgLight = backgroundInput
    static let bg1 = backgroundMain
    static let bg2 = backgroundInput
    static let surface1 = backgroundVessel

    static let ink = grayPrimary
    static let ink80 = grayPrimary.opacity(0.8)
    static let ink40 = graySecondary
    static let ink20 = backgroundVessel
    static let ink10 = line
    static let ink4 = backgroundInput

    static let tintBlue = backgroundInput
    static let tintGreen = backgroundInput
    static let tintOrange = backgroundInput
    static let onTintBlue = brightBlue
    static let onTintGreen = primaryGreen
    static let onTintOrange = brightOrange
    static let onTint = grayPrimary

    static let accent = primaryGreen
    static let gain = marketBuy
    static let loss = marketSell
    static let flat = graySecondary
    static let destructive = sentimentNegative
    static let error = sentimentNegative

    static let sessionOpen = sentimentPositive
    static let sessionPre = sentimentWarning
    static let sessionAfter = sentimentWarning
    static let sessionNight = sentimentNegative
    static let sessionClosed = sentimentNegative

    static let seriesBlue = brightBlue
    static let seriesPink = pink
    static let seriesOrange = brightOrange
    static let seriesYellow = brightYellow

    // Media colours intentionally stay absolute across themes.
    static let avatarForeground = nvwaFixed(0xFFFFFF)
    static let avatarRing = nvwaFixed(0xFFFFFF)
    static let photoPaper = nvwaFixed(0xFFFFFF)
    static let photoViewerScrim = nvwaFixed(0x000000, alpha: 0.72)
    static let photoCaption = nvwaFixed(0xFFFFFF)
    static let photoCaptionSecondary = nvwaFixed(0xFFFFFF, alpha: 0.7)
    static let photoCaptionTertiary = nvwaFixed(0xFFFFFF, alpha: 0.5)
    static let photoShadowSoft = nvwaFixed(0x000000, alpha: 0.16)
    static let photoShadowDeep = nvwaFixed(0x000000, alpha: 0.34)
    static let photoShadowViewer = nvwaFixed(0x000000, alpha: 0.4)

    static let quietBlue = tintBlue
}

private func nvwaFixed(_ hex: UInt32, alpha: Double = 1) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: alpha
    )
}

private func nvwaRGBA(_ rgba: UInt32) -> Color {
    nvwaFixed(rgba >> 8, alpha: Double(rgba & 0xFF) / 255)
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(nvwaHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    convenience init(nvwaRGBA rgba: UInt32) {
        self.init(
            red: CGFloat((rgba >> 24) & 0xFF) / 255,
            green: CGFloat((rgba >> 16) & 0xFF) / 255,
            blue: CGFloat((rgba >> 8) & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }
}

private func nvwaThemed(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        UIColor(nvwaHex: traits.userInterfaceStyle == .dark ? dark : light)
    })
}


private func nvwaThemedRGBA(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        UIColor(nvwaRGBA: traits.userInterfaceStyle == .dark ? dark : light)
    })
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(nvwaHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }


    convenience init(nvwaRGBA rgba: UInt32) {
        self.init(
            srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255,
            green: CGFloat((rgba >> 16) & 0xFF) / 255,
            blue: CGFloat((rgba >> 8) & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }
}

private func nvwaThemed(light: UInt32, dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(nvwaHex: isDark ? dark : light)
    })
}


private func nvwaThemedRGBA(light: UInt32, dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(nvwaRGBA: isDark ? dark : light)
    })
}
#endif
