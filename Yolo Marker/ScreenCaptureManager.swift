import AppKit
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

  @Published var isRecording = false
  var stats: String { statsManager.getStatsString() }

  private init() {
    yoloManager.detectionHandler = { [weak self] results in
      self?.handleDetections(results)
    }
  }

  func startCapture() async {
    do {
      // Get screen content to capture
      let content = try await SCShareableContent.current
      guard let mainScreen = content.displays.first else {
        print("No screens available")
        return
      }

      // Create a filter for the screen
      filter = .init(display: mainScreen, excludingWindows: [])

      // Create stream configuration
      let config = SCStreamConfiguration()
      config.width = Int(mainScreen.width)
      config.height = Int(mainScreen.height)
      config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(Settings.shared.targetFPS))
      config.queueDepth = 5

      // Create stream output handler
      streamOutput = StreamOutput { [weak self] frame in
        self?.processFrame(frame)
      }

      // Create and start the stream
      guard let filter = filter else { return }
      stream = SCStream(filter: filter, configuration: config, delegate: nil)

      try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global())
      try await stream?.startCapture()

      // Create overlay window for each screen
      let controllers = await withTaskGroup(of: OverlayWindowController.self) { group in
        for screen in NSScreen.screens {
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

      overlayWindows = controllers
      isRecording = true
      statsManager.recordFrame()  // Start recording frames

    } catch {
      print("Failed to start capture: \(error)")
    }
  }

  func stopCapture() async {
    do {
      try await stream?.stopCapture()
      stream = nil
      filter = nil

      // Remove overlay windows
      for controller in overlayWindows {
        await MainActor.run {
          controller.window?.orderOut(nil)
        }
      }
      overlayWindows.removeAll()

      isRecording = false

    } catch {
      print("Failed to stop capture: \(error)")
    }
  }

  private func processFrame(_ frame: CMSampleBuffer) {
    guard let imageBuffer = frame.imageBuffer else { return }

    // Record frame in stats
    statsManager.recordFrame()

    // Create CGImage from buffer
    var cgImage: CGImage?
    VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil as CFDictionary?, imageOut: &cgImage)

    if let cgImage = cgImage {
      // Perform YOLO detection
      yoloManager.detect(in: cgImage)
    }
  }

  private func handleDetections(_ results: [VNRecognizedObjectObservation]) {
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
private class StreamOutput: NSObject, SCStreamOutput {
  let frameHandler: (CMSampleBuffer) -> Void

  init(frameHandler: @escaping (CMSampleBuffer) -> Void) {
    self.frameHandler = frameHandler
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    if type == .screen {
      frameHandler(sampleBuffer)
    }
  }
}
