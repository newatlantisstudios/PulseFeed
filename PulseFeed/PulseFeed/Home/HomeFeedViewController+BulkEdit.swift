import UIKit

// MARK: - Bulk Editing Mode
extension HomeFeedViewController {
    
    // MARK: - Properties
    
    // MARK: - Bulk Edit Mode Toggle
    
    func toggleBulkEditState() {
        isBulkEditMode = !isBulkEditMode
        
        if isBulkEditMode {
            enterBulkEditMode()
        } else {
            exitBulkEditMode()
        }
    }
    
    private func enterBulkEditMode() {
        // Save original right bar button items
        originalRightBarButtonItems = navigationItem.rightBarButtonItems
        
        // Add cancel button to exit bulk edit mode
        let cancelButton = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(exitBulkEditModeAction)
        )
        
        // Add select all button
        let selectAllButton = UIBarButtonItem(
            title: "Select All",
            style: .plain,
            target: self,
            action: #selector(selectAllBulkItems)
        )
        
        // Set new right bar button items
        navigationItem.rightBarButtonItems = [cancelButton, selectAllButton]
        
        // Disable refresh control while in bulk edit mode
        refreshControl.isEnabled = false
        
        // Clear any existing selections
        selectedItems.removeAll()
        
        // Update the navigation title
        updateNavigationBarTitle()
        
        // Create and show bulk action toolbar
        setupBulkActionToolbar()
        
