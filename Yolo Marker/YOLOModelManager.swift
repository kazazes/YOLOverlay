import CoreML
import Vision

class YOLOModelManager {
  private var visionModel: VNCoreMLModel?
  private var detectionRequest: VNCoreMLRequest?

  // Callback for detection results
  var detectionHandler: (([VNRecognizedObjectObservation]) -> Void)?

  init() {
    setupModel()

    // Listen for model changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(modelChanged),
      name: .modelChanged,
      object: nil
    )
  }

  @objc private func modelChanged() {
    setupModel()
  }

  private func setupModel() {
    do {
      var modelURL: URL?

      // Get model name from settings
      let modelName = Settings.shared.modelName.isEmpty ? "yolov8n" : Settings.shared.modelName
      let formats = ["mlpackage", "mlmodelc"]

      // First try the main bundle
      for format in formats {
        if let url = Bundle.main.url(forResource: modelName, withExtension: format) {
          modelURL = url
          break
        }
      }

      // If not found, try Resources directory
      if modelURL == nil,
        let resourcesURL = Bundle.main.resourceURL?.appendingPathComponent("Contents/Resources")
      {
        for format in formats {
          let potentialURL = resourcesURL.appendingPathComponent("\(modelName).\(format)")
          if FileManager.default.fileExists(atPath: potentialURL.path) {
            modelURL = potentialURL
            break
          }
        }

        // Special case for .mlmodelc which is a directory
        let mlmodelcURL = resourcesURL.appendingPathComponent("\(modelName).mlmodelc")
        if FileManager.default.fileExists(atPath: mlmodelcURL.path) {
          modelURL = mlmodelcURL
        }
      }

      guard let modelURL = modelURL else {
        print("Error: Could not find model in any format")
        return
      }

      print("Found model at path: \(modelURL.path)")

      let config = MLModelConfiguration()
      config.computeUnits = .all

      do {
        let model = try MLModel(contentsOf: modelURL, configuration: config)
        print("Successfully loaded MLModel")

        // Extract model information
        let modelDesc = model.modelDescription

        // Get class labels directly from the model
        let classLabels = modelDesc.classLabels as? [String] ?? []

        // Get additional metadata
        let metadata = modelDesc.metadata
        let description =
          metadata[MLModelMetadataKey.description] as? String ?? "YOLOv8 Object Detection Model"
        let version = metadata[MLModelMetadataKey.versionString] as? String ?? ""
        let modelInfo = "\(description) (v\(version))"

        // Update settings with model information
        Settings.shared.updateModelInfo(
          name: modelName,
          description: modelInfo,
          classes: classLabels
        )

        do {
          visionModel = try VNCoreMLModel(for: model)
          print("Successfully created VNCoreMLModel")

          detectionRequest = VNCoreMLRequest(model: visionModel!) { [weak self] request, error in
            if let error = error {
              print("Detection error: \(error)")
              return
            }
            self?.processResults(request)
          }
          detectionRequest?.imageCropAndScaleOption = .scaleFit
          print("Successfully created VNCoreMLRequest")
        } catch {
          print("Failed to create VNCoreMLModel: \(error)")
        }
      } catch {
        print("Failed to load MLModel: \(error)")
      }
    } catch {
      print("Unexpected error: \(error)")
    }
  }

  func detect(in image: CGImage) {
    guard let request = detectionRequest else {
      print("Detection request not initialized")
      return
    }

    // Create a handler with proper orientation
    // Vision framework will automatically:
    // 1. Scale the image to the model's required size (640x640)
    // 2. Preserve aspect ratio
    // 3. Pad with gray to make it square
    let handler = VNImageRequestHandler(
      cgImage: image,
      orientation: .up
    )

    do {
      try handler.perform([request])
    } catch {
      print("Failed to perform detection: \(error)")
    }
  }

  func processResults(_ request: VNRequest) {
    guard let results = request.results as? [VNRecognizedObjectObservation] else {
      print("No detection results or invalid type")
      return
    }
    print("Detected \(results.count) objects")
    detectionHandler?(results)
  }
}

struct DetectedObject: Identifiable, Equatable {
  let id = UUID()
  let label: String
  let confidence: Float
  let boundingBox: CGRect

  // Implement Equatable
  static func == (lhs: DetectedObject, rhs: DetectedObject) -> Bool {
    lhs.label == rhs.label && lhs.confidence == rhs.confidence && lhs.boundingBox == rhs.boundingBox
  }
}
