import Flutter
@testable import Runner
import UIKit
import XCTest

final class RunnerTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: "VivordoSnapshotStoreTests")
    defaults.removePersistentDomain(forName: "VivordoSnapshotStoreTests")
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: "VivordoSnapshotStoreTests")
    defaults = nil
    super.tearDown()
  }

  func testSnapshotStoreDecodesVersionedSnapshot() throws {
    defaults.set(1, forKey: "siriSchemaVersion")
    defaults.set("account-generation", forKey: "siriAccountGeneration")
    defaults.set(1_789_792_200_000.0, forKey: "siriPublishedAt")
    defaults.set("2026-09-19", forKey: "siriDataDay")
    defaults.set(54, forKey: "siriStressScore")
    defaults.set(["Short sleep", "Busy calendar"], forKey: "stressDrivers")
    defaults.set(6_240, forKey: "steps")
    defaults.set(74, forKey: "siriHeartRateLatest")
    defaults.set(7.4, forKey: "siriSleepHours")

    let snapshot = try VivordoSnapshotStore(defaults: defaults).load()

    XCTAssertEqual(snapshot.schemaVersion, 1)
    XCTAssertEqual(snapshot.accountGeneration, "account-generation")
    XCTAssertEqual(snapshot.dataDay, "2026-09-19")
    XCTAssertEqual(snapshot.stressScore, 54)
    XCTAssertEqual(snapshot.stressDrivers, ["Short sleep", "Busy calendar"])
    XCTAssertEqual(snapshot.steps, 6_240)
    XCTAssertEqual(snapshot.latestHeartRate, 74)
    XCTAssertEqual(snapshot.sleepHours, 7.4)
  }

  func testSnapshotStoreRejectsClearedAccount() {
    defaults.set(1, forKey: "siriSchemaVersion")
    defaults.set("", forKey: "siriAccountGeneration")
    defaults.set(1_789_792_200_000.0, forKey: "siriPublishedAt")

    XCTAssertThrowsError(try VivordoSnapshotStore(defaults: defaults).load()) {
      XCTAssertEqual($0 as? VivordoSnapshotError, .accountUnavailable)
    }
  }

  func testSnapshotStoreRejectsUnsupportedSchema() {
    defaults.set(2, forKey: "siriSchemaVersion")

    XCTAssertThrowsError(try VivordoSnapshotStore(defaults: defaults).load()) {
      XCTAssertEqual($0 as? VivordoSnapshotError, .unsupportedSchema(2))
    }
  }

  func testFreshnessRejectsOldAndFutureSnapshots() throws {
    defaults.set(1, forKey: "siriSchemaVersion")
    defaults.set("account-generation", forKey: "siriAccountGeneration")
    defaults.set(1_000_000.0, forKey: "siriPublishedAt")
    let store = VivordoSnapshotStore(defaults: defaults)
    let snapshot = try store.load()

    XCTAssertTrue(
      store.isFresh(
        snapshot,
        now: Date(timeIntervalSince1970: 1_030),
        maximumAge: 60
      )
    )
    XCTAssertFalse(
      store.isFresh(
        snapshot,
        now: Date(timeIntervalSince1970: 1_061),
        maximumAge: 60
      )
    )
    XCTAssertFalse(
      store.isFresh(
        snapshot,
        now: Date(timeIntervalSince1970: 999),
        maximumAge: 60
      )
    )
  }

}
