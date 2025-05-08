import UIKit
import SafariServices
import Foundation
import WebKit

// MARK: - TableView Delegate and DataSource
extension HomeFeedViewController: UITableViewDelegate, UITableViewDataSource, UITableViewDataSourcePrefetching {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Ensure we're dealing with the table view's scroll view
        guard scrollView == tableView else { return }

        // Get the index paths of the currently visible rows
        guard let visibleRows = tableView.indexPathsForVisibleRows, !visibleRows.isEmpty else {
            return
        }

        // Find the minimum row index among visible rows
        let currentMinVisibleRow = visibleRows.map { $0.row }.min() ?? 0

        // Check if the user scrolled down past the previously tracked top row
        // Only mark items as read if this is NOT an auto-scroll
        if currentMinVisibleRow > previousMinVisibleRow && !isAutoScrolling {
            // Collect rows that should be marked as read
            for index in previousMinVisibleRow..<currentMinVisibleRow {
                // Ensure the index is valid
                if index >= 0 && index < items.count {
                    let normLink = normalizeLink(items[index].link)
                    if !items[index].isRead && !readLinks.contains(normLink) {
                        // Add to pending instead of updating immediately
                        if !pendingReadRows.contains(index) {
                            pendingReadRows.append(index)
                        }
                    }
                }
            }
        }

        // Update the tracker for the next scroll event, but only if not auto-scrolling
        if !isAutoScrolling {
            previousMinVisibleRow = currentMinVisibleRow
        }
        
