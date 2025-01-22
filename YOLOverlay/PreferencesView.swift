import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var settings = Settings.shared
  @State private var selectedTab = "Model"
  @ObservedObject private var captureManager = ScreenCaptureManager.shared

  var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      PreferencesSidebar(selectedTab: $selectedTab)
    } detail: {
      PreferencesDetail(
        selectedTab: selectedTab, settings: settings, captureManager: captureManager)
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
  let classes: [String]

  var body: some View {
    GroupBox("Detected Classes (\(classes.count))") {
      if classes.isEmpty {
        Text("No classes available")
          .foregroundColor(.secondary)
          .padding()
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
          ForEach(classes, id: \.self) { className in
            HStack(spacing: 4) {
              Circle()
                .fill(generateRandomColor())
                .frame(width: 8, height: 8)
              Text(className)
                .font(.system(size: 12))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(4)
          }
        }
        .padding(8)
      }
    }
  }

  private func generateRandomColor() -> Color {
    Color(
      red: Double.random(in: 0.5...1.0),
      green: Double.random(in: 0.5...1.0),
      blue: Double.random(in: 0.5...1.0)
    )
  }
}

// MARK: - Model Settings View
struct ModelSettingsView: View {
  @ObservedObject var settings: Settings

  var body: some View {
    Form {
      GroupBox("Model Selection") {
        Picker("Model", selection: $settings.modelName) {
          ForEach(settings.availableModels, id: \.self) { model in
            Text(model).tag(model)
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
        DetectedClassesGrid(classes: settings.modelClasses)
      }
    }
    .padding()
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
