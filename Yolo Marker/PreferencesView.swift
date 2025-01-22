import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var settings = Settings.shared

  private let availableColors = ["red", "blue", "green", "yellow", "orange", "purple"]
  private let availableFPS = [15.0, 30.0, 60.0]

  var body: some View {
    Form {
      Section("Performance") {
        Picker("Target FPS", selection: $settings.targetFPS) {
          ForEach(availableFPS, id: \.self) { fps in
            Text("\(Int(fps)) FPS").tag(fps)
          }
        }

        HStack {
          Text("Confidence Threshold")
          Slider(
            value: $settings.confidenceThreshold,
            in: 0.1...1.0,
            step: 0.1
          )
          Text("\(Int(settings.confidenceThreshold * 100))%")
        }
      }

      Section("Appearance") {
        Toggle("Show Labels", isOn: $settings.showLabels)

        Picker("Bounding Box Color", selection: $settings.boundingBoxColor) {
          ForEach(availableColors, id: \.self) { color in
            Text(color.capitalized).tag(color)
          }
        }

        HStack {
          Text("Box Opacity")
          Slider(
            value: $settings.boundingBoxOpacity,
            in: 0.1...1.0,
            step: 0.1
          )
          Text("\(Int(settings.boundingBoxOpacity * 100))%")
        }
      }
    }
    .padding()
    .frame(width: 350, height: 250)
  }
}

#Preview {
  PreferencesView()
}
