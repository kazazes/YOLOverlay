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
        self?.processDetectionResults(request)
      }
      detectionRequest?.imageCropAndScaleOption = .scaleFit
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

  private func processDetectionResults(_ request: VNRequest) {
    guard let detectionRequest = detectionRequest else {
      LogManager.shared.error("Detection request not initialized")
      return
    }

    guard let results = request.results as? [VNRecognizedObjectObservation] else {
      LogManager.shared.error("No detection results or invalid type")
      return
    }

    let currentTime = CACurrentMediaTime()

    // Filter results based on size constraints
    let threshold = Settings.shared.confidenceThreshold
    let filteredResults = results.filter { observation in
      guard let label = observation.labels.first else { return false }

      let box = observation.boundingBox
      let minSize: CGFloat = 0.01
      let maxSize: CGFloat = 0.7
      let isReasonableSize =
        (minSize...maxSize).contains(box.width) && (minSize...maxSize).contains(box.height)

      let area = box.width * box.height
      let maxArea: CGFloat = 0.4
      let hasReasonableArea = area <= maxArea

      return label.confidence >= threshold && isReasonableSize && hasReasonableArea
    }

    // Update tracked objects
    var newTrackedObjects: [YOLOTrackedObject] = []

    // Update existing tracked objects with new detections
    for result in filteredResults {
      guard let label = result.labels.first?.identifier else { continue }

      // Find closest matching tracked object
      if let index = trackedObjects.firstIndex(where: { tracked -> Bool in
        tracked.label == label && tracked.boundingBox.intersects(result.boundingBox)
          && currentTime - tracked.lastSeen < maxAge
      }) {
        // Update existing tracked object
        var tracked = trackedObjects[index]
        tracked.update(with: result, at: currentTime)
        newTrackedObjects.append(tracked)
      } else {
        // Create new tracked object
        let tracked = YOLOTrackedObject(
          label: label,
          confidence: result.labels.first?.confidence ?? 0,
          boundingBox: result.boundingBox,
          lastSeen: currentTime,
          velocity: .zero
        )
        newTrackedObjects.append(tracked)
      }
    }

    // Keep recently tracked objects that weren't updated
    for tracked in trackedObjects {
      if currentTime - tracked.lastSeen < maxAge
        && !newTrackedObjects.contains(where: { $0.label == tracked.label })
      {
        newTrackedObjects.append(tracked)
      }
    }

    trackedObjects = newTrackedObjects

    // Convert tracked objects to VNRecognizedObjectObservation
    let smoothedResults = trackedObjects.map { tracked -> VNRecognizedObjectObservation in
      // Create a recognized object observation
      let observation = VNRecognizedObjectObservation(boundingBox: tracked.boundingBox)

      // Create a classification observation using private API
      let classification = unsafeBitCast(
        NSClassFromString("VNClassificationObservation")?.alloc(),
        to: VNClassificationObservation.self
      )
      classification.setValue(tracked.label, forKey: "identifier")
      classification.setValue(tracked.confidence, forKey: "confidence")

      // Set the labels using setValue
      observation.setValue([classification], forKey: "labels")

      return observation
    }

    // Only log if there's a significant change in detections
    if smoothedResults.count != previousResultCount {
      previousResultCount = smoothedResults.count
      LogManager.shared.debug("Filtered detections: \(smoothedResults.count)")
    }

    // Pass smoothed results to handler
    detectionHandler?(smoothedResults)
  }

  // Track previous detection count to reduce logging
  private var previousResultCount: Int = 0

  private func findModel() -> URL? {
    // Get model name from settings
    let modelName = Settings.shared.modelName.isEmpty ? "yolov8n" : Settings.shared.modelName
    let formats = ["mlpackage", "mlmodelc"]

    // First try the main bundle
    for format in formats {
      if let url = Bundle.main.url(forResource: modelName, withExtension: format) {
        return url
      }
    }

    // If not found, try Resources directory
    if let resourcesURL = Bundle.main.resourceURL?.appendingPathComponent("Contents/Resources") {
      for format in formats {
        let potentialURL = resourcesURL.appendingPathComponent("\(modelName).\(format)")
        if FileManager.default.fileExists(atPath: potentialURL.path) {
          return potentialURL
        }
      }

      // Special case for .mlmodelc which is a directory
      let mlmodelcURL = resourcesURL.appendingPathComponent("\(modelName).mlmodelc")
      if FileManager.default.fileExists(atPath: mlmodelcURL.path) {
        return mlmodelcURL
      }
    }

    return nil
  }

  func detect(in image: CGImage) {
    guard let request = detectionRequest else {
      LogManager.shared.error("Detection request not initialized")
      return
    }

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
