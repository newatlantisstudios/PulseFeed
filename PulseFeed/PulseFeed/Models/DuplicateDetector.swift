import Foundation
import UIKit

/// Class responsible for detecting duplicate articles in the feed
class DuplicateDetector {
    
    /// Singleton instance for app-wide access
    static let shared = DuplicateDetector()
    
    /// Minimum similarity threshold for title-based duplicate detection (0.0-1.0)
    /// Higher value = more strict matching (less false positives)
    private let titleSimilarityThreshold: Double = 0.8
    
    /// Cache of normalized links to avoid repeated processing
    private var normalizedLinkCache = [String: String]()
    
    /// Cache of recently processed items to avoid redundant calculations
    private var recentlyProcessedItems = [String: RSSItem]()
    
    /// Maximum number of items to keep in the recently processed cache
    private let maxCacheSize = 1000
    
    /// Find duplicates in a list of RSS items
    /// - Parameter items: The RSS items to check for duplicates
    /// - Returns: Dictionary of original items mapped to their duplicates
    func findDuplicates(in items: [RSSItem]) -> [RSSItem: [RSSItem]] {
        // Dictionary to hold duplicates (original item -> array of duplicates)
        var duplicatesMap = [RSSItem: [RSSItem]]()
        
        // For performance, keep track of normalized links we've already seen
        var seenLinks = Set<String>()
        
        // For title-based matching, keep a dictionary of title -> item
        var titleToItem = [String: RSSItem]()
        
        // First pass: Find exact link duplicates (most efficient)
        for item in items {
            let normalizedLink = normalizeLink(item.link)
            
            if seenLinks.contains(normalizedLink) {
                // This is a duplicate by exact link match
                // Find the original item to associate with this duplicate
                if let originalItem = items.first(where: { normalizeLink($0.link) == normalizedLink && $0.link != item.link }) {
                    if duplicatesMap[originalItem] == nil {
                        duplicatesMap[originalItem] = [item]
                    } else {
                        duplicatesMap[originalItem]?.append(item)
                    }
                }
            } else {
                // First time seeing this link, add to seen set
                seenLinks.insert(normalizedLink)
                
                // For title-based matching, normalize the title and store
                let normalizedTitle = normalizeTitle(item.title)
                titleToItem[normalizedTitle] = item
            }
        }
        
        // Second pass: Find title-based duplicates (more expensive)
        for item in items {
            // Skip items that are already marked as duplicates
            if duplicatesMap.values.contains(where: { $0.contains(where: { $0.link == item.link }) }) {
                continue
            }
            
            // Skip items that are original items with duplicates
            if duplicatesMap.keys.contains(where: { $0.link == item.link }) {
                continue
            }
            
            let normalizedTitle = normalizeTitle(item.title)
            
            // Look for similar titles in other items
            for otherItem in items {
                // Skip comparing an item to itself
                if item.link == otherItem.link {
                    continue
                }
                
                // Skip items already identified as duplicates
                if duplicatesMap.values.contains(where: { $0.contains(where: { $0.link == otherItem.link }) }) {
                    continue
                }
                
                // Skip comparing to items that are original items with duplicates
                if duplicatesMap.keys.contains(where: { $0.link == otherItem.link }) {
                    continue
                }
                
                let otherNormalizedTitle = normalizeTitle(otherItem.title)
                let similarity = calculateTitleSimilarity(normalizedTitle, otherNormalizedTitle)
                
                if similarity >= titleSimilarityThreshold {
                    // Found a duplicate by title similarity
                    // Determine which one is the "original" based on publication date or source priority
                    let (original, duplicate) = determineOriginalAndDuplicate(item, otherItem)
                    
                    if duplicatesMap[original] == nil {
                        duplicatesMap[original] = [duplicate]
                    } else {
                        duplicatesMap[original]?.append(duplicate)
                    }
                }
            }
        }
        
        return duplicatesMap
    }
    
    /// Group duplicates together in clusters (for UI display and bulk actions)
    /// - Parameter items: The RSS items to process
    /// - Returns: Array of duplicate groups, where each group contains the original and its duplicates
    func groupDuplicates(in items: [RSSItem]) -> [[RSSItem]] {
        let duplicatesMap = findDuplicates(in: items)
        
        // Convert the map to groups that include the original item
        var duplicateGroups = [[RSSItem]]()
        
        for (original, duplicates) in duplicatesMap {
            // Only create groups that have at least one duplicate
            if !duplicates.isEmpty {
                var group = [original]
                group.append(contentsOf: duplicates)
                duplicateGroups.append(group)
            }
        }
        
        return duplicateGroups
    }
    
