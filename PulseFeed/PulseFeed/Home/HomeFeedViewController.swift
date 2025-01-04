private func getTimeAgo(from dateString: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    
    guard let date = dateFormatter.date(from: dateString) else { return dateString }
    
    let now = Date()
    let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
    
    if let days = components.day, days > 0 {
        return "\(days)d ago"
    } else if let hours = components.hour, hours > 0 {
        return "\(hours)h ago"
    } else if let minutes = components.minute, minutes > 0 {
        return "\(minutes)m ago"
    }
    return "just now"
}

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

enum AppColors {
    static var primary: UIColor {
        UIColor(hex: "121212")  // Dark background
    }
    
    static var secondary: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
            UIColor(hex: "9E9E9E") : UIColor(hex: "757575")
        }
    }
    
    static var accent: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
            UIColor(hex: "FFFFFF") : UIColor(hex: "1A1A1A")
        }
    }
    
    static var background: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
            UIColor(hex: "1E1E1E") : UIColor(hex: "F5F5F5")
        }
    }
}

// Add UIColor extension for hex colors
extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex)
        scanner.scanLocation = 0
        
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        
        let r = (rgbValue & 0xff0000) >> 16
        let g = (rgbValue & 0xff00) >> 8
        let b = rgbValue & 0xff
        
        self.init(red: CGFloat(r) / 0xff, green: CGFloat(g) / 0xff, blue: CGFloat(b) / 0xff, alpha: 1)
    }
}

import UIKit
import SafariServices

class HomeFeedViewController: UIViewController {
    private var items: [RSSItem] = []
    private let tableView = UITableView()
    private let refreshControl = UIRefreshControl()
    private var longPressGesture: UILongPressGestureRecognizer!
    
    private var footerLoadingIndicator: UIActivityIndicatorView?
    private var footerRefreshButton: UIButton?
    private var isShowingBookmarks = false
    private var footerView: UIView?
    
    private enum FeedType {
        case rss
        case bookmarks
        case heart
    }
    private var currentFeedType: FeedType = .rss {
        didSet {
            updateNavigationButtons()
            updateTableViewContent()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupRefreshControl()
        setupNavigationBar()
        setupTableView()
        setupScrollViewDelegate()
        setupNotificationObserver()
        setupLongPressGesture()
        loadRSSFeeds()
    }
    
    private func setupRefreshControl() {
        refreshControl.addTarget(self, action: #selector(refreshFeeds), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReadItemsReset),
            name: Notification.Name("readItemsReset"),
            object: nil
        )
    }
    
    private func updateTableViewContent() {
        switch currentFeedType {
        case .rss:
            items.removeAll()
            loadRSSFeeds()
            
        case .bookmarks:
            let bookmarkedLinks = UserDefaults.standard.stringArray(forKey: "bookmarkedItems") ?? []
            // Get all RSS items that are bookmarked
            guard let data = UserDefaults.standard.data(forKey: "rssFeeds"),
                  let feeds = try? JSONDecoder().decode([RSSFeed].self, from: data) else {
                items.removeAll()
                tableView.reloadData()
                return
            }
            
            items.removeAll()
            let dispatchGroup = DispatchGroup()
            
            feeds.forEach { feed in
                dispatchGroup.enter()
                
                guard let url = URL(string: feed.url) else {
                    dispatchGroup.leave()
                    return
                }
                
                let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                    defer { dispatchGroup.leave() }
                    
                    guard let data = data,
                          error == nil else { return }
                    
                    let parser = XMLParser(data: data)
                    let rssParser = RSSParser(source: feed.title)
                    parser.delegate = rssParser
                    
                    if parser.parse() {
                        let filteredItems = rssParser.items.filter { bookmarkedLinks.contains($0.link) }
                        self?.items.append(contentsOf: filteredItems)
                    }
                }
                task.resume()
            }
            
            dispatchGroup.notify(queue: .main) { [weak self] in
                self?.sortItemsByDate()
                self?.tableView.reloadData()
            }
            
        case .heart:
            let heartedLinks = UserDefaults.standard.stringArray(forKey: "heartedItems") ?? []
            // Get all RSS items that are hearted
            guard let data = UserDefaults.standard.data(forKey: "rssFeeds"),
                  let feeds = try? JSONDecoder().decode([RSSFeed].self, from: data) else {
                items.removeAll()
                tableView.reloadData()
                return
            }
            
            items.removeAll()
            let dispatchGroup = DispatchGroup()
            
            feeds.forEach { feed in
                dispatchGroup.enter()
                
                guard let url = URL(string: feed.url) else {
                    dispatchGroup.leave()
                    return
                }
                
                let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                    defer { dispatchGroup.leave() }
                    
                    guard let data = data,
                          error == nil else { return }
                    
                    let parser = XMLParser(data: data)
                    let rssParser = RSSParser(source: feed.title)
                    parser.delegate = rssParser
                    
                    if parser.parse() {
                        let filteredItems = rssParser.items.filter { heartedLinks.contains($0.link) }
                        self?.items.append(contentsOf: filteredItems)
                    }
                }
                task.resume()
            }
            
            dispatchGroup.notify(queue: .main) { [weak self] in
                self?.sortItemsByDate()
                self?.tableView.reloadData()
            }
        }
        
