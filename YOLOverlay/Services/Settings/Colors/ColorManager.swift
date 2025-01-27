import AppKit
import Foundation

class ColorManager: ObservableObject {
    static let shared = ColorManager()
    
    @Published var classColors: [String: String] = [:]
    
    // Available colors for class visualization
    static let availableColors = [
        "#FF0000",  // Red
        "#00FF00",  // Green
        "#0000FF",  // Blue
        "#FFFF00",  // Yellow
        "#FFA500",  // Orange
        "#800080",  // Purple
        "#FFC0CB",  // Pink
        "#008080",  // Teal
        "#4B0082",  // Indigo
        "#98FF98",  // Mint
        "#A52A2A",  // Brown
        "#00FFFF",  // Cyan
    ]
    
    private var persistentClassColors: [String: String] {
        get {
            return UserDefaults.standard.dictionary(forKey: "persistentClassColors") as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "persistentClassColors")
        }
    }
    
    private init() {
        if let persistentColors = UserDefaults.standard.dictionary(forKey: "persistentClassColors") as? [String: String] {
            self.classColors = persistentColors
        }
    }
    
    func updateColors(for classes: [String]) {
        // Clear existing colors for a fresh start
        classColors.removeAll()
        
        // Generate colors for all classes
        for label in classes {
            classColors[label] = generateConsistentColor(for: label)
        }
        
        // Save to persistent storage
        persistentClassColors = classColors
        LogManager.shared.info("Generated class colors: \(classColors)")
    }
    
    func getColorForClass(_ className: String) -> String {
        return classColors[className] ?? Settings.shared.boundingBoxColor
    }
    
    private func generateRandomColor() -> String {
        let r = UInt8.random(in: 128...255)  // Brighter colors
        let g = UInt8.random(in: 128...255)
        let b = UInt8.random(in: 128...255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    private func generateConsistentColor(for label: String) -> String {
        // If we already have a color for this label, return it
        if let existingColor = classColors[label] {
            return existingColor
        }
        
        // Get all currently used colors
        let usedColors = Set(classColors.values)
        
        // Try to find an unused color from the available colors
        if let unusedColor = Self.availableColors.first(where: { !usedColors.contains($0) }) {
            LogManager.shared.info("Assigned unused color \(unusedColor) to \(label)")
            return unusedColor
        }
        
        // If all colors are used, generate a visually distinct random color
        let newColor = generateRandomColor()
        LogManager.shared.info("Generated new random color \(newColor) for \(label)")
        return newColor
    }
} 