import CoreGraphics
import Foundation
import QuartzCore

struct TrackedObject: Identifiable {
  let id = UUID()
  var rect: CGRect
  var confidence: Float
  var smoothedConfidence: Float
  var label: String
  var timestamp: TimeInterval
  var velocity: CGPoint
  var alpha: CGFloat
  var detectionCount: Int
  var positionHistory: [(CGPoint, CGSize)]  // Store recent positions and sizes
  var lastUpdateTime: TimeInterval  // For velocity calculation
}

class ObjectTracker: ObservableObject {
  @Published private(set) var trackedObjects: [TrackedObject] = []
  private let settings = Settings.shared
  private let iouThreshold: CGFloat = 0.25  // Lowered for better matching
  private let confidenceSmoothingFactor: Float = 0.15  // More gradual confidence changes
  private let minDetectionCount = 3
  private let maxHistoryLength = 5  // Number of positions to keep in history
  private let confidenceHysteresis: Float = 0.1  // Prevent threshold flickering

  func update(with detections: [DetectedObject]) {
    guard settings.enableSmoothing else {
      trackedObjects = detections.map { detection in
        TrackedObject(
          rect: detection.boundingBox,
          confidence: detection.confidence,
          smoothedConfidence: detection.confidence,
          label: detection.label,
          timestamp: CACurrentMediaTime(),
          velocity: .zero,
          alpha: 1.0,
          detectionCount: 1,
          positionHistory: [
            (
              CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY),
              CGSize(width: detection.boundingBox.width, height: detection.boundingBox.height)
            )
          ],
          lastUpdateTime: CACurrentMediaTime()
        )
      }
      return
    }

    let currentTime = CACurrentMediaTime()
    var newTrackedObjects: [TrackedObject] = []
    var matchedDetections = Set<UUID>()

    // First, try to update existing objects with new detections
    for var existingObject in trackedObjects {
      if let (detection, iou) = findBestMatch(existingObject.rect, in: detections) {
        let timeDelta = currentTime - existingObject.lastUpdateTime
        let smoothingFactor = CGFloat(settings.smoothingFactor) * 0.5  // Reduce smoothing factor

        // Calculate new position and size
        let newCenter = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
        let newSize = CGSize(
          width: detection.boundingBox.width, height: detection.boundingBox.height)

        // Update position history
        var history = existingObject.positionHistory
        history.append((newCenter, newSize))
        if history.count > maxHistoryLength {
          history.removeFirst()
        }
        existingObject.positionHistory = history

        // Calculate smoothed position and size using history
        let smoothedPosition = calculateSmoothedPosition(history)
        let smoothedSize = calculateSmoothedSize(history)

        // Update rect with smoothed values
        existingObject.rect = CGRect(
          x: smoothedPosition.x - smoothedSize.width / 2,
          y: smoothedPosition.y - smoothedSize.height / 2,
          width: smoothedSize.width,
          height: smoothedSize.height
        )

        // Calculate and smooth velocity
        if timeDelta > 0 {
          let dx = (newCenter.x - existingObject.rect.midX) / CGFloat(timeDelta)
          let dy = (newCenter.y - existingObject.rect.midY) / CGFloat(timeDelta)
          let newVelocity = CGPoint(x: dx, y: dy)
          existingObject.velocity = CGPoint(
            x: existingObject.velocity.x * 0.8 + newVelocity.x * 0.2,
            y: existingObject.velocity.y * 0.8 + newVelocity.y * 0.2
          )
        }

        // Smooth confidence with hysteresis
        let confidenceThreshold = settings.confidenceThreshold
        if detection.confidence >= confidenceThreshold - confidenceHysteresis {
          existingObject.confidence = detection.confidence
          existingObject.smoothedConfidence +=
            (detection.confidence - existingObject.smoothedConfidence) * confidenceSmoothingFactor
        }

        existingObject.timestamp = currentTime
        existingObject.lastUpdateTime = currentTime
        existingObject.detectionCount += 1

        // Gradually increase alpha based on detection count
        let targetAlpha: CGFloat = existingObject.detectionCount >= minDetectionCount ? 1.0 : 0.3
        existingObject.alpha += (targetAlpha - existingObject.alpha) * 0.2

        newTrackedObjects.append(existingObject)
        matchedDetections.insert(detection.id)
      } else {
        // Object wasn't matched - handle fade out
        let age = currentTime - existingObject.timestamp
        if age < settings.objectPersistence {
          // Predict position based on velocity and history
          let predictedCenter = CGPoint(
            x: existingObject.rect.midX + existingObject.velocity.x * CGFloat(age),
            y: existingObject.rect.midY + existingObject.velocity.y * CGFloat(age)
          )
          existingObject.rect = CGRect(
            x: predictedCenter.x - existingObject.rect.width / 2,
            y: predictedCenter.y - existingObject.rect.height / 2,
            width: existingObject.rect.width,
            height: existingObject.rect.height
          )

          // Smooth fade out
          let fadeProgress = CGFloat(age / settings.objectPersistence)
          let targetAlpha: CGFloat = 1.0 - fadeProgress
          existingObject.alpha += (targetAlpha - existingObject.alpha) * 0.2
          existingObject.smoothedConfidence *= (1.0 - Float(fadeProgress) * 0.3)

          if existingObject.smoothedConfidence
            > (settings.confidenceThreshold - confidenceHysteresis) * 0.5
          {
            newTrackedObjects.append(existingObject)
          }
        }
      }
    }

