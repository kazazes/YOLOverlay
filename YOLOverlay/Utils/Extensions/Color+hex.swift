import SwiftUI

extension Color {
  init(hex: String) {
    let hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0

    // If scanning fails or length is invalid, use red as default
    guard hexSanitized.count == 6 && Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
      self = .red
      return
    }

    let r = Double((rgb & 0xFF0000) >> 16) / 255.0
    let g = Double((rgb & 0x00FF00) >> 8) / 255.0
    let b = Double(rgb & 0x0000FF) / 255.0

    self.init(red: r, green: g, blue: b)
  }
}
