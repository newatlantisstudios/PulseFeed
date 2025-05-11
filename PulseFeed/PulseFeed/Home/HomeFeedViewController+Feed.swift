import UIKit
import Foundation

// MARK: - Feed Loading & Management
extension HomeFeedViewController {
    
    // Load RSS feeds from storage and then fetch articles from each feed URL.
    func loadRSSFeeds() {
        isLoading = true
        print("DEBUG: isLoading set to true in loadRSSFeeds start")
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
                // Record the refresh time for all feeds being refreshed
                for feed in feeds {
                    RefreshIntervalManager.shared.recordRefresh(forFeed: feed.url)
                }
                
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
                        
                        // Scroll to top safely
                        self.safeScrollToTop()
                        self.isLoading = false
                        print("DEBUG: isLoading set to false in loadRSSFeeds failure handler")
                    }
                }
            }
        }
    }
    
    private func fetchFeedsContent(feeds: [RSSFeed]) {
        // Get read items directly from ReadStatusTracker
        let readLinks = Set(ReadStatusTracker.shared.getAllReadLinks())
        self.readLinks = readLinks // Keep the readLinks property for backward compatibility
            
            // We'll gather all live feed items in this array
            var liveItems: [RSSItem] = []
            let liveItemsQueue = DispatchQueue(label: "com.pulsefeed.liveItemsQueue") // Serial queue for synchronized access
            
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
                                // Analyze this feed to determine if it's a partial feed
                                // This will help with future extraction decisions
                                FullTextExtractor.shared.analyzeAndTrackPartialFeed(
                                    items: rssParser.items, 
                                    source: feed.title
                                )
                                
                                // Filter based on the "Hide Read Articles" setting
                                let hideReadArticles = UserDefaults.standard.bool(forKey: "hideReadArticles")
                                
                                // First filter by read status
                                let readFiltered: [RSSItem]
                                if hideReadArticles {
                                    // When setting is enabled, only include unread items
                                    readFiltered = rssParser.items.filter {
                                        let normLink = self.normalizeLink($0.link)
                                        return !readLinks.contains(normLink)
                                    }
                                } else {
                                    // When setting is disabled, include all items
                                    // but mark them as read appropriately
                                    readFiltered = rssParser.items.map { item in
                                        let normLink = self.normalizeLink(item.link)
                                        var modifiedItem = item
                                        modifiedItem.isRead = readLinks.contains(normLink)
                                        return modifiedItem
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
                                
                                // Synchronize access to liveItems
                                liveItemsQueue.sync {
                                    liveItems.append(contentsOf: filtered)
                                }
                                
                                // Print some debug info about the feed type (RSS or Atom)
                                //print("DEBUG: Successfully parsed \(feed.title) - Found \(rssParser.items.count) items")
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
            fetchGroup.notify(queue: .main) { [weak self] in // Keep self weak to avoid retain cycles if self can be deallocated before notify block executes
                guard let self = self else { return }
                // Update loading message to indicate article processing stage - on main thread
                self.loadingLabel.text = "Processing articles..."

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in // Move processing to a background queue
                    guard let self = self else { return }

                    // Sort all items
                    var finalItems = liveItems // Ensure liveItems is captured appropriately, or passed if necessary.
                                               // If liveItems is modified by other threads, synchronization is needed.
                                               // Assuming it's a snapshot at this point.
                    self.sortFilteredItems(&finalItems)
                    
                    // Filter items older than 30 days
                    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                    let filteredItems = finalItems.filter { item in
                        guard let itemDate = DateUtils.parseDate(item.pubDate) else {
                            return false // Exclude if date can't be parsed
                        }
                        return itemDate >= thirtyDaysAgo
                    }
                    
                    // Update the UI with the fetched items on the main thread
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        // If we skipped any feeds, show a message briefly before completing
                        if skippedFeedsCount > 0 { // Ensure skippedFeedsCount is also captured or accessed safely
                            self.loadingLabel.text = "Skipped \(skippedFeedsCount) slow/failed feed" + (skippedFeedsCount > 1 ? "s" : "")
                            
                            // Delay for a moment so the message is visible, then call completeLoadingWithItems
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                                guard let self = self else { return }
                                // Always call completeLoadingWithItems; it will handle the empty state.
                                self.completeLoadingWithItems(filteredItems)
                            }
                        } else {
                            // Always call completeLoadingWithItems; it will handle the empty state.
                            self.completeLoadingWithItems(filteredItems)
                        }
                        self.isLoading = false
                        print("DEBUG: isLoading set to false in fetchFeedsContent after all feeds processed")
                    }
                }
            }
        }
    }
    
    
    // MARK: - Data Management
    
    // Reference to the loadSmartFolderContents and filterArticlesForSmartFolder
    // are defined in HomeFeedViewController.swift
    // Removing the duplicate implementation here to fix the build issue
    
    // MARK: - Specialized Feed Types
    // Note: The loadArchivedFeeds function has been moved to HomeFeedViewController for better organization
    