        // Reload table to show checkmarks
        tableView.reloadData()
    }
    
    private func exitBulkEditMode() {
        // Restore original title
        updateNavigationBarTitle()
        
        // Restore original right bar button items
        if let originalItems = originalRightBarButtonItems {
            navigationItem.rightBarButtonItems = originalItems
        }
        
        // Enable refresh control
        refreshControl.isEnabled = true
        
        // Clear selections
        selectedItems.removeAll()
        
        // Remove bulk action toolbar
        removeBulkActionToolbar()
        
        // Reload table to remove checkmarks
        tableView.reloadData()
    }
    
    @objc private func exitBulkEditModeAction() {
        toggleBulkEditState()
    }
    
    @objc func selectAllBulkItems() {
        // Select all items
        for i in 0..<items.count {
            selectedItems.insert(i)
        }
        
        // Update button title based on selection state
        if selectedItems.count == items.count {
            // If all are selected, change to "Deselect All"
            navigationItem.rightBarButtonItems?[1].title = "Deselect All"
            navigationItem.rightBarButtonItems?[1].action = #selector(deselectAllBulkItems)
        }
        
        // Update navigation title with selection count
        updateNavigationBarTitle()
        
        // Update toolbar enabled state
        updateBulkEditToolbarButtons()
        
        // Reload table to show checkmarks
        tableView.reloadData()
    }
    
    @objc func deselectAllBulkItems() {
        // Deselect all items
        selectedItems.removeAll()
        
        // Change button back to "Select All"
        navigationItem.rightBarButtonItems?[1].title = "Select All"
        navigationItem.rightBarButtonItems?[1].action = #selector(selectAllBulkItems)
        
        // Update navigation title
        updateNavigationBarTitle()
        
        // Update toolbar enabled state
        updateBulkEditToolbarButtons()
        
        // Reload table to remove checkmarks
        tableView.reloadData()
    }
    
    // MARK: - Bulk Action Toolbar
    
    private func setupBulkActionToolbar() {
        // Create toolbar
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.barTintColor = AppColors.background
        
        // Add toolbar items
        let markReadButton = UIBarButtonItem(
            title: "Mark Read",
            style: .plain,
            target: self,
            action: #selector(markSelectedItemsAsRead)
        )
        
        let markUnreadButton = UIBarButtonItem(
            title: "Mark Unread",
            style: .plain,
            target: self,
            action: #selector(markSelectedItemsAsUnread)
        )
        
        
        let saveOfflineButton = UIBarButtonItem(
            title: "Save Offline",
            style: .plain,
            target: self,
            action: #selector(saveSelectedItemsOffline)
        )
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        toolbar.items = [
            markReadButton,
            flexSpace,
            markUnreadButton,
            flexSpace,
            saveOfflineButton
        ]
        
        // Add to view
        view.addSubview(toolbar)
        
        // Set constraints
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Store reference
        bulkEditToolbar = toolbar
        
        // Initially disable all buttons until selection is made
        updateBulkEditToolbarButtons()
        
        // Adjust table view insets to show the toolbar
        let insets = UIEdgeInsets(
            top: tableView.contentInset.top,
            left: tableView.contentInset.left,
            bottom: toolbar.intrinsicContentSize.height + 10,
            right: tableView.contentInset.right
        )
        tableView.contentInset = insets
        tableView.scrollIndicatorInsets = insets
    }
    
    private func removeBulkActionToolbar() {
        // Remove toolbar from view
        bulkEditToolbar?.removeFromSuperview()
        bulkEditToolbar = nil
        
        // Reset table view insets
        let insets = UIEdgeInsets(
            top: tableView.contentInset.top,
            left: tableView.contentInset.left,
            bottom: 0,
            right: tableView.contentInset.right
        )
        tableView.contentInset = insets
        tableView.scrollIndicatorInsets = insets
    }
    
    // Use the implementation from HomeFeedViewController+UI.swift instead
    private func updateBulkEditToolbarButtons() {
        guard let toolbar = bulkEditToolbar, let items = toolbar.items else {
            return
        }
        
        // Enable buttons only if items are selected
        let isEnabled = !selectedItems.isEmpty
        
        for item in items {
            // Skip flexible space items
            if item.style != .plain {
                continue
            }
            
            item.isEnabled = isEnabled
            
            // Set button text color based on enabled state
            if isEnabled {
                item.tintColor = AppColors.accent
            } else {
                item.tintColor = AppColors.secondary
            }
        }
    }
    
    // MARK: - Bulk Actions
    
    @objc private func markSelectedItemsAsRead() {
        guard !selectedItems.isEmpty else { return }
        
        // Collect links for selected items
        var linksToMark: [String] = []
        
        for index in selectedItems {
            if index < items.count {
                linksToMark.append(items[index].link)
                items[index].isRead = true
            }
        }
        
        // Mark the articles as read
        ReadStatusTracker.shared.markArticles(links: linksToMark, as: true)
        
        // Reload affected rows
        let indexPaths = selectedItems.map { IndexPath(row: $0, section: 0) }
        tableView.reloadRows(at: indexPaths, with: .fade)
        
        // Show confirmation toast
        showToast(message: "\(linksToMark.count) items marked as read")
    }
    
    @objc private func markSelectedItemsAsUnread() {
        guard !selectedItems.isEmpty else { return }
        
        // Collect links for selected items
        var linksToMark: [String] = []
        
        for index in selectedItems {
            if index < items.count {
                linksToMark.append(items[index].link)
                items[index].isRead = false
            }
        }
        
        // Mark the articles as unread
        ReadStatusTracker.shared.markArticles(links: linksToMark, as: false)
        
        // Reload affected rows
        let indexPaths = selectedItems.map { IndexPath(row: $0, section: 0) }
        tableView.reloadRows(at: indexPaths, with: .fade)
        
        // Show confirmation toast
        showToast(message: "\(linksToMark.count) items marked as unread")
    }
    
    
    @objc private func saveSelectedItemsOffline() {
        guard !selectedItems.isEmpty else { return }
        
        // Show confirmation dialog
        let alert = UIAlertController(
            title: "Save Offline",
            message: "Save \(selectedItems.count) articles for offline reading?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            self?.startSavingSelectedItemsOffline()
        })
        
        present(alert, animated: true)
    }
    
    private func startSavingSelectedItemsOffline() {
        guard !selectedItems.isEmpty else { return }
        
        // Items to process
        let itemsToSave = selectedItems.compactMap { index -> RSSItem? in
            guard index < items.count else { return nil }
            return items[index]
        }
        
        // Show progress alert
        let progressAlert = UIAlertController(
            title: "Saving Articles",
            message: "Saving 0 of \(itemsToSave.count) articles...",
            preferredStyle: .alert
        )
        
        // Add progress indicator
        let indicator = UIProgressView(progressViewStyle: .default)
        indicator.progress = 0
        indicator.translatesAutoresizingMaskIntoConstraints = false
        progressAlert.view.addSubview(indicator)
        
        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: progressAlert.view.leadingAnchor, constant: 20),
            indicator.trailingAnchor.constraint(equalTo: progressAlert.view.trailingAnchor, constant: -20),
            indicator.bottomAnchor.constraint(equalTo: progressAlert.view.bottomAnchor, constant: -20),
            indicator.heightAnchor.constraint(equalToConstant: 4)
        ])
        
        // Add cancel button
        progressAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            // Set cancel flag
            self?.isCachingCancelled = true
        })
        
        present(progressAlert, animated: true) { [weak self] in
            guard let self = self else { return }
            
            // Start caching process
            self.processArticleCaching(
                items: itemsToSave,
                currentIndex: 0,
                successCount: 0,
                progressAlert: progressAlert,
                progressView: indicator
            )
        }
    }
    
    private func processArticleCaching(
        items: [RSSItem],
        currentIndex: Int,
        successCount: Int,
        progressAlert: UIAlertController,
        progressView: UIProgressView
    ) {
        // Check if we're done or cancelled
        if currentIndex >= items.count || isCachingCancelled {
            // Complete the process
            DispatchQueue.main.async { [weak self] in
                // Dismiss the progress alert
                progressAlert.dismiss(animated: true) {
                    // Show completion message if not cancelled
                    if !(self?.isCachingCancelled ?? true) {
                        self?.showToast(message: "Saved \(successCount) of \(items.count) articles offline")
                    }
                    
                    // Reset cancellation flag
                    self?.isCachingCancelled = false
                    
                    // Reload table to show cached indicators
                    self?.tableView.reloadData()
                }
            }
            return
        }
        
        // Get the current item to cache
        let item = items[currentIndex]
        
        // Skip if already cached
        let isAlreadyCached = cachedArticleLinks.contains(normalizeLink(item.link))
        if isAlreadyCached {
            // Update progress
            let progress = Float(currentIndex + 1) / Float(items.count)
            
            DispatchQueue.main.async {
                // Update progress bar
                progressView.progress = progress
                
                // Update message
                progressAlert.message = "Saving \(currentIndex + 1) of \(items.count) articles..."
                
                // Continue with next item (already successful)
                self.processArticleCaching(
                    items: items,
                    currentIndex: currentIndex + 1,
                    successCount: successCount + 1,
                    progressAlert: progressAlert,
                    progressView: progressView
                )
            }
            return
        }
        
        // Cache the current article
        cacheArticleForOfflineReadingQuietly(item) { [weak self] success in
            guard let self = self else { return }
            
            // Update progress
            let progress = Float(currentIndex + 1) / Float(items.count)
            let newSuccessCount = success ? successCount + 1 : successCount
            
            DispatchQueue.main.async {
                // Update progress bar
                progressView.progress = progress
                
                // Update message
                progressAlert.message = "Saving \(currentIndex + 1) of \(items.count) articles..."
                
                // Continue with next item
                self.processArticleCaching(
                    items: items,
                    currentIndex: currentIndex + 1,
                    successCount: newSuccessCount,
                    progressAlert: progressAlert,
                    progressView: progressView
                )
            }
        }
    }
    
    // A variation of cacheArticleForOfflineReading that doesn't show UI for each article
    func cacheArticleForOfflineReadingQuietly(_ item: RSSItem, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: item.link) else {
            completion(false)
            return
        }
        
        // Use ContentExtractor to grab the article content
        let content = ContentExtractor.extractReadableContent(from: "", url: url)
        
        // Cache the article with the extracted content
        StorageManager.shared.cacheArticleContent(
            link: item.link,
            content: content,
            title: item.title,
            source: item.source
        ) { success, _ in
            // If successful, update cached articles set
            if success {
                DispatchQueue.main.async {
                    self.cachedArticleLinks.insert(self.normalizeLink(item.link))
                }
            }
            
            // Call completion handler with result
            completion(success)
        }
    }
}