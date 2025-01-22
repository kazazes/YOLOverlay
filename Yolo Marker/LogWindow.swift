import OSLog
import SwiftUI

struct LogWindow: View {
  @ObservedObject private var logManager = LogManager.shared
  @State private var searchText = ""
  @State private var selectedTypes: Set<OSLogEntryLog.Level> = Set([.info, .notice, .error, .fault])

  var filteredLogs: [LogEntry] {
    logManager.logEntries.filter { entry in
      let matchesSearch =
        searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
      let matchesType = selectedTypes.contains(entry.type)
      return matchesSearch && matchesType
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Toolbar
      HStack {
        Image(systemName: "line.3.horizontal.circle")
          .foregroundColor(.secondary)
        TextField("Search logs...", text: $searchText)
          .textFieldStyle(.roundedBorder)

        Menu {
          ForEach(OSLogEntryLog.Level.allCases, id: \.self) { type in
            Toggle(
              isOn: Binding(
                get: { selectedTypes.contains(type) },
                set: { isOn in
                  if isOn {
                    selectedTypes.insert(type)
                  } else {
                    selectedTypes.remove(type)
                  }
                }
              )
            ) {
              Label(type.description, systemImage: "circle.fill")
                .foregroundColor(LogEntry(message: "", timestamp: Date(), type: type).typeColor)
            }
          }
        } label: {
          Image(systemName: "line.3.horizontal.decrease.circle")
            .foregroundColor(.secondary)
        }

        Button(action: { logManager.logEntries.removeAll() }) {
          Image(systemName: "trash")
            .foregroundColor(.secondary)
        }
        .help("Clear logs")
      }
      .padding()
      .background(Color(NSColor.controlBackgroundColor))

      // Log list
      ScrollViewReader { proxy in
        List(filteredLogs.reversed()) { entry in
          LogEntryRow(entry: entry)
            .id(entry.id)
        }
        .onChange(of: filteredLogs.count) { _ in
          if let lastId = filteredLogs.first?.id {
            proxy.scrollTo(lastId)
          }
        }
      }
    }
    .frame(minWidth: 600, minHeight: 400)
  }
}

struct LogEntryRow: View {
  let entry: LogEntry

  private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(entry.typeIcon)
        Text(timeFormatter.string(from: entry.timestamp))
          .foregroundColor(.secondary)
          .font(.caption)
          .monospacedDigit()
        Text(entry.message)
          .foregroundColor(entry.typeColor)
          .textSelection(.enabled)
      }
    }
    .padding(.vertical, 2)
  }
}

extension OSLogEntryLog.Level: CaseIterable {
  public static var allCases: [OSLogEntryLog.Level] = [
    .undefined,
    .debug,
    .info,
    .notice,
    .error,
    .fault,
  ]

  var description: String {
    switch self {
    case .debug: return "Debug"
    case .info: return "Info"
    case .notice: return "Notice"
    case .error: return "Error"
    case .fault: return "Fault"
    case .undefined: return "Other"
    @unknown default: return "Unknown"
    }
  }
}
