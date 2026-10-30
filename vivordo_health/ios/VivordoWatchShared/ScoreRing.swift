import SwiftUI

/// Vivordo's colours on the wrist. Always on black, so these are the
/// dark-mode shades the phone's widgets use.
enum WatchPalette {
  static let capacity = Color(red: 0.69, green: 0.66, blue: 0.93)
  static let demand = Color(red: 0.50, green: 0.65, blue: 1.00)
  static let stress = Color(red: 1.00, green: 0.54, blue: 0.51)
  static let tile = Color(white: 0.11)
  static let secondary = Color(white: 0.71)
}

/// A 0–100 ring with the number inside; the Capacity ring on Today and in
/// the rectangular complication.
struct ScoreRing: View {
  let value: Int?
  let color: Color
  var lineWidth: CGFloat = 10

  var body: some View {
    ZStack {
      Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: CGFloat(min(max(value ?? 0, 0), 100)) / 100)
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Text(value.map(String.init) ?? "–")
        .font(.system(.title2, design: .rounded).weight(.bold))
        .minimumScaleFactor(0.5)
        .padding(lineWidth + 4)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(value.map { "\($0) of 100" } ?? "No score yet")
  }
}
