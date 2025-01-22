import Foundation
import SwiftUI

class Settings: ObservableObject {
  @Published var targetFPS: Double {
    didSet {
      UserDefaults.standard.set(targetFPS, forKey: "targetFPS")
      minimumFrameInterval = 1.0 / targetFPS
    }
  }

  @Published var confidenceThreshold: Float {
    didSet {
      UserDefaults.standard.set(confidenceThreshold, forKey: "confidenceThreshold")
    }
  }

  @Published var showLabels: Bool {
    didSet {
      UserDefaults.standard.set(showLabels, forKey: "showLabels")
    }
  }

  @Published var boundingBoxColor: String {
    didSet {
      UserDefaults.standard.set(boundingBoxColor, forKey: "boundingBoxColor")
    }
  }

  @Published var boundingBoxOpacity: Double {
    didSet {
      UserDefaults.standard.set(boundingBoxOpacity, forKey: "boundingBoxOpacity")
    }
  }

  // Smoothing settings
  @Published var enableSmoothing: Bool {
    didSet {
      UserDefaults.standard.set(enableSmoothing, forKey: "enableSmoothing")
    }
  }

  @Published var smoothingFactor: Double {
    didSet {
      UserDefaults.standard.set(smoothingFactor, forKey: "smoothingFactor")
    }
  }

  @Published var objectPersistence: Double {
    didSet {
      UserDefaults.standard.set(objectPersistence, forKey: "objectPersistence")
    }
  }

  // Model information
  @Published var modelName: String {
    didSet {
      if modelName != oldValue {
        UserDefaults.standard.set(modelName, forKey: "selectedModel")
        NotificationCenter.default.post(name: .modelChanged, object: nil)
      }
    }
  }
  @Published var modelDescription: String = ""
  @Published var modelClasses: [String] = []
  @Published var modelMetadata: String = ""
  @Published var classColors: [String: String] = [:]
  @Published var availableModels: [String] = []

  private(set) var minimumFrameInterval: TimeInterval

  static let shared = Settings()

  // Available colors for class detection
  static let availableColors = [
    "red", "blue", "green", "yellow", "orange", "purple",
    "pink", "teal", "indigo", "mint", "brown", "cyan",
  ]

  private func generateRandomColor() -> String {
    let hue = Double.random(in: 0...1)
    let saturation = Double.random(in: 0.7...0.9)
    let brightness = Double.random(in: 0.9...1.0)

    let color = NSColor(
      calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    let red = UInt8(round(color.redComponent * 255))
    let green = UInt8(round(color.greenComponent * 255))
    let blue = UInt8(round(color.blueComponent * 255))

    return String(format: "#%02X%02X%02X", red, green, blue)
  }

  private init() {
    // Initialize stored properties first
    let fps = UserDefaults.standard.double(forKey: "targetFPS").nonZeroValue(defaultValue: 30.0)
    self.minimumFrameInterval = 1.0 / fps

    // Then initialize published properties
    self.targetFPS = fps
    self.confidenceThreshold = Float(
      UserDefaults.standard.double(forKey: "confidenceThreshold").nonZeroValue(defaultValue: 0.3))
    self.showLabels = UserDefaults.standard.bool(forKey: "showLabels", defaultValue: true)
    self.boundingBoxColor = UserDefaults.standard.string(forKey: "boundingBoxColor") ?? "red"
    self.boundingBoxOpacity = UserDefaults.standard.double(forKey: "boundingBoxOpacity")
      .nonZeroValue(defaultValue: 1.0)

    // Initialize smoothing settings
    self.enableSmoothing = UserDefaults.standard.bool(forKey: "enableSmoothing", defaultValue: true)
    self.smoothingFactor = UserDefaults.standard.double(forKey: "smoothingFactor")
      .nonZeroValue(defaultValue: 0.3)
    self.objectPersistence = UserDefaults.standard.double(forKey: "objectPersistence")
      .nonZeroValue(defaultValue: 0.5)

    // Initialize model name with a default value
    self.modelName = UserDefaults.standard.string(forKey: "selectedModel") ?? "yolov8n"
    self.modelDescription = ""

    // Load saved class colors or use empty dictionary
    if let savedColors = UserDefaults.standard.dictionary(forKey: "classColors")
      as? [String: String]
    {
      self.classColors = savedColors
    } else {
      self.classColors = [:]
    }

    // Initialize empty arrays
    self.modelClasses = []
    self.availableModels = []

    // Now that all properties are initialized, load available models
    self.loadAvailableModels()
  }

  func loadAvailableModels() {
    var models: [String] = []

    // First scan main bundle
    do {
      let bundleModels =
        try Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil)?
        .map { $0.deletingPathExtension().lastPathComponent } ?? []
      models.append(contentsOf: bundleModels)
      LogManager.shared.info("Found models in main bundle: \(bundleModels)")
    } catch {
      LogManager.shared.error("Error scanning main bundle", error: error)
    }

    let appURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
    // Then scan app's Resources directory

    do {
      let resourceContents = try FileManager.default.contentsOfDirectory(
        at: appURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )

      let additionalModels =
        resourceContents
        .filter { $0.pathExtension == "mlmodelc" }
        .map { $0.deletingPathExtension().lastPathComponent }

      models.append(contentsOf: additionalModels)
      LogManager.shared.info("Found models in app Resources: \(additionalModels)")
    } catch {
      LogManager.shared.error("Error scanning app Resources directory", error: error)
    }

    // Remove duplicates and sort
    availableModels = Array(Set(models)).sorted()
    LogManager.shared.info("Final available models: \(availableModels)")

    // If current model is not in available models, select first available
    if !availableModels.isEmpty && !availableModels.contains(modelName) {
      modelName = availableModels[0]
    }
  }

