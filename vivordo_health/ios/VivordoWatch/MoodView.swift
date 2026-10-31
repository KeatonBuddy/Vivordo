import SwiftUI
import WatchKit

/// The Mood widget's five taps, on the wrist. The score is the same 0–100
/// the Home check-in and the widget use; the phone saves it as a check-in.
struct MoodView: View {
  /// Called once the tap is noted; the caller pops back to Today.
  let onDone: () -> Void
  @State private var saved: String?

  private static let moods: [(label: String, score: Int, color: Color)] = [
    ("Great", 95, Color(red: 0.13, green: 0.77, blue: 0.37)),
    ("Good", 75, Color(red: 0.20, green: 0.78, blue: 0.35)),
    ("Okay", 50, Color(red: 1.00, green: 0.58, blue: 0.00)),
    ("Down", 30, Color(red: 0.48, green: 0.43, blue: 0.96)),
    ("Awful", 10, Color(red: 0.94, green: 0.27, blue: 0.27)),
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: 6) {
        if let saved {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 40))
            .foregroundStyle(Color(red: 0.36, green: 0.79, blue: 0.65))
            .padding(.top, 12)
          Text("\(saved) · noted").font(.headline)
        } else {
          Text("How are you?").font(.headline)
          ForEach(Array(Self.moods.enumerated()), id: \.offset) { _, mood in
            Button(mood.label) { pick(mood.label, mood.score) }
              .tint(mood.color)
          }
        }
      }
      .scenePadding(.horizontal)
    }
    .navigationTitle("Mood")
  }

  private func pick(_ label: String, _ score: Int) {
    saved = label
    WKInterfaceDevice.current().play(.success)
    WatchActions.send("checkIn", ["score": score])
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onDone() }
  }
}
