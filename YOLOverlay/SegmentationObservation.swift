import Vision
import CoreML

class SegmentationObservation: VNRecognizedObjectObservation {
    var segmentationMask: MLMultiArray?
    var classLabels: [String]?

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    convenience init(boundingBox: CGRect) {
        self.init()
        // Create a classification observation using proper initialization
        if let classificationClass = NSClassFromString("VNClassificationObservation") as? NSObject.Type {
            let classification = classificationClass.init() as? VNClassificationObservation
            classification?.setValue("segmentation", forKey: "identifier")
            classification?.setValue(1.0 as Float, forKey: "confidence")
            
            if let classification = classification {
                // Set required properties using KVC since they're private
                setValue(boundingBox, forKey: "boundingBox")
                setValue([classification], forKey: "labels")
            }
        }
    }

    convenience init(mask: MLMultiArray) {
        self.init()
        segmentationMask = mask
        classLabels = Settings.shared.modelClasses
    }
} 