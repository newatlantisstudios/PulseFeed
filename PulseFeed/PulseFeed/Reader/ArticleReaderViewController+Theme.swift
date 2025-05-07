import UIKit
import WebKit

extension ArticleReaderViewController {
    
    // MARK: - Theme Management
    
    func setupThemeSupport() {
        // Add theme button to toolbar
        let themeButton = UIBarButtonItem(image: UIImage(systemName: "paintpalette"), style: .plain, target: self, action: #selector(showThemeSelector))
        
        // Add typography button to toolbar
        let typographyButton = UIBarButtonItem(image: UIImage(systemName: "textformat"), style: .plain, target: self, action: #selector(showTypographySettings))
        
        // Get current toolbar items
        guard var toolbarItems = toolbar.items else { return }
        
        // Find flex space items
        if toolbarItems.count >= 5 {
            // Add theme and typography buttons after the text justification button and before the increase font button
            // Format is: [decreaseFontButton, flexSpace, toggleModeButton, flexSpace, justifyButton, flexSpace, increaseFontButton]
            
            // Insert theme button, typography button and flex space
            let themeFlexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            toolbarItems.insert(contentsOf: [themeFlexSpace, themeButton, typographyButton], at: 6) // Insert before increase font button
            
            // Update toolbar items
            toolbar.items = toolbarItems
        }
        
        // Setup notifications for theme changes
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChanged), name: Notification.Name("articleThemeChanged"), object: nil)
        
        // Apply current theme
        applyCurrentTheme()
    }
    
    func applyCurrentTheme() {
        // Get current theme from manager
        let themeManager = ArticleThemeManager.shared
        let (textColor, bgColor, _) = themeManager.getCurrentThemeColors(for: traitCollection)
        
        // Save the colors for use throughout the view controller
        self.fontColor = textColor
        self.backgroundColor = bgColor
        
        // Update UI with theme colors
        updateUIWithThemeColors()
        
        // Update web content with theme colors
        if let content = htmlContent {
            displayContent(content)
        }
    }
    
    private func updateUIWithThemeColors() {
        // Update view background
        view.backgroundColor = backgroundColor
        
        // Update webview background
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = backgroundColor
        }
        
        // Update scroll indicator style based on background color
        let isDark = backgroundColor.isDarkColor
        webView.scrollView.indicatorStyle = isDark ? UIScrollView.IndicatorStyle.white : UIScrollView.IndicatorStyle.black
        
        // Update labels
        titleLabel.textColor = fontColor
        sourceLabel.textColor = AppColors.secondary
        dateLabel.textColor = AppColors.secondary
        estimatedReadingTimeLabel?.textColor = AppColors.secondary
    }
    
    // MARK: - Actions
    
    @objc func showThemeSelector() {
        let themeVC = ThemeSelectionViewController()
        themeVC.delegate = self
        
        let navController = UINavigationController(rootViewController: themeVC)
        present(navController, animated: true)
    }
    
    @objc func showTypographySettings() {
        let typographyVC = TypographyViewController()
        typographyVC.delegate = self
        
        let navController = UINavigationController(rootViewController: typographyVC)
        present(navController, animated: true)
    }
    
    @objc func handleThemeChanged() {
        // Apply the updated theme
        applyCurrentTheme()
    }
}

// MARK: - ThemeSelectionDelegate

extension ArticleReaderViewController: ThemeSelectionDelegate {
    func themeDidChange() {
        // Apply the updated theme
        applyCurrentTheme()
    }
}

// MARK: - TypographyChangeDelegate

extension ArticleReaderViewController: TypographyChangeDelegate {
    func typographyDidChange() {
        // Load updated typography settings
        typographySettings = TypographySettings.loadFromUserDefaults()
        
        // Update UI elements that use typography settings
        titleLabel.font = typographySettings.fontFamily.font(withSize: 22, weight: UIFont.Weight.bold)
        sourceLabel.font = typographySettings.fontFamily.font(withSize: 14, weight: UIFont.Weight.medium)
        dateLabel.font = typographySettings.fontFamily.font(withSize: 14)
        estimatedReadingTimeLabel?.font = typographySettings.fontFamily.font(withSize: 14, weight: UIFont.Weight.regular)
        
        // Reload the article content with the new typography settings
        if let content = htmlContent {
            displayContent(content)
        }
    }
}

// MARK: - UIColor Helpers

extension UIColor {
    var isDarkColor: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        self.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Calculate relative luminance
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        
        // Threshold for dark/light determination
        return luminance < 0.5
    }
}