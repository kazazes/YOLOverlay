import SwiftUI
import UniformTypeIdentifiers

// Define custom UTType for PyTorch models
extension UTType {
  static let pytorchModel = UTType(importedAs: "com.pytorch.model")

  // Fallback types for PyTorch models
  static let pythonScript = UTType(filenameExtension: "pt")
  static let pytorch = UTType(filenameExtension: "pth")
}

struct PreferencesView: View {
  @ObservedObject private var settings = Settings.shared
  @State private var selectedTab = 0
  @ObservedObject private var captureManager = ScreenCaptureManager.shared

  var body: some View {
    TabView(selection: $selectedTab) {
      ModelSettingsView(settings: settings)
        .tabItem {
          Label("Models", systemImage: "cube.box")
        }
        .tag(0)

      // Detection Settings
      VStack(alignment: .leading, spacing: 16) {
        PerformanceSettingsView(settings: settings)
      }
      .padding()
      .tabItem {
        Label("Detection", systemImage: "rectangle.dashed")
      }
      .tag(1)

      // Appearance Settings
      AppearanceSettingsView(settings: settings)
        .padding()
        .tabItem {
          Label("Appearance", systemImage: "paintbrush")
        }
        .tag(2)

      if settings.isSegmentationModel {
        // Segmentation Settings
        VStack(alignment: .leading, spacing: 16) {
          Text("Segmentation Settings")
            .font(.headline)

          VStack(alignment: .leading) {
            Text("Opacity: \(Int(settings.segmentationOpacity * 100))%")
            Slider(value: $settings.segmentationOpacity, in: 0...1)
          }

          Picker("Color Mode", selection: $settings.segmentationColorMode) {
            Text("Class-based").tag("class")
            Text("Confidence-based").tag("confidence")
          }
          .pickerStyle(SegmentedPickerStyle())
        }
        .padding()
        .tabItem {
          Label("Segmentation", systemImage: "paintbrush.fill")
        }
        .tag(3)
      }

      // Citation
      CitationView()
        .padding()
        .tabItem {
          Label("About", systemImage: "info.circle")
        }
        .tag(4)
    }
    .frame(width: 500, height: 600)
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        CaptureButton(captureManager: captureManager)
      }
    }
  }
}

// MARK: - Sidebar
private struct PreferencesSidebar: View {
  @Binding var selectedTab: String

  var body: some View {
    List(selection: $selectedTab) {
      Text("Model").tag("Model")
      Text("Performance").tag("Performance")
      Text("Appearance").tag("Appearance")
      Text("Citation").tag("Citation")
    }
    .listStyle(.sidebar)
  }
}

// MARK: - Detail View
private struct PreferencesDetail: View {
  let selectedTab: String
  @ObservedObject var settings: Settings
  @ObservedObject var captureManager: ScreenCaptureManager

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        switch selectedTab {
        case "Model":
          ModelSettingsView(settings: settings)
        case "Performance":
          PerformanceSettingsView(settings: settings)
        case "Appearance":
          AppearanceSettingsView(settings: settings)
        case "Citation":
          CitationView()
        default:
          EmptyView()
        }
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .toolbar {
      CaptureButton(captureManager: captureManager)
    }
  }
}

// MARK: - Capture Button
private struct CaptureButton: View {
  @ObservedObject var captureManager: ScreenCaptureManager

  var body: some View {
    Button(action: toggleCapture) {
      Label(
        captureManager.isRecording ? "Stop Detection" : "Start Detection",
        systemImage: captureManager.isRecording ? "stop.circle" : "play.circle"
      )
    }
    .help(captureManager.isRecording ? "Stop object detection" : "Start object detection")
  }

  private func toggleCapture() {
    Task {
      if captureManager.isRecording {
        await captureManager.stopCapture()
      } else {
        await captureManager.startCapture()
      }
    }
  }
}

// MARK: - Detected Classes Grid
private struct DetectedClassesGrid: View {
  @ObservedObject var settings: Settings
  let classes: [String]

  var body: some View {
    GroupBox("Detected Classes (\(classes.count))") {
      if classes.isEmpty {
        Text("No classes available")
          .foregroundColor(.secondary)
          .padding()
      } else {
        ScrollView {
          ClassGridContent(classes: classes, classColors: settings.classColors)
        }
        .frame(maxHeight: 300)  // Set a max height for scrolling
      }
    }
  }
}

// MARK: - Class Grid Content
private struct ClassGridContent: View {
  let classes: [String]
  let classColors: [String: String]

  var body: some View {
    LazyVGrid(
      columns: [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 8)
      ],
      spacing: 8
    ) {
      ForEach(classes, id: \.self) { className in
        ClassGridItem(className: className, colorHex: classColors[className] ?? "#FF0000")
      }
    }
    .padding(8)
  }
}

