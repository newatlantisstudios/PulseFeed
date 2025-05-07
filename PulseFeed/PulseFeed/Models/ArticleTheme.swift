import UIKit

struct ArticleTheme: Codable {
    // MARK: - Properties
    
    var name: String
    var textColor: String // Hex color
    var backgroundColor: String // Hex color
    var accentColor: String // Hex color for links
    var isCustom: Bool
    var supportsDarkMode: Bool
    
    // MARK: - Initialization
    
    init(name: String, 
         textColor: String, 
         backgroundColor: String, 
         accentColor: String, 
         isCustom: Bool = false, 
         supportsDarkMode: Bool = true) {
        self.name = name
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.isCustom = isCustom
        self.supportsDarkMode = supportsDarkMode
    }
    
    // MARK: - UIColor Conversion
    
    var textColorUI: UIColor {
        return UIColor(hex: textColor)
    }
    
    var backgroundColorUI: UIColor {
        return UIColor(hex: backgroundColor)
    }
    
    var accentColorUI: UIColor {
        return UIColor(hex: accentColor)
    }
    
    // MARK: - Factory Methods
    
    static func systemTheme() -> ArticleTheme {
        return ArticleTheme(
            name: "System",
            textColor: "000000", // Dynamic in use
            backgroundColor: "FFFFFF", // Dynamic in use
            accentColor: "007AFF",
            supportsDarkMode: true
        )
    }
    
    static func lightTheme() -> ArticleTheme {
        return ArticleTheme(
            name: "Light",
            textColor: "000000",
            backgroundColor: "FFFFFF",
            accentColor: "007AFF",
            supportsDarkMode: false
        )
    }
    
    static func darkTheme() -> ArticleTheme {
        return ArticleTheme(
            name: "Dark",
            textColor: "FFFFFF",
            backgroundColor: "000000",
            accentColor: "0A84FF",
            supportsDarkMode: false
        )
    }
    
    static func sepiaTheme() -> ArticleTheme {
        return ArticleTheme(
            name: "Sepia",
            textColor: "5B4636",
            backgroundColor: "F9F5E9",
            accentColor: "8E744B",
            supportsDarkMode: false
        )
    }
    
    static func blueFilterTheme() -> ArticleTheme {
        return ArticleTheme(
            name: "Blue Filter",
            textColor: "36454F",
            backgroundColor: "F8F4E9",
            accentColor: "4682B4",
            supportsDarkMode: false
        )
    }
    
    static func defaultThemes() -> [ArticleTheme] {
        return [
            .systemTheme(),
            .lightTheme(),
            .darkTheme(),
            .sepiaTheme(),
            .blueFilterTheme()
        ]
    }
    
    // MARK: - Methods
    
    func applyToReaderView(traitCollection: UITraitCollection) -> (textColor: UIColor, backgroundColor: UIColor, accentColor: UIColor) {
        // Handle System theme which adapts to Dark Mode
        if name == "System" {
            let isDarkMode = traitCollection.userInterfaceStyle == .dark
            let textColor = isDarkMode ? UIColor.white : UIColor.black
            let backgroundColor = isDarkMode ? UIColor.black : UIColor.white
            let accentColor = isDarkMode ? UIColor(hex: "0A84FF") : UIColor(hex: "007AFF")
            return (textColor, backgroundColor, accentColor)
        } else {
            return (textColorUI, backgroundColorUI, accentColorUI)
        }
    }
}

// MARK: - Theme Manager

class ArticleThemeManager {
    // MARK: - Properties
    
    static let shared = ArticleThemeManager()
    
    private let userDefaults = UserDefaults.standard
    private let themesKey = "articleThemes"
    private let selectedThemeKey = "selectedArticleTheme"
    
    private(set) var themes: [ArticleTheme]
    private(set) var selectedTheme: ArticleTheme
    
    // MARK: - Initialization
    
    private init() {
        // Load custom themes if available
        if let themesData = userDefaults.data(forKey: themesKey),
           let decodedThemes = try? JSONDecoder().decode([ArticleTheme].self, from: themesData) {
            // Merge default themes with any custom themes
            let defaultThemes = ArticleTheme.defaultThemes()
            let customThemes = decodedThemes.filter { $0.isCustom }
            themes = defaultThemes + customThemes
        } else {
            themes = ArticleTheme.defaultThemes()
        }
        
        // Load selected theme
        let selectedThemeName = userDefaults.string(forKey: selectedThemeKey) ?? "System"
        selectedTheme = themes.first { $0.name == selectedThemeName } ?? ArticleTheme.systemTheme()
    }
    
    // MARK: - Theme Management
    
    func selectTheme(named themeName: String) {
        guard let theme = themes.first(where: { $0.name == themeName }) else { return }
        selectedTheme = theme
        userDefaults.set(theme.name, forKey: selectedThemeKey)
        
        // Notify observers of theme change
        NotificationCenter.default.post(name: Notification.Name("articleThemeChanged"), object: nil)
    }
    
    func addCustomTheme(_ theme: ArticleTheme) -> Bool {
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
    
    func updateTheme(_ updatedTheme: ArticleTheme) -> Bool {
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
            NotificationCenter.default.post(name: Notification.Name("articleThemeChanged"), object: nil)
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
    
    func getCurrentThemeColors(for traitCollection: UITraitCollection) -> (textColor: UIColor, backgroundColor: UIColor, accentColor: UIColor) {
        return selectedTheme.applyToReaderView(traitCollection: traitCollection)
    }
}