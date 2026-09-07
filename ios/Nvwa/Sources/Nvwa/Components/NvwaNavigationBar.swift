import SwiftUI

enum NvwaNavigationBarMetrics {
  static let height: CGFloat = 64
  // Figma places the 40-point visible circles 16 points from each edge. The
  // button keeps a 44-point hit target, so the layout inset starts 2 points
  // earlier while preserving the authored visual inset.
  static let horizontalPadding: CGFloat = 14
  static let hitTargetSize: CGFloat = 44
  static let visibleControlSize: CGFloat = 40
  /// 一侧只有一枚图标时的尺寸：返回、关闭、新增都是这一档。
  static let iconSize: CGFloat = 24
  /// 同一侧挤了两枚图标时改用小一档——`2224:66` 的主题与语言画的就是 20pt，
  /// 24pt 两颗并排会压过对面的关闭图标。用户 2026-09-03 定的尺寸。
  static let compactIconSize: CGFloat = 20
  /// 尾随图标组的内部间距，比两端 14pt 的页边距略窄，是这一组的专属值。
  static let trailingGroupSpacing: CGFloat = 15

  /// 头像首字母：`2206:768` 把 Avatar 实例的文字样式改写成了 `T-G Medium`，
  /// 不是 Avatar 组件本身那档 `B-L Semi Bold`。
  static let avatarTypography = Nvwa.Typography.titleGroup
  /// 二级导航标题 `2224:62`：`T-B Semi Bold`（18/24，-1%）。
  /// 2026-09-04 从 `B-M Semi Bold` 14pt 上调，三个 Icon 变体用的是同一档。
  static let titleTypography = Nvwa.Typography.titleBody

  static var avatarFontSize: CGFloat { avatarTypography.size }
  static var avatarTracking: CGFloat { avatarTypography.tracking }

  static var visualEdgeInset: CGFloat {
    horizontalPadding + ((hitTargetSize - visibleControlSize) / 2)
  }

  static var visualVerticalInset: CGFloat {
    (height - visibleControlSize) / 2
  }
}

/// The trailing action's colour. Figma authors both: the filled Primary
/// circle and the neutral `Add-Interactive` on `bg/vessel`. Hosts use the tone
/// to separate two different actions that share the same glyph.
public enum NvwaNavigationBarActionTone {
  case primary
  case neutral
}

/// 导航栏上的一枚 40pt 圆形控件。三个变体的差别只在于两侧各放了什么，
/// 所以槽位用同一个类型描述，不再按变体各开一个初始化器。
public struct NvwaNavigationBarItem {
  enum Content {
    case avatar(initials: String, image: Image?)
    case glyph(Image, tone: NvwaNavigationBarActionTone)
    /// 原色图片（国旗），不做模板化渲染。
    case artwork(Image)
  }

  let content: Content
  let accessibilityLabel: String
  let action: () -> Void

  /// `image` 是宿主注入的头像图（Figma 只画了首字母一档，这是代码扩展）：
  /// 给了就盖掉首字母，没给才显示首字母。
  public static func avatar(
    initials: String,
    image: Image? = nil,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) -> Self {
    Self(
      content: .avatar(initials: initials, image: image),
      accessibilityLabel: accessibilityLabel,
      action: action
    )
  }

  public static func icon(
    _ image: Image,
    tone: NvwaNavigationBarActionTone = .neutral,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) -> Self {
    Self(
      content: .glyph(image, tone: tone),
      accessibilityLabel: accessibilityLabel,
      action: action
    )
  }

  /// 语言图标是一枚**原色**国旗（`2224:73` 的 United Kingdom/China 组件），
  /// 不能走模板渲染——旗子模板化之后只剩一个纯色轮廓，看不出是哪国旗了。
  /// 渲染方式跟货币页 `CurrencyPickerView` 那一排国旗完全一样
  /// （`.resizable().scaledToFill()` 裁圆，不额外套插值/滤镜），用户
  /// 2026-09-03 点名要用那边「现成的」画法——同一份资源，画法也要对得上，
  /// 不要自己另起一套显得偏灰偏透明。
  public static func artwork(
    _ image: Image,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) -> Self {
    Self(
      content: .artwork(image),
      accessibilityLabel: accessibilityLabel,
      action: action
    )
  }
}

