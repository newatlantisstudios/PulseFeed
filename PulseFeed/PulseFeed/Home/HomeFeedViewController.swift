import SafariServices
import UIKit

// MARK: - HomeFeedViewController
class HomeFeedViewController: UIViewController, CALayerDelegate {
    
    // MARK: - CALayerDelegate
    func layoutSublayers(of layer: CALayer) {
        // This is called when the layer's bounds change
        // Update any gradient layers to fit their containing views
        if let gradientLayer = layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = layer.bounds
        }
    }

    // MARK: - Properties
    
    // Data
    internal var items: [RSSItem] = []
    internal var _allItems: [RSSItem] = []
    var readLinks: Set<String> = [] // Store normalized read links
    internal var heartedItems: Set<String> = []
    internal var bookmarkedItems: Set<String> = []
    internal var cachedArticleLinks: Set<String> = [] // Track which articles are cached for offline reading
    internal var hasLoadedRSSFeeds = false
    internal var isSortedAscending: Bool = false // State for sorting order
    internal var isOfflineMode = false // Track if we're in offline mode
    internal var filterKeywords: [String] = [] // Keywords used to filter articles
    internal var isContentFilteringEnabled: Bool = false // Whether content filtering is enabled
    
    // UI Components
    let tableView = UITableView()
    let refreshControl = UIRefreshControl()
    private var longPressGesture: UILongPressGestureRecognizer!
    internal var footerView: UIView?
    internal var footerRefreshButton: UIButton?
    var loadingIndicator: UIActivityIndicatorView!
    var loadingLabel: UILabel!
    var previousMinVisibleRow: Int = 0 // Track the topmost visible row
    
    // Navigation Items
    var rssButton: UIBarButtonItem?
    var refreshButton: UIBarButtonItem?
    var bookmarkButton: UIBarButtonItem?
    var heartButton: UIBarButtonItem?
    var folderButton: UIBarButtonItem?
    var settingsButton: UIBarButtonItem?
    
    // Timer for refresh operations
    internal var refreshTimeoutTimer: Timer?
    
    // Configuration
    internal var useEnhancedStyle: Bool {
        return UserDefaults.standard.bool(forKey: "enhancedArticleStyle")
    }
    
    // Feed types
    enum FeedType {
        case rss, bookmarks, heart, folder(id: String)
        
        var displayName: String {
            switch self {
            case .rss: return "All Feeds"
            case .bookmarks: return "Bookmarks"
            case .heart: return "Favorites"
            case .folder: return "Folder"
            }
        }
    }
    
    internal var currentFeedType: FeedType = .rss {
        didSet {
            updateTableViewContent()
            updateNavigationButtons()
        }
    }
    
    // Current folder if any
    var currentFolder: FeedFolder?
    
    // Property to access allItems
    var allItems: [RSSItem] {
        get { return _allItems }
        set { _allItems = newValue }
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(fontSizeChanged(_:)), name: Notification.Name("fontSizeChanged"), object: nil)
        
        // Setup UI elements
        setupLoadingIndicator()
        setupRefreshControl()
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Ensure navigation bar is correctly configured
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.prefersLargeTitles = false
        setupNavigationBar()
        setupNotificationObserver()
        setupLongPressGesture()
        
        // Hide tableView initially until articles are loaded
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        
        // Start the animation immediately
        startRefreshAnimation()
        
        // Load feeds
        loadRSSFeeds()

        // Load cached data
        loadCachedData()
        
        // Restore sort order
        restoreSortOrder()
        
        // Update offline status
        updateOfflineStatus()
        
        // Load filter settings
        loadFilterSettings()
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
            
            // Ensure refresh icon is spinning
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startRefreshAnimation()
            }
            
            // Start the refresh spinner but keep it invisible until tableView is shown
            refreshControl.beginRefreshing()

            // Call the refresh method
            refreshFeeds()
        } else {
            // Ensure the footer is visible after feeds have loaded
            if case .rss = currentFeedType {
                // Always recreate the footer to ensure it's properly configured
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.addFooterToTableView()
                    self.updateReadStatusIndicator()
                }
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Ensure the footer view is properly laid out after view appears
        if case .rss = currentFeedType {
            if tableView.tableFooterView == nil {
                // Always create a footer with the button
                addFooterToTableView()
            }
            
            // Check if all articles are read, but we'll always show the Mark All as Read button
            let allArticlesRead = !items.isEmpty && !items.contains { !$0.isRead }
            if allArticlesRead && !tableView.isHidden {
                DispatchQueue.main.async {
                    // We still want to show the congratulatory message
                    self.checkAndShowAllReadMessage()
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCachedData() {
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
        
        // Load cached article links
        StorageManager.shared.getAllCachedArticles { [weak self] result in
            guard let self = self else { return }
            
            if case .success(let cachedArticles) = result {
                DispatchQueue.main.async {
                    // Store the cached article links for UI indicators
                    self.cachedArticleLinks = Set(cachedArticles.map { self.normalizeLink($0.link) })
                    
                    // If table is visible, reload to update cache indicators
                    if !self.tableView.isHidden {
                        self.tableView.reloadData()
                    }
                    
                    print("DEBUG: Loaded \(self.cachedArticleLinks.count) cached article links")
                }
            }
        }
    }
    
    // MARK: - Offline Mode
    
    private func updateOfflineStatus() {
        // Get current offline status
        isOfflineMode = StorageManager.shared.isDeviceOffline
        
        // Setup observers for changes to offline status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOfflineStatusChanged(_:)),
            name: Notification.Name("OfflineStatusChanged"),
            object: nil
        )
        
        // Setup observers for article cache changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArticleCached(_:)),
            name: Notification.Name("ArticleCached"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArticleRemovedFromCache(_:)),
            name: Notification.Name("ArticleRemovedFromCache"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArticleCacheCleared),
            name: Notification.Name("ArticleCacheCleared"),
            object: nil
        )
        
        // Update UI based on offline status
        updateOfflineModeUI()
    }
    
    private func updateOfflineModeUI() {
        // If we're in offline mode, update the navigation bar title
        if isOfflineMode {
            // Add "Offline" to title
            if let oldTitle = title, !oldTitle.contains("(Offline)") {
                title = "\(oldTitle) (Offline)"
            }
            
            // Show a banner to indicate offline mode if not already showing
            showOfflineBanner()
            
            // Disable refresh button
            refreshButton?.isEnabled = false
            refreshButton?.tintColor = AppColors.secondary
        } else {
            // Remove "Offline" from title
            if let oldTitle = title, oldTitle.contains("(Offline)") {
                title = oldTitle.replacingOccurrences(of: " (Offline)", with: "")
            }
            
            // Hide offline banner if showing
            hideOfflineBanner()
            
            // Enable refresh button
            refreshButton?.isEnabled = true
            refreshButton?.tintColor = AppColors.dynamicIconColor
        }
    }
    
    @objc private func handleOfflineStatusChanged(_ notification: Notification) {
        if let isOffline = notification.userInfo?["isOffline"] as? Bool {
            DispatchQueue.main.async {
                self.isOfflineMode = isOffline
                self.updateOfflineModeUI()
                
                // If going from online to offline, try to load cached articles
                if isOffline {
                    self.loadCachedArticlesForOfflineMode()
                }
            }
        }
    }
    
    @objc private func handleArticleCached(_ notification: Notification) {
        if let link = notification.userInfo?["link"] as? String {
            let normalizedLink = normalizeLink(link)
            
            DispatchQueue.main.async {
                // Add to cached articles set
                self.cachedArticleLinks.insert(normalizedLink)
                
                // Reload table to update cache indicators
                self.tableView.reloadData()
            }
        }
    }
    
    @objc private func handleArticleRemovedFromCache(_ notification: Notification) {
        if let link = notification.userInfo?["link"] as? String {
            let normalizedLink = normalizeLink(link)
            
            DispatchQueue.main.async {
                // Remove from cached articles set
                self.cachedArticleLinks.remove(normalizedLink)
                
                // Reload table to update cache indicators
                self.tableView.reloadData()
            }
        }
    }
    
    @objc private func handleArticleCacheCleared() {
        DispatchQueue.main.async {
            // Clear cached articles set
            self.cachedArticleLinks.removeAll()
            
            // Reload table to update cache indicators
            self.tableView.reloadData()
        }
    }
    
    private func loadCachedArticlesForOfflineMode() {
        // Load all cached articles
        StorageManager.shared.getAllCachedArticles { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let cachedArticles):
                DispatchQueue.main.async {
                    // If no cached articles, show message
                    if cachedArticles.isEmpty {
                        self.showEmptyCacheMessage()
                        return
                    }
                    
                    // Create RSSItems from cached articles
                    var cachedItems: [RSSItem] = []
                    
                    for article in cachedArticles {
                        // Create RSSItem from cached article
                        let rssItem = RSSItem(
                            title: article.title,
                            link: article.link,
                            pubDate: DateFormatter.localizedString(from: article.cachedDate, dateStyle: .medium, timeStyle: .short),
                            source: article.source
                        )
                        
                        // Add to array
                        cachedItems.append(rssItem)
                    }
                    
                    // Sort by cached date (most recent first)
                    cachedItems.sort { 
                        let date1 = DateUtils.parseDate($0.pubDate) ?? Date.distantPast
                        let date2 = DateUtils.parseDate($1.pubDate) ?? Date.distantPast
                        return date1 > date2
                    }
                    
                    // Update UI
                    self.items = cachedItems
                    self.tableView.reloadData()
                    self.tableView.isHidden = false
                    self.loadingIndicator.stopAnimating()
                    self.stopRefreshAnimation()
                    self.refreshControl.endRefreshing()
                }
                
            case .failure(let error):
                print("DEBUG: Error loading cached articles: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.showEmptyCacheMessage()
                }
            }
        }
    }
    
    private func showEmptyCacheMessage() {
        // Show message when no cached articles are available in offline mode
        let alert = UIAlertController(
            title: "No Cached Articles",
            message: "You're in offline mode, but no articles have been cached for offline reading. Connect to the internet to read new articles.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        
        // Hide loading indicators
        loadingIndicator.stopAnimating()
        stopRefreshAnimation()
        refreshControl.endRefreshing()
        
        // Empty the items array and show empty table
        items = []
        tableView.reloadData()
        tableView.isHidden = false
    }
    
    // MARK: - Offline Banner
    
    private var offlineBannerView: UIView?
    
    private func showOfflineBanner() {
        // Don't show banner if it's already visible
        if offlineBannerView != nil {
            return
        }
        
        // Create banner
        let banner = UIView()
        banner.backgroundColor = AppColors.warning
        banner.translatesAutoresizingMaskIntoConstraints = false
        
        // Create label
        let label = UILabel()
        label.text = "Offline Mode - Showing Cached Articles"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to view
        banner.addSubview(label)
        view.addSubview(banner)
        
        // Add constraints
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            banner.heightAnchor.constraint(equalToConstant: 30),
            
            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])
        
        // Adjust table view top constraint
        for constraint in tableView.constraints where constraint.firstAttribute == .top {
            constraint.constant = 30
        }
        
        // Store reference
        offlineBannerView = banner
        
        // Animate in
        banner.alpha = 0
        UIView.animate(withDuration: 0.3) {
            banner.alpha = 1
        }
    }
    
    private func hideOfflineBanner() {
        // Only hide if banner is visible
        guard let banner = offlineBannerView else {
            return
        }
        
        // Animate out and remove
        UIView.animate(withDuration: 0.3, animations: {
            banner.alpha = 0
        }) { _ in
            banner.removeFromSuperview()
            self.offlineBannerView = nil
            
            // Reset table view top constraint
            for constraint in self.tableView.constraints where constraint.firstAttribute == .top {
                constraint.constant = 0
            }
        }
    }
    
    private func restoreSortOrder() {
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
    
    // MARK: - Content Filtering
    
    private func loadFilterSettings() {
        // Load filter enabled state
        isContentFilteringEnabled = UserDefaults.standard.bool(forKey: "enableContentFiltering")
        
        // Load filter keywords
        StorageManager.shared.load(forKey: "filterKeywords") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let keywords):
                    self.filterKeywords = keywords
                case .failure:
                    self.filterKeywords = []
                }
                
                // Apply filtering to current items
                if self.isContentFilteringEnabled && !self.filterKeywords.isEmpty {
                    self.updateTableViewContent()
                }
            }
        }
    }
    
    internal func shouldFilterArticle(_ item: RSSItem) -> Bool {
        // Skip filtering if not enabled or no keywords are set
        if !isContentFilteringEnabled || filterKeywords.isEmpty {
            return false
        }
        
        // Check if article contains any filter keywords in title or description
        for keyword in filterKeywords {
            let lowercaseKeyword = keyword.lowercased()
            
            // Check title
            if item.title.lowercased().contains(lowercaseKeyword) {
                return true
            }
            
            // Check description if available
            if let description = item.description, description.lowercased().contains(lowercaseKeyword) {
                return true
            }
            
            // Check content if available
            if let content = item.content, content.lowercased().contains(lowercaseKeyword) {
                return true
            }
            
            // Check source
            if item.source.lowercased().contains(lowercaseKeyword) {
                return true
            }
            
            // Check author if available
            if let author = item.author, author.lowercased().contains(lowercaseKeyword) {
                return true
            }
        }
        
        return false
    }
    
    @objc private func handleContentFilteringChanged() {
        // Update filter enabled state
        isContentFilteringEnabled = UserDefaults.standard.bool(forKey: "enableContentFiltering")
        
        // Reload filter keywords
        StorageManager.shared.load(forKey: "filterKeywords") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let keywords):
                    self.filterKeywords = keywords
                case .failure:
                    self.filterKeywords = []
                }
                
                // Update table content with the new filters
                self.updateTableViewContent()
            }
        }
    }
    
    private func setupNotificationObserver() {
        // Add observers for various notification events
        let notifications: [(name: Notification.Name, selector: Selector)] = [
            (.init("readItemsReset"), #selector(handleReadItemsReset)),
            (.init("readItemsUpdated"), #selector(handleReadItemsUpdated)),
            (.init("bookmarkedItemsUpdated"), #selector(handleBookmarkedItemsUpdated)),
            (.init("heartedItemsUpdated"), #selector(handleHeartedItemsUpdated)),
            (.init("articleSortOrderChanged"), #selector(handleSortOrderChanged)),
            (.init("feedFoldersUpdated"), #selector(handleFeedFoldersUpdated)),
            (.init("showReadArticlesChanged"), #selector(handleShowReadArticlesChanged)),
            (.init("contentFilteringChanged"), #selector(handleContentFilteringChanged))
        ]
        
        notifications.forEach { notification in
            NotificationCenter.default.addObserver(
                self,
                selector: notification.selector,
                name: notification.name,
                object: nil)
        }
    }
    
    private func setupLongPressGesture() {
        longPressGesture = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPressGesture)
    }
    
    // Helper to normalize links for consistent comparison
    func normalizeLink(_ link: String) -> String {
        return StorageManager.shared.normalizeLink(link)
    }
    
    // MARK: - Event Handlers
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let point = gesture.location(in: tableView)
            if let indexPath = tableView.indexPathForRow(at: point) {
                showMarkAboveAlert(for: indexPath)
            }
        }
    }
    
    private func showMarkAboveAlert(for indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Mark as Read",
            message: "Do you want to mark all articles above this one as read?",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Mark Read", style: .default) { [weak self] _ in
                self?.markItemsAboveAsRead(indexPath)
            })
        present(alert, animated: true)
    }
    
    private func markItemsAboveAsRead(_ indexPath: IndexPath) {
        for index in 0...indexPath.row {
            items[index].isRead = true
        }
        scheduleSaveReadState()
        let indexPaths = (0...indexPath.row).map { IndexPath(row: $0, section: 0) }
        tableView.reloadRows(at: indexPaths, with: .fade)
    }
    
    private var saveReadStateWorkItem: DispatchWorkItem?
    private let saveReadStateDebounceInterval: TimeInterval = 1.5
    
    // Debounced save for read state
    func scheduleSaveReadState() {
        saveReadStateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveReadState()
        }
        saveReadStateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveReadStateDebounceInterval, execute: workItem)
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleReadItemsReset() {
        loadRSSFeeds()
    }
    
    @objc private func handleReadItemsUpdated() {
        StorageManager.shared.load(forKey: "readItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let readItems):
                DispatchQueue.main.async {
                    // Update cached read links
                    self.readLinks = Set(readItems.map { self.normalizeLink($0) })
                    
                    // Update read state for all items
                    self.updateReadState()
                    
                    // Reload the table view
                    self.tableView.reloadData()
                }
            case .failure(let error):
                print("ERROR: Failed to load updated read items: \(error.localizedDescription)")
            }
        }
    }
    
    private func updateReadState() {
        // Update all items
        for i in 0..<self._allItems.count {
            let normLink = normalizeLink(_allItems[i].link)
            _allItems[i].isRead = readLinks.contains(normLink)
        }
        
        // Update current items
        for i in 0..<items.count {
            let normLink = normalizeLink(items[i].link)
            items[i].isRead = readLinks.contains(normLink)
        }
    }
    
    @objc private func handleBookmarkedItemsUpdated() {
        StorageManager.shared.load(forKey: "bookmarkedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let bookmarkedItems):
                DispatchQueue.main.async {
                    // Update cached bookmarked links
                    self.bookmarkedItems = Set(bookmarkedItems)
                    
                    // If currently viewing bookmarked feed, refresh it
                    if case .bookmarks = self.currentFeedType {
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
        StorageManager.shared.load(forKey: "heartedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let heartedItems):
                DispatchQueue.main.async {
                    // Update cached hearted links
                    self.heartedItems = Set(heartedItems)
                    
                    // If currently viewing hearted feed, refresh it
                    if case .heart = self.currentFeedType {
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
    
    @objc private func handleSortOrderChanged(_ notification: Notification) {
        // Restore the sort order from UserDefaults
        restoreSortOrder()
        
        // Apply the sort order to the current items
        sortItems(ascending: isSortedAscending)
    }
    
    @objc private func handleFeedFoldersUpdated(_ notification: Notification) {
        // If we're currently viewing a folder feed, refresh it
        // since the folder contents might have changed
        if case .folder(let folderId) = currentFeedType {
            // Get the folder from storage
            StorageManager.shared.getFolders { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let folders) = result,
                       let folder = folders.first(where: { $0.id == folderId }) {
                        // Update currentFolder
                        self.currentFolder = folder
                        
                        // Only reload if the folder feedURLs have changed
                        if self.currentFolder?.feedURLs != folder.feedURLs {
                            // Reload folder feeds
                            self.loadFolderFeeds(folder: folder)
                        }
                    }
                }
            }
        }
    }
    
    @objc private func handleShowReadArticlesChanged(_ notification: Notification) {
        // Reload feeds based on the current view
        switch currentFeedType {
        case .rss:
            // For RSS feeds, we need to refresh the current items shown based on the setting
            updateTableViewContent()
        case .folder(let folderId):
            // For folder views, also refresh
            if let folder = currentFolder, folder.id == folderId {
                loadFolderFeeds(folder: folder)
            }
        default:
            // For other views (bookmarks, heart), we don't filter by read status
            // so no need to refresh
            break
        }
    }
    
    // MARK: - Trait Changes
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setupNavigationBar()
            tableView.backgroundColor = AppColors.background
            tableView.reloadData()
        }
    }
    
    // Handle KVO for table view content size changes
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "contentSize", let tableView = object as? UITableView {
            // When content size changes, check if we need to refresh the footer
            if case .rss = currentFeedType, tableView.tableFooterView == nil {
                refreshFooterView()
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        tableView.removeObserver(self, forKeyPath: "contentSize")
    }
}