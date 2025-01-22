import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI
import VideoToolbox
import Vision

@MainActor
class ScreenCaptureManager: NSObject, ObservableObject {
  static let shared = ScreenCaptureManager()

  private var filter: SCContentFilter?
  private var stream: SCStream?
  private var streamOutput: StreamOutput?
  private var yoloManager = YOLOModelManager()
  private var overlayWindows: [OverlayWindowController] = []
  private var statsManager = StatsManager()
  private var isProcessingFrame = false
  private var cancellables = Set<AnyCancellable>()
  private let streamQueue = DispatchQueue(label: "com.kazazes.Yolo-Marker.stream")

  @Published var isRecording = false
  var stats: String { statsManager.getStatsString() }

  private override init() {
    super.init()
    yoloManager.detectionHandler = { [weak self] results in
      self?.handleDetections(results)
    }

    // Observe FPS changes
    Settings.shared.$targetFPS
      .sink { [weak self] newFPS in
        self?.handleFPSChange(newFPS)
      }
      .store(in: &cancellables)
  }

  private func handleFPSChange(_ newFPS: Double) {
    LogManager.shared.info("FPS setting changed to \(newFPS)")
    if isRecording {
      LogManager.shared.notice("Restarting capture to apply new frame rate...")
      Task {
        await stopCapture()
        await startCapture()
      }
    }
  }

  func startCapture() async {
    guard !isRecording else {
      LogManager.shared.notice("Capture already in progress")
      return
    }

    LogManager.shared.info("Starting screen capture...")

    // Get shareable content
    guard let content = try? await SCShareableContent.current else {
      LogManager.shared.error("Failed to get shareable content")
      return
    }

    // Get the main display
    guard let display = content.displays.first else {
      LogManager.shared.error("No screens available")
      return
    }

    LogManager.shared.info("Found primary display: \(display.width)x\(display.height)")

    // Create overlay windows
    overlayWindows = await createOverlayWindows()
    LogManager.shared.info("Created \(overlayWindows.count) overlay windows")

    // Wait for windows to register
    LogManager.shared.debug("Waiting for windows to register...")
    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

    // Get updated window list and create filter
    let updatedContent = try? await SCShareableContent.current
    let overlayWindowsToExclude =
      updatedContent?.windows.filter { window in
        // First check bundle identifier
        guard window.owningApplication?.bundleIdentifier == "com.kazazes.Yolo-Marker" else {
          return false
        }

        // Exclude preference windows
        guard window.title?.contains("Preferences") != true else {
          return false
        }

        // Then verify it's one of our overlay windows
        return overlayWindows.contains { controller in
          if let windowNumber = controller.window?.windowNumber {
            return windowNumber == window.windowID
          }
          return false
        }
      } ?? []
    LogManager.shared.debug("Found \(overlayWindowsToExclude.count) windows to exclude")

    // Create filter
    let filter = SCContentFilter(
      display: display,
      excludingWindows: overlayWindowsToExclude
    )
    LogManager.shared.debug("Created screen capture filter")

    // Configure stream
    let configuration = SCStreamConfiguration()
    configuration.width = Int(display.width)
    configuration.height = Int(display.height)
    configuration.minimumFrameInterval = CMTime(
      value: 1, timescale: CMTimeScale(Settings.shared.targetFPS))
    configuration.queueDepth = 5
    configuration.showsCursor = false  // Exclude mouse pointer from capture
    LogManager.shared.debug(
      """
      Stream configuration:
      - Resolution: \(configuration.width)x\(configuration.height)
      - FPS: \(Settings.shared.targetFPS)
      - Queue Depth: \(configuration.queueDepth)
      """)

    do {
      // Create stream output handler and store reference
      streamOutput = StreamOutput { [weak self] buffer in
        self?.processFrame(buffer)
      }

      // Create and configure stream
      stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)

      // Add stream output
      if let streamOutput = streamOutput {
        try await stream?.addStreamOutput(
          streamOutput, type: .screen, sampleHandlerQueue: streamQueue)
      }
      try await stream?.startCapture()

      isRecording = true
    } catch {
      LogManager.shared.error("Failed to start capture", error: error)
      // Clean up on error
      stream = nil
      streamOutput = nil
      isRecording = false
    }
  }

  func stopCapture() async {
    LogManager.shared.info("Stopping screen capture...")

    do {
      if let stream = stream, let streamOutput = streamOutput {
        try await stream.stopCapture()
        // Remove stream output before nulling references
        try await stream.removeStreamOutput(streamOutput, type: .screen)
        self.stream = nil
        self.streamOutput = nil
      }

      LogManager.shared.debug("Removing \(overlayWindows.count) overlay windows")
      for controller in overlayWindows {
        await MainActor.run {
          controller.window?.orderOut(nil)
        }
      }
      overlayWindows.removeAll()

      isRecording = false
      LogManager.shared.info("Screen capture stopped successfully")
    } catch {
      LogManager.shared.error("Failed to stop capture", error: error)
    }
  }

  private func createOverlayWindows() async -> [OverlayWindowController] {
    return await withTaskGroup(of: OverlayWindowController.self) { group in
      let screens = NSScreen.screens
      for screen in screens {
        group.addTask { @MainActor in
          let controller = OverlayWindowController(screen: screen)
          controller.window?.orderFront(nil)
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

  private func processFrame(_ frame: CMSampleBuffer) {
    // Skip if we're still processing the previous frame
    guard !isProcessingFrame else {
      statsManager.incrementDroppedFrames()  // Record as dropped frame
      handleDroppedFrame()
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

  private func handleDroppedFrame() {
    statsManager.incrementDroppedFrames()
    LogManager.shared.notice("Dropped frame - total dropped: \(statsManager.droppedFrames)")
  }
}

// MARK: - Stream Output Handler
private class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
  private let frameHandler: (CMSampleBuffer) -> Void

  init(frameHandler: @escaping (CMSampleBuffer) -> Void) {
    self.frameHandler = frameHandler
    super.init()
  }

  nonisolated func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    if type == .screen {
      frameHandler(sampleBuffer)
    }
  }

  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    LogManager.shared.error("Stream stopped with error", error: error)
    Task { @MainActor in
      ScreenCaptureManager.shared.isRecording = false
    }
  }
}
