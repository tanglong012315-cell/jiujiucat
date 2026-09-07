import Foundation
import XCTest

#if os(iOS)
@testable import PawFolio
#endif

final class SheetPresentationPolicyTests: XCTestCase {
    #if os(iOS)
    func testAdaptiveHeightUsesNaturalSizeUntilTheEightyPointCap() {
        XCTAssertGreaterThan(
            PawSheetSizing.bootstrapHeight,
            PawSheetSizing.initialHeight
        )
        XCTAssertEqual(
            PawSheetSizing.resolvedHeight(
                idealHeight: 420,
                viewportHeight: 844,
                bottomSafeArea: 34
            ),
            420
        )
        XCTAssertEqual(
            PawSheetSizing.resolvedHeight(
                idealHeight: 900,
                viewportHeight: 844,
                bottomSafeArea: 34
            ),
            730
        )
        XCTAssertEqual(
            PawSheetSizing.resolvedHeight(
                idealHeight: 20,
                viewportHeight: 844,
                bottomSafeArea: 34
            ),
            PawSheetSizing.initialHeight
        )
    }
    #endif

    /// The 2026-09-06 policy permits one shared adaptive style. Raw detents and
    /// the superseded half/full choices would reintroduce inconsistent heights.
    func testFeatureSheetsUseOnlySharedAdaptiveStyle() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let featuresDirectory = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("PawFolio/Features", isDirectory: true)

        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: featuresDirectory,
                includingPropertiesForKeys: nil
            )
        )
        var violations: [String] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains(".presentationDetents(")
                || source.contains("pawAdaptiveSheetHeight")
                || source.contains(".pawSheetPresentation(.")
                || source.contains("size: .half")
                || source.contains("size: .full") {
                violations.append(fileURL.lastPathComponent)
            }

            if source.contains(".pawSheetPresentation()")
                && !source.contains(".pawSheetMeasuredPart()") {
                violations.append("\(fileURL.lastPathComponent) (missing measured parts)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Use PawSheet or measured parts with pawSheetPresentation(): \(violations)"
        )
    }

    func testSharedPolicyCapsAtEightyPointsAndUsesWindowGeometry() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceDirectory = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("PawFolio", isDirectory: true)
        let controls = try String(
            contentsOf: sourceDirectory.appendingPathComponent("DesignSystem/PawControls.swift"),
            encoding: .utf8
        )
        let root = try String(
            contentsOf: sourceDirectory.appendingPathComponent("App/RootTabView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(controls.contains("static let topClearance: CGFloat = 80"))
        XCTAssertTrue(controls.contains("viewportHeight - topClearance - bottomSafeArea"))
        XCTAssertTrue(controls.contains(".presentationContentInteraction(.scrolls)"))
        XCTAssertTrue(root.contains(".environment(\\.pawViewportHeight, viewportHeight)"))
        XCTAssertFalse(controls.contains("UIScreen.main.bounds"))
    }

    /// A footer can consume the whole bootstrap detent before the middle
    /// ScrollView gets a layout pass. The content must keep its intrinsic
    /// vertical size or long forms (notably Add Earn) stay collapsed forever.
    func testSharedSheetMeasuresScrollableContentAtItsIntrinsicHeight() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceDirectory = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("PawFolio", isDirectory: true)
        let controls = try String(
            contentsOf: sourceDirectory.appendingPathComponent("DesignSystem/PawControls.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(controls.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(controls.contains(".onGeometryChange(for: CGFloat.self)"))
        XCTAssertTrue(controls.contains(".preference(key: PawSheetHeightPreferenceKey.self"))
    }

    func testTransactionsRemainAFullScreenDestination() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceDirectory = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("PawFolio", isDirectory: true)
        let source = try String(
            contentsOf: sourceDirectory.appendingPathComponent(
                "Features/Portfolio/LedgerPortfolioView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".sheet(isPresented: $showsTransactions)"))
        XCTAssertEqual(
            source.components(separatedBy: ".fullScreenCover(isPresented: $showsTransactions)").count - 1,
            2
        )
    }

    func testLanguagePickerUsesMeasuredAdaptiveSheet() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceDirectory = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("PawFolio", isDirectory: true)
        let source = try String(
            contentsOf: sourceDirectory.appendingPathComponent(
                "Features/Account/LanguagePickerSheet.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".pawSheetPresentation()"))
        XCTAssertTrue(source.contains(".pawSheetMeasuredPart()"))
        XCTAssertFalse(source.contains("maxHeight: .infinity"))
    }
}