        // Cancel any existing timer
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(processReadItemsAfterScrolling), object: nil)
        
        // Set a new timer to process the read items after scrolling stops, but only if not auto-scrolling
        if !isAutoScrolling {
            perform(#selector(processReadItemsAfterScrolling), with: nil, afterDelay: 0.3)
        }
    }
    
    @objc private func processReadItemsAfterScrolling() {
        guard !pendingReadRows.isEmpty else { return }
        
        var indexPathsToUpdate: [IndexPath] = []
        
        // Mark all pending items as read
        for index in pendingReadRows {
            if index >= 0 && index < items.count {
                items[index].isRead = true
                indexPathsToUpdate.append(IndexPath(row: index, section: 0))
            }
        }
        
        // Clear the pending array
        pendingReadRows.removeAll()
        
        // If any items were marked as read, save the state and reload the rows
        if !indexPathsToUpdate.isEmpty {
            scheduleSaveReadState()
            tableView.reloadRows(at: indexPathsToUpdate, with: .none)
        }
    }
    
    // Add a scrollViewDidEndDragging method to handle when user manually stops scrolling
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            // Scrolling stopped immediately, process read items now
            processReadItemsAfterScrolling()
        }
    }
    
    // Add a scrollViewDidEndDecelerating method to handle when scroll view stops moving
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Scrolling has completely stopped, process read items now
        processReadItemsAfterScrolling()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int)
        -> Int
    {
        let count = items.count
        
        // If there are no unread articles but there are articles, 
        // add an extra row for "All Articles Read" message
        let isRssFeed: Bool
        if case .rss = currentFeedType {
            isRssFeed = true
        } else {
            isRssFeed = false
        }
        
        if count > 0 && !items.contains(where: { !$0.isRead }) && isRssFeed {
            return count + 1 // Add an extra row for "All Articles Read" message
        }
        
        return count
    }
    
    // MARK: - Leading Swipe Actions (New)
    
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Check if this is our special "All Articles Read" footer cell
        let isRssFeed: Bool
        if case .rss = currentFeedType {
            isRssFeed = true
        } else {
            isRssFeed = false
        }
        
        let allArticlesRead = !items.isEmpty && !items.contains(where: { !$0.isRead }) && isRssFeed
        if allArticlesRead && indexPath.row == items.count {
            // No swipe actions for our special footer cell
            return nil
        }
        
        let item = items[indexPath.row]
        
        // Configure Share Action
        let shareAction = UIContextualAction(style: .normal, title: nil) { [weak self] (action, view, completion) in
            guard let self = self, let url = URL(string: item.link) else {
                completion(false)
                return
            }
            
            let activityViewController = UIActivityViewController(
                activityItems: [url], 
                applicationActivities: nil
            )
            
            // Present from the cell for iPad compatibility
            if let popoverController = activityViewController.popoverPresentationController {
                if let cell = tableView.cellForRow(at: indexPath) {
                    popoverController.sourceView = cell
                    popoverController.sourceRect = cell.bounds
                }
            }
            
            self.present(activityViewController, animated: true)
            completion(true)
        }
        
        // Use system icon for sharing
        shareAction.image = UIImage(systemName: "square.and.arrow.up")
        shareAction.backgroundColor = AppColors.accent
        
        // Configure Save Offline Action
        let isArticleCached = cachedArticleLinks.contains(normalizeLink(item.link))
        let cacheAction = UIContextualAction(style: .normal, title: nil) { [weak self] (action, view, completion) in
            guard let self = self else {
                completion(false)
                return
            }
            
            if isArticleCached {
                // Remove from offline cache
                StorageManager.shared.removeCachedArticle(link: item.link) { success, error in
                    if success {
                        DispatchQueue.main.async {
                            // Update UI
                            self.cachedArticleLinks.remove(self.normalizeLink(item.link))
                            tableView.reloadRows(at: [indexPath], with: .automatic)
                            completion(true)
                        }
                    } else {
                        completion(false)
                    }
                }
            } else {
                // Add to offline cache
                self.cacheArticleForOfflineReading(item) { success in
                    if success {
                        DispatchQueue.main.async {
                            // Update UI
                            self.cachedArticleLinks.insert(self.normalizeLink(item.link))
                            tableView.reloadRows(at: [indexPath], with: .automatic)
                            completion(true)
                        }
                    } else {
                        completion(false)
                    }
                }
            }
        }
        
        // Use different icons based on cache status
        cacheAction.image = UIImage(systemName: isArticleCached ? "xmark.icloud" : "arrow.down.circle")
        cacheAction.backgroundColor = isArticleCached ? AppColors.warning : AppColors.success
        
        return UISwipeActionsConfiguration(actions: [shareAction, cacheAction])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        // Check if this is our special "All Articles Read" footer cell
        let isRssFeed: Bool
        if case .rss = currentFeedType {
            isRssFeed = true
        } else {
            isRssFeed = false
        }
        
        let allArticlesRead = !items.isEmpty && !items.contains(where: { !$0.isRead }) && isRssFeed
        if allArticlesRead && indexPath.row == items.count {
            // No swipe actions for our special footer cell
            return nil
        }
        
        let item = items[indexPath.row]
        let normalizedLink = normalizeLink(item.link)

        // Configure Heart Action using local state with normalized link
        let isHearted = heartedItems.contains { normalizeLink($0) == normalizedLink }
        let heartAction = UIContextualAction(style: .normal, title: nil) {
            (action, view, completion) in
            self.toggleHeart(for: item) {
                tableView.reloadRows(at: [indexPath], with: .none)
                completion(true)
            }
        }
        heartAction.image = UIImage(systemName: isHearted ? "heart.fill" : "heart")?
            .withRenderingMode(.alwaysTemplate)
        heartAction.backgroundColor = AppColors.primary

        // Configure Bookmark Action using local state with normalized link
        let isBookmarked = bookmarkedItems.contains { normalizeLink($0) == normalizedLink }
        let bookmarkAction = UIContextualAction(style: .normal, title: nil) {
            (action, view, completion) in
            self.toggleBookmark(for: item) {
                tableView.reloadRows(at: [indexPath], with: .none)
                completion(true)
            }
        }
        bookmarkAction.image = UIImage(
            systemName: isBookmarked ? "bookmark.fill" : "bookmark")?
            .withRenderingMode(.alwaysTemplate)
        bookmarkAction.backgroundColor = AppColors.primary
        
        // Configure Archive Action
        let isArchived = archivedItems.contains { normalizeLink($0) == normalizedLink }
        let archiveAction = UIContextualAction(style: .normal, title: nil) {
            (action, view, completion) in
            self.toggleArchive(for: item) {
                tableView.reloadRows(at: [indexPath], with: .none)
                completion(true)
            }
        }
        // Use system icons for archive status
        archiveAction.image = UIImage(systemName: isArchived ? "archivebox.fill" : "archivebox")
        archiveAction.backgroundColor = AppColors.primary
        
        // Configure Read/Unread Action
        let isItemRead = ReadStatusTracker.shared.isArticleRead(link: item.link)
        let readAction = UIContextualAction(style: .normal, title: nil) {
            (action, view, completion) in
            self.toggleReadStatus(for: item) {
                tableView.reloadRows(at: [indexPath], with: .none)
                completion(true)
            }
        }
        // Use standard system icons for read/unread status
        readAction.image = UIImage(systemName: isItemRead ? "envelope.open.fill" : "envelope.fill")
        readAction.backgroundColor = isItemRead ? AppColors.secondary : AppColors.accent

        return UISwipeActionsConfiguration(actions: [
            bookmarkAction, heartAction, archiveAction, readAction,
        ])
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Check if this is our special footer cell for "All Articles Read" message
        let isRssFeed: Bool
        if case .rss = currentFeedType {
            isRssFeed = true
        } else {
            isRssFeed = false
        }
        
        let allArticlesRead = !items.isEmpty && !items.contains(where: { !$0.isRead }) && isRssFeed
        
        if allArticlesRead && indexPath.row == items.count {
            // This is our special "All Articles Read" message cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "RSSCell", for: indexPath)
            
            // Configure cell with "All Articles Read" message
            var config = cell.defaultContentConfiguration()
            config.text = "All Articles Read"
            config.textProperties.alignment = .center
            config.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
            config.textProperties.color = AppColors.primary
            
            cell.backgroundColor = AppColors.background
            cell.selectionStyle = .none
            cell.accessoryType = .none
            cell.contentConfiguration = config
            
            // Log that we're displaying this special cell
            print("DEBUG: Displaying 'All Articles Read' special cell at row \(indexPath.row)")
            
            return cell
        }
        
        // Regular content cell
        let item = items[indexPath.row]
        
        // Check if the item should be marked as read using the ReadStatusTracker
        let isItemRead = item.isRead || ReadStatusTracker.shared.isArticleRead(link: item.link)
        
        // Check if the article is cached
        let isArticleCached = cachedArticleLinks.contains(normalizeLink(item.link))
        
        // Check if this article is part of a duplicate group
        let isPartOfDuplicateGroup = isArticleDuplicate(item)
        let duplicateGroup = isPartOfDuplicateGroup ? getDuplicateGroup(for: item) : nil
        let isPrimaryDuplicate = duplicateGroup?.primary.link == item.link
        let duplicateCount = duplicateGroup?.count ?? 0
        
        // Get the font size from UserDefaults (defaulting to 16 if not set)
        let storedFontSize = CGFloat(UserDefaults.standard.float(forKey: "fontSize") != 0 ? UserDefaults.standard.float(forKey: "fontSize") : 16)
        
        if useEnhancedStyle {
            // Use the enhanced card-style cell
            let cell = tableView.dequeueReusableCell(
                withIdentifier: EnhancedRSSCell.identifier, for: indexPath) as! EnhancedRSSCell
            
            // Configure with item data including cached state
            cell.configure(with: item, fontSize: storedFontSize, isRead: isItemRead, isCached: isArticleCached)
            
            // Add duplicate information if applicable
            if isPartOfDuplicateGroup && DuplicateManager.shared.handlingMode == .groupAndShow {
                if isPrimaryDuplicate {
                    // This is the primary article of a duplicate group
                    if DuplicateManager.shared.showDuplicateCountBadge && duplicateCount > 0 {
                        // Add a badge showing duplicate count
                        cell.addDuplicateBadge(count: duplicateCount)
                    }
                } else {
                    // This is a duplicate article
                    cell.markAsDuplicate()
                }
            }
            
            // Configure for bulk edit mode if needed
            if isBulkEditMode {
                // Set accessory type based on selection state
                cell.accessoryType = selectedItems.contains(indexPath.row) ? .checkmark : .none
                cell.tintColor = AppColors.accent
            }
            
            return cell
        } else {
            // Use the default plain text cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "RSSCell", for: indexPath)
            
            // Configure cell with read state
            var config = cell.defaultContentConfiguration()
            
            // Add duplicate indicator if applicable
            if isPartOfDuplicateGroup && DuplicateManager.shared.handlingMode == .groupAndShow {
                // Visual indication of duplicates
                if isPrimaryDuplicate && duplicateCount > 1 {
                    // This is the primary article with duplicates
                    config.text = "🔄 \(item.title) [+\(duplicateCount - 1)]"
                    cell.backgroundColor = UIColor(hex: "1E90FF").withAlphaComponent(0.05)
                } else if !isPrimaryDuplicate {
                    // This is a duplicate article
                    config.text = "⤷ \(item.title)"
                    cell.backgroundColor = UIColor(hex: "1E90FF").withAlphaComponent(0.02)
                } else {
                    config.text = item.title
                }
            } else {
                config.text = item.title
                cell.backgroundColor = AppColors.background
            }
            
            // Add "Cached" indicator to secondary text if article is cached
            var secondaryText = "\(item.source) • \(DateUtils.getTimeAgo(from: item.pubDate))"
            if isArticleCached {
                secondaryText += " • 📥 Cached"
            }
            
            // Add read status indicator to secondary text
            if isItemRead {
                secondaryText += " • 👁️ Read"
            }
            
            // Add duplicate indicator to secondary text
            if isPartOfDuplicateGroup && DuplicateManager.shared.handlingMode == .groupAndShow {
                if isPrimaryDuplicate {
                    secondaryText += " • 🔄 Primary"
                } else {
                    secondaryText += " • 🔄 Duplicate"
                }
            }
            
            // Add tags to secondary text if any
            item.getTags { result in
                if case .success(let tags) = result, !tags.isEmpty {
                    DispatchQueue.main.async {
                        var tagText = ""
                        for (index, tag) in tags.enumerated() {
                            if index == 0 {
                                tagText += " • 🏷️ "
                            } else {
                                tagText += ", "
                            }
                            tagText += tag.name
                        }
                        
                        // Update config with tags
                        var updatedConfig = cell.defaultContentConfiguration()
                        updatedConfig.text = config.text
                        updatedConfig.secondaryText = secondaryText + tagText
                        
                        // Apply text properties
                        updatedConfig.textProperties.color = isItemRead ? AppColors.secondary : AppColors.accent
                        updatedConfig.secondaryTextProperties.color = AppColors.secondary
                        updatedConfig.secondaryTextProperties.font = .systemFont(ofSize: 12)
                        updatedConfig.textProperties.font = .systemFont(ofSize: storedFontSize, weight: isItemRead ? .regular : .medium)
                        
                        // Update cell
                        cell.contentConfiguration = updatedConfig
                    }
                }
            }
            
            config.secondaryText = secondaryText
            
            cell.backgroundColor = AppColors.background
            
            // Apply text color based on read state - MORE CONTRAST between read/unread
            config.textProperties.color = isItemRead ? AppColors.secondary : AppColors.accent
            config.secondaryTextProperties.color = AppColors.secondary
            config.secondaryTextProperties.font = .systemFont(ofSize: 12)
            
            config.textProperties.font = .systemFont(ofSize: storedFontSize, weight: isItemRead ? .regular : .medium)
            
            // Configure for regular mode or bulk edit mode
            if isBulkEditMode {
                // Set accessory type based on selection state
                cell.accessoryType = selectedItems.contains(indexPath.row) ? .checkmark : .none
                cell.tintColor = AppColors.accent
            } else {
                // Use disclosure indicator in normal mode
                cell.accessoryType = .disclosureIndicator
            }
            
            cell.contentConfiguration = config
            
            return cell
        }
    }
    
    // Cache indicator handling is now implemented directly in the cell classes
    
    // Context menu for right-click and long press
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // Check if this is the special footer cell
        let isRssFeed: Bool
        if case .rss = currentFeedType {
            isRssFeed = true
        } else {
            isRssFeed = false
        }
        
        let allArticlesRead = !items.isEmpty && !items.contains(where: { !$0.isRead }) && isRssFeed
        if allArticlesRead && indexPath.row == items.count {
            return nil
        }
        
        // Get the item
        let item = items[indexPath.row]
        let normalizedLink = normalizeLink(item.link)
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return UIMenu() }
            
            // Create menu actions for all swipe actions
            var menuActions: [UIMenuElement] = []
            
            // BOOKMARK ACTION
            let isBookmarked = self.bookmarkedItems.contains { self.normalizeLink($0) == normalizedLink }
            let bookmarkAction = UIAction(
                title: isBookmarked ? "Remove Bookmark" : "Bookmark",
                image: UIImage(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
            ) { [weak self] _ in
                self?.toggleBookmark(for: item) {
                    // Reload the table to update UI
                    self?.tableView.reloadData()
                }
            }
            menuActions.append(bookmarkAction)
            
            // HEART/FAVORITE ACTION
            let isHearted = self.heartedItems.contains { self.normalizeLink($0) == normalizedLink }
            let heartAction = UIAction(
                title: isHearted ? "Remove from Favorites" : "Add to Favorites",
                image: UIImage(systemName: isHearted ? "heart.fill" : "heart")
            ) { [weak self] _ in
                self?.toggleHeart(for: item) {
                    // Reload the table to update UI
                    self?.tableView.reloadData()
                }
            }
            menuActions.append(heartAction)
            
            // ARCHIVE ACTION
            let isArchived = self.archivedItems.contains { self.normalizeLink($0) == normalizedLink }
            let archiveAction = UIAction(
                title: isArchived ? "Remove from Archive" : "Archive",
                image: UIImage(systemName: isArchived ? "archivebox.fill" : "archivebox")
            ) { [weak self] _ in
                self?.toggleArchive(for: item) {
                    // Reload the table to update UI
                    self?.tableView.reloadData()
                }
            }
            menuActions.append(archiveAction)
            
            // READ/UNREAD ACTION
            let isItemRead = ReadStatusTracker.shared.isArticleRead(link: item.link)
            let readAction = UIAction(
                title: isItemRead ? "Mark as Unread" : "Mark as Read",
                image: UIImage(systemName: isItemRead ? "envelope.open.fill" : "envelope.fill")
            ) { [weak self] _ in
                self?.toggleReadStatus(for: item) {
                    // Reload the table to update UI
                    self?.tableView.reloadData()
                }
            }
            menuActions.append(readAction)
            
            // SHARE ACTION
            let shareAction = UIAction(
                title: "Share",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak self] _ in
                guard let self = self, let url = URL(string: item.link) else { return }
                
                let activityViewController = UIActivityViewController(
                    activityItems: [url],
                    applicationActivities: nil
                )
                
                // Present from the cell for iPad compatibility
                if let cell = tableView.cellForRow(at: indexPath) {
                    if let popoverController = activityViewController.popoverPresentationController {
                        popoverController.sourceView = cell
                        popoverController.sourceRect = cell.bounds
                    }
                } else {
                    // Fallback to presenting from view
                    if let popoverController = activityViewController.popoverPresentationController {
                        popoverController.sourceView = self.view
                        popoverController.sourceRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
                    }
                }
                
                self.present(activityViewController, animated: true)
            }
            menuActions.append(shareAction)
            
            // CACHE OFFLINE ACTION
            let isArticleCached = self.cachedArticleLinks.contains(self.normalizeLink(item.link))
            let cacheAction = UIAction(
                title: isArticleCached ? "Remove from Offline Cache" : "Save for Offline Reading",
                image: UIImage(systemName: isArticleCached ? "xmark.icloud" : "arrow.down.circle")
            ) { [weak self] _ in
                guard let self = self else { return }
                
                if isArticleCached {
                    // Remove from offline cache
                    StorageManager.shared.removeCachedArticle(link: item.link) { success, error in
                        if success {
                            DispatchQueue.main.async {
                                // Update UI
                                self.cachedArticleLinks.remove(self.normalizeLink(item.link))
                                self.tableView.reloadData()
                            }
                        }
                    }
                } else {
                    // Add to offline cache
                    self.cacheArticleForOfflineReading(item) { success in
                        if success {
                            DispatchQueue.main.async {
                                // Update UI
                                self.cachedArticleLinks.insert(self.normalizeLink(item.link))
                                self.tableView.reloadData()
                            }
                        }
                    }
                }
            }
            menuActions.append(cacheAction)
            
            // OPEN IN BROWSER ACTION
            let openAction = UIAction(
                title: "Open in Browser",
                image: UIImage(systemName: "safari")
            ) { [weak self] _ in
                guard let self = self else { return }
                self.openInSafari(item)
            }
            menuActions.append(openAction)
            
            // MANAGE TAGS ACTION
            let tagsAction = UIAction(
                title: "Manage Tags",
                image: UIImage(systemName: "tag")
            ) { [weak self] _ in
                self?.showTagManager(for: item)
            }
            menuActions.append(tagsAction)
            
            // MARK ABOVE AS READ ACTION
            if indexPath.row > 0 {
                let markAboveAction = UIAction(
                    title: "Mark Above as Read",
                    image: UIImage(systemName: "text.badge.checkmark")
                ) { [weak self] _ in
                    self?.markItemsAboveAsRead(indexPath)
                }
                menuActions.append(markAboveAction)
            }
            
            // Create and return the menu with all actions
            return UIMenu(title: "", children: menuActions)
        }
    }
    
    func showTagManager(for item: RSSItem) {
        // Create alert controller
        let alert = UIAlertController(title: "Manage Tags", message: "Apply tags to this article", preferredStyle: .actionSheet)
        
        // First, get all existing tags
        StorageManager.shared.getTags { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let tags):
                    // Get the tags for this item
                    item.getTags { itemTagsResult in
                        let itemTags: [Tag]
                        if case .success(let tags) = itemTagsResult {
                            itemTags = tags
                        } else {
                            itemTags = []
                        }
                        
                        // Add actions for each existing tag
                        for tag in tags.sorted(by: { $0.name < $1.name }) {
                            let isTagged = itemTags.contains { $0.id == tag.id }
                            let action = UIAlertAction(
                                title: isTagged ? "✓ \(tag.name)" : tag.name,
                                style: isTagged ? .destructive : .default
                            ) { _ in
                                // Toggle the tag
                                if isTagged {
                                    // Remove tag
                                    item.removeTag(tag) { [weak self] result in
                                        if case .success = result {
                                            // Force refresh the table
                                            DispatchQueue.main.async {
                                                self?.tableView.reloadData()
                                            }
                                        }
                                    }
                                } else {
                                    // Add tag
                                    item.addTag(tag) { [weak self] result in
                                        if case .success = result {
                                            // Force refresh the table
                                            DispatchQueue.main.async {
                                                self?.tableView.reloadData()
                                            }
                                        }
                                    }
                                }
                            }
                            alert.addAction(action)
                        }
                        
                        // Add an action to create a new tag
                        alert.addAction(UIAlertAction(title: "Create New Tag", style: .default) { [weak self] _ in
                            self?.showCreateTagDialog(for: item)
                        })
                        
                        // Add cancel action
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                        
                        // Present alert
                        if let popoverController = alert.popoverPresentationController {
                            popoverController.sourceView = self.view
                            popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                            popoverController.permittedArrowDirections = []
                        }
                        
                        self.present(alert, animated: true)
                    }
                    
                case .failure:
                    // If we can't get tags, just show the create new tag option
                    alert.addAction(UIAlertAction(title: "Create New Tag", style: .default) { [weak self] _ in
                        self?.showCreateTagDialog(for: item)
                    })
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    
                    if let popoverController = alert.popoverPresentationController {
                        popoverController.sourceView = self.view
                        popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                        popoverController.permittedArrowDirections = []
                    }
                    
                    self.present(alert, animated: true)
                }
            }
        }
    }
    
    func showCreateTagDialog(for item: RSSItem? = nil) {
        let alert = UIAlertController(
            title: "New Tag",
            message: "Enter a name for the new tag",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Tag Name"
        }
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let tagName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !tagName.isEmpty else {
                return
            }
            
            // Create the tag
            StorageManager.shared.createTag(name: tagName) { result in
                switch result {
                case .success(let newTag):
                    // If we have an item, add the tag to it
                    if let item = item {
                        item.addTag(newTag) { [weak self] tagResult in
                            if case .success = tagResult {
                                // Force refresh the table
                                DispatchQueue.main.async {
                                    self?.tableView.reloadData()
                                }
                            }
                        }
                    } else {
                        // Just reload the table to reflect any changes
                        DispatchQueue.main.async {
                            self.tableView.reloadData()
                        }
                    }
                case .failure:
                    // Show error message
                    let errorAlert = UIAlertController(
                        title: "Error",
                        message: "Failed to create tag",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    DispatchQueue.main.async {
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }

    func tableView(
        _ tableView: UITableView, didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // Check if this is our special "All Articles Read" footer cell
        let isRssFeed: Bool
        if case .rss = currentFeedType {
            isRssFeed = true
        } else {
            isRssFeed = false
        }
        
        let allArticlesRead = !items.isEmpty && !items.contains(where: { !$0.isRead }) && isRssFeed
        if allArticlesRead && indexPath.row == items.count {
            // Don't do anything for this special cell
            print("DEBUG: Special 'All Articles Read' cell tapped")
            return
        }
        
        // Handle differently in bulk edit mode
        if isBulkEditMode {
            // Toggle selection
            if selectedItems.contains(indexPath.row) {
                selectedItems.remove(indexPath.row)
            } else {
                selectedItems.insert(indexPath.row)
            }
            
            // Update the Select All / Deselect All button
            if selectedItems.count == items.count {
                navigationItem.rightBarButtonItems?[1].title = "Deselect All"
                navigationItem.rightBarButtonItems?[1].action = #selector(deselectAllBulkItems)
            } else {
                navigationItem.rightBarButtonItems?[1].title = "Select All"
                navigationItem.rightBarButtonItems?[1].action = #selector(selectAllBulkItems)
            }
            
            // Update navigation title with selection count
            updateNavigationBarTitle()
            
            // Update toolbar state
            updateBulkToolbarState()
            
            // Update the cell visually
            tableView.reloadRows(at: [indexPath], with: .none)
            return
        }
        
        // Regular mode behavior - open the article
        
        // Get the current item
        let item = items[indexPath.row]
        
        // Check if this is a duplicate and handle it if needed
        if isArticleDuplicate(item) && DuplicateManager.shared.handlingMode == .groupAndShow {
            if let group = getDuplicateGroup(for: item) {
                // If this is a duplicate but not the primary, show a menu to choose which one to view
                if group.primary.link != item.link {
                    showDuplicateOptions(for: group, atIndexPath: indexPath)
                    return
                }
            }
        }
        
        // Mark item as read
        items[indexPath.row].isRead = true  // Update the local item in the array
        
        // Mark as read in the ReadStatusTracker
        ReadStatusTracker.shared.markArticle(link: item.link, as: true)
        
        // Update the cell
        if let cell = tableView.cellForRow(at: indexPath) {
            configureCell(cell, with: items[indexPath.row])
        }
        
        // Check if we should use in-app reader or Safari
        let useInAppReader = UserDefaults.standard.bool(forKey: "useInAppReader")
        
        if useInAppReader {
            // Use our custom ArticleReaderViewController
            openInArticleReader(item)
        } else {
            // Use Safari with Reader Mode
            openInSafari(item)
        }
    }
    
    internal func openInArticleReader(_ item: RSSItem) {
        guard let _ = URL(string: item.link) else {
            // Show error if URL is invalid
            let alert = UIAlertController(
                title: "Error",
                message: "Invalid article URL",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        // Create a loading indicator view BEFORE creating the ArticleReaderViewController
        let loadingView = UIActivityIndicatorView(style: .medium)
        loadingView.startAnimating()
        loadingView.center = view.center
        view.addSubview(loadingView)
        
        // Check if article is cached before opening to avoid locks
        if isOfflineMode {
            let normalizedLink = normalizeLink(item.link)
            if !cachedArticleLinks.contains(normalizedLink) {
                // Not cached and offline - show alert and return
                loadingView.removeFromSuperview()
                let alert = UIAlertController(
                    title: "Article Not Cached",
                    message: "This article is not available offline. Connect to the internet to read it.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        }
        
        // Create ArticleReaderViewController after confirming we can read the article
        let articleReaderVC = ArticleReaderViewController()
        articleReaderVC.item = item
        
        // Pass all items and find the current index for swipe navigation
        articleReaderVC.allItems = self.items
        if let index = self.items.firstIndex(where: { $0.link == item.link }) {
            articleReaderVC.currentItemIndex = index
        }
        
        // Load cached content if offline
        if isOfflineMode {
            let normalizedLink = normalizeLink(item.link)
            if cachedArticleLinks.contains(normalizedLink) {
                // Pre-load cached content in background before showing controller
                StorageManager.shared.getCachedArticleContent(link: item.link) { result in
                    if case .success(let cachedArticle) = result {
                        DispatchQueue.main.async {
                            articleReaderVC.htmlContent = cachedArticle.content
                            // Now that content is loaded, navigate to the article reader
                            self.navigationController?.pushViewController(articleReaderVC, animated: true)
                            
                            // Remove the loading view after navigation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                loadingView.removeFromSuperview()
                            }
                        }
                    } else {
                        // Error loading cached content
                        DispatchQueue.main.async {
                            loadingView.removeFromSuperview()
                            let alert = UIAlertController(
                                title: "Error",
                                message: "Failed to load cached article",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(alert, animated: true)
                        }
                    }
                }
                return // Return early since we'll push the VC after content loads
            }
        }
        
        // For online mode, push the view controller and let it load content
        navigationController?.pushViewController(articleReaderVC, animated: true)
        
        // Remove the loading view after navigation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadingView.removeFromSuperview()
        }
    }
    
    internal func openInSafari(_ item: RSSItem) {
        guard let url = URL(string: item.link) else { return }
        
        // Check if offline mode and handle accordingly
        if isOfflineMode {
            let normalizedLink = normalizeLink(item.link)
            
            if cachedArticleLinks.contains(normalizedLink) {
                // Article is cached, offer to open in article reader
                let alert = UIAlertController(
                    title: "Offline Mode",
                    message: "Safari requires an internet connection. Would you like to open this article in the built-in reader using the cached version?",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Open Cached Version", style: .default) { [weak self] _ in
                    self?.openInArticleReader(item)
                })
                
                present(alert, animated: true)
            } else {
                // Article is not cached
                let alert = UIAlertController(
                    title: "No Internet Connection",
                    message: "Safari requires an internet connection, and this article is not available offline.",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
            
            return
        }
        
        // Check user preference for in-app browser
        let useInAppBrowser = UserDefaults.standard.bool(forKey: "useInAppBrowser")
        
        if useInAppBrowser {
            // Open in our in-app browser
            let webVC = WebViewController(url: url)
            navigationController?.pushViewController(webVC, animated: true)
        } else {
            // Use Safari View Controller
            // Create and show a loading alert before opening Safari
            let loadingAlert = UIAlertController(
                title: nil,
                message: "Opening link...",
                preferredStyle: .alert
            )
            
            // Add an activity indicator to the alert
            let loadingIndicator = UIActivityIndicatorView(style: .medium)
            loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
            loadingIndicator.startAnimating()
            
            // Add the indicator to the alert's view
            loadingAlert.view.addSubview(loadingIndicator)
            
            // Set up constraints
            NSLayoutConstraint.activate([
                loadingIndicator.centerYAnchor.constraint(equalTo: loadingAlert.view.centerYAnchor, constant: -10),
                loadingIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor)
            ])
            
            // Present the loading alert
            present(loadingAlert, animated: true)
            
            // Configure and prepare Safari VC
            let configuration = SFSafariViewController.Configuration()
            
            // Check if reader mode should be auto-enabled
            configuration.entersReaderIfAvailable = UserDefaults.standard.bool(forKey: "autoEnableReaderMode")
            
            let safariVC = SFSafariViewController(
                url: url, configuration: configuration)
            safariVC.dismissButtonStyle = .close
            safariVC.preferredControlTintColor = AppColors.accent
            safariVC.delegate = self
            
            // Dismiss the loading alert and show Safari after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                loadingAlert.dismiss(animated: true) {
                    self.present(safariVC, animated: true)
                }
            }
        }
    }

    func configureCell(_ cell: UITableViewCell, with item: RSSItem) {
        // Check if the item should be marked as read using the ReadStatusTracker
        let isItemRead = item.isRead || ReadStatusTracker.shared.isArticleRead(link: item.link)
        
        // Check if the article is cached
        let isArticleCached = cachedArticleLinks.contains(normalizeLink(item.link))
        
        // Get the font size from UserDefaults (defaulting to 16 if not set)
        let storedFontSize = CGFloat(UserDefaults.standard.float(forKey: "fontSize") != 0 ? UserDefaults.standard.float(forKey: "fontSize") : 16)
        
        if let enhancedCell = cell as? EnhancedRSSCell {
            // Configure the enhanced cell with cached state
            enhancedCell.configure(with: item, fontSize: storedFontSize, isRead: isItemRead, isCached: isArticleCached)
        } else {
            // Configure the default cell
            var config = cell.defaultContentConfiguration()
            
            config.text = item.title
            
            // Add "Cached" indicator to secondary text if article is cached
            var secondaryText = "\(item.source) • \(DateUtils.getTimeAgo(from: item.pubDate))"
            if isArticleCached {
                secondaryText += " • 📥 Cached"
            }
            
            // Add read status indicator to secondary text
            if isItemRead {
                secondaryText += " • 👁️ Read"
            }
            
            config.secondaryText = secondaryText
            
            // Apply text color based on read state
            config.textProperties.color = isItemRead ? AppColors.secondary : AppColors.accent
            config.secondaryTextProperties.color = AppColors.secondary
            config.secondaryTextProperties.font = .systemFont(ofSize: 12)
            
            config.textProperties.font = .systemFont(ofSize: storedFontSize, weight: isItemRead ? .regular : .medium)
            
            cell.contentConfiguration = config
            
            // Add tags to secondary text if any (for standard cells)
            item.getTags { result in
                if case .success(let tags) = result, !tags.isEmpty {
                    DispatchQueue.main.async {
                        var tagText = ""
                        for (index, tag) in tags.enumerated() {
                            if index == 0 {
                                tagText += " • 🏷️ "
                            } else {
                                tagText += ", "
                            }
                            tagText += tag.name
                        }
                        
                        // Update config with tags
                        var updatedConfig = cell.defaultContentConfiguration()
                        updatedConfig.text = config.text
                        updatedConfig.secondaryText = secondaryText + tagText
                        
                        // Apply text properties
                        updatedConfig.textProperties.color = isItemRead ? AppColors.secondary : AppColors.accent
                        updatedConfig.secondaryTextProperties.color = AppColors.secondary
                        updatedConfig.secondaryTextProperties.font = .systemFont(ofSize: 12)
                        updatedConfig.textProperties.font = .systemFont(ofSize: storedFontSize, weight: isItemRead ? .regular : .medium)
                        
                        // Update cell
                        cell.contentConfiguration = updatedConfig
                    }
                }
            }
        }
    }

    func toggleHeart(for item: RSSItem, completion: @escaping () -> Void) {
        // Use normalized link for consistent comparison
        let normalizedLink = normalizeLink(item.link)
        
        // Check if the item is already hearted by normalized link
        let isHearted = heartedItems.contains { normalizeLink($0) == normalizedLink }
        
        if isHearted {
            // Remove all versions of this link (both normalized and non-normalized)
            heartedItems = heartedItems.filter { normalizeLink($0) != normalizedLink }
        } else {
            // Add the normalized version of the link
            heartedItems.insert(normalizedLink)
        }

        StorageManager.shared.save(Array(heartedItems), forKey: "heartedItems")
        { error in
            if let error = error {
                print(
                    "Error saving hearted items: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func toggleBookmark(for item: RSSItem, completion: @escaping () -> Void) {
        // Use normalized link for consistent comparison
        let normalizedLink = normalizeLink(item.link)
        
        // Check if the item is already bookmarked by normalized link
        let isBookmarked = bookmarkedItems.contains { normalizeLink($0) == normalizedLink }
        
        if isBookmarked {
            // Remove all versions of this link (both normalized and non-normalized)
            bookmarkedItems = bookmarkedItems.filter { normalizeLink($0) != normalizedLink }
        } else {
            // Add the normalized version of the link
            bookmarkedItems.insert(normalizedLink)
        }

        StorageManager.shared.save(
            Array(bookmarkedItems), forKey: "bookmarkedItems"
        ) { error in
            if let error = error {
                print(
                    "Error saving bookmarked items: \(error.localizedDescription)"
                )
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func toggleReadStatus(for item: RSSItem, completion: @escaping () -> Void) {
        // Check current read status
        let isRead = ReadStatusTracker.shared.isArticleRead(link: item.link)
        
        // Toggle the status
        ReadStatusTracker.shared.markArticle(link: item.link, as: !isRead) { success in
            if success {
                // Update the local item
                if let index = self.items.firstIndex(where: { self.normalizeLink($0.link) == self.normalizeLink(item.link) }) {
                    self.items[index].isRead = !isRead
                }
                
                // Update the allItems array
                if let index = self._allItems.firstIndex(where: { self.normalizeLink($0.link) == self.normalizeLink(item.link) }) {
                    self._allItems[index].isRead = !isRead
                }
                
                // Check if we should update the read status indicator
                self.updateReadStatusIndicator()
            }
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func toggleArchive(for item: RSSItem, completion: @escaping () -> Void) {
        // Use normalized link for consistent comparison
        let normalizedLink = normalizeLink(item.link)
        
        // Check if the item is already archived by normalized link
        let isArchived = archivedItems.contains { normalizeLink($0) == normalizedLink }
        
        if isArchived {
            // Remove from archived items
            StorageManager.shared.unarchiveArticle(link: item.link) { success, error in
                if success {
                    // Update local state
                    DispatchQueue.main.async {
                        self.archivedItems = self.archivedItems.filter { self.normalizeLink($0) != normalizedLink }
                        
                        // If currently viewing archived feed, remove the item from the current view
                        if case .archive = self.currentFeedType {
                            if let index = self.items.firstIndex(where: { self.normalizeLink($0.link) == normalizedLink }) {
                                self.items.remove(at: index)
                                self.tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
                            }
                        }
                        
                        // Call completion handler
                        completion()
                    }
                } else {
                    print("ERROR: Failed to unarchive article: \(error?.localizedDescription ?? "Unknown error")")
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            }
        } else {
            // Add to archived items
            StorageManager.shared.archiveArticle(link: item.link) { success, error in
                if success {
                    // Update local state
                    DispatchQueue.main.async {
                        self.archivedItems.insert(normalizedLink)
                        completion()
                    }
                } else {
                    print("ERROR: Failed to archive article: \(error?.localizedDescription ?? "Unknown error")")
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            }
        }
    }
}

// MARK: - Table View Prefetching
extension HomeFeedViewController {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        // Prefetch cell data for smoother scrolling
        for indexPath in indexPaths {
            // Skip prefetching for out of bounds indexes
            guard indexPath.row < items.count else { continue }
            
            let item = items[indexPath.row]
            
            // Pre-compute and cache essential data needed for cells
            _ = normalizeLink(item.link)
            _ = ReadStatusTracker.shared.isArticleRead(link: item.link)
            
            // If we're using enhanced cells, prepare image loading
            if useEnhancedStyle, 
               UserDefaults.standard.bool(forKey: "showArticleImages"),
               let description = item.description,
               let imageUrlString = extractImageUrlFromDescription(description),
               let _ = URL(string: imageUrlString) {
                // Just prepare the URL, we'll let the cell load it when needed
                // This reduces unnecessary network requests for cells that might never be seen
            }
        }
    }
    
    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        // Cancel any expensive operations for rows that are no longer needed
        // Currently we don't need to do anything here as our prefetching is lightweight
    }
    
    // Helper method to extract image URL from description
    private func extractImageUrlFromDescription(_ description: String) -> String? {
        let pattern = "img\\s+[^>]*src\\s*=\\s*['\"]([^'\"]+)['\"]"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let matches = regex.matches(in: description, options: [], range: NSRange(location: 0, length: description.count))
        
        guard let match = matches.first,
              let range = Range(match.range(at: 1), in: description) else {
            return nil
        }
        
        return String(description[range])
    }
}

// MARK: - Safari View Controller Delegate
extension HomeFeedViewController: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true)
    }
}