  func updateModelInfo(name: String, description: String, classes: [String], metadata: String) {
    // Only update if there are actual changes
    let hasChanges =
      modelName != name || modelDescription != description || modelClasses != classes
      || modelMetadata != metadata

    if hasChanges {
      modelName = name
      modelDescription = description
      modelClasses = classes
      modelMetadata = metadata

      // Generate colors for any new classes
      for className in classes {
        if classColors[className] == nil {
          classColors[className] = generateRandomColor()
        }
      }

      // Clean up colors for removed classes
      classColors = classColors.filter { classes.contains($0.key) }
    }
  }

  func getColorForClass(_ className: String) -> String {
    return classColors[className] ?? boundingBoxColor
  }

  private func findModel() -> URL? {
    // Get model name from settings
    let modelName = Settings.shared.modelName.isEmpty ? "yolov8n" : Settings.shared.modelName
    let formats = ["mlpackage", "mlmodelc"]

    // First try the main bundle
    for format in formats {
      if let url = Bundle.main.url(forResource: modelName, withExtension: format) {
        LogManager.shared.info("Found model in main bundle: \(url.lastPathComponent)")
        return url
      }
    }

    // If not found, try Resources directory if it exists
    if let resourcesURL = Bundle.main.resourceURL?.appendingPathComponent("Contents/Resources"),
      FileManager.default.fileExists(atPath: resourcesURL.path)
    {
      for format in formats {
        let potentialURL = resourcesURL.appendingPathComponent("\(modelName).\(format)")
        if FileManager.default.fileExists(atPath: potentialURL.path) {
          LogManager.shared.info(
            "Found model in Resources directory: \(potentialURL.lastPathComponent)")
          return potentialURL
        }
      }

      // Special case for .mlmodelc which is a directory
      let mlmodelcURL = resourcesURL.appendingPathComponent("\(modelName).mlmodelc")
      if FileManager.default.fileExists(atPath: mlmodelcURL.path) {
        LogManager.shared.info(
          "Found compiled model in Resources directory: \(mlmodelcURL.lastPathComponent)")
        return mlmodelcURL
      }
    }

    LogManager.shared.error("Model not found: \(modelName)")
    return nil
  }
}

// Model structure
struct YOLOModel: Identifiable {
  let id = UUID()
  let name: String
  let displayName: String
  let description: String
}

// Notification for model changes
extension Notification.Name {
  static let modelChanged = Notification.Name("modelChanged")
}

// Helper extensions
extension UserDefaults {
  func bool(forKey key: String, defaultValue: Bool) -> Bool {
    if object(forKey: key) == nil {
      return defaultValue
    }
    return bool(forKey: key)
  }
}

extension Double {
  func nonZeroValue(defaultValue: Double) -> Double {
    return self == 0 ? defaultValue : self
  }
}
