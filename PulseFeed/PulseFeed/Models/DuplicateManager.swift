import Foundation
import UIKit

/// Manages app-wide settings and behavior for duplicate article handling
class DuplicateManager {
    
    /// Singleton instance
    static let shared = DuplicateManager()
    
    /// Notification posted when duplicate handling settings change
    static let duplicateSettingsChangedNotification = Notification.Name("duplicateSettingsChanged")
    
    /// Possible actions to take when duplicates are detected
    enum DuplicateHandlingMode: String, CaseIterable {
        /// Show all articles, including duplicates
        case showAll = "Show All Articles"
        
        /// Automatically hide duplicates, keeping only the primary version
        case hideAutomatically = "Hide Duplicates Automatically"
        
        /// Group duplicates together and show a special UI for them
        case groupAndShow = "Group and Show Duplicates"
    }
    
    /// Strategy for choosing the primary article when duplicates are found
    enum PrimarySelectionStrategy: String, CaseIterable {
        /// Choose the newest article by publication date
        case newest = "Newest First"
        
        /// Choose the article from the highest priority source
        case sourcePriority = "Preferred Source"
        
        /// Choose the article with the most content/details
        case mostContent = "Most Content"
    }
    
    /// The current handling mode for duplicates
    var handlingMode: DuplicateHandlingMode {
        get {
            let storedValue = UserDefaults.standard.string(forKey: "duplicateHandlingMode")
            return DuplicateHandlingMode(rawValue: storedValue ?? "") ?? .showAll
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "duplicateHandlingMode")
            NotificationCenter.default.post(name: DuplicateManager.duplicateSettingsChangedNotification, object: nil)
        }
    }
    
    /// The current strategy for selecting the primary article
    var primarySelectionStrategy: PrimarySelectionStrategy {
        get {
            let storedValue = UserDefaults.standard.string(forKey: "primarySelectionStrategy")
            return PrimarySelectionStrategy(rawValue: storedValue ?? "") ?? .newest
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "primarySelectionStrategy")
            NotificationCenter.default.post(name: DuplicateManager.duplicateSettingsChangedNotification, object: nil)
        }
    }
    
    /// Whether to show a count badge for duplicate groups
    var showDuplicateCountBadge: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "showDuplicateCountBadge")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showDuplicateCountBadge")
            NotificationCenter.default.post(name: DuplicateManager.duplicateSettingsChangedNotification, object: nil)
        }
    }
    
    /// User's preferred sources, in order of priority
    var preferredSources: [String] {
        get {
            return UserDefaults.standard.stringArray(forKey: "preferredSources") ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preferredSources")
            NotificationCenter.default.post(name: DuplicateManager.duplicateSettingsChangedNotification, object: nil)
        }
    }
    
    /// Determine if duplicate detection is enabled
    var isDuplicateDetectionEnabled: Bool {
        return handlingMode != .showAll
    }
    
    /// Private constructor for singleton
    private init() {
        // Set default values if not already set
        if UserDefaults.standard.object(forKey: "duplicateHandlingMode") == nil {
            UserDefaults.standard.set(DuplicateHandlingMode.showAll.rawValue, forKey: "duplicateHandlingMode")
        }
        
        if UserDefaults.standard.object(forKey: "primarySelectionStrategy") == nil {
            UserDefaults.standard.set(PrimarySelectionStrategy.newest.rawValue, forKey: "primarySelectionStrategy")
        }
        
        if UserDefaults.standard.object(forKey: "showDuplicateCountBadge") == nil {
            UserDefaults.standard.set(true, forKey: "showDuplicateCountBadge")
        }
    }
    
    /// Process a list of RSS items according to the current duplicate handling settings
    /// - Parameter items: The original list of RSS items
    /// - Returns: Processed list according to the current settings
    func processItems(_ items: [RSSItem]) -> [RSSItem] {
        // If duplicate handling is disabled, return the original list
        guard isDuplicateDetectionEnabled else {
            return items
        }
        
        switch handlingMode {
        case .showAll:
            // This shouldn't happen because of the guard above, but included for completeness
            return items
            
        case .hideAutomatically:
            // Filter out duplicates, keeping only the originals
            return DuplicateDetector.shared.filterDuplicates(from: items)
            
        case .groupAndShow:
            // For groupAndShow, we still show all items in the HomeFeedViewController
            // The special UI for grouped duplicates is handled in the cell configuration
            return items
        }
    }
    
    /// Get duplicate groups from a list of items
    /// - Parameter items: List of RSS items to check for duplicates
    /// - Returns: Array of duplicate groups
    func getDuplicateGroups(from items: [RSSItem]) -> [DuplicateArticleGroup] {
        let rawGroups = DuplicateDetector.shared.groupDuplicates(in: items)
        
        // Convert raw groups to DuplicateArticleGroup objects
        return rawGroups.map { articleGroup in
            return DuplicateArticleGroup(articles: articleGroup)
        }
    }
    
    /// Add a source to the preferred sources list
    /// - Parameter source: The source name to add
    func addPreferredSource(_ source: String) {
        var current = preferredSources
        if !current.contains(source) {
            current.append(source)
            preferredSources = current
        }
    }
    
    /// Remove a source from the preferred sources list
    /// - Parameter source: The source name to remove
    func removePreferredSource(_ source: String) {
        var current = preferredSources
        if let index = current.firstIndex(of: source) {
            current.remove(at: index)
            preferredSources = current
        }
    }
    
    /// Move a source up in the preferred sources list
    /// - Parameter source: The source name to move up
    func movePreferredSourceUp(_ source: String) {
        var current = preferredSources
        if let index = current.firstIndex(of: source), index > 0 {
            current.remove(at: index)
            current.insert(source, at: index - 1)
            preferredSources = current
        }
    }
    
    /// Move a source down in the preferred sources list
    /// - Parameter source: The source name to move down
    func movePreferredSourceDown(_ source: String) {
        var current = preferredSources
        if let index = current.firstIndex(of: source), index < current.count - 1 {
            current.remove(at: index)
            current.insert(source, at: index + 1)
            preferredSources = current
        }
    }
}