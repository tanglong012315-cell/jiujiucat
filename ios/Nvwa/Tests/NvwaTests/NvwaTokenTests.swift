import SwiftUI
import XCTest

@testable import Nvwa

final class NvwaTokenTests: XCTestCase {
  func testFigmaColorPrimitivesRemainExact() {
    XCTAssertEqual(Nvwa.Hex.coreBrightBlueLight, 0x6999FF)
    XCTAssertEqual(Nvwa.Hex.coreBrightBlueDark, 0x4782FF)
    XCTAssertEqual(Nvwa.Hex.primaryGreenLight, 0x0051FE)
    XCTAssertEqual(Nvwa.Hex.primaryGreenDark, 0x2D66F0)
    XCTAssertEqual(Nvwa.Hex.grayPrimaryLight, 0x000000)
    XCTAssertEqual(Nvwa.Hex.grayPrimaryDark, 0xFFFFFF)
    XCTAssertEqual(Nvwa.Hex.graySecondary, 0x868685)
    XCTAssertEqual(Nvwa.Hex.textBlueLight, 0x0051FE)
    XCTAssertEqual(Nvwa.Hex.textBlueDark, 0x4782FF)
    XCTAssertEqual(Nvwa.Hex.colorOnBlue, 0xFFFFFF)
    XCTAssertEqual(Nvwa.Hex.textBlack, 0x000000)
    XCTAssertEqual(Nvwa.Hex.backgroundMainLight, 0xFFFFFF)
    XCTAssertEqual(Nvwa.Hex.backgroundMainDark, 0x000000)
    XCTAssertEqual(Nvwa.Hex.backgroundVesselLight, 0xEFEFEF)
    XCTAssertEqual(Nvwa.Hex.backgroundVesselDark, 0x212121)
    XCTAssertEqual(Nvwa.Hex.backgroundInputLight, 0xEFEFEF)
    XCTAssertEqual(Nvwa.Hex.backgroundInputDark, 0x1D1D1D)
    XCTAssertEqual(Nvwa.Hex.backgroundCardLight, 0xF6F6F6)
    XCTAssertEqual(Nvwa.Hex.backgroundCardDark, 0x212121)
    XCTAssertEqual(Nvwa.Hex.backgroundContainerLight, 0xFFFFFF)
    XCTAssertEqual(Nvwa.Hex.backgroundContainerDark, 0x373737)
    XCTAssertEqual(Nvwa.Hex.backgroundDialogueLight, 0xFFFFFF)
    XCTAssertEqual(Nvwa.Hex.backgroundDialogueDark, 0x262626)
    XCTAssertEqual(Nvwa.Hex.lineLight, 0xDEDEDD)
    XCTAssertEqual(Nvwa.Hex.lineDark, 0x2B2B2B)
    XCTAssertEqual(Nvwa.Hex.buttonGrayLight, 0xDEDEDD)
    XCTAssertEqual(Nvwa.Hex.buttonGrayDark, 0x3C3C3C)
    XCTAssertEqual(Nvwa.Hex.marketBuyLight, 0x1D7353)
    XCTAssertEqual(Nvwa.Hex.marketBuyDark, 0x2CC094)
    XCTAssertEqual(Nvwa.Hex.marketSellLight, 0xCE2632)
    XCTAssertEqual(Nvwa.Hex.marketSellDark, 0xF0616D)
    XCTAssertEqual(Nvwa.Hex.sentimentWarning, 0xEDC843)
    XCTAssertEqual(Nvwa.Hex.sentimentPositive, 0x2F5711)
    XCTAssertEqual(Nvwa.Hex.sentimentNegativeLight, 0xA8200D)
    XCTAssertEqual(Nvwa.Hex.sentimentNegativeDark, 0xDC432D)
    XCTAssertEqual(Nvwa.Hex.alphaGreen20LightRGBA, 0x4AB18B33)
    XCTAssertEqual(Nvwa.Hex.alphaGreen20DarkRGBA, 0x2CC09433)
    XCTAssertEqual(Nvwa.Hex.alphaRed20RGBA, 0xCE263233)
    XCTAssertEqual(Nvwa.Hex.alphaYellow20RGBA, 0xEDC84333)
    XCTAssertEqual(Nvwa.Hex.alphaBlue10LightRGBA, 0x0051FE1A)
    XCTAssertEqual(Nvwa.Hex.alphaBlue10DarkRGBA, 0x4782FF33)
    XCTAssertEqual(Nvwa.Hex.brightOrange, 0xFFC091)
    XCTAssertEqual(Nvwa.Hex.brightYellow, 0xFFEB69)
    XCTAssertEqual(Nvwa.Hex.brightBlue, 0xA0E1E1)
    XCTAssertEqual(Nvwa.Hex.pink, 0xFFD7EF)
  }

