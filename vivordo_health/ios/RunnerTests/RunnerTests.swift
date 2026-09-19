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

  func testSiriQueryAnswersCurrentAndPartialSnapshots() {
    seedSnapshot(publishedAt: 1_000)
    defaults.set(63, forKey: "siriStressScore")
    defaults.set(["Short sleep", "Workload", "Ignored third driver"], forKey: "stressDrivers")
    defaults.set(7.5, forKey: "siriSleepHours")
    defaults.set(72, forKey: "siriHeartRateLatest")
    defaults.set(8_450, forKey: "steps")

    let service = VivordoSiriQueryService(store: VivordoSnapshotStore(defaults: defaults))
    let now = Date(timeIntervalSince1970: 1_100)

    XCTAssertEqual(
      service.answer(for: .stress, now: now).dialog,
      "Your Vivordo stress score is 63 out of 100. Your main drivers are Short sleep and Workload."
    )
    XCTAssertEqual(service.answer(for: .sleep, now: now).dialog, "Vivordo recorded 7 hours and 30 minutes of sleep.")
    XCTAssertEqual(service.answer(for: .heartRate, now: now).dialog, "Your latest heart rate is 72 beats per minute.")
    XCTAssertEqual(service.answer(for: .steps, now: now).dialog, "You've taken 8,450 steps today.")
    XCTAssertEqual(
      service.answer(for: .wellness, now: now).dialog,
      "Vivordo doesn't have a wellness score for you yet today."
    )
  }

  func testSiriQueryRejectsStaleSnapshot() {
    seedSnapshot(publishedAt: 1_000)
    defaults.set(80, forKey: "siriWellnessScore")
    let service = VivordoSiriQueryService(store: VivordoSnapshotStore(defaults: defaults))

    XCTAssertEqual(
      service.answer(
        for: .wellness,
        now: Date(timeIntervalSince1970: 1_000 + VivordoSiriQueryService.maximumSnapshotAge + 1)
      ).dialog,
      "Your Vivordo data needs a refresh. Open the app to update it."
    )
  }

  func testSiriQueryHandlesMissingSnapshot() {
    let service = VivordoSiriQueryService(store: VivordoSnapshotStore(defaults: defaults))
    XCTAssertEqual(
      service.answer(for: .steps).dialog,
      "Open Vivordo to sign in and refresh your health data."
    )
  }

  private func seedSnapshot(publishedAt: TimeInterval) {
    defaults.set(1, forKey: "siriSchemaVersion")
    defaults.set("account-generation", forKey: "siriAccountGeneration")
    defaults.set(publishedAt * 1000, forKey: "siriPublishedAt")
    defaults.set("2026-09-19", forKey: "siriDataDay")
  }

}
