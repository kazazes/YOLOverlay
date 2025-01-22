import CoreGraphics
import Foundation
import QuartzCore

struct TrackedObject: Identifiable {
  let id = UUID()
  var rect: CGRect
  var confidence: Float
  var label: String
  var timestamp: TimeInterval
  var velocity: CGPoint
  var alpha: CGFloat
}

class ObjectTracker: ObservableObject {
  @Published private(set) var trackedObjects: [TrackedObject] = []
  private let settings = Settings.shared
  private let iouThreshold: CGFloat = 0.5

  func update(with detections: [DetectedObject]) {
    guard settings.enableSmoothing else {
      // If smoothing is disabled, just convert detections directly
      trackedObjects = detections.map { detection in
        TrackedObject(
          rect: detection.boundingBox,
          confidence: detection.confidence,
          label: detection.label,
          timestamp: CACurrentMediaTime(),
          velocity: .zero,
          alpha: 1.0
        )
      }
      return
    }

    let currentTime = CACurrentMediaTime()
    var newTrackedObjects: [TrackedObject] = []

    // Update existing objects and match with new detections
    for detection in detections {
      if let (index, iou) = findBestMatch(detection.boundingBox, in: trackedObjects),
        iou > iouThreshold
      {
        // Update existing object with smoothing
        var updatedObject = trackedObjects[index]
        let smoothingFactor = CGFloat(settings.smoothingFactor)

        // Calculate velocity
        let dx = detection.boundingBox.origin.x - updatedObject.rect.origin.x
        let dy = detection.boundingBox.origin.y - updatedObject.rect.origin.y
        updatedObject.velocity = CGPoint(
          x: dx / smoothingFactor,
          y: dy / smoothingFactor
        )

        // Apply smoothing to position and size
        updatedObject.rect.origin.x += dx * smoothingFactor
        updatedObject.rect.origin.y += dy * smoothingFactor
        updatedObject.rect.size.width +=
          (detection.boundingBox.width - updatedObject.rect.width) * smoothingFactor
        updatedObject.rect.size.height +=
          (detection.boundingBox.height - updatedObject.rect.height) * smoothingFactor

        updatedObject.confidence = detection.confidence
        updatedObject.timestamp = currentTime
        updatedObject.alpha = 1.0

        newTrackedObjects.append(updatedObject)
      } else {
        // Add new tracked object
        newTrackedObjects.append(
          TrackedObject(
            rect: detection.boundingBox,
            confidence: detection.confidence,
            label: detection.label,
            timestamp: currentTime,
            velocity: .zero,
            alpha: 1.0
          )
        )
      }
    }

    // Handle objects that weren't matched (fade them out)
    let persistenceTime = settings.objectPersistence
    for object in trackedObjects {
      let age = currentTime - object.timestamp
      if age < persistenceTime,
        !newTrackedObjects.contains(where: { $0.id == object.id })
      {
        var fadingObject = object

        // Apply velocity-based prediction
        fadingObject.rect.origin.x += object.velocity.x * CGFloat(age)
        fadingObject.rect.origin.y += object.velocity.y * CGFloat(age)

        // Calculate fade out
        fadingObject.alpha = 1.0 - (CGFloat(age) / CGFloat(persistenceTime))
        newTrackedObjects.append(fadingObject)
      }
    }

    trackedObjects = newTrackedObjects
  }

  private func findBestMatch(_ rect: CGRect, in objects: [TrackedObject]) -> (Int, CGFloat)? {
    var bestMatch: (index: Int, iou: CGFloat) = (-1, 0)

    for (index, object) in objects.enumerated() {
      let intersection = object.rect.intersection(rect)
      let union = object.rect.union(rect)
      let iou = intersection.width * intersection.height / (union.width * union.height)

      if iou > bestMatch.iou {
        bestMatch = (index, iou)
      }
    }

    return bestMatch.index != -1 ? bestMatch : nil
  }
}