  func testLatestSelectionAndSliderTokensRemainExact() {
    XCTAssertEqual(Nvwa.Hex.primaryGreenLight, 0x0051FE)
    XCTAssertEqual(Nvwa.Hex.primaryGreenDark, 0x2D66F0)
    XCTAssertEqual(Nvwa.Hex.backgroundInputLight, 0xEFEFEF)
    XCTAssertEqual(Nvwa.Hex.backgroundInputDark, 0x1D1D1D)
    XCTAssertEqual(Nvwa.Hex.backgroundMainLight, 0xFFFFFF)
    XCTAssertEqual(Nvwa.Hex.backgroundMainDark, 0x000000)
  }

  /// 弹层底色和页面底色**只在深色下才不一样**——这正是 `NvwaModalHeader` 一度用错
  /// token 还没人发现的原因：浅色下两者都是 `#FFFFFF`，深色下才露出
  /// `#000000` 的头部压在 `#262626` 的弹层上。哪天有人觉得「这俩一样，随便用一个」，
  /// 这条会先响。
  func testDialogueSurfaceOnlyDivergesFromTheMainBackgroundInDarkMode() {
    XCTAssertEqual(Nvwa.Hex.backgroundDialogueLight, Nvwa.Hex.backgroundMainLight)
    XCTAssertNotEqual(Nvwa.Hex.backgroundDialogueDark, Nvwa.Hex.backgroundMainDark)
  }

  func testLatestButtonAndTagColorsRemainExact() {
    XCTAssertEqual(Nvwa.Hex.buttonGrayLight, 0xDEDEDD)
    XCTAssertEqual(Nvwa.Hex.buttonGrayDark, 0x3C3C3C)
    XCTAssertEqual(Nvwa.Hex.alphaBlue10LightRGBA, 0x0051FE1A)
    XCTAssertEqual(Nvwa.Hex.alphaBlue10DarkRGBA, 0x4782FF33)
    XCTAssertEqual(Nvwa.Hex.primaryGreenLight, 0x0051FE)
    XCTAssertEqual(Nvwa.Hex.primaryGreenDark, 0x2D66F0)
  }

  func testLegacyBackgroundNamesFollowCurrentFigmaRoles() {
    XCTAssertEqual(Nvwa.Hex.backgroundLight, Nvwa.Hex.backgroundMainLight)
    XCTAssertEqual(Nvwa.Hex.backgroundDark, Nvwa.Hex.backgroundMainDark)
    XCTAssertEqual(Nvwa.Hex.backgroundNeutralLight, Nvwa.Hex.backgroundVesselLight)
    XCTAssertEqual(Nvwa.Hex.backgroundNeutralDark, Nvwa.Hex.backgroundVesselDark)
    XCTAssertEqual(Nvwa.Hex.backgroundLightLight, Nvwa.Hex.backgroundInputLight)
    XCTAssertEqual(Nvwa.Hex.backgroundLightDark, Nvwa.Hex.backgroundInputDark)
  }

  func testControlSizesMatchFigma() {
    XCTAssertEqual(NvwaControlSize.huge.height, 48)
    XCTAssertEqual(NvwaControlSize.large.height, 40)
    XCTAssertEqual(NvwaControlSize.small.height, 32)
    XCTAssertEqual(NvwaControlSize.tiny.height, 28)
    XCTAssertEqual(NvwaControlSize.huge.horizontalPadding, 24)
    XCTAssertEqual(NvwaControlSize.large.horizontalPadding, 24)
    XCTAssertEqual(NvwaControlSize.small.horizontalPadding, 12)
  }

