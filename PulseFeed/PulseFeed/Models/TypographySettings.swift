import UIKit

struct TypographySettings: Codable {
    // MARK: - Font Properties
    
    enum FontFamily: String, Codable, CaseIterable {
        case system = "System"
        case georgia = "Georgia"
        case times = "Times New Roman"
        case palatino = "Palatino"
        case avenir = "Avenir"
        case helveticaNeue = "Helvetica Neue"
        case menlo = "Menlo"
        case sanFrancisco = "San Francisco"
        
        var fontName: String {
            switch self {
            case .system:
                return UIFont.systemFont(ofSize: 17).fontName
            case .georgia:
                return "Georgia"
            case .times:
                return "TimesNewRomanPSMT"
            case .palatino:
                return "Palatino-Roman"
            case .avenir:
                return "Avenir-Book"
            case .helveticaNeue:
                return "HelveticaNeue"
            case .menlo:
                return "Menlo-Regular"
            case .sanFrancisco:
                return UIFont.systemFont(ofSize: 17).fontName // System font is actually SF
            }
        }
        
        var displayName: String {
            return self.rawValue
        }
        
        func font(withSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            switch self {
            case .system, .sanFrancisco:
                return UIFont.systemFont(ofSize: size, weight: weight)
            default:
                if let font = UIFont(name: self.fontName, size: size) {
                    return font
                } else {
                    return UIFont.systemFont(ofSize: size, weight: weight)
                }
            }
        }
    }
    
    // MARK: - Properties
    
    var fontFamily: FontFamily
    var fontSize: CGFloat
    var lineHeight: CGFloat // Multiplier, e.g., 1.5 means 1.5x the font size
    
    // MARK: - Initialization
    
    init(fontFamily: FontFamily = .system, fontSize: CGFloat = 18, lineHeight: CGFloat = 1.5) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
    }
    
    // MARK: - Factory Methods
    
    static func defaultSettings() -> TypographySettings {
        return TypographySettings()
    }
    
    // Load settings from UserDefaults
    static func loadFromUserDefaults() -> TypographySettings {
        // Try to load from UserDefaults
        let defaults = UserDefaults.standard
        
        let fontFamilyString = defaults.string(forKey: "readerFontFamily") ?? FontFamily.system.rawValue
        let fontFamily = FontFamily(rawValue: fontFamilyString) ?? .system
        
        let fontSize = CGFloat(defaults.float(forKey: "readerFontSize"))
        let lineHeight = CGFloat(defaults.float(forKey: "readerLineHeight"))
        
        // If values are 0, they haven't been set yet, so use defaults
        return TypographySettings(
            fontFamily: fontFamily,
            fontSize: fontSize > 0 ? fontSize : 18,
            lineHeight: lineHeight > 0 ? lineHeight : 1.5
        )
    }
    
    // MARK: - Methods
    
    // Save settings to UserDefaults
    func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(fontFamily.rawValue, forKey: "readerFontFamily")
        defaults.set(Float(fontSize), forKey: "readerFontSize")
        defaults.set(Float(lineHeight), forKey: "readerLineHeight")
        
        // Notify observers that typography settings have changed
        NotificationCenter.default.post(name: Notification.Name("typographySettingsChanged"), object: nil)
    }
    
    // Apply settings to labels for consistent styling
    func applyToLabel(_ label: UILabel, withWeight weight: UIFont.Weight = .regular) {
        label.font = fontFamily.font(withSize: fontSize, weight: weight)
    }
    
    // Generate CSS for web view
    func generateCSS() -> String {
        return """
        body {
            font-family: '\(fontFamily.fontName)', -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: \(fontSize)px;
            line-height: \(lineHeight);
        }
        """
    }
}