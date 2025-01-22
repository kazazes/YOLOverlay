import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI
import VideoToolbox
import Vision

@MainActor
class ScreenCaptureManager: ObservableObject {
  static let shared = ScreenCaptureManager()

  private var filter: SCContentFilter?
  private var stream: SCStream?
  private var streamOutput: StreamOutput?
  private var yoloManager = YOLOModelManager()
  private var overlayWindows: [OverlayWindowController] = []
  private var statsManager = StatsManager()
  private var isProcessingFrame = false
  private var cancellables = Set<AnyCancellable>()

  @Published var isRecording = false
  var stats: String { statsManager.getStatsString() }

  private init() {
    yoloManager.detectionHandler = { [weak self] results in
      self?.handleDetections(results)
    }

    // Observe FPS changes
    Settings.shared.$targetFPS
      .sink { [weak self] newFPS in
        print("🎯 FPS setting changed to \(newFPS)")
        Task { @MainActor in
          if self?.isRecording == true {
            print("🔄 Restarting capture to apply new frame rate...")
            await self?.stopCapture()
            await self?.startCapture()
          }
        }
      }
      .store(in: &cancellables)
  }

  func startCapture() async {
    guard !isRecording else {
      print("⚠️ Capture already in progress")
      return
    }

    do {
      print("🎥 Starting screen capture...")

      // Get screen content to capture
      let content = try await SCShareableContent.current
      guard let display = content.displays.first else {
        print("❌ No screens available")
        return
      }
      print("📺 Found primary display: \(display.width)x\(display.height)")

      // Find our overlay windows to exclude
      print("🪟 Available windows:")
      content.windows.forEach { window in
        print(
          "  • Title: \(window.title ?? "nil")\n    App: \(window.owningApplication?.applicationName ?? "")\n    Bundle: \(window.owningApplication?.bundleIdentifier ?? "")"
        )
      }

      // Create overlay window for each screen
      @Sendable func createOverlayWindows() async -> [OverlayWindowController] {
        let screens = NSScreen.screens
        return await withTaskGroup(of: OverlayWindowController.self) { group in
          for screen in screens {
            group.addTask {
              let controller = OverlayWindowController(screen: screen)
              await MainActor.run {
                controller.window?.orderFront(nil)
              }
              return controller
            }
          }

          var controllers: [OverlayWindowController] = []
          for await controller in group {
            controllers.append(controller)
          }
          return controllers
        }
      }

      overlayWindows = await createOverlayWindows()
      print("🎨 Created \(overlayWindows.count) overlay windows")

      // Wait a moment for windows to be created and registered
      print("⏳ Waiting for windows to register...")
      try await Task.sleep(for: .milliseconds(100))

      // Get updated window list and create filter
      let updatedContent = try await SCShareableContent.current
      let overlayWindowsToExclude = updatedContent.windows.filter { window in
        guard window.owningApplication?.bundleIdentifier == "com.kazazes.Yolo-Marker" else {
          return false
        }
        return window.title?.contains("Preferences") != true
      }
      print("🎯 Found \(overlayWindowsToExclude.count) windows to exclude")

      // Update the filter with the new window list
      filter = try SCContentFilter(
        display: display,
        excludingWindows: overlayWindowsToExclude
      )
      print("✅ Created screen capture filter")

      // Configure the stream
      let configuration = SCStreamConfiguration()
      configuration.width = Int(display.width)
      configuration.height = Int(display.height)
      configuration.minimumFrameInterval = CMTime(
        value: 1, timescale: Int32(Settings.shared.targetFPS))
      configuration.queueDepth = 5
      print(
        "⚙️ Configured stream: \(configuration.width)x\(configuration.height) @ \(Settings.shared.targetFPS)fps"
      )

      // Create stream output handler
      streamOutput = StreamOutput { [weak self] frame in
        self?.processFrame(frame)
      }

      // Create and start the stream
      guard let filter = filter, let streamOutput = streamOutput else { return }
      stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)
      try stream?.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: .global())
      try await stream?.startCapture()

      isRecording = true
      statsManager.recordFrame()

    } catch {
      print("Failed to start capture: \(error)")
    }
  }

  func stopCapture() async {
    print("🛑 Stopping screen capture...")
    do {
      try await stream?.stopCapture()
      stream = nil
      filter = nil

      // Remove overlay windows
      print("🧹 Removing \(overlayWindows.count) overlay windows")
      for controller in overlayWindows {
        await MainActor.run {
          controller.window?.orderOut(nil)
        }
      }
      overlayWindows.removeAll()

      isRecording = false
      print("✅ Screen capture stopped successfully")

    } catch {
      print("❌ Failed to stop capture: \(error)")
    }
  }

  private func processFrame(_ frame: CMSampleBuffer) {
    // Skip if we're still processing the previous frame
    guard !isProcessingFrame else {
      statsManager.recordFrame()  // Record as dropped frame
      if statsManager.droppedFrames % 100 == 0 {  // Log every 100th drop
        print("⚠️ Dropped frame - total dropped: \(statsManager.droppedFrames)")
      }
      return
    }

    guard let imageBuffer = frame.imageBuffer else { return }

    isProcessingFrame = true

    // Create CGImage from buffer
    var cgImage: CGImage?
    VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)

    if let cgImage = cgImage {
      // Perform YOLO detection
      yoloManager.detect(in: cgImage)
    }
  }

  private func handleDetections(_ results: [VNRecognizedObjectObservation]) {
    defer { isProcessingFrame = false }  // Reset processing flag when done

    // Convert Vision observations to our DetectedObject type
    let detectedObjects = results.compactMap { observation -> DetectedObject? in
      guard let label = observation.labels.first else { return nil }
      return DetectedObject(
        label: label.identifier,
        confidence: label.confidence,
        boundingBox: observation.boundingBox
      )
    }

    // Update overlay windows on main thread
    Task { @MainActor in
      self.overlayWindows.forEach { controller in
        controller.updateDetections(detectedObjects)
      }
    }

    // Update stats
    statsManager.updateDetections(detectedObjects)
  }
}

// MARK: - Stream Output Handler
private class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
  let frameHandler: (CMSampleBuffer) -> Void

  init(frameHandler: @escaping (CMSampleBuffer) -> Void) {
    self.frameHandler = frameHandler
    super.init()
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    if type == .screen {
      frameHandler(sampleBuffer)
    }
  }

  // Required SCStreamDelegate methods
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    print("Stream stopped with error: \(error)")
  }
}