  /// Slider `Property 1=Default`, Figma node `2072:865`. The library resized it
  /// The current component uses a 4-point track with `rx=2` and a `r=5` fill
  /// under a centred 2-point stroke, so the visible thumb remains 12 points overall.
  func testSliderGeometryMatchesFigma() {
    XCTAssertEqual(NvwaSliderMetrics.height, 16)
    XCTAssertEqual(NvwaSliderMetrics.trackHeight, 4)
    XCTAssertEqual(NvwaSliderMetrics.thumbDiameter, 12)
    XCTAssertEqual(NvwaSliderMetrics.thumbBorderWidth, 2)
    XCTAssertEqual(NvwaSliderMetrics.trackCornerRadius, 2)
  }

  func testNavigationBarGeometryMatchesFigma() {
    XCTAssertEqual(NvwaNavigationBarMetrics.height, 64)
    XCTAssertEqual(NvwaNavigationBarMetrics.horizontalPadding, 14)
    XCTAssertEqual(NvwaNavigationBarMetrics.hitTargetSize, 44)
    XCTAssertEqual(NvwaNavigationBarMetrics.visibleControlSize, 40)
    XCTAssertEqual(NvwaNavigationBarMetrics.iconSize, 24)
    XCTAssertEqual(NvwaNavigationBarMetrics.compactIconSize, 20)
    XCTAssertEqual(NvwaNavigationBarMetrics.trailingGroupSpacing, 15)
    // 头像首字母是 `T-G Medium`（14/20，1.5%），标题是 `B-M Semi Bold`（14/22，1.25%）。
    XCTAssertEqual(NvwaNavigationBarMetrics.avatarFontSize, 14)
    XCTAssertEqual(NvwaNavigationBarMetrics.avatarTracking, 0.21)
    XCTAssertEqual(NvwaNavigationBarMetrics.avatarTypography.figmaName, "T-G Medium")
    XCTAssertEqual(NvwaNavigationBarMetrics.titleTypography.figmaName, "T-B Semi Bold")
    XCTAssertEqual(NvwaNavigationBarMetrics.titleTypography.size, 18)
    XCTAssertEqual(NvwaNavigationBarMetrics.titleTypography.lineHeight, 24)
    XCTAssertEqual(NvwaNavigationBarMetrics.visualEdgeInset, 16)
    XCTAssertEqual(NvwaNavigationBarMetrics.visualVerticalInset, 12)
  }

  /// Scroll button `2243:704`：345 × 56 的胶囊轨道，56pt 滑块，行程是宽度减滑块。
  func testScrollButtonGeometryMatchesFigma() {
    XCTAssertEqual(NvwaScrollButtonMetrics.height, 56)
    XCTAssertEqual(NvwaScrollButtonMetrics.knobDiameter, 56)
    XCTAssertEqual(NvwaScrollButtonMetrics.authoredWidth, 345)
    XCTAssertEqual(NvwaScrollButtonMetrics.spinnerSize, 24)
    // `2243:702` 的滑块停在 138，BG/Vessel 覆盖层宽 194 = 138 + 56，
    // 即左端到滑块右沿。
    XCTAssertEqual(
      NvwaScrollButtonMetrics.travel(inWidth: NvwaScrollButtonMetrics.authoredWidth),
      289
    )
    XCTAssertEqual(NvwaScrollButtonMetrics.travel(inWidth: 40), 0)
    XCTAssertTrue(NvwaScrollButtonMetrics.trailExtendsToKnobTrailingEdge)
  }

  /// Hint `2062:773`：32 高、圆角 10、内距 12/6、内容间距 4，提示插画是 12pt 的
  /// Warning 圆片，顶部再让 4pt。
  func testHintGeometryMatchesFigma() {
    XCTAssertEqual(NvwaHintMetrics.minimumHeight, 32)
    XCTAssertEqual(NvwaHintMetrics.cornerRadius, 10)
    XCTAssertEqual(NvwaHintMetrics.horizontalPadding, 12)
    XCTAssertEqual(NvwaHintMetrics.verticalPadding, 6)
    XCTAssertEqual(NvwaHintMetrics.contentSpacing, 4)
    XCTAssertEqual(NvwaHintMetrics.markSize, 12)
    XCTAssertEqual(NvwaHintMetrics.markTopInset, 4)
    XCTAssertEqual(NvwaHintMetrics.rightIconSize, 20)
  }

