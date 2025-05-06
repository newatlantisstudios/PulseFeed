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
    internal var hasLoadedRSSFeeds = false
    internal var isSortedAscending: Bool = false // State for sorting order
    
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
    
    private func setupNotificationObserver() {
        // Add observers for various notification events
        let notifications: [(name: Notification.Name, selector: Selector)] = [
            (.init("readItemsReset"), #selector(handleReadItemsReset)),
            (.init("readItemsUpdated"), #selector(handleReadItemsUpdated)),
            (.init("bookmarkedItemsUpdated"), #selector(handleBookmarkedItemsUpdated)),
            (.init("heartedItemsUpdated"), #selector(handleHeartedItemsUpdated)),
            (.init("articleSortOrderChanged"), #selector(handleSortOrderChanged)),
            (.init("feedFoldersUpdated"), #selector(handleFeedFoldersUpdated))
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