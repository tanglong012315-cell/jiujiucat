import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Runtime-only interaction metrics for sortable content.
///
/// Reordering is not a Figma-authored component variant. Nvwa owns these values so every host
/// gets the same scroll threshold, lift timing, and active-row treatment.
enum NvwaReorderMetrics {
    static let minimumPressDuration: TimeInterval = 0.3
    static let allowableMovement: CGFloat = 10
    static let liftScale: CGFloat = 1.02
    static let rowShadowOpacity = 0.16
    static let rowShadowRadius: CGFloat = 12
    static let rowShadowY: CGFloat = 4
    static let chipShadowOpacity = 0.2
    static let chipShadowRadius: CGFloat = 6
    static let chipShadowY: CGFloat = 3
    static let liftAnimationDuration = 0.16
    static let selectionSuppressionDuration: TimeInterval = 0.2
}

/// Pure geometry used by sortable vertical rows and variable-width horizontal chips.
enum NvwaReorderProjection {
    /// Keeps a sortable item on the axis owned by its host list. The recognizer still observes
    /// the full finger path so scroll and swipe arbitration remain unchanged.
    static func constrainedTranslation(_ translation: CGSize, axis: Axis) -> CGSize {
        switch axis {
        case .horizontal:
            CGSize(width: translation.width, height: 0)
        case .vertical:
            CGSize(width: 0, height: translation.height)
        }
    }

    static func projectedDestination(
        from startIndex: Int,
        translation: Double,
        itemWidths: [Double],
        spacing: Double
    ) -> Int {
        guard itemWidths.indices.contains(startIndex),
              itemWidths.allSatisfy({ $0 > 0 && $0.isFinite }),
              spacing >= 0,
              spacing.isFinite,
              translation.isFinite else {
            return startIndex
        }

        var centers: [Double] = []
        centers.reserveCapacity(itemWidths.count)
        var leading = 0.0
        for width in itemWidths {
            centers.append(leading + width / 2)
            leading += width + spacing
        }

        let draggedCenter = centers[startIndex] + translation
        var destination = startIndex
        if translation > 0, startIndex < centers.count - 1 {
            for index in (startIndex + 1)..<centers.count {
                let threshold = (centers[index - 1] + centers[index]) / 2
                if draggedCenter >= threshold { destination = index }
            }
        } else if translation < 0, startIndex > 0 {
            for index in stride(from: startIndex - 1, through: 0, by: -1) {
                let threshold = (centers[index] + centers[index + 1]) / 2
                if draggedCenter <= threshold { destination = index }
            }
        }
        return destination
    }

    static func projectedDestination(
        from startIndex: Int,
        translation: Double,
        rowHeight: Double,
        count: Int
    ) -> Int {
        guard count > 0,
              rowHeight > 0,
              translation.isFinite,
              (0..<count).contains(startIndex) else {
            return startIndex
        }

        let steps = Int((translation / rowHeight).rounded())
        return min(max(startIndex + steps, 0), count - 1)
    }

    /// The caller must first ensure that the dragged item and the displaced item belong to the
    /// same list. Indices alone cannot distinguish two independently sortable sections.
    static func displacement(
        forIndex index: Int,
        origin: Int,
        destination: Int,
        step: Double
    ) -> Double {
        guard index != origin, step.isFinite else { return 0 }
        if origin < destination, index > origin, index <= destination { return -step }
        if destination < origin, index >= destination, index < origin { return step }
        return 0
    }

    static func destination(
        from index: Int,
        translation: Double,
        rowHeight: Double,
        appliedSteps: Int,
        count: Int
    ) -> Int? {
        guard count > 1,
              rowHeight > 0,
              translation.isFinite,
              (0..<count).contains(index) else {
            return nil
        }

        let startIndex = index - appliedSteps
        let target = projectedDestination(
            from: startIndex,
            translation: translation,
            rowHeight: rowHeight,
            count: count
        )
        return target == index ? nil : target
    }
}