        updateFooterVisibility()
    }
    
    private func sortItemsByDate() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        items.sort { item1, item2 in
            guard let date1 = dateFormatter.date(from: item1.pubDate),
                  let date2 = dateFormatter.date(from: item2.pubDate) else {
                return false
            }
            return date1 > date2
        }
    }
    
    private func setupLongPressGesture() {
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        tableView.addGestureRecognizer(longPressGesture)
    }

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
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Mark Read", style: .default) { [weak self] _ in
            self?.markItemsAboveAsRead(indexPath)
        })

        present(alert, animated: true)
    }

    private func markItemsAboveAsRead(_ indexPath: IndexPath) {
        for index in 0...indexPath.row {
            items[index].isRead = true
        }
        saveReadState()
        tableView.reloadRows(at: (0...indexPath.row).map { IndexPath(row: $0, section: 0) }, with: .fade)
    }
    
    @objc private func handleReadItemsReset() {
        loadRSSFeeds()
    }
    
    // Add cleanup in deinit
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // Mark items as read and save state
    private func markVisibleItemsAsRead() {
        let visibleIndexPaths = tableView.indexPathsForVisibleRows ?? []
        for indexPath in visibleIndexPaths {
            if !items[indexPath.row].isRead {
                items[indexPath.row].isRead = true
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
        saveReadState()
    }
    
    private func saveReadState() {
        // Get existing read links
        var existingReadLinks = UserDefaults.standard.stringArray(forKey: "readItems") ?? []
        
        // Add new read links
        let newReadLinks = items.filter { $0.isRead }.map { $0.link }
        existingReadLinks.append(contentsOf: newReadLinks)
        
        // Remove duplicates
        existingReadLinks = Array(Set(existingReadLinks))
        
        // Save back to UserDefaults
        UserDefaults.standard.set(existingReadLinks, forKey: "readItems")
        UserDefaults.standard.synchronize()
        
        //debugPrintReadState(message: "After saving read state")
    }
    
    private func loadReadState() {
        let readLinks = UserDefaults.standard.stringArray(forKey: "readItems") ?? []
        items = items.map { item in
            var updatedItem = item
            updatedItem.isRead = readLinks.contains(item.link)
            return updatedItem
        }
    }
    
    private func setupScrollViewDelegate() {
        tableView.delegate = self
    }
    
    private func debugPrintReadState(message: String) {
        print("DEBUG - \(message)")
        print("Total items: \(items.count)")
        print("Read items in UserDefaults: \(UserDefaults.standard.stringArray(forKey: "readItems")?.count ?? 0)")
        print("Read items links: \(UserDefaults.standard.stringArray(forKey: "readItems") ?? [])")
    }
    
    private func loadRSSFeeds() {
        //debugPrintReadState(message: "Start loading RSS feeds")
        let readLinks = UserDefaults.standard.stringArray(forKey: "readItems") ?? []
        
        guard let data = UserDefaults.standard.data(forKey: "rssFeeds"),
              let feeds = try? JSONDecoder().decode([RSSFeed].self, from: data) else {
            refreshControl.endRefreshing()
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var allItems: [RSSItem] = []
        
        feeds.forEach { feed in
            dispatchGroup.enter()
            
            guard let url = URL(string: feed.url) else {
                dispatchGroup.leave()
                return
            }
            
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                defer { dispatchGroup.leave() }
                
                guard let data = data,
                      error == nil else {
                    print("Error fetching RSS feed: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                let parser = XMLParser(data: data)
                let rssParser = RSSParser(source: feed.title)
                parser.delegate = rssParser
                
                if parser.parse() {
                    let items = rssParser.items.filter { !readLinks.contains($0.link) }
                    allItems.append(contentsOf: items)
                }
            }
            task.resume()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            self.items = allItems.sorted { item1, item2 in
                guard let date1 = dateFormatter.date(from: item1.pubDate),
                      let date2 = dateFormatter.date(from: item2.pubDate) else {
                    return false
                }
                return date1 > date2
            }
            
            // Update button state based on available items
            if self.items.isEmpty {
                self.footerRefreshButton?.setTitle("  No More Articles  ", for: .normal)
                self.footerRefreshButton?.isEnabled = false
            } else {
                self.footerRefreshButton?.setTitle("  Refresh Feed  ", for: .normal)
                self.footerRefreshButton?.isEnabled = true
            }
            
            //debugPrintReadState(message: "Finished loading RSS feeds")
            if let markAllButton = self.tableView.tableFooterView?.subviews.first as? UIButton {
                markAllButton.setTitle(self.items.isEmpty ? "  Reached the end  " : "  Mark All as Read  ", for: .normal)
                markAllButton.isEnabled = !self.items.isEmpty
            }
            self.tableView.reloadData()
            self.refreshControl.endRefreshing()
            updateFooterVisibility()
        }
    }
    
    private func setupNavigationBar() {
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.primary
        
        // Dynamic color based on light/dark mode
        let titleColor: UIColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
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
    }
    
    private func setupNavigationButtons() {
        let leftButtons = [
            createBarButton(imageName: "rss", action: #selector(rssButtonTapped)),
            createBarButton(imageName: "bookmark", action: #selector(bookmarkButtonTapped)),
            createBarButton(imageName: "heart", action: #selector(heartButtonTapped))
        ]
        
        let rightButtons = [
            createBarButton(imageName: "settings", action: #selector(openSettings)),
            createBarButton(imageName: "edit", action: #selector(editButtonTapped))
        ]
        
        navigationItem.leftBarButtonItems = leftButtons
        navigationItem.rightBarButtonItems = rightButtons
        updateNavigationButtons()
    }
    
    private func updateNavigationButtons() {
        guard let leftButtons = navigationItem.leftBarButtonItems else { return }
        
        // Reset all to unfilled
        leftButtons[0].image = resizeImage(UIImage(named: "rss"), targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(.alwaysTemplate)
        leftButtons[1].image = resizeImage(UIImage(named: "bookmark"), targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(.alwaysTemplate)
        leftButtons[2].image = resizeImage(UIImage(named: "heart"), targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(.alwaysTemplate)
        
        // Set filled based on current type
        switch currentFeedType {
        case .rss:
            leftButtons[0].image = resizeImage(UIImage(named: "rssFilled"), targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(.alwaysTemplate)
        case .bookmarks:
            leftButtons[1].image = resizeImage(UIImage(named: "bookmarkFilled"), targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(.alwaysTemplate)
        case .heart:
            leftButtons[2].image = resizeImage(UIImage(named: "heartFilled"), targetSize: CGSize(width: 24, height: 24))?.withRenderingMode(.alwaysTemplate)
        }
    }
    
    private func createBarButton(imageName: String, action: Selector) -> UIBarButtonItem {
        let button = UIBarButtonItem(
            image: resizeImage(UIImage(named: imageName), targetSize: CGSize(width: 24, height: 24))?
                .withRenderingMode(.alwaysTemplate),
            style: .plain,
            target: self,
            action: action
        )
        button.tintColor = .white
        return button
    }
    
    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "RSSCell")
        
        setupTableViewFooter()
        tableView.tableFooterView = footerView
    }
    
    private func setupTableViewFooter() {
        footerView = UIView(frame: CGRect(x: 0, y: 0, width: view.frame.width, height: 80))
        footerView?.backgroundColor = AppColors.background
        
        let markAllButton = UIButton(type: .system)
        markAllButton.translatesAutoresizingMaskIntoConstraints = false
        footerView?.addSubview(markAllButton)
        
        markAllButton.backgroundColor = AppColors.primary
        markAllButton.setTitle(items.isEmpty ? "  Reached the end  " : "  Mark All as Read  ", for: .normal)
        markAllButton.isEnabled = !items.isEmpty
        markAllButton.setTitleColor(.white, for: .normal)
        markAllButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        markAllButton.layer.cornerRadius = 20
        markAllButton.layer.masksToBounds = true
        
        NSLayoutConstraint.activate([
            markAllButton.centerXAnchor.constraint(equalTo: footerView!.centerXAnchor),
            markAllButton.centerYAnchor.constraint(equalTo: footerView!.centerYAnchor),
            markAllButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        markAllButton.addTarget(self, action: #selector(markAllAsReadTapped), for: .touchUpInside)
    }
    
    private func updateFooterVisibility() {
        // Hide footer for bookmarks and hearts views
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
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Mark All", style: .default) { [weak self] _ in
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
        // Show loading state
        footerLoadingIndicator?.startAnimating()
        footerRefreshButton?.setTitle("  Loading...  ", for: .normal)
        footerRefreshButton?.isEnabled = false
        
        refreshFeeds()
    }
    
    @objc private func refreshFeeds() {
        items.removeAll { $0.isRead }
        tableView.reloadData()
        loadRSSFeeds()
        
        // Update button text based on items
        if items.isEmpty {
            footerRefreshButton?.setTitle("  No More Articles  ", for: .normal)
            footerRefreshButton?.isEnabled = false
        } else {
            footerRefreshButton?.setTitle("  Refresh Feed  ", for: .normal)
            footerRefreshButton?.isEnabled = true
        }
        footerLoadingIndicator?.stopAnimating()
    }
    
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
    
    private func toggleHeart(for item: RSSItem) {
        var heartedItems = UserDefaults.standard.stringArray(forKey: "heartedItems") ?? []
        
        if heartedItems.contains(item.link) {
            heartedItems.removeAll { $0 == item.link }
        } else {
            heartedItems.append(item.link)
        }
        
        UserDefaults.standard.set(heartedItems, forKey: "heartedItems")
        UserDefaults.standard.synchronize()
        
        // Refresh table if we're in heart view and unhearted an item
        if currentFeedType == .heart && !heartedItems.contains(item.link) {
            items.removeAll { $0.link == item.link }
            tableView.reloadData()
        }
    }
    
    @objc private func openSettings() {
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
    }
    
    func resizeImage(_ image: UIImage?, targetSize: CGSize) -> UIImage? {
        guard let image = image else { return nil }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setupNavigationBar()
            tableView.backgroundColor = AppColors.background
            tableView.reloadData()
        }
    }
    
    private func toggleBookmark(for item: RSSItem) {
        var bookmarkedItems = UserDefaults.standard.stringArray(forKey: "bookmarkedItems") ?? []
        
        if bookmarkedItems.contains(item.link) {
            bookmarkedItems.removeAll { $0 == item.link }
        } else {
            bookmarkedItems.append(item.link)
        }
        
        UserDefaults.standard.set(bookmarkedItems, forKey: "bookmarkedItems")
        UserDefaults.standard.synchronize()
        
        // Refresh table if we're in bookmarks view and unbookmarked an item
        if currentFeedType == .bookmarks && !bookmarkedItems.contains(item.link) {
            items.removeAll { $0.link == item.link }
            tableView.reloadData()
        }
    }
    
}

extension HomeFeedViewController: UIScrollViewDelegate {
    private func configureCell(_ cell: UITableViewCell, with item: RSSItem) {
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = "\(item.source) • \(getTimeAgo(from: item.pubDate))"
        
        config.textProperties.color = item.isRead ? AppColors.secondary : AppColors.accent
        config.secondaryTextProperties.color = AppColors.secondary
        config.secondaryTextProperties.font = .systemFont(ofSize: 12)
        config.textProperties.font = .systemFont(ofSize: 16, weight: item.isRead ? .regular : .medium)
        
        cell.contentConfiguration = config
    }
}

extension HomeFeedViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let item = items[indexPath.row]
        let bookmarkedItems = UserDefaults.standard.stringArray(forKey: "bookmarkedItems") ?? []
        let isBookmarked = bookmarkedItems.contains(item.link)
        
        let bookmarkAction = UIContextualAction(style: .normal, title: nil) { [weak self] (action, view, completion) in
            guard let self = self else {
                completion(false)
                return
            }
            
            self.toggleBookmark(for: item)
            
            // Update the swipe action's image after toggling
            let updatedBookmarkedItems = UserDefaults.standard.stringArray(forKey: "bookmarkedItems") ?? []
            let isNowBookmarked = updatedBookmarkedItems.contains(item.link)
            view.backgroundColor = AppColors.primary
            
            // Create and set new image
            let newImage = UIImage(named: isNowBookmarked ? "bookmarkFilled" : "bookmark")?
                .withRenderingMode(.alwaysTemplate)
            
            if let contextualAction = action as? UIContextualAction {
                contextualAction.image = newImage
            }
            
            completion(true)
        }
        
        // Set initial image based on current state
        bookmarkAction.image = UIImage(named: isBookmarked ? "bookmarkFilled" : "bookmark")?
            .withRenderingMode(.alwaysTemplate)
        bookmarkAction.backgroundColor = AppColors.primary
        
        return UISwipeActionsConfiguration(actions: [bookmarkAction])
    }
    
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let heartAction = UIContextualAction(style: .normal, title: nil) { [weak self] (action, view, completion) in
            guard let self = self else {
                completion(false)
                return
            }
            
            let item = self.items[indexPath.row]
            self.toggleHeart(for: item)
            
            let heartedItems = UserDefaults.standard.stringArray(forKey: "heartedItems") ?? []
            let isHearted = heartedItems.contains(item.link)
            let heartImage = UIImage(named: isHearted ? "heartFilled" : "heart")?.withRenderingMode(.alwaysTemplate)
            view.backgroundColor = AppColors.primary
            
            completion(true)
        }
        
        let item = items[indexPath.row]
        let heartedItems = UserDefaults.standard.stringArray(forKey: "heartedItems") ?? []
        let isHearted = heartedItems.contains(item.link)
        
        heartAction.image = UIImage(named: isHearted ? "heartFilled" : "heart")?.withRenderingMode(.alwaysTemplate)
        heartAction.backgroundColor = AppColors.primary
        
        return UISwipeActionsConfiguration(actions: [heartAction])
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RSSCell", for: indexPath)
        let item = items[indexPath.row]
        
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = "\(item.source) • \(getTimeAgo(from: item.pubDate))"
        
        // Style configuration
        cell.backgroundColor = AppColors.background
        config.textProperties.color = item.isRead ? AppColors.secondary : AppColors.accent
        config.secondaryTextProperties.color = AppColors.secondary
        config.secondaryTextProperties.font = .systemFont(ofSize: 12)
        config.textProperties.font = .systemFont(ofSize: 16, weight: item.isRead ? .regular : .medium)
        
        cell.accessoryType = .disclosureIndicator
        cell.contentConfiguration = config
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let url = URL(string: items[indexPath.row].link) {
            items[indexPath.row].isRead = true
            configureCell(tableView.cellForRow(at: indexPath)!, with: items[indexPath.row])
            saveReadState()
            
            let safariVC = SFSafariViewController(url: url)
            safariVC.dismissButtonStyle = .close
            safariVC.delegate = self
            present(safariVC, animated: true)
        }
    }
    
}

extension HomeFeedViewController: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        // Just dismiss - no need to reload feeds
        controller.dismiss(animated: true)
    }
}

// RSSParser.swift
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
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            let item = RSSItem(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines),
                source: feedSource
            )
            items.append(item)
            parsingItem = false
        }
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
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
            case "title": currentTitle += string
            case "link": currentLink += string
            case "pubDate": currentPubDate += string
            default: break
            }
        }
    }
    
}
