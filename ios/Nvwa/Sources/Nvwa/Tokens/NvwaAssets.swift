import SwiftUI

/// Artwork owned by Nvwa components. Key Feature artwork is intentionally
/// bundled here because those nine glyphs are illustrations authored in the
/// Figma library, not interchangeable product/action icons.
enum NvwaInternalAsset: String, Sendable {
    case tooltipArrow = "NvwaTooltipArrow"
    case keyFeatureInvest = "NvwaKeyFeatureInvest"
    case keyFeatureKeep = "NvwaKeyFeatureKeep"
    case keyFeatureConvert = "NvwaKeyFeatureConvert"
    case keyFeatureSend = "NvwaKeyFeatureSend"
    case keyFeatureAdd = "NvwaKeyFeatureAdd"
    case keyFeatureClose = "NvwaKeyFeatureClose"
    case keyFeatureTick = "NvwaKeyFeatureTick"
    case keyFeatureWarning = "NvwaKeyFeatureWarning"

    var image: Image {
        Image(rawValue, bundle: .module)
    }
}
