import AppKit
import SwiftUI

class OverlayWindow: NSWindow {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    // Make the window transparent and floating
    self.backgroundColor = .clear
    self.isOpaque = false
    self.hasShadow = false

    // Make it visible on all spaces
    self.collectionBehavior = [.canJoinAllSpaces, .stationary]

    // Keep it on top
    self.level = .floating

    // Allow click-through
    self.ignoresMouseEvents = true
  }
}

struct OverlayView: View {
  let detectedObjects: [DetectedObject]
  let screenFrame: CGRect
  @ObservedObject private var settings = Settings.shared

  private func getColor(_ name: String) -> Color {
    switch name.lowercased() {
    case "red": return .red
    case "blue": return .blue
    case "green": return .green
    case "yellow": return .yellow
    case "orange": return .orange
    case "purple": return .purple
    default: return .red
    }
  }

  var body: some View {
    ZStack {
      // Transparent background
      Color.clear

      // Draw bounding boxes
      ForEach(detectedObjects.filter { $0.confidence >= settings.confidenceThreshold }) { object in
        let rect = calculateScreenRect(object.boundingBox)
        let color = getColor(settings.boundingBoxColor)

        ZStack {
          // Bounding box
          Rectangle()
            .stroke(color, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

          // Label (if enabled)
          if settings.showLabels {
            Text("\(object.label) (\(Int(object.confidence * 100))%)")
              .font(.system(size: 12, weight: .bold))
              .foregroundColor(.white)
              .padding(4)
              .background(color)
              .cornerRadius(4)
              .position(x: rect.midX, y: rect.minY - 10)
          }
        }
        .opacity(settings.boundingBoxOpacity)
      }
    }
    .frame(width: screenFrame.width, height: screenFrame.height)
  }

  private func calculateScreenRect(_ normalizedRect: CGRect) -> CGRect {
    let x = normalizedRect.origin.x * screenFrame.width
    let y = (1 - normalizedRect.origin.y - normalizedRect.height) * screenFrame.height
    let width = normalizedRect.width * screenFrame.width
    let height = normalizedRect.height * screenFrame.height
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

class OverlayWindowController: NSWindowController {
  convenience init(screen: NSScreen) {
    let window = OverlayWindow(contentRect: screen.frame)
    self.init(window: window)
  }

  func updateDetections(_ detections: [DetectedObject]) {
    guard let window = self.window,
      let screen = window.screen
    else { return }

    let hostingView = NSHostingView(
      rootView: OverlayView(
        detectedObjects: detections,
        screenFrame: screen.frame
      )
    )
    window.contentView = hostingView
  }
}
