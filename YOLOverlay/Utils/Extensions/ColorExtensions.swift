import AppKit

extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return "#FF0000"  // Fallback to red
        }
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
    
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        switch hex.count {
        case 3:  // RGB (12-bit)
            r = CGFloat((int >> 8) & 0xF) / 15.0
            g = CGFloat((int >> 4) & 0xF) / 15.0
            b = CGFloat(int & 0xF) / 15.0
        case 6:  // RGB (24-bit)
            r = CGFloat((int >> 16) & 0xFF) / 255.0
            g = CGFloat((int >> 8) & 0xFF) / 255.0
            b = CGFloat(int & 0xFF) / 255.0
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
} 