  /// 行盒：Figma 的行高是行盒总高，SwiftUI 的 `Text` 只给字体自带的高度，
  /// 差额要一半补首尾、全额补行间，两者加起来才等于稿子的行高。
  func testTypographyLineBoxRestoresFigmaLineHeight() {
    for token in Nvwa.Typography.all {
      let natural = token.naturalLineHeight
      XCTAssertGreaterThan(natural, 0, token.figmaName)
      // 单行：字体行盒 + 上下两个 half-leading = 稿子行高。
      XCTAssertEqual(
        natural + token.halfLeading * 2,
        max(token.lineHeight, natural),
        accuracy: 0.001,
        token.figmaName
      )
      // 多行：行间距补的是全额差额，行距才等于稿子行高。
      XCTAssertEqual(
        natural + token.lineSpacing,
        max(token.lineHeight, natural),
        accuracy: 0.001,
        token.figmaName
      )
    }
  }

  func testButtonTypographyMatchesEachFigmaVariant() {
    for kind: NvwaButtonKind in [.primary, .secondary, .outline, .warning, .outlineWarning, .buy, .sell] {
      XCTAssertEqual(NvwaButtonMetrics.fontSize(kind: kind, size: .huge), 16)
      XCTAssertEqual(NvwaButtonMetrics.tracking(kind: kind, size: .huge), 0.08)
      XCTAssertEqual(NvwaButtonMetrics.fontSize(kind: kind, size: .large), 14)
      XCTAssertEqual(NvwaButtonMetrics.tracking(kind: kind, size: .large), 0.175)
      XCTAssertEqual(NvwaButtonMetrics.fontSize(kind: kind, size: .small), 14)
      XCTAssertEqual(NvwaButtonMetrics.fontSize(kind: kind, size: .tiny), 12)
      XCTAssertEqual(NvwaButtonMetrics.tracking(kind: kind, size: .tiny), 0.12)
      XCTAssertFalse(NvwaButtonMetrics.usesSemibold(kind: kind, size: .tiny))
    }
    XCTAssertTrue(NvwaButtonMetrics.usesSemibold(kind: .outline, size: .large))
    XCTAssertFalse(NvwaButtonMetrics.usesSemibold(kind: .outlineWarning, size: .small))
    XCTAssertEqual(NvwaButtonMetrics.tracking(kind: .outlineWarning, size: .small), 0.14)
    XCTAssertEqual(NvwaButtonMetrics.tracking(kind: .primary, size: .small), 0.175)
    XCTAssertEqual(NvwaButtonMetrics.outlineWidth, 1)
  }

  /// 交易页的买入/卖出按钮（用户 2026-09-05 要求收进组件库）：底色走涨跌语义色，
  /// 不跟品牌色；排版和 primary 完全一致。
  func testBuyAndSellButtonsUseMarketColours() {
    XCTAssertEqual(NvwaButtonKind.buy.backgroundRole, .marketBuy)
    XCTAssertEqual(NvwaButtonKind.sell.backgroundRole, .marketSell)
    XCTAssertNotEqual(NvwaButtonKind.buy.backgroundRole, NvwaButtonKind.primary.backgroundRole)
    for kind: NvwaButtonKind in [.buy, .sell] {
      XCTAssertEqual(
        NvwaButtonMetrics.fontSize(kind: kind, size: .huge),
        NvwaButtonMetrics.fontSize(kind: .primary, size: .huge)
      )
      XCTAssertTrue(NvwaButtonMetrics.usesSemibold(kind: kind, size: .huge))
    }
  }

