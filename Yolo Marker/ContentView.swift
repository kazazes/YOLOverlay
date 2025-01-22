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
  @Published var previewImage: NSImage?
  @Published var detectedObjects: [DetectedObject] = []

  private var stream: SCStream?
  private var streamOutput: StreamOutput?
  private let yoloManager = YOLOModelManager()

  init() {
    streamOutput = StreamOutput()
    streamOutput?.frameHandler = { [weak self] image in
      guard let self = self else { return }
      Task { @MainActor in
        self.previewImage = image
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
      }
    }
  }

  func startCapture() async {
    let config = SCStreamConfiguration()
    config.width = 1920
    config.height = 1080
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
      ZStack {
        if let previewImage = captureManager.previewImage {
          Image(nsImage: previewImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          if !captureManager.detectedObjects.isEmpty {
            BoundingBoxView(
              detectedObjects: captureManager.detectedObjects,
              frameSize: previewImage.size
            )
          }
        } else {
          Text("No preview available")
            .font(.title)
        }
      }

      Button(captureManager.isRecording ? "Stop Recording" : "Start Recording") {
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
    }
    .frame(minWidth: 800, minHeight: 600)
  }
}

#Preview {
  ContentView()
}