/// Nvwa 的 64pt 顶部导航，对应组件稿 `2224:91` 的五个变体：
///
/// - `添加持仓, Icon=Left` `2102:1169`：头像 + 新增；
/// - `二级导航, Icon=Left` `2102:1102`：返回/关闭 + 居中标题；
/// - `二级导航, Icon=Right` `2238:574`：只有尾随图标 + 居中标题；
/// - `二级导航, Icon=L+R` `2238:582`：两侧各一枚图标 + 居中标题；
/// - `个人中心, Icon=Left` `2224:66`：关闭 + 主题、语言两枚小图标。
///
/// 五者共用 64pt 骨架、16pt 视觉边距、40pt 圆形控件，差别只在两侧槽位与是否有
/// 标题，所以这里只有一个初始化器，按槽位组合即可——`Icon` 那三档就是「左槽位
/// 给不给」「右槽位给不给」的排列，不需要各开一个入口。功能图标由宿主注入。
public struct NvwaNavigationBar: View {
  private let leading: NvwaNavigationBarItem?
  private let title: String?
  private let trailing: [NvwaNavigationBarItem]

  public init(
    leading: NvwaNavigationBarItem? = nil,
    title: String? = nil,
    trailing: [NvwaNavigationBarItem] = []
  ) {
    self.leading = leading
    self.title = title
    self.trailing = trailing
  }

  public var body: some View {
    HStack(spacing: 0) {
      if let leading {
        item(leading, glyphSize: NvwaNavigationBarMetrics.iconSize)
      } else if reservesEmptySlots {
        emptySlot
      }

      if let title {
        Text(LocalizedStringKey(title))
          .nvwaTextStyle(NvwaNavigationBarMetrics.titleTypography)
          .foregroundStyle(Nvwa.grayPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity)
      } else {
        Spacer(minLength: 0)
      }

      if trailing.isEmpty {
        if reservesEmptySlots {
          emptySlot
        }
      } else {
        // 两枚图标收在一组里，间距 15——不能复用外层 `spacing: 0` 硬凑。
        HStack(spacing: NvwaNavigationBarMetrics.trailingGroupSpacing) {
          ForEach(Array(trailing.enumerated()), id: \.offset) { _, item in
            self.item(item, glyphSize: trailingGlyphSize)
          }
        }
      }
    }
    .padding(.horizontal, NvwaNavigationBarMetrics.horizontalPadding)
    .frame(maxWidth: .infinity)
    .frame(height: NvwaNavigationBarMetrics.height)
  }

  /// 有标题时两侧都要占位，标题才落在整条导航的正中：`2102:1102` 的尾随槽位
  /// 就是一个空的 40×40 框。没有标题时不占位，否则单边导航右边会空出一块。
  private var reservesEmptySlots: Bool {
    title != nil
  }

  private var trailingGlyphSize: CGFloat {
    trailing.count > 1
      ? NvwaNavigationBarMetrics.compactIconSize
      : NvwaNavigationBarMetrics.iconSize
  }

  private var emptySlot: some View {
    Color.clear
      .frame(
        width: NvwaNavigationBarMetrics.hitTargetSize,
        height: NvwaNavigationBarMetrics.hitTargetSize
      )
  }

  private func item(
    _ item: NvwaNavigationBarItem,
    glyphSize: CGFloat
  ) -> some View {
    Button(action: item.action) {
      control(for: item.content, glyphSize: glyphSize)
        .frame(
          width: NvwaNavigationBarMetrics.hitTargetSize,
          height: NvwaNavigationBarMetrics.hitTargetSize
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(NvwaPressButtonStyle())
    .accessibilityLabel(item.accessibilityLabel)
  }

  @ViewBuilder
  private func control(
    for content: NvwaNavigationBarItem.Content,
    glyphSize: CGFloat
  ) -> some View {
    switch content {
    case let .avatar(initials, image):
      NvwaAvatar(
        initials: initials,
        image: image,
        diameter: NvwaNavigationBarMetrics.visibleControlSize,
        typography: NvwaNavigationBarMetrics.avatarTypography
      )

    case let .glyph(image, tone):
      image
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: glyphSize, height: glyphSize)
        .foregroundStyle(
          tone == .primary ? Nvwa.colorOnBlue : Nvwa.grayPrimary
        )
        .frame(
          width: NvwaNavigationBarMetrics.visibleControlSize,
          height: NvwaNavigationBarMetrics.visibleControlSize
        )
        .background(
          tone == .primary ? Nvwa.primaryGreen : Nvwa.backgroundVessel,
          in: Circle()
        )

    case let .artwork(image):
      image
        .renderingMode(.original)
        .resizable()
        .scaledToFill()
        .frame(
          width: NvwaNavigationBarMetrics.compactIconSize,
          height: NvwaNavigationBarMetrics.compactIconSize
        )
        .clipShape(Circle())
        .frame(
          width: NvwaNavigationBarMetrics.visibleControlSize,
          height: NvwaNavigationBarMetrics.visibleControlSize
        )
        .background(Nvwa.backgroundVessel, in: Circle())
    }
  }
}
