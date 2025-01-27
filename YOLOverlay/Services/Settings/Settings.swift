import CoreML
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
                UserDefaults.standard.set(modelName, forKey: "modelName")
                NotificationCenter.default.post(name: .modelChanged, object: nil)
                Task { @MainActor in
                    await loadModelMetadata()
                }
            }
        }
    }
    @Published var modelDescription: String = ""
    @Published var modelClasses: [String] = []
    @Published var modelMetadata: String = ""
    @Published var classColors: [String: String] = [:]
    @Published var availableModels: [String] = []
    @Published var isSegmentationModel: Bool = false

    // Segmentation settings
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

    // Custom models storage
    private var customModels: [String: URL] {
        get {
            if let data = UserDefaults.standard.data(forKey: "customModels"),
               let paths = try? JSONDecoder().decode([String: String].self, from: data)
            {
                // Convert paths back to URLs
                var models: [String: URL] = [:]
                for (name, path) in paths {
                    models[name] = URL(fileURLWithPath: path)
                }
                return models
            }
            return [:]
        }
        set {
            // Convert URLs to paths for storage
            let paths = newValue.mapValues { $0.path }
            if let data = try? JSONEncoder().encode(paths) {
                UserDefaults.standard.set(data, forKey: "customModels")
            }
        }
    }

    // Add persistent class colors storage
    private var persistentClassColors: [String: String] {
        get {
            return UserDefaults.standard.dictionary(forKey: "persistentClassColors") as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "persistentClassColors")
        }
    }

    private(set) var minimumFrameInterval: TimeInterval

    static let shared = Settings()

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

    private func generateRandomColor() -> String {
        let r = UInt8.random(in: 128...255)  // Brighter colors
        let g = UInt8.random(in: 128...255)
        let b = UInt8.random(in: 128...255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    @MainActor
    func generateConsistentColor(for label: String) -> String {
        // If we already have a color for this label, return it
        if let existingColor = classColors[label] {
            return existingColor
        }

        // Get all currently used colors
        let usedColors = Set(classColors.values)

        // Try to find an unused color from the available colors
        if let unusedColor = Self.availableColors.first(where: { !usedColors.contains($0) }) {
            classColors[label] = unusedColor
            LogManager.shared.info("Assigned unused color \(unusedColor) to \(label)")
            return unusedColor
        }

        // If all colors are used, generate a visually distinct random color
        let newColor = generateRandomColor()
        classColors[label] = newColor
        LogManager.shared.info("Generated new random color \(newColor) for \(label)")
        return newColor
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

        // Initialize segmentation settings
        self.segmentationOpacity = UserDefaults.standard.double(forKey: "segmentationOpacity")
            .nonZeroValue(defaultValue: 0.5)
        self.segmentationColorMode =
        UserDefaults.standard.string(forKey: "segmentationColorMode") ?? "class"
        self.isSegmentationModel = false

        // Initialize model name with a default value
        self.modelName = UserDefaults.standard.string(forKey: "modelName") ?? "yolov8n"
        self.modelDescription = ""

        // Load persistent class colors
        if let persistentColors = UserDefaults.standard.dictionary(forKey: "persistentClassColors")
            as? [String: String]
        {
            self.classColors = persistentColors
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

        // Log current custom models
        LogManager.shared.info("Current custom models: \(customModels)")

        // First scan main bundle for built-in models

        let bundleModels =
        Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil)?
            .map { $0.deletingPathExtension().lastPathComponent } ?? []
        models.append(contentsOf: bundleModels)
        LogManager.shared.info("Found models in main bundle: \(bundleModels)")


        // Then scan app's Resources directory
        let appURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
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

        // Add custom models from Application Support
        do {
            let modelsDir = try getOrCreateModelsDirectory()
            LogManager.shared.info("Checking models directory: \(modelsDir.path)")

            let customModelURLs = try FileManager.default.contentsOfDirectory(
                at: modelsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let customModelNames =
            customModelURLs
                .filter { $0.pathExtension == "mlmodelc" }
                .map { $0.deletingPathExtension().lastPathComponent }

            // Update customModels dictionary
            for name in customModelNames {
                let url = modelsDir.appendingPathComponent("\(name).mlmodelc")
                if FileManager.default.fileExists(atPath: url.path) {
                    customModels[name] = url
                    LogManager.shared.info("Added custom model: \(name) at \(url.path)")
                } else {
                    LogManager.shared.error("Custom model file not found: \(url.path)")
                }
            }

            models.append(contentsOf: customModelNames)
            LogManager.shared.info("Found custom models: \(customModelNames)")
        } catch {
            LogManager.shared.error("Error scanning custom models directory", error: error)
        }

        // Remove duplicates and sort
        availableModels = Array(Set(models)).sorted()
        LogManager.shared.info("Final available models: \(availableModels)")

        // If current model is not in available models, select first available
        if !availableModels.isEmpty && !availableModels.contains(modelName) {
            modelName = availableModels[0]
            LogManager.shared.info("Selected default model: \(modelName)")
        }
    }

    @MainActor
    func updateModelInfo(
        modelClasses: [String],
        isSegmentation: Bool = false
    ) {
        self.modelClasses = modelClasses
        self.isSegmentationModel = isSegmentation

        // Clear existing colors for a fresh start
        classColors.removeAll()

        // Generate colors for all classes
        for label in modelClasses {
            classColors[label] = generateConsistentColor(for: label)
        }

        LogManager.shared.info("Generated class colors: \(classColors)")
    }

    func getColorForClass(_ className: String) -> String {
        return classColors[className] ?? boundingBoxColor
    }

    private func findModel() -> URL? {
        // First check if it's a custom model
        if let customModelURL = customModels[modelName] {
            LogManager.shared.info("Found custom model: \(customModelURL.lastPathComponent)")
            return customModelURL
        }

        // If not a custom model, check built-in models
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
        }

        LogManager.shared.error("Model not found: \(modelName)")
        return nil
    }

    private func loadModelMetadata() async {
        // Try to load the model to check its type and metadata
        if let modelURL = findModel(),
           let model = try? MLModel(contentsOf: modelURL)
        {
            LogManager.shared.info("Model metadata: \(model.modelDescription.metadata)")

            // Check if this is a segmentation model by looking at outputs
            let isSegmentation = model.modelDescription.outputDescriptionsByName.values.contains {
                output in
                if case .multiArray = output.type {
                    // Check for common segmentation output names
                    let name = output.name.lowercased()
                    return name.contains("mask") ||
                    name.contains("seg") ||
                    name == "p" ||  // For this specific model format
                    (name.contains("output") && output.multiArrayConstraint?.shape.count == 4)  // For YOLO segmentation models
                }
                return false
            }

            // Update model type
            await MainActor.run {
                self.isSegmentationModel = isSegmentation
            }
            LogManager.shared.info("Model type: \(isSegmentation ? "segmentation" : "detection")")

            // Try to get class labels from different metadata locations
            var classLabels: [String] = []

            // First try standard CoreML metadata
            if let labels = model.modelDescription.metadata[MLModelMetadataKey(rawValue: "classes")]
                as? [String]
            {
                classLabels = labels
                LogManager.shared.info("Found class labels in standard metadata")
            }
            // Then try the model's classLabels
            else if let labels = model.modelDescription.classLabels as? [String] {
                classLabels = labels
                LogManager.shared.info("Found class labels in model description")
            }
            // Finally try the creator defined metadata (used by this segmentation model)
            else if let creatorMetadata = model.modelDescription.metadata[
                MLModelMetadataKey(rawValue: "MLModelCreatorDefinedKey")] as? [String: Any],
                    let namesStr = creatorMetadata["names"] as? String
            {
                // Parse the names dictionary string
                // Format is like: "{0: 'hair', 1: 'face', ...}"
                LogManager.shared.info("Found names in creator metadata: \(namesStr)")

                // Remove the curly braces
                let cleanStr = namesStr.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))

                // Split into individual key-value pairs
                let pairs = cleanStr.components(separatedBy: ", ")

                // Create a dictionary to store index-name pairs
                var indexedLabels: [Int: String] = [:]

                // Parse each pair
                for pair in pairs {
                    let components = pair.components(separatedBy: ": ")
                    if components.count == 2 {
                        let index = Int(components[0]) ?? -1
                        // Remove quotes from the name
                        let name = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                        if index >= 0 {
                            indexedLabels[index] = name
                        }
                    }
                }

                // Convert to ordered array
                classLabels = (0..<indexedLabels.count).compactMap { indexedLabels[$0] }
                LogManager.shared.info("Parsed class labels: \(classLabels)")
            }

            await MainActor.run {
                self.modelClasses = classLabels
            }
            LogManager.shared.info("Final class labels: \(classLabels)")

            // Update colors for all classes
            await updateModelInfo(modelClasses: classLabels, isSegmentation: isSegmentation)

            // Set description from metadata
            let description: String
            if let metadataDesc = model.modelDescription.metadata[
                MLModelMetadataKey(rawValue: "MLModelDescriptionKey")] as? String
            {
                description = metadataDesc
            } else {
                description = isSegmentation ? "YOLO segmentation model" : "YOLO detection model"
            }

            // Build metadata string
            var metadata = [String]()
            metadata.append("Format: CoreML")
            metadata.append("Type: \(isSegmentation ? "Segmentation" : "Detection")")

            // Add version if available
            if let version = model.modelDescription.metadata[
                MLModelMetadataKey(rawValue: "MLModelVersionStringKey")] as? String
            {
                metadata.append("Version: \(version)")
            }

            // Add license if available
            if let license = model.modelDescription.metadata[
                MLModelMetadataKey(rawValue: "MLModelLicenseKey")] as? String
            {
                metadata.append("License: \(license)")
            }

            // Get input image size
            if let inputFeature = model.modelDescription.inputDescriptionsByName.first?.value {
                if case MLFeatureType.image = inputFeature.type {
                    if let constraint = inputFeature.imageConstraint {
                        metadata.append(
                            "Input Size: \(Int(constraint.pixelsWide))x\(Int(constraint.pixelsHigh))")
                    }
                }
            }

            let metadataString = metadata.joined(separator: "\n")

            // Generate colors for classes if needed
            var updatedColors = self.classColors
            for className in classLabels {
                if updatedColors[className] == nil {
                    updatedColors[className] = Settings.availableColors.randomElement() ?? "red"
                }
            }

            await MainActor.run {
                self.modelDescription = description
                self.modelMetadata = metadataString
                self.classColors = updatedColors
                // Save class colors
                UserDefaults.standard.set(updatedColors, forKey: "classColors")
            }
        } else {
            LogManager.shared.error("Failed to load model for metadata extraction")
            await MainActor.run {
                self.modelDescription = "Failed to load model"
                self.modelMetadata = "Error: Model could not be loaded"
                self.modelClasses = []
                self.isSegmentationModel = false
            }
        }
    }

    func addCustomModel(name: String, url: URL) async throws {
        // Create models directory if it doesn't exist
        let modelsDirectory = try getOrCreateModelsDirectory()
        let modelName = name.replacingOccurrences(of: ".pt", with: "").replacingOccurrences(
            of: ".pth", with: "")
        let destinationURL = modelsDirectory.appendingPathComponent("\(modelName).mlmodelc")

        // Download and save the model
        let (data, _) = try await URLSession.shared.data(from: url)

        // Create a temporary directory for unzipping
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Save zip file
        let zipPath = tempDir.appendingPathComponent("model.zip")
        try data.write(to: zipPath)

        // Unzip the file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipPath.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        // Find the .mlpackage directory in the unzipped contents
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )

        // Look for the .mlpackage directory
        guard let mlpackage = contents.first(where: { $0.pathExtension == "mlpackage" }) else {
            throw NSError(
                domain: "Settings",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No .mlpackage found in downloaded file"]
            )
        }

        // Find the model file inside the .mlpackage/Data/com.apple.CoreML directory
        let modelPath =
        mlpackage
            .appendingPathComponent("Data")
            .appendingPathComponent("com.apple.CoreML")
            .appendingPathComponent("model.mlmodel")

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw NSError(
                domain: "Settings",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not find model.mlmodel in .mlpackage/Data/com.apple.CoreML"
                ]
            )
        }

        // Remove existing model if it exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        // Compile the model
        do {
            let compiledModelURL = try await MLModel.compileModel(at: modelPath)

            // Move the compiled model to the models directory
            try FileManager.default.copyItem(at: compiledModelURL, to: destinationURL)

            // Update custom models
            customModels[modelName] = destinationURL

            // Try to load the model to verify it works
            guard (try? MLModel(contentsOf: destinationURL)) != nil else {
                // If loading fails, clean up and throw error
                try? FileManager.default.removeItem(at: destinationURL)
                customModels.removeValue(forKey: modelName)
                throw NSError(
                    domain: "Settings",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load compiled model"]
                )
            }

            // Reload available models
            await MainActor.run {
                loadAvailableModels()
            }
        } catch {
            throw NSError(
                domain: "Settings",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to compile model: \(error.localizedDescription)"
                ]
            )
        }
    }

    private func getOrCreateModelsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelsDir = appSupport.appendingPathComponent("Models")

        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try FileManager.default.createDirectory(
                at: modelsDir,
                withIntermediateDirectories: true
            )
        }

        return modelsDir
    }

    func removeCustomModel(_ name: String) throws {
        // Check if it's a custom model
        guard let modelURL = customModels[name] else {
            throw NSError(
                domain: "Settings",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not a custom model: \(name)"]
            )
        }

        // Check if the model is currently selected
        let isCurrentModel = modelName == name

        // Remove the model file
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }

        // Remove from custom models dictionary
        customModels.removeValue(forKey: name)

        // If this was the current model, switch to another available model
        if isCurrentModel {
            loadAvailableModels()  // This will refresh the list
            if let firstModel = availableModels.first {
                modelName = firstModel
            }
        } else {
            loadAvailableModels()  // Just refresh the list
        }
    }

    func getModelURL(for name: String) -> URL? {
        return customModels[name]
    }

    func isCustomModel(_ name: String) -> Bool {
        return customModels.keys.contains(name)
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

// MARK: - Color Helpers
extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return "#FF0000"  // Fallback to red
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: nil)

        let hex = String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
        return hex
    }

    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        switch hex.count {
        case 3:  // RGB (12-bit)
            r = CGFloat((int >> 8) & 0xF) / 15.0
            g = CGFloat((int >> 4) & 0xF) / 15.0
            b = CGFloat(int & 0xF) / 15.0
        case 6:  // RGB (24-bit)
            r = CGFloat((int >> 16) & 0xFF) / 255.0
            g = CGFloat((int >> 8) & 0xFF) / 255.0
            b = CGFloat(int & 0xFF) / 255.0
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