/// Geometry contract for a sortable collection. Keeping the axis and projection data together
/// prevents a horizontal list from accidentally using vertical movement (or vice versa).
public enum NvwaReorderLayout: Equatable {
    case vertical(itemExtent: CGFloat)
    case horizontal(itemExtents: [CGFloat], spacing: CGFloat)

    fileprivate var axis: Axis {
        switch self {
        case .vertical: .vertical
        case .horizontal: .horizontal
        }
    }

    fileprivate func destination(from origin: Int, translation: CGSize, count: Int) -> Int {
        switch self {
        case let .vertical(itemExtent):
            NvwaReorderProjection.projectedDestination(
                from: origin,
                translation: Double(translation.height),
                rowHeight: Double(itemExtent),
                count: count
            )
        case let .horizontal(itemExtents, spacing):
            NvwaReorderProjection.projectedDestination(
                from: origin,
                translation: Double(translation.width),
                itemWidths: itemExtents.map(Double.init),
                spacing: Double(spacing)
            )
        }
    }

    fileprivate func displacementExtent(at origin: Int) -> CGFloat? {
        switch self {
        case let .vertical(itemExtent):
            guard itemExtent > 0, itemExtent.isFinite else { return nil }
            return itemExtent
        case let .horizontal(itemExtents, spacing):
            guard itemExtents.indices.contains(origin),
                  itemExtents[origin] > 0,
                  itemExtents[origin].isFinite,
                  spacing >= 0,
                  spacing.isFinite else { return nil }
            return itemExtents[origin] + spacing
        }
    }
}

public struct NvwaReorderMove<ID: Hashable>: Equatable {
    public let item: ID
    public let destinationIndex: Int
}

/// Complete list-level state for Nvwa reordering.
///
/// Feature views keep one value per independently sortable list. Nvwa owns the start/destination
/// bookkeeping, section isolation, post-drop tap suppression, displacement, and accessibility
/// move calculations so those invariants cannot drift between screens.
public struct NvwaReorderState<ID: Hashable> {
    public private(set) var activeItem: ID?
    public private(set) var destinationIndex: Int?
    public private(set) var feedbackTrigger = 0

    private var originIndex: Int?
    private var selectionSuppressedUntil = Date.distantPast

    public init() {}

    public var isReordering: Bool { activeItem != nil }

    public func isActive(_ item: ID) -> Bool {
        activeItem == item
    }

    public func allowsSelection(at date: Date = Date()) -> Bool {
        date >= selectionSuppressedUntil
    }

    @discardableResult
    public mutating func begin(_ item: ID, in items: [ID]) -> Bool {
        guard activeItem == nil, let origin = items.firstIndex(of: item) else { return false }
        activeItem = item
        originIndex = origin
        destinationIndex = origin
        selectionSuppressedUntil = .distantFuture
        feedbackTrigger &+= 1
        return true
    }

    /// Returns true only when another item boundary was crossed. Callers can use this to avoid
    /// invalidating a parent view for every pointer sample.
    @discardableResult
    public mutating func update(
        item: ID,
        translation: CGSize,
        items: [ID],
        layout: NvwaReorderLayout
    ) -> Bool {
        guard activeItem == item,
              items.contains(item),
              let originIndex else { return false }
        let next = layout.destination(
            from: originIndex,
            translation: translation,
            count: items.count
        )
        guard destinationIndex != next else { return false }
        destinationIndex = next
        return true
    }

    public func displacement(
        for item: ID,
        in items: [ID],
        layout: NvwaReorderLayout
    ) -> CGSize {
        guard let activeItem,
              items.contains(activeItem),
              let originIndex,
              let destinationIndex,
              let index = items.firstIndex(of: item),
              item != activeItem,
              let extent = layout.displacementExtent(at: originIndex) else {
            return .zero
        }
        let displacement = CGFloat(
            NvwaReorderProjection.displacement(
                forIndex: index,
                origin: originIndex,
                destination: destinationIndex,
                step: Double(extent)
            )
        )
        return layout.axis == .horizontal
            ? CGSize(width: displacement, height: 0)
            : CGSize(width: 0, height: displacement)
    }