    // Add new detections that weren't matched
    for detection in detections {
      if !matchedDetections.contains(detection.id) {
        if detection.confidence >= settings.confidenceThreshold {
          let center = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
          let size = CGSize(
            width: detection.boundingBox.width, height: detection.boundingBox.height)
          let newObject = TrackedObject(
            rect: detection.boundingBox,
            confidence: detection.confidence,
            smoothedConfidence: detection.confidence,
            label: detection.label,
            timestamp: currentTime,
            velocity: .zero,
            alpha: 0.3,  // Start very faint
            detectionCount: 1,
            positionHistory: [(center, size)],
            lastUpdateTime: currentTime
          )
          newTrackedObjects.append(newObject)
        }
      }
    }

    // Sort by confidence and update
    trackedObjects = newTrackedObjects.sorted { $0.smoothedConfidence > $1.smoothedConfidence }
  }

  private func calculateSmoothedPosition(_ history: [(CGPoint, CGSize)]) -> CGPoint {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var totalWeight: CGFloat = 0

    for (i, (position, _)) in history.enumerated() {
      let weight = CGFloat(i + 1)
      x += position.x * weight
      y += position.y * weight
      totalWeight += weight
    }

    return CGPoint(x: x / totalWeight, y: y / totalWeight)
  }

  private func calculateSmoothedSize(_ history: [(CGPoint, CGSize)]) -> CGSize {
    var width: CGFloat = 0
    var height: CGFloat = 0
    var totalWeight: CGFloat = 0

    for (i, (_, size)) in history.enumerated() {
      let weight = CGFloat(i + 1)
      width += size.width * weight
      height += size.height * weight
      totalWeight += weight
    }

    return CGSize(width: width / totalWeight, height: height / totalWeight)
  }

  private func findBestMatch(_ rect: CGRect, in detections: [DetectedObject]) -> (
    DetectedObject, CGFloat
  )? {
    guard !detections.isEmpty else { return nil }

    var bestMatch: (detection: DetectedObject, iou: CGFloat) = (detections[0], 0)
    let center = CGPoint(x: rect.midX, y: rect.midY)

    for detection in detections {
      let intersection = rect.intersection(detection.boundingBox)
      let union = rect.union(detection.boundingBox)
      var iou = intersection.width * intersection.height / (union.width * union.height)

      // Consider distance between centers for better matching
      let detectionCenter = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
      let distance = hypot(center.x - detectionCenter.x, center.y - detectionCenter.y)
      let distanceWeight = 1.0 - min(distance / max(rect.width, rect.height), 1.0)

      // Adjust IOU based on distance
      iou *= distanceWeight

      if iou > bestMatch.iou {
        bestMatch = (detection, iou)
      }
    }

    return bestMatch.iou > iouThreshold ? bestMatch : nil
  }
}
