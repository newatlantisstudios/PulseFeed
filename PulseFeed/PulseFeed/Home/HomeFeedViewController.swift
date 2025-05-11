import SafariServices
import UIKit

// MARK: - HomeFeedViewController
class HomeFeedViewController: UIViewController, CALayerDelegate {
    
    // MARK: - Theme Handling
    
    @objc func appThemeChanged(_ notification: Notification) {
        // Update UI elements with new theme colors
        view.backgroundColor = AppColors.background
        tableView.backgroundColor = AppColors.background
        tableView.separatorColor = AppColors.secondary.withAlphaComponent(0.3)
        
        // Refresh navigation and UI 
        setupNavigationBar()
        tableView.reloadData()
        
        // Update loading indicator colors if visible
        loadingLabel.textColor = AppColors.secondary
    }
    
    // MARK: - Feed Refresh
    
    @objc func refreshFeeds() {
        // Hide tableView and show loading indicator during refresh
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        startRefreshAnimation() // Start animation
        
        // Reset the scroll position tracker to ensure we start at the top after refresh
        previousMinVisibleRow = 0
        
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
            
        case .smartFolder(let folderId):
            // For smart folder view, refresh the current smart folder
            if let folder = currentSmartFolder, folder.id == folderId {
                // Load the smart folder contents
                loadSmartFolderContents(folder: folder)
            } else {
                // Smart folder not loaded yet, load it first
                StorageManager.shared.getSmartFolders { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        if case .success(let folders) = result,
                           let folder = folders.first(where: { $0.id == folderId }) {
                            self.currentSmartFolder = folder
                            // Load the smart folder contents
                            self.loadSmartFolderContents(folder: folder)
                        } else {
                            // Smart folder not found, fall back to all feeds
                            self.loadRSSFeeds()
                        }
                    }
                }
            }
            
        case .bookmarks:
            // For bookmarks feed type, go back to standard behavior
            loadRSSFeeds()
            
        case .heart:
            // For hearted feed type, go back to standard behavior  
            loadRSSFeeds()
            
