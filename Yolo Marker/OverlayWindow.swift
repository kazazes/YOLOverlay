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

  var body: some View {
    ZStack {
      // Transparent background
      Color.clear

      // Draw bounding boxes
      ForEach(detectedObjects) { object in
        let rect = calculateScreenRect(object.boundingBox)

        Rectangle()
          .strokeBorder(Color.red, lineWidth: 2)
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
          .overlay(
            Text("\(object.label) (\(Int(object.confidence * 100))%)")
              .font(.system(size: 12, weight: .bold))
              .foregroundColor(.white)
              .padding(4)
              .background(Color.red)
              .cornerRadius(4)
              .position(x: rect.midX, y: rect.minY - 10)
          )
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
