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
        if count > 0 && !items.contains(where: { !$0.isRead }) && currentFeedType == .rss {
            return count + 1 // Add an extra row for "All Articles Read" message
        }
        
        return count
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        // Check if this is our special "All Articles Read" footer cell
        let allArticlesRead = !items.isEmpty && !items.contains(where: { !$0.isRead }) && currentFeedType == .rss
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
        let allArticlesRead = !items.isEmpty && !items.contains(where: { !$0.isRead }) && currentFeedType == .rss
        
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
        
        // Get the font size from UserDefaults (defaulting to 16 if not set)
        let storedFontSize = CGFloat(UserDefaults.standard.float(forKey: "fontSize") != 0 ? UserDefaults.standard.float(forKey: "fontSize") : 16)
        
        if useEnhancedStyle {
            // Use the enhanced card-style cell
            let cell = tableView.dequeueReusableCell(
                withIdentifier: EnhancedRSSCell.identifier, for: indexPath) as! EnhancedRSSCell
            
            // Configure with item data
            cell.configure(with: item, fontSize: storedFontSize, isRead: isItemRead)
            
            return cell
        } else {
            // Use the default plain text cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "RSSCell", for: indexPath)
            
            // Configure cell with read state
            var config = cell.defaultContentConfiguration()
            config.text = item.title
            config.secondaryText = "\(item.source) • \(DateUtils.getTimeAgo(from: item.pubDate))"
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

    func tableView(
        _ tableView: UITableView, didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // Check if this is our special "All Articles Read" footer cell
        let allArticlesRead = !items.isEmpty && !items.contains(where: { !$0.isRead }) && currentFeedType == .rss
        if allArticlesRead && indexPath.row == items.count {
            // Don't do anything for this special cell
            print("DEBUG: Special 'All Articles Read' cell tapped")
            return
        }
        
        // Regular article cell handling
        if let url = URL(string: items[indexPath.row].link) {
            items[indexPath.row].isRead = true
            if let cell = tableView.cellForRow(at: indexPath) {
                configureCell(cell, with: items[indexPath.row])
            }
            scheduleSaveReadState()
            
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
            configuration.entersReaderIfAvailable = true
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