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
  private var seenMessageHashes = Set<Int>()  // Track seen messages
  private var logdRetryCount = 0
  private let maxLogdRetries = 3

  private init() {
    self.logger = Logger(subsystem: subsystem, category: "app")
    // Start collecting logs continuously
    Task {
      while true {
        await collectLogs()
        // Increase sleep time if we're having logd connection issues
        let sleepTime = logdRetryCount > 0 ? 2_000_000_000 : 500_000_000  // 2s or 500ms
        try? await Task.sleep(nanoseconds: UInt64(sleepTime))
      }
    }
  }

  // MARK: - Logging Methods

  func debug(_ message: String, file: String = #file, function: String = #function) {
    let component = URL(fileURLWithPath: file).lastPathComponent
    logger.debug("[\(component)] \(message)")
  }

  func info(_ message: String, file: String = #file, function: String = #function) {
    let component = URL(fileURLWithPath: file).lastPathComponent
    logger.info("[\(component)] \(message)")
  }

  func notice(_ message: String, file: String = #file, function: String = #function) {
    let component = URL(fileURLWithPath: file).lastPathComponent
    logger.notice("[\(component)] \(message)")
  }

  func error(
    _ message: String, error: Error? = nil, file: String = #file, function: String = #function
  ) {
    let component = URL(fileURLWithPath: file).lastPathComponent
    if let error = error {
      logger.error("[\(component)] \(message): \(error.localizedDescription)")
    } else {
      logger.error("[\(component)] \(message)")
    }
  }

  func fault(
    _ message: String, error: Error? = nil, file: String = #file, function: String = #function
  ) {
    let component = URL(fileURLWithPath: file).lastPathComponent
    if let error = error {
      logger.fault("[\(component)] \(message): \(error.localizedDescription)")
    } else {
      logger.fault("[\(component)] \(message)")
    }
  }

  private func collectLogs() async {
    do {
      let store = try OSLogStore(scope: .currentProcessIdentifier)  // Back to process scope
      let position = store.position(date: lastCollectionTime)

      // Get entries since last collection
      let entries = try store.getEntries(at: position)
        .compactMap { $0 as? OSLogEntryLog }
        .filter { entry in
          // Include our app logs and any errors/warnings
          entry.subsystem == subsystem || entry.level == .error || entry.level == .fault
        }
        .map { entry in
          LogEntry(
            message: entry.composedMessage,
            timestamp: entry.date,
            type: entry.level
          )
        }
        .filter { entry in
          // Create a unique hash for each message + timestamp combination
          let hash = "\(entry.message)|\(entry.timestamp.timeIntervalSince1970)".hashValue
          if seenMessageHashes.contains(hash) {
            return false
          }
          seenMessageHashes.insert(hash)
          return true
        }

      // Only add new entries
      if !entries.isEmpty {
        await MainActor.run {
          // Add new entries at the beginning to show newest first
          logEntries.insert(contentsOf: entries, at: 0)

          // Trim if we exceed maxEntries
          if logEntries.count > maxEntries {
            logEntries.removeLast(logEntries.count - maxEntries)
            // Also trim the seen messages set to prevent unbounded growth
            seenMessageHashes = Set(
              logEntries.map { "\($0.message)|\($0.timestamp.timeIntervalSince1970)".hashValue }
            )
          }
        }

        // Update last collection time only if we found entries
        lastCollectionTime = entries.last?.timestamp ?? lastCollectionTime
      }

      // Reset retry count on success
      logdRetryCount = 0
    } catch {
      logdRetryCount += 1
      if logdRetryCount <= maxLogdRetries {
        logger.error(
          "Failed to collect logs (attempt \(self.logdRetryCount)): \(error.localizedDescription)")
      }
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
