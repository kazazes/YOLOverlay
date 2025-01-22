import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var settings = Settings.shared
  @State private var selectedTab = "Model"

  var body: some View {
    NavigationSplitView {
      // Sidebar
      List(selection: $selectedTab) {
        Text("Model").tag("Model")
        Text("Performance").tag("Performance")
        Text("Appearance").tag("Appearance")
        Text("Classes").tag("Classes")
      }
      .listStyle(.sidebar)
    } detail: {
      // Detail View
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          switch selectedTab {
          case "Model":
            ModelSettingsView(settings: settings)
          case "Performance":
            PerformanceSettingsView(settings: settings)
          case "Appearance":
            AppearanceSettingsView(settings: settings)
          case "Classes":
            ClassesView(settings: settings)
          default:
            EmptyView()
          }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
  }
}

// MARK: - Model Settings View
struct ModelSettingsView: View {
  @ObservedObject var settings: Settings

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("Model Selection") {
        Picker("Model", selection: $settings.modelName) {
          ForEach(settings.availableModels, id: \.self) { model in
            Text(model).tag(model)
          }
        }
        .disabled(settings.availableModels.isEmpty)

        if settings.availableModels.isEmpty {
          Text("No models found. Please add YOLO models to the application bundle.")
            .foregroundColor(.secondary)
        }
      }

      GroupBox("Model Information") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Model: \(settings.modelName)")
            .font(.headline)

          Text("Description:")
            .font(.subheadline)
          Text(settings.modelDescription)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
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

// MARK: - Classes View
struct ClassesView: View {
  @ObservedObject var settings: Settings

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("Detected Classes") {
        if settings.modelClasses.isEmpty {
          Text("No classes available")
            .foregroundColor(.secondary)
        } else {
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
          ) {
            ForEach(settings.modelClasses, id: \.self) { className in
              HStack(spacing: 6) {
                Circle()
                  .fill(getColor(settings.getColorForClass(className)))
                  .frame(width: 8, height: 8)
                Text(className)
                  .font(.system(size: 11))
                  .lineLimit(1)
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 6)
              .padding(.vertical, 4)
              .background(Color(NSColor.controlBackgroundColor))
              .cornerRadius(4)
            }
          }
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
