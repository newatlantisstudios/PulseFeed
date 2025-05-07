import UIKit

class NonWorkingFeedsViewController: UITableViewController {
    
    // Data source: list of non-working feeds
    var nonWorkingFeeds: [RSSFeed] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Non-Working Feeds"
        
        // Register our cell class
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NonWorkingFeedCell")
        
        setupNavigationBar()
        
        // Load non-working feeds
        loadNonWorkingFeeds()
    }
    
    private func setupNavigationBar() {
        // Add a refresh button
        let refreshButton = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(checkFeeds)
        )
        
        // Add a remove all button
        let removeAllButton = UIBarButtonItem(
            title: "Remove All",
            style: .plain,
            target: self,
            action: #selector(removeAllFeeds)
        )
        removeAllButton.tintColor = .systemRed
        
        navigationItem.rightBarButtonItems = [refreshButton, removeAllButton]
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data in case feeds status has changed
        loadNonWorkingFeeds()
    }
    
    private func loadNonWorkingFeeds() {
        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        navigationItem.titleView = activityIndicator
        
        // Load all feeds first
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let feeds):
                // Filter out feeds that are marked as problematic
                self.nonWorkingFeeds = feeds.filter { feed in
                    return FeedLoadTimeManager.shared.shouldSkipFeed(titled: feed.title) ||
                           FeedLoadTimeManager.shared.getFailureCount(for: feed.title) > 0
                }
                
                DispatchQueue.main.async {
                    // Update UI
                    self.navigationItem.titleView = nil
                    self.title = "Non-Working Feeds (\(self.nonWorkingFeeds.count))"
                    self.tableView.reloadData()
                    
                    // Show a message if no problematic feeds found
                    if self.nonWorkingFeeds.isEmpty {
                        let emptyLabel = UILabel()
                        emptyLabel.text = "No problematic feeds found"
                        emptyLabel.textAlignment = .center
                        emptyLabel.textColor = .gray
                        self.tableView.backgroundView = emptyLabel
                    } else {
                        self.tableView.backgroundView = nil
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.navigationItem.titleView = nil
                    self.title = "Non-Working Feeds"
                    self.showError("Failed to load feeds: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func checkFeeds() {
        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        navigationItem.titleView = activityIndicator
        
        // First load all feeds
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let feeds):
                // Validate each feed
                self.validateFeeds(feeds) { updatedNonWorkingFeeds in
                    DispatchQueue.main.async {
                        self.nonWorkingFeeds = updatedNonWorkingFeeds
                        self.navigationItem.titleView = nil
                        self.title = "Non-Working Feeds (\(updatedNonWorkingFeeds.count))"
                        self.tableView.reloadData()
                        
                        // Show a message if no problematic feeds found
                        if self.nonWorkingFeeds.isEmpty {
                            let emptyLabel = UILabel()
                            emptyLabel.text = "No problematic feeds found"
                            emptyLabel.textAlignment = .center
                            emptyLabel.textColor = .gray
                            self.tableView.backgroundView = emptyLabel
                        } else {
                            self.tableView.backgroundView = nil
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.navigationItem.titleView = nil
                    self.title = "Non-Working Feeds"
                    self.showError("Failed to load feeds: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func validateFeeds(_ feeds: [RSSFeed], completion: @escaping ([RSSFeed]) -> Void) {
        let dispatchGroup = DispatchGroup()
        var nonWorkingFeeds: [RSSFeed] = []
        
        for feed in feeds {
            dispatchGroup.enter()
            
            // Check if the feed already has a high failure count
            if FeedLoadTimeManager.shared.shouldSkipFeed(titled: feed.title) {
                nonWorkingFeeds.append(feed)
                dispatchGroup.leave()
                continue
            }
            
            // Try to fetch the feed to see if it's working
            guard let url = URL(string: feed.url) else {
                dispatchGroup.leave()
                continue
            }
            
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                defer { dispatchGroup.leave() }
                
                // Check for errors
                if let error = error {
                    print("Feed validation error for \(feed.title): \(error.localizedDescription)")
                    FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
                    nonWorkingFeeds.append(feed)
                    return
                }
                
                // Check if we got data and it's a valid RSS/Atom feed
                guard let data = data,
                      let xmlString = String(data: data, encoding: .utf8),
                      xmlString.contains("<rss") || xmlString.contains("<feed") else {
                    print("Feed validation failed for \(feed.title): Invalid format")
                    FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
                    nonWorkingFeeds.append(feed)
                    return
                }
                
                // Further validate by checking if parsing works
                let parser = XMLParser(data: data)
                let rssParser = RSSParser(source: feed.title)
                parser.delegate = rssParser
                
                if !parser.parse() || rssParser.items.isEmpty {
                    print("Feed validation failed for \(feed.title): Parsing failed or no items")
                    FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
                    nonWorkingFeeds.append(feed)
                } else {
                    // Record a successful load
                    FeedLoadTimeManager.shared.recordLoadTime(for: feed.title, time: 1.0)
                }
            }
            task.resume()
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(nonWorkingFeeds)
        }
    }
    
    // MARK: - Table View Data Source Methods
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return nonWorkingFeeds.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NonWorkingFeedCell", for: indexPath)
        let feed = nonWorkingFeeds[indexPath.row]
        
        var config = cell.defaultContentConfiguration()
        config.text = feed.title
        
        let failureCount = FeedLoadTimeManager.shared.getFailureCount(for: feed.title)
        let willBeSkipped = FeedLoadTimeManager.shared.shouldSkipFeed(titled: feed.title)
        
        if willBeSkipped {
            config.secondaryText = "⛔️ Will be skipped (failure count: \(failureCount))"
            config.secondaryTextProperties.color = .systemRed
        } else {
            config.secondaryText = "⚠️ Issues detected (failure count: \(failureCount))"
            config.secondaryTextProperties.color = .systemOrange
        }
        
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        cell.contentConfiguration = config
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let feed = nonWorkingFeeds[indexPath.row]
        showFeedOptions(for: feed)
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let feedToRemove = nonWorkingFeeds[indexPath.row]
            removeFeed(feedToRemove)
        }
    }
    
    private func showFeedOptions(for feed: RSSFeed) {
        let alert = UIAlertController(
            title: feed.title,
            message: "This feed has issues. What would you like to do?",
            preferredStyle: .actionSheet
        )
        
        // Option to remove the feed
        alert.addAction(UIAlertAction(title: "Remove Feed", style: .destructive) { [weak self] _ in
            self?.removeFeed(feed)
        })
        
        // Option to reset the feed's failure count
        alert.addAction(UIAlertAction(title: "Reset Failure Count", style: .default) { [weak self] _ in
            FeedLoadTimeManager.shared.resetFailureCount(for: feed.title)
            self?.loadNonWorkingFeeds()
        })
        
        // Option to test the feed again
        alert.addAction(UIAlertAction(title: "Test Feed Again", style: .default) { [weak self] _ in
            self?.testSingleFeed(feed)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad, set the source view for the popover
        if let popoverController = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: IndexPath(row: nonWorkingFeeds.firstIndex(where: { $0.url == feed.url }) ?? 0, section: 0)) {
                popoverController.sourceView = cell
                popoverController.sourceRect = cell.bounds
            } else {
                popoverController.barButtonItem = navigationItem.rightBarButtonItem
            }
        }
        
        present(alert, animated: true)
    }
    
    private func testSingleFeed(_ feed: RSSFeed) {
        // Show loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        navigationItem.titleView = activityIndicator
        
        guard let url = URL(string: feed.url) else {
            DispatchQueue.main.async {
                self.navigationItem.titleView = nil
                self.showError("Invalid URL for feed: \(feed.title)")
            }
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            var success = false
            var message = ""
            
            // Check for errors
            if let error = error {
                message = "Feed test failed: \(error.localizedDescription)"
                FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
            }
            // Check if we got data and it's a valid RSS/Atom feed
            else if let data = data,
                    let xmlString = String(data: data, encoding: .utf8),
                    xmlString.contains("<rss") || xmlString.contains("<feed") {
                
                // Further validate by checking if parsing works
                let parser = XMLParser(data: data)
                let rssParser = RSSParser(source: feed.title)
                parser.delegate = rssParser
                
                if parser.parse() && !rssParser.items.isEmpty {
                    success = true
                    message = "Feed is working correctly (found \(rssParser.items.count) items)"
                    FeedLoadTimeManager.shared.resetFailureCount(for: feed.title)
                } else {
                    message = "Feed format is valid but parsing failed or no items found"
                    FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
                }
            } else {
                message = "Invalid feed format"
                FeedLoadTimeManager.shared.recordFailedFeed(for: feed.title)
            }
            
            DispatchQueue.main.async {
                self.navigationItem.titleView = nil
                
                // Show result
                let alert = UIAlertController(
                    title: success ? "Feed Test Successful" : "Feed Test Failed",
                    message: message,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    // Reload the list after testing
                    self.loadNonWorkingFeeds()
                })
                self.present(alert, animated: true)
            }
        }
        task.resume()
    }
    
    @objc private func removeAllFeeds() {
        // If there are no non-working feeds, just show an alert
        if nonWorkingFeeds.isEmpty {
            let alert = UIAlertController(
                title: "No Feeds to Remove",
                message: "There are no problematic feeds to remove.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        // Confirm with the user
        let alert = UIAlertController(
            title: "Remove All Non-Working Feeds",
            message: "Are you sure you want to remove all problematic feeds? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove All", style: .destructive) { [weak self] _ in
            self?.performRemoveAllFeeds()
        })
        
        present(alert, animated: true)
    }
    
    private func performRemoveAllFeeds() {
        // Show activity indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        navigationItem.titleView = activityIndicator
        
        // Get URLs of all non-working feeds
        let nonWorkingFeedURLs = nonWorkingFeeds.map { $0.url }
        
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(var feeds):
                // Remove all non-working feeds
                let originalCount = feeds.count
                feeds.removeAll { nonWorkingFeedURLs.contains($0.url) }
                let removedCount = originalCount - feeds.count
                
                // Save the updated feeds list
                StorageManager.shared.save(feeds, forKey: "rssFeeds") { error in
                    DispatchQueue.main.async {
                        // Hide activity indicator
                        self.navigationItem.titleView = nil
                        
                        if let error = error {
                            self.showError("Failed to remove feeds: \(error.localizedDescription)")
                        } else {
                            // Clear our list
                            self.nonWorkingFeeds.removeAll()
                            self.tableView.reloadData()
                            
                            // Update the title with count
                            self.title = "Non-Working Feeds (0)"
                            
                            // Show empty message
                            let emptyLabel = UILabel()
                            emptyLabel.text = "No problematic feeds found"
                            emptyLabel.textAlignment = .center
                            emptyLabel.textColor = .gray
                            self.tableView.backgroundView = emptyLabel
                            
                            // Show success message
                            let successAlert = UIAlertController(
                                title: "Feeds Removed",
                                message: "Successfully removed \(removedCount) problematic feed\(removedCount == 1 ? "" : "s").",
                                preferredStyle: .alert
                            )
                            successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(successAlert, animated: true)
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    // Hide activity indicator
                    self.navigationItem.titleView = nil
                    
                    self.showError("Failed to load feeds: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func removeFeed(_ feed: RSSFeed) {
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(var feeds):
                // Remove the feed from the array
                feeds.removeAll { $0.url == feed.url }
                
                // Save the updated feeds list
                StorageManager.shared.save(feeds, forKey: "rssFeeds") { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.showError("Failed to remove feed: \(error.localizedDescription)")
                        } else {
                            // Update our list
                            self.nonWorkingFeeds.removeAll { $0.url == feed.url }
                            self.tableView.reloadData()
                            
                            // Update the title with count
                            self.title = "Non-Working Feeds (\(self.nonWorkingFeeds.count))"
                            
                            // Show empty message if needed
                            if self.nonWorkingFeeds.isEmpty {
                                let emptyLabel = UILabel()
                                emptyLabel.text = "No problematic feeds found"
                                emptyLabel.textAlignment = .center
                                emptyLabel.textColor = .gray
                                self.tableView.backgroundView = emptyLabel
                            }
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.showError("Failed to load feeds: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}