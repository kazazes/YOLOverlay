import Foundation

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
}

extension Double {
    func nonZeroValue(defaultValue: Double) -> Double {
        return self == 0 ? defaultValue : self
    }
} 