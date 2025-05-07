import UIKit

class TagManagementViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    // MARK: - Properties
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "TagCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private var tags: [(tag: Tag, count: Int)] = [] {
        didSet {
            DispatchQueue.main.async {
                print("DEBUG: TagManagementViewController - Tags data source updated with \(self.tags.count) tags, triggering tableView reload")
                self.tableView.reloadData()
            }
        }
    }
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tags"
        view.backgroundColor = AppColors.background
        setupNavigationBar()
        setupTableView()
        setupNotifications()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadTags()
    }
    
    // MARK: - Setup Methods
    
    private func setupNavigationBar() {
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addButtonTapped)
        )
        navigationItem.rightBarButtonItem = addButton
    }
    
    private func setupTableView() {
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tagsUpdated),
            name: Notification.Name("tagsUpdated"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(taggedItemsUpdated),
            name: Notification.Name("taggedItemsUpdated"),
            object: nil
        )
    }
    
    // MARK: - Data Loading Methods
    
    private func loadTags() {
        print("DEBUG: TagManagementViewController - Loading tags")
        
        // Try getting tags directly from UserDefaults first for immediate UI update
        if let data = UserDefaults.standard.data(forKey: "tags") {
            do {
                let directTags = try JSONDecoder().decode([Tag].self, from: data)
                if !directTags.isEmpty {
                    print("DEBUG: TagManagementViewController - DIRECT loaded \(directTags.count) tags from UserDefaults")
                    
                    // Create simple tag counts for immediate display
                    let simpleCounts = directTags.map { (tag: $0, count: 0) }
                    self.tags = simpleCounts.sorted { $0.tag.name.lowercased() < $1.tag.name.lowercased() }
                    
                    // Update UI immediately
                    self.tableView.reloadData()
                    print("DEBUG: TagManagementViewController - Table DIRECTLY reloaded with \(self.tags.count) tags")
                }
            } catch {
                print("DEBUG: TagManagementViewController - Error decoding tags from UserDefaults: \(error.localizedDescription)")
            }
        }
        
        // Still do the full load to get proper counts
        StorageManager.shared.getTagsWithCounts { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let tagsWithCounts):
                    print("DEBUG: TagManagementViewController - Loaded \(tagsWithCounts.count) tags")
                    for tagWithCount in tagsWithCounts {
                        print("DEBUG: TagManagementViewController - Tag: \(tagWithCount.tag.name), Count: \(tagWithCount.count)")
                    }
                    
                    // Sort and update data source
                    self.tags = tagsWithCounts.sorted { $0.tag.name.lowercased() < $1.tag.name.lowercased() }
                    
                    // Force reload the table on the main thread
                    self.tableView.reloadData()
                    print("DEBUG: TagManagementViewController - Table reloaded with \(self.tags.count) tags")
                    
                case .failure(let error):
                    print("DEBUG: TagManagementViewController - Error loading tags: \(error.localizedDescription)")
                    // Only show error if we didn't already load tags directly
                    if self.tags.isEmpty {
                        self.showError("Failed to load tags: \(error.localizedDescription)")
                        self.tags = []
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }
    
    // MARK: - Action Methods
    
    @objc private func addButtonTapped() {
        showCreateTagDialog()
    }
    
    @objc private func tagsUpdated() {
        print("DEBUG: TagManagementViewController - Tags updated notification received")
        print("DEBUG: Forcing complete table reload due to tag updates")
        
        // Force immediate reload with a little delay to ensure storage is updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Clear the cache to force reload from UserDefaults
            StorageManager.shared.clearTagCache()
            self.loadTags()
        }
    }
    
    @objc private func taggedItemsUpdated() {
        print("DEBUG: TagManagementViewController - Tagged items updated notification received")
        
        // Force immediate reload with a little delay to ensure storage is updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.loadTags()
        }
    }
    
    private func showCreateTagDialog() {
        let alert = UIAlertController(
            title: "New Tag",
            message: "Enter a name for the new tag",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Tag Name"
        }
        
        // Add color picker to the alert
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let tagName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !tagName.isEmpty else {
                return
            }
            
            self?.createTag(name: tagName)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func createTag(name: String) {
        print("DEBUG: TagManagementViewController - Creating tag: \(name)")
        StorageManager.shared.createTag(name: name) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let tag):
                // Tag created successfully, will reload via notification
                print("DEBUG: TagManagementViewController - Tag created successfully: \(tag.name)")
                
                // Force reload the table explicitly
                DispatchQueue.main.async {
                    self.loadTags()
                    
                    // Also post the notification manually to ensure it's sent
                    NotificationCenter.default.post(name: Notification.Name("tagsUpdated"), object: nil)
                }
            case .failure(let error):
                print("DEBUG: TagManagementViewController - Failed to create tag: \(error.localizedDescription)")
                self.showError("Failed to create tag: \(error.localizedDescription)")
            }
        }
    }
    
    private func showTagOptions(for tag: Tag, at indexPath: IndexPath) {
        let alert = UIAlertController(title: tag.name, message: nil, preferredStyle: .actionSheet)
        
        // Rename action
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.showRenameDialog(for: tag)
        })
        
        // Change color action
        alert.addAction(UIAlertAction(title: "Change Color", style: .default) { [weak self] _ in
            self?.showChangeColorDialog(for: tag)
        })
        
        // View items action
        alert.addAction(UIAlertAction(title: "View Tagged Items", style: .default) { [weak self] _ in
            self?.showTaggedItems(tag)
        })
        
        // Delete action
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDeleteTag(tag)
        })
        
        // Cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = tableView
            popoverController.sourceRect = tableView.rectForRow(at: indexPath)
        }
        
        present(alert, animated: true)
    }
    
    private func showRenameDialog(for tag: Tag) {
        let alert = UIAlertController(
            title: "Rename Tag",
            message: "Enter a new name for the tag",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Tag Name"
            textField.text = tag.name
        }
        
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newName.isEmpty else {
                return
            }
            
            var updatedTag = tag
            updatedTag.name = newName
            
            self?.updateTag(updatedTag)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showChangeColorDialog(for tag: Tag) {
        let alert = UIAlertController(
            title: "Change Tag Color",
            message: "Select a new color for the tag",
            preferredStyle: .actionSheet
        )
        
        // Add actions for some predefined colors
        let colors = [
            ("Blue", "#007AFF"),
            ("Green", "#34C759"),
            ("Red", "#FF3B30"),
            ("Orange", "#FF9500"),
            ("Purple", "#AF52DE"),
            ("Pink", "#FF2D55"),
            ("Yellow", "#FFCC00"),
            ("Light Blue", "#5AC8FA"),
            ("Gray", "#8E8E93")
        ]
        
        for (colorName, colorHex) in colors {
            alert.addAction(UIAlertAction(title: colorName, style: .default) { [weak self] _ in
                var updatedTag = tag
                updatedTag.colorHex = colorHex
                self?.updateTag(updatedTag)
            })
        }
        
        // Random color option
        alert.addAction(UIAlertAction(title: "Random Color", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            StorageManager.shared.getTags { result in
                switch result {
                case .success(let existingTags):
                    let randomColor = TagManager.generateUniqueColor(existingTags: existingTags)
                    var updatedTag = tag
                    updatedTag.colorHex = randomColor
                    self.updateTag(updatedTag)
                case .failure(let error):
                    self.showError("Failed to generate random color: \(error.localizedDescription)")
                }
            }
        })
        
        // Cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    private func showTaggedItems(_ tag: Tag) {
        // Create view controller to show tagged items
        let taggedItemsVC = TaggedItemsViewController(tag: tag)
        navigationController?.pushViewController(taggedItemsVC, animated: true)
    }
    
    private func confirmDeleteTag(_ tag: Tag) {
        let alert = UIAlertController(
            title: "Delete Tag",
            message: "Are you sure you want to delete the tag '\(tag.name)'? This will remove the tag from all items.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteTag(id: tag.id)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func updateTag(_ tag: Tag) {
        StorageManager.shared.updateTag(tag) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                // Tag updated successfully, will reload via notification
                print("Tag updated successfully")
            case .failure(let error):
                self.showError("Failed to update tag: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteTag(id: String) {
        StorageManager.shared.deleteTag(id: id) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                // Tag deleted successfully, will reload via notification
                print("Tag deleted successfully")
            case .failure(let error):
                self.showError("Failed to delete tag: \(error.localizedDescription)")
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
    
    // MARK: - UITableViewDataSource Methods
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tags.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TagCell", for: indexPath)
        
        let tagWithCount = tags[indexPath.row]
        let tag = tagWithCount.tag
        let count = tagWithCount.count
        
        var config = cell.defaultContentConfiguration()
        config.text = tag.name
        config.secondaryText = "\(count) \(count == 1 ? "item" : "items")"
        
        // Create a color view
        let colorView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        colorView.backgroundColor = colorFromHex(tag.colorHex)
        colorView.layer.cornerRadius = 10
        
        cell.accessoryView = colorView
        cell.contentConfiguration = config
        
        return cell
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let tag = tags[indexPath.row].tag
        showTagOptions(for: tag, at: indexPath)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let tag = tags[indexPath.row].tag
            confirmDeleteTag(tag)
        }
    }
    
    // MARK: - Helper Methods
    
    private func colorFromHex(_ hex: String) -> UIColor {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if cString.hasPrefix("#") {
            cString.remove(at: cString.startIndex)
        }

        if (cString.count) != 6 {
            return .gray
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        return UIColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - Tagged Items View Controller

class TaggedItemsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let tag: Tag
    private var feedItems: [RSSFeed] = []
    private var articleItems: [ArticleSummary] = []
    
    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Feeds", "Articles"])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "TaggedItemCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    init(tag: Tag) {
        self.tag = tag
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Items Tagged \"\(tag.name)\""
        view.backgroundColor = AppColors.background
        setupTableView()
        loadTaggedItems()
    }
    
    private func setupTableView() {
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        tableView.reloadData()
    }
    
    private func loadTaggedItems() {
        // Get all items with this tag
        let group = DispatchGroup()
        
        // Load feeds
        group.enter()
        StorageManager.shared.getItemsWithTag(tagId: tag.id, itemType: .feed) { [weak self] result in
            defer { group.leave() }
            guard let self = self else { return }
            
            switch result {
            case .success(let feedURLs):
                // Now get the actual feed objects
                self.loadFeeds(for: feedURLs)
            case .failure(let error):
                print("Error loading tagged feeds: \(error.localizedDescription)")
            }
        }
        
        // Load articles
        group.enter()
        StorageManager.shared.getItemsWithTag(tagId: tag.id, itemType: .article) { [weak self] result in
            defer { group.leave() }
            guard let self = self else { return }
            
            switch result {
            case .success(let articleLinks):
                // Now get the actual article objects
                self.loadArticles(for: articleLinks)
            case .failure(let error):
                print("Error loading tagged articles: \(error.localizedDescription)")
            }
        }
        
        group.notify(queue: .main) {
            self.tableView.reloadData()
        }
    }
    
    private func loadFeeds(for feedURLs: [String]) {
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let allFeeds):
                // Filter to just get the tagged feeds
                let normalizedURLs = feedURLs.map { StorageManager.shared.normalizeLink($0) }
                
                self.feedItems = allFeeds.filter { feed in
                    normalizedURLs.contains { StorageManager.shared.normalizeLink(feed.url) == $0 }
                }.sorted { $0.title.lowercased() < $1.title.lowercased() }
                
                if self.segmentedControl.selectedSegmentIndex == 0 {
                    self.tableView.reloadData()
                }
                
            case .failure(let error):
                print("Error loading feeds: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadArticles(for articleLinks: [String]) {
        // In a real implementation, we would need to load all articles from all feeds
        // This is just a placeholder for now
        self.articleItems = []
        // This would need to be implemented based on how articles are stored in your app
    }
    
    private func removeTag(from itemId: String, itemType: TaggedItem.ItemType) {
        StorageManager.shared.removeTagFromItem(tagId: tag.id, itemId: itemId, itemType: itemType) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                // Reload tagged items
                self.loadTaggedItems()
            case .failure(let error):
                self.showError("Failed to remove tag: \(error.localizedDescription)")
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
    
    // MARK: - UITableViewDataSource Methods
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let selectedType = segmentedControl.selectedSegmentIndex
        return selectedType == 0 ? feedItems.count : articleItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TaggedItemCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        
        let selectedType = segmentedControl.selectedSegmentIndex
        if selectedType == 0 {
            // Feeds
            let feed = feedItems[indexPath.row]
            config.text = feed.title
            config.secondaryText = feed.url
        } else {
            // Articles
            if !articleItems.isEmpty {
                let article = articleItems[indexPath.row]
                config.text = article.title
                config.secondaryText = article.link
            } else {
                config.text = "No tagged articles"
            }
        }
        
        cell.contentConfiguration = config
        return cell
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Remove tag action
        let removeTagAction = UIContextualAction(style: .destructive, title: "Remove Tag") { [weak self] _, _, completion in
            guard let self = self else {
                completion(false)
                return
            }
            
            let selectedType = self.segmentedControl.selectedSegmentIndex
            if selectedType == 0 && indexPath.row < self.feedItems.count {
                // Remove tag from feed
                let feed = self.feedItems[indexPath.row]
                self.removeTag(from: feed.url, itemType: .feed)
                completion(true)
            } else if selectedType == 1 && indexPath.row < self.articleItems.count {
                // Remove tag from article
                let article = self.articleItems[indexPath.row]
                self.removeTag(from: article.link, itemType: .article)
                completion(true)
            } else {
                completion(false)
            }
        }
        
        return UISwipeActionsConfiguration(actions: [removeTagAction])
    }
}