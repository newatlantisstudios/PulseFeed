import UIKit

class SearchResultsViewController: UIViewController {
    
    // MARK: - Properties
    
    /// Search query used to produce these results
    private var searchQuery: SearchQuery
    
    /// The search results to display
    private var searchResults: [RSSItem]
    
    /// Table view for displaying results
    private let tableView = UITableView()
    
    /// Empty results view shown when no results are found
    private let emptyResultsView = UIView()
    
    /// Label for the empty results view
    private let emptyResultsLabel = UILabel()
    
    /// Set of read article links (normalized)
    private var readLinks: Set<String> = []
    
    /// Set of bookmarked article links
    private var bookmarkedItems: Set<String> = []
    
    /// Set of hearted article links
    private var heartedItems: Set<String> = []
    
    // MARK: - Initialization
    
    init(query: SearchQuery, results: [RSSItem]) {
        self.searchQuery = query
        self.searchResults = results
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCachedData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Update read status
        StorageManager.shared.load(forKey: "readItems") { [weak self] (result: Result<[String], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if case .success(let readItems) = result {
                    // Update cached read links
                    self.readLinks = Set(readItems.map { StorageManager.shared.normalizeLink($0) })
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupUI() {
        title = "Search Results"
        view.backgroundColor = AppColors.background
        
        // Set up table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ResultCell")
        tableView.register(EnhancedRSSCell.self, forCellReuseIdentifier: "EnhancedResultCell")
        view.addSubview(tableView)
        
        // Setup empty results view
        emptyResultsView.translatesAutoresizingMaskIntoConstraints = false
        emptyResultsView.isHidden = !searchResults.isEmpty
        view.addSubview(emptyResultsView)
        
        emptyResultsLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyResultsLabel.text = "No results found for your search"
        emptyResultsLabel.textAlignment = .center
        emptyResultsLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        emptyResultsLabel.textColor = .secondaryLabel
        emptyResultsView.addSubview(emptyResultsLabel)
        
        // Add navigation bar buttons
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Refine",
            style: .plain,
            target: self,
            action: #selector(refineTapped)
        )
        
        // Setup constraints
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            emptyResultsView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyResultsView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyResultsView.widthAnchor.constraint(equalTo: view.widthAnchor),
            emptyResultsView.heightAnchor.constraint(equalToConstant: 200),
            
            emptyResultsLabel.centerXAnchor.constraint(equalTo: emptyResultsView.centerXAnchor),
            emptyResultsLabel.centerYAnchor.constraint(equalTo: emptyResultsView.centerYAnchor),
            emptyResultsLabel.leadingAnchor.constraint(equalTo: emptyResultsView.leadingAnchor, constant: 20),
            emptyResultsLabel.trailingAnchor.constraint(equalTo: emptyResultsView.trailingAnchor, constant: -20)
        ])
    }
    
    private func loadCachedData() {
        // Load hearted items
        StorageManager.shared.load(forKey: "heartedItems") { [weak self] (result: Result<[String], Error>) in
            if case .success(let items) = result {
                DispatchQueue.main.async {
                    self?.heartedItems = Set(items)
                    self?.tableView.reloadData()
                }
            }
        }
        
        // Load bookmarked items
        StorageManager.shared.load(forKey: "bookmarkedItems") { [weak self] (result: Result<[String], Error>) in
            if case .success(let items) = result {
                DispatchQueue.main.async {
                    self?.bookmarkedItems = Set(items)
                    self?.tableView.reloadData()
                }
            }
        }
    }
    
    // MARK: - Action Handlers
    
    @objc private func refineTapped() {
        let searchVC = AdvancedSearchViewController()
        searchVC.setupWithData(articles: searchResults, bookmarkedItems: bookmarkedItems, heartedItems: heartedItems)
        searchVC.delegate = self
        
        let navController = UINavigationController(rootViewController: searchVC)
        present(navController, animated: true)
    }
    
    // MARK: - Article Operations
    
    /// Updates the search results with a new set
    func updateResults(with newResults: [RSSItem], from query: SearchQuery) {
        searchQuery = query
        searchResults = newResults
        
        // Update UI
        tableView.reloadData()
        emptyResultsView.isHidden = !searchResults.isEmpty
    }
    
    /// Opens an article for reading
    private func openArticle(_ article: RSSItem, at indexPath: IndexPath) {
        guard let navigationController = navigationController else { return }
        
        // Mark article as read in memory
        searchResults[indexPath.row].isRead = true
        tableView.reloadRows(at: [indexPath], with: .none)
        
        // Use ReadStatusTracker to mark as read
        ReadStatusTracker.shared.markArticle(link: article.link, as: true)
        
        // Show the article reader
        let readerVC = ArticleReaderViewController()
        readerVC.article = article
        navigationController.pushViewController(readerVC, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SearchResultsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Get the article for this row
        let article = searchResults[indexPath.row]
        
        // Determine if we should use the enhanced cell style
        let useEnhancedStyle = UserDefaults.standard.bool(forKey: "enhancedArticleStyle")
        
        if useEnhancedStyle {
            let cell = tableView.dequeueReusableCell(withIdentifier: "EnhancedResultCell", for: indexPath) as! EnhancedRSSCell
            
            // Configure the cell with the article
            cell.configure(with: article)
            
            // Set bookmarked and hearted status
            cell.isBookmarked = bookmarkedItems.contains(article.link)
            cell.isHearted = heartedItems.contains(article.link)
            
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell", for: indexPath)
            
            // Configure basic cell
            cell.textLabel?.text = article.title
            cell.textLabel?.numberOfLines = 2
            cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
            
            // Show source as subtitle
            cell.detailTextLabel?.text = article.source
            cell.detailTextLabel?.textColor = .secondaryLabel
            
            // Show indicator for read/unread status
            if article.isRead {
                cell.textLabel?.textColor = .secondaryLabel
            } else {
                cell.textLabel?.textColor = .label
            }
            
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension SearchResultsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let article = searchResults[indexPath.row]
        openArticle(article, at: indexPath)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Use different heights based on cell style
        let useEnhancedStyle = UserDefaults.standard.bool(forKey: "enhancedArticleStyle")
        return useEnhancedStyle ? 120 : 70
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let article = searchResults[indexPath.row]
        
        // Bookmark action
        let bookmarkAction = UIContextualAction(style: .normal, title: "Bookmark") { [weak self] (_, _, completion) in
            guard let self = self else {
                completion(false)
                return
            }
            
            let isBookmarked = self.bookmarkedItems.contains(article.link)
            
            if isBookmarked {
                // Remove bookmark
                var items = Array(self.bookmarkedItems)
                items.removeAll { $0 == article.link }
                
                StorageManager.shared.save(items, forKey: "bookmarkedItems") { error in
                    if error == nil {
                        DispatchQueue.main.async {
                            self.bookmarkedItems.remove(article.link)
                            tableView.reloadRows(at: [indexPath], with: .automatic)
                            
                            // Post notification that bookmarks have been updated
                            NotificationCenter.default.post(name: Notification.Name("bookmarkedItemsUpdated"), object: nil)
                        }
                    }
                    completion(error == nil)
                }
            } else {
                // Add bookmark
                var items = Array(self.bookmarkedItems)
                items.append(article.link)
                
                StorageManager.shared.save(items, forKey: "bookmarkedItems") { error in
                    if error == nil {
                        DispatchQueue.main.async {
                            self.bookmarkedItems.insert(article.link)
                            tableView.reloadRows(at: [indexPath], with: .automatic)
                            
                            // Post notification that bookmarks have been updated
                            NotificationCenter.default.post(name: Notification.Name("bookmarkedItemsUpdated"), object: nil)
                        }
                    }
                    completion(error == nil)
                }
            }
        }
        
        // Heart/favorite action
        let heartAction = UIContextualAction(style: .normal, title: "Favorite") { [weak self] (_, _, completion) in
            guard let self = self else {
                completion(false)
                return
            }
            
            let isHearted = self.heartedItems.contains(article.link)
            
            if isHearted {
                // Remove from favorites
                var items = Array(self.heartedItems)
                items.removeAll { $0 == article.link }
                
                StorageManager.shared.save(items, forKey: "heartedItems") { error in
                    if error == nil {
                        DispatchQueue.main.async {
                            self.heartedItems.remove(article.link)
                            tableView.reloadRows(at: [indexPath], with: .automatic)
                            
                            // Post notification that favorites have been updated
                            NotificationCenter.default.post(name: Notification.Name("heartedItemsUpdated"), object: nil)
                        }
                    }
                    completion(error == nil)
                }
            } else {
                // Add to favorites
                var items = Array(self.heartedItems)
                items.append(article.link)
                
                StorageManager.shared.save(items, forKey: "heartedItems") { error in
                    if error == nil {
                        DispatchQueue.main.async {
                            self.heartedItems.insert(article.link)
                            tableView.reloadRows(at: [indexPath], with: .automatic)
                            
                            // Post notification that favorites have been updated
                            NotificationCenter.default.post(name: Notification.Name("heartedItemsUpdated"), object: nil)
                        }
                    }
                    completion(error == nil)
                }
            }
        }
        
        // Set action colors and icons
        let isBookmarked = bookmarkedItems.contains(article.link)
        bookmarkAction.backgroundColor = UIColor.systemBlue
        bookmarkAction.image = UIImage(named: isBookmarked ? "bookmark" : "bookmarkFilled")
        
        let isHearted = heartedItems.contains(article.link)
        heartAction.backgroundColor = UIColor.systemRed
        heartAction.image = UIImage(named: isHearted ? "heart" : "heartFilled")
        
        // Read/Unread toggle action
        let readAction = UIContextualAction(style: .normal, title: article.isRead ? "Unread" : "Read") { [weak self] (_, _, completion) in
            guard let self = self else {
                completion(false)
                return
            }
            
            // Toggle read status
            let newReadStatus = !article.isRead
            
            // Update the article in our collection
            self.searchResults[indexPath.row].isRead = newReadStatus
            
            // Use ReadStatusTracker to update read status
            ReadStatusTracker.shared.markArticle(link: article.link, as: newReadStatus)
            
            // Reload the cell
            tableView.reloadRows(at: [indexPath], with: .automatic)
            
            completion(true)
        }
        
        // Set read action style
        readAction.backgroundColor = article.isRead ? UIColor.systemGreen : UIColor.systemGray
        
        return UISwipeActionsConfiguration(actions: [readAction, heartAction, bookmarkAction])
    }
}

// MARK: - AdvancedSearchDelegate

extension SearchResultsViewController: AdvancedSearchDelegate {
    func didPerformSearch(with query: SearchQuery, results: [RSSItem]) {
        updateResults(with: results, from: query)
    }
    
    func didSelectSavedSearch(_ query: SearchQuery) {
        // Not needed for results view controller
    }
}