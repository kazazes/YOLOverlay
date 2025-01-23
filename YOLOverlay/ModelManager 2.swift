import CoreImage
import CoreML
import Foundation
import OSLog
import Vision

class ModelManager: ObservableObject {
  static let shared = ModelManager()

  @Published var isDownloading = false
  @Published var downloadProgress: Double = 0
  @Published var currentOperation: String = ""

  private let modelsDirectory: URL
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ModelManager")

  private init() {
    // Get Application Support directory
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    modelsDirectory = appSupport.appendingPathComponent("YOLOverlay/Models", isDirectory: true)

    // Create models directory if it doesn't exist
    try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
  }

  func downloadModel(from repoID: String) async throws {
    await MainActor.run {
      isDownloading = true
      currentOperation = "Preparing download..."
    }

    let modelName = repoID.components(separatedBy: "/").last ?? repoID

    // Try downloading in order of preference: CoreML -> ONNX
    let modelFormats = [
      ("model.mlpackage", false),  // (format, needs conversion)
      ("model.onnx", true),
    ]

    var lastError: Error = ModelError.downloadFailed

    for (format, needsConversion) in modelFormats {
      do {
        let downloadURL = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(format)")!

        // Download the model
        let (downloadedURL, _) = try await URLSession.shared.download(from: downloadURL) {
          progress in
          Task { @MainActor in
            self.downloadProgress = progress.fractionCompleted
            self.currentOperation = "Downloading model..."
          }
        }

        var mlmodelURL = downloadedURL

        // Convert if needed
        if needsConversion {
          await MainActor.run { currentOperation = "Converting model to CoreML..." }
          mlmodelURL = try await convertONNXToCoreML(downloadedURL, modelName: modelName)
        }

        // Add NMS pipeline
        let pipelineURL = try await addNMSPipeline(mlmodelURL)

        // Move to models directory
        let destinationURL = modelsDirectory.appendingPathComponent("\(modelName).mlpackage")
        try FileManager.default.moveItem(at: pipelineURL, to: destinationURL)

        await MainActor.run {
          isDownloading = false
          downloadProgress = 0
          currentOperation = ""
        }

        Settings.shared.loadAvailableModels()
        return

      } catch {
        lastError = error
        logger.error("Failed to download/convert \(format): \(error.localizedDescription)")
        continue
      }
    }

    throw lastError
  }

  private func convertONNXToCoreML(_ onnxFile: URL, modelName: String) async throws -> URL {
    let config = MLModelConfiguration()
    config.computeUnits = .all

    // Convert ONNX model to CoreML
    let modelURL = try await MLModel.compileModel(at: onnxFile, configuration: config)

    return modelURL
  }

  private func createNMSModel(inputShape: [NSNumber], classCount: Int, maxDetections: Int = 300)
    throws -> MLModel
  {
    let modelDescription = MLModelDescription()

    // Define inputs
    let boxesInputShape = [1, inputShape[1], 4] as [NSNumber]
    let scoresInputShape = [1, inputShape[1], classCount] as [NSNumber]

    let boxesInput = MLFeatureDescription(name: "boxes", type: .multiArray(shape: boxesInputShape))
    let scoresInput = MLFeatureDescription(
      name: "scores", type: .multiArray(shape: scoresInputShape))
    let iouThresholdInput = MLFeatureDescription(name: "iouThreshold", type: .double)
    let confidenceThresholdInput = MLFeatureDescription(name: "confidenceThreshold", type: .double)

    modelDescription.inputDescriptionsByName = [
      "boxes": boxesInput,
      "scores": scoresInput,
      "iouThreshold": iouThresholdInput,
      "confidenceThreshold": confidenceThresholdInput,
    ]

    // Define outputs
    let outputShape = [maxDetections, 5] as [NSNumber]  // [x, y, width, height, class]
    let outputDesc = MLFeatureDescription(
      name: "coordinates", type: .multiArray(shape: outputShape))
    let confidenceDesc = MLFeatureDescription(
      name: "confidence", type: .multiArray(shape: [maxDetections, 1]))

    modelDescription.outputDescriptionsByName = [
      "coordinates": outputDesc,
      "confidence": confidenceDesc,
    ]

    // Create NMS parameters
    let nmsParams = MLModelParameters()
    nmsParams.parameterDictionary["iouThreshold"] = 0.45 as NSNumber
    nmsParams.parameterDictionary["confidenceThreshold"] = 0.25 as NSNumber
    nmsParams.parameterDictionary["maxDetections"] = maxDetections as NSNumber

    return try MLModel(modelDescription: modelDescription, parameters: nmsParams)
  }

