import AppKit
import SwiftUI

class OverlayWindow: NSWindow {
  init(screen: NSScreen) {
    super.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)

    self.level = .floating
    self.backgroundColor = .clear
    self.isOpaque = false
    self.hasShadow = false
    self.ignoresMouseEvents = true
    self.collectionBehavior = [.canJoinAllSpaces, .stationary]
  }
}

struct OverlayView: View {
  let detectedObjects: [DetectedObject]
  let screenFrame: CGRect
  @ObservedObject private var settings = Settings.shared
  @ObservedObject private var tracker: ObjectTracker

  init(detectedObjects: [DetectedObject], screenFrame: CGRect, tracker: ObjectTracker) {
    self.detectedObjects = detectedObjects
    self.screenFrame = screenFrame
    self.tracker = tracker
  }

  private func getColor(_ name: String) -> Color {
    // If the string starts with #, treat it as a hex color
    if name.starts(with: "#") {
      return Color(hex: name)
    }

    // Otherwise, treat it as a named color
    switch name.lowercased() {
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
    default: return .red
    }
  }

  var body: some View {
    ZStack {
      // Transparent background
      Color.clear

      // Draw bounding boxes
      ForEach(tracker.trackedObjects) { object in
        let rect = calculateScreenRect(object.rect)
        let color = getColor(settings.getColorForClass(object.label))
          .opacity(object.alpha * settings.boundingBoxOpacity)

        ZStack {
          // Bounding box
          Rectangle()
            .stroke(color, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

          // Label (if enabled)
          if settings.showLabels {
            // Find best label position that doesn't overlap with other boxes
            let labelPosition = findBestLabelPosition(
              for: rect, avoiding: tracker.trackedObjects.map { calculateScreenRect($0.rect) })

            Text("\(object.label) (\(Int(object.confidence * 100))%)")
              .font(.system(size: 12, weight: .bold))
              .foregroundColor(.white)
              .padding(4)
              .background(color)
              .cornerRadius(4)
              .position(x: labelPosition.x, y: labelPosition.y)
          }
        }
      }
    }
    .onAppear {
      tracker.update(with: detectedObjects)
    }
    .onChange(of: detectedObjects) { _, newDetections in
      tracker.update(with: newDetections)
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

  private func findBestLabelPosition(for rect: CGRect, avoiding otherRects: [CGRect]) -> CGPoint {
    // Possible positions to try (in order of preference)
    let positions: [(CGFloat, CGFloat)] = [
      (rect.midX, rect.minY - 10),  // Above center
      (rect.midX, rect.maxY + 10),  // Below center
      (rect.minX - 10, rect.midY),  // Left center
      (rect.maxX + 10, rect.midY),  // Right center
      (rect.minX, rect.minY - 10),  // Above left
      (rect.maxX, rect.minY - 10),  // Above right
      (rect.minX, rect.maxY + 10),  // Below left
      (rect.maxX, rect.maxY + 10),  // Below right
    ]

    // Approximate label size
    let labelSize = CGSize(width: 100, height: 20)

    // Try each position until we find one that doesn't overlap
    for (x, y) in positions {
      let labelRect = CGRect(
        x: x - labelSize.width / 2,
        y: y - labelSize.height / 2,
        width: labelSize.width,
        height: labelSize.height
      )

      // Check if this position overlaps with any other bounding boxes
      let hasOverlap = otherRects.contains { otherRect in
        labelRect.intersects(otherRect)
      }

      if !hasOverlap {
        return CGPoint(x: x, y: y)
      }
    }

    // If all positions overlap, return the default position (above center)
    return CGPoint(x: rect.midX, y: rect.minY - 10)
  }
}

class OverlayWindowController: NSWindowController {
  private var hostingView: NSHostingView<OverlayView>?
  private let tracker = ObjectTracker()

  init(screen: NSScreen) {
    let window = OverlayWindow(screen: screen)
    super.init(window: window)

    // Create initial hosting view with empty detections
    let hostingView = NSHostingView(
      rootView: OverlayView(
        detectedObjects: [],
        screenFrame: screen.frame,
        tracker: tracker
      )
    )
    window.contentView = hostingView
    self.hostingView = hostingView

    // Show the window immediately
    window.orderFront(nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateDetections(_ detections: [DetectedObject]) {
    guard
      let window = window,
      let screen = window.screen,
      let hostingView = self.hostingView
    else { return }

    // Update the root view instead of creating a new hosting view
    hostingView.rootView = OverlayView(
      detectedObjects: detections,
      screenFrame: screen.frame,
      tracker: tracker
    )
  }
}
