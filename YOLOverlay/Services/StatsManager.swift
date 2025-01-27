import Foundation
import QuartzCore

class StatsManager: ObservableObject {
  @Published private(set) var fps: Double = 0
  @Published private(set) var averageProcessingTime: TimeInterval = 0
  @Published private(set) var detectionCount: Int = 0
  @Published private(set) var droppedFrames: Int = 0
  @Published private(set) var objectCounts: [String: Int] = [:]
  @Published private(set) var cpuUsage: Double = 0
  @Published private(set) var gpuUsage: Double = 0
  @Published private(set) var memoryUsage: Double = 0

  private var frameTimestamps: [TimeInterval] = []
  private var processingTimes: [TimeInterval] = []
  private let maxSamples = 30  // For rolling average
  private var lastFrameTime: TimeInterval = 0
  private var lastCPUInfo: host_cpu_load_info?

  private let settings = Settings.shared
  private let processInfo = ProcessInfo.processInfo
  private let hostCPULoadInfo = host_cpu_load_info()

  init() {
    startSystemMonitoring()
  }

  private func startSystemMonitoring() {
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateSystemStats()
    }
  }

  private func updateSystemStats() {
    updateCPUUsage()
    updateMemoryUsage()
    updateGPUUsage()
  }

  private func updateCPUUsage() {
    var cpuInfo = host_cpu_load_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &cpuInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }

    if result == KERN_SUCCESS {
      if let lastInfo = lastCPUInfo {
        let userDiff = Double(cpuInfo.cpu_ticks.0 - lastInfo.cpu_ticks.0)
        let systemDiff = Double(cpuInfo.cpu_ticks.1 - lastInfo.cpu_ticks.1)
        let idleDiff = Double(cpuInfo.cpu_ticks.2 - lastInfo.cpu_ticks.2)
        let niceDiff = Double(cpuInfo.cpu_ticks.3 - lastInfo.cpu_ticks.3)

        let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
        let usedTicks = userDiff + systemDiff + niceDiff

        cpuUsage = (usedTicks / totalTicks) * 100.0
      }
      lastCPUInfo = cpuInfo
    }
  }

  private func updateMemoryUsage() {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }

    if result == KERN_SUCCESS {
      let usedBytes = Double(info.phys_footprint)
      let totalBytes = Double(processInfo.physicalMemory)
      memoryUsage = (usedBytes / totalBytes) * 100.0
    }
  }

  private func updateGPUUsage() {
    // Note: Getting actual GPU usage requires Metal Performance Metrics
    // This is a simplified approximation based on processing time
    let gpuLoad = (averageProcessingTime / (1.0 / settings.targetFPS)) * 100.0
    gpuUsage = min(gpuLoad, 100.0)
  }

  func recordFrame() {
    let now = CACurrentMediaTime()

    // Only drop frames if we're significantly below the target interval
    // This allows for some variance in frame timing
    let targetInterval = settings.minimumFrameInterval
    if now - lastFrameTime < targetInterval * 0.5 {
      droppedFrames += 1
      return
    }

    frameTimestamps.append(now)
    if frameTimestamps.count > maxSamples {
      frameTimestamps.removeFirst()
    }

    // Calculate FPS based on recent frames
    if frameTimestamps.count > 1 {
      let timeWindow = frameTimestamps.last! - frameTimestamps.first!
      fps = Double(frameTimestamps.count - 1) / timeWindow
    }

    lastFrameTime = now
  }

  func recordProcessingTime(_ time: TimeInterval) {
    processingTimes.append(time)
    if processingTimes.count > maxSamples {
      processingTimes.removeFirst()
    }

    // Calculate average processing time
    averageProcessingTime = processingTimes.reduce(0, +) / Double(processingTimes.count)
  }

  func updateDetections(_ objects: [DetectedObject]) {
    // Filter by confidence threshold
    let filteredObjects = objects.filter { $0.confidence >= settings.confidenceThreshold }
    detectionCount = filteredObjects.count

    // Update object type counts
    var counts: [String: Int] = [:]
    for object in filteredObjects {
      counts[object.label, default: 0] += 1
    }
    objectCounts = counts
  }

  func getStatsString() -> String {
    let fpsStr = String(format: "%.1f", fps)
    let procStr = String(format: "%.1f", averageProcessingTime * 1000)  // Convert to ms
    let cpuStr = String(format: "%.1f", cpuUsage)
    let gpuStr = String(format: "%.1f", gpuUsage)
    let memStr = String(format: "%.1f", memoryUsage)

    var stats = "FPS: \(fpsStr)/\(Int(settings.targetFPS)) | Proc: \(procStr)ms"
    stats += "\nCPU: \(cpuStr)% | GPU: \(gpuStr)% | Mem: \(memStr)%"
    stats += "\nObjects: \(detectionCount)"

    if droppedFrames > 0 {
      stats += " | Dropped: \(droppedFrames)"
    }

    // Add top 3 most detected objects with confidence
    let topObjects = objectCounts.sorted { $0.value > $1.value }.prefix(3)
    if !topObjects.isEmpty {
      stats +=
        "\nTop detected: " + topObjects.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }

    return stats
  }

  func reset() {
    fps = 0
    averageProcessingTime = 0
    detectionCount = 0
    droppedFrames = 0
    objectCounts.removeAll()
    frameTimestamps.removeAll()
    processingTimes.removeAll()
    lastFrameTime = 0
    cpuUsage = 0
    gpuUsage = 0
    memoryUsage = 0
  }

  func incrementDroppedFrames() {
    droppedFrames += 1
  }

  func incrementProcessedFrames() {
    recordFrame()
  }
}