    public mutating func finish(at date: Date = Date()) -> NvwaReorderMove<ID>? {
        let move = activeItem.flatMap { item in
            destinationIndex.map { NvwaReorderMove(item: item, destinationIndex: $0) }
        }
        activeItem = nil
        originIndex = nil
        destinationIndex = nil
        selectionSuppressedUntil = date.addingTimeInterval(
            NvwaReorderMetrics.selectionSuppressionDuration
        )
        return move
    }

    public mutating func accessibilityMove(
        _ item: ID,
        by delta: Int,
        in items: [ID]
    ) -> NvwaReorderMove<ID>? {
        guard let origin = items.firstIndex(of: item), !items.isEmpty else { return nil }
        let destination = min(max(origin + delta, 0), items.count - 1)
        guard destination != origin else { return nil }
        feedbackTrigger &+= 1
        return NvwaReorderMove(item: item, destinationIndex: destination)
    }
}

public enum NvwaReorderLiftStyle: Sendable {
    case row
    case chip
}

private struct NvwaReorderLiftModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool
    let style: NvwaReorderLiftStyle
    let offset: CGSize

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .row:
            content
                .background(Nvwa.backgroundMain)
                .scaleEffect(isActive ? NvwaReorderMetrics.liftScale : 1)
                .shadow(
                    color: .black.opacity(isActive ? NvwaReorderMetrics.rowShadowOpacity : 0),
                    radius: NvwaReorderMetrics.rowShadowRadius,
                    y: NvwaReorderMetrics.rowShadowY
                )
                .zIndex(isActive ? 1 : 0)
                .animation(liftAnimation, value: isActive)
                // Keep the translation outside the shadow effect so the lifted row and its
                // shadow are composited and moved as one layer. Applying `.offset` before this
                // modifier can leave the shadow rendered at the row's original layout position.
                .offset(x: offset.width, y: offset.height)
        case .chip:
            content
                .background(Nvwa.backgroundMain.opacity(isActive ? 1 : 0), in: Capsule())
                .shadow(
                    color: Color(
                        .sRGB,
                        red: 69 / 255,
                        green: 71 / 255,
                        blue: 69 / 255,
                        opacity: isActive ? NvwaReorderMetrics.chipShadowOpacity : 0
                    ),
                    radius: NvwaReorderMetrics.chipShadowRadius,
                    y: NvwaReorderMetrics.chipShadowY
                )
                .zIndex(isActive ? 1 : 0)
                .animation(liftAnimation, value: isActive)
                .offset(x: offset.width, y: offset.height)
        }
    }

    private var liftAnimation: Animation? {
        reduceMotion
            ? nil
            : .snappy(duration: NvwaReorderMetrics.liftAnimationDuration, extraBounce: 0)
    }
}

private extension View {
    func nvwaReorderLift(
        isActive: Bool,
        style: NvwaReorderLiftStyle = .row,
        offset: CGSize = .zero
    ) -> some View {
        modifier(NvwaReorderLiftModifier(isActive: isActive, style: style, offset: offset))
    }
}

#if canImport(UIKit)
/// A transparent interaction layer for sortable content embedded in a `ScrollView`.
///
/// A quick vertical movement stays with the enclosing scroll view. A stationary press lifts the
/// item after 300 ms, while an optional horizontal pan can drive a reveal action. Because this
/// UIKit view owns hit testing, taps are recognized here as well and wait for the long press to
/// fail, preventing a completed reorder from also opening the row.
private struct NvwaReorderGestureOverlay: UIViewRepresentable {
    private let onTap: (() -> Void)?
    private let onHorizontalSwipeChanged: ((CGSize) -> Void)?
    private let onHorizontalSwipeEnded: ((CGSize) -> Void)?
    private let onBegan: () -> Void
    private let onChanged: (CGSize) -> Void
    private let onEnded: () -> Void

