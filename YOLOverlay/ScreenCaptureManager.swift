import AppKit
import Combine
import CoreML
import ScreenCaptureKit
import SwiftUI
import VideoToolbox
import Vision

@MainActor
class ScreenCaptureManager: NSObject, ObservableObject {
  static let shared = ScreenCaptureManager()

  // Shared CIContext for hardware-accelerated image processing
  private static let ciContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
  ])

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
    do {
      let content = try await SCShareableContent.current

      // Get the main display
      guard let display = content.displays.first else {
        LogManager.shared.error("No screens available")
        handleCaptureError(.noScreensAvailable)
        return
      }

      LogManager.shared.info("Found primary display: \(display.width)x\(display.height)")

      // Create overlay windows
      overlayWindows = await createOverlayWindows()
      LogManager.shared.info("Created \(overlayWindows.count) overlay windows")

      // Wait longer for windows to register and become visible
      LogManager.shared.debug("Waiting for windows to register...")
      try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

      // Get updated window list and create filter
      let updatedContent = try await SCShareableContent.current

      // Get our window IDs for more reliable filtering
      let overlayWindowIDs = Set(overlayWindows.compactMap { $0.window?.windowNumber })
      LogManager.shared.debug("Overlay window IDs: \(overlayWindowIDs)")

      let overlayWindowsToExclude = updatedContent.windows.filter { window in
        // First check bundle identifier
        guard window.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier else {
          return false
        }

        // Exclude preference windows
        guard window.title?.contains("Preferences") != true else {
          return false
        }

        // Then verify it's one of our overlay windows by ID
        return overlayWindowIDs.contains(Int(window.windowID))
      }

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

      // Create stream output handler and store reference
      streamOutput = StreamOutput { [weak self] buffer in
        self?.processFrame(buffer)
      }

      // Create and configure stream
      stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)

      // Add stream output
      if let streamOutput = streamOutput {
        try stream?.addStreamOutput(
          streamOutput, type: .screen, sampleHandlerQueue: streamQueue)
      }
      try await stream?.startCapture()

      isRecording = true

    } catch let error as SCStreamError {
      switch error.code {
      case .userDeclined:
        LogManager.shared.error("Screen recording permission denied by user")
        handleCaptureError(.permissionDenied)
      case .missingEntitlements:
        LogManager.shared.error("Screen recording permission not available - missing entitlements")
        handleCaptureError(.permissionDenied)
      case .failedToStart:
        LogManager.shared.error("Failed to start screen capture")
        handleCaptureError(.unknown(error))
      default:
        LogManager.shared.error("Screen capture error: \(error.localizedDescription)")
        handleCaptureError(.unknown(error))
      }
      // Clean up on error
      stream = nil
      streamOutput = nil
    } catch {
      LogManager.shared.error("Failed to start capture", error: error)
      handleCaptureError(.unknown(error))
      // Clean up on error
      stream = nil
      streamOutput = nil
    }
  }

  func stopCapture() async {
    LogManager.shared.info("Stopping screen capture...")

    do {
      if let stream = stream, let streamOutput = streamOutput {
        try await stream.stopCapture()
        // Remove stream output before nulling references
        try stream.removeStreamOutput(streamOutput, type: .screen)
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
      statsManager.incrementDroppedFrames()
      return
    }

    guard let imageBuffer = frame.imageBuffer else { return }
    isProcessingFrame = true

    // Use CIContext for hardware-accelerated image conversion
    let ciImage = CIImage(cvImageBuffer: imageBuffer)
    let context = ScreenCaptureManager.ciContext  // Use shared context for better performance

    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      isProcessingFrame = false
      return
    }

    // Perform detection/segmentation
    yoloManager.detect(in: cgImage)
  }

  private func handleDetections(_ observations: [VNRecognizedObjectObservation]) {
    defer { isProcessingFrame = false }  // Reset processing flag when done

    // Update stats
    statsManager.incrementProcessedFrames()

    // Update each overlay window on main thread
    Task { @MainActor in
      for window in overlayWindows {
        if let segObs = observations.first as? SegmentationObservation {
          // Handle segmentation
          if let mask = segObs.segmentationMask,
            let labels = segObs.classLabels
          {
            // Get the current screen frame
            guard let screenFrame = window.window?.screen?.frame else {
              LogManager.shared.error("Could not get screen frame for window")
              continue
            }

            LogManager.shared.info("Updating segmentation with screen frame: \(screenFrame)")
            window.updateSegmentation(
              mask: mask,
              classColors: Settings.shared.classColors,
              classLabels: labels,
              opacity: Settings.shared.segmentationOpacity,
              captureFrame: screenFrame  // Pass the screen frame
            )
          }
        } else {
          // Handle regular detections
          window.updateDetections(observations)
        }
      }
    }
  }

  private func handleSegmentationResults(_ results: [VNRecognizedObjectObservation]) {
    // For segmentation models, try to get the segmentation mask
    if Settings.shared.isSegmentationModel {
      guard let observation = results.first as? SegmentationObservation,
        let mask = observation.segmentationMask,
        let classes = observation.classLabels
      else {
        LogManager.shared.error("Failed to get segmentation mask from results")
        return
      }

      LogManager.shared.info(
        "Got segmentation mask with shape: \(mask.shape) and classes: \(classes)")

      // Update overlay windows with segmentation data
      for window in overlayWindows {
        window.updateSegmentation(
          mask: mask,
          classColors: Settings.shared.classColors,
          classLabels: classes,
          opacity: Settings.shared.segmentationOpacity
        )
      }
      return
    }
  }

  private func handleDroppedFrame() {
    statsManager.incrementDroppedFrames()
    LogManager.shared.notice("Dropped frame - total dropped: \(statsManager.droppedFrames)")
  }

  // MARK: - Error Handling
  enum CaptureError {
    case permissionDenied
    case noScreensAvailable
    case unknown(Error)
  }

  private func handleCaptureError(_ error: CaptureError) {
    Task { @MainActor in
      isRecording = false

      let alert = NSAlert()
      switch error {
      case .permissionDenied:
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
          YOLOverlay needs screen recording permission to detect objects.

          To grant permission:
          1. Open System Settings
          2. Go to Privacy & Security > Screen Recording
          3. Enable YOLOverlay
          4. Restart the app
          """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
          NSWorkspace.shared.open(
            URL(
              string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }

      case .noScreensAvailable:
        alert.messageText = "No Screens Available"
        alert.informativeText = "YOLOverlay could not find any displays to capture from."
        alert.addButton(withTitle: "OK")
        alert.runModal()

      case .unknown(let underlyingError):
        alert.messageText = "Capture Error"
        alert.informativeText =
          "An error occurred while starting screen capture: \(underlyingError.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    }
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
