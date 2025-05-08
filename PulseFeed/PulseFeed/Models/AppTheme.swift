import UIKit

// Import for access to UIColor hex initializer
import class UIKit.UIColor

struct AppTheme: Codable, Hashable {
    // MARK: - Properties
    
    var name: String
    var primaryColor: String // Hex color
    var secondaryColor: String // Hex color
    var backgroundColor: String // Hex color
    var accentColor: String // Hex color
    var textColor: String // Hex color
    var isCustom: Bool
    var supportsDarkMode: Bool
    
    // MARK: - Initialization
    
    init(name: String, 
         primaryColor: String, 
         secondaryColor: String,
         backgroundColor: String, 
         accentColor: String,
         textColor: String,
         isCustom: Bool = false, 
         supportsDarkMode: Bool = true) {
        self.name = name
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.textColor = textColor
        self.isCustom = isCustom
        self.supportsDarkMode = supportsDarkMode
    }
    
    // MARK: - UIColor Conversion
    
    var primaryColorUI: UIColor {
        return UIColor(hex: primaryColor)
    }
    
    var secondaryColorUI: UIColor {
        return UIColor(hex: secondaryColor)
    }
    
    var backgroundColorUI: UIColor {
        return UIColor(hex: backgroundColor)
    }
    
    var accentColorUI: UIColor {
        return UIColor(hex: accentColor)
    }
    
    var textColorUI: UIColor {
        return UIColor(hex: textColor)
    }
    
    // MARK: - Hashable Implementation
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: AppTheme, rhs: AppTheme) -> Bool {
        return lhs.name == rhs.name
    }
    
    // MARK: - Factory Methods
    
    static func systemTheme() -> AppTheme {
        return AppTheme(
            name: "System",
            primaryColor: "121212", // Dynamic in use
            secondaryColor: "9E9E9E", // Dynamic in use
            backgroundColor: "FFFFFF", // Dynamic in use
            accentColor: "007AFF",
            textColor: "000000", // Dynamic in use
            supportsDarkMode: true
        )
    }
    
    static func lightTheme() -> AppTheme {
        return AppTheme(
            name: "Light",
            primaryColor: "121212",
            secondaryColor: "757575",
            backgroundColor: "FFFFFF",
            accentColor: "007AFF",
            textColor: "000000",
            supportsDarkMode: false
        )
    }
    
    static func darkTheme() -> AppTheme {
        return AppTheme(
            name: "Dark",
            primaryColor: "FFFFFF",
            secondaryColor: "9E9E9E",
            backgroundColor: "121212",
            accentColor: "0A84FF",
            textColor: "FFFFFF",
            supportsDarkMode: false
        )
    }
    
    static func sepiaTheme() -> AppTheme {
        return AppTheme(
            name: "Sepia",
            primaryColor: "5B4636",
            secondaryColor: "8E744B",
            backgroundColor: "F9F5E9",
            accentColor: "8E744B",
            textColor: "5B4636",
            supportsDarkMode: false
        )
    }
    
    static func blueTheme() -> AppTheme {
        return AppTheme(
            name: "Blue",
            primaryColor: "36454F",
            secondaryColor: "4682B4",
            backgroundColor: "E6F1FF",
            accentColor: "4682B4",
            textColor: "36454F",
            supportsDarkMode: false
        )
    }
    
    static func purpleTheme() -> AppTheme {
        return AppTheme(
            name: "Purple",
            primaryColor: "4A3B52",
            secondaryColor: "8E6C9E",
            backgroundColor: "F8F2FF",
            accentColor: "8E6C9E", 
            textColor: "4A3B52",
            supportsDarkMode: false
        )
    }
    
    static func oledBlackTheme() -> AppTheme {
        return AppTheme(
            name: "OLED Black",
            primaryColor: "000000", // Primary is black
            secondaryColor: "999999",
            backgroundColor: "000000", // True black for OLED displays
            accentColor: "FFFFFF", // Accent is white
            textColor: "FFFFFF",
            supportsDarkMode: false
        )
    }
    
    static func defaultThemes() -> [AppTheme] {
        return [
            .systemTheme(),
            .lightTheme(),
            .darkTheme(),
            .oledBlackTheme(),
            .sepiaTheme(),
            .blueTheme(),
            .purpleTheme()
        ]
    }
    
    // MARK: - Methods
    
    func applyToInterface(traitCollection: UITraitCollection) -> (primaryColor: UIColor, secondaryColor: UIColor, backgroundColor: UIColor, accentColor: UIColor, textColor: UIColor) {
        // Handle System theme which adapts to Dark Mode
        if name == "System" {
            let isDarkMode = traitCollection.userInterfaceStyle == .dark
            let primaryColor = isDarkMode ? UIColor.white : UIColor(hex: "121212")
            let secondaryColor = isDarkMode ? UIColor(hex: "9E9E9E") : UIColor(hex: "757575")
            let backgroundColor = isDarkMode ? UIColor(hex: "121212") : UIColor.white
            let accentColor = isDarkMode ? UIColor(hex: "0A84FF") : UIColor(hex: "007AFF")
            let textColor = isDarkMode ? UIColor.white : UIColor.black
            return (primaryColor, secondaryColor, backgroundColor, accentColor, textColor)
        } else {
            return (primaryColorUI, secondaryColorUI, backgroundColorUI, accentColorUI, textColorUI)
        }
    }
}

