import SwiftUI
import XCTest

@testable import Nvwa

final class NvwaComponentSpecTests: XCTestCase {
    func testFigmaSegmentMatrixAndGeometry() {
        XCTAssertEqual(NvwaSegmentMetrics.selectionAnimationDuration, 0.06)
        XCTAssertEqual(NvwaSegmentMetrics.height(for: .normal), 40)
        XCTAssertEqual(NvwaSegmentMetrics.itemHeight(for: .normal), 36)
        XCTAssertEqual(NvwaSegmentMetrics.fixedWidth(for: .normal), 345)
        XCTAssertEqual(NvwaSegmentMetrics.height(for: .small), 28)
        XCTAssertEqual(NvwaSegmentMetrics.itemHeight(for: .small), 24)
        XCTAssertNil(NvwaSegmentMetrics.fixedWidth(for: .small))
        XCTAssertEqual(NvwaSegmentMetrics.smallAuthoredExampleWidth, 89)

        XCTAssertTrue(NvwaSegmentMetrics.isFigmaAuthored(size: .normal, optionCount: 2))
        XCTAssertTrue(NvwaSegmentMetrics.isFigmaAuthored(size: .normal, optionCount: 4))
        XCTAssertTrue(NvwaSegmentMetrics.isFigmaAuthored(size: .small, optionCount: 3))
        XCTAssertFalse(NvwaSegmentMetrics.isFigmaAuthored(size: .small, optionCount: 2))
    }

    func testSectionSelectionFeedbackIsImmediate() {
        XCTAssertEqual(NvwaSectionMetrics.height, 28)
        XCTAssertNil(NvwaSectionMetrics.selectionAnimation)
    }

    /// `2070:825` 的四个组件集，几何各不相同——一起钉住，免得哪一档被顺手对齐掉。
    func testFigmaSectionStyleGeometry() {
        XCTAssertEqual(NvwaSectionMetrics.height(for: .primary), 28)
        XCTAssertEqual(NvwaSectionMetrics.height(for: .secondary), 28)
        XCTAssertEqual(NvwaSectionMetrics.height(for: .currency), 36)
        // Text Section 没有容器高度，靠 `B-S Regular` 的 20pt 行盒撑开。
        XCTAssertNil(NvwaSectionMetrics.height(for: .text))

        XCTAssertEqual(NvwaSectionMetrics.horizontalPadding(for: .primary), 16)
        XCTAssertEqual(NvwaSectionMetrics.horizontalPadding(for: .secondary), 16)
        XCTAssertEqual(NvwaSectionMetrics.horizontalPadding(for: .currency), 10)
        XCTAssertEqual(NvwaSectionMetrics.horizontalPadding(for: .text), 0)

        XCTAssertEqual(NvwaSectionMetrics.verticalPadding(for: .primary), 3)
        XCTAssertEqual(NvwaSectionMetrics.verticalPadding(for: .currency), 0)

        XCTAssertEqual(NvwaSectionMetrics.iconSize(for: .currency), 20)
        XCTAssertEqual(NvwaSectionMetrics.iconSpacing(for: .currency), 5)
        XCTAssertEqual(NvwaSectionMetrics.iconSize(for: .text), 16)
        XCTAssertEqual(NvwaSectionMetrics.iconSpacing(for: .text), 4)

        // Text 那档是 Regular，其余三档是 Semi Bold，字号行高都是 12/20。
        XCTAssertEqual(NvwaSectionMetrics.typography(for: .text), Nvwa.Typography.bodySmall)
        for style in [NvwaSectionStyle.primary, .secondary, .currency] {
            XCTAssertEqual(
                NvwaSectionMetrics.typography(for: style),
                Nvwa.Typography.bodySmallSemibold
            )
        }
    }

