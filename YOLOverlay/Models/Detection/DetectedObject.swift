import Vision
import CoreGraphics

struct DetectedObject: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect

    // Implement Equatable
    static func == (lhs: DetectedObject, rhs: DetectedObject) -> Bool {
        lhs.label == rhs.label && lhs.confidence == rhs.confidence && lhs.boundingBox == rhs.boundingBox
    }
}

// Helper extension to convert between types
extension VNRecognizedObjectObservation {
    static func fromDetectedObject(_ object: DetectedObject) -> VNRecognizedObjectObservation {
        let observation = VNRecognizedObjectObservation(boundingBox: object.boundingBox)

        // Create a classification observation using private API
        let classification = unsafeBitCast(
            NSClassFromString("VNClassificationObservation")?.alloc(),
            to: VNClassificationObservation.self
        )
        classification.setValue(object.label, forKey: "identifier")
        classification.setValue(object.confidence, forKey: "confidence")

        // Set the labels using setValue
        observation.setValue([classification], forKey: "labels")
        return observation
    }
} 