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
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

    guard let date = dateFormatter.date(from: dateString) else {
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
    private var heartedItems: Set<String> = []
    private var bookmarkedItems: Set<String> = []
    private var allItems: [RSSItem] = []
    private var hasLoadedRSSFeeds = false

    // Feed types; RSSFeed is managed separately.
    private enum FeedType {
        case rss, bookmarks, heart
    }
    private var currentFeedType: FeedType = .rss {
        didSet {
            updateNavigationButtons()
            updateTableViewContent()
        }
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLoadingIndicator()
        setupRefreshControl()
        setupNavigationBar()
        setupTableView()
        setupScrollViewDelegate()
        setupNotificationObserver()
        setupLongPressGesture()
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

    }

    private func setupLoadingIndicator() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.center = view.center
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
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
    }

    private func setupScrollViewDelegate() {
        tableView.delegate = self
    }

    private func setupLongPressGesture() {
        longPressGesture = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPressGesture)
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

    private func markItemsAboveAsRead(_ indexPath: IndexPath) {
        for index in 0...indexPath.row {
            items[index].isRead = true
        }
        saveReadState()
        let indexPaths = (0...indexPath.row).map {
            IndexPath(row: $0, section: 0)
        }
        tableView.reloadRows(at: indexPaths, with: .fade)
    }

    @objc private func handleReadItemsReset() {
        loadRSSFeeds()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Updating Content Based on Feed Type
    private func updateTableViewContent() {
        switch currentFeedType {
        case .rss:
            if !hasLoadedRSSFeeds {
                items.removeAll()
                loadRSSFeeds()
            } else {
                // Use the cached items from the initial load.
                items = allItems
                tableView.reloadData()
            }
        case .bookmarks:
            loadBookmarkedFeeds()
        case .heart:
            loadHeartedFeeds()
        }
        updateFooterVisibility()
    }

    // Load RSS feeds from storage and then fetch articles from each feed URL.
    private func loadRSSFeeds() {
        loadingIndicator.startAnimating()
        self.view.bringSubviewToFront(loadingIndicator)

        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            switch result {
            case .success(let feeds):
                print("DEBUG: Loaded RSS Feeds:")
                feeds.forEach { feed in
                    print("DEBUG: Feed Title: \(feed.title), URL: \(feed.url), Last Updated: \(feed.lastUpdated)")
                }

                let allFeeds = feeds

                // Load read items as [ReadItem] and extract links.
                StorageManager.shared.load(forKey: "readItems") { (readResult: Result<[ReadItem], Error>) in
                    var readLinks: [String] = []
                    if case .success(let readItems) = readResult {
                        readLinks = readItems.map { $0.link }
                        print("DEBUG: Loaded read links: \(readLinks)")
                    }

                    let dispatchGroup = DispatchGroup()
                    var liveItems: [RSSItem] = []

                    feeds.forEach { feed in
                        guard let url = URL(string: feed.url) else { return }
                        dispatchGroup.enter()

                        let startTime = Date()
                        let task = URLSession.shared.dataTask(with: url) { data, response, error in
                            let elapsedTime = Date().timeIntervalSince(startTime)
                            DispatchQueue.main.async {
                                if elapsedTime >= 45 {
                                    FeedLoadTimeManager.shared.loadTimes[feed.title] = -1
                                } else {
                                    FeedLoadTimeManager.shared.loadTimes[feed.title] = elapsedTime
                                }
                            }
                            defer { dispatchGroup.leave() }

                            if elapsedTime >= 45 {
                                print("DEBUG: Feed '\(feed.title)' skipped due to load time: \(elapsedTime) seconds")
                                return
                            }

                            guard let data = data, error == nil else {
                                print("DEBUG: Error fetching RSS feed: \(error?.localizedDescription ?? "Unknown error")")
                                return
                            }

                            let parser = XMLParser(data: data)
                            let rssParser = RSSParser(source: feed.title)
                            parser.delegate = rssParser
                            if parser.parse() {
                                let itemsFromFeed = rssParser.items
                                let filteredItems = itemsFromFeed.filter { !readLinks.contains($0.link) }
                                print("DEBUG: Feed '\(feed.title)' - fetched \(itemsFromFeed.count) items, filtered to \(filteredItems.count)")
                                liveItems.append(contentsOf: filteredItems)
                            }
                        }
                        task.resume()
                    }

                    dispatchGroup.notify(queue: .main) {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

                        // Sort live items by publication date.
                        let sortedItems = liveItems.sorted { item1, item2 in
                            guard let date1 = dateFormatter.date(from: item1.pubDate),
                                  let date2 = dateFormatter.date(from: item2.pubDate) else { return false }
                            return date1 > date2
                        }

                        // Save all fetched items so they can be later filtered by bookmarks/heart.
                        self.allItems = sortedItems

                        // For RSS feed type, display all items.
                        self.items = self.allItems

                        print("DEBUG: Total live items after filtering: \(self.items.count)")

                        if self.items.isEmpty {
                            self.footerRefreshButton?.setTitle("  No More Articles  ", for: .normal)
                            self.footerRefreshButton?.isEnabled = false
                        } else {
                            self.footerRefreshButton?.setTitle("  Refresh Feed  ", for: .normal)
                            self.footerRefreshButton?.isEnabled = true
                        }

                        if let markAllButton = self.tableView.tableFooterView?.subviews.first as? UIButton {
                            markAllButton.setTitle(self.items.isEmpty ? "  Reached the end  " : "  Mark All as Read  ", for: .normal)
                            markAllButton.isEnabled = !self.items.isEmpty
                        }

                        // Save live articles per feed into CloudKit.
                        let groupedByFeed = Dictionary(grouping: self.items, by: { $0.source })
                        for (feedId, articles) in groupedByFeed {
                            let summaries = articles.map { article in
                                ArticleSummary(title: article.title, link: article.link, pubDate: article.pubDate)
                            }
                            CloudKitStorage().saveArticles(forFeed: feedId, articles: summaries) { error in
                                if let error = error {
                                    print("Error saving articles for feed \(feedId): \(error.localizedDescription)")
                                } else {
                                    print("Successfully saved live articles for feed \(feedId)")
                                }
                            }
                        }

                        // For each feed, load cached articles and merge them with live articles.
                        for feed in allFeeds {
                            CloudKitStorage().loadArticles(forFeed: feed.title) { result in
                                switch result {
                                case .success(let cachedArticles):
                                    let unreadCachedArticles = cachedArticles.filter { !readLinks.contains($0.link) }
                                    let liveArticles = self.items.filter { $0.source == feed.title }
                                    var mergedArticles = liveArticles
                                    for cached in unreadCachedArticles {
                                        if !mergedArticles.contains(where: { $0.link == cached.link }) {
                                            let rssItem = RSSItem(title: cached.title, link: cached.link, pubDate: cached.pubDate, source: feed.title, isRead: false)
                                            mergedArticles.append(rssItem)
                                        }
                                    }
                                    self.items.removeAll { $0.source == feed.title }
                                    self.items.append(contentsOf: mergedArticles)

                                    let readCachedArticles = cachedArticles.filter { readLinks.contains($0.link) }
                                    if !readCachedArticles.isEmpty {
                                        let updatedCachedArticles = cachedArticles.filter { !readLinks.contains($0.link) }
                                        CloudKitStorage().saveArticles(forFeed: feed.title, articles: updatedCachedArticles) { error in
                                            if let error = error {
                                                print("Error updating cached articles for feed \(feed.title): \(error.localizedDescription)")
                                            } else {
                                                print("Updated cached articles for feed \(feed.title)")
                                            }
                                        }
                                    }
                                case .failure(let error):
                                    print("Error loading cached articles for feed \(feed.title): \(error.localizedDescription)")
                                }
                                DispatchQueue.main.async {
                                    self.items.sort { item1, item2 in
                                        guard let date1 = dateFormatter.date(from: item1.pubDate),
                                              let date2 = dateFormatter.date(from: item2.pubDate) else { return false }
                                        return date1 > date2
                                    }
                                    self.tableView.reloadData()
                                }
                            }
                        }

                        self.hasLoadedRSSFeeds = true

                        self.tableView.reloadData()
                        self.refreshControl.endRefreshing()
                        self.updateFooterVisibility()
                        self.loadingIndicator.stopAnimating()
                    }
                }
            case .failure(let error):
                print("DEBUG: Error loading rssFeeds: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.refreshControl.endRefreshing()
                    self.loadingIndicator.stopAnimating()
                }
            }
        }
    }

    // New implementation for loading bookmarked feeds
    private func loadBookmarkedFeeds() {
        // Filter the complete list based on bookmarked links.
        self.items = self.allItems.filter {
            self.bookmarkedItems.contains($0.link)
        }
        tableView.reloadData()
    }

    // New implementation for loading hearted feeds
    private func loadHeartedFeeds() {
        // Filter the complete list based on hearted links.
        self.items = self.allItems.filter {
            self.heartedItems.contains($0.link)
        }
        tableView.reloadData()
    }

    // MARK: - Data Loading and Saving

    // Save read state using asynchronous storage
    private func saveReadState() {
        StorageManager.shared.load(forKey: "readItems") {
            [weak self] (result: Result<[ReadItem], Error>) in
            guard let self = self else { return }
            var existingReadItems: [ReadItem] = []
            if case .success(let items) = result {
                existingReadItems = items
            }

            // Map new read items with current date.
            let newReadItems = self.items.filter { $0.isRead }.map {
                ReadItem(link: $0.link, readDate: Date())
            }
            existingReadItems.append(contentsOf: newReadItems)

            // Deduplicate: Keep the latest readDate for each link.
            var uniqueItems = [String: ReadItem]()
            for item in existingReadItems {
                if let existing = uniqueItems[item.link] {
                    uniqueItems[item.link] =
                        item.readDate > existing.readDate ? item : existing
                } else {
                    uniqueItems[item.link] = item
                }
            }
            let dedupedItems = Array(uniqueItems.values)

            // Cleanup items: Remove those older than 30 days and enforce a max count.
            let cleanedItems = self.cleanupReadItems(
                dedupedItems, maxAge: 30 * 24 * 60 * 60, maxCount: 5000)

            StorageManager.shared.save(cleanedItems, forKey: "readItems") {
                error in
                if let error = error {
                    print(
                        "Error saving cleaned read items: \(error.localizedDescription)"
                    )
                } else {
                    print("Successfully saved cleaned read items.")
                }
            }
        }
    }

    private func cleanupReadItems(
        _ items: [ReadItem], maxAge: TimeInterval, maxCount: Int
    ) -> [ReadItem] {
        // Remove items older than maxAge (e.g., 30 days)
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        var filteredItems = items.filter { $0.readDate >= cutoffDate }

        // If the list still exceeds the max count, keep only the most recent ones.
        if filteredItems.count > maxCount {
            filteredItems.sort { $0.readDate > $1.readDate }
            filteredItems = Array(filteredItems.prefix(maxCount))
        }

        return filteredItems
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
        appearance.backgroundColor = AppColors.primary

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        appearance.titleTextAttributes = titleAttributes
        appearance.largeTitleTextAttributes = titleAttributes

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationController?.navigationBar.compactScrollEdgeAppearance =
                appearance
        }
        setupNavigationButtons()
    }

    private func setupNavigationButtons() {
        let leftButtons = [
            createBarButton(
                imageName: "rss", action: #selector(rssButtonTapped)),
            createBarButton(
                imageName: "bookmark", action: #selector(bookmarkButtonTapped)),
            createBarButton(
                imageName: "heart", action: #selector(heartButtonTapped)),
        ]

        let rightButtons = [
            createBarButton(
                imageName: "settings", action: #selector(openSettings)),
            createBarButton(
                imageName: "edit", action: #selector(editButtonTapped)),
        ]

        navigationItem.leftBarButtonItems = leftButtons
        navigationItem.rightBarButtonItems = rightButtons
        updateNavigationButtons()
    }

    private func updateNavigationButtons() {
        guard let leftButtons = navigationItem.leftBarButtonItems else {
            return
        }
        leftButtons[0].image = resizeImage(
            UIImage(named: "rss"), targetSize: CGSize(width: 24, height: 24))?
            .withRenderingMode(.alwaysTemplate)
        leftButtons[1].image = resizeImage(
            UIImage(named: "bookmark"),
            targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(
                .alwaysTemplate)
        leftButtons[2].image = resizeImage(
            UIImage(named: "heart"), targetSize: CGSize(width: 24, height: 24))?
            .withRenderingMode(.alwaysTemplate)

        switch currentFeedType {
        case .rss:
            leftButtons[0].image = resizeImage(
                UIImage(named: "rssFilled"),
                targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(
                    .alwaysTemplate)
        case .bookmarks:
            leftButtons[1].image = resizeImage(
                UIImage(named: "bookmarkFilled"),
                targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(
                    .alwaysTemplate)
        case .heart:
            leftButtons[2].image = resizeImage(
                UIImage(named: "heartFilled"),
                targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(
                    .alwaysTemplate)
        }
    }

    private func createBarButton(imageName: String, action: Selector)
        -> UIBarButtonItem
    {
        let button = UIBarButtonItem(
            image: resizeImage(
                UIImage(named: imageName),
                targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(
                    .alwaysTemplate),
            style: .plain,
            target: self,
            action: action)
        button.tintColor = .white
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
        markAllButton.setTitle(
            items.isEmpty ? "  Reached the end  " : "  Mark All as Read  ",
            for: .normal)
        markAllButton.isEnabled = !items.isEmpty
        markAllButton.setTitleColor(.white, for: .normal)
        markAllButton.titleLabel?.font = .systemFont(
            ofSize: 16, weight: .semibold)
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
            if footerView == nil {
                setupTableViewFooter()
            }
            tableView.tableFooterView = footerView
        }
    }

    @objc private func markAllAsReadTapped() {
        let alert = UIAlertController(
            title: "Mark All as Read",
            message: "Are you sure you want to mark all articles as read?",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Mark All", style: .default) { [weak self] _ in
                self?.markAllItemsAsRead()
            })
        present(alert, animated: true)
    }

    private func markAllItemsAsRead() {
        for index in 0..<items.count {
            items[index].isRead = true
        }
        saveReadState()
        items.removeAll()
        loadRSSFeeds()
    }

    @objc private func refreshButtonTapped() {
        footerLoadingIndicator?.startAnimating()
        footerRefreshButton?.setTitle("  Loading...  ", for: .normal)
        footerRefreshButton?.isEnabled = false
        refreshFeeds()
    }

    @objc private func refreshFeeds() {
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
}

// MARK: - TableView Delegate and DataSource
extension HomeFeedViewController: UITableViewDelegate, UITableViewDataSource {

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

        // Configure Heart Action using local state
        let isHearted = heartedItems.contains(item.link)
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

        // Configure Bookmark Action using local state
        let isBookmarked = bookmarkedItems.contains(item.link)
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

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
        -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "RSSCell", for: indexPath)
        let item = items[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText =
            "\(item.source) • \(getTimeAgo(from: item.pubDate))"
        cell.backgroundColor = AppColors.background
        config.textProperties.color =
            item.isRead ? AppColors.secondary : AppColors.accent
        config.secondaryTextProperties.color = AppColors.secondary
        config.secondaryTextProperties.font = .systemFont(ofSize: 12)
        config.textProperties.font = .systemFont(
            ofSize: 16, weight: item.isRead ? .regular : .medium)
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
            saveReadState()

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
        if heartedItems.contains(item.link) {
            heartedItems.remove(item.link)
        } else {
            heartedItems.insert(item.link)
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
        if bookmarkedItems.contains(item.link) {
            bookmarkedItems.remove(item.link)
        } else {
            bookmarkedItems.insert(item.link)
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