    init(
        onTap: (() -> Void)? = nil,
        onHorizontalSwipeChanged: ((CGSize) -> Void)? = nil,
        onHorizontalSwipeEnded: ((CGSize) -> Void)? = nil,
        onBegan: @escaping () -> Void,
        onChanged: @escaping (CGSize) -> Void,
        onEnded: @escaping () -> Void
    ) {
        self.onTap = onTap
        self.onHorizontalSwipeChanged = onHorizontalSwipeChanged
        self.onHorizontalSwipeEnded = onHorizontalSwipeEnded
        self.onBegan = onBegan
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onHorizontalSwipeChanged: onHorizontalSwipeChanged,
            onHorizontalSwipeEnded: onHorizontalSwipeEnded,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isAccessibilityElement = false

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = NvwaReorderMetrics.minimumPressDuration
        longPress.allowableMovement = NvwaReorderMetrics.allowableMovement
        longPress.cancelsTouchesInView = true
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)

        let horizontalPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHorizontalPan(_:))
        )
        horizontalPan.delegate = context.coordinator
        horizontalPan.require(toFail: longPress)
        view.addGestureRecognizer(horizontalPan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onHorizontalSwipeChanged = onHorizontalSwipeChanged
        context.coordinator.onHorizontalSwipeEnded = onHorizontalSwipeEnded
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.finishReorderIfNeeded()
        coordinator.finishSwipeIfNeeded(translation: .zero)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (() -> Void)?
        var onHorizontalSwipeChanged: ((CGSize) -> Void)?
        var onHorizontalSwipeEnded: ((CGSize) -> Void)?
        var onBegan: () -> Void
        var onChanged: (CGSize) -> Void
        var onEnded: () -> Void

        private var reorderStartLocation = CGPoint.zero
        private var isReordering = false
        private var isSwiping = false

        init(
            onTap: (() -> Void)?,
            onHorizontalSwipeChanged: ((CGSize) -> Void)?,
            onHorizontalSwipeEnded: ((CGSize) -> Void)?,
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGSize) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onHorizontalSwipeChanged = onHorizontalSwipeChanged
            self.onHorizontalSwipeEnded = onHorizontalSwipeEnded
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let pan = gestureRecognizer as? UIPanGestureRecognizer {
                guard onHorizontalSwipeChanged != nil || onHorizontalSwipeEnded != nil else {
                    return false
                }
                let velocity = pan.velocity(in: gestureRecognizer.view)
                return abs(velocity.x) > abs(velocity.y)
            }

            return !Self.enclosingScrollViews(of: gestureRecognizer.view).contains { $0.isDragging }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onTap?()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: nil)
            switch gesture.state {
            case .began:
                Self.stopScrolling(around: gesture.view)
                reorderStartLocation = location
                isReordering = true
                onBegan()
            case .changed where isReordering:
                onChanged(
                    CGSize(
                        width: location.x - reorderStartLocation.x,
                        height: location.y - reorderStartLocation.y
                    )
                )
            case .ended, .cancelled, .failed:
                finishReorderIfNeeded()
            default:
                break
            }
        }

        @objc func handleHorizontalPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .began, .changed:
                isSwiping = true
                onHorizontalSwipeChanged?(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                finishSwipeIfNeeded(
                    translation: CGSize(width: translation.x, height: translation.y)
                )
            default:
                break
            }
        }

        func finishReorderIfNeeded() {
            guard isReordering else { return }
            isReordering = false
            onEnded()
        }

        func finishSwipeIfNeeded(translation: CGSize) {
            guard isSwiping else { return }
            isSwiping = false
            onHorizontalSwipeEnded?(translation)
        }

        private static func stopScrolling(around view: UIView?) {
            for scrollView in enclosingScrollViews(of: view) {
                scrollView.panGestureRecognizer.isEnabled = false
                scrollView.panGestureRecognizer.isEnabled = true
            }
        }

        private static func enclosingScrollViews(of view: UIView?) -> [UIScrollView] {
            var found: [UIScrollView] = []
            var node = view?.superview
            while let current = node {
                if let scrollView = current as? UIScrollView { found.append(scrollView) }
                node = current.superview
            }
            return found
        }
    }
}

