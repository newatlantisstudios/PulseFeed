import SafariServices
import UIKit

// MARK: - RSSItem Model
struct RSSItem: Codable {
    let title: String
    let link: String
    let pubDate: String
    let source: String
    var isRead: Bool = false

    enum CodingKeys: String, CodingKey {
        case title, link, pubDate, source, isRead
    }
}

struct ReadItem: Codable {
    let link: String
    let readDate: Date
}

// MARK: - AppColors and UIColor Extension
enum AppColors {
    static var primary: UIColor {
        return UIColor(hex: "121212")
    }

    static var secondary: UIColor {
        return UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: "9E9E9E") : UIColor(hex: "757575")
        }
    }

    static var accent: UIColor {
        return UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: "FFFFFF") : UIColor(hex: "1A1A1A")
        }
    }

    static var background: UIColor {
        return UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: "1E1E1E") : UIColor(hex: "F5F5F5")
        }
    }
}

extension AppColors {
    static var dynamicIconColor: UIColor {
        return UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
    }
}

extension AppColors {
    static var navBarBackground: UIColor {
        return UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                // Dark background in Dark Mode
                return UIColor(hex: "121212")
            default:
                // Light background in Light Mode
                return UIColor(hex: "FFFFFF") // or "F5F5F5", etc.
            }
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex)
        scanner.scanLocation = 0

        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = (rgbValue & 0xff0000) >> 16
        let g = (rgbValue & 0xff00) >> 8
        let b = rgbValue & 0xff

        self.init(
            red: CGFloat(r) / 0xff,
            green: CGFloat(g) / 0xff,
            blue: CGFloat(b) / 0xff,
            alpha: 1)
    }
}

// MARK: - Helper Function
private func getTimeAgo(from dateString: String) -> String {
    // Create multiple date formatters to handle different RSS date formats
    let primaryFormatter = DateFormatter()
    primaryFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    primaryFormatter.locale = Locale(identifier: "en_US_POSIX")
    primaryFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    
    // Helper function to parse dates with multiple formatters
    func parseDate(_ dateString: String) -> Date? {
        // Skip empty strings
        if dateString.isEmpty {
            return nil
        }
        
        // Try standard RSS format first
        if let date = primaryFormatter.date(from: dateString) {
            return date
        }
        
        // Try local timezone format (like PDT)
        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Common RSS format with different timezone (PDT/PST/EDT etc)
        localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = localFormatter.date(from: dateString) {
            return date
        }
        
        // Try with offset timezone like -0700
        localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = localFormatter.date(from: dateString) {
            return date
        }
        
        // Try ISO 8601 format
        localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = localFormatter.date(from: dateString) {
            return date
        }
        
        // Try more fallback formats
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "EEE, dd MMM yyyy",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm zzz"  // No seconds
        ]
        
        for format in formats {
            localFormatter.dateFormat = format
            if let date = localFormatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }

    guard let date = parseDate(dateString) else {
        return dateString
    }
    
    let now = Date()
    let components = Calendar.current.dateComponents(
        [.minute, .hour, .day], from: date, to: now)

    if let days = components.day, days > 0 {
        return "\(days)d ago"
    } else if let hours = components.hour, hours > 0 {
        return "\(hours)h ago"
    } else if let minutes = components.minute, minutes > 0 {
        return "\(minutes)m ago"
    }
    return "just now"
}

// MARK: - HomeFeedViewController
class HomeFeedViewController: UIViewController {

    // Data and UI
    private var items: [RSSItem] = []
    private let tableView = UITableView()
    private let refreshControl = UIRefreshControl()
    private var longPressGesture: UILongPressGestureRecognizer!
    private var footerLoadingIndicator: UIActivityIndicatorView?
    private var footerRefreshButton: UIButton?
    private var footerView: UIView?
    private var loadingIndicator: UIActivityIndicatorView!
    private var loadingLabel: UILabel! // Add label to show which feed is loading
    private var heartedItems: Set<String> = []
    private var bookmarkedItems: Set<String> = []
    private var _allItems: [RSSItem] = []
    private var hasLoadedRSSFeeds = false
    private var previousMinVisibleRow: Int = 0 // Track the topmost visible row
    private var isSortedAscending: Bool = false // Add state for sorting order
    private var readLinks: Set<String> = [] // Store normalized read links
    
    // Property to access allItems
    var allItems: [RSSItem] {
        get {
            return _allItems
        }
        set {
            _allItems = newValue
        }
    }

    // Add properties for Nav Bar Buttons
    private var rssButton: UIBarButtonItem?
    private var refreshButton: UIBarButtonItem?
    private var bookmarkButton: UIBarButtonItem?
    private var heartButton: UIBarButtonItem?
    private var settingsButton: UIBarButtonItem?
    private var editButton: UIBarButtonItem?
    private var sortButton: UIBarButtonItem? // Add sort button property

    // Feed types; RSSFeed is managed separately.
    private enum FeedType {
        case rss, bookmarks, heart
    }
    private var currentFeedType: FeedType = .rss {
        didSet {
            updateTableViewContent()
            updateNavigationButtons()
        }
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(fontSizeChanged(_:)), name: Notification.Name("fontSizeChanged"), object: nil)
        
        // Setup UI elements in proper order to ensure navigation buttons are ready for animation
        setupLoadingIndicator()
        setupRefreshControl()
        setupNavigationBar() // This sets up all navigation buttons including the refresh button
        updateNavigationButtons()
        setupTableView()
        setupScrollViewDelegate()
        setupNotificationObserver()
        setupLongPressGesture()
        
        // Hide tableView initially until articles are loaded
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        
        // Start the animation immediately
        startRefreshAnimation()
        
        // Load the feeds (which will also start the animation again as a backup)
        loadRSSFeeds()

