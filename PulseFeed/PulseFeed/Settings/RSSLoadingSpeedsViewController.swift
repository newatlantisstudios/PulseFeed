import UIKit

class RSSLoadingSpeedsViewController: UITableViewController {
    
    // Data source: list of (feed title, load time, failure count)
    var feedLoadTimes: [(title: String, time: TimeInterval, failureCount: Int)] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RSS Feed Loading Speeds"
        
        // Register our custom cell class
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FeedSpeedCell")
        
        // Add a reset button to the navigation bar
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Reset",
            style: .plain,
            target: self,
            action: #selector(resetFeedStatistics)
        )
        
        // Load feed data
        loadFeedTimes()
        
        // Setup notification observer for feed load time updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(feedLoadTimeUpdated),
            name: Notification.Name("feedLoadTimeUpdated"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func feedLoadTimeUpdated(_ notification: Notification) {
        loadFeedTimes()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data in case new times have been recorded
        loadFeedTimes()
    }
    
    private func loadFeedTimes() {
        // Create tuples of (title, time, failureCount)
        feedLoadTimes = FeedLoadTimeManager.shared.loadTimes
            .map { (
                title: $0.key,
                time: $0.value,
                failureCount: FeedLoadTimeManager.shared.getFailureCount(for: $0.key)
            )}
            .sorted { 
                // First sort by whether feeds will be skipped
                if FeedLoadTimeManager.shared.shouldSkipFeed(titled: $0.title) &&
                   !FeedLoadTimeManager.shared.shouldSkipFeed(titled: $1.title) {
                    return true
                } else if !FeedLoadTimeManager.shared.shouldSkipFeed(titled: $0.title) &&
                          FeedLoadTimeManager.shared.shouldSkipFeed(titled: $1.title) {
                    return false
                }
                
                // Then sort by time (slowest first)
                return $0.time > $1.time
            }
        tableView.reloadData()
    }
    
    @objc private func resetFeedStatistics() {
        let alert = UIAlertController(
            title: "Reset Feed Statistics",
            message: "Do you want to reset load statistics for all feeds or just for skipped feeds?",
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Reset All Feeds", style: .destructive) { [weak self] _ in
            // Reset all feed load statistics
            for feed in self?.feedLoadTimes ?? [] {
                FeedLoadTimeManager.shared.resetFailureCount(for: feed.title)
            }
            self?.loadFeedTimes()
        })
        
        alert.addAction(UIAlertAction(title: "Reset Only Skipped Feeds", style: .default) { [weak self] _ in
            // Reset only feeds that would be skipped
            for feed in self?.feedLoadTimes ?? [] where FeedLoadTimeManager.shared.shouldSkipFeed(titled: feed.title) {
                FeedLoadTimeManager.shared.resetFailureCount(for: feed.title)
            }
            self?.loadFeedTimes()
        })
        
        alert.addAction(UIAlertAction(title: "Reset Selected Feed", style: .default) { [weak self] _ in
            self?.promptForFeedSelection()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad, set the source view for the popover
        if let popoverController = alert.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(alert, animated: true)
    }
    
    private func promptForFeedSelection() {
        let feedsAlert = UIAlertController(
            title: "Select Feed to Reset",
            message: "Choose a feed to reset its statistics",
            preferredStyle: .actionSheet
        )
        
        // Add an action for each feed
        for feed in feedLoadTimes {
            feedsAlert.addAction(UIAlertAction(title: feed.title, style: .default) { [weak self] _ in
                FeedLoadTimeManager.shared.resetFailureCount(for: feed.title)
                self?.loadFeedTimes()
            })
        }
        
        feedsAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad, set the source view for the popover
        if let popoverController = feedsAlert.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(feedsAlert, animated: true)
    }
    
    // MARK: - Table View Data Source Methods
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return feedLoadTimes.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FeedSpeedCell", for: indexPath)
        let feed = feedLoadTimes[indexPath.row]
        
        // Create a mutable content configuration
        var config = cell.defaultContentConfiguration()
        
        // Format the time
        let formattedTime: String
        if feed.time < 0 {
            formattedTime = "error"
        } else if feed.time < 60 {
            formattedTime = String(format: "%.2f seconds", feed.time)
        } else {
            let minutes = Int(feed.time) / 60
            let seconds = Int(feed.time) % 60
            formattedTime = "\(minutes)m \(seconds)s"
        }
        
        // Update the cell content
        config.text = feed.title
        
        // Show the status: skipped, slow, or normal
        if FeedLoadTimeManager.shared.shouldSkipFeed(titled: feed.title) {
            config.secondaryText = "⛔️ SKIPPED (\(formattedTime), failures: \(feed.failureCount)/\(FeedLoadTimeManager.shared.maxFailures))"
            config.secondaryTextProperties.color = .systemRed
        } else if FeedLoadTimeManager.shared.isFeedSlow(titled: feed.title) {
            config.secondaryText = "⚠️ SLOW: \(formattedTime) (failures: \(feed.failureCount)/\(FeedLoadTimeManager.shared.maxFailures))"
            config.secondaryTextProperties.color = .systemOrange
        } else {
            config.secondaryText = "✅ \(formattedTime)"
            config.secondaryTextProperties.color = .systemGreen
        }
        
        cell.contentConfiguration = config
        
        // Add a reset button to each row
        cell.accessoryType = .detailDisclosureButton
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let feed = feedLoadTimes[indexPath.row]
        
        let alert = UIAlertController(
            title: feed.title,
            message: "Do you want to reset the load statistics for this feed?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            FeedLoadTimeManager.shared.resetFailureCount(for: feed.title)
            self?.loadFeedTimes()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
}