    /// Determine which item should be considered the "original" versus the "duplicate"
    /// - Parameters:
    ///   - item1: First RSS item
    ///   - item2: Second RSS item
    /// - Returns: Tuple of (original, duplicate)
    private func determineOriginalAndDuplicate(_ item1: RSSItem, _ item2: RSSItem) -> (RSSItem, RSSItem) {
        // Get user preference
        let preferenceString = UserDefaults.standard.string(forKey: "primarySelectionStrategy") ?? "Newest First"
        
        switch preferenceString {
        case "Newest First":
            // Strategy 1: Newer items are considered the original
            if let date1 = DateUtils.parseDate(item1.pubDate),
               let date2 = DateUtils.parseDate(item2.pubDate) {
                return date1 > date2 ? (item1, item2) : (item2, item1)
            }
            
        case "Preferred Source":
            // Strategy 2: Preferred sources take priority
            let preferredSources = UserDefaults.standard.stringArray(forKey: "preferredSources") ?? []
            let index1 = preferredSources.firstIndex(of: item1.source) ?? Int.max
            let index2 = preferredSources.firstIndex(of: item2.source) ?? Int.max
            
            if index1 != index2 {
                return index1 < index2 ? (item1, item2) : (item2, item1)
            }
            
        case "Most Content":
            // Strategy 3: Items with more content are preferred
            let content1Length = (item1.content?.count ?? 0) + (item1.description?.count ?? 0)
            let content2Length = (item2.content?.count ?? 0) + (item2.description?.count ?? 0)
            
            if content1Length != content2Length {
                return content1Length > content2Length ? (item1, item2) : (item2, item1)
            }
            
        default:
            break
        }
        
        // Fallback: Use alphabetical order of source as a last resort
        return item1.source < item2.source ? (item1, item2) : (item2, item1)
    }
    
    /// Normalize a link for consistent comparison
    /// - Parameter link: The link to normalize
    /// - Returns: Normalized link
    private func normalizeLink(_ link: String) -> String {
        // Check cache first
        if let cachedNormalized = normalizedLinkCache[link] {
            return cachedNormalized
        }
        
        // Use the same normalization logic as StorageManager
        let normalized = StorageManager.shared.normalizeLink(link)
        
        // Cache the result for future use
        if normalizedLinkCache.count >= maxCacheSize {
            // Clear half the cache if it gets too big
            normalizedLinkCache = [:]
        }
        normalizedLinkCache[link] = normalized
        
        return normalized
    }
    
    /// Normalize a title for consistent comparison
    /// - Parameter title: The title to normalize
    /// - Returns: Normalized title
    private func normalizeTitle(_ title: String) -> String {
        // Convert to lowercase
        var normalized = title.lowercased()
        
        // Remove common news prefixes/suffixes
        let prefixesToRemove = ["breaking: ", "exclusive: ", "watch: ", "video: "]
        for prefix in prefixesToRemove {
            if normalized.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
            }
        }
        
        // Remove punctuation and extra whitespace
        normalized = normalized.components(separatedBy: CharacterSet.punctuationCharacters).joined(separator: " ")
        normalized = normalized.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        
        return normalized
    }
    
    /// Calculate the similarity between two normalized titles (0.0-1.0)
    /// - Parameters:
    ///   - title1: First normalized title
    ///   - title2: Second normalized title
    /// - Returns: Similarity score from 0.0 (completely different) to 1.0 (identical)
    private func calculateTitleSimilarity(_ title1: String, _ title2: String) -> Double {
        // For identical titles, return 1.0
        if title1 == title2 {
            return 1.0
        }
        
        // Split titles into words for comparison
        let words1 = Set(title1.components(separatedBy: .whitespacesAndNewlines))
        let words2 = Set(title2.components(separatedBy: .whitespacesAndNewlines))
        
        // Calculate Jaccard similarity (intersection over union)
        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
        
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }
    
    /// Filter out duplicate items, keeping only the originals
    /// - Parameter items: The full list of RSS items
    /// - Returns: List with duplicates removed
    func filterDuplicates(from items: [RSSItem]) -> [RSSItem] {
        let duplicatesMap = findDuplicates(in: items)
        
        // Create a set of all duplicate items (to exclude them)
        var duplicateItems = Set<String>()
        for duplicates in duplicatesMap.values {
            for duplicate in duplicates {
                duplicateItems.insert(duplicate.link)
            }
        }
        
        // Return only items that aren't in the duplicates set
        return items.filter { !duplicateItems.contains($0.link) }
    }
}

/// Extension to RSSItem to work with the DuplicateDetector
extension RSSItem {
    
    /// Check if this item is likely a duplicate of another item
    /// - Parameter otherItem: The item to compare against
    /// - Returns: True if the items are likely duplicates
    func isDuplicate(of otherItem: RSSItem) -> Bool {
        // Use the DuplicateDetector to check
        let detector = DuplicateDetector.shared
        let possibleDuplicates = detector.findDuplicates(in: [self, otherItem])
        
        // If either item is in the duplicates map, they're duplicates
        return !possibleDuplicates.isEmpty
    }
    
    /// Check if this item is a duplicate of any item in a list
    /// - Parameter items: List of items to check against
    /// - Returns: The original item if a duplicate is found, nil otherwise
    func findDuplicateIn(items: [RSSItem]) -> RSSItem? {
        // Skip the search if the list is empty
        guard !items.isEmpty else { return nil }
        
        // Create a list including this item and search for duplicates
        var allItems = items
        allItems.append(self)
        
        let duplicatesMap = DuplicateDetector.shared.findDuplicates(in: allItems)
        
        // Check if this item is a duplicate of any original
        for (original, duplicates) in duplicatesMap {
            if duplicates.contains(where: { $0.link == self.link }) {
                return original
            }
        }
        
        // Check if this item is an original with duplicates 
        // (should not happen in this context but included for completeness)
        if duplicatesMap[self] != nil {
            // In this case, this item is actually the original
            return nil
        }
        
        return nil
    }
}