import UIKit
import Foundation

// MARK: - Feed Loading & Management
extension HomeFeedViewController {
    
    // Load RSS feeds from storage and then fetch articles from each feed URL.
    func loadRSSFeeds() {
        // Hide tableView and show loading indicator
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        
        // Show the loading label with initial message
        loadingLabel.text = "Loading feeds..."
        loadingLabel.isHidden = false
        
        // Make sure the refresh icon is spinning
        startRefreshAnimation()
        
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let feeds):
                self.fetchFeedsContent(feeds: feeds)
                
            case .failure(let error):
                print("DEBUG: Error loading rssFeeds: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.refreshControl.endRefreshing()
                    // Show tableView even on error, but ensure it's reloaded first
                    self.tableView.reloadData()
                    
                    // Stop animations and show the tableView
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.stopRefreshAnimation()
                        self.loadingIndicator.stopAnimating()
                        self.loadingLabel.isHidden = true
                        self.tableView.isHidden = false
                        self.updateFooterVisibility()
                    }
                }
            }
        }
    }
    
    private func fetchFeedsContent(feeds: [RSSFeed]) {
        // Load read items (to filter out already-read links)
        StorageManager.shared.load(forKey: "readItems") { [weak self] (readResult: Result<[String], Error>) in
            guard let self = self else { return }
            
            var readLinks: Set<String> = []
            if case .success(let readItems) = readResult {
                readLinks = Set(readItems.map { self.normalizeLink($0) })
            }
            self.readLinks = readLinks // Store for later use
            
            // We'll gather all live feed items in this array
            var liveItems: [RSSItem] = []
            
            // A dispatch group to wait until all feed network calls finish
            let fetchGroup = DispatchGroup()
            
            // Counter for skipped feeds
            var skippedFeedsCount = 0
            
            // Fetch each feed
            for feed in feeds {
                guard let url = URL(string: feed.url) else { continue }
                
                // Check if this feed should be skipped based on historical performance
                if FeedLoadTimeManager.shared.shouldSkipFeed(titled: feed.title) {
                    // Skip this feed entirely
                    skippedFeedsCount += 1
                    
                    // Update loading label to show feed was skipped
                    DispatchQueue.main.async {
                        self.loadingLabel.text = "Skipped \(feed.title) (consistently slow/failed)"
                    }
                    
                    // Log the skip for debugging
                    print("DEBUG: Skipping feed \(feed.title) due to historical performance issues")
                    continue
                }
                
                fetchGroup.enter()
                let startTime = Date()
                
                // Update loading label with current feed
                DispatchQueue.main.async {
                    // Show load time if available
                    let previousLoadTime = FeedLoadTimeManager.shared.getLoadTime(for: feed.title)
                    if previousLoadTime > 0 {
                        let timeString = String(format: "%.1f", previousLoadTime)
                        self.loadingLabel.text = "Loading \(feed.title)... (est. \(timeString)s)"
                    } else {
                        self.loadingLabel.text = "Loading \(feed.title)..."
                    }
                }
                
                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    defer { 
                        let elapsedTime = Date().timeIntervalSince(startTime)
                        
                        // If there was an error, record it as a failed feed
                        if error != nil || data == nil {
                            FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
                        } else {
                            // Record the load time for this feed
                            FeedLoadTimeManager.shared.recordLoadTime(for: feed.title, time: elapsedTime)
                        }
                        
                        fetchGroup.leave() 
                    }
                    
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    // Skip if it took too long or if there was an error
                    if elapsedTime >= 45 || error != nil || data == nil {
                        DispatchQueue.main.async {
                            // Update loading label to show feed failed
                            if self.loadingLabel.text?.contains(feed.title) == true {
                                if error != nil {
                                    self.loadingLabel.text = "Failed to load \(feed.title): network error"
                                } else if elapsedTime >= 45 {
                                    self.loadingLabel.text = "Failed to load \(feed.title): timeout after \(Int(elapsedTime))s"
                                } else {
                                    self.loadingLabel.text = "Failed to load \(feed.title): no data"
                                }
                            }
                        }
                        return
                    }
                    
                    // Update loading label to show feed loaded successfully
                    DispatchQueue.main.async {
                        if self.loadingLabel.text?.contains(feed.title) == true {
                            let timeString = String(format: "%.1f", elapsedTime)
                            self.loadingLabel.text = "Loaded \(feed.title) in \(timeString)s"
                        }
                    }
                    
                    // Parse
                    if let data = data {
                        let parser = XMLParser(data: data)
                        let rssParser = RSSParser(source: feed.title)
                        parser.delegate = rssParser
                        
                        if parser.parse() {
                            // If no items were found, it might be an unsupported format
                            if rssParser.items.isEmpty {
                                DispatchQueue.main.async {
                                    self.loadingLabel.text = "No items found in \(feed.title)"
                                }
                            } else {
                                // Filter based on the "Show Read Articles" setting
                                let showReadArticles = UserDefaults.standard.bool(forKey: "showReadArticles")
                                
                                // First filter by read status
                                let readFiltered: [RSSItem]
                                if showReadArticles {
                                    // When showReadArticles is enabled, include all items
                                    // but mark them as read appropriately
                                    readFiltered = rssParser.items.map { item in
                                        let normLink = self.normalizeLink(item.link)
                                        var modifiedItem = item
                                        modifiedItem.isRead = readLinks.contains(normLink)
                                        return modifiedItem
                                    }
                                } else {
                                    // When showReadArticles is disabled, only include unread items
                                    readFiltered = rssParser.items.filter {
                                        let normLink = self.normalizeLink($0.link)
                                        return !readLinks.contains(normLink)
                                    }
                                }
                                
                                // Then filter by keywords if content filtering is enabled
                                let filtered: [RSSItem]
                                if self.isContentFilteringEnabled && !self.filterKeywords.isEmpty {
                                    // Filter out articles that match any of the filter keywords
                                    filtered = readFiltered.filter { !self.shouldFilterArticle($0) }
                                } else {
                                    // No keyword filtering, use all read-filtered items
                                    filtered = readFiltered
                                }
                                
                                liveItems.append(contentsOf: filtered)
                                
                                // Print some debug info about the feed type (RSS or Atom)
                                print("DEBUG: Successfully parsed \(feed.title) - Found \(rssParser.items.count) items")
                            }
                        } else {
                            // XML parsing failed - mark as failed feed
                            DispatchQueue.main.async {
                                self.loadingLabel.text = "Failed to parse \(feed.title): invalid feed format"
                            }
                            FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
                        }
                    }
                }
                task.resume()
            }
            
            // After all feeds are fetched, process the results
            fetchGroup.notify(queue: .main) {
                // Sort all items
                var finalItems = liveItems
                self.sortFilteredItems(&finalItems)
                
                // Filter items older than 30 days
                let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                let filteredItems = finalItems.filter { item in
                    guard let itemDate = DateUtils.parseDate(item.pubDate) else {
                        return false // Exclude if date can't be parsed
                    }
                    return itemDate >= thirtyDaysAgo
                }
                
                // Update the UI with the fetched items
                DispatchQueue.main.async {
                    // If we skipped any feeds, show a message briefly before completing
                    if skippedFeedsCount > 0 {
                        self.loadingLabel.text = "Skipped \(skippedFeedsCount) slow/failed feed" + (skippedFeedsCount > 1 ? "s" : "")
                        
                        // Delay for a moment so the message is visible
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.completeLoadingWithItems(filteredItems)
                        }
                    } else {
                        self.completeLoadingWithItems(filteredItems)
                    }
                }
            }
        }
    }
    
    // Helper to complete the loading process with the filtered items
    private func completeLoadingWithItems(_ filteredItems: [RSSItem]) {
        // Update our data source
        self._allItems = filteredItems
        
        // Set read status for all items
        for i in 0..<self._allItems.count {
            let normLink = self.normalizeLink(self._allItems[i].link)
            self._allItems[i].isRead = self.readLinks.contains(normLink)
        }
        
        // Update the currently displayed items if RSS feed is active
        if case .rss = self.currentFeedType {
            // Apply content filtering if enabled
            if self.isContentFilteringEnabled && !self.filterKeywords.isEmpty {
                // Filter out articles that match any of the filter keywords
                self.items = self._allItems.filter { !self.shouldFilterArticle($0) }
                print("DEBUG: Keyword filtered \(self._allItems.count) items to \(self.items.count) items")
            } else {
                // No keyword filtering
                self.items = self._allItems
            }
        }
        
        // First, reload the table while it's still hidden
        self.tableView.reloadData()
        
        // Update state and show the tableView
        self.refreshControl.endRefreshing()
        self.hasLoadedRSSFeeds = true
        self.updateFooterVisibility()
        
        // Show the tableView after everything is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.stopRefreshAnimation()
            self.loadingIndicator.stopAnimating()
            self.loadingLabel.isHidden = true
            self.tableView.isHidden = false
            self.updateFooterVisibility()
        }
    }
    
    // MARK: - Data Management
    
    // Save read state using asynchronous storage
    func saveReadState() {
        // Start with all links already in the readLinks set
        var combinedReadLinks = self.readLinks
        
        // Add all read items from the current view
        for item in self.items where item.isRead {
            combinedReadLinks.insert(self.normalizeLink(item.link))
        }
        
        // Also include any read items from allItems that may not be in the current view
        for item in self._allItems where item.isRead {
            combinedReadLinks.insert(self.normalizeLink(item.link))
        }
        
        if combinedReadLinks.isEmpty {
            return
        }
        
        // Update our cached read links set
        self.readLinks = combinedReadLinks
        
        // Use the improved merge-based save function in StorageManager
        StorageManager.shared.save(Array(combinedReadLinks), forKey: "readItems") { error in
            if let error = error {
                print("Error saving read items: \(error.localizedDescription)")
            } else {
                // Notify that read items have been updated so other views can refresh if needed
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("readItemsUpdated"), object: nil)
                }
            }
        }
    }
    
    @objc internal func refreshFeeds() {
        // Hide tableView and show loading indicator during refresh
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        startRefreshAnimation() // Start animation
        
        // Based on the current feed type, refresh the appropriate content
        switch currentFeedType {
        case .rss:
            // For main RSS feed, load all feeds
            loadRSSFeeds()
            
        case .folder(let folderId):
            // For folder view, only refresh the current folder
            if let folder = currentFolder, folder.id == folderId {
                loadFolderFeeds(folder: folder)
            } else {
                // Folder not loaded yet, load it first
                StorageManager.shared.getFolders { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        if case .success(let folders) = result,
                           let folder = folders.first(where: { $0.id == folderId }) {
                            self.currentFolder = folder
                            self.loadFolderFeeds(folder: folder)
                        } else {
                            // Folder not found, fall back to all feeds
                            self.loadRSSFeeds()
                        }
                    }
                }
            }
            
        default:
            // For other feed types (bookmarks, heart), go back to standard behavior
            loadRSSFeeds()
        }
    }
}