  private func addNMSPipeline(_ modelURL: URL) async throws -> URL {
    let config = MLModelConfiguration()
    let model = try MLModel(contentsOf: modelURL, configuration: config)

    // Get model description
    let inputDesc = model.modelDescription.inputDescriptionsByName
    let outputDesc = model.modelDescription.outputDescriptionsByName

    guard let imageInput = inputDesc["image"],
      let boxesOutput = outputDesc["output0"],
      let scoresOutput = outputDesc["output1"]
    else {
      throw ModelError.invalidModelFormat
    }

    // Get metadata
    let metadata = model.modelDescription.metadata
    let classCount = (metadata["nc"] as? NSNumber)?.intValue ?? 80

    // Create NMS model
    let nmsModel = try createNMSModel(
      inputShape: boxesOutput.multiArrayConstraint?.shape as? [NSNumber] ?? [],
      classCount: classCount
    )

    // Create pipeline
    let pipeline = MLPipeline()

    // Add preprocessing
    let preprocessingDesc = MLModelDescription()
    preprocessingDesc.inputDescriptionsByName["image"] = MLFeatureDescription(
      name: "image",
      type: .image,
      imageConstraint: MLImageConstraint(pixelsHigh: 640, pixelsWide: 640)
    )

    // Add main model
    pipeline.add(model)

    // Add NMS model
    pipeline.add(nmsModel)

    // Save pipeline with metadata
    let pipelineURL = modelURL.deletingLastPathComponent().appendingPathComponent(
      "pipeline.mlpackage")
    try pipeline.write(to: pipelineURL)

    // Add metadata
    if let existingMetadata = metadata as? [String: Any] {
      try addMetadata(to: pipelineURL, metadata: existingMetadata)
    }

    return pipelineURL
  }

  private func addMetadata(to modelURL: URL, metadata: [String: Any]) throws {
    var model = try MLModel(contentsOf: modelURL)

    // Update metadata
    var updatedMetadata = model.modelDescription.metadata
    for (key, value) in metadata {
      updatedMetadata[key] = value
    }

    // Add additional metadata
    updatedMetadata["com.apple.coreml.model.preview.type"] = "objectDetector" as NSString
    updatedMetadata["com.apple.coreml.model.preview.params"] = try? JSONSerialization.data(
      withJSONObject: [
        "labels": metadata["names"] ?? [],
        "iouThreshold": 0.45,
        "confidenceThreshold": 0.25,
      ])

    try model.write(to: modelURL)
  }

  func getModelPath(for name: String) -> URL? {
    let modelURL = modelsDirectory.appendingPathComponent("\(name).mlpackage")
    return FileManager.default.fileExists(atPath: modelURL.path) ? modelURL : nil
  }

  func listAvailableModels() -> [String] {
    guard
      let contents = try? FileManager.default.contentsOfDirectory(
        at: modelsDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    return
      contents
      .filter { $0.pathExtension == "mlpackage" }
      .map { $0.deletingPathExtension().lastPathComponent }
  }
}

enum ModelError: Error {
  case conversionNotImplemented
  case invalidModelFormat
  case pipelineCreationFailed
  case conversionFailed
  case metadataError
  case downloadFailed
  case unsupportedModelFormat
}
