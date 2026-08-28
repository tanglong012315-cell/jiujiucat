import Foundation
import XCTest
@testable import PawFolio

final class AccountProfileStoreTests: XCTestCase {
    func testProfilePersistsPerAccountWithCurrentSchemaVersion() async throws {
        let suiteName = "PawFolioTests.AccountProfile.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsAccountProfileStore(suiteName: suiteName)
        try await store.save(
            LocalAccountProfile(
                displayName: "  Snow Cat  ",
                avatar: .faceCute,
                updatedAtMilliseconds: 100
            ),
            for: "account-a"
        )
        try await store.save(
            LocalAccountProfile(
                displayName: "Midnight",
                avatar: .catBobo,
                updatedAtMilliseconds: 200
            ),
            for: "account-b"
        )

        let restored = UserDefaultsAccountProfileStore(suiteName: suiteName)
        let first = try await restored.profile(for: "account-a")
        let second = try await restored.profile(for: "account-b")

        XCTAssertEqual(first?.schemaVersion, LocalAccountProfile.currentSchemaVersion)
        XCTAssertEqual(first?.displayName, "Snow Cat")
        XCTAssertEqual(first?.avatar, .faceCute)
        XCTAssertEqual(first?.updatedAtMilliseconds, 100)
        XCTAssertEqual(second?.displayName, "Midnight")
        XCTAssertEqual(second?.avatar, .catBobo)
        XCTAssertEqual(second?.updatedAtMilliseconds, 200)
    }

    func testLegacyProfileMigratesPlaceholderAvatarAndMissingTimestamp() throws {
        let data = Data(
            #"{"schemaVersion":1,"displayName":"Legacy Cat","avatar":"ginger"}"#.utf8
        )

        let profile = try JSONDecoder().decode(LocalAccountProfile.self, from: data)

        XCTAssertEqual(profile.schemaVersion, LocalAccountProfile.currentSchemaVersion)
        XCTAssertEqual(profile.displayName, "Legacy Cat")
        XCTAssertEqual(profile.avatar, .faceLove)
        XCTAssertEqual(profile.updatedAtMilliseconds, 0)
    }

    func testProfileValidationRejectsBlankAccountAndLongName() async throws {
        let suiteName = "PawFolioTests.AccountProfile.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAccountProfileStore(suiteName: suiteName)

        do {
            try await store.save(LocalAccountProfile(), for: "   ")
            XCTFail("Expected a blank account identifier to fail")
        } catch let error as AccountProfileStoreError {
            XCTAssertEqual(error, .invalidUserIdentifier)
        }

        do {
            try await store.save(
                LocalAccountProfile(displayName: String(repeating: "猫", count: 21)),
                for: "account-a"
            )
            XCTFail("Expected an overlong display name to fail")
        } catch let error as AccountProfileStoreError {
            XCTAssertEqual(error, .invalidDisplayName)
        }
    }

    func testProfileMergeUsesNewestTimestampAndLocalTieBreak() throws {
        let local = LocalAccountProfile(
            displayName: "Local",
            avatar: .faceHappy,
            updatedAtMilliseconds: 200
        )
        let olderRemote = LocalAccountProfile(
            displayName: "Remote",
            avatar: .catPuffy,
            updatedAtMilliseconds: 100
        )
        let newerRemote = LocalAccountProfile(
            displayName: "Remote",
            avatar: .catPuffy,
            updatedAtMilliseconds: 300
        )
        let tiedRemote = LocalAccountProfile(
            displayName: "Remote",
            avatar: .catPuffy,
            updatedAtMilliseconds: 200
        )

        let localWinner = try XCTUnwrap(
            AccountProfileMerge.reconcile(local: local, remote: olderRemote)
        )
        XCTAssertEqual(localWinner.profile, local)
        XCTAssertTrue(localWinner.shouldUploadRemotely)
        XCTAssertFalse(localWinner.shouldSaveLocally)

        let remoteWinner = try XCTUnwrap(
            AccountProfileMerge.reconcile(local: local, remote: newerRemote)
        )
        XCTAssertEqual(remoteWinner.profile, newerRemote)
        XCTAssertTrue(remoteWinner.shouldSaveLocally)
        XCTAssertFalse(remoteWinner.shouldUploadRemotely)

        let tieWinner = try XCTUnwrap(
            AccountProfileMerge.reconcile(local: local, remote: tiedRemote)
        )
        XCTAssertEqual(tieWinner.profile, local)
        XCTAssertTrue(tieWinner.shouldUploadRemotely)
    }

    func testUneditedMigratedLocalProfileDoesNotCreateMissingRemoteRow() throws {
        let migrated = LocalAccountProfile(
            displayName: "Legacy",
            avatar: .faceLove,
            updatedAtMilliseconds: 0
        )

        let result = try XCTUnwrap(
            AccountProfileMerge.reconcile(local: migrated, remote: nil)
        )

        XCTAssertEqual(result.profile, migrated)
        XCTAssertFalse(result.shouldSaveLocally)
        XCTAssertFalse(result.shouldUploadRemotely)
    }
}
