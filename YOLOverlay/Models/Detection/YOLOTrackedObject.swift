import Vision
import CoreGraphics

struct YOLOTrackedObject {
    var label: String
    var confidence: Float
    var boundingBox: CGRect
    var lastSeen: TimeInterval
    var velocity: CGVector  // For basic motion prediction

    // Smoothing factors
    static let positionSmoothing: CGFloat = 0.7  // Higher = more smoothing
    static let confidenceSmoothing: Float = 0.8

    mutating func update(with observation: VNRecognizedObjectObservation, at time: TimeInterval) {
        // Smooth confidence
        let newConfidence = observation.labels.first?.confidence ?? 0
        confidence =
            confidence * Self.confidenceSmoothing + newConfidence
            * (1 - Self.confidenceSmoothing)

        // Calculate velocity
        let dt = time - lastSeen
        if dt > 0 {
            let dx = observation.boundingBox.origin.x - boundingBox.origin.x
            let dy = observation.boundingBox.origin.y - boundingBox.origin.y
            velocity = CGVector(dx: dx / dt, dy: dy / dt)
        }

        // Smooth position with velocity prediction
        let predictedBox = CGRect(
            x: boundingBox.origin.x + CGFloat(velocity.dx * dt),
            y: boundingBox.origin.y + CGFloat(velocity.dy * dt),
            width: boundingBox.width,
            height: boundingBox.height
        )

        // Smooth between prediction and new observation
        boundingBox = predictedBox.interpolated(
            to: observation.boundingBox,
            amount: 1 - Self.positionSmoothing
        )

        lastSeen = time
    }
}

// Helper extension for CGRect interpolation
extension CGRect {
    func interpolated(to other: CGRect, amount: CGFloat) -> CGRect {
        let x = origin.x + (other.origin.x - origin.x) * amount
        let y = origin.y + (other.origin.y - origin.y) * amount
        let width = size.width + (other.size.width - size.width) * amount
        let height = size.height + (other.size.height - size.height) * amount
        return CGRect(x: x, y: y, width: width, height: height)
    }
} 