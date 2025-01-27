import SwiftUI

struct BoundingBoxView: View {
  let detectedObjects: [DetectedObject]
  let frameSize: CGSize
  @ObservedObject private var settings = Settings.shared

  var body: some View {
    GeometryReader { geometry in
      ForEach(detectedObjects) { object in
        let rect = calculateRect(object.boundingBox, in: geometry.size)
        let color = getColorForClass(object.label)

        Rectangle()
          .strokeBorder(color, lineWidth: 2)
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
          .overlay(
            Text("\(object.label) (\(Int(object.confidence * 100))%)")
              .font(.caption)
              .foregroundColor(.white)
              .padding(4)
              .background(color)
              .cornerRadius(4)
              .position(x: rect.midX, y: rect.minY - 10)
          )
      }
    }
  }

  private func calculateRect(_ boundingBox: CGRect, in size: CGSize) -> CGRect {
    let x = boundingBox.origin.x * size.width
    let y = (1 - boundingBox.origin.y - boundingBox.height) * size.height
    let width = boundingBox.width * size.width
    let height = boundingBox.height * size.height
    return CGRect(x: x, y: y, width: width, height: height)
  }
  
  private func getColorForClass(_ className: String) -> Color {
    let colorString = settings.getColorForClass(className)
    // First try as a named color
    switch colorString.lowercased() {
    case "red": return .red
    case "blue": return .blue
    case "green": return .green
    case "yellow": return .yellow
    case "orange": return .orange
    case "purple": return .purple
    case "pink": return .pink
    case "teal": return .teal
    case "indigo": return .indigo
    case "mint": return .mint
    case "brown": return .brown
    case "cyan": return .cyan
    default:
      // If not a named color, try as hex
      if colorString.hasPrefix("#") {
        return Color(hex: colorString) ?? .red
      }
      return .red
    }
  }
}
