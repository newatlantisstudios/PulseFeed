import UIKit

enum AppColors {
    static var primary: UIColor {
        return UIColor { traitCollection in
            let themeManager = AppThemeManager.shared
            let (primaryColor, _, _, _, _) = themeManager.getCurrentThemeColors(for: traitCollection)
            return primaryColor
        }
    }

    static var secondary: UIColor {
        return UIColor { traitCollection in
            let themeManager = AppThemeManager.shared
            let (_, secondaryColor, _, _, _) = themeManager.getCurrentThemeColors(for: traitCollection)
            return secondaryColor
        }
    }

    static var accent: UIColor {
        return UIColor { traitCollection in
            let themeManager = AppThemeManager.shared
            let (_, _, _, accentColor, _) = themeManager.getCurrentThemeColors(for: traitCollection)
            return accentColor
        }
    }

    static var background: UIColor {
        return UIColor { traitCollection in
            let themeManager = AppThemeManager.shared
            let (_, _, backgroundColor, _, _) = themeManager.getCurrentThemeColors(for: traitCollection)
            return backgroundColor
        }
    }
    
    static var textColor: UIColor {
        return UIColor { traitCollection in
            let themeManager = AppThemeManager.shared
            let (_, _, _, _, textColor) = themeManager.getCurrentThemeColors(for: traitCollection)
            return textColor
        }
    }
    
    static var dynamicIconColor: UIColor {
        return UIColor { traitCollection in
            let themeManager = AppThemeManager.shared
            let (_, _, _, _, textColor) = themeManager.getCurrentThemeColors(for: traitCollection)
            return textColor
        }
    }
    
    static var navBarBackground: UIColor {
        return UIColor { traitCollection in
            let themeManager = AppThemeManager.shared
            let (_, _, backgroundColor, _, _) = themeManager.getCurrentThemeColors(for: traitCollection)
            return backgroundColor
        }
    }
    
    static var warning: UIColor {
        return UIColor(hex: "F44336") // Red color for warning banners
    }
    
    static var cacheIndicator: UIColor {
        return UIColor(hex: "4CAF50") // Green color for cached article indicators
    }
    
    static var success: UIColor {
        return UIColor(hex: "4CAF50") // Green color for success indicators
    }
}

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        // Ensure we have a valid hex string
        if hexSanitized.isEmpty {
            self.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            return
        }
        
        // Handle 3-digit hex
        if hexSanitized.count == 3 {
            var sixDigitHex = ""
            for character in hexSanitized {
                sixDigitHex.append(String(repeating: character, count: 2))
            }
            hexSanitized = sixDigitHex
        }
        
        // Add leading zeros if needed
        if hexSanitized.count < 6 {
            let zeros = String(repeating: "0", count: 6 - hexSanitized.count)
            hexSanitized = zeros + hexSanitized
        }
        
        // Create scanner and get RGB value
        let scanner = Scanner(string: hexSanitized)
        scanner.scanLocation = 0
        
        var rgbValue: UInt64 = 0
        let scanned = scanner.scanHexInt64(&rgbValue)
        
        // If scan failed, use a fallback color
        if !scanned {
            // Try alternate parsing method
            if let intValue = UInt64(hexSanitized, radix: 16) {
                rgbValue = intValue
            } else {
                self.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
                return
            }
        }
        
        // Extract RGB components
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    static func fromHex(_ hex: String) -> UIColor {
        return UIColor(hex: hex)
    }
    
    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        return String(
            format: "%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255)
        )
    }
    
    // Convenience method to get a color description
    var colorDescription: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        return "UIColor(red: \(r), green: \(g), blue: \(b), alpha: \(a))"
    }
}