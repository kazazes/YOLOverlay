import AppKit
import CoreML
import SwiftUI
import Vision

class OverlayWindow: NSWindow {
  init(screen: NSScreen) {
    super.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)

    self.level = .floating
    self.backgroundColor = .clear
    self.isOpaque = false
    self.hasShadow = false
    self.ignoresMouseEvents = true
    self.collectionBehavior = [.canJoinAllSpaces, .stationary]

    // Set window frame to match screen
    self.setFrame(screen.frame, display: true)
  }
}

// Simple data structure to hold overlay state
struct OverlayState {
  var detections: [VNRecognizedObjectObservation] = []
  var segmentationImage: CGImage?
  var segmentationOpacity: Double = 1.0
  var captureFrame: CGRect = .zero  // Add capture frame information
}

struct OverlayView: View {
  let state: OverlayState

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        // Segmentation layer
        if let segImage = state.segmentationImage {
          Image(nsImage: NSImage(cgImage: segImage, size: NSSize(width: segImage.width, height: segImage.height)))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(
              width: state.captureFrame.width,
              height: state.captureFrame.height
            )
            .position(
              x: state.captureFrame.midX,
              y: state.captureFrame.midY
            )
            .opacity(state.segmentationOpacity)
            .animation(.easeInOut(duration: 0.2), value: state.segmentationOpacity)
        }

        // Detection boxes layer
        BoundingBoxView(
          detectedObjects: state.detections.compactMap { observation in
            guard let label = observation.labels.first else { return nil }
            return DetectedObject(
              label: label.identifier,
              confidence: label.confidence,
              boundingBox: observation.boundingBox
            )
          },
          frameSize: geometry.size
        )
      }
    }
  }
}

class OverlayWindowController: NSWindowController {
  private var hostingView: NSHostingView<OverlayView>?
  private var segmentationRenderer: SegmentationRenderer?
  private var state = OverlayState()

  init(screen: NSScreen) {
    self.segmentationRenderer = SegmentationRenderer()
    super.init(window: nil)

    let window = OverlayWindow(screen: screen)
    self.window = window
    
    // Set initial capture frame
    state.captureFrame = screen.frame
    
    let hostingView = NSHostingView(rootView: OverlayView(state: state))
    window.contentView = hostingView
    self.hostingView = hostingView

    window.orderFront(nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateDetections(_ detections: [VNRecognizedObjectObservation]) {
    guard let hostingView = self.hostingView else { return }
    state.detections = detections
    hostingView.rootView = OverlayView(state: state)
  }

  func updateSegmentation(
    mask: MLMultiArray, 
    classColors: [String: String], 
    classLabels: [String], 
    opacity: Double,
    captureFrame: CGRect? = nil  // Add optional capture frame parameter
  ) {
    guard let hostingView = self.hostingView,
      let segmentationRenderer = self.segmentationRenderer
    else { return }

    LogManager.shared.info("Updating segmentation with mask shape: \(mask.shape)")
    LogManager.shared.info("Class colors: \(classColors)")
    LogManager.shared.info("Class labels: \(classLabels)")
    if let frame = captureFrame {
      LogManager.shared.info("Capture frame: \(frame)")
    }

    // Process segmentation on background queue
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      // Convert colors to RGB space
      let processedColors = classColors.mapValues { colorString -> String in
        guard let color = NSColor(named: colorString) ?? NSColor(hexString: colorString),
          let rgbColor = color.usingColorSpace(.deviceRGB)
        else {
          LogManager.shared.error("Failed to convert color: \(colorString)")
          return "#FF0000"  // Fallback to red
        }

        let red = Int(rgbColor.redComponent * 255)
        let green = Int(rgbColor.greenComponent * 255)
        let blue = Int(rgbColor.blueComponent * 255)
        let hexColor = String(format: "#%02X%02X%02X", red, green, blue)
        LogManager.shared.info("Converted \(colorString) to \(hexColor)")
        return hexColor
      }

      // Render mask
      if let renderedMask = segmentationRenderer.renderMask(
        mask: mask,
        classColors: processedColors,
        classLabels: classLabels,
        opacity: Float(opacity)
      ) {
        LogManager.shared.info("Successfully rendered segmentation mask")
        DispatchQueue.main.async {
          self.state.segmentationImage = renderedMask
          self.state.segmentationOpacity = opacity
          if let frame = captureFrame {
            self.state.captureFrame = frame
          }
          hostingView.rootView = OverlayView(state: self.state)
          LogManager.shared.info("Updated overlay view with new segmentation")
        }
      } else {
        LogManager.shared.error("Failed to render segmentation mask")
      }
    }
  }
}

// Helper extension for color parsing
extension NSColor {
  convenience init?(hexString: String) {
    let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a: UInt64
    let r: UInt64
    let g: UInt64
    let b: UInt64
    switch hex.count {
    case 3:  // RGB (12-bit)
      (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6:  // RGB (24-bit)
      (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8:  // ARGB (32-bit)
      (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
      return nil
    }
    self.init(
      deviceRed: CGFloat(r) / 255,
      green: CGFloat(g) / 255,
      blue: CGFloat(b) / 255,
      alpha: CGFloat(a) / 255
    )
  }
}
