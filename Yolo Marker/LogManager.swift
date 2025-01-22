import Foundation
import OSLog
import SwiftUI

class LogManager: ObservableObject {
  static let shared = LogManager()
  private let logger: Logger
  @Published var logEntries: [LogEntry] = []
  private let maxEntries = 1000
  private var lastCollectionTime = Date()
  private let subsystem = "com.kazazes.Yolo-Marker"

  private init() {
    self.logger = Logger(subsystem: subsystem, category: "app")
    // Start collecting logs continuously
    Task {
      while true {
        await collectLogs()
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      }
    }
  }

  func log(_ message: String, type: OSLogType = .default) {
    switch type {
    case .debug:
      logger.debug("\(message)")
    case .info:
      logger.info("\(message)")
    case .error:
      logger.error("\(message)")
    case .fault:
      logger.fault("\(message)")
    default:
      logger.notice("\(message)")
    }
  }

  private func collectLogs() async {
    do {
      let store = try OSLogStore(scope: .currentProcessIdentifier)
      let position = store.position(date: lastCollectionTime)

      var newEntries: [LogEntry] = []
      for entry in try store.getEntries(at: position) {
        if let logEntry = entry as? OSLogEntryLog,
          logEntry.subsystem == subsystem
        {
          newEntries.append(
            LogEntry(
              message: logEntry.composedMessage,
              timestamp: entry.date,
              type: logEntry.level
            )
          )
        }
      }

      await MainActor.run {
        // Add new entries and maintain max size
        logEntries.append(contentsOf: newEntries)
        if logEntries.count > maxEntries {
          logEntries.removeFirst(logEntries.count - maxEntries)
        }
      }

      lastCollectionTime = Date()
    } catch {
      print("Failed to collect logs: \(error)")
    }
  }
}

struct LogEntry: Identifiable {
  let id = UUID()
  let message: String
  let timestamp: Date
  let type: OSLogEntryLog.Level

  var typeIcon: String {
    switch type {
    case .debug: return "🔍"
    case .info: return "ℹ️"
    case .notice: return "📝"
    case .error: return "⚠️"
    case .fault: return "❌"
    default: return "📋"
    }
  }

  var typeColor: Color {
    switch type {
    case .debug: return .secondary
    case .info: return .blue
    case .notice: return .primary
    case .error: return .orange
    case .fault: return .red
    default: return .primary
    }
  }
}