        // Load hearted items
        StorageManager.shared.load(forKey: "heartedItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                DispatchQueue.main.async {
                    self.heartedItems = Set(items)
                }
            }
        }

        // Load bookmarked items
        StorageManager.shared.load(forKey: "bookmarkedItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                DispatchQueue.main.async {
                    self.bookmarkedItems = Set(items)
                }
            }
        }

        // Restore sort order from UserDefaults
        if UserDefaults.standard.object(forKey: "articleSortAscending") != nil {
            isSortedAscending = UserDefaults.standard.bool(forKey: "articleSortAscending")
        } else {
            // Default to newest first (false = descending order) if not set
            isSortedAscending = false
            // Save the default value to UserDefaults
            UserDefaults.standard.set(false, forKey: "articleSortAscending")
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // If the tableView is still hidden, make sure the refresh icon is spinning
        if tableView.isHidden {
            startRefreshAnimation()
        }

        // If we haven't loaded feeds yet, automatically show pull-to-refresh:
        if !hasLoadedRSSFeeds {
            // Keep tableView hidden while refreshing
            tableView.isHidden = true
            loadingIndicator.startAnimating()
            
            // Ensure refresh icon is spinning (with a small delay to ensure it works)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startRefreshAnimation()
            }
            
            // 1. Start the refresh spinner but keep it invisible until tableView is shown
            refreshControl.beginRefreshing()

            // 2. Call the same refresh method used by pull-to-refresh
            refreshFeeds()
        }
    }

    private func setupLoadingIndicator() {
        // Setup main loading indicator
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.center = view.center
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        
        // Setup loading label below the indicator
        loadingLabel = UILabel()
        loadingLabel.textAlignment = .center
        loadingLabel.textColor = AppColors.secondary
        loadingLabel.font = UIFont.systemFont(ofSize: 14)
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)
        
        NSLayoutConstraint.activate([
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 12),
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            loadingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        // Initially hide the label
        loadingLabel.isHidden = true
    }

    // MARK: - Setup Methods
    private func setupRefreshControl() {
        refreshControl.addTarget(
            self, action: #selector(refreshFeeds), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReadItemsReset),
            name: Notification.Name("readItemsReset"),
            object: nil)
            
        // Add observer for when read items are updated (e.g. from CloudKit sync)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReadItemsUpdated),
            name: Notification.Name("readItemsUpdated"),
            object: nil)
            
        // Add observer for bookmarked items updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBookmarkedItemsUpdated),
            name: Notification.Name("bookmarkedItemsUpdated"),
            object: nil)
            
        // Add observer for hearted items updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHeartedItemsUpdated),
            name: Notification.Name("heartedItemsUpdated"),
            object: nil)
    }

    private func setupScrollViewDelegate() {
        tableView.delegate = self
    }

    private func setupLongPressGesture() {
        longPressGesture = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPressGesture)
    }
    
    private func updateNavigationButtons() {
        guard let leftButtons = navigationItem.leftBarButtonItems, leftButtons.count >= 4 else {
            return
        }
        
        // leftButtons order: [rss, refresh, bookmark, heart]
        // Update the RSS button image:
        let rssImageName = (currentFeedType == .rss) ? "rssFilled" : "rss"
        rssButton?.image = resizeImage(
            UIImage(named: rssImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        
        // Do not change the refresh button (index 1)
        
        // Update the Bookmark button image:
        let bookmarkImageName = (currentFeedType == .bookmarks) ? "bookmarkFilled" : "bookmark"
        bookmarkButton?.image = resizeImage(
            UIImage(named: bookmarkImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        
        // Update the Heart button image:
        let heartImageName = (currentFeedType == .heart) ? "heartFilled" : "heart"
        heartButton?.image = resizeImage(
            UIImage(named: heartImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
    }


    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer)
    {
        if gesture.state == .began {
            let point = gesture.location(in: tableView)
            if let indexPath = tableView.indexPathForRow(at: point) {
                showMarkAboveAlert(for: indexPath)
            }
        }
    }

    private var saveReadStateWorkItem: DispatchWorkItem?
    private let saveReadStateDebounceInterval: TimeInterval = 1.5
    private var hasResetCloudKitReadItemsThisSession = false

    // Debounced save for read state
    private func scheduleSaveReadState() {
        saveReadStateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveReadState()
        }
        saveReadStateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveReadStateDebounceInterval, execute: workItem)
    }

    private func showMarkAboveAlert(for indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Mark as Read",
            message: "Do you want to mark all articles above this one as read?",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Mark Read", style: .default) {
                [weak self] _ in
                self?.markItemsAboveAsRead(indexPath)
            })
        present(alert, animated: true)
    }

    // Helper to normalize links for consistent comparison
    private func normalizeLink(_ link: String) -> String {
        // Use the StorageManager's normalization method for consistency
        return StorageManager.shared.normalizeLink(link)
    }

    private func markItemsAboveAsRead(_ indexPath: IndexPath) {
        for index in 0...indexPath.row {
            items[index].isRead = true
            print("Marking as read and saving link: \(self.normalizeLink(items[index].link))")
        }
        scheduleSaveReadState()
        let indexPaths = (0...indexPath.row).map {
            IndexPath(row: $0, section: 0)
        }
        tableView.reloadRows(at: indexPaths, with: .fade)
    }

    @objc private func handleReadItemsReset() {
        loadRSSFeeds()
    }
    
    @objc private func handleReadItemsUpdated() {
        // Load the updated read items from UserDefaults
        StorageManager.shared.load(forKey: "readItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let readItems):
                DispatchQueue.main.async {
                    // Update our cached read links
                    self.readLinks = Set(readItems.map { self.normalizeLink($0) })
                    
                    // Update the read state for all items
                    for i in 0..<self._allItems.count {
                        let normLink = self.normalizeLink(self._allItems[i].link)
                        self._allItems[i].isRead = self.readLinks.contains(normLink)
                    }
                    
                    // Update the current items if needed
                    for i in 0..<self.items.count {
                        let normLink = self.normalizeLink(self.items[i].link)
                        self.items[i].isRead = self.readLinks.contains(normLink)
                    }
                    
                    // Reload the table view to show the updated read states
                    self.tableView.reloadData()
                }
            case .failure(let error):
                print("ERROR: Failed to load updated read items: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func handleBookmarkedItemsUpdated() {
        // Load the updated bookmarked items from UserDefaults
        StorageManager.shared.load(forKey: "bookmarkedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let bookmarkedItems):
                DispatchQueue.main.async {
                    // Update our cached bookmarked links
                    self.bookmarkedItems = Set(bookmarkedItems)
                    
                    // If currently viewing bookmarked feed, refresh it
                    if self.currentFeedType == .bookmarks {
                        self.loadBookmarkedFeeds()
                    } else {
                        // Otherwise just reload the table to update swipe actions
                        self.tableView.reloadData()
                    }
                }
            case .failure(let error):
                print("ERROR: Failed to load updated bookmarked items: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func handleHeartedItemsUpdated() {
        // Load the updated hearted items from UserDefaults
        StorageManager.shared.load(forKey: "heartedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let heartedItems):
                DispatchQueue.main.async {
                    // Update our cached hearted links
                    self.heartedItems = Set(heartedItems)
                    
                    // If currently viewing hearted feed, refresh it
                    if self.currentFeedType == .heart {
                        self.loadHeartedFeeds()
                    } else {
                        // Otherwise just reload the table to update swipe actions
                        self.tableView.reloadData()
                    }
                }
            case .failure(let error):
                print("ERROR: Failed to load updated hearted items: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func fontSizeChanged(_ notification: Notification) {
        tableView.reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Updating Content Based on Feed Type
    private func updateTableViewContent() {
        switch currentFeedType {
        case .rss:
            if !hasLoadedRSSFeeds {
                // If feeds haven't been loaded yet, hide tableView and load them
                tableView.isHidden = true
                loadingIndicator.startAnimating()
                startRefreshAnimation() // Start refresh button animation
                items.removeAll()
                loadRSSFeeds()
            } else {
                // Use the cached items from the initial load.
                // Hide the tableView briefly while reloading
                tableView.isHidden = true
                loadingIndicator.startAnimating()
                startRefreshAnimation() // Start refresh button animation
                
                items = allItems
                tableView.reloadData()
                
                // Show tableView after a short delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tableView.isHidden = false
                    self.loadingIndicator.stopAnimating()
                    self.loadingLabel.isHidden = true
                    self.stopRefreshAnimation() // Stop refresh button animation
                }
            }
        case .bookmarks:
            // For bookmarks and heart feeds, briefly hide the tableView while loading
            tableView.isHidden = true
            loadingIndicator.startAnimating()
            startRefreshAnimation() // Start refresh button animation
            
            loadBookmarkedFeeds()
            
            // Show tableView after a short delay to ensure smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.tableView.isHidden = false
                self.loadingIndicator.stopAnimating()
                self.loadingLabel.isHidden = true
                self.stopRefreshAnimation() // Stop refresh button animation
            }
        case .heart:
            // For bookmarks and heart feeds, briefly hide the tableView while loading
            tableView.isHidden = true
            loadingIndicator.startAnimating()
            startRefreshAnimation() // Start refresh button animation
            
            loadHeartedFeeds()
            
            // Show tableView after a short delay to ensure smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.tableView.isHidden = false
                self.loadingIndicator.stopAnimating()
                self.loadingLabel.isHidden = true
                self.stopRefreshAnimation() // Stop refresh button animation
            }
        }
        updateFooterVisibility()
    }

    // Load RSS feeds from storage and then fetch articles from each feed URL.
    private func loadRSSFeeds() {
        // Hide tableView and show loading indicator
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        
        // Show the loading label with initial message
        loadingLabel.text = "Loading feeds..."
        loadingLabel.isHidden = false
        
        // Make sure the refresh icon is spinning
        startRefreshAnimation() // Start animation
        
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let feeds):
                // Load read items (to filter out already-read links)
                StorageManager.shared.load(forKey: "readItems") { (readResult: Result<[String], Error>) in
                    var readLinks: Set<String> = []
                    if case .success(let readItems) = readResult {
                        readLinks = Set(readItems.map { self.normalizeLink($0) })
                    }
                    //print("[loadRSSFeeds] Loaded read links: \(readLinks)")
                    self.readLinks = readLinks // Store for later use
                    // Print normalized links for all items after loading feeds (after parsing, before filtering)
                    // We'll gather all live feed items in this array
                    var liveItems: [RSSItem] = []
                    
                    // A dispatch group to wait until all feed network calls finish
                    let fetchGroup = DispatchGroup()
                    
                    // 1) Fetch each feed
                    for feed in feeds {
                        guard let url = URL(string: feed.url) else { continue }
                        
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
                                // Record the load time for this feed
                                FeedLoadTimeManager.shared.recordLoadTime(for: feed.title, time: elapsedTime)
                                fetchGroup.leave() 
                            }
                            
                            let elapsedTime = Date().timeIntervalSince(startTime)
                            // Skip if it took too long or if there was an error
                            if elapsedTime >= 45 || error != nil || data == nil {
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
                            let parser = XMLParser(data: data!)
                            let rssParser = RSSParser(source: feed.title)
                            parser.delegate = rssParser
                            
                            if parser.parse() {
                                // Filter out already-read links
                                let filtered = rssParser.items.filter {
                                    let normLink = self.normalizeLink($0.link)
                                    if readLinks.contains(normLink) {
                                        //print("Filtering out read article: \(normLink)")
                                        return false
                                    }
                                    return true
                                }
                                print("Feed \(feed.title): Filtered out \(rssParser.items.count - filtered.count) read articles out of \(rssParser.items.count)")
                                liveItems.append(contentsOf: filtered)
                            }
                        }
                        task.resume()
                    }
                    
                    // 2) After all feeds are fetched, we can do iCloud sync, then merges
                    fetchGroup.notify(queue: .main) {
                        // Show that all feeds have been loaded
                        self.loadingLabel.text = "All feeds loaded, processing articles..."
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

                        // Create enhanced date parsing that handles multiple formats
                        let primaryFormatter = dateFormatter
                        
                        // Helper function to parse dates with multiple formatters
                        func parseDate(_ dateString: String) -> Date? {
                            // Skip empty strings
                            if dateString.isEmpty {
                                return nil
                            }
                            
                            // Try standard RSS format first
                            if let date = primaryFormatter.date(from: dateString) {
                                return date
                            }
                            
                            // Try local timezone format (like PDT)
                            let localFormatter = DateFormatter()
                            localFormatter.locale = Locale(identifier: "en_US_POSIX")
                            
                            // Common RSS format with different timezone (PDT/PST/EDT etc)
                            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                            if let date = localFormatter.date(from: dateString) {
                                return date
                            }
                            
                            // Try with time zone without seconds
                            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm zzz"
                            if let date = localFormatter.date(from: dateString) {
                                return date
                            }
                            
                            // Try with offset timezone like -0700
                            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                            if let date = localFormatter.date(from: dateString) {
                                return date
                            }
                            
                            // Try ISO 8601 format
                            localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                            if let date = localFormatter.date(from: dateString) {
                                return date
                            }
                            
                            // Try more fallback formats
                            let formats = [
                                "yyyy-MM-dd HH:mm:ss",
                                "yyyy-MM-dd'T'HH:mm:ss",
                                "yyyy-MM-dd HH:mm",
                                "EEE, dd MMM yyyy",
                                "dd MMM yyyy HH:mm:ss Z"
                            ]
                            
                            for format in formats {
                                localFormatter.dateFormat = format
                                if let date = localFormatter.date(from: dateString) {
                                    return date
                                }
                            }
                            
                            // If we get here, we couldn't parse the date with standard formats
                            return nil
                        }
                        
                        // Sort all newly fetched items by pubDate initially with improved date parsing
                        let sortedLiveItems = liveItems.sorted {
                            // Get dates for both items
                            let date1 = parseDate($0.pubDate)
                            let date2 = parseDate($1.pubDate)
                            
                            // If both dates can be parsed, use them for comparison
                            if let d1 = date1, let d2 = date2 {
                                return self.isSortedAscending ? d1 < d2 : d1 > d2
                            }
                            
                            // If only one date can be parsed, the one with a valid date should come first
                            if date1 != nil {
                                return self.isSortedAscending ? false : true  // Valid date first
                            }
                            if date2 != nil {
                                return self.isSortedAscending ? true : false  // Valid date first
                            }
                            
                            // If neither date can be parsed and both are not empty, compare strings
                            if !$0.pubDate.isEmpty && !$1.pubDate.isEmpty {
                                // Just use string comparison as a fallback
                                return self.isSortedAscending ? $0.pubDate < $1.pubDate : $0.pubDate > $1.pubDate
                            }
                            
                            // Place empty dates at the end
                            if $0.pubDate.isEmpty {
                                return self.isSortedAscending ? true : false
                            }
                            if $1.pubDate.isEmpty {
                                return self.isSortedAscending ? false : true
                            }
                            
                            // If we're here, both are empty - considered equal
                            return false
                        }

                        // Temp storage for merged items per feed
                        var mergedItemsByFeed: [String: [RSSItem]] = [:]
                        // Keep track of new articles found during merge
                        var feedArticlesToSave: [String: [ArticleSummary]] = [:]
                        let mergeGroup = DispatchGroup()

                        for feed in feeds {
                            mergeGroup.enter()
                            CloudKitStorage().loadArticles(forFeed: feed.title) { result in
                                // Holds merged items for this specific feed
                                var itemsForThisFeed: [RSSItem] = []
                                // Holds only the articles fetched live for comparison
                                let liveForFeed = sortedLiveItems.filter { $0.source == feed.title }

                                switch result {
                                case .success(let cachedArticles):
                                    // Filter out read items from cache (normalize link)
                                    let unreadCached = cachedArticles.filter {
                                        !self.readLinks.contains(self.normalizeLink($0.link))
                                    }

                                    // Start with live items for this feed
                                    itemsForThisFeed = liveForFeed
                                    let liveLinks = Set(liveForFeed.map { $0.link })
                                    var newArticlesForCloudKit: [ArticleSummary] = []

                                    // Add cached items if they aren't already in the live list
                                    for cached in unreadCached {
                                        if !liveLinks.contains(cached.link) {
                                            let normLink = self.normalizeLink(cached.link)
                                            let newItem = RSSItem(
                                                title: cached.title,
                                                link: cached.link,
                                                pubDate: cached.pubDate,
                                                source: feed.title,
                                                isRead: self.readLinks.contains(normLink)
                                            )
                                            itemsForThisFeed.append(newItem)
                                        }
                                    }

                                    // Identify articles that were fetched live but not in the cache (these are new)
                                    let cachedLinks = Set(cachedArticles.map { $0.link })
                                    newArticlesForCloudKit = liveForFeed
                                        .filter { !cachedLinks.contains($0.link) }
                                        .map { ArticleSummary(title: $0.title, link: $0.link, pubDate: $0.pubDate) }

                                    if !newArticlesForCloudKit.isEmpty {
                                        feedArticlesToSave[feed.title] = newArticlesForCloudKit
                                    }

                                case .failure(let error):
                                    print("Error loading cached articles for feed \(feed.title): \(error.localizedDescription)")
                                    // If loading cache fails, still use the live items for this feed
                                    itemsForThisFeed = liveForFeed
                                    // Assume all live items are new if cache fails
                                    let newArticles = itemsForThisFeed.map { ArticleSummary(title: $0.title, link: $0.link, pubDate: $0.pubDate) }
                                    if !newArticles.isEmpty {
                                        feedArticlesToSave[feed.title] = newArticles
                                    }
                                }

                                // Store the merged items for this feed temporarily
                                mergedItemsByFeed[feed.title] = itemsForThisFeed

                                mergeGroup.leave()
                            }
                        }

                        // 4) Once merges finish, save *only* the new articles to CloudKit
                        mergeGroup.notify(queue: .global(qos: .background)) { // Runs after all loadArticles complete
                            let saveGroup = DispatchGroup()
                            for (feedId, articles) in feedArticlesToSave {
                                if articles.isEmpty { continue } // Skip saving if no new articles
                                saveGroup.enter()
                                CloudKitStorage().saveArticles(forFeed: feedId, articles: articles) { error in
                                    if let error = error {
                                        print("Error saving NEW articles for feed \(feedId): \(error.localizedDescription)")
                                    } else {
                                        print("Successfully saved \(articles.count) NEW live articles for feed \(feedId)")
                                    }
                                    saveGroup.leave()
                                }
                            }

                            // 5) After saving, update UI on the main thread
                            saveGroup.notify(queue: .main) { // Runs after all saveArticles complete
                                // Combine all items from the temporary storage
                                var finalAllItems = mergedItemsByFeed.values.flatMap { $0 }

                                // Create more robust date formatters for different RSS formats
                                let primaryFormatter = dateFormatter
                                
                                // Secondary formatter for alternative formats
                                let alternateFormatter = DateFormatter()
                                alternateFormatter.locale = Locale(identifier: "en_US_POSIX")
                                alternateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ" // ISO 8601
                                
                                // Helper function to parse dates with multiple formatters
                                func parseDate(_ dateString: String) -> Date? {
                                    if let date = primaryFormatter.date(from: dateString) {
                                        return date
                                    } else if let date = alternateFormatter.date(from: dateString) {
                                        return date
                                    } else {
                                        // Try one more common format as a fallback
                                        alternateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                                        return alternateFormatter.date(from: dateString)
                                    }
                                }
                                
                                // Final sort of the combined list with improved date parsing
                                finalAllItems.sort {
                                    // Get dates for both items
                                    let date1 = parseDate($0.pubDate)
                                    let date2 = parseDate($1.pubDate)
                                    
                                    // If both dates can be parsed, use them for comparison
                                    if let d1 = date1, let d2 = date2 {
                                        return self.isSortedAscending ? d1 < d2 : d1 > d2
                                    }
                                    
                                    // If only one date can be parsed, the one with a valid date should come first
                                    if date1 != nil {
                                        return self.isSortedAscending ? false : true  // Valid date first
                                    }
                                    if date2 != nil {
                                        return self.isSortedAscending ? true : false  // Valid date first
                                    }
                                    
                                    // If neither date can be parsed and both are not empty, compare strings
                                    if !$0.pubDate.isEmpty && !$1.pubDate.isEmpty {
                                        // Just use string comparison as a fallback
                                        return self.isSortedAscending ? $0.pubDate < $1.pubDate : $0.pubDate > $1.pubDate
                                    }
                                    
                                    // Place empty dates at the end
                                    if $0.pubDate.isEmpty {
                                        return self.isSortedAscending ? true : false
                                    }
                                    if $1.pubDate.isEmpty {
                                        return self.isSortedAscending ? false : true
                                    }
                                    
                                    // If we're here, both are empty - considered equal
                                    return false
                                }

                                // Filter items older than 30 days
                                let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                                let filteredItems = finalAllItems.filter { item in
                                    guard let itemDate = dateFormatter.date(from: item.pubDate) else {
                                        return false // Exclude if date can't be parsed
                                    }
                                    return itemDate >= thirtyDaysAgo
                                }

                                // Debug: Check for any read articles still in filteredItems
                                for item in filteredItems {
                                    let normLink = self.normalizeLink(item.link)
                                    if self.readLinks.contains(normLink) {
                                        print("ERROR: Read article still in filteredItems: \(item.title) (\(normLink))")
                                    }
                                }

                                // Update the main data source ONCE with the filtered items
                                self._allItems = filteredItems // Use the filtered list
                                // Set isRead for all items in allItems
                                for i in 0..<self._allItems.count {
                                    let normLink = self.normalizeLink(self._allItems[i].link)
                                    self._allItems[i].isRead = self.readLinks.contains(normLink)
                                }
                                print("Final article count after filtering: \(filteredItems.count)")
                                // Update the currently displayed items if RSS feed is active
                                if self.currentFeedType == .rss {
                                    self.items = self._allItems
                                }

                                // First, reload the table while it's still hidden
                                self.tableView.reloadData()

                                // Then, asynchronously update state
                                // to allow reloadData() to begin processing before showing the tableView
                                DispatchQueue.main.async {
                                    self.refreshControl.endRefreshing()
                                    self.hasLoadedRSSFeeds = true
                                    self.updateFooterVisibility()
                                    
                                    // Only show the tableView after everything is ready
                                    // Add a small delay to ensure UI has fully processed the data
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        // Stop all animations only after tableView is ready to be shown
                                        self.stopRefreshAnimation() // Stop refresh button animation
                                        self.loadingIndicator.stopAnimating()
                                        self.loadingLabel.isHidden = true
                                        self.tableView.isHidden = false
                                    }
                                }
                            }
                        }
                    }
                }
                
            case .failure(let error):
                print("DEBUG: Error loading rssFeeds: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.refreshControl.endRefreshing()
                    // Show tableView even on error, but ensure it's reloaded first
                    self.tableView.reloadData()
                    
                    // Stop animations only after tableView is ready to be shown
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.stopRefreshAnimation() // Stop animation on error too
                        self.loadingIndicator.stopAnimating()
                        self.loadingLabel.isHidden = true
                        self.tableView.isHidden = false
                    }
                }
            }
        }
    }

    // New implementation for loading bookmarked feeds
    private func loadBookmarkedFeeds() {
        // Filter the complete list based on bookmarked links using normalized links
        var filteredItems = self._allItems.filter { item in
            let normalizedLink = self.normalizeLink(item.link)
            return self.bookmarkedItems.contains { self.normalizeLink($0) == normalizedLink }
        }
        // Sort the filtered items based on the current sort order
        sortFilteredItems(&filteredItems)
        self.items = filteredItems
        // Reload data before showing the tableView
        tableView.reloadData()
    }

    // New implementation for loading hearted feeds
    private func loadHeartedFeeds() {
        // Filter the complete list based on hearted links using normalized links
        var filteredItems = self._allItems.filter { item in
            let normalizedLink = self.normalizeLink(item.link)
            return self.heartedItems.contains { self.normalizeLink($0) == normalizedLink }
        }
        // Sort the filtered items based on the current sort order
        sortFilteredItems(&filteredItems)
        self.items = filteredItems
        // Reload data before showing the tableView
        tableView.reloadData()
    }

    // Helper function to sort a given array of items based on the current setting
    private func sortFilteredItems(_ itemsToSort: inout [RSSItem]) {
        // Create a more robust date formatter that can handle different RSS date formats
        let primaryFormatter = DateFormatter()
        primaryFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        primaryFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Secondary formatter for alternative formats that might appear
        let alternateFormatter = DateFormatter()
        alternateFormatter.locale = Locale(identifier: "en_US_POSIX")
        alternateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ" // ISO 8601 format
        
        // Helper function to parse dates with multiple formatters
        func parseDate(_ dateString: String) -> Date? {
            // Skip empty strings
            if dateString.isEmpty {
                return nil
            }
            
            // Try standard RSS format first
            if let date = primaryFormatter.date(from: dateString) {
                return date
            }
            
            // Try local timezone format (like PDT)
            let localFormatter = DateFormatter()
            localFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            // Common RSS format with different timezone (PDT/PST/EDT etc)
            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = localFormatter.date(from: dateString) {
                return date
            }
            
            // Try with time zone without seconds
            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm zzz"
            if let date = localFormatter.date(from: dateString) {
                return date
            }
            
            // Try with offset timezone like -0700
            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            if let date = localFormatter.date(from: dateString) {
                return date
            }
            
            // Try ISO 8601 format
            if let date = alternateFormatter.date(from: dateString) {
                return date
            }
            
            // Try more fallback formats
            let formats = [
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd HH:mm",
                "EEE, dd MMM yyyy",
                "dd MMM yyyy HH:mm:ss Z"
            ]
            
            for format in formats {
                localFormatter.dateFormat = format
                if let date = localFormatter.date(from: dateString) {
                    return date
                }
            }
            
            // If we get here, we couldn't parse the date with standard formats
            return nil
        }

        itemsToSort.sort {
            // Get dates for both items
            let date1 = parseDate($0.pubDate)
            let date2 = parseDate($1.pubDate)
            
            // If both dates can be parsed, use them for comparison
            if let d1 = date1, let d2 = date2 {
                return self.isSortedAscending ? d1 < d2 : d1 > d2
            }
            
            // If only one date can be parsed, the one with a valid date should come first
            if date1 != nil {
                return self.isSortedAscending ? false : true  // Valid date first in descending order
            }
            if date2 != nil {
                return self.isSortedAscending ? true : false  // Valid date first in descending order
            }
            
            // If neither date can be parsed and both are not empty, compare strings
            if !$0.pubDate.isEmpty && !$1.pubDate.isEmpty {
                // Just use string comparison as a fallback
                return self.isSortedAscending ? $0.pubDate < $1.pubDate : $0.pubDate > $1.pubDate
            }
            
            // Place empty dates at the end
            if $0.pubDate.isEmpty {
                return self.isSortedAscending ? true : false
            }
            if $1.pubDate.isEmpty {
                return self.isSortedAscending ? false : true
            }
            
            // If we're here, both are empty - considered equal
            return false
        }
        
        // Debug printing - print first and last dates after sorting
        if !itemsToSort.isEmpty {
            print("Sorted items - first item date: \(itemsToSort.first?.pubDate ?? "none"), last item date: \(itemsToSort.last?.pubDate ?? "none"), ascending: \(self.isSortedAscending)")
        }
    }

    // MARK: - Data Loading and Saving

    // One-time CloudKit readItems reset for migration issues
    private func resetCloudKitReadItemsIfNeeded(completion: (() -> Void)? = nil) {
        CloudKitStorage().save([String](), forKey: "readItems") { error in
            if let error = error {
                print("Error resetting CloudKit readItems: \(error.localizedDescription)")
            } else {
                print("Successfully reset CloudKit readItems to empty array.")
            }
            completion?()
        }
    }

    // Save read state using asynchronous storage
    private func saveReadState() {
        // Map all read items to their normalized links
        let newReadLinks = self.items.filter { $0.isRead }.map { self.normalizeLink($0.link) }
        
        // Also include any read items from allItems that may not be in the current view
        let allReadLinks = self._allItems.filter { $0.isRead }.map { self.normalizeLink($0.link) }
        
        // Combine both sets
        let combinedReadLinks = Set(newReadLinks).union(Set(allReadLinks))
        
        if combinedReadLinks.isEmpty {
            print("No read items to save")
            return
        }
        
        print("[saveReadState] Saving \(combinedReadLinks.count) read links")
        
        // Use the improved merge-based save function in StorageManager
        StorageManager.shared.save(Array(combinedReadLinks), forKey: "readItems") { error in
            if let error = error {
                print("Error saving read items: \(error.localizedDescription)")
            } else {
                print("Successfully saved read items")
            }
        }
    }

    // Helper function to load cached articles for a given feed from CloudKit.
    private func loadCachedArticles(forFeed feedId: String) {
        CloudKitStorage().loadArticles(forFeed: feedId) { [weak self] result in
            switch result {
            case .success(let cachedArticles):
                // Convert ArticleSummary objects back into RSSItem instances.
                let cachedItems = cachedArticles.map { summary in
                    RSSItem(
                        title: summary.title,
                        link: summary.link,
                        pubDate: summary.pubDate,
                        source: feedId,
                        isRead: false)
                }
                self?.items.append(contentsOf: cachedItems)
                DispatchQueue.main.async {
                    self?.tableView.reloadData()
                }
            case .failure(let error):
                print(
                    "Error loading cached articles for feed \(feedId): \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Navigation Bar and Buttons
    private func setupNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        // Use your new dynamic color here:
        appearance.backgroundColor = AppColors.navBarBackground

        // Make title text dynamic too (white in Dark Mode, black in Light Mode)
        let titleColor = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: titleColor,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        appearance.titleTextAttributes = titleAttributes
        appearance.largeTitleTextAttributes = titleAttributes

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationController?.navigationBar.compactScrollEdgeAppearance = appearance
        }

        setupNavigationButtons()
        updateNavigationButtons()
    }

    private func setupNavigationButtons() {
        // Create each bar button
        rssButton = createBarButton(
            imageName: "rss",
            action: #selector(rssButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )
        refreshButton = createBarButton(
            imageName: "refresh",
            action: #selector(refreshButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )
        bookmarkButton = createBarButton(
            imageName: "bookmark",
            action: #selector(bookmarkButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )
        heartButton = createBarButton(
            imageName: "heart",
            action: #selector(heartButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )

        // Special handling for SF Symbol for the sort button
        let sortButtonImage = resizeImage(
            UIImage(systemName: "arrow.up.arrow.down"), // Use systemName for SF Symbols
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        sortButton = UIBarButtonItem(
            image: sortButtonImage,
            style: .plain,
            target: self,
            action: #selector(sortButtonTapped)
        )
        sortButton?.tintColor = AppColors.dynamicIconColor

        // Create your right-side buttons
        settingsButton = createBarButton(
            imageName: "settings",
            action: #selector(openSettings),
            tintColor: AppColors.dynamicIconColor
        )
        editButton = createBarButton(
            imageName: "edit",
            action: #selector(editButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )

        // Assign them in the order you want on the left side
        navigationItem.leftBarButtonItems = [
            rssButton,
            refreshButton,
            bookmarkButton,
            heartButton
        ].compactMap { $0 } // Use properties and compactMap to handle potential nils

        // Assign the right-side buttons
        navigationItem.rightBarButtonItems = [settingsButton, editButton, sortButton].compactMap { $0 } // Add sortButton here
    }

    private func createBarButton(
        imageName: String,
        action: Selector,
        tintColor: UIColor = .white,
        renderOriginal: Bool = false
    ) -> UIBarButtonItem {
        let renderingMode: UIImage.RenderingMode = renderOriginal ? .alwaysOriginal : .alwaysTemplate
        let buttonImage = resizeImage(
            UIImage(named: imageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(renderingMode)

        let button = UIBarButtonItem(
            image: buttonImage,
            style: .plain,
            target: self,
            action: action
        )
        button.tintColor = tintColor
        return button
    }

    // MARK: - Table View Setup and Footer
    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(
            UITableViewCell.self, forCellReuseIdentifier: "RSSCell")
        setupTableViewFooter()
        tableView.tableFooterView = footerView
    }

    private func setupTableViewFooter() {
        footerView = UIView(
            frame: CGRect(x: 0, y: 0, width: view.frame.width, height: 80))
        footerView?.backgroundColor = AppColors.background

        let markAllButton = UIButton(type: .system)
        markAllButton.translatesAutoresizingMaskIntoConstraints = false
        footerView?.addSubview(markAllButton)

        markAllButton.backgroundColor = AppColors.primary
        // Show "No Articles" if the items array is empty; otherwise show the button title.
        markAllButton.setTitle(items.isEmpty ? "No Articles" : "Mark All as Read", for: .normal)
        markAllButton.isEnabled = !items.isEmpty
        markAllButton.setTitleColor(.white, for: .normal)
        markAllButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        markAllButton.layer.cornerRadius = 20
        markAllButton.layer.masksToBounds = true

        NSLayoutConstraint.activate([
            markAllButton.centerXAnchor.constraint(
                equalTo: footerView!.centerXAnchor),
            markAllButton.centerYAnchor.constraint(
                equalTo: footerView!.centerYAnchor),
            markAllButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        markAllButton.addTarget(
            self, action: #selector(markAllAsReadTapped), for: .touchUpInside)
        footerRefreshButton = markAllButton
    }

    private func updateFooterVisibility() {
        if currentFeedType == .bookmarks || currentFeedType == .heart {
            tableView.tableFooterView = nil
        } else {
            // If the footer view is already set up, update the button title and enabled state.
            if let markAllButton = footerRefreshButton {
                let newTitle = items.isEmpty ? "No Articles" : "Mark All as Read"
                markAllButton.setTitle(newTitle, for: .normal)
                markAllButton.isEnabled = !items.isEmpty
            } else {
                // Otherwise, create it
                setupTableViewFooter()
            }
            tableView.tableFooterView = footerView
        }
    }

    @IBAction func markAllAsReadTapped(_ sender: UIButton) {
        // Only proceed if there are articles.
        guard !items.isEmpty else { return }
        
        let alert = UIAlertController(
            title: "Mark All as Read",
            message: "This action will mark all your feed items as read. Are you sure you want to continue?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            // Update local items: mark each one as read.
            self.items = self.items.map { item in
                var updatedItem = item
                updatedItem.isRead = true
                return updatedItem
            }
            
            // Also update the full set if needed.
            self.allItems = self.allItems.map { item in
                var updatedItem = item
                updatedItem.isRead = true
                return updatedItem
            }
            
            // Save the new read state locally (which also handles deduplication and cleanup).
            self.saveReadState()
            
            // Reload the table view to update the UI immediately.
            self.tableView.reloadData()
            
            // Now update storage—this will update both UserDefaults and iCloud.
            StorageManager.shared.markAllAsRead { success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error marking all as read: \(error.localizedDescription)")
                    }
                    // Reload again in case any external state changed.
                    self.tableView.reloadData()
                }
            }
        }))
        
        self.present(alert, animated: true, completion: nil)
    }

    @objc private func refreshButtonTapped() {
        // 1) Hide tableView and show loading indicator
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        
        // 2) Manually begin showing the refresh spinner (it will be hidden with the tableView)
        if !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }
        
        // 3) Now do your actual refresh logic
        refreshFeeds()
    }

    @objc private func refreshFeeds() {
        // Hide tableView and show loading indicator during refresh
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        startRefreshAnimation() // Start animation
        loadRSSFeeds()
    }

    // MARK: - Feed Type Button Actions
    @objc private func rssButtonTapped() {
        currentFeedType = .rss
    }

    @objc private func bookmarkButtonTapped() {
        currentFeedType = .bookmarks
    }

    @objc private func heartButtonTapped() {
        currentFeedType = .heart
    }

    @objc private func editButtonTapped() {
        let rssSettingsVC = RSSSettingsViewController()
        navigationController?.pushViewController(rssSettingsVC, animated: true)
    }

    @objc private func openSettings() {
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
    }

    @objc private func sortButtonTapped() {
        let alert = UIAlertController(title: "Sort Articles", message: nil, preferredStyle: .actionSheet)

        let newestFirstAction = UIAlertAction(title: "Newest First", style: .default) { [weak self] _ in
            self?.sortItems(ascending: false)
        }
        // Add a checkmark if this is the current sort order
        if !isSortedAscending {
            newestFirstAction.setValue(true, forKey: "checked")
        }

        let oldestFirstAction = UIAlertAction(title: "Oldest First", style: .default) { [weak self] _ in
            self?.sortItems(ascending: true)
        }
        // Add a checkmark if this is the current sort order
        if isSortedAscending {
            oldestFirstAction.setValue(true, forKey: "checked")
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(newestFirstAction)
        alert.addAction(oldestFirstAction)
        alert.addAction(cancelAction)

        // For iPad compatibility
        if let popoverController = alert.popoverPresentationController {
            popoverController.barButtonItem = sortButton
        }

        present(alert, animated: true)
    }

    // MARK: - Sorting Logic
    private func sortItems(ascending: Bool) {
        isSortedAscending = ascending
        // Save sort order to UserDefaults
        UserDefaults.standard.set(ascending, forKey: "articleSortAscending")
        
        // Create a more robust date formatter that can handle different RSS date formats
        let primaryFormatter = DateFormatter()
        primaryFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        primaryFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Secondary formatter for alternative formats that might appear
        let alternateFormatter = DateFormatter()
        alternateFormatter.locale = Locale(identifier: "en_US_POSIX")
        alternateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ" // ISO 8601 format
        
        // Helper function to parse dates with multiple formatters
        func parseDate(_ dateString: String) -> Date? {
            // Skip empty strings
            if dateString.isEmpty {
                return nil
            }
            
            // Try standard RSS format first
            if let date = primaryFormatter.date(from: dateString) {
                return date
            }
            
            // Try local timezone format (like PDT)
            let localFormatter = DateFormatter()
            localFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            // Common RSS format with different timezone (PDT/PST/EDT etc)
            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = localFormatter.date(from: dateString) {
                return date
            }
            
            // Try with time zone without seconds
            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm zzz"
            if let date = localFormatter.date(from: dateString) {
                return date
            }
            
            // Try with offset timezone like -0700
            localFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            if let date = localFormatter.date(from: dateString) {
                return date
            }
            
            // Try ISO 8601 format
            if let date = alternateFormatter.date(from: dateString) {
                return date
            }
            
            // Try more fallback formats
            let formats = [
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd HH:mm",
                "EEE, dd MMM yyyy",
                "dd MMM yyyy HH:mm:ss Z"
            ]
            
            for format in formats {
                localFormatter.dateFormat = format
                if let date = localFormatter.date(from: dateString) {
                    return date
                }
            }
            
            // If we get here, we couldn't parse the date with standard formats
            return nil
        }

        // Log before sorting
        if !items.isEmpty {
            print("Before sorting - first item date: \(items.first?.pubDate ?? "none"), last item date: \(items.last?.pubDate ?? "none")")
        }

        // Sort the current items
        items.sort {
            // Get dates for both items
            let date1 = parseDate($0.pubDate)
            let date2 = parseDate($1.pubDate)
            
            // If both dates can be parsed, use them for comparison
            if let d1 = date1, let d2 = date2 {
                return ascending ? d1 < d2 : d1 > d2
            }
            
            // If only one date can be parsed, the one with a valid date should come first
            if date1 != nil {
                return ascending ? false : true  // Valid date first in descending order
            }
            if date2 != nil {
                return ascending ? true : false  // Valid date first in descending order
            }
            
            // If neither date can be parsed and both are not empty, compare strings
            if !$0.pubDate.isEmpty && !$1.pubDate.isEmpty {
                // Just use string comparison as a fallback
                return ascending ? $0.pubDate < $1.pubDate : $0.pubDate > $1.pubDate
            }
            
            // Place empty dates at the end
            if $0.pubDate.isEmpty {
                return ascending ? true : false
            }
            if $1.pubDate.isEmpty {
                return ascending ? false : true
            }
            
            // If we're here, both are empty - considered equal
            return false
        }
        
        // Log after sorting
        if !items.isEmpty {
            print("After sorting - first item date: \(items.first?.pubDate ?? "none"), last item date: \(items.last?.pubDate ?? "none"), ascending: \(ascending)")
        }
        
        // Also sort the allItems array if we're viewing the RSS feed
        if currentFeedType == .rss {
            _allItems.sort {
                // Get dates for both items
                let date1 = parseDate($0.pubDate)
                let date2 = parseDate($1.pubDate)
                
                // If both dates can be parsed, use them for comparison
                if let d1 = date1, let d2 = date2 {
                    return ascending ? d1 < d2 : d1 > d2
                }
                
                // If only one date can be parsed, the one with a valid date should come first
                if date1 != nil {
                    return ascending ? false : true  // Valid date first in descending order
                }
                if date2 != nil {
                    return ascending ? true : false  // Valid date first in descending order
                }
                
                // If neither date can be parsed and both are not empty, compare strings
                if !$0.pubDate.isEmpty && !$1.pubDate.isEmpty {
                    // Just use string comparison as a fallback
                    return ascending ? $0.pubDate < $1.pubDate : $0.pubDate > $1.pubDate
                }
                
                // Place empty dates at the end
                if $0.pubDate.isEmpty {
                    return ascending ? true : false
                }
                if $1.pubDate.isEmpty {
                    return ascending ? false : true
                }
                
                // If we're here, both are empty - considered equal
                return false
            }
        }
        
        // Reload the table to show newly sorted items
        tableView.reloadData()
    }

    // MARK: - Image Resizing and Trait Changes
    func resizeImage(_ image: UIImage?, targetSize: CGSize) -> UIImage? {
        guard let image = image else { return nil }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(
            comparedTo: previousTraitCollection)
        {
            setupNavigationBar()
            tableView.backgroundColor = AppColors.background
            tableView.reloadData()
        }
    }

    // MARK: - Refresh Button Animation
    private func startRefreshAnimation() {
        // Create a direct animation on the UIBarButtonItem
        guard let refreshButton = self.refreshButton else {
            print("Refresh button not available")
            return
        }
        
        // Create a UIImageView to hold the animation
        let imageView = UIImageView(image: UIImage(named: "refresh")?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = AppColors.dynamicIconColor
        imageView.contentMode = .scaleAspectFit
        
        // Set up the rotation animation
        let rotation = CABasicAnimation(keyPath: "transform.rotation")
        rotation.fromValue = 0.0
        rotation.toValue = CGFloat.pi * 2.0
        rotation.duration = 1.0
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        
        // Apply the animation
        imageView.layer.add(rotation, forKey: "rotationAnimation")
        
        // Resize to match bar button item size
        let resizedImageView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        imageView.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        imageView.center = CGPoint(x: resizedImageView.bounds.midX, y: resizedImageView.bounds.midY)
        resizedImageView.addSubview(imageView)
        
        // Replace the current button with this animated view
        refreshButton.customView = resizedImageView
    }
    
    private func stopRefreshAnimation() {
        // Return to the normal button state
        guard let refreshButton = self.refreshButton else { return }
        
        // Remove the custom view to restore the normal button
        refreshButton.customView = nil
        
        // Recreate the standard button
        refreshButton.image = resizeImage(
            UIImage(named: "refresh"),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        refreshButton.tintColor = AppColors.dynamicIconColor
    }
}

// MARK: - TableView Delegate and DataSource
extension HomeFeedViewController: UITableViewDelegate, UITableViewDataSource {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Ensure we're dealing with the table view's scroll view
        guard scrollView == tableView else { return }

        //print("scrollViewDidScroll called")

        // Get the index paths of the currently visible rows
        guard let visibleRows = tableView.indexPathsForVisibleRows, !visibleRows.isEmpty else {
            //print("No visible rows")
            return
        }

        //print("Visible rows: \(visibleRows.map { $0.row })")

        // Find the minimum row index among visible rows
        let currentMinVisibleRow = visibleRows.map { $0.row }.min() ?? 0
        //print("previousMinVisibleRow: \(previousMinVisibleRow), currentMinVisibleRow: \(currentMinVisibleRow)")

        // Check if the user scrolled down past the previously tracked top row
        if currentMinVisibleRow > previousMinVisibleRow {
            var indexPathsToUpdate: [IndexPath] = []

            // Iterate through the rows that have just scrolled off the top
            for index in previousMinVisibleRow..<currentMinVisibleRow {
                // Ensure the index is valid
                if index >= 0 && index < items.count {
                    let normLink = self.normalizeLink(items[index].link)
                    if !items[index].isRead && !readLinks.contains(normLink) {
                        //print("Marking article at index \(index) as read: \(items[index].title)")
                        items[index].isRead = true
                        indexPathsToUpdate.append(IndexPath(row: index, section: 0))
                    }
                }
            }

            // If any items were marked as read, save the state and reload the rows
            if !indexPathsToUpdate.isEmpty {
                //print("Saving read state and reloading rows: \(indexPathsToUpdate.map { $0.row })")
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
        return items.count
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "RSSCell", for: indexPath)
        let item = items[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = "\(item.source) • \(getTimeAgo(from: item.pubDate))"
        cell.backgroundColor = AppColors.background
        config.textProperties.color = item.isRead ? AppColors.secondary : AppColors.accent
        config.secondaryTextProperties.color = AppColors.secondary
        config.secondaryTextProperties.font = .systemFont(ofSize: 12)
        
        // Get the font size from UserDefaults (defaulting to 16 if not set)
        let storedFontSize = CGFloat(UserDefaults.standard.float(forKey: "fontSize") != 0 ? UserDefaults.standard.float(forKey: "fontSize") : 16)
        config.textProperties.font = .systemFont(ofSize: storedFontSize, weight: item.isRead ? .regular : .medium)
        
        cell.accessoryType = .disclosureIndicator
        cell.contentConfiguration = config
        return cell
    }

    func tableView(
        _ tableView: UITableView, didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let url = URL(string: items[indexPath.row].link) {
            items[indexPath.row].isRead = true
            if let cell = tableView.cellForRow(at: indexPath) {
                configureCell(cell, with: items[indexPath.row])
            }
            scheduleSaveReadState()

            let configuration = SFSafariViewController.Configuration()
            configuration.entersReaderIfAvailable = true
            let safariVC = SFSafariViewController(
                url: url, configuration: configuration)
            safariVC.dismissButtonStyle = .close
            safariVC.preferredControlTintColor = AppColors.accent
            safariVC.delegate = self
            present(safariVC, animated: true)
        }
    }

    private func configureCell(_ cell: UITableViewCell, with item: RSSItem) {
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText =
            "\(item.source) • \(getTimeAgo(from: item.pubDate))"
        config.textProperties.color =
            item.isRead ? AppColors.secondary : AppColors.accent
        config.secondaryTextProperties.color = AppColors.secondary
        config.secondaryTextProperties.font = .systemFont(ofSize: 12)
        config.textProperties.font = .systemFont(
            ofSize: 16, weight: item.isRead ? .regular : .medium)
        cell.contentConfiguration = config
    }

    private func toggleHeart(
        for item: RSSItem, completion: @escaping () -> Void
    ) {
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

    private func toggleBookmark(
        for item: RSSItem, completion: @escaping () -> Void
    ) {
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

extension HomeFeedViewController: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true)
    }
}

// MARK: - RSSParser
class RSSParser: NSObject, XMLParserDelegate {
    private(set) var items: [RSSItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var parsingItem = false
    private var feedSource: String

    init(source: String) {
        self.feedSource = source
        super.init()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" {
            parsingItem = true
            currentTitle = ""
            currentLink = ""
            currentPubDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if parsingItem {
            switch currentElement {
            case "title":
                currentTitle += string
            case "link":
                currentLink += string
            case "pubDate":
                currentPubDate += string
            default:
                break
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            let item = RSSItem(
                title: currentTitle.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                pubDate: currentPubDate.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                source: feedSource)
            items.append(item)
            parsingItem = false
        }
    }
}
