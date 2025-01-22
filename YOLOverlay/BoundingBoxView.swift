import SwiftUI

struct BoundingBoxView: View {
  let detectedObjects: [DetectedObject]
  let frameSize: CGSize

  var body: some View {
    GeometryReader { geometry in
      ForEach(detectedObjects) { object in
        let rect = calculateRect(object.boundingBox, in: geometry.size)

        Rectangle()
          .strokeBorder(Color.red, lineWidth: 2)
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
          .overlay(
            Text("\(object.label) (\(Int(object.confidence * 100))%)")
              .font(.caption)
              .foregroundColor(.white)
              .padding(4)
              .background(Color.red)
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
}
