import Foundation

struct YOLOModel: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
}

enum ModelError: Error {
    case modelNotFound
    case modelLoadError(Error)
    case visionError(Error)
}

extension Notification.Name {
    static let modelChanged = Notification.Name("modelChanged")
} 