// MARK: - Class Grid Item
private struct ClassGridItem: View {
  let className: String
  let colorHex: String

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(getColorFromString(colorHex))
        .frame(width: 8, height: 8)
      Text(className)
        .font(.system(size: 12))
        .lineLimit(1)
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.controlBackgroundColor))
    .cornerRadius(4)
  }
  
  private func getColorFromString(_ colorString: String) -> Color {
    // First try as a named color
    switch colorString.lowercased() {
    case "red": return .red
    case "blue": return .blue
    case "green": return .green
    case "yellow": return .yellow
    case "orange": return .orange
    case "purple": return .purple
    case "pink": return .pink
    case "teal": return .teal
    case "indigo": return .indigo
    case "mint": return .mint
    case "brown": return .brown
    case "cyan": return .cyan
    default:
      // If not a named color, try as hex
      if colorString.hasPrefix("#") {
        return Color(hex: colorString) ?? .red
      }
      return .red
    }
  }
}

// MARK: - Model Settings View
struct ModelSettingsView: View {
  @ObservedObject var settings: Settings
  @State private var isShowingFilePicker = false
  @State private var isUploading = false
  @State private var uploadError: String?
  @State private var showingDeleteAlert = false
  @State private var modelToDelete: String?

  var body: some View {
    Form {
      GroupBox("Model Selection") {
        VStack(alignment: .leading, spacing: 12) {
          // Model List
          List(settings.availableModels, id: \.self, selection: $settings.modelName) { model in
            HStack {
              // Model name and type
              VStack(alignment: .leading) {
                Text(model)
                  .fontWeight(settings.modelName == model ? .bold : .regular)
                Text(settings.isCustomModel(model) ? "Custom Model" : "Built-in Model")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }

              Spacer()

              // Delete button for custom models
              if settings.isCustomModel(model) {
                Button(action: {
                  modelToDelete = model
                  showingDeleteAlert = true
                }) {
                  Image(systemName: "trash")
                    .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
              }
            }
            .padding(.vertical, 4)
          }
          .frame(height: 200)
          .background(Color(.textBackgroundColor))
          .cornerRadius(8)

          Divider()

          // Add Custom Model Button
          Button(action: { isShowingFilePicker = true }) {
            Label("Import Custom Model", systemImage: "square.and.arrow.down")
          }
          .disabled(isUploading)

          if isUploading {
            ProgressView("Converting model...")
          }

          if let error = uploadError {
            Text(error)
              .foregroundColor(.red)
              .font(.caption)
          }
        }
      }

      if !settings.modelDescription.isEmpty {
        GroupBox("Description") {
          Text(settings.modelDescription)
            .font(.system(.body, design: .monospaced))
        }
      }

      if !settings.modelMetadata.isEmpty {
        GroupBox("Model Information") {
          Text(settings.modelMetadata)
            .font(.system(.body, design: .monospaced))
        }
      }

      GroupBox("Detected Classes") {
        DetectedClassesGrid(settings: settings, classes: settings.modelClasses)
      }
    }
    .padding()
    .fileImporter(
      isPresented: $isShowingFilePicker,
      allowedContentTypes: [
        .pytorchModel,
        .pythonScript ?? .data,
        .pytorch ?? .data,
      ].compactMap { $0 },
      allowsMultipleSelection: false
    ) { result in
      Task {
        await handleModelSelection(result)
      }
    }
    .alert("Delete Model", isPresented: $showingDeleteAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        if let model = modelToDelete {
          do {
            try settings.removeCustomModel(model)
          } catch {
            uploadError = "Failed to delete model: \(error.localizedDescription)"
          }
        }
      }
    } message: {
      if let model = modelToDelete {
        Text("Are you sure you want to delete '\(model)'? This action cannot be undone.")
      }
    }
  }

  private func handleModelSelection(_ result: Result<[URL], Error>) async {
    do {
      let urls = try result.get()
      guard let selectedFile = urls.first else { return }

      // Verify file extension
      guard
        selectedFile.pathExtension.lowercased() == "pt"
          || selectedFile.pathExtension.lowercased() == "pth"
      else {
        await MainActor.run {
          uploadError = "Invalid file type. Please select a .pt or .pth file."
        }
        return
      }

      await MainActor.run {
        isUploading = true
        uploadError = nil
      }

      // Start file access coordination
      guard selectedFile.startAccessingSecurityScopedResource() else {
        throw NSError(
          domain: "ModelService", code: -1,
          userInfo: [
            NSLocalizedDescriptionKey: "Permission denied: Cannot access the selected file"
          ])
      }

      defer {
        selectedFile.stopAccessingSecurityScopedResource()
      }

      // Upload model
      let modelService = ModelService.shared
      let downloadURL = try await modelService.uploadModel(fileURL: selectedFile)

      // Add model to available models and select it
      try await settings.addCustomModel(name: selectedFile.lastPathComponent, url: downloadURL)

      await MainActor.run {
        settings.modelName = selectedFile.lastPathComponent.replacingOccurrences(
          of: ".pt", with: ""
        ).replacingOccurrences(of: ".pth", with: "")
      }

    } catch {
      await MainActor.run {
        uploadError = "Failed to process model: \(error.localizedDescription)"
      }
    }

    await MainActor.run {
      isUploading = false
    }
  }
}