    /// `2285:342`：四档文字按钮共用 2pt 间距，12pt 两档配 12pt 图标，
    /// 14/16pt 两档配 14pt 图标。
    func testTextDropdownButtonVariantsMatchFigma() {
        XCTAssertEqual(NvwaTextDropdownButtonMetrics.spacing, 2)
        XCTAssertEqual(
            NvwaTextDropdownButtonMetrics.typography(for: .small),
            Nvwa.Typography.bodySmall
        )
        XCTAssertEqual(
            NvwaTextDropdownButtonMetrics.typography(for: .smallSemibold),
            Nvwa.Typography.bodySmallSemibold
        )
        XCTAssertEqual(
            NvwaTextDropdownButtonMetrics.typography(for: .medium),
            Nvwa.Typography.bodyMediumSemibold
        )
        XCTAssertEqual(
            NvwaTextDropdownButtonMetrics.typography(for: .large),
            Nvwa.Typography.bodyLargeSemibold
        )
        XCTAssertEqual(NvwaTextDropdownButtonMetrics.iconSize(for: .small), 12)
        XCTAssertEqual(NvwaTextDropdownButtonMetrics.iconSize(for: .smallSemibold), 12)
        XCTAssertEqual(NvwaTextDropdownButtonMetrics.iconSize(for: .medium), 14)
        XCTAssertEqual(NvwaTextDropdownButtonMetrics.iconSize(for: .large), 14)
    }

