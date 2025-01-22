import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var settings = Settings.shared

  var body: some View {
    HStack(spacing: 0) {
      // Left side - Settings
      VStack(spacing: 0) {
        List {
          Section("Model Selection") {
            VStack(alignment: .leading, spacing: 8) {
              Picker("Model", selection: $settings.modelName) {
                ForEach(settings.availableModels) { model in
                  HStack {
                    VStack(alignment: .leading) {
                      Text(model.displayName)
                        .font(.headline)
                      Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                  }
                  .tag(model.name)
                }
              }
              .pickerStyle(.inline)

              if settings.availableModels.isEmpty {
                Text("No models available. Use convert_yolo.py to add models.")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .listRowInsets(EdgeInsets())
          }

          Section("Model Information") {
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
            .listRowInsets(EdgeInsets())
          }

          Section("Performance") {
            VStack(spacing: 10) {
              VStack(alignment: .leading) {
                HStack {
                  Text("Target FPS")
                  Spacer()
                  Text("\(Int(settings.targetFPS))")
                }
                Slider(value: $settings.targetFPS, in: 1...60, step: 1)
              }

              VStack(alignment: .leading) {
                HStack {
                  Text("Confidence")
                  Spacer()
                  Text(String(format: "%.2f", settings.confidenceThreshold))
                }
                Slider(value: $settings.confidenceThreshold, in: 0...1, step: 0.05)
              }
            }
            .listRowInsets(EdgeInsets())
          }

          Section("Appearance") {
            Toggle("Show Labels", isOn: $settings.showLabels)

            VStack(alignment: .leading, spacing: 10) {
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
            .listRowInsets(EdgeInsets())
          }
        }
      }
      .frame(width: 300)

      // Divider
      Divider()

      // Right side - Class List
      VStack(alignment: .leading) {
        Text("Detected Classes")
          .font(.headline)
          .padding()

        ScrollView {
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
          .padding(8)
        }
      }
      .frame(minWidth: 400)
      .background(Color(NSColor.controlBackgroundColor))
    }
    .frame(minWidth: 700, minHeight: 500)
  }

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
}

#Preview {
  PreferencesView()
}