/// Combines the gesture layer, lifted-item treatment, and live translation for one sortable item.
///
/// The live pointer translation is intentionally kept in this modifier's local state. Hosts only
/// need to update their shared destination when the dragged item crosses another item, avoiding a
/// full parent-screen render for every touch sample.
private struct NvwaReorderableModifier<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liveOffset = CGSize.zero

    @Binding var state: NvwaReorderState<ID>
    let item: ID
    let items: [ID]
    let layout: NvwaReorderLayout
    let style: NvwaReorderLiftStyle
    let onTap: (() -> Void)?
    let onHorizontalSwipeChanged: ((CGSize) -> Void)?
    let onHorizontalSwipeEnded: ((CGSize) -> Void)?
    let onLift: (() -> Void)?
    let onMove: (ID, Int) -> Void

    func body(content: Content) -> some View {
        let isActive = state.isActive(item)
        let restingOffset = state.displacement(for: item, in: items, layout: layout)

        content
            .nvwaReorderLift(
                isActive: isActive,
                style: style,
                offset: isActive ? liveOffset : restingOffset
            )
            .overlay {
                NvwaReorderGestureOverlay(
                    onTap: handleTap,
                    onHorizontalSwipeChanged: onHorizontalSwipeChanged,
                    onHorizontalSwipeEnded: onHorizontalSwipeEnded,
                    onBegan: begin,
                    onChanged: update,
                    onEnded: finish
                )
            }
            .animation(
                isActive || reduceMotion
                    ? nil
                    : .snappy(duration: NvwaReorderMetrics.liftAnimationDuration, extraBounce: 0),
                value: state.destinationIndex
            )
            .onChange(of: isActive) { _, active in
                if !active { liveOffset = .zero }
            }
    }

    private func handleTap() {
        guard state.allowsSelection() else { return }
        onTap?()
    }

    private func begin() {
        var next = state
        guard next.begin(item, in: items) else { return }
        liveOffset = .zero
        state = next
        onLift?()
    }

    private func update(_ translation: CGSize) {
        let constrainedTranslation = NvwaReorderProjection.constrainedTranslation(
            translation,
            axis: layout.axis
        )
        liveOffset = constrainedTranslation

        var next = state
        if next.update(
            item: item,
            translation: constrainedTranslation,
            items: items,
            layout: layout
        ) {
            state = next
        }
    }

    private func finish() {
        let updateStateAndMove = {
            var next = state
            let move = next.finish()
            state = next
            liveOffset = .zero
            if let move {
                onMove(move.item, move.destinationIndex)
            }
        }

        if reduceMotion {
            updateStateAndMove()
        } else {
            withAnimation(
                .snappy(duration: NvwaReorderMetrics.liftAnimationDuration, extraBounce: 0),
                updateStateAndMove
            )
        }
    }
}

public extension View {
    /// Applies Nvwa's complete sortable-item behavior. The host owns one `NvwaReorderState` per
    /// independent list and only supplies the current item order plus the final move operation.
    func nvwaReorderable<ID: Hashable>(
        item: ID,
        items: [ID],
        state: Binding<NvwaReorderState<ID>>,
        layout: NvwaReorderLayout,
        style: NvwaReorderLiftStyle = .row,
        onTap: (() -> Void)? = nil,
        onHorizontalSwipeChanged: ((CGSize) -> Void)? = nil,
        onHorizontalSwipeEnded: ((CGSize) -> Void)? = nil,
        onLift: (() -> Void)? = nil,
        onMove: @escaping (ID, Int) -> Void
    ) -> some View {
        modifier(
            NvwaReorderableModifier(
                state: state,
                item: item,
                items: items,
                layout: layout,
                style: style,
                onTap: onTap,
                onHorizontalSwipeChanged: onHorizontalSwipeChanged,
                onHorizontalSwipeEnded: onHorizontalSwipeEnded,
                onLift: onLift,
                onMove: onMove
            )
        )
    }
}
#endif