// MARK: - Theme Manager

class AppThemeManager {
    // MARK: - Properties
    
    static let shared = AppThemeManager()
    
    private let userDefaults = UserDefaults.standard
    private let themesKey = "appThemes"
    private let selectedThemeKey = "selectedAppTheme"
    
    private(set) var themes: [AppTheme]
    private(set) var selectedTheme: AppTheme
    
    // MARK: - Initialization
    
    private init() {
        // Load custom themes if available
        if let themesData = userDefaults.data(forKey: themesKey),
           let decodedThemes = try? JSONDecoder().decode([AppTheme].self, from: themesData) {
            // Merge default themes with any custom themes
            let defaultThemes = AppTheme.defaultThemes()
            let customThemes = decodedThemes.filter { $0.isCustom }
            themes = defaultThemes + customThemes
        } else {
            themes = AppTheme.defaultThemes()
        }
        
        // Load selected theme
        let selectedThemeName = userDefaults.string(forKey: selectedThemeKey) ?? "System"
        selectedTheme = themes.first { $0.name == selectedThemeName } ?? AppTheme.systemTheme()
    }
    
    // MARK: - Theme Management
    
    func selectTheme(named themeName: String) {
        guard let theme = themes.first(where: { $0.name == themeName }) else { return }
        selectedTheme = theme
        userDefaults.set(theme.name, forKey: selectedThemeKey)
        
        // Notify observers of theme change
        NotificationCenter.default.post(name: Notification.Name("appThemeChanged"), object: nil)
    }
    
    func addCustomTheme(_ theme: AppTheme) -> Bool {
        // Ensure theme name is unique
        guard !themes.contains(where: { $0.name == theme.name }) else {
            return false
        }
        
        // Add theme with isCustom flag set to true
        var customTheme = theme
        customTheme.isCustom = true
        themes.append(customTheme)
        
        // Save updated themes
        saveThemes()
        return true
    }
    
    func updateTheme(_ updatedTheme: AppTheme) -> Bool {
        // Find the theme to update
        guard let index = themes.firstIndex(where: { $0.name == updatedTheme.name }) else {
            return false
        }
        
        // Only allow updating custom themes or if it's the selected theme
        if themes[index].isCustom || themes[index].name == selectedTheme.name {
            themes[index] = updatedTheme
            
            // Update selected theme if it was updated
            if selectedTheme.name == updatedTheme.name {
                selectedTheme = updatedTheme
            }
            
            // Save updated themes
            saveThemes()
            
            // Notify observers of theme change
            NotificationCenter.default.post(name: Notification.Name("appThemeChanged"), object: nil)
            return true
        }
        
        return false
    }
    
    func deleteCustomTheme(named themeName: String) -> Bool {
        // Only allow deleting custom themes
        guard let index = themes.firstIndex(where: { $0.name == themeName && $0.isCustom }) else {
            return false
        }
        
        // If deleting the selected theme, switch to system theme
        if selectedTheme.name == themeName {
            selectTheme(named: "System")
        }
        
        // Remove the theme
        themes.remove(at: index)
        
        // Save updated themes
        saveThemes()
        return true
    }
    
    // MARK: - Persistence
    
    private func saveThemes() {
        // Only save custom themes
        let customThemes = themes.filter { $0.isCustom }
        
        if let encoded = try? JSONEncoder().encode(customThemes) {
            userDefaults.set(encoded, forKey: themesKey)
        }
    }
    
    // MARK: - Theme Application
    
    func getCurrentThemeColors(for traitCollection: UITraitCollection) -> (primaryColor: UIColor, secondaryColor: UIColor, backgroundColor: UIColor, accentColor: UIColor, textColor: UIColor) {
        return selectedTheme.applyToInterface(traitCollection: traitCollection)
    }
}