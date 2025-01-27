import CoreGraphics
import Foundation
import QuartzCore

struct TrackedObject: Identifiable {
  let id: UUID
  let label: String
  var rect: CGRect
  var confidence: Float
  var alpha: CGFloat
  var lastUpdateTime: TimeInterval

  init(from detection: DetectedObject, id: UUID = UUID()) {
    self.id = id
    self.label = detection.label
    self.rect = detection.boundingBox
    self.confidence = detection.confidence
    self.alpha = 0.3
    self.lastUpdateTime = CACurrentMediaTime()
  }

  mutating func update(with detection: DetectedObject, timeDelta: TimeInterval) {
    // Simple linear interpolation for position
    let t = CGFloat(min(1.0, timeDelta * 30.0))  // Slower interpolation
    rect = rect.interpolated(to: detection.boundingBox, amount: t)

    // Direct confidence update
    confidence = detection.confidence

    // Update timing
    lastUpdateTime = CACurrentMediaTime()

    // Simple fade in
    alpha = min(1.0, alpha + 0.2)
  }
}

class ObjectTracker: ObservableObject {
  @Published private(set) var trackedObjects: [TrackedObject] = []
  @Published private(set) var sortedObjects: [TrackedObject] = []

  private let maxTrackingDistance: CGFloat = 0.3
  private let fadeOutDuration: TimeInterval = 0.15
  private var lastUpdateTime: TimeInterval = CACurrentMediaTime()

  func update(with detections: [DetectedObject]) {
    let currentTime = CACurrentMediaTime()
    let timeDelta = currentTime - lastUpdateTime
    lastUpdateTime = currentTime

    var updatedObjects: [TrackedObject] = []
    var usedDetections = Set<Int>()

    // Update existing objects
    for var existingObject in trackedObjects {
      if let (detection, index) = findBestMatch(
        for: existingObject, in: detections, excluding: usedDetections)
      {
        existingObject.update(with: detection, timeDelta: timeDelta)
        updatedObjects.append(existingObject)
        usedDetections.insert(index)
      } else {
        // Simple fade out
        let age = currentTime - existingObject.lastUpdateTime
        if age < fadeOutDuration {
          existingObject.alpha = max(
            0.0, existingObject.alpha - CGFloat(timeDelta / fadeOutDuration))
          if existingObject.alpha > 0 {
            updatedObjects.append(existingObject)
          }
        }
      }
    }

    // Add new objects
    for (index, detection) in detections.enumerated() {
      if !usedDetections.contains(index) {
        updatedObjects.append(TrackedObject(from: detection))
      }
    }

    // Sort by size and update both arrays
    let sorted = updatedObjects.sorted {
      $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height
    }

    // Update both published properties
    trackedObjects = updatedObjects
    sortedObjects = sorted
  }

  private func findBestMatch(
    for object: TrackedObject,
    in detections: [DetectedObject],
    excluding usedIndices: Set<Int>
  ) -> (DetectedObject, Int)? {
    var bestMatch: (detection: DetectedObject, distance: CGFloat, index: Int)?

    for (index, detection) in detections.enumerated() {
      if usedIndices.contains(index) || detection.label != object.label {
        continue
      }

      let dist = distance(between: object.rect, and: detection.boundingBox)
      if dist < maxTrackingDistance {
        if bestMatch == nil || dist < bestMatch!.distance {
          bestMatch = (detection, dist, index)
        }
      }
    }

    return bestMatch.map { ($0.detection, $0.index) }
  }

  private func distance(between rect1: CGRect, and rect2: CGRect) -> CGFloat {
    let center1 = CGPoint(x: rect1.midX, y: rect1.midY)
    let center2 = CGPoint(x: rect2.midX, y: rect2.midY)
    let dx = center1.x - center2.x
    let dy = center1.y - center2.y
    return sqrt(dx * dx + dy * dy)
  }
}
