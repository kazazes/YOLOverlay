import CoreML
import Foundation
import SwiftUI

class Settings: ObservableObject {
    static let shared = Settings()
    
    // MARK: - Display Settings
    @Published var targetFPS: Double {
        didSet {
            UserDefaults.standard.set(targetFPS, forKey: "targetFPS")
            minimumFrameInterval = 1.0 / targetFPS
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
    
    // MARK: - Detection Settings
    @Published var confidenceThreshold: Float {
        didSet {
            UserDefaults.standard.set(confidenceThreshold, forKey: "confidenceThreshold")
        }
    }
    
    // MARK: - Smoothing Settings
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
    
    // MARK: - Segmentation Settings
    @Published var segmentationOpacity: Double {
        didSet {
            UserDefaults.standard.set(segmentationOpacity, forKey: "segmentationOpacity")
        }
    }
    
    @Published var segmentationColorMode: String {
        didSet {
            UserDefaults.standard.set(segmentationColorMode, forKey: "segmentationColorMode")
        }
    }
    
    private(set) var minimumFrameInterval: TimeInterval
    
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
        
        // Initialize segmentation settings
        self.segmentationOpacity = UserDefaults.standard.double(forKey: "segmentationOpacity")
            .nonZeroValue(defaultValue: 0.5)
        self.segmentationColorMode = UserDefaults.standard.string(forKey: "segmentationColorMode") ?? "class"
    }
} 