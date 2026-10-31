import SwiftUI
import WatchKit

/// Three taps. The score is the same 0–100 the Home check-in and the Mood
/// widget use; the phone turns it into the usual label.
struct CheckInView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var saved: String?

  private static let options: [(label: String, score: Int, color: Color)] = [
    ("High", 80, WatchPalette.capacity),
    ("Okay", 50, WatchPalette.demand),
    ("Low", 30, WatchPalette.stress),
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        if let saved {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 40))
            .foregroundStyle(Color(red: 0.36, green: 0.79, blue: 0.65))
            .padding(.top, 12)
          Text("\(saved) · noted").font(.headline)
        } else {
          Text("Energy right now?").font(.headline)
          ForEach(Array(Self.options.enumerated()), id: \.offset) { _, option in
            Button(option.label) { pick(option.label, option.score) }
              .tint(option.color)
          }
        }
      }
      .scenePadding(.horizontal)
    }
    .navigationTitle("Energy")
  }

  private func pick(_ label: String, _ score: Int) {
    saved = label
    WKInterfaceDevice.current().play(.success)
    WatchActions.send("checkIn", ["score": score])
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
  }
}
