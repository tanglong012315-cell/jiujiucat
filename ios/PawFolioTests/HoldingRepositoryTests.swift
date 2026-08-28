import Foundation
import XCTest
@testable import PawFolio

final class HoldingRepositoryTests: XCTestCase {
    func testSaveAndLoadPreservesVersionedHoldingAndTombstone() async throws {
        let location = try temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

        let repository = LocalHoldingRepository(fileURL: location)
        let holding = Holding(
            id: "h_saved",
            symbol: "AAPL",
            holdingKind: .market,
            quantity: 3,
            costPerShare: 200,
            createdAt: 1_780_000_000_000,
            deletedAt: 1_780_000_100_000
        )

        try await repository.save([holding])
        let loaded = try await repository.load()

        XCTAssertEqual(loaded, [holding])

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any]
        )
        XCTAssertEqual(object["storageVersion"] as? Int, 1)
    }

    func testLoadsLegacyBareArray() async throws {
        let location = try temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

        let holding = Holding(
            id: "h_legacy_local",
            symbol: "USDT",
            assetType: .stable,
            holdingKind: .interest,
            principal: 2_000,
            annualRate: 4,
            interestMode: .simple,
            createdAt: 1_780_000_000_000
        )
        let data = try JSONEncoder().encode([holding])
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: location)

        let repository = LocalHoldingRepository(fileURL: location)
        let loaded = try await repository.load()

        XCTAssertEqual(loaded, [holding])
    }

    func testCorruptFileIsReportedWithoutBeingReplaced() async throws {
        let location = try temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

        let original = Data("not-json".utf8)
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try original.write(to: location)

        let repository = LocalHoldingRepository(fileURL: location)

        do {
            _ = try await repository.load()
            XCTFail("Expected corrupt local data to be reported")
        } catch let error as HoldingRepositoryError {
            guard case .unreadableData = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: location), original)
    }

    func testScopedRepositoryKeepsGuestAndAccountsIsolated() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawfolio-scoped-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let repository = ScopedLocalHoldingRepository(baseDirectoryURL: baseDirectory)
        let guest = holding(id: "guest", symbol: "USDT")
        let firstAccount = holding(id: "first", symbol: "AAPL")
        let secondAccount = holding(id: "second", symbol: "VOO")

        try await repository.save([guest], for: .guest)
        try await repository.save([firstAccount], for: .account(userID: "user-a"))
        try await repository.save([secondAccount], for: .account(userID: "user/b"))

        let loadedGuest = try await repository.load(for: .guest)
        let loadedFirst = try await repository.load(for: .account(userID: "user-a"))
        let loadedSecond = try await repository.load(for: .account(userID: "user/b"))

        XCTAssertEqual(loadedGuest, [guest])
        XCTAssertEqual(loadedFirst, [firstAccount])
        XCTAssertEqual(loadedSecond, [secondAccount])
    }

    func testScopedRepositoryRejectsEmptyAccountIdentifier() async throws {
        let repository = ScopedLocalHoldingRepository(
            baseDirectoryURL: FileManager.default.temporaryDirectory
        )

        do {
            _ = try await repository.load(for: .account(userID: "  "))
            XCTFail("Expected empty account identifier to fail")
        } catch let error as HoldingRepositoryError {
            guard case .invalidAccountIdentifier = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
        }
    }

    func testFixedScopeRepositoriesNeverWriteAcrossGuestAndAccountFiles() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawfolio-active-scope-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let scopedRepository = ScopedLocalHoldingRepository(baseDirectoryURL: baseDirectory)
        let guestRepository = FixedScopeHoldingRepository(
            repository: scopedRepository,
            scope: .guest
        )
        let accountRepository = FixedScopeHoldingRepository(
            repository: scopedRepository,
            scope: .account(userID: "user-a")
        )
        let guest = holding(id: "guest", symbol: "USDT")
        let account = holding(id: "account", symbol: "AAPL")

        try await guestRepository.save([guest])
        try await accountRepository.save([account])

        let loadedAccount = try await accountRepository.load()
        XCTAssertEqual(loadedAccount, [account])
        let loadedGuest = try await guestRepository.load()
        XCTAssertEqual(loadedGuest, [guest])
    }

    private func temporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawfolio-tests-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent("holdings.json", isDirectory: false)
    }

    private func holding(id: String, symbol: String) -> Holding {
        Holding(
            id: id,
            symbol: symbol,
            holdingKind: symbol == "USDT" ? .interest : .market,
            quantity: symbol == "USDT" ? nil : 1,
            costPerShare: symbol == "USDT" ? nil : 100,
            principal: symbol == "USDT" ? 100 : nil,
            interestMode: symbol == "USDT" ? .simple : nil,
            createdAt: 100
        )
    }
}
