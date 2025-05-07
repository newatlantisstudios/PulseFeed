import UIKit

// MARK: - Duplicate Article Detection
extension HomeFeedViewController {

    /// Handle changes to duplicate settings
    @objc func handleDuplicateSettingsChanged() {
        // Redetect duplicates with new settings
        detectDuplicates()
        
        // Reload the table to reflect changes
        tableView.reloadData()
    }
    
    /// Detect duplicate articles in the feed
    internal func detectDuplicates() {
        // Clear previous duplicate data
        duplicateGroups = []
        duplicateArticleLinks = []
        
        // Only detect duplicates if enabled
        guard DuplicateManager.shared.isDuplicateDetectionEnabled else {
            return
        }
        
        // Run duplicate detection
        let groups = DuplicateManager.shared.getDuplicateGroups(from: _allItems)
        
        // Store the groups
        duplicateGroups = groups
        
        // Build the set of all duplicate article links for quick lookups
        for group in groups {
            for article in group.allArticles() {
                duplicateArticleLinks.insert(StorageManager.shared.normalizeLink(article.link))
            }
        }
    }
    
    /// Check if an article is part of a duplicate group
    /// - Parameter item: The article to check
    /// - Returns: True if the article is part of a duplicate group
    internal func isArticleDuplicate(_ item: RSSItem) -> Bool {
        let normalizedLink = StorageManager.shared.normalizeLink(item.link)
        return duplicateArticleLinks.contains(normalizedLink)
    }
    
    /// Get the duplicate group that contains an article
    /// - Parameter item: The article to look for
    /// - Returns: The duplicate group if found, nil otherwise
    internal func getDuplicateGroup(for item: RSSItem) -> DuplicateArticleGroup? {
        let normalizedLink = StorageManager.shared.normalizeLink(item.link)
        
        // Find the group containing this item
        return duplicateGroups.first { group in
            group.allArticles().contains { StorageManager.shared.normalizeLink($0.link) == normalizedLink }
        }
    }
    
    /// Show options for handling a duplicate article
    /// - Parameters:
    ///   - group: The duplicate group
    ///   - indexPath: The indexPath of the selected duplicate
    internal func showDuplicateOptions(for group: DuplicateArticleGroup, atIndexPath indexPath: IndexPath) {
        // Create alert controller
        let alert = UIAlertController(
            title: "Duplicate Article",
            message: "This article is available from multiple sources. Which version would you like to view?",
            preferredStyle: .actionSheet
        )
        
        // Add action for each article in the group
        let articles = group.allArticles()
        for (index, article) in articles.enumerated() {
            let title = "\(article.source): \(article.title)"
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                // Mark as read and open the selected article
                ReadStatusTracker.shared.markArticle(link: article.link, as: true)
                
                let useInAppReader = UserDefaults.standard.bool(forKey: "useInAppReader")
                if useInAppReader {
                    self.openInArticleReader(article)
                } else {
                    self.openInSafari(article)
                }
                
                // Update UI to reflect read status
                self.tableView.reloadData()
            }
            
            // Mark the primary article
            if index == 0 {
                action.setValue(UIImage(systemName: "star.fill"), forKey: "image")
            }
            
            alert.addAction(action)
        }
        
        // Add option to make this the primary article
        let selectedArticle = items[indexPath.row]
        if selectedArticle.link != group.primary.link {
            let makeDefaultAction = UIAlertAction(title: "Make This the Primary Article", style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                // Find the index of this article in the duplicates array
                if let duplicateIndex = group.duplicates.firstIndex(where: { $0.link == selectedArticle.link }) {
                    // Create new group with this as primary
                    let updatedGroup = group.changePrimary(to: duplicateIndex)
                    
                    // Update the duplicates list
                    if let groupIndex = self.duplicateGroups.firstIndex(where: { $0 == group }) {
                        self.duplicateGroups[groupIndex] = updatedGroup
                    }
                    
                    // Reload the tableView to show updated UI
                    self.tableView.reloadData()
                }
            }
            alert.addAction(makeDefaultAction)
        }
        
        // Add cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad compatibility
        if let popoverController = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: indexPath) {
                popoverController.sourceView = cell
                popoverController.sourceRect = cell.bounds
            } else {
                popoverController.sourceView = view
                popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
        }
        
        present(alert, animated: true)
    }
}