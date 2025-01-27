import CoreImage
import CoreML
import QuartzCore
import Vision

// MARK: - Model Error
enum ModelError: Error {
  case modelNotFound
  case modelLoadError(Error)
  case visionError(Error)
}

// Helper struct to track objects over time
private struct YOLOTrackedObject {
  var label: String
  var confidence: Float
  var boundingBox: CGRect
  var lastSeen: TimeInterval
  var velocity: CGVector  // For basic motion prediction

  // Smoothing factors
  static let positionSmoothing: CGFloat = 0.7  // Higher = more smoothing
  static let confidenceSmoothing: Float = 0.8

  mutating func update(with observation: VNRecognizedObjectObservation, at time: TimeInterval) {
    // Smooth confidence
    let newConfidence = observation.labels.first?.confidence ?? 0
    confidence =
      confidence * YOLOTrackedObject.confidenceSmoothing + newConfidence
      * (1 - YOLOTrackedObject.confidenceSmoothing)

    // Calculate velocity
    let dt = time - lastSeen
    if dt > 0 {
      let dx = observation.boundingBox.origin.x - boundingBox.origin.x
      let dy = observation.boundingBox.origin.y - boundingBox.origin.y
      velocity = CGVector(dx: dx / dt, dy: dy / dt)
    }

    // Smooth position with velocity prediction
    let predictedBox = CGRect(
      x: boundingBox.origin.x + CGFloat(velocity.dx * dt),
      y: boundingBox.origin.y + CGFloat(velocity.dy * dt),
      width: boundingBox.width,
      height: boundingBox.height
    )

    // Smooth between prediction and new observation
    boundingBox = predictedBox.interpolated(
      to: observation.boundingBox,
      amount: 1 - YOLOTrackedObject.positionSmoothing
    )

    lastSeen = time
  }
}

