import UIKit

enum AppColors {
    static var primary: UIColor {
        return UIColor(hex: "121212")
    }

    static var secondary: UIColor {
        return UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: "9E9E9E") : UIColor(hex: "757575")
        }
    }

    static var accent: UIColor {
        return UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: "FFFFFF") : UIColor(hex: "1A1A1A")
        }
    }

    static var background: UIColor {
        return UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: "1E1E1E") : UIColor(hex: "F5F5F5")
        }
    }
    
    static var dynamicIconColor: UIColor {
        return UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
    }
    
    static var navBarBackground: UIColor {
        return UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                // Dark background in Dark Mode
                return UIColor(hex: "121212")
            default:
                // Light background in Light Mode
                return UIColor(hex: "FFFFFF") // or "F5F5F5", etc.
            }
        }
    }
    
    static var warning: UIColor {
        return UIColor(hex: "F44336") // Red color for warning banners
    }
    
    static var cacheIndicator: UIColor {
        return UIColor(hex: "4CAF50") // Green color for cached article indicators
    }
}

extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex)
        scanner.scanLocation = 0

        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = (rgbValue & 0xff0000) >> 16
        let g = (rgbValue & 0xff00) >> 8
        let b = rgbValue & 0xff

        self.init(
            red: CGFloat(r) / 0xff,
            green: CGFloat(g) / 0xff,
            blue: CGFloat(b) / 0xff,
            alpha: 1)
    }
}