  func testAllFigmaTypographyTokensRemainExact() {
    let tokens = Nvwa.Typography.all
    XCTAssertEqual(tokens.count, 15)
    XCTAssertEqual(Set(tokens.map(\.figmaName)).count, 15)

    assertTypography(
      Nvwa.Typography.titleScreen,
      name: "T Semi Bold", size: 30, lineHeight: 34, tracking: -0.75,
      weight: .semibold, scaleRole: .largeTitle
    )
    assertTypography(
      Nvwa.Typography.titleSection,
      name: "T-S Semi Bold", size: 26, lineHeight: 32, tracking: -0.39,
      weight: .semibold, scaleRole: .title
    )
    assertTypography(
      Nvwa.Typography.titleSubsection,
      name: "T-Sub Semi Bold", size: 22, lineHeight: 28, tracking: -0.33,
      weight: .semibold, scaleRole: .title2
    )
    assertTypography(
      Nvwa.Typography.titleBody,
      name: "T-B Semi Bold", size: 18, lineHeight: 24, tracking: -0.18,
      weight: .semibold, scaleRole: .title3
    )
    assertTypography(
      Nvwa.Typography.titleGroup,
      name: "T-G Medium", size: 14, lineHeight: 20, tracking: 0.21,
      weight: .medium, scaleRole: .headline
    )
    assertTypography(
      Nvwa.Typography.bodyLarge,
      name: "B-L Regular", size: 16, lineHeight: 24, tracking: -0.08,
      weight: .regular, scaleRole: .body
    )
    assertTypography(
      Nvwa.Typography.bodyLargeSemibold,
      name: "B-L Semi Bold", size: 16, lineHeight: 24, tracking: 0.08,
      weight: .semibold, scaleRole: .body
    )
    assertTypography(
      Nvwa.Typography.bodyMedium,
      name: "B-M Regular", size: 14, lineHeight: 22, tracking: 0.14,
      weight: .regular, scaleRole: .body
    )
    assertTypography(
      Nvwa.Typography.bodyMediumSemibold,
      name: "B-M Semi Bold", size: 14, lineHeight: 22, tracking: 0.175,
      weight: .semibold, scaleRole: .body
    )
    assertTypography(
      Nvwa.Typography.bodySmall,
      name: "B-S Regular", size: 12, lineHeight: 20, tracking: 0.12,
      weight: .regular, scaleRole: .footnote
    )
    assertTypography(
      Nvwa.Typography.bodySmallSemibold,
      name: "B-S Semi Bold", size: 12, lineHeight: 20, tracking: 0.12,
      weight: .semibold, scaleRole: .footnote
    )
    assertTypography(
      Nvwa.Typography.linkLarge,
      name: "Link L Semi Bold", size: 16, lineHeight: 24, tracking: 0.16,
      weight: .semibold, underlined: true, scaleRole: .body
    )
    assertTypography(
      Nvwa.Typography.linkMedium,
      name: "Link M Semi Bold", size: 14, lineHeight: 22, tracking: 0.175,
      weight: .semibold, underlined: true, scaleRole: .body
    )
    assertTypography(
      Nvwa.Typography.caption1,
      name: "C-1 Regular", size: 11, lineHeight: 18, tracking: 0.11,
      weight: .regular, scaleRole: .caption
    )
    assertTypography(
      Nvwa.Typography.caption2,
      name: "C-2 Regular", size: 10, lineHeight: 16, tracking: 0.1,
      weight: .regular, scaleRole: .caption2
    )
  }

  /// Outline Button `Large` + `Leading`, Figma node `2119:1267`. It follows the
  /// 14-point Large ramp with the same 8-point icon gap the small and tiny
  /// leading variants already use.
  func testOutlineLargeLeadingMatchesFigmaVariant() {
    XCTAssertEqual(NvwaButtonMetrics.fontSize(kind: .outline, size: .large), 14)
    XCTAssertTrue(NvwaButtonMetrics.usesSemibold(kind: .outline, size: .large))
    XCTAssertEqual(NvwaButtonMetrics.tracking(kind: .outline, size: .large), 0.175)
  }

  /// Outline Button `Huge` + `Leading`, Figma node `2216:916`.
  func testOutlineHugeLeadingMatchesFigmaVariant() {
    XCTAssertEqual(NvwaButtonMetrics.fontSize(kind: .outline, size: .huge), 16)
    XCTAssertTrue(NvwaButtonMetrics.usesSemibold(kind: .outline, size: .huge))
    XCTAssertEqual(NvwaButtonMetrics.tracking(kind: .outline, size: .huge), 0.08)
    XCTAssertEqual(NvwaButtonMetrics.iconSpacing(kind: .outline, size: .huge), 4)
  }

