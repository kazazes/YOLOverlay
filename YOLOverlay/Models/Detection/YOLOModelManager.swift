import CoreImage
import CoreML
import QuartzCore
import Vision

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
        // Clear existing request and model
        detectionRequest = nil
        visionModel = nil
        trackedObjects.removeAll()
        
        // Load model first
        let mlModel = try await loadModel()
        
        // Create Vision request
        let model = try VNCoreMLModel(for: mlModel)
        visionModel = model
        
        // Create new request
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
          if let error = error {
            LogManager.shared.error("Detection request error", error: error)
            return
          }
          
          guard let self = self else { return }
          
          // Check if we still have a valid request
          if self.detectionRequest === request {
            LogManager.shared.info("Detection request completed successfully")
            self.handleResults(request)
          } else {
            LogManager.shared.info("Ignoring results from outdated request")
          }
        }
        
        request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFit
        detectionRequest = request
        
        // Log model configuration
        LogManager.shared.info("Model configuration:")
        LogManager.shared.info("Input and output features:")
        for feature in mlModel.modelDescription.inputDescriptionsByName {
          LogManager.shared.info("- Input: \(feature.key): \(feature.value)")
        }
        for feature in mlModel.modelDescription.outputDescriptionsByName {
          LogManager.shared.info("- Output: \(feature.key): \(feature.value)")
        }
        
        LogManager.shared.info("Successfully initialized model and request")
      } catch {
        LogManager.shared.error("Failed to setup model", error: error)
      }
    }
  }

  private func loadModel() async throws -> MLModel {
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
      if classLabels.isEmpty {
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

      return mlModel
    } catch {
      LogManager.shared.error("Failed to load MLModel", error: error)
      throw ModelError.modelLoadError(error)
    }
  }

  private func handleResults(_ request: VNRequest) {
    guard let results = request.results else {
      LogManager.shared.error("No detection results")
      return
    }

    LogManager.shared.info("Got \(results.count) results of type: \(type(of: results.first))")

    // Clear previous results if model type has changed
    if Settings.shared.isSegmentationModel {
      // Handle segmentation results
      for observation in results {
        guard let featureValueObs = observation as? VNCoreMLFeatureValueObservation else {
          LogManager.shared.error("Invalid segmentation result type: \(type(of: observation))")
          continue
        }
        
        let featureValue = featureValueObs.featureValue
        guard case .multiArray = featureValue.type,
              let mask = featureValue.multiArrayValue else {
          LogManager.shared.error("Invalid feature value type: \(featureValue.type)")
          continue
        }

        // Validate mask dimensions
        let shape = mask.shape
        guard shape.count == 4,
              shape[0].intValue == 1,
              shape[2].intValue == 160,
              shape[3].intValue == 160 else {
          LogManager.shared.error("Invalid mask shape: \(shape)")
          continue
        }

        // Create segmentation observation
        let observation = SegmentationObservation(mask: mask)
        observation.classLabels = Settings.shared.modelClasses
        observation.setValue(CGRect(x: 0, y: 0, width: 1, height: 1), forKey: "boundingBox")
        
        LogManager.shared.info("Created segmentation observation with \(Settings.shared.modelClasses.count) classes")
        detectionHandler?([observation])
        return
      }
      
      LogManager.shared.error("No valid segmentation mask found in results")
    } else {
      // Handle regular YOLO detection results
      let detections = results.compactMap { $0 as? VNRecognizedObjectObservation }
      
      if detections.isEmpty {
        LogManager.shared.error("No valid detection results found")
        return
      }

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
