//
//  ContentView.swift
//  Yolo Marker
//
//  Created by p on 1/22/25.
//

import CoreGraphics
import ScreenCaptureKit
import SwiftUI
import Vision

@MainActor
class ScreenCaptureManager: ObservableObject {
  @Published var isRecording = false
  @Published var detectedObjects: [DetectedObject] = []

  private var stream: SCStream?
  private var streamOutput: StreamOutput?
  private let yoloManager = YOLOModelManager()
  private var overlayController: OverlayWindowController?

  init() {
    setupOverlayWindow()
    setupModel()
  }

  private func setupOverlayWindow() {
    guard let screen = NSScreen.main else { return }
    overlayController = OverlayWindowController(screen: screen)
    overlayController?.window?.orderFront(nil)
  }

  private func setupModel() {
    streamOutput = StreamOutput()
    streamOutput?.frameHandler = { [weak self] image in
      guard let self = self else { return }
      Task { @MainActor in
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
          self.yoloManager.detect(in: cgImage)
        }
      }
    }

    yoloManager.detectionHandler = { [weak self] observations in
      let objects = observations.map { observation in
        DetectedObject(
          label: observation.labels.first?.identifier ?? "Unknown",
          confidence: observation.confidence,
          boundingBox: observation.boundingBox
        )
      }
      Task { @MainActor in
        self?.detectedObjects = objects
        self?.overlayController?.updateDetections(objects)
      }
    }
  }

  func startCapture() async {
    let config = SCStreamConfiguration()
    config.width = Int(NSScreen.main?.frame.width ?? 1920)
    config.height = Int(NSScreen.main?.frame.height ?? 1080)
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

    do {
      // Get the main display
      guard let display = await SCShareableContent.current.displays.first else {
        print("No displays available")
        return
      }

      let filter = SCContentFilter(display: display, excludingWindows: [])
      stream = try SCStream(filter: filter, configuration: config, delegate: nil)

      try await stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .main)
      try await stream?.startCapture()

      isRecording = true
    } catch {
      print("Failed to start capture: \(error)")
    }
  }

  func stopCapture() async {
    do {
      try await stream?.stopCapture()
      isRecording = false
      detectedObjects = []
      overlayController?.updateDetections([])
    } catch {
      print("Failed to stop capture: \(error)")
    }
  }
}

class StreamOutput: NSObject, SCStreamOutput {
  var frameHandler: ((NSImage) -> Void)?

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen,
      let imageBuffer = sampleBuffer.imageBuffer
    else { return }

    let ciImage = CIImage(cvImageBuffer: imageBuffer)
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
    let image = NSImage(
      cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

    frameHandler?(image)
  }
}

struct ContentView: View {
  @StateObject private var captureManager = ScreenCaptureManager()

  var body: some View {
    VStack {
      Button(captureManager.isRecording ? "Stop Detection" : "Start Detection") {
        Task {
          if captureManager.isRecording {
            await captureManager.stopCapture()
          } else {
            await captureManager.startCapture()
          }
        }
      }
      .buttonStyle(.borderedProminent)
      .padding()

      Text("Detected Objects: \(captureManager.detectedObjects.count)")
        .font(.caption)
    }
    .frame(width: 200, height: 100)
  }
}

#Preview {
  ContentView()
}
