import CoreML
import Foundation

class ModelManager: ObservableObject {
    static let shared = ModelManager()
    
    // MARK: - Published Properties
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
    @Published var availableModels: [String] = []
    @Published var isSegmentationModel: Bool = false
    
    // MARK: - Private Properties
    private var customModels: [String: URL] {
        get {
            if let data = UserDefaults.standard.data(forKey: "customModels"),
               let paths = try? JSONDecoder().decode([String: String].self, from: data)
            {
                return paths.mapValues { URL(fileURLWithPath: $0) }
            }
            return [:]
        }
        set {
            let paths = newValue.mapValues { $0.path }
            if let data = try? JSONEncoder().encode(paths) {
                UserDefaults.standard.set(data, forKey: "customModels")
            }
        }
    }
    
    private init() {
        self.modelName = UserDefaults.standard.string(forKey: "modelName") ?? "yolov8n"
        loadAvailableModels()
    }
    
    // MARK: - Public Methods
    func loadAvailableModels() {
        var models: [String] = []
        
        // Log current custom models
        LogManager.shared.info("Current custom models: \(customModels)")
        
        // Scan main bundle for built-in models
        let bundleModels = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil)?
            .map { $0.deletingPathExtension().lastPathComponent } ?? []
        models.append(contentsOf: bundleModels)
        LogManager.shared.info("Found models in main bundle: \(bundleModels)")
        
