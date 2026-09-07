import XCTest
import SwiftUI

@testable import Nvwa

final class NvwaReorderTests: XCTestCase {
    private let rowHeight = 92.0

    private func destination(
        from index: Int,
        translation: Double,
        appliedSteps: Int = 0,
        count: Int = 4
    ) -> Int? {
        NvwaReorderProjection.destination(
            from: index,
            translation: translation,
            rowHeight: rowHeight,
            appliedSteps: appliedSteps,
            count: count
        )
    }

    func testInteractionMetricsKeepTheVerifiedGestureThresholds() {
        XCTAssertEqual(NvwaReorderMetrics.minimumPressDuration, 0.3)
        XCTAssertEqual(NvwaReorderMetrics.allowableMovement, 10)
        XCTAssertEqual(NvwaReorderMetrics.liftScale, 1.02)
        XCTAssertEqual(NvwaReorderMetrics.rowShadowOpacity, 0.16)
        XCTAssertEqual(NvwaReorderMetrics.rowShadowRadius, 12)
        XCTAssertEqual(NvwaReorderMetrics.rowShadowY, 4)
    }

    func testTranslationIsConstrainedToTheListAxis() {
        let translation = CGSize(width: 34, height: -76)

        XCTAssertEqual(
            NvwaReorderProjection.constrainedTranslation(translation, axis: .vertical),
            CGSize(width: 0, height: -76)
        )
        XCTAssertEqual(
            NvwaReorderProjection.constrainedTranslation(translation, axis: .horizontal),
            CGSize(width: 34, height: 0)
        )
    }

    func testReorderStateOwnsTheWholeDragLifecycle() {
        let items = ["A", "B", "C"]
        let layout = NvwaReorderLayout.vertical(itemExtent: 82)
        let endedAt = Date(timeIntervalSince1970: 100)
        var state = NvwaReorderState<String>()

        XCTAssertTrue(state.begin("A", in: items))
        XCTAssertTrue(state.isReordering)
        XCTAssertTrue(state.isActive("A"))
        XCTAssertEqual(state.feedbackTrigger, 1)
        XCTAssertFalse(state.allowsSelection())

        XCTAssertTrue(
            state.update(
                item: "A",
                translation: CGSize(width: 40, height: 90),
                items: items,
                layout: layout
            )
        )
        XCTAssertEqual(state.destinationIndex, 1)
        XCTAssertEqual(
            state.displacement(for: "B", in: items, layout: layout),
            CGSize(width: 0, height: -82)
        )
        XCTAssertEqual(
            state.finish(at: endedAt),
            NvwaReorderMove(item: "A", destinationIndex: 1)
        )
        XCTAssertFalse(state.isReordering)
        XCTAssertFalse(state.allowsSelection(at: endedAt))
        XCTAssertTrue(
            state.allowsSelection(
                at: endedAt.addingTimeInterval(
                    NvwaReorderMetrics.selectionSuppressionDuration + 0.01
                )
            )
        )
    }

    func testReorderStateOnlyPublishesWhenDestinationChanges() {
        let items = ["A", "B", "C"]
        let layout = NvwaReorderLayout.vertical(itemExtent: 82)
        var state = NvwaReorderState<String>()

        XCTAssertTrue(state.begin("B", in: items))
        XCTAssertFalse(
            state.update(
                item: "B",
                translation: CGSize(width: 50, height: 20),
                items: items,
                layout: layout
            )
        )
        XCTAssertTrue(
            state.update(
                item: "B",
                translation: CGSize(width: 50, height: -50),
                items: items,
                layout: layout
            )
        )
        XCTAssertFalse(
            state.update(
                item: "B",
                translation: CGSize(width: 70, height: -70),
                items: items,
                layout: layout
            )
        )
    }

    func testReorderStateKeepsIndependentSectionsIsolated() {
        let trading = ["BTC", "ETH"]
        let earn = ["Flexible", "Fixed"]
        let layout = NvwaReorderLayout.vertical(itemExtent: 82)
        var state = NvwaReorderState<String>()

        XCTAssertTrue(state.begin("BTC", in: trading))
        XCTAssertTrue(
            state.update(
                item: "BTC",
                translation: CGSize(width: 0, height: 82),
                items: trading,
                layout: layout
            )
        )
        XCTAssertEqual(state.displacement(for: "Flexible", in: earn, layout: layout), .zero)
    }

    func testAccessibilityMoveUsesTheSameBoundsAndFeedbackState() {
        let items = ["A", "B", "C"]
        var state = NvwaReorderState<String>()

        XCTAssertNil(state.accessibilityMove("A", by: -1, in: items))
        XCTAssertEqual(state.feedbackTrigger, 0)
        XCTAssertEqual(
            state.accessibilityMove("B", by: 1, in: items),
            NvwaReorderMove(item: "B", destinationIndex: 2)
        )
        XCTAssertEqual(state.feedbackTrigger, 1)
    }

    func testDisplacementMovesOnlyRowsBetweenOriginAndDestination() {
        let step = 82.0
        let offsets = (0..<4).map {
            NvwaReorderProjection.displacement(
                forIndex: $0,
                origin: 0,
                destination: 2,
                step: step
            )
        }
        XCTAssertEqual(offsets, [0, -step, -step, 0])
    }

