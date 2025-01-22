import Foundation
import SwiftUI

class Settings: ObservableObject {
  static let availableColors = [
    "red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue",
    "indigo", "purple", "pink", "brown", "gray",
  ]

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
  @Published var modelName: String = ""
  @Published var modelDescription: String = ""
  @Published var modelClasses: [String] = []
  @Published var classColors: [String: String] = [:]

  private(set) var minimumFrameInterval: TimeInterval

  static let shared = Settings()

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