        // Scan app's Resources directory
        if let appURL = Bundle.main.resourceURL?.appendingPathComponent("Contents/Resources") {
            do {
                let resourceContents = try FileManager.default.contentsOfDirectory(
                    at: appURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                
                let additionalModels = resourceContents
                    .filter { $0.pathExtension == "mlmodelc" }
                    .map { $0.deletingPathExtension().lastPathComponent }
                
                models.append(contentsOf: additionalModels)
                LogManager.shared.info("Found models in app Resources: \(additionalModels)")
            } catch {
                LogManager.shared.error("Error scanning app Resources directory", error: error)
            }
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
            
            let customModelNames = customModelURLs
                .filter { $0.pathExtension == "mlmodelc" }
                .map { $0.deletingPathExtension().lastPathComponent }
            
            // Update customModels dictionary
            for name in customModelNames {
                let url = modelsDir.appendingPathComponent("\(name).mlmodelc")
                if FileManager.default.fileExists(atPath: url.path) {
                    customModels[name] = url
                    LogManager.shared.info("Added custom model: \(name) at \(url.path)")
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
    
    private func loadModelMetadata() async {
        if let modelURL = findModel(),
           let model = try? MLModel(contentsOf: modelURL)
        {
            LogManager.shared.info("Model metadata: \(model.modelDescription.metadata)")
            
            // Check if this is a segmentation model
            let isSegmentation = model.modelDescription.outputDescriptionsByName.values.contains {
                output in
                if case .multiArray = output.type {
                    let name = output.name.lowercased()
                    return name.contains("mask") ||
                    name.contains("seg") ||
                    name == "p" ||
                    (name.contains("output") && output.multiArrayConstraint?.shape.count == 4)
                }
                return false
            }
            
            await MainActor.run {
                self.isSegmentationModel = isSegmentation
            }
            LogManager.shared.info("Model type: \(isSegmentation ? "segmentation" : "detection")")
            
            // Get class labels
            let classLabels = await extractClassLabels(from: model)
            
            // Update UI with model information
            await updateModelInfo(model: model, classLabels: classLabels, isSegmentation: isSegmentation)
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
    
    private func extractClassLabels(from model: MLModel) async -> [String] {
        // Try different metadata locations for class labels
        if let labels = model.modelDescription.metadata[MLModelMetadataKey(rawValue: "classes")] as? [String] {
            LogManager.shared.info("Found class labels in standard metadata")
            return labels
        }
        
        if let labels = model.modelDescription.classLabels as? [String] {
            LogManager.shared.info("Found class labels in model description")
            return labels
        }
        
        if let creatorMetadata = model.modelDescription.metadata[MLModelMetadataKey(rawValue: "MLModelCreatorDefinedKey")] as? [String: Any],
           let namesStr = creatorMetadata["names"] as? String
        {
            LogManager.shared.info("Found names in creator metadata: \(namesStr)")
            return parseCreatorDefinedLabels(namesStr)
        }
        
        return []
    }
    
    private func parseCreatorDefinedLabels(_ namesStr: String) -> [String] {
        let cleanStr = namesStr.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        let pairs = cleanStr.components(separatedBy: ", ")
        var indexedLabels: [Int: String] = [:]
        
        for pair in pairs {
            let components = pair.components(separatedBy: ": ")
            if components.count == 2 {
                let index = Int(components[0]) ?? -1
                let name = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                if index >= 0 {
                    indexedLabels[index] = name
                }
            }
        }
        
        return (0..<indexedLabels.count).compactMap { indexedLabels[$0] }
    }
    
    @MainActor
    private func updateModelInfo(model: MLModel, classLabels: [String], isSegmentation: Bool) {
        self.modelClasses = classLabels
        
        // Update description
        if let description = model.modelDescription.metadata[MLModelMetadataKey(rawValue: "MLModelDescriptionKey")] as? String {
            self.modelDescription = description
        } else {
            self.modelDescription = isSegmentation ? "YOLO segmentation model" : "YOLO detection model"
        }
        
        // Build metadata string
        var metadata = [String]()
        metadata.append("Format: CoreML")
        metadata.append("Type: \(isSegmentation ? "Segmentation" : "Detection")")
        
        if let version = model.modelDescription.metadata[MLModelMetadataKey(rawValue: "MLModelVersionStringKey")] as? String {
            metadata.append("Version: \(version)")
        }
        
        if let license = model.modelDescription.metadata[MLModelMetadataKey(rawValue: "MLModelLicenseKey")] as? String {
            metadata.append("License: \(license)")
        }
        
        if let inputFeature = model.modelDescription.inputDescriptionsByName.first?.value,
           case MLFeatureType.image = inputFeature.type,
           let constraint = inputFeature.imageConstraint {
            metadata.append("Input Size: \(Int(constraint.pixelsWide))x\(Int(constraint.pixelsHigh))")
        }
        
        self.modelMetadata = metadata.joined(separator: "\n")
        
        // Update colors for new classes
        ColorManager.shared.updateColors(for: classLabels)
    }
    
    private func findModel() -> URL? {
        // Check custom models first
        if let customModelURL = customModels[modelName] {
            LogManager.shared.info("Found custom model: \(customModelURL.lastPathComponent)")
            return customModelURL
        }
        
        // Check built-in models
        let formats = ["mlpackage", "mlmodelc"]
        
        for format in formats {
            if let url = Bundle.main.url(forResource: modelName, withExtension: format) {
                LogManager.shared.info("Found model in main bundle: \(url.lastPathComponent)")
                return url
            }
        }
        
        // Check Resources directory
        if let resourcesURL = Bundle.main.resourceURL?.appendingPathComponent("Contents/Resources") {
            for format in formats {
                let potentialURL = resourcesURL.appendingPathComponent("\(modelName).\(format)")
                if FileManager.default.fileExists(atPath: potentialURL.path) {
                    LogManager.shared.info("Found model in Resources directory: \(potentialURL.lastPathComponent)")
                    return potentialURL
                }
            }
        }
        
        LogManager.shared.error("Model not found: \(modelName)")
        return nil
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
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        return modelsDir
    }
    
    // MARK: - Custom Model Management
    func addCustomModel(name: String, url: URL) async throws {
        let modelsDirectory = try getOrCreateModelsDirectory()
        let modelName = name.replacingOccurrences(of: ".pt", with: "").replacingOccurrences(of: ".pth", with: "")
        let destinationURL = modelsDirectory.appendingPathComponent("\(modelName).mlmodelc")
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Create temporary directory for unzipping
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Save and unzip file
        let zipPath = tempDir.appendingPathComponent("model.zip")
        try data.write(to: zipPath)
        
        try await unzipAndCompileModel(at: zipPath, tempDir: tempDir, destinationURL: destinationURL, modelName: modelName)
    }
    
    private func unzipAndCompileModel(at zipPath: URL, tempDir: URL, destinationURL: URL, modelName: String) async throws {
        // Unzip the file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipPath.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()
        
        // Find and compile the model
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let mlpackage = contents.first(where: { $0.pathExtension == "mlpackage" }) else {
            throw ModelError.modelNotFound
        }
        
        let modelPath = mlpackage
            .appendingPathComponent("Data")
            .appendingPathComponent("com.apple.CoreML")
            .appendingPathComponent("model.mlmodel")
        
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ModelError.modelNotFound
        }
        
        // Remove existing model if it exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // Compile and move the model
        let compiledModelURL = try await MLModel.compileModel(at: modelPath)
        try FileManager.default.copyItem(at: compiledModelURL, to: destinationURL)
        
        // Verify the model
        guard (try? MLModel(contentsOf: destinationURL)) != nil else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw ModelError.modelLoadError(NSError(domain: "ModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load compiled model"]))
        }
        
        // Update custom models and reload
        customModels[modelName] = destinationURL
        await MainActor.run {
            loadAvailableModels()
        }
    }
    
    func removeCustomModel(_ name: String) throws {
        guard let modelURL = customModels[name] else {
            throw ModelError.modelNotFound
        }
        
        let isCurrentModel = modelName == name
        
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
        
        customModels.removeValue(forKey: name)
        
        if isCurrentModel {
            loadAvailableModels()
            if let firstModel = availableModels.first {
                modelName = firstModel
            }
        } else {
            loadAvailableModels()
        }
    }
    
    func getModelURL(for name: String) -> URL? {
        return customModels[name]
    }
    
    func isCustomModel(_ name: String) -> Bool {
        return customModels.keys.contains(name)
    }
} 