class YOLOModelManager {
  private var visionModel: VNCoreMLModel?
  private var detectionRequest: VNCoreMLRequest?
  private var trackedObjects: [YOLOTrackedObject] = []
  private let maxAge: TimeInterval = 0.5  // Maximum time to keep tracking an unseen object
  private var currentFrame: CGRect = .zero  // Add current frame storage

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
    Task {
      do {
        visionModel = try await loadModel()
        await setupDetectionRequest()
      } catch {
        LogManager.shared.error("Failed to setup model", error: error)
      }
    }
  }

  private func loadModel() async throws -> VNCoreMLModel {
    guard let modelURL = findModel() else {
      LogManager.shared.error("Could not find model in any format")
      throw ModelError.modelNotFound
    }

    LogManager.shared.debug("Found model at path: \(modelURL.path)")

    do {
      let config = MLModelConfiguration()
      config.computeUnits = .all

      let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
      LogManager.shared.info("Successfully loaded MLModel")

      // Extract model metadata
      let modelDescription = mlModel.modelDescription

      // Extract class labels - try multiple known metadata keys
      var classLabels: [String] = []

      // First try to parse from creator metadata which is used by YOLOv8
      if let creatorMetadata = modelDescription.metadata[.creatorDefinedKey] as? [String: Any],
        let namesStr = creatorMetadata["names"] as? String,
        // Parse the string format "{0: 'hair', 1: 'face', ...}"
        let regex = try? NSRegularExpression(pattern: "'([^']*)'", options: [])
      {
        let matches = regex.matches(
          in: namesStr,
          options: [],
          range: NSRange(namesStr.startIndex..., in: namesStr)
        )

        let extractedLabels = matches.compactMap { (match: NSTextCheckingResult) -> String? in
          guard let range = Range(match.range(at: 1), in: namesStr) else { return nil }
          return String(namesStr[range])
        }
        classLabels = extractedLabels

        LogManager.shared.info("Extracted class labels from creator metadata: \(classLabels)")
      }

      // Fallback to other metadata keys if needed
      if classLabels.isEmpty {
        if let labels = modelDescription.metadata[MLModelMetadataKey(rawValue: "classes")]
          as? [String]
        {
          classLabels = labels
        } else if let labels = modelDescription.metadata[MLModelMetadataKey(rawValue: "names")]
          as? [String]
        {
          classLabels = labels
        } else if let labels = modelDescription.classLabels as? [String] {
          classLabels = labels
        }
      }

      // For segmentation models, check output shape for number of classes if no labels found
      if classLabels.isEmpty && Settings.shared.isSegmentationModel {
        if let output = modelDescription.outputDescriptionsByName.values.first(where: {
          $0.name.lowercased().contains("mask") || $0.name.lowercased().contains("seg")
        }),
          case .multiArray = output.type,
          let shape = output.multiArrayConstraint?.shape,
          shape.count >= 3
        {
          // For YOLOv8 segmentation models, use the second dimension (channels)
          let numClasses = shape[1].intValue
          classLabels = Array(0..<numClasses).map { "Class \($0)" }
          LogManager.shared.info(
            "Generated \(numClasses) default class labels from segmentation output shape")
        }
      }

      LogManager.shared.info("Found class labels: \(classLabels)")

      // Check if this is a segmentation model based on outputs
      let isSegmentation = modelDescription.outputDescriptionsByName.values.contains { output in
        // Check for segmentation-specific output named "p" with expected shape
        if output.name == "p",
           case .multiArray = output.type,
           let shape = output.multiArrayConstraint?.shape,
           shape.count == 4,  // [1, 32, 160, 160]
           shape[2].intValue == 160,
           shape[3].intValue == 160 {
          return true
        }
        return false
      }

      // Update Settings with model info - make a local copy to avoid capture
      let finalClassLabels = classLabels
      await Settings.shared.updateModelInfo(
        modelClasses: finalClassLabels,
        isSegmentation: isSegmentation
      )

      do {
        let model = try VNCoreMLModel(for: mlModel)
        LogManager.shared.info("Successfully created VNCoreMLModel")
        return model
      } catch {
        LogManager.shared.error("Detection error", error: error)
        throw ModelError.visionError(error)
      }
    } catch {
      LogManager.shared.error("Failed to load MLModel", error: error)
      throw ModelError.modelLoadError(error)
    }
  }

  private func setupDetectionRequest() async {
    do {
      let model = try await loadModel()
      detectionRequest = VNCoreMLRequest(model: model) { [weak self] request, error in
        if let error = error {
          LogManager.shared.error("Detection request error", error: error)
          return
        }
        LogManager.shared.info("Detection request completed successfully")
        self?.handleResults(request)
      }
      detectionRequest?.imageCropAndScaleOption = .scaleFit
      
      // Log model configuration
      LogManager.shared.info("Model configuration:")
      LogManager.shared.info("Input and output features:")
      let mlModel = try await MLModel.load(contentsOf: findModel()!, configuration: MLModelConfiguration())
      for feature in mlModel.modelDescription.inputDescriptionsByName {
        LogManager.shared.info("- Input: \(feature.key): \(feature.value)")
      }
      for feature in mlModel.modelDescription.outputDescriptionsByName {
        LogManager.shared.info("- Output: \(feature.key): \(feature.value)")
      }
      
      LogManager.shared.info("Successfully created VNCoreMLRequest")
    } catch let error as ModelError {
      switch error {
      case .visionError(let err):
        LogManager.shared.error("Failed to create VNCoreMLModel", error: err)
      case .modelLoadError(let err):
        LogManager.shared.error("Failed to load MLModel", error: err)
      case .modelNotFound:
        LogManager.shared.error("Model not found")
      }
    } catch {
      LogManager.shared.fault("Unexpected error", error: error)
    }
  }

  private func handleResults(_ request: VNRequest) {
    guard let results = request.results else {
      LogManager.shared.error("No detection results")
      return
    }

    LogManager.shared.info("Got results of type: \(type(of: results))")
    LogManager.shared.info("First result type: \(type(of: results.first))")
    LogManager.shared.info("Number of results: \(results.count)")

    if Settings.shared.isSegmentationModel {
      // Handle segmentation results
      for (index, observation) in results.enumerated() {
        LogManager.shared.info("Processing observation \(index) of type: \(type(of: observation))")
        
        guard let featureValueObs = observation as? VNCoreMLFeatureValueObservation else {
          LogManager.shared.error("Observation is not a VNCoreMLFeatureValueObservation")
          continue
        }
        
        LogManager.shared.info("Found VNCoreMLFeatureValueObservation with name: \(featureValueObs.featureName)")
        let featureValue = featureValueObs.featureValue
        LogManager.shared.info("Feature value type: \(type(of: featureValue))")
        
        guard featureValue.type == .multiArray,
              let mask = featureValue.multiArrayValue else {
          LogManager.shared.error("Feature value is not a multiArray")
          continue
        }

        // Validate mask dimensions
        let shape = mask.shape
        if shape.count != 4 {
            LogManager.shared.error("Invalid mask shape: expected 4 dimensions, got \(shape.count)")
            continue
        }

        // Validate mask dimensions match expected format
        if shape[0].intValue != 1 || shape[2].intValue != 160 || shape[3].intValue != 160 {
            LogManager.shared.error("Invalid mask dimensions: expected [1, N, 160, 160], got \(shape)")
            continue
        }

        // Create segmentation observation with current frame
        let observation = SegmentationObservation(mask: mask)
        observation.classLabels = Settings.shared.modelClasses
        observation.setValue(CGRect(x: 0, y: 0, width: 1, height: 1), forKey: "boundingBox")
        
        LogManager.shared.info("Created segmentation observation with mask shape: \(mask.shape)")
        LogManager.shared.info("Class labels: \(Settings.shared.modelClasses)")
        LogManager.shared.info("Current frame: \(currentFrame)")
        LogManager.shared.info("Calling detection handler with segmentation observation")
        
        detectionHandler?([observation])
        return // Exit after successfully processing the segmentation mask
      }
      
      // If we get here, no valid segmentation mask was found
      LogManager.shared.error("No segmentation mask found in results")
    } else {
      // Handle regular YOLO detection results
      let detections = results.compactMap { $0 as? VNRecognizedObjectObservation }
      if !detections.isEmpty {
        // Filter by confidence threshold
        let filteredDetections = detections.filter { observation in
          guard let confidence = observation.labels.first?.confidence else { return false }
          return confidence >= Settings.shared.confidenceThreshold
        }

        if !filteredDetections.isEmpty {
          LogManager.shared.info("Found \(filteredDetections.count) detections above threshold")
          for detection in filteredDetections {
            if let label = detection.labels.first {
              LogManager.shared.debug("  - \(label.identifier): \(label.confidence)")
            }
          }
          detectionHandler?(filteredDetections)
        } else {
          LogManager.shared.debug("No detections above confidence threshold")
        }
      } else {
        LogManager.shared.error("No valid detection results found in observations")
      }
    }
  }

  private func findModel() -> URL? {
    // Get model name from settings
    let modelName = Settings.shared.modelName.isEmpty ? "yolov8n" : Settings.shared.modelName
    LogManager.shared.info("Looking for model: \(modelName)")

    // First check if it's a custom model
    if let customModelURL = Settings.shared.getModelURL(for: modelName) {
      LogManager.shared.info("Found custom model at: \(customModelURL.path)")
      return customModelURL
    }

    let formats = ["mlpackage", "mlmodelc"]

    // First try the main bundle
    for format in formats {
      if let url = Bundle.main.url(forResource: modelName, withExtension: format) {
        LogManager.shared.info("Found model in main bundle: \(url.path)")
        return url
      }
    }

    // If not found, try Resources directory
    if let resourcesURL = Bundle.main.resourceURL?.appendingPathComponent("Contents/Resources") {
      LogManager.shared.info("Checking Resources directory: \(resourcesURL.path)")

      for format in formats {
        let potentialURL = resourcesURL.appendingPathComponent("\(modelName).\(format)")
        LogManager.shared.debug("Checking for model at: \(potentialURL.path)")
        if FileManager.default.fileExists(atPath: potentialURL.path) {
          LogManager.shared.info("Found model in Resources: \(potentialURL.path)")
          return potentialURL
        }
      }

      // Special case for .mlmodelc which is a directory
      let mlmodelcURL = resourcesURL.appendingPathComponent("\(modelName).mlmodelc")
      LogManager.shared.debug("Checking for .mlmodelc at: \(mlmodelcURL.path)")
      if FileManager.default.fileExists(atPath: mlmodelcURL.path) {
        LogManager.shared.info("Found .mlmodelc in Resources: \(mlmodelcURL.path)")
        return mlmodelcURL
      }
    }

    // Check Application Support directory
    do {
      let appSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let modelsDir = appSupport.appendingPathComponent("Models")
      LogManager.shared.info("Checking Application Support directory: \(modelsDir.path)")

      for format in formats {
        let potentialURL = modelsDir.appendingPathComponent("\(modelName).\(format)")
        LogManager.shared.debug("Checking for model at: \(potentialURL.path)")
        if FileManager.default.fileExists(atPath: potentialURL.path) {
          LogManager.shared.info("Found model in Application Support: \(potentialURL.path)")
          return potentialURL
        }
      }
    } catch {
      LogManager.shared.error("Error checking Application Support directory", error: error)
    }

    LogManager.shared.error("Could not find model '\(modelName)' in any location")
    return nil
  }

  func detect(in image: CGImage) {
    guard let request = detectionRequest else {
      LogManager.shared.error("Detection request not initialized")
      return
    }

    // Store current frame dimensions
    currentFrame = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    LogManager.shared.info("Processing frame with dimensions: \(currentFrame)")

    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    try? handler.perform([request])
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

// Helper extension to convert between types
extension VNRecognizedObjectObservation {
  static func fromDetectedObject(_ object: DetectedObject) -> VNRecognizedObjectObservation {
    let observation = VNRecognizedObjectObservation(boundingBox: object.boundingBox)

    // Create a classification observation using private API
    let classification = unsafeBitCast(
      NSClassFromString("VNClassificationObservation")?.alloc(),
      to: VNClassificationObservation.self
    )
    classification.setValue(object.label, forKey: "identifier")
    classification.setValue(object.confidence, forKey: "confidence")

    // Set the labels using setValue
    observation.setValue([classification], forKey: "labels")
    return observation
  }
}

// Helper extension for CGRect interpolation
extension CGRect {
  func interpolated(to other: CGRect, amount: CGFloat) -> CGRect {
    let x = origin.x + (other.origin.x - origin.x) * amount
    let y = origin.y + (other.origin.y - origin.y) * amount
    let width = size.width + (other.size.width - size.width) * amount
    let height = size.height + (other.size.height - size.height) * amount
    return CGRect(x: x, y: y, width: width, height: height)
  }
}
