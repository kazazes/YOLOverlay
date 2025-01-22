import CoreGraphics
import Foundation
import QuartzCore

struct TrackedObject: Identifiable {
  let id: UUID
  let label: String
  var rect: CGRect
  var confidence: Float
  var smoothedConfidence: Float
  var alpha: CGFloat
  var velocity: CGPoint
  var detectionCount: Int
  var positionHistory: [(CGPoint, CGSize)]  // Store recent positions and sizes
  var lastUpdateTime: TimeInterval  // For velocity calculation
  private let smoothingFactor: CGFloat = 0.5

  init(from detection: DetectedObject, id: UUID = UUID()) {
    self.id = id
    self.label = detection.label
    self.rect = detection.boundingBox
    self.confidence = detection.confidence
    self.smoothedConfidence = detection.confidence
    self.alpha = 0.3  // Start faint and fade in
    self.velocity = .zero
    self.detectionCount = 1
    self.positionHistory = [
      (
        CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY),
        CGSize(width: detection.boundingBox.width, height: detection.boundingBox.height)
      )
    ]
    self.lastUpdateTime = CACurrentMediaTime()
  }

  mutating func update(with detection: DetectedObject, timeDelta: TimeInterval) {
    // Update position history
    let newCenter = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
    let newSize = CGSize(width: detection.boundingBox.width, height: detection.boundingBox.height)
    positionHistory.append((newCenter, newSize))
    if positionHistory.count > 5 {  // Keep last 5 positions
      positionHistory.removeFirst()
    }

    // Calculate velocity
    if timeDelta > 0 {
      let dx = (newCenter.x - rect.midX) / CGFloat(timeDelta)
      let dy = (newCenter.y - rect.midY) / CGFloat(timeDelta)
      velocity = CGPoint(
        x: velocity.x * 0.8 + dx * 0.2,  // Smooth velocity changes
        y: velocity.y * 0.8 + dy * 0.2
      )
    }

    // Smooth the transition
    let t = CGFloat(min(1.0, timeDelta * 60.0 * smoothingFactor))  // 60 fps target
    rect = rect.interpolated(to: detection.boundingBox, amount: t)

    // Update confidence with smoothing
    confidence = detection.confidence
    smoothedConfidence += (detection.confidence - smoothedConfidence) * 0.15

    // Update counters and timing
    detectionCount += 1
    lastUpdateTime = CACurrentMediaTime()

    // Update alpha based on detection count
    let targetAlpha: CGFloat = detectionCount >= 3 ? 1.0 : 0.3
    alpha += (targetAlpha - alpha) * 0.2
  }
}

class ObjectTracker: ObservableObject {
  @Published private(set) var trackedObjects: [TrackedObject] = []
  @Published private(set) var sortedObjects: [TrackedObject] = []

  private let settings = Settings.shared
  private let iouThreshold: CGFloat = 0.25
  private let confidenceSmoothingFactor: Float = 0.15
  private let minDetectionCount = 3
  private let maxHistoryLength = 5
  private let confidenceHysteresis: Float = 0.1
  private let maxTrackingDistance: CGFloat = 0.3

  private var lastUpdateTime = Date()
  private var nextObjectId = 0

  func update(with detections: [DetectedObject]) {
    let currentTime = Date()
    let timeDelta = currentTime.timeIntervalSince(lastUpdateTime)
    lastUpdateTime = currentTime

    var updatedObjects: [TrackedObject] = []
    var usedDetections = Set<Int>()

    // First, try to update existing objects with the closest matching detection
    for var existingObject in trackedObjects {
      if let (detection, _) = findBestMatch(
        for: existingObject, in: detections, excluding: usedDetections)
      {
        existingObject.update(with: detection, timeDelta: timeDelta)
        updatedObjects.append(existingObject)
        if let index = detections.firstIndex(where: { $0.id == detection.id }) {
          usedDetections.insert(index)
        }
      }
    }

    // Create new tracked objects for remaining detections
    for (index, detection) in detections.enumerated() {
      if !usedDetections.contains(index) {
        let newObject = TrackedObject(from: detection, id: UUID())
        updatedObjects.append(newObject)
      }
    }

    // Update the tracked objects
    trackedObjects = updatedObjects

    // Update sorted cache
    sortedObjects = trackedObjects.sorted {
      $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height
    }
  }

  private func findBestMatch(
    for object: TrackedObject,
    in detections: [DetectedObject],
    excluding usedIndices: Set<Int>
  ) -> (DetectedObject, CGFloat)? {
    var bestMatch: (detection: DetectedObject, distance: CGFloat, index: Int)?

    for (index, detection) in detections.enumerated() {
      // Skip if this detection is already used or labels don't match
      if usedIndices.contains(index) || detection.label != object.label {
        continue
      }

      let dist = distance(between: object.rect, and: detection.boundingBox)

      // Only consider detections within the maximum tracking distance
      if dist < maxTrackingDistance {
        if bestMatch == nil || dist < bestMatch!.distance {
          bestMatch = (detection, dist, index)
        }
      }
    }

    return bestMatch.map { ($0.detection, $0.distance) }
  }

  private func distance(between rect1: CGRect, and rect2: CGRect) -> CGFloat {
    let center1 = CGPoint(x: rect1.midX, y: rect1.midY)
    let center2 = CGPoint(x: rect2.midX, y: rect2.midY)

    let dx = center1.x - center2.x
    let dy = center1.y - center2.y
    return sqrt(dx * dx + dy * dy)
  }
}