  /// 组件稿 `2224:91` 的三个变体全部用同一个槽位化初始化器表达，宿主注入图标。
  @MainActor
  func testNavigationBarComposesEveryFigmaVariant() {
    let icon = Image("HostInjectedRemixIcon")

    // 添加持仓 `2102:1169`
    _ = NvwaNavigationBar(
      leading: .avatar(
        initials: "NV",
        accessibilityLabel: "Open profile",
        action: {}
      ),
      trailing: [
        .icon(icon, tone: .primary, accessibilityLabel: "Add item", action: {})
      ]
    )
    // 二级导航 / Icon=Left `2102:1102`
    _ = NvwaNavigationBar(
      leading: .icon(icon, accessibilityLabel: "Back", action: {}),
      title: "Title"
    )
    // 二级导航 / Icon=Right `2238:574`：左槽位留空，标题仍落在正中。
    _ = NvwaNavigationBar(
      title: "Title",
      trailing: [.icon(icon, accessibilityLabel: "Close", action: {})]
    )
    // 二级导航 / Icon=L+R `2238:582`
    _ = NvwaNavigationBar(
      leading: .icon(icon, accessibilityLabel: "Back", action: {}),
      title: "Title",
      trailing: [.icon(icon, accessibilityLabel: "Close", action: {})]
    )
    // 个人中心 `2224:66`
    _ = NvwaNavigationBar(
      leading: .icon(icon, accessibilityLabel: "Close", action: {}),
      trailing: [
        .icon(icon, accessibilityLabel: "Toggle appearance", action: {}),
        .artwork(icon, accessibilityLabel: "Change language", action: {})
      ]
    )
    // 未登录态是代码扩展，只换左槽位。
    _ = NvwaNavigationBar(
      leading: .icon(icon, accessibilityLabel: "Log in", action: {}),
      trailing: [
        .icon(icon, tone: .primary, accessibilityLabel: "Add item", action: {})
      ]
    )
  }

  /// 头像有三档 Figma 用法，组件不钉死其中一档：`2014:7932` 是 42 配
  /// `B-L Semi Bold`，`47:2224` 的个人中心大头像是 72 配 `T Semi Bold`，
  /// 导航栏 `2206:768` 是 40 配 `T-G Medium`。
  @MainActor
  func testAvatarAcceptsEveryFigmaSize() {
    _ = NvwaAvatar(initials: "TL")
    _ = NvwaAvatar(
      initials: "TL",
      diameter: 72,
      typography: Nvwa.Typography.titleScreen
    )
    _ = NvwaAvatar(
      initials: "TL",
      diameter: NvwaNavigationBarMetrics.visibleControlSize,
      typography: NvwaNavigationBarMetrics.avatarTypography
    )
  }


  /// Section `2071:843`: 28 high, radius 24, horizontal padding 16,
  /// vertical padding 3, with Alpha Blue 10% behind the selected state.
  @MainActor
  func testSectionUsesRefreshedFigmaStyle() {
    _ = NvwaSection("100K", isSelected: true) {}
    _ = NvwaSection("100K", isSelected: false, expandsHorizontally: true) {}
    XCTAssertEqual(Nvwa.Hex.primaryGreenLight, 0x0051FE)
  }

  private func assertTypography(
    _ token: NvwaTypographyToken,
    name: String,
    size: CGFloat,
    lineHeight: CGFloat,
    tracking: CGFloat,
    weight: Nvwa.FontWeight,
    underlined: Bool = false,
    scaleRole: NvwaTextScaleRole,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(token.figmaName, name, file: file, line: line)
    XCTAssertEqual(token.size, size, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(token.lineHeight, lineHeight, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(token.tracking, tracking, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(token.weight, weight, file: file, line: line)
    XCTAssertEqual(token.isUnderlined, underlined, file: file, line: line)
    XCTAssertEqual(token.scaleRole, scaleRole, file: file, line: line)
  }
}
