import UIKit
import SafariServices
import Foundation

// MARK: - TableView Delegate and DataSource
extension HomeFeedViewController: UITableViewDelegate, UITableViewDataSource {

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
        if currentMinVisibleRow > previousMinVisibleRow {
            var indexPathsToUpdate: [IndexPath] = []

            // Iterate through the rows that have just scrolled off the top
            for index in previousMinVisibleRow..<currentMinVisibleRow {
                // Ensure the index is valid
                if index >= 0 && index < items.count {
                    let normLink = normalizeLink(items[index].link)
                    if !items[index].isRead && !readLinks.contains(normLink) {
                        items[index].isRead = true
                        indexPathsToUpdate.append(IndexPath(row: index, section: 0))
                    }
                }
            }

            // If any items were marked as read, save the state and reload the rows
            if !indexPathsToUpdate.isEmpty {
                scheduleSaveReadState()
                // Use .none to avoid animation glitches during scrolling
                tableView.reloadRows(at: indexPathsToUpdate, with: .none)
            }
        }

        // Update the tracker for the next scroll event
        previousMinVisibleRow = currentMinVisibleRow
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
        heartAction.image = UIImage(named: isHearted ? "heartFilled" : "heart")?
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
            named: isBookmarked ? "bookmarkFilled" : "bookmark")?
            .withRenderingMode(.alwaysTemplate)
        bookmarkAction.backgroundColor = AppColors.primary

        return UISwipeActionsConfiguration(actions: [
            bookmarkAction, heartAction,
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
        
        // Check if the item should be marked as read based on normalized link
        let normLink = normalizeLink(item.link)
        let isItemRead = item.isRead || readLinks.contains(normLink)
        
        // Check if the article is cached
        let isArticleCached = cachedArticleLinks.contains(normLink)
        
        // Get the font size from UserDefaults (defaulting to 16 if not set)
        let storedFontSize = CGFloat(UserDefaults.standard.float(forKey: "fontSize") != 0 ? UserDefaults.standard.float(forKey: "fontSize") : 16)
        
        if useEnhancedStyle {
            // Use the enhanced card-style cell
            let cell = tableView.dequeueReusableCell(
                withIdentifier: EnhancedRSSCell.identifier, for: indexPath) as! EnhancedRSSCell
            
            // Configure with item data
            cell.configure(with: item, fontSize: storedFontSize, isRead: isItemRead)
            
            // Add cache indicator if article is cached
            if isArticleCached {
                addCacheIndicator(to: cell)
            } else {
                removeCacheIndicator(from: cell)
            }
            
            return cell
        } else {
            // Use the default plain text cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "RSSCell", for: indexPath)
            
            // Configure cell with read state
            var config = cell.defaultContentConfiguration()
            config.text = item.title
            
            // Add "Cached" indicator to secondary text if article is cached
            var secondaryText = "\(item.source) • \(DateUtils.getTimeAgo(from: item.pubDate))"
            if isArticleCached {
                secondaryText += " • 📥 Cached"
            }
            config.secondaryText = secondaryText
            
            cell.backgroundColor = AppColors.background
            
            // Apply text color based on read state - MORE CONTRAST between read/unread
            config.textProperties.color = isItemRead ? AppColors.secondary : AppColors.accent
            config.secondaryTextProperties.color = AppColors.secondary
            config.secondaryTextProperties.font = .systemFont(ofSize: 12)
            
            config.textProperties.font = .systemFont(ofSize: storedFontSize, weight: isItemRead ? .regular : .medium)
            
            cell.accessoryType = .disclosureIndicator
            cell.contentConfiguration = config
            
            return cell
        }
    }
    
    // Helper method to add a cache indicator to a cell
    private func addCacheIndicator(to cell: UITableViewCell) {
        // Remove any existing indicator first
        removeCacheIndicator(from: cell)
        
        // Create a small badge icon to indicate cached status
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 12))
        indicator.backgroundColor = AppColors.cacheIndicator
        indicator.layer.cornerRadius = 6
        indicator.tag = 999 // Tag for identification
        
        // Add to cell
        if let contentView = cell as? EnhancedRSSCell {
            // For enhanced cells, place it in the card corner
            contentView.addSubview(indicator)
            
            // Position in top right corner with margins
            indicator.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                indicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                indicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
                indicator.widthAnchor.constraint(equalToConstant: 12),
                indicator.heightAnchor.constraint(equalToConstant: 12)
            ])
        } else {
            // For standard cells, add to the right side
            cell.accessoryView = indicator
        }
    }
    
    // Helper method to remove a cache indicator from a cell
    private func removeCacheIndicator(from cell: UITableViewCell) {
        // Remove from enhanced cell
        if let contentView = cell as? EnhancedRSSCell {
            if let indicator = contentView.viewWithTag(999) {
                indicator.removeFromSuperview()
            }
        } 
        // Remove from standard cell
        else if cell.accessoryView?.tag == 999 {
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
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
        
        // Mark item as read
        let item = items[indexPath.row]
        items[indexPath.row].isRead = true  // Properly update the item in the array
        if let cell = tableView.cellForRow(at: indexPath) {
            configureCell(cell, with: items[indexPath.row])
        }
        scheduleSaveReadState()
        
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
    
    private func openInArticleReader(_ item: RSSItem) {
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
        
        // Create and configure the article reader
        let articleReaderVC = ArticleReaderViewController()
        articleReaderVC.item = item
        
        // If offline and article is cached, load cached content
        if isOfflineMode {
            let normalizedLink = normalizeLink(item.link)
            if cachedArticleLinks.contains(normalizedLink) {
                // Load cached content
                StorageManager.shared.getCachedArticleContent(link: item.link) { result in
                    if case .success(let cachedArticle) = result {
                        DispatchQueue.main.async {
                            articleReaderVC.htmlContent = cachedArticle.content
                        }
                    }
                }
            } else {
                // Show alert that article is not available offline
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
        
        // Create a loading indicator view
        let loadingView = UIActivityIndicatorView(style: .medium)
        loadingView.startAnimating()
        loadingView.center = view.center
        view.addSubview(loadingView)
        
        // Navigate to the article reader view
        navigationController?.pushViewController(articleReaderVC, animated: true)
        
        // Remove the loading view after navigation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadingView.removeFromSuperview()
        }
    }
    
    private func openInSafari(_ item: RSSItem) {
        guard let url = URL(string: item.link) else { return }
        
        // Check if offline and offer cached version if available
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

    func configureCell(_ cell: UITableViewCell, with item: RSSItem) {
        // Check if the item should be marked as read based on normalized link
        let normLink = normalizeLink(item.link)
        let isItemRead = item.isRead || readLinks.contains(normLink)
        
        // Get the font size from UserDefaults (defaulting to 16 if not set)
        let storedFontSize = CGFloat(UserDefaults.standard.float(forKey: "fontSize") != 0 ? UserDefaults.standard.float(forKey: "fontSize") : 16)
        
        if let enhancedCell = cell as? EnhancedRSSCell {
            // Configure the enhanced cell
            enhancedCell.configure(with: item, fontSize: storedFontSize, isRead: isItemRead)
        } else {
            // Configure the default cell
            var config = cell.defaultContentConfiguration()
            
            config.text = item.title
            config.secondaryText = "\(item.source) • \(DateUtils.getTimeAgo(from: item.pubDate))"
            
            // Apply text color based on read state
            config.textProperties.color = isItemRead ? AppColors.secondary : AppColors.accent
            config.secondaryTextProperties.color = AppColors.secondary
            config.secondaryTextProperties.font = .systemFont(ofSize: 12)
            
            config.textProperties.font = .systemFont(ofSize: storedFontSize, weight: isItemRead ? .regular : .medium)
            
            cell.contentConfiguration = config
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
}

// MARK: - Safari View Controller Delegate
extension HomeFeedViewController: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true)
    }
}