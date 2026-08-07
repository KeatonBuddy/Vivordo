import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var exerciseCount: Int
    var status: String
  }

  var startedAt: Date
}
