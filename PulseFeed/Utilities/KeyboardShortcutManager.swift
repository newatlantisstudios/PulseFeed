import UIKit

/// A centralized manager for keyboard shortcuts in the app
class KeyboardShortcutManager {
    
    // MARK: - Shortcut Definitions
    
    /// HomeFeedViewController shortcuts
    struct HomeFeed {
        static let refresh = UIKeyCommand(input: "R", modifierFlags: .command, action: #selector(HomeFeedViewController.refreshFeeds), discoverabilityTitle: "Refresh Feeds")
        
        static let navigateNext = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(HomeFeedViewController.navigateToNextItem), discoverabilityTitle: "Next Item")
        
        static let navigatePrevious = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(HomeFeedViewController.navigateToPreviousItem), discoverabilityTitle: "Previous Item")
        
        static let openItem = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(HomeFeedViewController.openSelectedItem), discoverabilityTitle: "Open Item")
        
        static let toggleBookmark = UIKeyCommand(input: "B", modifierFlags: .command, action: #selector(HomeFeedViewController.toggleBookmark), discoverabilityTitle: "Toggle Bookmark")
        
        static let toggleFavorite = UIKeyCommand(input: "F", modifierFlags: .command, action: #selector(HomeFeedViewController.toggleFavorite), discoverabilityTitle: "Toggle Favorite")
        
        static let toggleReadStatus = UIKeyCommand(input: "M", modifierFlags: .command, action: #selector(HomeFeedViewController.toggleReadStatus), discoverabilityTitle: "Toggle Read Status")
        
        static let scrollToTop = UIKeyCommand(input: "T", modifierFlags: .command, action: #selector(HomeFeedViewController.safeScrollToTop), discoverabilityTitle: "Scroll to Top")
        
        static let search = UIKeyCommand(input: "F", modifierFlags: [.command, .shift], action: #selector(HomeFeedViewController.showSearch), discoverabilityTitle: "Search")
        
        /// Get all available shortcuts for HomeFeedViewController
        static var allShortcuts: [UIKeyCommand] {
            return [
                refresh,
                navigateNext,
                navigatePrevious,
                openItem,
                toggleBookmark,
                toggleFavorite,
                toggleReadStatus,
                scrollToTop,
                search
            ]
        }
    }
    
    /// ArticleReaderViewController shortcuts
    struct ArticleReader {
        static let nextArticle = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: .command, action: #selector(ArticleReaderViewController.navigateToNextArticle), discoverabilityTitle: "Next Article")
        
        static let previousArticle = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: .command, action: #selector(ArticleReaderViewController.navigateToPreviousArticle), discoverabilityTitle: "Previous Article")
        
        static let increaseFontSize = UIKeyCommand(input: "+", modifierFlags: .command, action: #selector(ArticleReaderViewController.increaseFontSize), discoverabilityTitle: "Increase Font Size")
        
        static let decreaseFontSize = UIKeyCommand(input: "-", modifierFlags: .command, action: #selector(ArticleReaderViewController.decreaseFontSize), discoverabilityTitle: "Decrease Font Size")
        
        static let toggleTheme = UIKeyCommand(input: "T", modifierFlags: .command, action: #selector(ArticleReaderViewController.toggleReadingMode), discoverabilityTitle: "Toggle Theme")
        
        static let shareArticle = UIKeyCommand(input: "S", modifierFlags: .command, action: #selector(ArticleReaderViewController.shareArticle), discoverabilityTitle: "Share Article")
        
        static let openInSafari = UIKeyCommand(input: "O", modifierFlags: .command, action: #selector(ArticleReaderViewController.openInSafari), discoverabilityTitle: "Open in Safari")
        
        // Additional shortcuts for text justification
        static let toggleTextJustification = UIKeyCommand(input: "J", modifierFlags: .command, action: #selector(ArticleReaderViewController.toggleTextJustification), discoverabilityTitle: "Toggle Text Justification")
        
        // Additional shortcut for offline caching
        static let toggleOfflineCache = UIKeyCommand(input: "D", modifierFlags: .command, action: #selector(ArticleReaderViewController.toggleOfflineCache), discoverabilityTitle: "Save for Offline Reading")
        
        /// Get all available shortcuts for ArticleReaderViewController
        static var allShortcuts: [UIKeyCommand] {
            return [
                nextArticle,
                previousArticle,
                increaseFontSize,
                decreaseFontSize,
                toggleTheme,
                shareArticle,
                openInSafari,
                toggleTextJustification,
                toggleOfflineCache
            ]
        }
    }
    
    /// SearchResultsViewController shortcuts
    struct SearchResults {
        static let closeSearch = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(SearchResultsViewController.dismissSearch), discoverabilityTitle: "Close Search")
    }
    
    // MARK: - Helper Methods
    
    /// Configures priority for iOS 15+ keyboard shortcuts
    static func configurePriority(for commands: [UIKeyCommand]) -> [UIKeyCommand] {
        if #available(iOS 15.0, *) {
            commands.forEach { command in
                // Give priority to navigation keys
                if command.input == UIKeyCommand.inputUpArrow || 
                   command.input == UIKeyCommand.inputDownArrow ||
                   command.input == UIKeyCommand.inputLeftArrow ||
                   command.input == UIKeyCommand.inputRightArrow {
                    command.wantsPriorityOverSystemBehavior = true
                }
            }
        }
        return commands
    }
    
    // MARK: - Documentation
    
    /// Returns a dictionary of shortcut sections with their commands for documentation
    static func getShortcutDocumentation() -> [(title: String, shortcuts: [(key: String, description: String)])] {
        return [
            ("Feed Navigation", [
                ("↓", "Next item"),
                ("↑", "Previous item"),
                ("→", "Open item"),
                ("⌘R", "Refresh feeds"),
                ("⌘T", "Scroll to top"),
                ("⌘⇧F", "Search")
            ]),
            ("Item Actions", [
                ("⌘B", "Toggle bookmark"),
                ("⌘F", "Toggle favorite"),
                ("⌘M", "Toggle read status")
            ]),
            ("Article Reading", [
                ("⌘→", "Next article"),
                ("⌘←", "Previous article"),
                ("⌘+", "Increase font size"),
                ("⌘-", "Decrease font size"),
                ("⌘T", "Toggle theme"),
                ("⌘S", "Share article"),
                ("⌘O", "Open in Safari")
            ])
        ]
    }
}