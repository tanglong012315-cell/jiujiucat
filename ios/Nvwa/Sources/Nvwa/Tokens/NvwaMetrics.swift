import SwiftUI

public extension Nvwa {
    static let radiusBlock: CGFloat = 20
    static let radiusCard: CGFloat = 16
    static let radiusControl: CGFloat = 10
    static let radiusCapsule: CGFloat = 100

    /// Shared field height from the Nvwa Text/Search/Date/Flag Input components.
    static let inputHeight: CGFloat = 48

    static let cardRadius = radiusBlock
    static let controlRadius: CGFloat = 12
    static let contentWidth: CGFloat = 760
}

public enum NvwaControlSize: Sendable {
    case huge
    case large
    case small
    case tiny

    public var height: CGFloat {
        switch self {
        case .huge: 48
        case .large: 40
        case .small: 32
        case .tiny: 28
        }
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .huge, .large: 24
        case .small, .tiny: 12
        }
    }
}
