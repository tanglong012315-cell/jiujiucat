import XCTest
@testable import PawFolio

final class GuestImportDecisionStoreTests: XCTestCase {
    func testDecisionPersistsPerAccountAcrossStoreInstances() async throws {
        let suiteName = "PawFolioTests.GuestImport.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let firstStore = UserDefaultsGuestImportDecisionStore(suiteName: suiteName)
        try await firstStore.save(.copiedIntoAccount, for: "account-a")
        try await firstStore.save(.keepSeparate, for: "account-b")

        let restoredStore = UserDefaultsGuestImportDecisionStore(suiteName: suiteName)
        let firstDecision = try await restoredStore.decision(for: "account-a")
        let secondDecision = try await restoredStore.decision(for: "account-b")
        let missingDecision = try await restoredStore.decision(for: "account-c")

        XCTAssertEqual(firstDecision, .copiedIntoAccount)
        XCTAssertEqual(secondDecision, .keepSeparate)
        XCTAssertNil(missingDecision)
    }

    func testDecisionStoreRejectsBlankAccountIdentifier() async throws {
        let suiteName = "PawFolioTests.GuestImport.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsGuestImportDecisionStore(suiteName: suiteName)

        do {
            try await store.save(.keepSeparate, for: "   ")
            XCTFail("Expected blank user identifier to fail")
        } catch let error as GuestImportDecisionStoreError {
            guard case .invalidUserIdentifier = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
