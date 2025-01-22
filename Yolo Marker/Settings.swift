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

  // Model information
  @Published var modelName: String = "" {
    didSet {
      UserDefaults.standard.set(modelName, forKey: "selectedModel")
      NotificationCenter.default.post(name: .modelChanged, object: nil)
    }
  }
  @Published var modelDescription: String = ""
  @Published var modelClasses: [String] = []
  @Published var classColors: [String: String] = [:]
  @Published var availableModels: [YOLOModel] = []

  private(set) var minimumFrameInterval: TimeInterval

  static let shared = Settings()

  // Available colors for class detection
  static let availableColors = [
    "red", "blue", "green", "yellow", "orange", "purple",
    "pink", "teal", "indigo", "mint", "brown", "cyan",
  ]

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

    // Load saved class colors or generate new ones
    if let savedColors = UserDefaults.standard.dictionary(forKey: "classColors")
      as? [String: String]
    {
      self.classColors = savedColors
    }

    // Load available models
    self.loadAvailableModels()

    // Set selected model
    if let savedModel = UserDefaults.standard.string(forKey: "selectedModel") {
      self.modelName = savedModel
    } else {
      self.modelName = "yolov8n"  // Default model
    }
  }

  func loadAvailableModels() {
    let versions = [
      ("v8", "YOLOv8"),
      ("11", "YOLO11"),
    ]
    let sizes = [
      ("n", "Nano", "Fastest, smallest model"),
      ("s", "Small", "Balanced speed and accuracy"),
      ("m", "Medium", "Better accuracy, medium speed"),
      ("l", "Large", "High accuracy, slower speed"),
      ("x", "XLarge", "Highest accuracy, slowest speed"),
    ]

    var models: [YOLOModel] = []

    // Generate all possible model combinations
    for (version, versionName) in versions {
      for (size, sizeName, description) in sizes {
        let name = version == "11" ? "yolo11\(size)" : "yolov8\(size)"
        let displayName = "\(versionName) \(sizeName)"
        models.append(
          YOLOModel(
            name: name,
            displayName: displayName,
            description: description
          ))
      }
    }

    // Filter to only include models that exist in the bundle
    availableModels = models.filter { model in
      let formats = ["mlpackage", "mlmodelc"]
      return formats.contains { format in
        Bundle.main.url(forResource: model.name, withExtension: format) != nil
      }
    }
  }

  func updateModelInfo(name: String, description: String, classes: [String]) {
    self.modelName = name
    self.modelDescription = description
    self.modelClasses = classes

    // Generate colors for new classes
    for (index, className) in classes.enumerated() {
      if classColors[className] == nil {
        classColors[className] = Settings.availableColors[index % Settings.availableColors.count]
      }
    }

    // Save class colors
    UserDefaults.standard.set(classColors, forKey: "classColors")
  }

  func getColorForClass(_ className: String) -> String {
    return classColors[className] ?? boundingBoxColor
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
