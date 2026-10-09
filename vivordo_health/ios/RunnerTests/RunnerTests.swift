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
      service.answer(for: .capacity, now: now).dialog,
      "Vivordo doesn't have your Capacity for today yet. It comes in once last night's sleep syncs."
    )
    XCTAssertEqual(
      service.answer(for: .trainingLoad, now: now).dialog,
      "Vivordo is still learning your usual week of activity. Training load needs about four weeks."
    )
  }

  func testSiriQueryRejectsStaleSnapshot() {
    seedSnapshot(publishedAt: 1_000)
    seedCapacity(80)
    let service = VivordoSiriQueryService(store: VivordoSnapshotStore(defaults: defaults))

    XCTAssertEqual(
      service.answer(
        for: .capacity,
        now: Date(timeIntervalSince1970: 1_000 + VivordoSiriQueryService.maximumSnapshotAge + 1)
      ).dialog,
      "Your Vivordo data needs a refresh. Open the app to update it."
    )
  }

  func testSiriQueryBuildsDistinctStressAndCapacityCards() {
    seedSnapshot(publishedAt: 1_000)
    defaults.set(32, forKey: "siriStressScore")
    defaults.set(["Busy calendar"], forKey: "stressDrivers")
    seedCapacity(84)

    let service = VivordoSiriQueryService(store: VivordoSnapshotStore(defaults: defaults))
    let now = Date(timeIntervalSince1970: 1_100)
    let stress = service.answer(for: .stress, now: now)
    let capacity = service.answer(for: .capacity, now: now)

    XCTAssertEqual(stress.metric, .stress)
    XCTAssertEqual(stress.title, "Stress Score")
    XCTAssertEqual(stress.value, "32")
    XCTAssertEqual(stress.status, "Low stress")
    XCTAssertEqual(stress.detail, "Main drivers: Busy calendar")
    XCTAssertEqual(stress.progress, 0.32)

    XCTAssertEqual(capacity.metric, .capacity)
    XCTAssertEqual(capacity.title, "Capacity")
    XCTAssertEqual(capacity.value, "84")
    XCTAssertEqual(capacity.status, "Above your usual")
    XCTAssertNil(capacity.detail)
    XCTAssertEqual(capacity.progress, 0.84)
    XCTAssertEqual(capacity.dialog, "Your Capacity today is 84, which is above your usual.")
  }

  func testCapacityUsesMyDaysRecentDemand() {
    seedSnapshot(publishedAt: 1_000)
    seedCapacity(84)
    defaults.set(37, forKey: "siriDemand")
    defaults.set("Room to spare today", forKey: "siriDemandHeadline")
    defaults.set(900_000.0, forKey: "siriDemandAt")
    let service = VivordoSiriQueryService(store: VivordoSnapshotStore(defaults: defaults))

    let answer = service.answer(for: .capacity, now: Date(timeIntervalSince1970: 1_100))
    XCTAssertEqual(answer.dialog, "Your Capacity today is 84, which is above your usual. Room to spare today.")
    XCTAssertEqual(answer.status, "Room to spare today")
    XCTAssertEqual(answer.detail, "Demand 37 still ahead today")

    // Hours old: left out rather than out of date.
    let later = service.answer(for: .capacity, now: Date(timeIntervalSince1970: 1_000 + 3 * 3_600))
    XCTAssertEqual(later.dialog, "Your Capacity today is 84, which is above your usual.")
  }

  func testTrainingLoadAndMeetingAnswers() {
    seedSnapshot(publishedAt: 1_000)
    defaults.set("high", forKey: "siriTrainingState")
    defaults.set(1.6, forKey: "siriTrainingRatio")
    defaults.set(4, forKey: "siriTrainingHardDays")
    let now = Date(timeIntervalSince1970: 1_100)
    defaults.set(
      [[
        "title": "Team sync",
        "startAt": (now.timeIntervalSince1970 + 3_600) * 1_000,
        "high": true,
        "lift": "21% over your usual",
      ]],
      forKey: "siriMeetingPatterns"
    )
    let service = VivordoSiriQueryService(store: VivordoSnapshotStore(defaults: defaults))

    XCTAssertEqual(
      service.answer(for: .trainingLoad, now: now).dialog,
      "Your training load is high. The last 7 days were 60% above your usual week, with 4 hard days. An easier few days will help."
    )
    let meetings = service.answer(for: .meetings, now: now)
    XCTAssertTrue(meetings.dialog.hasPrefix("Team sync at "))
    XCTAssertTrue(meetings.dialog.hasSuffix("usually raises your heart rate, about 21% over your usual."))
    XCTAssertEqual(meetings.status, "Heart rate usually up")
    XCTAssertEqual(
      service.answer(for: .meetings, now: now.addingTimeInterval(7_200)).dialog,
      "None of your meetings left today has a heart-rate pattern yet."
    )
  }

  func testSiriQueryHandlesMissingSnapshot() {
    let service = VivordoSiriQueryService(store: VivordoSnapshotStore(defaults: defaults))
    XCTAssertEqual(
      service.answer(for: .steps).dialog,
      "Open Vivordo to sign in and refresh your health data."
    )
  }

  func testCalendarSnapshotDecodesAndSortsEvents() throws {
    let morning = Date(timeIntervalSince1970: 2_000)
    let afternoon = Date(timeIntervalSince1970: 4_000)
    defaults.set(
      [
        calendarEvent("Afternoon", start: afternoon, duration: 1_800),
        calendarEvent("Morning", start: morning, duration: 3_600, kind: "fitness"),
      ],
      forKey: "calendarEvents"
    )
    defaults.set(1_900_000.0, forKey: "calendarWeekUpdatedAt")

    let snapshot = try VivordoCalendarSnapshotStore(defaults: defaults).load()

    XCTAssertEqual(snapshot.updatedAt, Date(timeIntervalSince1970: 1_900))
    XCTAssertEqual(snapshot.events.map(\.title), ["Morning", "Afternoon"])
    XCTAssertEqual(snapshot.events.first?.kind, "fitness")
  }

  func testCalendarQueriesReturnTodayAndNextEvent() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
      year: 2026,
      month: 9,
      day: 22,
      hour: 12
    ))!
    let first = calendar.date(byAdding: .hour, value: 1, to: now)!
    let second = calendar.date(byAdding: .hour, value: 3, to: now)!
    defaults.set(
      [
        calendarEvent("Team meeting", start: first, duration: 3_600),
        calendarEvent("Workout", start: second, duration: 2_700, kind: "fitness"),
      ],
      forKey: "calendarEvents"
    )
    defaults.set(now.addingTimeInterval(-600).timeIntervalSince1970 * 1_000, forKey: "calendarWeekUpdatedAt")

    let service = VivordoCalendarQueryService(
      store: VivordoCalendarSnapshotStore(defaults: defaults),
      calendar: calendar
    )
    let today = service.answer(for: .today, now: now)
    let next = service.answer(for: .next, now: now)

    XCTAssertEqual(today.title, "Today's Schedule")
    XCTAssertEqual(today.status, "2 events remaining")
    XCTAssertEqual(today.events.map(\.title), ["Team meeting", "Workout"])
    XCTAssertTrue(today.dialog.contains("Team meeting"))

    XCTAssertEqual(next.title, "Next Event")
    XCTAssertEqual(next.status, "Today")
    XCTAssertEqual(next.events.map(\.title), ["Team meeting"])
    XCTAssertTrue(next.dialog.contains("Team meeting"))
  }

  func testCalendarQueryRejectsStaleCache() {
    let now = Date(timeIntervalSince1970: 10_000)
    defaults.set(
      [calendarEvent("Old event", start: now, duration: 3_600)],
      forKey: "calendarEvents"
    )
    defaults.set(
      (now.timeIntervalSince1970 - VivordoCalendarQueryService.maximumSnapshotAge - 1) * 1_000,
      forKey: "calendarWeekUpdatedAt"
    )

    let answer = VivordoCalendarQueryService(
      store: VivordoCalendarSnapshotStore(defaults: defaults)
    ).answer(for: .next, now: now)

    XCTAssertEqual(answer.status, "Refresh needed")
    XCTAssertTrue(answer.events.isEmpty)
  }

  func testPlanningServiceCombinesScheduleAndHealthContext() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
      year: 2026,
      month: 9,
      day: 22,
      hour: 12
    ))!
    seedSnapshot(publishedAt: now.timeIntervalSince1970 - 300)
    defaults.set(72, forKey: "siriStressScore")
    seedCapacity(45)
    defaults.set(5.5, forKey: "siriSleepHours")
    defaults.set(
      [
        calendarEvent("Planning", start: now.addingTimeInterval(1_800), duration: 1_800),
        calendarEvent("Review", start: now.addingTimeInterval(4_200), duration: 3_000),
        calendarEvent("Interview", start: now.addingTimeInterval(7_800), duration: 3_000),
      ],
      forKey: "siriCalendarEvents"
    )
    defaults.set((now.timeIntervalSince1970 - 300) * 1_000, forKey: "calendarWeekUpdatedAt")

    let answer = VivordoPlanningService(
      healthStore: VivordoSnapshotStore(defaults: defaults),
      calendarStore: VivordoCalendarSnapshotStore(defaults: defaults),
      calendar: calendar
    ).answer(for: .scheduleLoad, now: now)

    XCTAssertEqual(answer.title, "Schedule Load")
    XCTAssertEqual(answer.headline, "Demanding")
    XCTAssertNotNil(answer.loadScore)
    XCTAssertGreaterThanOrEqual(answer.loadScore ?? 0, 67)
    XCTAssertTrue(answer.drivers.contains("Stress is elevated at 72"))
    XCTAssertTrue(answer.drivers.contains("Sleep was 5 hr 30 min"))
    XCTAssertTrue(answer.dialog.contains("back-to-back"))
    XCTAssertEqual(answer.events.map(\.title), ["Planning", "Review", "Interview"])
    XCTAssertEqual(
      answer.priorities,
      [
        "Prepare for Planning",
        "Protect time for recovery",
        "Create a buffer between meetings",
      ]
    )
  }

  func testScheduleLoadUsesMyDaysDemandWhenFresh() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!
    seedSnapshot(publishedAt: now.timeIntervalSince1970 - 300)
    seedCapacity(86)
    defaults.set(37, forKey: "siriDemand")
    defaults.set("Room to spare today", forKey: "siriDemandHeadline")
    defaults.set((now.timeIntervalSince1970 - 600) * 1_000, forKey: "siriDemandAt")
    defaults.set(
      [calendarEvent("Team sync", start: now.addingTimeInterval(3_600), duration: 3_600)],
      forKey: "siriCalendarEvents"
    )
    defaults.set((now.timeIntervalSince1970 - 300) * 1_000, forKey: "calendarWeekUpdatedAt")

    let answer = VivordoPlanningService(
      healthStore: VivordoSnapshotStore(defaults: defaults),
      calendarStore: VivordoCalendarSnapshotStore(defaults: defaults),
      calendar: calendar
    ).answer(for: .scheduleLoad, now: now)

    XCTAssertEqual(answer.headline, "Room to spare today")
    XCTAssertEqual(answer.loadScore, 37)
    XCTAssertEqual(
      answer.dialog,
      "Room to spare today. Your Demand for the rest of today is 37 against a Capacity of 86."
    )
  }

  func testScheduleLoadCardIncludesAllDayAndCompletedEventsForToday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
      year: 2026,
      month: 9,
      day: 22,
      hour: 12
    ))!
    let morning = now.addingTimeInterval(-3_600)
    defaults.set(
      [
        calendarEvent("Morning review", start: morning, duration: 1_800),
        calendarEvent("Next meeting", start: now.addingTimeInterval(3_600), duration: 1_800),
        calendarEvent("Conference", start: now, duration: 86_400, isAllDay: true),
      ],
      forKey: "siriCalendarEvents"
    )
    defaults.set((now.timeIntervalSince1970 - 300) * 1_000, forKey: "calendarWeekUpdatedAt")

    let answer = VivordoPlanningService(
      healthStore: VivordoSnapshotStore(defaults: defaults),
      calendarStore: VivordoCalendarSnapshotStore(defaults: defaults),
      calendar: calendar
    ).answer(for: .scheduleLoad, now: now)

    XCTAssertEqual(
      answer.events.map(\.title),
      ["Conference", "Morning review", "Next meeting"]
    )
    XCTAssertEqual(
      answer.priorities,
      ["Prepare for Next meeting", "Protect your open focus time"]
    )
  }

  func testPlanningServiceFindsFirstThirtyMinuteRecoveryWindow() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
      year: 2026,
      month: 9,
      day: 22,
      hour: 12,
      minute: 7
    ))!
    let first = calendar.date(from: DateComponents(
      year: 2026,
      month: 9,
      day: 22,
      hour: 12
    ))!
    let second = calendar.date(from: DateComponents(
      year: 2026,
      month: 9,
      day: 22,
      hour: 14
    ))!
    defaults.set(
      [
        calendarEvent("Current meeting", start: first, duration: 3_600),
        calendarEvent("Later meeting", start: second, duration: 3_600),
      ],
      forKey: "siriCalendarEvents"
    )
    defaults.set((now.timeIntervalSince1970 - 300) * 1_000, forKey: "calendarWeekUpdatedAt")

    let answer = VivordoPlanningService(
      healthStore: VivordoSnapshotStore(defaults: defaults),
      calendarStore: VivordoCalendarSnapshotStore(defaults: defaults),
      calendar: calendar
    ).answer(for: .recoveryWindow, now: now)

    let expectedStart = calendar.date(from: DateComponents(
      year: 2026,
      month: 9,
      day: 22,
      hour: 13
    ))!
    XCTAssertEqual(answer.title, "Recovery Window")
    XCTAssertEqual(answer.recoveryWindow?.start, expectedStart)
    XCTAssertEqual(answer.recoveryWindow?.end, expectedStart.addingTimeInterval(1_800))
    XCTAssertTrue(answer.dialog.contains("30 minute recovery window"))
  }

  private func seedCapacity(_ score: Int) {
    defaults.set(true, forKey: "dashboardHasCapacity")
    defaults.set(score, forKey: "capacityScore")
    defaults.set("Above your usual", forKey: "capacityLabel")
    defaults.set("2026-09-19", forKey: "capacityDay")
  }

  private func seedSnapshot(publishedAt: TimeInterval) {
    defaults.set(1, forKey: "siriSchemaVersion")
    defaults.set("account-generation", forKey: "siriAccountGeneration")
    defaults.set(publishedAt * 1000, forKey: "siriPublishedAt")
    defaults.set("2026-09-19", forKey: "siriDataDay")
  }

  private func calendarEvent(
    _ title: String,
    start: Date,
    duration: TimeInterval,
    kind: String = "calendar",
    isAllDay: Bool = false
  ) -> [String: Any] {
    [
      "title": title,
      "startAt": start.timeIntervalSince1970 * 1_000,
      "endAt": start.addingTimeInterval(duration).timeIntervalSince1970 * 1_000,
      "isAllDay": isAllDay,
      "kind": kind,
    ]
  }

}