    /// `2285:355`：40pt 与 24pt 两档不是等比缩放，各自保留自己的内距、圆角和排版。
    func testBackgroundDropdownButtonVariantsMatchFigma() {
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.height(for: .large), 40)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.height(for: .small), 24)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.horizontalPadding(for: .large), 12)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.horizontalPadding(for: .small), 8)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.verticalPadding(for: .small), 3)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.spacing(for: .large), 8)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.spacing(for: .small), 0)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.cornerRadius(for: .large), 8)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.cornerRadius(for: .small), 6)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.iconSize(for: .large), 20)
        XCTAssertEqual(NvwaBackgroundDropdownButtonMetrics.iconSize(for: .small), 16)

        let large = NvwaBackgroundDropdownButtonMetrics.typography(for: .large)
        XCTAssertEqual(large.size, 14)
        XCTAssertEqual(large.lineHeight, 22)
        XCTAssertEqual(large.weight, .medium)
        XCTAssertEqual(large.tracking, 0)

        let small = NvwaBackgroundDropdownButtonMetrics.typography(for: .small)
        XCTAssertEqual(small.size, 12)
        XCTAssertEqual(small.lineHeight, 18)
        XCTAssertEqual(small.weight, .medium)
        XCTAssertEqual(small.tracking, 0)
    }

    /// `2286:449`：四个 38pt 行加上下各 10pt，正好是稿子的 172pt 高。
    func testDropdownMenuGeometryAndShadowMatchFigma() {
        XCTAssertEqual(NvwaDropdownMenuMetrics.authoredWidth, 113)
        XCTAssertEqual(NvwaDropdownMenuMetrics.cornerRadius, 12)
        XCTAssertEqual(NvwaDropdownMenuMetrics.verticalPadding, 10)
        XCTAssertEqual(NvwaDropdownMenuMetrics.rowHorizontalPadding, 10)
        XCTAssertEqual(NvwaDropdownMenuMetrics.rowVerticalPadding, 8)
        XCTAssertEqual(NvwaDropdownMenuMetrics.rowSpacing, 4)
        XCTAssertEqual(NvwaDropdownMenuMetrics.checkIconSize, 20)
        XCTAssertEqual(NvwaDropdownMenuMetrics.height(itemCount: 4), 172)
        XCTAssertEqual(NvwaDropdownMenuMetrics.firstShadowOpacity, 0.10)
        XCTAssertEqual(NvwaDropdownMenuMetrics.firstShadowRadius, 3)
        XCTAssertEqual(NvwaDropdownMenuMetrics.firstShadowY, 2)
        XCTAssertEqual(NvwaDropdownMenuMetrics.secondShadowOpacity, 0.08)
        XCTAssertEqual(NvwaDropdownMenuMetrics.secondShadowRadius, 7)
        XCTAssertEqual(NvwaDropdownMenuMetrics.secondShadowY, 8)
    }

    func testFigmaButtonLeadingIconMatrix() {
        XCTAssertTrue(
            NvwaButtonMetrics.isFigmaAuthored(
                kind: .outline,
                size: .large,
                hasLeadingIcon: true
            )
        )
        XCTAssertFalse(
            NvwaButtonMetrics.isFigmaAuthored(
                kind: .primary,
                size: .large,
                hasLeadingIcon: true
            )
        )
        XCTAssertTrue(
            NvwaButtonMetrics.isFigmaAuthored(
                kind: .outline,
                size: .huge,
                hasLeadingIcon: true
            )
        )
        XCTAssertTrue(
            NvwaButtonMetrics.isFigmaAuthored(
                kind: .primary,
                size: .small,
                hasLeadingIcon: true
            )
        )
        XCTAssertEqual(NvwaButtonMetrics.iconSpacing(kind: .outline, size: .huge), 4)
        XCTAssertEqual(NvwaButtonMetrics.iconSpacing(kind: .outline, size: .large), 8)
        XCTAssertEqual(NvwaButtonMetrics.iconSpacing(kind: .primary, size: .small), 8)
    }

    func testSecondaryButtonUsesDedicatedFigmaGray() {
        XCTAssertEqual(NvwaButtonKind.secondary.backgroundRole, .buttonGray)
    }

    func testFigmaTagToneMatrixAndBindingsIncludeBlue() {
        XCTAssertEqual(NvwaTagTone.allCases, [.gray, .green, .red, .blue])
        XCTAssertEqual(NvwaTagTone.gray.foregroundRole, .grayPrimary)
        XCTAssertEqual(NvwaTagTone.gray.backgroundRole, .backgroundInput)
        XCTAssertEqual(NvwaTagTone.green.foregroundRole, .marketBuy)
        XCTAssertEqual(NvwaTagTone.green.backgroundRole, .alphaGreen20)
        XCTAssertEqual(NvwaTagTone.red.foregroundRole, .sentimentNegative)
        XCTAssertEqual(NvwaTagTone.red.backgroundRole, .alphaRed20)
        XCTAssertEqual(NvwaTagTone.blue.foregroundRole, .primaryGreen)
        XCTAssertEqual(NvwaTagTone.blue.backgroundRole, .alphaBlue10)
    }

    func testInputGeometryKeepsSizeAndValidationIndependent() {
        XCTAssertEqual(Nvwa.inputHeight, 48)
        XCTAssertEqual(NvwaInputMetrics.fieldHeight, 48)
        XCTAssertEqual(NvwaInputMetrics.supportingLineHeight, 20)
        XCTAssertEqual(NvwaInputMetrics.verticalSpacing, 4)
        XCTAssertEqual(NvwaInputMetrics.horizontalPadding, 16)
        XCTAssertEqual(NvwaInputMetrics.cornerRadius, 10)
        XCTAssertEqual(NvwaInputMetrics.valueTypography.figmaName, "T-G Medium")
        XCTAssertEqual(NvwaInputMetrics.valueTypography.size, 14)
        XCTAssertEqual(NvwaInputMetrics.valueTypography.lineHeight, 20)
        XCTAssertEqual(NvwaInputMetrics.valueTypography.tracking, 0.21, accuracy: 0.001)
        XCTAssertEqual(NvwaInputMetrics.valueTypography.weight, .medium)
    }

    func testModalHeaderGeometryPreservesVisibleAndHitTargetAnchors() {
        XCTAssertEqual(NvwaModalHeaderMetrics.height, 66)
        XCTAssertEqual(NvwaModalHeaderMetrics.dragAreaHeight, 16)
        XCTAssertEqual(NvwaModalHeaderMetrics.titleRowHeight, 50)
        XCTAssertEqual(NvwaModalHeaderMetrics.horizontalPadding, 15)
        XCTAssertEqual(NvwaModalHeaderMetrics.iconSize, 16)
        XCTAssertEqual(NvwaModalHeaderMetrics.hitTargetSize, 44)
        XCTAssertEqual(NvwaModalHeaderMetrics.actionOffset, 14)
    }

    func testToastHugsContentUntilItsMaximumWidth() {
        XCTAssertEqual(NvwaToastMetrics.horizontalPadding, 8)
        XCTAssertEqual(NvwaToastMetrics.verticalPadding, 6)
        XCTAssertEqual(NvwaToastMetrics.minimumTextHeight, 20)
        XCTAssertEqual(NvwaToastMetrics.maximumWidth, 300)
        XCTAssertEqual(NvwaToastMetrics.maximumTextWidth, 284)
        XCTAssertEqual(NvwaToastMetrics.cornerRadius, 10)
    }

    func testKeyFeatureIconScopeAndGeometryMatchCurrentFigmaFrame() {
        XCTAssertEqual(
            NvwaKeyFeatureIconKind.allCases,
            [.invest, .keep, .convert, .send, .receive, .add, .close, .tick, .warning]
        )

        for kind in NvwaKeyFeatureIconKind.allCases.prefix(6) {
            XCTAssertEqual(kind.containerSize, 56)
            XCTAssertEqual(kind.glyphSize, 28)
        }

        for kind in NvwaKeyFeatureIconKind.allCases.suffix(3) {
            XCTAssertEqual(kind.containerSize, 48)
            XCTAssertEqual(kind.glyphSize, 24)
        }
    }

    func testKeyFeaturePaintRolesMatchLiveFigmaBindings() {
        for kind in [
            NvwaKeyFeatureIconKind.invest,
            .keep,
            .convert,
            .send,
            .receive
        ] {
            XCTAssertEqual(kind.backgroundRole, .primaryGreen)
            XCTAssertEqual(kind.foregroundRole, .colorOnBlue)
        }

        XCTAssertEqual(NvwaKeyFeatureIconKind.add.backgroundRole, .backgroundVessel)
        XCTAssertEqual(NvwaKeyFeatureIconKind.add.foregroundRole, .grayPrimary)
        XCTAssertEqual(NvwaKeyFeatureIconKind.close.backgroundRole, .sentimentNegative)
        XCTAssertEqual(NvwaKeyFeatureIconKind.close.foregroundRole, .literalWhite)
        XCTAssertEqual(NvwaKeyFeatureIconKind.tick.backgroundRole, .primaryGreen)
        XCTAssertEqual(NvwaKeyFeatureIconKind.tick.foregroundRole, .literalWhite)
        XCTAssertEqual(NvwaKeyFeatureIconKind.warning.backgroundRole, .sentimentWarning)
        XCTAssertEqual(NvwaKeyFeatureIconKind.warning.foregroundRole, .black)
    }

    @MainActor
    func testDetailedVariantsAcceptHostInjectedImages() {
        let image = Image("HostInjectedRemixIcon")
        let text = Binding.constant("Example")

        _ = NvwaInputField(
            label: "Label",
            placeholder: "Placeholder",
            text: text,
            helpText: "Error"
        )
        _ = NvwaHint("Hint", rightIcon: image, rightIconAccessibilityLabel: "More")
        // Section 的图标槽位也是宿主注入的：Currency 收国旗，Text 收模板图标。
        _ = NvwaSection("100K", style: .secondary, isSelected: true) {}
        _ = NvwaSection("USD", style: .currency, isSelected: true, icon: { image }, action: {})
        _ = NvwaSection("Tab", style: .text, isSelected: false, icon: { image }, action: {})
        _ = NvwaTextDropdownButton("BTC", dropdownIcon: image) {}
        _ = NvwaTextDropdownButton("BTC", style: .large, dropdownIcon: image) {}
        _ = NvwaBackgroundDropdownButton("10%", dropdownIcon: image) {}
        _ = NvwaBackgroundDropdownButton("Symbol", size: .small, dropdownIcon: image) {}
        _ = NvwaDropdownMenu(
            options: ["ETH", "BTC", "BNB", "USDT"],
            selection: Binding.constant("BTC"),
            checkIcon: image,
            title: { $0 }
        )
        _ = NvwaScrollButton("Scroll to Confirm") {}
        _ = NvwaScrollButton("Scroll to Confirm", isLoading: true) {}
        _ = NvwaHint("Sync failed. ", level: .negative, actionTitle: "Retry", action: {})
        _ = NvwaToast("Saved")
        _ = NvwaToast(
            "This intentionally long toast verifies that multiline content remains constructible."
        )
        _ = NvwaModalHeader("Title")
        _ = NvwaModalHeader(
            "Title",
            leading: NvwaModalHeaderAction(
                icon: image,
                accessibilityLabel: "Delete",
                tone: .destructive,
                action: {}
            ),
            trailing: NvwaModalHeaderAction(
                icon: image,
                accessibilityLabel: "More",
                action: {}
            )
        )
    }

    @MainActor
    func testAllKeyFeatureKindsConstructWithBundledArtwork() {
        for kind in NvwaKeyFeatureIconKind.allCases {
            _ = NvwaKeyFeatureIcon(kind)
        }
    }
}