    func testDisplacementMovesRowsDownWhenDraggingUpwards() {
        let step = 82.0
        let offsets = (0..<4).map {
            NvwaReorderProjection.displacement(
                forIndex: $0,
                origin: 2,
                destination: 0,
                step: step
            )
        }
        XCTAssertEqual(offsets, [step, step, 0, 0])
    }

    func testDisplacementIsZeroWhenNothingMoved() {
        XCTAssertEqual(
            (0..<4).map {
                NvwaReorderProjection.displacement(
                    forIndex: $0,
                    origin: 1,
                    destination: 1,
                    step: 82
                )
            },
            [0, 0, 0, 0]
        )
    }

    func testProjectionUsesTheOriginalSlotWithoutMutatingTheList() {
        XCTAssertEqual(
            NvwaReorderProjection.projectedDestination(
                from: 1,
                translation: rowHeight * 1.6,
                rowHeight: rowHeight,
                count: 4
            ),
            3
        )
        XCTAssertEqual(
            NvwaReorderProjection.projectedDestination(
                from: 2,
                translation: -rowHeight * 1.2,
                rowHeight: rowHeight,
                count: 4
            ),
            1
        )
    }

    func testStayingInsideHalfARowDoesNotMove() {
        XCTAssertNil(destination(from: 1, translation: 0))
        XCTAssertNil(destination(from: 1, translation: rowHeight * 0.49))
        XCTAssertNil(destination(from: 1, translation: -rowHeight * 0.49))
    }

    func testCrossingHalfARowMovesOneSlot() {
        XCTAssertEqual(destination(from: 1, translation: rowHeight * 0.5), 2)
        XCTAssertEqual(destination(from: 1, translation: -rowHeight * 0.5), 0)
    }

    func testMovingSeveralSlotsAtOnce() {
        XCTAssertEqual(destination(from: 0, translation: rowHeight * 2), 2)
        XCTAssertEqual(destination(from: 3, translation: -rowHeight * 3), 0)
    }

    func testAppliedStepsAreSubtracted() {
        XCTAssertNil(destination(from: 2, translation: rowHeight * 2, appliedSteps: 2))
        XCTAssertEqual(destination(from: 2, translation: rowHeight * 3, appliedSteps: 2), 3)
    }

    func testDraggingPastEitherEndClampsAndStops() {
        XCTAssertNil(destination(from: 3, translation: rowHeight * 5))
        XCTAssertNil(destination(from: 0, translation: -rowHeight * 5))
    }

    func testDraggingBackAfterClampingStillMovesOneSlotAtATime() {
        XCTAssertNil(destination(from: 3, translation: rowHeight * 3, appliedSteps: 2))
        XCTAssertEqual(destination(from: 3, translation: rowHeight, appliedSteps: 2), 2)
        XCTAssertEqual(destination(from: 3, translation: -rowHeight, appliedSteps: 2), 0)
    }

    func testSingleItemAndDegenerateInputsNeverMove() {
        XCTAssertNil(destination(from: 0, translation: rowHeight * 3, count: 1))
        XCTAssertNil(destination(from: 0, translation: rowHeight, count: 0))
        XCTAssertNil(
            NvwaReorderProjection.destination(
                from: 0,
                translation: rowHeight,
                rowHeight: 0,
                appliedSteps: 0,
                count: 4
            )
        )
        XCTAssertNil(destination(from: 9, translation: rowHeight))
        XCTAssertNil(destination(from: 1, translation: .nan))
        XCTAssertNil(destination(from: 1, translation: .infinity))
    }

    func testHorizontalItemsUseTheirRealCenters() {
        let widths = [82.0, 101.0, 96.0]
        let spacing = 10.0

        XCTAssertEqual(
            NvwaReorderProjection.projectedDestination(
                from: 0,
                translation: 51,
                itemWidths: widths,
                spacing: spacing
            ),
            1
        )
        XCTAssertEqual(
            NvwaReorderProjection.projectedDestination(
                from: 2,
                translation: -110,
                itemWidths: widths,
                spacing: spacing
            ),
            1
        )
    }

    func testHorizontalDragCanCrossSeveralItemsAndReturn() {
        let widths = [82.0, 101.0, 96.0, 74.0]

        XCTAssertEqual(
            NvwaReorderProjection.projectedDestination(
                from: 0,
                translation: 500,
                itemWidths: widths,
                spacing: 10
            ),
            3
        )
        XCTAssertEqual(
            NvwaReorderProjection.projectedDestination(
                from: 0,
                translation: 0,
                itemWidths: widths,
                spacing: 10
            ),
            0
        )
    }

    func testHorizontalInvalidInputsStayAtOrigin() {
        XCTAssertEqual(
            NvwaReorderProjection.projectedDestination(
                from: 1,
                translation: .infinity,
                itemWidths: [80, 90, 100],
                spacing: 10
            ),
            1
        )
        XCTAssertEqual(
            NvwaReorderProjection.projectedDestination(
                from: 1,
                translation: 100,
                itemWidths: [80, 0, 100],
                spacing: 10
            ),
            1
        )
    }
}