        case .archive:
            // For archive feed, load archived articles
            loadArchivedFeeds()
        }
    }
    
    // MARK: - Loading Methods
    
    /// Loads the archived items feed
    func loadArchivedFeeds() {
        // Set the title
        self.title = "Archive"
        
        // Hide table and show loading
        isLoading = true
        print("DEBUG: isLoading set to true in loadArchivedFeeds start")
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        loadingLabel.text = "Loading archived articles..."
        loadingLabel.isHidden = false
        
        // If no items are archived, show empty message and return
        if archivedItems.isEmpty {
            items = []
            tableView.reloadData()
            
            // Update UI
            loadingLabel.text = "No archived articles"
            loadingLabel.isHidden = false
            loadingIndicator.stopAnimating()
            tableView.isHidden = false
            isLoading = false
            print("DEBUG: isLoading set to false in loadArchivedFeeds (no archived items)")
            return
        }
        
        // If we already have items loaded, just filter and display
        if !_allItems.isEmpty {
            // Filter to show only archived items
            let filteredItems = _allItems.filter { item in
                let normalizedLink = normalizeLink(item.link)
                return archivedItems.contains { normalizeLink($0) == normalizedLink }
            }
            
            // Update UI
            items = filteredItems
            tableView.reloadData()
            tableView.isHidden = false
            loadingIndicator.stopAnimating()
            loadingLabel.isHidden = filteredItems.isEmpty ? false : true
            
            if filteredItems.isEmpty {
                loadingLabel.text = "No archived articles"
            }
            isLoading = false
            print("DEBUG: isLoading set to false in loadArchivedFeeds (filtered items)")
        } else {
            // If no items are loaded yet, load main RSS feeds first
            loadRSSFeeds()
        }
    }
    
    // Helper to complete the loading process with the filtered items
    func completeLoadingWithItems(_ filteredItems: [RSSItem]) {
        // If full-text extraction is enabled, attempt to extract content for partial feeds
        if FullTextExtractor.shared.isEnabled {
            // Show loading message for full-text extraction
            DispatchQueue.main.async {
                self.loadingLabel.text = "Extracting full content for partial feeds..."
            }
            
            // Process items with FullTextExtractor
            FullTextExtractor.shared.extractFullContentForItems(filteredItems) { [weak self] updatedItems in
                guard let self = self else { return }
                
                // Continue with the regular flow
                self.finalizeItemLoading(updatedItems)
            }
        } else {
            // Skip full-text extraction and continue with the regular flow
            finalizeItemLoading(filteredItems)
        }
    }
    
    // Helper to finalize loading process after full-text extraction (if any)
    func finalizeItemLoading(_ filteredItems: [RSSItem]) {
        // Safety check for empty arrays
        guard !filteredItems.isEmpty else {
            // Handle empty items case directly on the current (presumably main) thread
            self._allItems = []
            self.items = []
            self.duplicateGroups = []
            self.duplicateArticleLinks = []

            // Reset read tracking state to prevent unwanted auto-marking
            self.pendingReadRows.removeAll()
            self.isAutoScrolling = true
            self.previousMinVisibleRow = 0
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.processReadItemsAfterScrolling), object: nil)

            self.tableView.reloadData() // Reload first
            self.refreshControl.endRefreshing()
            self.loadingIndicator.stopAnimating()
            print("DEBUG: loadingIndicator.stopAnimating() in finalizeItemLoading (empty)")
            self.loadingLabel.text = "No articles found"
            self.loadingLabel.isHidden = false
            print("DEBUG: loadingLabel.isHidden set to false in finalizeItemLoading (empty)")
            // Only show the table if there are items or if explicitly showing a no-articles state
            self.tableView.isHidden = !self.items.isEmpty ? false : true
            print("DEBUG: tableView.isHidden set to \(self.tableView.isHidden) in finalizeItemLoading (empty)")
            self.isLoading = false
            self.stopRefreshAnimation()

            // Reset auto-scrolling flag after a delay
            // This still needs to be async as it's a delayed action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isAutoScrolling = false
            }
            return
        }

        // Update our data source
        self._allItems = filteredItems

        // Set read status for all items
        for i in 0..<self._allItems.count {
            self._allItems[i].isRead = ReadStatusTracker.shared.isArticleRead(link: self._allItems[i].link)
        }

        // Detect duplicates if enabled
        self.detectDuplicates()

        // Update the currently displayed items if RSS feed is active
        if case .rss = self.currentFeedType {
            // First check if we need to filter out read articles
            let hideReadArticles = UserDefaults.standard.bool(forKey: "hideReadArticles")

            // Apply read status filtering if needed
            var readFilteredItems = self._allItems
            if hideReadArticles {
                readFilteredItems = self._allItems.filter { !ReadStatusTracker.shared.isArticleRead(link: $0.link) }
                print("DEBUG: Read status filtered \(self._allItems.count) items to \(readFilteredItems.count) items")
            }

            // Then apply advanced filtering and sorting
            self.items = FeedFilterManagerNew.shared.applySortAndFilter(to: readFilteredItems)

            // Apply duplicate handling according to user settings
            if DuplicateManager.shared.isDuplicateDetectionEnabled {
                self.items = DuplicateManager.shared.processItems(self.items)
            }

            // Update the sort/filter view with the current settings if it exists
            if let sortFilterView = self.sortFilterView {
                sortFilterView.setSortOption(FeedFilterManagerNew.shared.getSortOption())
                sortFilterView.setFilterOption(FeedFilterManagerNew.shared.getFilterOption())
            }

            // Log counts for debugging
            print("DEBUG: Applied sorting and filtering: \(self._allItems.count) items to \(self.items.count) items")
            print("DEBUG: Found \(self.duplicateGroups.count) duplicate groups with \(self.duplicateArticleLinks.count) articles")
        }

        // Reset read tracking state to prevent unwanted auto-marking
        self.pendingReadRows.removeAll()
        self.isAutoScrolling = true
        self.previousMinVisibleRow = 0
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.processReadItemsAfterScrolling), object: nil)

        // Reload the table with new data
        self.tableView.reloadData()

        // Update UI state immediately after reloadData()
        self.refreshControl.endRefreshing()
        self.loadingIndicator.stopAnimating()
        print("DEBUG: loadingIndicator.stopAnimating() in finalizeItemLoading (non-empty)")
        self.loadingLabel.isHidden = true
        print("DEBUG: loadingLabel.isHidden set to true in finalizeItemLoading (non-empty)")
        // Only show the table if there are items
        self.tableView.isHidden = self.items.isEmpty
        print("DEBUG: tableView.isHidden set to \(self.tableView.isHidden) in finalizeItemLoading (non-empty)")
        self.isLoading = false
        self.stopRefreshAnimation() // Ensure this is also done before showing table
        self.hasLoadedRSSFeeds = true
        self.updateFooterVisibility()


        // Perform actions that can be delayed (like scrolling) after a brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // Short delay for UI to settle if needed
            // Scroll to top of the list safely and reset auto-scrolling flag after a delay
            self.safeScrollToTop()

            // Reset auto-scrolling flag after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // This is a nested delay, consider if it's still needed or can be combined.
                self.isAutoScrolling = false
            }
        }
    }
    
    // MARK: - CALayerDelegate
    func layoutSublayers(of layer: CALayer) {
        // This is called when the layer's bounds change
        // Update any gradient layers to fit their containing views
        if let gradientLayer = layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = layer.bounds
        }
    }
    
    // MARK: - Safe Scroll To Top
    
    /// Scrolls the table view to the top without marking articles as read
    internal func safeScrollToTop() {
        // Only proceed if there are items and the table is visible
        guard !items.isEmpty && !tableView.isHidden else { return }

        // Set the auto-scrolling flag to prevent marking articles as read
        isAutoScrolling = true

        // Reset any pending read operations
        pendingReadRows.removeAll()

        // Reset the previous min visible row to prevent issues when auto-scrolling is disabled
        previousMinVisibleRow = 0

        // Cancel any scheduled process read operations
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(processReadItemsAfterScrolling), object: nil)

        // Perform the scroll
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)

        // Reset the flag after a delay that's longer than the animation duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isAutoScrolling = false
        }
    }
    
    // MARK: - Keyboard Navigation Methods
    
    /// Simply call safeScrollToTop for keyboard shortcut compatibility
    @objc func scrollToTop() {
        safeScrollToTop()
    }
    
    /// Navigate to the next item in the feed
    @objc func navigateToNextItem() {
        guard !items.isEmpty && !tableView.isHidden else { return }

        // Get the currently visible rows
        guard let visibleRows = tableView.indexPathsForVisibleRows, let firstVisible = visibleRows.min() else {
            return
        }

        // Calculate the next row, ensuring we don't go beyond the bounds
        let nextRow = min(firstVisible.row + 1, items.count - 1)
        let nextIndexPath = IndexPath(row: nextRow, section: 0)

        // Reset any pending read operations
        pendingReadRows.removeAll()

        // Cancel any scheduled process read operations
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(processReadItemsAfterScrolling), object: nil)

        // Scroll to the next item
        isAutoScrolling = true
        tableView.scrollToRow(at: nextIndexPath, at: .top, animated: true)

        // Update tracker to prevent any pending item marking
        previousMinVisibleRow = nextRow

        // Reset the flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isAutoScrolling = false
        }

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Navigate to the previous item in the feed
    @objc func navigateToPreviousItem() {
        guard !items.isEmpty && !tableView.isHidden else { return }

        // Get the currently visible rows
        guard let visibleRows = tableView.indexPathsForVisibleRows, let firstVisible = visibleRows.min() else {
            return
        }

        // Calculate the previous row, ensuring we don't go below zero
        let prevRow = max(firstVisible.row - 1, 0)
        let prevIndexPath = IndexPath(row: prevRow, section: 0)

        // Reset any pending read operations
        pendingReadRows.removeAll()

        // Cancel any scheduled process read operations
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(processReadItemsAfterScrolling), object: nil)

        // Scroll to the previous item
        isAutoScrolling = true
        tableView.scrollToRow(at: prevIndexPath, at: .top, animated: true)

        // Update tracker to prevent any pending item marking
        previousMinVisibleRow = prevRow

        // Reset the flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isAutoScrolling = false
        }

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    /// Open the currently selected item
    @objc func openSelectedItem() {
        guard !items.isEmpty && !tableView.isHidden else { return }
        
        // Get the currently visible rows
        guard let visibleRows = tableView.indexPathsForVisibleRows, let firstVisible = visibleRows.min() else {
            return
        }
        
        // Simulate a tap on the first visible row
        tableView(tableView, didSelectRowAt: firstVisible)
    }
    
    /// Toggle bookmark status for the currently visible item
    @objc func toggleBookmark() {
        guard !items.isEmpty && !tableView.isHidden else { return }
        
        // Get the currently visible rows
        guard let visibleRows = tableView.indexPathsForVisibleRows, let firstVisible = visibleRows.min() else {
            return
        }
        
        // Toggle bookmark for the first visible item
        let item = items[firstVisible.row]
        toggleBookmark(for: item) {
            self.tableView.reloadRows(at: [firstVisible], with: .none)
        }
        
        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    /// Toggle favorite status for the currently visible item
    @objc func toggleFavorite() {
        guard !items.isEmpty && !tableView.isHidden else { return }
        
        // Get the currently visible rows
        guard let visibleRows = tableView.indexPathsForVisibleRows, let firstVisible = visibleRows.min() else {
            return
        }
        
        // Toggle favorite for the first visible item
        let item = items[firstVisible.row]
        toggleHeart(for: item) {
            self.tableView.reloadRows(at: [firstVisible], with: .none)
        }
        
        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    /// Toggle read status for the currently visible item
    @objc func toggleReadStatus() {
        guard !items.isEmpty && !tableView.isHidden else { return }
        
        // Get the currently visible rows
        guard let visibleRows = tableView.indexPathsForVisibleRows, let firstVisible = visibleRows.min() else {
            return
        }
        
        // Toggle read status for the first visible item
        let item = items[firstVisible.row]
        toggleReadStatus(for: item) {
            self.tableView.reloadRows(at: [firstVisible], with: .none)
        }
        
        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    /// Show the search interface
    @objc func showSearch() {
        // Check if we have a search button in the navigation bar
        if let searchButton = navigationItem.rightBarButtonItems?.first {
            // Just trigger the action - likely to be search in this context
            perform(searchButton.action)
        } else {
            // If no search function is available, show toast
            let toast = UIAlertController(title: "Search", message: "Search functionality will be available soon", preferredStyle: .alert)
            toast.addAction(UIAlertAction(title: "OK", style: .default))
            present(toast, animated: true)
        }
    }
    

    // MARK: - Properties
    
    // Data
    internal var items: [RSSItem] = []
    internal var _allItems: [RSSItem] = []
    var readLinks: Set<String> = [] // Store normalized read links
    internal var heartedItems: Set<String> = []
    internal var bookmarkedItems: Set<String> = []
    internal var archivedItems: Set<String> = [] // Track which articles are archived
    internal var cachedArticleLinks: Set<String> = [] // Track which articles are cached for offline reading
    internal var hasLoadedRSSFeeds = false
    internal var isSortedAscending: Bool = false // State for sorting order
    internal var isOfflineMode = false // Track if we're in offline mode
    internal var filterKeywords: [String] = [] // Keywords used to filter articles
    internal var isContentFilteringEnabled: Bool = false // Whether content filtering is enabled
    internal var originalItemsBeforeSearch: [RSSItem] = [] // Stores original items during search
    
    // Sort & Filter view
    internal var sortFilterView: SortFilterView?
    
    // Bulk editing mode
    internal var isBulkEditMode: Bool = false
    internal var originalRightBarButtonItems: [UIBarButtonItem]?
    internal var isCachingCancelled: Bool = false // Flag to cancel bulk caching operations
    internal var selectedItems: Set<Int> = []
    internal var bulkEditToolbar: UIToolbar?
    
    // Duplicate article tracking
    internal var duplicateGroups: [DuplicateArticleGroup] = []
    internal var duplicateArticleLinks: Set<String> = [] // Links that are part of a duplicate group
    
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
    var archiveButton: UIBarButtonItem?
    var folderButton: UIBarButtonItem?
    var settingsButton: UIBarButtonItem?
    
    // Timer for refresh operations
    internal var refreshTimeoutTimer: Timer?
    
    // Timer for automatic refresh based on intervals
    internal var autoRefreshTimer: Timer?
    
    // Configuration - always use enhanced style
    internal var useEnhancedStyle: Bool {
        return true
    }
    
    // Feed types
    enum FeedType {
        case rss, bookmarks, heart, archive, folder(id: String), smartFolder(id: String)
        
        var displayName: String {
            switch self {
            case .rss: return "All Feeds"
            case .bookmarks: return "Bookmarks"
            case .heart: return "Favorites"
            case .archive: return "Archive"
            case .folder: return "Folder"
            case .smartFolder: return "Smart Folder"
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
    
    // Current smart folder if any
    var currentSmartFolder: SmartFolder?
    
    // Property to access allItems
    var allItems: [RSSItem] {
        get { return _allItems }
        set { _allItems = newValue }
    }
    
    // Variable to track rows to mark as read after scrolling stops
    internal var pendingReadRows: [Int] = []
    
    // Flag to prevent marking articles as read during programmatic scrolling
    internal var isAutoScrolling: Bool = false
    
    // Track if articles are currently being loaded
    internal var isLoading: Bool = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(fontSizeChanged(_:)), name: Notification.Name("fontSizeChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appThemeChanged(_:)), name: Notification.Name("appThemeChanged"), object: nil)
        
        // Setup UI elements
        setupLoadingIndicator()
        setupRefreshControl()
        setupTableView()
        // Temporarily commented out until SortFilterView is properly implemented
        // setupSortFilterView()
        
        // Setup automatic refresh timer
        setupAutoRefreshTimer()
    }
    
    // Stub implementation to be properly implemented later
    func setupSortFilterView() {
        // This is a temporary stub implementation
        print("SortFilterView setup will be implemented in a future update")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Ensure navigation bar is correctly configured
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.prefersLargeTitles = false
        setupNavigationBar()
        setupNotificationObserver()
        setupLongPressGesture()
        setupSwipeGestures()
        
        // Only do initial loading if we haven't loaded feeds yet
        if !hasLoadedRSSFeeds {
            // Hide tableView initially until articles are loaded
            tableView.isHidden = true
            loadingIndicator.startAnimating()
            
            // Start the animation immediately
            startRefreshAnimation()
            
            // Load feeds (only on first appearance)
            loadRSSFeeds()
        } else {
            // If we're returning from another view, just ensure UI is updated
            // without reloading all feeds
            updateNavigationButtons()
            
            // Make sure the table is visible
            tableView.isHidden = false
            loadingIndicator.stopAnimating()
            
            // Ensure refresh animation is stopped when returning from article
            stopRefreshAnimation()
        }

        // Load cached data
        loadCachedData()
        
        // Restore sort order
        restoreSortOrder()
        
        // Update offline status
        updateOfflineStatus()
        
        // Load filter settings
        loadFilterSettings()
        
        // If we're returning from an article, update read status safely
        // But don't call updateReadState() directly to avoid lockups
        if hasLoadedRSSFeeds {
            // First make sure we have read links loaded
            StorageManager.shared.load(forKey: "readItems") { [weak self] (result: Result<[String], Error>) in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let readItems) = result {
                        // Update cached read links safely
                        self.readLinks = Set(readItems.map { StorageManager.shared.normalizeLink($0) })
                        
                        // Only reload the table - don't try to update all items yet
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // If the tableView is still hidden, make sure the refresh icon is spinning
        if tableView.isHidden {
            startRefreshAnimation()
        }
        
        // Become first responder to capture keyboard events
        becomeFirstResponder()
        
        // No need to call refreshFeeds() here since we're handling initial loading in viewWillAppear
        // Just ensure the UI is properly updated when returning from another view
        
        if hasLoadedRSSFeeds {
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
        
        // Load archived items
        StorageManager.shared.load(forKey: "archivedItems") {
            (result: Result<[String], Error>) in
            if case .success(let items) = result {
                DispatchQueue.main.async {
                    self.archivedItems = Set(items)
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
    
    // MARK: - Offline Caching
    
    /// Caches an article for offline reading
    /// - Parameters:
    ///   - item: The RSSItem to cache
    ///   - completion: Callback with success status
    func cacheArticleForOfflineReading(_ item: RSSItem, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: item.link) else {
            completion(false)
            return
        }
        
        // Create a loading indicator to show progress
        let loadingAlert = UIAlertController(
            title: "Saving Article",
            message: "Downloading article content for offline reading...",
            preferredStyle: .alert
        )
        
        // Add activity indicator
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        
        loadingAlert.view.addSubview(indicator)
        
        // Position indicator in alert
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
            indicator.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -20)
        ])
        
        // Present the loading alert
        present(loadingAlert, animated: true)
        
        // Use ContentExtractor to grab the article content
        let content = ContentExtractor.extractReadableContent(from: "", url: url)
        
        // Cache the article with the extracted content
        StorageManager.shared.cacheArticleContent(
            link: item.link,
            content: content,
            title: item.title,
            source: item.source
        ) { success, error in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    // Show success/failure message
                    let title = success ? "Article Saved" : "Save Failed"
                    let message = success ?
                        "The article has been saved for offline reading." :
                        "Could not save the article. Please try again."
                    
                    let alert = UIAlertController(
                        title: title,
                        message: message,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
                
                // Call completion handler with result
                completion(success)
            }
        }
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
    
    /// Shows the smart folder feed with the given SmartFolder
    func showSmartFolderFeed(folder: SmartFolder) {
        // Store the current smart folder
        currentSmartFolder = folder
        
        // Set the feed type to smart folder
        if case .smartFolder(let id) = currentFeedType, id == folder.id {
            // Already showing this smart folder - do nothing
        } else {
            currentFeedType = .smartFolder(id: folder.id)
            
            // Load contents in this smart folder
            loadSmartFolderContents(folder: folder)
        }
    }
    
    /// Loads and displays the contents of a smart folder based on its rules
    func loadSmartFolderContents(folder: SmartFolder) {
        // Start loading animation
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        loadingLabel.text = "Loading smart folder..."
        loadingLabel.isHidden = false
        startRefreshAnimation()
        
        // Reset the scroll position tracker
        previousMinVisibleRow = 0
        
        // Create a dispatch group for concurrent operations
        let group = DispatchGroup()
        
        // First, make sure we have a full list of articles from all feeds
        if !_allItems.isEmpty {
            // If we already have items loaded, use them
            print("DEBUG: Using \(_allItems.count) previously loaded articles")
        } else {
            // If we don't have any articles loaded yet, we need to load all feeds first
            group.enter()
            StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
                guard let self = self else {
                    group.leave()
                    return
                }
                
                switch result {
                case .success(let feeds):
                    // Start a nested group for fetching all feeds
                    let feedsGroup = DispatchGroup()
                    var allFeedItems: [RSSItem] = []
                    
                    for feed in feeds {
                        feedsGroup.enter()
                        // Use loadArticlesForFeed from HomeFeedViewController+UI.swift
                        self.loadArticlesForFeed(feed) { items in
                            allFeedItems.append(contentsOf: items)
                            feedsGroup.leave()
                        }
                    }
                    
                    feedsGroup.notify(queue: .main) {
                        // Update _allItems with all the articles we loaded
                        self._allItems = allFeedItems
                        group.leave()
                    }
                    
                case .failure(let error):
                    print("ERROR: Failed to load feeds for smart folder: \(error.localizedDescription)")
                    // Use an empty array as fallback
                    self._allItems = []
                    group.leave()
                }
            }
        }
        
        // When all feeds are loaded, filter items based on smart folder rules
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // Update loading message
            self.loadingLabel.text = "Filtering articles based on smart folder rules..."
            
            // Apply the smart folder rules to filter articles
            self.filterArticlesForSmartFolder(folder) { filteredItems in
                // Apply read status filtering if needed
                let hideReadArticles = UserDefaults.standard.bool(forKey: "hideReadArticles")
                var readFilteredItems = filteredItems
                
                if hideReadArticles {
                    readFilteredItems = filteredItems.filter { !ReadStatusTracker.shared.isArticleRead(link: $0.link) }
                    print("DEBUG: Read status filtered \(filteredItems.count) items to \(readFilteredItems.count) items")
                }
                
                // Then apply keyword filtering if enabled
                var keywordFilteredItems: [RSSItem]
                if self.isContentFilteringEnabled && !self.filterKeywords.isEmpty {
                    // Filter out articles that match any of the filter keywords
                    keywordFilteredItems = readFilteredItems.filter { !self.shouldFilterArticle($0) }
                    print("DEBUG: Keyword filtered \(readFilteredItems.count) items to \(keywordFilteredItems.count) items")
                } else {
                    // No keyword filtering
                    keywordFilteredItems = readFilteredItems
                }
                
                // Sort the filtered items
                self.sortFilteredItems(&keywordFilteredItems)
                
                // Update the UI
                DispatchQueue.main.async {
                    self.items = keywordFilteredItems
                    self.tableView.reloadData()
                    
                    // Update UI elements
                    self.tableView.isHidden = false
                    self.loadingIndicator.stopAnimating()
                    self.loadingLabel.isHidden = true
                    self.stopRefreshAnimation()
                    self.refreshControl.endRefreshing()
                    self.updateFooterVisibility()
                    
                    // Scroll to top safely
                    self.safeScrollToTop()
                    
                    // Log results
                    print("DEBUG: Smart folder \(folder.name) loaded with \(keywordFilteredItems.count) articles")
                    
                    // Show message if no articles were found
                    if keywordFilteredItems.isEmpty {
                        self.loadingLabel.text = "No articles found matching this smart folder's rules"
                        self.loadingLabel.isHidden = false
                        
                        // Hide the message after a few seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.loadingLabel.isHidden = true
                        }
                    }
                }
            }
        }
    }
    
    /// Filters articles based on smart folder rules
    private func filterArticlesForSmartFolder(_ folder: SmartFolder, completion: @escaping ([RSSItem]) -> Void) {
        // Create a dispatch group to handle asynchronous rule evaluation
        let group = DispatchGroup()
        let itemsToEvaluate = self._allItems
        var matchingItems: [RSSItem] = []
        
        // Add debug logging for smart folder rules
        print("DEBUG: Starting article filtering for smart folder \(folder.name)")
        print("DEBUG: Smart folder has \(folder.rules.count) rules")
        print("DEBUG: Smart folder match mode: \(folder.matchMode)")
        for (index, rule) in folder.rules.enumerated() {
            print("DEBUG: Rule \(index): \(rule.field) \(rule.operation) '\(rule.value)'")
        }
        print("DEBUG: Total articles to evaluate: \(itemsToEvaluate.count)")
        
        // Check if any rules look for title contains "Andor"
        let hasAndorRule = folder.rules.contains { rule in
            return rule.field == .title && 
                   rule.operation == .contains && 
                   rule.value.lowercased().contains("andor")
        }
        
        if hasAndorRule {
            print("DEBUG: Found rule looking for 'Andor' in title - checking all article titles:")
            for article in itemsToEvaluate {
                if article.title.lowercased().contains("andor") {
                    print("DEBUG: FOUND ARTICLE WITH ANDOR: \(article.title)")
                }
            }
        }
        
        // Process each article to see if it matches the smart folder rules
        for item in itemsToEvaluate {
            group.enter()
            folder.matchesArticle(item) { matches in
                if matches {
                    // If this article matched, log it for debugging
                    print("DEBUG: Article matched: \"\(item.title)\"")
                    matchingItems.append(item)
                } else if hasAndorRule && item.title.lowercased().contains("andor") {
                    // Special debugging for Andor case
                    print("DEBUG: ANDOR ARTICLE DID NOT MATCH RULES: \(item.title)")
                    
                    // Manually evaluate each rule for this article to see which ones are failing
                    let evaluationGroup = DispatchGroup()
                    var ruleResults: [String] = []
                    
                    for (index, rule) in folder.rules.enumerated() {
                        evaluationGroup.enter()
                        if rule.field == .title {
                            // Direct evaluation for title rules
                            let normalizedValue = item.title.lowercased()
                            let normalizedRuleValue = rule.value.lowercased()
                            
                            var result = false
                            if rule.operation == .contains {
                                result = normalizedValue.contains(normalizedRuleValue)
                            } else if rule.operation == .notContains {
                                result = !normalizedValue.contains(normalizedRuleValue)
                            } else if rule.operation == .equals {
                                result = normalizedValue == normalizedRuleValue
                            } else if rule.operation == .notEquals {
                                result = normalizedValue != normalizedRuleValue
                            } else if rule.operation == .beginsWith {
                                result = normalizedValue.hasPrefix(normalizedRuleValue)
                            } else if rule.operation == .endsWith {
                                result = normalizedValue.hasSuffix(normalizedRuleValue)
                            }
                            
                            ruleResults.append("Rule \(index) (\(rule.field) \(rule.operation) '\(rule.value)'): \(result)")
                            evaluationGroup.leave()
                        } else {
                            // For other rules, let the standard evaluation handle it
                            evaluationGroup.leave()
                        }
                    }
                    
                    evaluationGroup.notify(queue: .main) {
                        print("DEBUG: Rule evaluation results for '\(item.title)':")
                        for result in ruleResults {
                            print("DEBUG: \(result)")
                        }
                    }
                }
                group.leave()
            }
        }
        
        // When all evaluations are complete, return the matching items
        group.notify(queue: .main) {
            print("DEBUG: Smart folder evaluation complete, found \(matchingItems.count) matching articles")
            completion(matchingItems)
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
    
    @objc private func handleFullTextExtractionChanged() {
        // When full-text extraction setting changes, refresh feeds to apply the new setting
        if hasLoadedRSSFeeds {
            // If already loaded, just clear the FullTextExtractor cache
            FullTextExtractor.shared.clearCache()
            
            // Display a message to let the user know they need to refresh for the change to take effect
            let alert = UIAlertController(
                title: "Setting Changed",
                message: "The full-text extraction setting has been updated. Refresh feeds to apply this change.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Refresh Now", style: .default) { [weak self] _ in
                self?.refreshFeeds()
            })
            alert.addAction(UIAlertAction(title: "Later", style: .cancel))
            present(alert, animated: true)
        }
    }
    
    @objc private func handleRefreshIntervalSettingsChanged() {
        // When refresh interval settings change, restart the auto-refresh timer
        DispatchQueue.main.async { [weak self] in
            self?.setupAutoRefreshTimer()
        }
    }
    
    private func setupNotificationObserver() {
        // Add observers for various notification events
        let notifications: [(name: Notification.Name, selector: Selector)] = [
            (.init("readItemsReset"), #selector(handleReadItemsReset)),
            (.init("readItemsUpdated"), #selector(handleReadItemsUpdated)),
            (.init("bookmarkedItemsUpdated"), #selector(handleBookmarkedItemsUpdated)),
            (.init("heartedItemsUpdated"), #selector(handleHeartedItemsUpdated)),
            (.init("archivedItemsUpdated"), #selector(handleArchivedItemsUpdated)),
            (.init("articleSortOrderChanged"), #selector(handleSortOrderChanged)),
            (.init("feedFoldersUpdated"), #selector(handleFeedFoldersUpdated)),
            (.init("smartFoldersUpdated"), #selector(handleSmartFoldersUpdated)),
            (.init("hideReadArticlesChanged"), #selector(handleHideReadArticlesChanged)),
            (DuplicateManager.duplicateSettingsChangedNotification, #selector(handleDuplicateSettingsChanged)),
            (.init("contentFilteringChanged"), #selector(handleContentFilteringChanged)),
            (.init("fullTextExtractionChanged"), #selector(handleFullTextExtractionChanged)),
            (.init("refreshIntervalSettingsChanged"), #selector(handleRefreshIntervalSettingsChanged)),
            // Add tag-related notifications
            (.init("tagsUpdated"), #selector(handleTagsUpdated)),
            (.init("taggedItemsUpdated"), #selector(handleTaggedItemsUpdated))
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
    
    // MARK: - Swipe Gestures
    
    private func setupSwipeGestures() {
        // Setup swipe gestures to navigate between feed types
        SwipeGestureManager.shared.addFeedNavigationGestures(
            to: self,
            leftAction: { [weak self] in
                self?.navigateToNextFeedType()
            },
            rightAction: { [weak self] in
                self?.navigateToPreviousFeedType()
            }
        )
    }
    
    @objc func handleFeedSwipe(_ gesture: UISwipeGestureRecognizer) {
        // This method will be called by the SwipeGestureManager
        // Action is handled via closures set in setupSwipeGestures
    }
    
    private func navigateToNextFeedType() {
        // Progress to the next feed type
        switch currentFeedType {
        case .rss:
            // From main feed -> bookmarks
            if !bookmarkedItems.isEmpty {
                currentFeedType = .bookmarks
                loadBookmarkedFeeds()
            } else {
                // Skip to favorites if no bookmarks
                if !heartedItems.isEmpty {
                    currentFeedType = .heart
                    loadHeartedFeeds()
                } else if !archivedItems.isEmpty {
                    // Skip to archive if no favorites
                    currentFeedType = .archive
                    updateTableViewContent()
                } else {
                    // Skip to folders if available
                    StorageManager.shared.getFolders { [weak self] result in
                        guard let self = self else { return }
                        
                        DispatchQueue.main.async {
                            if case .success(let folders) = result, !folders.isEmpty {
                                // Switch to first folder
                                self.currentFeedType = .folder(id: folders[0].id)
                                self.currentFolder = folders[0]
                                self.loadFolderFeeds(folder: folders[0])
                            } else {
                                // No other feeds to switch to - stay on RSS
                                self.showToast(message: "No other feed types available")
                            }
                        }
                    }
                }
            }
            
        case .bookmarks:
            // From bookmarks -> favorites
            if !heartedItems.isEmpty {
                currentFeedType = .heart
                loadHeartedFeeds()
            } else {
                // Skip to folders if available
                StorageManager.shared.getFolders { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        if case .success(let folders) = result, !folders.isEmpty {
                            // Switch to first folder
                            self.currentFeedType = .folder(id: folders[0].id)
                            self.currentFolder = folders[0]
                            self.loadFolderFeeds(folder: folders[0])
                        } else {
                            // Loop back to RSS feed
                            self.currentFeedType = .rss
                            self.updateTableViewContent()
                        }
                    }
                }
            }
            
        case .heart:
            // From favorites -> archive if available
            if !archivedItems.isEmpty {
                currentFeedType = .archive
                updateTableViewContent()
            } else {
                // Skip to folders if available
                StorageManager.shared.getFolders { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        if case .success(let folders) = result, !folders.isEmpty {
                            // Switch to first folder
                            self.currentFeedType = .folder(id: folders[0].id)
                            self.currentFolder = folders[0]
                            self.loadFolderFeeds(folder: folders[0])
                        } else {
                            // Loop back to RSS feed
                            self.currentFeedType = .rss
                            self.updateTableViewContent()
                        }
                    }
                }
            }
            
        case .archive:
            // From archive -> folders if available
            StorageManager.shared.getFolders { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let folders) = result, !folders.isEmpty {
                        // Switch to first folder
                        self.currentFeedType = .folder(id: folders[0].id)
                        self.currentFolder = folders[0]
                        self.loadFolderFeeds(folder: folders[0])
                    } else {
                        // Loop back to RSS feed
                        self.currentFeedType = .rss
                        self.updateTableViewContent()
                    }
                }
            }
            
        case .folder(let currentFolderId):
            // From folder -> next folder or back to RSS
            StorageManager.shared.getFolders { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let folders) = result {
                        // Find current folder index
                        if let currentIndex = folders.firstIndex(where: { $0.id == currentFolderId }) {
                            if currentIndex < folders.count - 1 {
                                // Move to next folder
                                let nextFolder = folders[currentIndex + 1]
                                self.currentFeedType = .folder(id: nextFolder.id)
                                self.currentFolder = nextFolder
                                self.loadFolderFeeds(folder: nextFolder)
                            } else {
                                // Check if we have smart folders to navigate to
                                StorageManager.shared.getSmartFolders { [weak self] result in
                                    guard let self = self else { return }
                                    
                                    DispatchQueue.main.async {
                                        if case .success(let smartFolders) = result, !smartFolders.isEmpty {
                                            // Move to first smart folder
                                            let firstSmartFolder = smartFolders[0]
                                            self.currentFeedType = .smartFolder(id: firstSmartFolder.id)
                                            self.currentSmartFolder = firstSmartFolder
                                            self.loadSmartFolderContents(folder: firstSmartFolder)
                                        } else {
                                            // Loop back to RSS feed
                                            self.currentFeedType = .rss
                                            self.updateTableViewContent()
                                        }
                                    }
                                }
                            }
                        } else {
                            // Current folder not found, go back to RSS
                            self.currentFeedType = .rss
                            self.updateTableViewContent()
                        }
                    } else {
                        // Error getting folders, go back to RSS
                        self.currentFeedType = .rss
                        self.updateTableViewContent()
                    }
                }
            }
            
        case .smartFolder(let currentFolderId):
            // From smart folder -> next smart folder or back to RSS
            StorageManager.shared.getSmartFolders { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let folders) = result {
                        // Find current folder index
                        if let currentIndex = folders.firstIndex(where: { $0.id == currentFolderId }) {
                            if currentIndex < folders.count - 1 {
                                // Move to next smart folder
                                let nextFolder = folders[currentIndex + 1]
                                self.currentFeedType = .smartFolder(id: nextFolder.id)
                                self.currentSmartFolder = nextFolder
                                self.loadSmartFolderContents(folder: nextFolder)
                            } else {
                                // Loop back to RSS feed
                                self.currentFeedType = .rss
                                self.updateTableViewContent()
                            }
                        } else {
                            // Current smart folder not found, go back to RSS
                            self.currentFeedType = .rss
                            self.updateTableViewContent()
                        }
                    } else {
                        // Error getting smart folders, go back to RSS
                        self.currentFeedType = .rss
                        self.updateTableViewContent()
                    }
                }
            }
        }
        
        // Show haptic feedback for feed change
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
    }
    
    private func navigateToPreviousFeedType() {
        // Move to the previous feed type
        switch currentFeedType {
        case .rss, .bookmarks, .heart, .archive, .folder, .smartFolder:
            // From RSS, go to the last feed type (last smart folder, last folder, heart, or bookmarks)
            // First check for smart folders
            StorageManager.shared.getSmartFolders { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let smartFolders) = result, !smartFolders.isEmpty {
                        // Go to last smart folder
                        let lastSmartFolder = smartFolders.last!
                        self.currentFeedType = .smartFolder(id: lastSmartFolder.id)
                        self.currentSmartFolder = lastSmartFolder
                        self.loadSmartFolderContents(folder: lastSmartFolder)
                    } else {
                        // No smart folders, check for regular folders
                        StorageManager.shared.getFolders { [weak self] result in
                            guard let self = self else { return }
                            
                            DispatchQueue.main.async {
                                if case .success(let folders) = result, !folders.isEmpty {
                                    // Go to last folder
                                    let lastFolder = folders.last!
                                    self.currentFeedType = .folder(id: lastFolder.id)
                                    self.currentFolder = lastFolder
                                    self.loadFolderFeeds(folder: lastFolder)
                                } else if !self.heartedItems.isEmpty {
                                    // No folders, go to favorites
                                    self.currentFeedType = .heart
                                    self.loadHeartedFeeds()
                                } else if !self.bookmarkedItems.isEmpty {
                                    // No favorites, go to bookmarks
                                    self.currentFeedType = .bookmarks
                                    self.loadBookmarkedFeeds()
                                } else {
                                    // No other feeds to go to - stay on RSS
                                    self.showToast(message: "No other feed types available")
                                }
                            }
                        }
                    }
                }
            }
            
        case .bookmarks:
            // From bookmarks -> RSS
            currentFeedType = .rss
            updateTableViewContent()
            
        case .heart:
            // From favorites -> bookmarks or RSS
            if !bookmarkedItems.isEmpty {
                currentFeedType = .bookmarks
                loadBookmarkedFeeds()
            } else {
                currentFeedType = .rss
                updateTableViewContent()
            }
            
        case .folder(let currentFolderId):
            // From folder -> previous folder or heart or bookmarks or RSS
            StorageManager.shared.getFolders { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let folders) = result {
                        // Find current folder index
                        if let currentIndex = folders.firstIndex(where: { $0.id == currentFolderId }) {
                            if currentIndex > 0 {
                                // Move to previous folder
                                let prevFolder = folders[currentIndex - 1]
                                self.currentFeedType = .folder(id: prevFolder.id)
                                self.currentFolder = prevFolder
                                self.loadFolderFeeds(folder: prevFolder)
                            } else {
                                // We're at first folder, go to favorites if available
                                if !self.heartedItems.isEmpty {
                                    self.currentFeedType = .heart
                                    self.loadHeartedFeeds()
                                } else if !self.bookmarkedItems.isEmpty {
                                    // No favorites, go to bookmarks
                                    self.currentFeedType = .bookmarks
                                    self.loadBookmarkedFeeds()
                                } else {
                                    // No other feeds, go to RSS
                                    self.currentFeedType = .rss
                                    self.updateTableViewContent()
                                }
                            }
                        } else {
                            // Current folder not found, go to heart or bookmarks or RSS
                            if !self.heartedItems.isEmpty {
                                self.currentFeedType = .heart
                                self.loadHeartedFeeds()
                            } else if !self.bookmarkedItems.isEmpty {
                                self.currentFeedType = .bookmarks
                                self.loadBookmarkedFeeds()
                            } else {
                                self.currentFeedType = .rss
                                self.updateTableViewContent()
                            }
                        }
                    } else {
                        // Error getting folders, try heart or bookmarks or RSS
                        if !self.heartedItems.isEmpty {
                            self.currentFeedType = .heart
                            self.loadHeartedFeeds()
                        } else if !self.bookmarkedItems.isEmpty {
                            self.currentFeedType = .bookmarks
                            self.loadBookmarkedFeeds()
                        } else {
                            self.currentFeedType = .rss
                            self.updateTableViewContent()
                        }
                    }
                }
            }
            
        case .smartFolder(let currentFolderId):
            // From smart folder -> previous smart folder or regular folder or heart or bookmarks or RSS
            StorageManager.shared.getSmartFolders { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let folders) = result {
                        // Find current folder index
                        if let currentIndex = folders.firstIndex(where: { $0.id == currentFolderId }) {
                            if currentIndex > 0 {
                                // Move to previous smart folder
                                let prevFolder = folders[currentIndex - 1]
                                self.currentFeedType = .smartFolder(id: prevFolder.id)
                                self.currentSmartFolder = prevFolder
                                self.loadSmartFolderContents(folder: prevFolder)
                            } else {
                                // We're at the first smart folder, check for regular folders
                                StorageManager.shared.getFolders { [weak self] result in
                                    guard let self = self else { return }
                                    
                                    DispatchQueue.main.async {
                                        if case .success(let regularFolders) = result, !regularFolders.isEmpty {
                                            // Go to last regular folder
                                            let lastFolder = regularFolders.last!
                                            self.currentFeedType = .folder(id: lastFolder.id)
                                            self.currentFolder = lastFolder
                                            self.loadFolderFeeds(folder: lastFolder)
                                        } else if !self.heartedItems.isEmpty {
                                            // No regular folders, go to favorites
                                            self.currentFeedType = .heart
                                            self.loadHeartedFeeds()
                                        } else if !self.bookmarkedItems.isEmpty {
                                            // No favorites, go to bookmarks
                                            self.currentFeedType = .bookmarks
                                            self.loadBookmarkedFeeds()
                                        } else {
                                            // No other feeds, go to RSS
                                            self.currentFeedType = .rss
                                            self.updateTableViewContent()
                                        }
                                    }
                                }
                            }
                        } else {
                            // Current smart folder not found, check for regular folders
                            StorageManager.shared.getFolders { [weak self] result in
                                guard let self = self else { return }
                                
                                DispatchQueue.main.async {
                                    if case .success(let regularFolders) = result, !regularFolders.isEmpty {
                                        // Go to last regular folder
                                        let lastFolder = regularFolders.last!
                                        self.currentFeedType = .folder(id: lastFolder.id)
                                        self.currentFolder = lastFolder
                                        self.loadFolderFeeds(folder: lastFolder)
                                    } else if !self.heartedItems.isEmpty {
                                        // No regular folders, go to favorites
                                        self.currentFeedType = .heart
                                        self.loadHeartedFeeds()
                                    } else if !self.bookmarkedItems.isEmpty {
                                        // No favorites, go to bookmarks
                                        self.currentFeedType = .bookmarks
                                        self.loadBookmarkedFeeds()
                                    } else {
                                        // No other feeds, go to RSS
                                        self.currentFeedType = .rss
                                        self.updateTableViewContent()
                                    }
                                }
                            }
                        }
                    } else {
                        // Error getting smart folders, try regular folders
                        StorageManager.shared.getFolders { [weak self] result in
                            guard let self = self else { return }
                            
                            DispatchQueue.main.async {
                                if case .success(let regularFolders) = result, !regularFolders.isEmpty {
                                    // Go to last regular folder
                                    let lastFolder = regularFolders.last!
                                    self.currentFeedType = .folder(id: lastFolder.id)
                                    self.currentFolder = lastFolder
                                    self.loadFolderFeeds(folder: lastFolder)
                                } else if !self.heartedItems.isEmpty {
                                    // No regular folders, go to favorites
                                    self.currentFeedType = .heart
                                    self.loadHeartedFeeds()
                                } else if !self.bookmarkedItems.isEmpty {
                                    // No favorites, go to bookmarks
                                    self.currentFeedType = .bookmarks
                                    self.loadBookmarkedFeeds()
                                } else {
                                    // No other feeds, go to RSS
                                    self.currentFeedType = .rss
                                    self.updateTableViewContent()
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Show haptic feedback for feed change
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
    }
    
    // Show a toast message
    func showToast(message: String) {
        let toastLabel = UILabel(frame: CGRect(x: view.frame.width/2 - 150, y: view.frame.height - 200, width: 300, height: 35))
        toastLabel.backgroundColor = AppColors.primary.withAlphaComponent(0.9)
        toastLabel.textColor = UIColor.white
        toastLabel.textAlignment = .center
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10
        toastLabel.clipsToBounds = true
        toastLabel.font = .systemFont(ofSize: 14)
        
        view.addSubview(toastLabel)
        
        UIView.animate(withDuration: 2.0, delay: 0.1, options: .curveEaseInOut, animations: {
            toastLabel.alpha = 0.0
        }, completion: { _ in
            toastLabel.removeFromSuperview()
        })
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
    
    /// Mark all items above a specific index path as read
    /// - Parameter indexPath: The index path that was long-pressed
    internal func markItemsAboveAsRead(_ indexPath: IndexPath) {
        // Collect all links from items above the tapped row
        let linksToMark = (0...indexPath.row).map { items[$0].link }
        
        // Mark them all as read in ReadStatusTracker
        ReadStatusTracker.shared.markArticles(links: linksToMark, as: true)
        
        // Update the local items array
        for index in 0...indexPath.row {
            items[index].isRead = true
        }
        
        // Reload the affected rows
        let indexPaths = (0...indexPath.row).map { IndexPath(row: $0, section: 0) }
        tableView.reloadRows(at: indexPaths, with: .fade)
    }
    
    private var saveReadStateWorkItem: DispatchWorkItem?
    private let saveReadStateDebounceInterval: TimeInterval = 1.5
    
    // Debounced save for read state
    func scheduleSaveReadState() {
        saveReadStateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            // Collect read items from current visible items
            guard let self = self else { return }
            
            // Collect all links from read items
            var readItemLinks: [String] = []
            
            // Add all read items from the current view
            for item in self.items where item.isRead {
                readItemLinks.append(item.link)
            }
            
            // Also include any read items from allItems that may not be in the current view
            for item in self._allItems where item.isRead {
                readItemLinks.append(item.link)
            }
            
            // Use the ReadStatusTracker to mark these articles as read
            ReadStatusTracker.shared.markArticles(links: readItemLinks, as: true)
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
    
    @objc private func handleArchivedItemsUpdated() {
        StorageManager.shared.load(forKey: "archivedItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let archivedItems):
                DispatchQueue.main.async {
                    // Update cached archived links
                    self.archivedItems = Set(archivedItems)
                    
                    // If currently viewing archived feed, refresh it
                    if case .archive = self.currentFeedType {
                        // Reload the current view to refresh archive content
                        self.updateTableViewContent()
                    } else {
                        // Otherwise just reload the table to update swipe actions
                        self.tableView.reloadData()
                    }
                }
            case .failure(let error):
                print("ERROR: Failed to load updated archived items: \(error.localizedDescription)")
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
    
    @objc private func handleSmartFoldersUpdated(_ notification: Notification) {
        // If we're currently viewing a smart folder feed, refresh it
        // since the folder rules might have changed
        if case .smartFolder(let folderId) = currentFeedType {
            // Get the smart folder from storage
            StorageManager.shared.getSmartFolders { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if case .success(let folders) = result,
                       let folder = folders.first(where: { $0.id == folderId }) {
                        // Update currentSmartFolder
                        self.currentSmartFolder = folder
                        
                        // Reload smart folder contents
                        self.loadSmartFolderContents(folder: folder)
                        
                        print("DEBUG: Refreshed smart folder \(folder.name) after update notification")
                    }
                }
            }
        }
    }
    
    @objc private func handleHideReadArticlesChanged(_ notification: Notification) {
        // Apply a fade animation to show the user that the list is being filtered
        UIView.animate(withDuration: 0.3, animations: {
            self.tableView.alpha = 0.5
        }) { _ in
            // Reload feeds based on the current view
            switch self.currentFeedType {
            case .rss:
                // For RSS feeds, we need to refresh the current items shown based on the setting
                self.updateTableViewContent()
            case .folder(let folderId):
                // For folder views, also refresh
                if let folder = self.currentFolder, folder.id == folderId {
                    self.loadFolderFeeds(folder: folder)
                }
            case .smartFolder(let folderId):
                // For smart folder views, also refresh
                if let folder = self.currentSmartFolder, folder.id == folderId {
                    self.loadSmartFolderContents(folder: folder)
                }
            case .bookmarks, .heart, .archive:
                // For these views, even though we don't typically filter by read status
                // we'll still refresh in case the user wants this behavior everywhere
                self.updateTableViewContent()
            }
            
            // Fade the table view back in
            UIView.animate(withDuration: 0.3) {
                self.tableView.alpha = 1.0
            }
        }
        
        // Show a brief confirmation toast when the setting changes
        let hideReadArticles = UserDefaults.standard.bool(forKey: "hideReadArticles")
        let message = hideReadArticles ? "Read articles are now hidden" : "All articles are now shown"
        self.showToast(message: message)
    }
    
    @objc private func handleTagsUpdated(_ notification: Notification) {
        // When tags themselves are updated (added, modified, or deleted)
        // We need to refresh the table to show the updated tags
        print("DEBUG: Tags updated notification received")
        
        // First, clear any cached tag data
        StorageManager.shared.clearTagCache()
        
        DispatchQueue.main.async {
            // Force a full table reload with animation to ensure changes are visible
            print("DEBUG: Forcing complete table reload due to tag updates")
            UIView.transition(with: self.tableView, 
                          duration: 0.3,
                          options: .transitionCrossDissolve,
                          animations: { self.tableView.reloadData() },
                          completion: nil)
        }
    }
    
    @objc private func handleTaggedItemsUpdated(_ notification: Notification) {
        // When items are tagged or untagged, we need to refresh the relevant cells
        if let itemId = notification.userInfo?["itemId"] as? String {
            // Print debug information
            print("DEBUG: Tagged item updated notification received for item: \(itemId)")
            if let tagId = notification.userInfo?["tagId"] as? String {
                print("DEBUG: Tag ID: \(tagId)")
            }
            
            DispatchQueue.main.async {
                // Find the cells that need updating
                let matchingIndices = self.items.enumerated()
                    .filter { $0.element.link == itemId || StorageManager.shared.normalizeLink($0.element.link) == itemId }
                
                // Print debug information
                print("DEBUG: Found \(matchingIndices.count) matching item(s) in the table")
                for match in matchingIndices {
                    print("DEBUG: Match at index \(match.offset): \(match.element.title)")
                }
                
                let indexPathsToReload = matchingIndices.map { IndexPath(row: $0.offset, section: 0) }
                
                if !indexPathsToReload.isEmpty {
                    print("DEBUG: Reloading specific rows: \(indexPathsToReload)")
                    // Force reload with animation to ensure the update is visible
                    self.tableView.reloadRows(at: indexPathsToReload, with: .fade)
                } else {
                    // If we can't find the specific cells, just reload all (less efficient but ensures UI is up to date)
                    print("DEBUG: No matching rows found, reloading entire table")
                    self.tableView.reloadData()
                }
            }
        } else {
            // No specific item ID, reload all cells
            print("DEBUG: Tagged item updated notification received without item ID")
            DispatchQueue.main.async {
                self.tableView.reloadData()
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
    
    // MARK: - Automatic Refresh
    
    /// Sets up the timer for automatic refresh based on configured intervals
    private func setupAutoRefreshTimer() {
        // Stop any existing timer
        stopAutoRefreshTimer()
        
        // Create a new timer that checks for feeds to refresh every minute
        autoRefreshTimer = Timer.scheduledTimer(
            timeInterval: 60, // Check every minute
            target: self,
            selector: #selector(checkFeedsForAutoRefresh),
            userInfo: nil,
            repeats: true
        )
        
        // Add to run loop to ensure it runs when scrolling
        RunLoop.current.add(autoRefreshTimer!, forMode: .common)
        
        // Run once immediately
        checkFeedsForAutoRefresh()
    }
    
    /// Stops the automatic refresh timer
    private func stopAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }
    
    /// Checks if any feeds are due for refresh based on their intervals
    @objc private func checkFeedsForAutoRefresh() {
        // Skip if offline or a refresh is already in progress
        if isOfflineMode || tableView.isHidden || loadingIndicator.isAnimating {
            return
        }
        
        // Only check when showing the main feed or a folder
        switch currentFeedType {
        case .rss, .folder:
            // Continue with checks
            break
        default:
            // Skip for other feed types
            return
        }
        
        // Load all feeds to check their refresh status
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let feeds):
                var feedsToRefresh: [RSSFeed] = []
                
                // Find feeds that are due for refresh
                for feed in feeds {
                    if RefreshIntervalManager.shared.shouldRefreshFeed(feed) {
                        feedsToRefresh.append(feed)
                    }
                }
                
                // If any feeds need refresh, trigger a refresh
                if !feedsToRefresh.isEmpty {
                    print("DEBUG: Auto-refreshing \(feedsToRefresh.count) feeds")
                    
                    // Record refresh time for all feeds being refreshed
                    for feed in feedsToRefresh {
                        RefreshIntervalManager.shared.recordRefresh(forFeed: feed.url)
                    }
                    
                    // Perform the refresh on the main thread
                    DispatchQueue.main.async {
                        self.refreshFeeds()
                    }
                }
                
            case .failure(let error):
                print("ERROR: Failed to load feeds for auto-refresh check: \(error.localizedDescription)")
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        tableView.removeObserver(self, forKeyPath: "contentSize")
        stopAutoRefreshTimer()
    }
    
    // MARK: - Keyboard Shortcuts Support
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var keyCommands: [UIKeyCommand]? {
        // Keyboard shortcuts temporarily disabled
        return []
    }
    
    // Keyboard shortcuts handling moved to the main viewDidAppear
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Resign first responder when leaving the view
        resignFirstResponder()
    }
    
    /// Keyboard shortcut help temporarily disabled
    @objc func showKeyboardShortcutHelp() {
        // Keyboard shortcuts disabled
    }
}