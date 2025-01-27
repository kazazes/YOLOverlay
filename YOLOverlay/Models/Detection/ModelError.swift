import Foundation

enum ModelError: Error {
    case modelNotFound
    case modelLoadError(Error)
    case visionError(Error)
} 