// MARK: - Performance Settings View
struct PerformanceSettingsView: View {
  @ObservedObject var settings: Settings

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("Frame Rate") {
        VStack(alignment: .leading) {
          HStack {
            Text("Target FPS")
            Spacer()
            Text("\(Int(settings.targetFPS))")
          }
          Slider(value: $settings.targetFPS, in: 1...60, step: 1)
        }
      }

      GroupBox("Detection") {
        VStack(alignment: .leading) {
          HStack {
            Text("Confidence Threshold")
            Spacer()
            Text(String(format: "%.2f", settings.confidenceThreshold))
          }
          Slider(value: $settings.confidenceThreshold, in: 0...1, step: 0.05)
        }
      }

      GroupBox("Smoothing") {
        VStack(alignment: .leading, spacing: 12) {
          Toggle("Enable Smoothing", isOn: $settings.enableSmoothing)

          if settings.enableSmoothing {
            VStack(alignment: .leading, spacing: 12) {
              VStack(alignment: .leading) {
                HStack {
                  Text("Smoothing Factor")
                  Spacer()
                  Text(String(format: "%.2f", settings.smoothingFactor))
                }
                Slider(value: $settings.smoothingFactor, in: 0.1...0.9, step: 0.1)
              }

              VStack(alignment: .leading) {
                HStack {
                  Text("Object Persistence")
                  Spacer()
                  Text(String(format: "%.1fs", settings.objectPersistence))
                }
                Slider(value: $settings.objectPersistence, in: 0.1...2.0, step: 0.1)
              }

              Text(
                "Higher smoothing values mean more responsive but potentially jittery tracking. Lower values are smoother but have more latency."
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }
          }
        }
      }
    }
  }
}

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
  @ObservedObject var settings: Settings

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("Display") {
        Toggle("Show Labels", isOn: $settings.showLabels)
      }

      GroupBox("Bounding Box") {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Default Color")
            Spacer()
            Picker("", selection: $settings.boundingBoxColor) {
              ForEach(Settings.availableColors, id: \.self) { color in
                HStack {
                  Circle()
                    .fill(getColor(color))
                    .frame(width: 12, height: 12)
                  Text(color.capitalized)
                }
                .tag(color)
              }
            }
            .frame(width: 120)
          }

          VStack(alignment: .leading) {
            HStack {
              Text("Opacity")
              Spacer()
              Text(String(format: "%.1f", settings.boundingBoxOpacity))
            }
            Slider(value: $settings.boundingBoxOpacity, in: 0.1...1, step: 0.1)
          }
        }
      }
    }
  }
}

// MARK: - Citation View
struct CitationView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("About") {
        VStack(alignment: .leading, spacing: 12) {
          Text("This application uses YOLO11 by Ultralytics")
            .font(.headline)

          Text(
            "YOLO11 is a state-of-the-art object detection model that powers the core functionality of this application."
          )
          .font(.subheadline)
          .foregroundColor(.secondary)
        }
      }

      GroupBox("Authors & Version") {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Authors")
              .font(.subheadline)
              .foregroundColor(.secondary)
            Text("Glenn Jocher & Jing Qiu")
              .font(.body)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Version")
              .font(.subheadline)
              .foregroundColor(.secondary)
            Text("11.0.0 (2024)")
              .font(.body)
          }
        }
      }

      GroupBox("Links & License") {
        VStack(alignment: .leading, spacing: 12) {
          Link(
            "View on GitHub",
            destination: URL(string: "https://github.com/ultralytics/ultralytics")!
          )
          .font(.body)

          Text("Licensed under AGPL-3.0")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }
    }
  }
}

// MARK: - Helper Functions
private func getColor(_ name: String) -> Color {
  switch name.lowercased() {
  case "red": return .red
  case "blue": return .blue
  case "green": return .green
  case "yellow": return .yellow
  case "orange": return .orange
  case "purple": return .purple
  case "pink": return .pink
  case "teal": return .teal
  case "indigo": return .indigo
  case "mint": return .mint
  case "brown": return .brown
  case "cyan": return .cyan
  default: return .red
  }
}

#Preview {
  PreferencesView()
}
