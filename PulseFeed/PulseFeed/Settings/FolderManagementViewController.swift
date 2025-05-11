import UIKit

class FolderManagementViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    // MARK: - Properties
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FolderCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private var folders: [FeedFolder] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    
    private var feeds: [RSSFeed] = [] {
        didSet {
            calculateFolderedFeeds()
        }
    }
    
    private var unfolderedFeeds: [RSSFeed] = []
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Folders"
        view.backgroundColor = AppColors.background
        setupNavigationBar()
        setupTableView()
        setupNotifications()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadFolders()
        loadFeeds()
    }
    
    // MARK: - Setup Methods
    
    private func setupNavigationBar() {
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addButtonTapped)
        )
        navigationItem.rightBarButtonItem = addButton
        
        // Add a back button
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonPressed)
        )
        backButton.tintColor = .systemBlue
        navigationItem.leftBarButtonItem = backButton
    }
    
    @objc private func backButtonPressed() {
        navigationController?.popViewController(animated: true)
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
        // Listen for folder updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(foldersUpdated),
            name: Notification.Name("feedFoldersUpdated"),
            object: nil
        )

        // Listen for memory warnings to check if that's causing our issue
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Listen for app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appStateChanged),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appStateChanged),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        print("DEBUG: Memory warning received in FolderManagementViewController")
    }

    @objc private func appStateChanged(notification: Notification) {
        print("DEBUG: App state changed: \(notification.name)")
    }
    
    // MARK: - Data Loading Methods
    
    private func loadFolders() {
        StorageManager.shared.getFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let loadedFolders):
                self.folders = loadedFolders.sorted { $0.name.lowercased() < $1.name.lowercased() }
                
                // If we already have feeds loaded, update the unfoldered feeds
                if !self.feeds.isEmpty {
                    self.calculateFolderedFeeds()
                }
                
            case .failure(let error):
                print("Error loading folders: \(error.localizedDescription)")
                self.folders = []
            }
        }
    }
    
    private func loadFeeds() {
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let loadedFeeds):
                self.feeds = loadedFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }
            case .failure(let error):
                print("Error loading feeds: \(error.localizedDescription)")
                self.feeds = []
            }
        }
    }
    
    private func calculateFolderedFeeds() {
        // Get all feed URLs that are in folders
        let folderedFeedURLs = Set(folders.flatMap { $0.feedURLs.map { StorageManager.shared.normalizeLink($0) } })
        
        // Filter out feeds that are already in folders
        unfolderedFeeds = feeds.filter { feed in
            !folderedFeedURLs.contains(StorageManager.shared.normalizeLink(feed.url))
        }
        
        // Reload table to reflect changes
        tableView.reloadData()
    }
    
    // MARK: - Action Methods
    
    @objc private func addButtonTapped() {
        let alert = UIAlertController(
            title: "New Folder",
            message: "Enter a name for the new folder",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Folder Name"
        }
        
        let createAction = UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let folderName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !folderName.isEmpty else {
                return
            }
            
            self?.createFolder(name: folderName)
        }
        
        alert.addAction(createAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func foldersUpdated() {
        loadFolders()
    }
    
    private func createFolder(name: String) {
        StorageManager.shared.createFolder(name: name) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                // Reload folders
                self.loadFolders()
            case .failure(let error):
                self.showError("Failed to create folder: \(error.localizedDescription)")
            }
        }
    }
    
    private func showFolderOptions(for folder: FeedFolder, at indexPath: IndexPath) {
        let alert = UIAlertController(title: folder.name, message: nil, preferredStyle: .actionSheet)
        
        // Rename action
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.showRenameDialog(for: folder)
        })
        
        // Add feeds action
        alert.addAction(UIAlertAction(title: "Add Feeds", style: .default) { [weak self] _ in
            self?.showAddFeedsDialog(for: folder)
        })
        
        // View feeds action
        alert.addAction(UIAlertAction(title: "View Feeds", style: .default) { [weak self] _ in
            self?.showFeedsInFolder(folder)
        })
        
        // Delete action
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDeleteFolder(folder)
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
    
    private func showRenameDialog(for folder: FeedFolder) {
        let alert = UIAlertController(
            title: "Rename Folder",
            message: "Enter a new name for the folder",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Folder Name"
            textField.text = folder.name
        }
        
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newName.isEmpty else {
                return
            }
            
            var updatedFolder = folder
            updatedFolder.name = newName
            
            self?.updateFolder(updatedFolder)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showAddFeedsDialog(for folder: FeedFolder) {
        // Create view controller to select feeds
        let feedSelectionVC = FeedSelectionViewController(
            feeds: unfolderedFeeds,
            folder: folder
        )
        navigationController?.pushViewController(feedSelectionVC, animated: true)
    }
    
    private func showFeedsInFolder(_ folder: FeedFolder) {
        // Create view controller to show feeds in folder
        let folderFeedsVC = FolderFeedsViewController(folder: folder)

        // Ensure the folder is fully loaded before pushing the view controller
        folderFeedsVC.preloadFeeds {
            DispatchQueue.main.async { [weak self] in
                self?.navigationController?.pushViewController(folderFeedsVC, animated: true)
            }
        }
    }
    
    private func confirmDeleteFolder(_ folder: FeedFolder) {
        let alert = UIAlertController(
            title: "Delete Folder",
            message: "Are you sure you want to delete the folder '\(folder.name)'? This will not delete the feeds inside it.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteFolder(id: folder.id)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func updateFolder(_ folder: FeedFolder) {
        StorageManager.shared.updateFolder(folder) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                // Folder updated successfully, will reload via notification
                print("Folder updated successfully")
            case .failure(let error):
                self.showError("Failed to update folder: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteFolder(id: String) {
        StorageManager.shared.deleteFolder(id: id) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                // Folder deleted successfully, will reload via notification
                print("Folder deleted successfully")
            case .failure(let error):
                self.showError("Failed to delete folder: \(error.localizedDescription)")
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
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? folders.count : 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderCell", for: indexPath)
        
        var config = cell.defaultContentConfiguration()
        
        if indexPath.section == 0 {
            // Folder section
            let folder = folders[indexPath.row]
            config.text = folder.name
            
            // Show count of feeds in folder
            let feedCount = folder.feedURLs.count
            config.secondaryText = "\(feedCount) \(feedCount == 1 ? "feed" : "feeds")"
            
            // Add disclosure indicator for folders
            cell.accessoryType = .disclosureIndicator
        } else {
            // Unfoldered feeds section
            config.text = "Unorganized Feeds"
            let feedCount = unfolderedFeeds.count
            config.secondaryText = "\(feedCount) \(feedCount == 1 ? "feed" : "feeds")"
            
            // Add disclosure indicator for unfoldered feeds
            cell.accessoryType = .disclosureIndicator
        }
        
        cell.contentConfiguration = config
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Folders" : "Other"
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 {
            // Show folder options
            let folder = folders[indexPath.row]
            showFolderOptions(for: folder, at: indexPath)
        } else {
            // Show unfoldered feeds
            let unfolderedFeedsVC = UnfolderedFeedsViewController(feeds: unfolderedFeeds)
            navigationController?.pushViewController(unfolderedFeedsVC, animated: true)
        }
    }
    
    // For swipe-to-delete
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if indexPath.section == 0 && editingStyle == .delete {
            let folder = folders[indexPath.row]
            confirmDeleteFolder(folder)
        }
    }
}

// MARK: - Feed Selection View Controller

class FeedSelectionViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let feeds: [RSSFeed]
    private let folder: FeedFolder
    private var selectedFeeds: Set<String> = []
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FeedSelectionCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.allowsMultipleSelection = true
        return table
    }()
    
    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Select one or more feeds to add to this folder"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    init(feeds: [RSSFeed], folder: FeedFolder) {
        self.feeds = feeds
        self.folder = folder
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Add to \(folder.name)"
        view.backgroundColor = AppColors.background
        setupTableView()
        setupNavigationBar()
        updateDoneButton()
    }
    
    private func setupTableView() {
        view.addSubview(instructionLabel)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigationBar() {
        // Add "Done" button on the right
        let doneButton = UIBarButtonItem(
            title: "Add (0)",
            style: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        navigationItem.rightBarButtonItem = doneButton
        
        // Add "Select All" button
        let selectAllButton = UIBarButtonItem(
            title: "Select All",
            style: .plain,
            target: self,
            action: #selector(selectAllButtonTapped)
        )
        
        // Create a custom back button with the standard back chevron
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonTapped)
        )
        
        // Set the left bar button items to include both back and select all
        navigationItem.leftBarButtonItems = [backButton, selectAllButton]
    }
    
    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    private func updateDoneButton() {
        let count = selectedFeeds.count
        navigationItem.rightBarButtonItem?.title = count > 0 ? "Add (\(count))" : "Done"
        navigationItem.rightBarButtonItem?.isEnabled = count > 0
    }
    
    @objc private func selectAllButtonTapped() {
        if selectedFeeds.count == feeds.count {
            // Deselect all
            selectedFeeds.removeAll()
            for row in 0..<feeds.count {
                let indexPath = IndexPath(row: row, section: 0)
                tableView.deselectRow(at: indexPath, animated: true)
            }
            navigationItem.leftBarButtonItem?.title = "Select All"
        } else {
            // Select all
            for (index, feed) in feeds.enumerated() {
                selectedFeeds.insert(feed.url)
                let indexPath = IndexPath(row: index, section: 0)
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            }
            navigationItem.leftBarButtonItem?.title = "Deselect All"
        }
        
        updateDoneButton()
        tableView.reloadData()
    }
    
    @objc private func doneButtonTapped() {
        if selectedFeeds.isEmpty {
            navigationController?.popViewController(animated: true)
            return
        }
        
        // Add selected feeds to folder
        let group = DispatchGroup()
        var errors: [Error] = []
        
        for feedURL in selectedFeeds {
            group.enter()
            StorageManager.shared.addFeedToFolder(feedURL: feedURL, folderId: folder.id) { result in
                switch result {
                case .success(_):
                    break
                case .failure(let error):
                    errors.append(error)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            if errors.isEmpty {
                // All feeds added successfully
                NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                self?.navigationController?.popViewController(animated: true)
            } else {
                // Show error
                self?.showError("Failed to add some feeds to folder")
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
        return feeds.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FeedSelectionCell", for: indexPath)
        
        let feed = feeds[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = feed.title
        config.secondaryText = feed.url
        cell.contentConfiguration = config
        
        // Set the cell's selection state
        if selectedFeeds.contains(feed.url) {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }
        
        return cell
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let feed = feeds[indexPath.row]
        selectedFeeds.insert(feed.url)
        
        // Update UI
        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .checkmark
        }
        
        updateDoneButton()
        
        // Update "Select All" button
        if selectedFeeds.count == feeds.count {
            navigationItem.leftBarButtonItem?.title = "Deselect All"
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let feed = feeds[indexPath.row]
        selectedFeeds.remove(feed.url)
        
        // Update UI
        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .none
        }
        
        updateDoneButton()
        
        // Update "Select All" button
        if selectedFeeds.count < feeds.count {
            navigationItem.leftBarButtonItem?.title = "Select All"
        }
    }
}

// MARK: - Folder Feeds View Controller

// Global debugging function to help track when feeds are reset
func printFeedsReset(feeds: [RSSFeed], file: String = #file, function: String = #function, line: Int = #line) {
    print("DEBUG: FEEDS RESET TO EMPTY ARRAY! Caller: \(file):\(line) - \(function)")
    print("DEBUG: Previous feeds count: \(feeds.count)")
    print("DEBUG: Stack trace:")
    Thread.callStackSymbols.forEach { print("DEBUG: \($0)") }

    // Dump memory addresses for more detailed investigation
    print("DEBUG: Memory addresses:")
    for (index, feed) in feeds.enumerated() {
        print("DEBUG: Feed \(index) address: \(Unmanaged.passUnretained(feed as AnyObject).toOpaque())")
    }

    // Log the current responder chain to see what view is active
    print("DEBUG: Current responder chain:")
    // Use the modern approach for getting key window in multi-scene apps
    var responder: UIResponder? = nil
    if #available(iOS 13.0, *) {
        let scene = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first
        if let windowScene = scene as? UIWindowScene {
            responder = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        }
    } else {
        // Fallback for older iOS versions
        responder = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }

    var i = 0
    while let r = responder {
        print("DEBUG: [\(i)] \(type(of: r))")
        responder = r.next
        i += 1
    }
}

class FolderFeedsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    private let folder: FeedFolder
    // Use strong reference to feeds
    // Store feeds in UserDefaults when empty - ensures we always have a backup
    private func backupFeeds(_ feeds: [RSSFeed]) {
        if !feeds.isEmpty {
            let feedData = feeds.map { ["title": $0.title, "url": $0.url] }
            UserDefaults.standard.set(feedData, forKey: "folder_\(folder.id)_feeds_backup")
            UserDefaults.standard.synchronize()
            print("DEBUG: Backed up \(feeds.count) feeds to UserDefaults")
        }
    }

    // Restore feeds from backup if needed
    private func restoreFeeds() -> [RSSFeed]? {
        if let savedFeedData = UserDefaults.standard.array(forKey: "folder_\(folder.id)_feeds_backup") as? [[String: String]] {
            let restoredFeeds = savedFeedData.map { dict -> RSSFeed in
                RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
            }

            if !restoredFeeds.isEmpty {
                print("DEBUG: Restored \(restoredFeeds.count) feeds from backup")
                return restoredFeeds
            }
        }
        return nil
    }

    // Strong reference to feeds with extra protection
    private var _feeds: [RSSFeed] = []
    private var feeds: [RSSFeed] {
        get {
            // If feeds are empty but we know they should exist (preloaded=true),
            // try to restore from backup
            if _feeds.isEmpty && preloaded {
                print("DEBUG: Feeds are empty but should be loaded, attempting to restore")
                if let restored = restoreFeeds() {
                    _feeds = restored
                }
            }
            return _feeds
        }
        set {
            let oldCount = _feeds.count
            _feeds = newValue
            print("DEBUG: Feeds updated - new count: \(newValue.count), previous count: \(oldCount)")

            // Automatically backup feeds when they change
            if !newValue.isEmpty {
                backupFeeds(newValue)
            }

            // If we're setting to empty but had data before, log it
            if newValue.isEmpty && oldCount > 0 {
                print("DEBUG: [WARNING] Feeds being cleared! Current stack trace:")
                Thread.callStackSymbols.forEach { print($0) }
            }

            // When feeds are set, ensure the table is updated immediately
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Reload table view
                self.tableView.reloadData()
                self.emptyStateLabel.isHidden = !self.feeds.isEmpty
            }
        }
    }
    private var isLoading = false
    private var preloaded = false

    // Fixed footer label that will always be visible
    private let footerLabel = UILabel()

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FolderFeedCell")
        // Enable multi-selection for bulk delete
        table.allowsMultipleSelection = true
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No feeds in this folder"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // Method to preload feeds before showing the view
    func preloadFeeds(completion: @escaping () -> Void) {
        // Don't load again if already loading or preloaded
        if isLoading || preloaded {
            print("DEBUG: preloadFeeds - already loading or preloaded, returning immediately")
            completion()
            return
        }

        print("DEBUG: preloadFeeds - starting preload operation")
        isLoading = true

        // Capture start time for performance debugging
        let startTime = Date()

        // Create a local completion handler for tracking
        var preloadCompletionCalled = false

        StorageManager.shared.getFeedsInFolder(folderId: folder.id) { [weak self] result in
            let elapsed = Date().timeIntervalSince(startTime)
            print("DEBUG: preloadFeeds API call completed in \(elapsed) seconds")

            guard let self = self else {
                print("DEBUG: preloadFeeds - self was deallocated during API call")
                if !preloadCompletionCalled {
                    preloadCompletionCalled = true
                    completion()
                }
                return
            }

            switch result {
            case .success(let folderFeeds):
                print("DEBUG: preloadFeeds - successfully loaded \(folderFeeds.count) feeds")

                // Ensure operations happen on main thread since we'll be updating UI state
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else {
                        print("DEBUG: preloadFeeds - self was deallocated in main thread callback")
                        if !preloadCompletionCalled {
                            preloadCompletionCalled = true
                            completion()
                        }
                        return
                    }

                    print("DEBUG: preloadFeeds - Processing results on main thread")

                    // Sort the feeds by name, but first make a local copy to retain
                    let sortedFeeds = folderFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }

                    // Update our feeds array
                    self.feeds = sortedFeeds
                    self.preloaded = true
                    print("DEBUG: preloadFeeds - feeds updated to \(sortedFeeds.count) items")

                    // Save to UserDefaults as a backup
                    if !folderFeeds.isEmpty {
                        let feedIDs = folderFeeds.map { ["title": $0.title, "url": $0.url] }
                        UserDefaults.standard.set(feedIDs, forKey: "folder_\(self.folder.id)_feeds")
                        UserDefaults.standard.set(feedIDs, forKey: "folder_\(self.folder.id)_feeds_backup")
                        UserDefaults.standard.synchronize()
                        print("DEBUG: preloadFeeds - saved \(feedIDs.count) feeds to UserDefaults backup")
                    }

                    self.isLoading = false
                    if !preloadCompletionCalled {
                        preloadCompletionCalled = true
                        completion()
                    }
                }

            case .failure(let error):
                print("DEBUG: Error preloading feeds in folder: \(error.localizedDescription)")

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else {
                        print("DEBUG: preloadFeeds - self was deallocated in failure handler")
                        if !preloadCompletionCalled {
                            preloadCompletionCalled = true
                            completion()
                        }
                        return
                    }

                    // Try to restore from backup first
                    if let savedFeedData = UserDefaults.standard.array(forKey: "folder_\(self.folder.id)_feeds_backup") as? [[String: String]] {
                        let restoredFeeds = savedFeedData.map { dict -> RSSFeed in
                            RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                        }

                        if !restoredFeeds.isEmpty {
                            self.feeds = restoredFeeds
                            self.preloaded = true
                            print("DEBUG: preloadFeeds - Restored \(restoredFeeds.count) feeds from backup")
                        } else {
                            // Also try the regular backup
                            if let regularBackup = UserDefaults.standard.array(forKey: "folder_\(self.folder.id)_feeds") as? [[String: String]] {
                                let regularRestoredFeeds = regularBackup.map { dict -> RSSFeed in
                                    RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                                }

                                if !regularRestoredFeeds.isEmpty {
                                    self.feeds = regularRestoredFeeds
                                    self.preloaded = true
                                    print("DEBUG: preloadFeeds - Restored \(regularRestoredFeeds.count) feeds from regular backup")
                                } else {
                                    self.feeds = []
                                    print("DEBUG: preloadFeeds - No feeds in regular backup either, using empty array")
                                }
                            } else {
                                self.feeds = []
                                print("DEBUG: preloadFeeds - No backups available, using empty array")
                            }
                        }
                    } else {
                        self.feeds = []
                        print("DEBUG: preloadFeeds - No backup available, using empty array")
                    }

                    self.isLoading = false
                    if !preloadCompletionCalled {
                        preloadCompletionCalled = true
                        completion()
                    }
                }
            }
        }

        // Set up a watchdog timer to ensure completion is called even if there's an issue
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            if !preloadCompletionCalled {
                print("DEBUG: [CRITICAL] preloadFeeds watchdog timer fired - completion was never called!")

                guard let self = self else {
                    preloadCompletionCalled = true
                    completion()
                    return
                }

                // Reset loading state
                self.isLoading = false

                // Try to restore from backup as a last resort
                if self.feeds.isEmpty {
                    print("DEBUG: preloadFeeds watchdog - attempting to restore from backup")
                    if let backupData = UserDefaults.standard.array(forKey: "folder_\(self.folder.id)_feeds_backup") as? [[String: String]] {
                        let restoredFeeds = backupData.map { dict -> RSSFeed in
                            RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                        }

                        if !restoredFeeds.isEmpty {
                            print("DEBUG: preloadFeeds watchdog - restored \(restoredFeeds.count) feeds from backup")
                            self.feeds = restoredFeeds
                            self.preloaded = true
                        }
                    }
                }

                preloadCompletionCalled = true
                completion()
            }
        }
    }

    init(folder: FeedFolder) {
        self.folder = folder
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        print("DEBUG: viewDidLoad called - folder: \(folder.name), feedURLs count: \(folder.feedURLs.count)")
        title = folder.name
        view.backgroundColor = AppColors.background
        setupTableViewWithFixedFooter() // Use our new setup method
        setupLoadingIndicator()
        setupEmptyStateLabel()
        setupFixedFooter() // Add a permanent fixed footer that won't disappear

        // Setup notification observer to stay updated on folder changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(folderUpdated),
            name: Notification.Name("feedFoldersUpdated"),
            object: nil
        )
        // Setup navigation bar items for bulk delete
        setupNavigationBar()
    }

    private func setupFixedFooter() {
        // Create a container view to hold the footer elements
        let footerContainer = UIView()
        footerContainer.backgroundColor = AppColors.background
        footerContainer.translatesAutoresizingMaskIntoConstraints = false

        // Configure our fixed footer label
        footerLabel.text = "Tap multiple feeds to select them, then press 'Delete'"
        footerLabel.textAlignment = .center
        footerLabel.textColor = .secondaryLabel
        footerLabel.font = .systemFont(ofSize: 14)
        footerLabel.numberOfLines = 0
        footerLabel.translatesAutoresizingMaskIntoConstraints = false

        // Create a separator line above the footer
        let separatorView = UIView()
        separatorView.backgroundColor = .separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false

        // Add elements to container
        footerContainer.addSubview(separatorView)
        footerContainer.addSubview(footerLabel)

        // Add container as direct subview of the main view
        view.addSubview(footerContainer)

        // Add constraints for separator within container
        NSLayoutConstraint.activate([
            separatorView.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            separatorView.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        // Configure footer label constraints within container
        NSLayoutConstraint.activate([
            footerLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            footerLabel.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor),
            footerLabel.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Position container at the bottom of the view
        NSLayoutConstraint.activate([
            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // Store container reference to adjust table view in setupTableViewWithFixedFooter
        tableBottomInset = 44.5  // Height of label plus separator

        // Ensure footer container is on top of everything
        view.bringSubviewToFront(footerContainer)
    }

    // Variable to track the table bottom inset needed for the footer
    private var tableBottomInset: CGFloat = 44.5
    // MARK: - Bulk Delete Support
    private var editMode: Bool = false
    private var selectedFeeds: Set<String> = []
    private var editButton: UIBarButtonItem!
    private var cancelButton: UIBarButtonItem!
    private var deleteButton: UIBarButtonItem!
    private func updateDeleteButton() {
        deleteButton.title = "Delete (\(selectedFeeds.count))"
        deleteButton.isEnabled = !selectedFeeds.isEmpty
    }

    // Setup navigation bar items for bulk delete
    private func setupNavigationBar() {
        // 'Select' toggles multi-select delete mode
        editButton = UIBarButtonItem(title: "Select", style: .plain, target: self, action: #selector(editButtonTapped))
        navigationItem.rightBarButtonItem = editButton
        // Prepare 'Cancel' and 'Delete' buttons
        cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(editButtonTapped))
        deleteButton = UIBarButtonItem(title: "Delete (0)", style: .plain, target: self, action: #selector(deleteButtonTapped))
        deleteButton.tintColor = .systemRed
        deleteButton.isEnabled = false
    }
    
    @objc private func editButtonTapped() {
        editMode.toggle()
        if editMode {
            // Enter selection mode
            editButton.title = "Cancel"
            navigationItem.setRightBarButtonItems([cancelButton, deleteButton], animated: true)
            selectedFeeds.removeAll()
            tableView.reloadData()
        } else {
            // Exit selection mode
            editButton.title = "Select"
            navigationItem.setRightBarButtonItems([editButton], animated: true)
            selectedFeeds.removeAll()
            tableView.reloadData()
        }
    }
    
    @objc private func deleteButtonTapped() {
        let alert = UIAlertController(title: "Delete Feeds", message: "Are you sure you want to delete the selected feeds?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.loadingIndicator.startAnimating()
            // Remove selected feeds from data and UI
            let feedsToRemove = Array(self.selectedFeeds)
            var remaining = self.feeds
            for url in feedsToRemove {
                if let idx = remaining.firstIndex(where: { $0.url == url }) {
                    remaining.remove(at: idx)
                }
            }
            self.feeds = remaining
            self.tableView.reloadData()
            // Perform backend deletions
            let group = DispatchGroup()
            for url in feedsToRemove {
                group.enter()
                StorageManager.shared.removeFeedFromFolder(feedURL: url, folderId: self.folder.id) { _ in
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.loadingIndicator.stopAnimating()
                // Exit selection mode
                self.editButtonTapped()
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    // Keep this for compatibility with existing calls
    private func setupTableFooter() {
        // This is now a no-op since we're using a fixed footer
    }

    // New method that properly sets up the table view with space for our fixed footer
    private func setupTableViewWithFixedFooter() {
        view.addSubview(tableView)

        // Create a constant bottom constraint we can reference later if needed
        let bottomConstraint = tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -tableBottomInset)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Adjust bottom constraint to make room for our fixed footer
            bottomConstraint
        ])

        // Add content inset to ensure all cells can be scrolled fully visible
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: tableBottomInset, right: 0)

        // Add a small amount of extra bottom padding to ensure the last cell is fully visible
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: tableBottomInset, right: 0)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("DEBUG: viewWillAppear called - feeds count: \(feeds.count), preloaded: \(preloaded)")

        // Track view controller lifecycle more clearly
        print("DEBUG: View controller state: view.window = \(view.window != nil ? "visible" : "not visible"), isViewLoaded = \(isViewLoaded), isBeingPresented = \(isBeingPresented), isMovingToParent = \(isMovingToParent)")

        // Save a reference count
        print("DEBUG: Feeds array retain count before viewWillAppear processing: \(CFGetRetainCount(feeds as CFArray))")

        // Verify the feeds array hasn't been deallocated or replaced
        if feeds.isEmpty {
            print("DEBUG: [WARNING] Feeds array is empty in viewWillAppear!")
        }

        // Create a local strong reference to prevent deallocation during the method
        let localFeedsReference = feeds
        print("DEBUG: Created local reference to feeds array with \(localFeedsReference.count) items")

        // If feeds were preloaded, just update the UI
        if preloaded {
            print("DEBUG: Using preloaded feeds")

            // Create a backup copy to ensure we don't lose data
            // This should help identify if the feeds array is being cleared elsewhere
            print("DEBUG: Creating backup copy of \(feeds.count) preloaded feeds")
            let feedsCopy = feeds

            // Check if we still have our feeds reference
            print("DEBUG: Feeds count before reload: \(feeds.count)")

            tableView.reloadData()
            emptyStateLabel.isHidden = !feeds.isEmpty

            // Print visible rows
            DispatchQueue.main.async { [weak self, feedsCopy] in
                guard let self = self else {
                    print("DEBUG: [CRITICAL] Self was deallocated during viewWillAppear async block!")
                    return
                }

                // Check if our feeds were emptied during the reload
                if self.feeds.isEmpty && !feedsCopy.isEmpty {
                    print("DEBUG: [CRITICAL] Feeds were cleared during table reload! Restoring from backup copy.")
                    self.feeds = feedsCopy
                }

                let visibleRows = self.tableView.indexPathsForVisibleRows?.count ?? 0
                print("DEBUG: viewWillAppear after reload - visible rows: \(visibleRows), tableView.numberOfRows: \(self.tableView.numberOfRows(inSection: 0))")
            }
        } else {
            // Otherwise load them normally
            print("DEBUG: Loading feeds from storage")
            loadFeeds()
        }

        // Make sure our layout is correct
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("DEBUG: viewWillDisappear called - feeds count: \(feeds.count), preloaded: \(preloaded)")

        // Track view controller lifecycle more clearly
        print("DEBUG: View controller state in viewWillDisappear: isBeingDismissed = \(isBeingDismissed), isMovingFromParent = \(isMovingFromParent)")

        // Save current feeds to backup in case they're cleared
        if !feeds.isEmpty {
            print("DEBUG: Creating backup of \(feeds.count) feeds before disappearing")
            let backupFeeds = feeds.map { ["title": $0.title, "url": $0.url] }
            UserDefaults.standard.set(backupFeeds, forKey: "folder_\(folder.id)_feeds_backup")
            UserDefaults.standard.synchronize() // Force immediate write

            // Create a persist-through-disappear copy
            let feedsCopy = feeds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, feedsCopy] in
                guard let self = self else { return }

                // If feeds were cleared, restore from our copy
                if self.feeds.isEmpty && !feedsCopy.isEmpty {
                    print("DEBUG: [CRITICAL] Feeds were cleared during view disappearing! Restoring from delayed backup copy.")
                    self.feeds = feedsCopy
                }
            }
        }

        // Log feed URLs to make sure we still have them
        for (index, feed) in feeds.enumerated() {
            print("DEBUG: Feed \(index): \(feed.title) - \(feed.url)")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        print("DEBUG: viewDidDisappear called - feeds count: \(feeds.count)")

        // Check if feeds were cleared during the disappear transition
        if feeds.isEmpty && preloaded {
            print("DEBUG: [CRITICAL] Feeds were emptied during view disappearing! Attempting to restore from backup.")

            // Try to restore from our backup
            if let backupData = UserDefaults.standard.array(forKey: "folder_\(folder.id)_feeds_backup") as? [[String: String]] {
                let restoredFeeds = backupData.map { dict -> RSSFeed in
                    RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                }

                if !restoredFeeds.isEmpty {
                    print("DEBUG: Restored \(restoredFeeds.count) feeds from backup")
                    feeds = restoredFeeds
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Ensure footer stays visible on top of everything else
        if let superview = footerLabel.superview {
            superview.bringSubviewToFront(footerLabel)
        }

        print("DEBUG: viewDidLayoutSubviews called - feeds count: \(feeds.count)")
        print("DEBUG: TableView frame: \(tableView.frame), contentSize: \(tableView.contentSize)")
        print("DEBUG: Footer frame: \(footerLabel.frame)")

        // Verify layout is correct
        if tableView.frame.maxY >= footerLabel.frame.minY {
            print("DEBUG: [WARNING] TableView overlaps with footer! Adjusting...")

            // Fix the layout by adjusting table view bottom constraint
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerLabel.frame.height + 10, right: 0)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("DEBUG: viewDidAppear called - feeds count: \(feeds.count)")

        // Do a final verification of feeds array
        if feeds.isEmpty && preloaded {
            print("DEBUG: [CRITICAL] Feeds are still empty in viewDidAppear despite being preloaded!")

            // Try to restore from backup one last time
            if let backupData = UserDefaults.standard.array(forKey: "folder_\(folder.id)_feeds_backup") as? [[String: String]] {
                let restoredFeeds = backupData.map { dict -> RSSFeed in
                    RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                }

                if !restoredFeeds.isEmpty {
                    print("DEBUG: Last-chance restoration of \(restoredFeeds.count) feeds in viewDidAppear")
                    feeds = restoredFeeds
                    tableView.reloadData()
                } else {
                    print("DEBUG: No backup feeds available for restoration in viewDidAppear")
                    // Force a reload as last resort
                    preloaded = false
                    loadFeeds()
                }
            }
        }

        // Force proper layout
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup Methods

    private func setupTableView() {
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupLoadingIndicator() {
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupEmptyStateLabel() {
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    // MARK: - Data Loading

    @objc private func folderUpdated() {
        // Always reload when folder is updated
        loadFeeds()
    }

    private func loadFeeds() {
        print("DEBUG: loadFeeds called - current feeds count: \(feeds.count), preloaded: \(preloaded)")
        print("DEBUG: Thread for loadFeeds: \(Thread.isMainThread ? "main thread" : "background thread")")
        print("DEBUG: Stack trace for loadFeeds:")
        Thread.callStackSymbols.forEach { print("DEBUG: \($0)") }

        // If already preloaded, just update UI and don't fetch again
        if preloaded {
            print("DEBUG: Using preloaded feeds in loadFeeds()")

            // Make a strong copy to prevent deallocation during table reload
            let feedsCopy = feeds

            // Check if somehow our feeds were cleared between the check and the next line
            if feeds.isEmpty && !feedsCopy.isEmpty {
                print("DEBUG: [CRITICAL] Feeds were cleared between preloaded check and UI update! Restoring.")
                feeds = feedsCopy
            }

            tableView.reloadData()
            emptyStateLabel.isHidden = !feeds.isEmpty

            // Log feed URLs to verify they're still there
            for (index, feed) in feeds.enumerated() {
                print("DEBUG: Preloaded feed \(index): \(feed.title) - \(feed.url)")
            }

            return
        }

        // Don't load again if already loading
        if isLoading {
            print("DEBUG: Already loading feeds, skipping duplicate load")
            return
        }

        print("DEBUG: Starting to load feeds from storage")
        isLoading = true
        loadingIndicator.startAnimating()
        emptyStateLabel.isHidden = true

        // Save the caller info for tracking
        let callerThread = Thread.current
        print("DEBUG: Loading feeds from caller thread: \(callerThread), isMain: \(Thread.isMainThread)")

        // Make a local variable to track if we've called the callback yet
        var callbackCalled = false

        // Set a debug timer to detect potential deadlocks or long operations
        let startTime = Date()

        // Set up a watchdog timer to detect if the API call takes too long
        let watchdogWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, !callbackCalled else { return }

            print("DEBUG: [WARNING] Feed loading watchdog timer fired after 5 seconds - API call may be stuck!")
            print("DEBUG: Current loading state: isLoading = \(self.isLoading), preloaded = \(self.preloaded), feeds count = \(self.feeds.count)")

            // Try to load from backup if available
            if self.feeds.isEmpty, let backupData = UserDefaults.standard.array(forKey: "folder_\(self.folder.id)_feeds_backup") as? [[String: String]] {
                print("DEBUG: Loading feeds from backup in watchdog timer")
                let restoredFeeds = backupData.map { dict -> RSSFeed in
                    RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                }

                if !restoredFeeds.isEmpty {
                    DispatchQueue.main.async {
                        print("DEBUG: Restored \(restoredFeeds.count) feeds from backup in watchdog timer")
                        self.feeds = restoredFeeds
                        self.preloaded = true
                        self.isLoading = false
                        self.loadingIndicator.stopAnimating()
                    }
                }
            }
        }

        // Schedule the watchdog timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: watchdogWorkItem)

        StorageManager.shared.getFeedsInFolder(folderId: folder.id) { [weak self] result in
            // Cancel the watchdog timer since we got a response
            watchdogWorkItem.cancel()

            callbackCalled = true

            let elapsedTime = Date().timeIntervalSince(startTime)
            print("DEBUG: API call completed in \(elapsedTime) seconds")
            print("DEBUG: API callback thread: \(Thread.isMainThread ? "main thread" : "background thread")")

            guard let self = self else {
                print("DEBUG: [CRITICAL] Self was deallocated during API callback")
                return
            }

            // Set as preloaded even if view is not visible, so data is ready when view becomes visible again
            self.preloaded = true
            print("DEBUG: Feeds loaded from API, setting preloaded = true")

            // Make a strong reference to keep our context
            let storngSelf = self

            DispatchQueue.main.async {
                storngSelf.isLoading = false
                storngSelf.loadingIndicator.stopAnimating()
                print("DEBUG: Processing API result on main thread")

                switch result {
                case .success(let folderFeeds):
                    print("DEBUG: Successfully loaded \(folderFeeds.count) feeds from folder")

                    // Log each feed before updating
                    for (index, feed) in folderFeeds.enumerated() {
                        print("DEBUG: Loaded feed \(index): \(feed.title) - \(feed.url)")
                    }

                    // Save to backup immediately
                    if !folderFeeds.isEmpty {
                        let backupFeeds = folderFeeds.map { ["title": $0.title, "url": $0.url] }
                        UserDefaults.standard.set(backupFeeds, forKey: "folder_\(storngSelf.folder.id)_feeds_backup")
                        UserDefaults.standard.synchronize()
                        print("DEBUG: Saved \(folderFeeds.count) feeds to UserDefaults backup")
                    }

                    // Sort the feeds by name but use a temporary variable
                    let sortedFeeds = folderFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }

                    // Check if we got empty result but have a backup
                    if sortedFeeds.isEmpty {
                        print("DEBUG: [WARNING] Got empty feeds result from API, checking backup...")

                        if let backupData = UserDefaults.standard.array(forKey: "folder_\(storngSelf.folder.id)_feeds_backup") as? [[String: String]] {
                            let restoredFeeds = backupData.map { dict -> RSSFeed in
                                RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                            }

                            if !restoredFeeds.isEmpty {
                                print("DEBUG: Using \(restoredFeeds.count) feeds from backup instead of empty API result")
                                storngSelf.feeds = restoredFeeds
                            } else {
                                storngSelf.feeds = sortedFeeds
                            }
                        } else {
                            storngSelf.feeds = sortedFeeds
                        }
                    } else {
                        // Use our sorted result
                        storngSelf.feeds = sortedFeeds
                    }

                    // Always update UI regardless of visibility state
                    storngSelf.tableView.reloadData()

                    // Show empty state if needed
                    storngSelf.emptyStateLabel.isHidden = !storngSelf.feeds.isEmpty

                    // Verify feeds are still present after UI update
                    print("DEBUG: After API update UI, feeds count: \(storngSelf.feeds.count)")

                case .failure(let error):
                    print("DEBUG: Error loading feeds in folder: \(error.localizedDescription)")

                    // Try to load from backup first
                    if let backupData = UserDefaults.standard.array(forKey: "folder_\(storngSelf.folder.id)_feeds_backup") as? [[String: String]] {
                        let restoredFeeds = backupData.map { dict -> RSSFeed in
                            RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                        }

                        if !restoredFeeds.isEmpty {
                            print("DEBUG: Restored \(restoredFeeds.count) feeds from backup after API error")
                            storngSelf.feeds = restoredFeeds
                            storngSelf.tableView.reloadData()
                            storngSelf.emptyStateLabel.isHidden = true
                            return
                        }
                    }

                    // If no backup, clear feeds
                    storngSelf.feeds = []

                    // Always update UI regardless of visibility state
                    storngSelf.showError("Failed to load feeds in folder")
                    storngSelf.tableView.reloadData()
                    storngSelf.emptyStateLabel.text = "Failed to load feeds"
                    storngSelf.emptyStateLabel.isHidden = false
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

    // MARK: - UITableViewDataSource Methods

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = feeds.count
        print("DEBUG: numberOfRowsInSection called - feeds count: \(count), preloaded: \(preloaded)")

        // If we have no feeds but should have them (preloaded=true), try to get them back
        if count == 0 && preloaded {
            print("DEBUG: Feed count is 0 but should have feeds!")

            // Try to restore from backup
            if let restored = restoreFeeds() {
                // Update the feeds array - this will trigger UI refresh
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.feeds = restored
                }
                return restored.count
            }

            // If we couldn't restore, force a reload
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.preloaded = false
                self.loadFeeds()
            }
        }

        return max(0, count)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderFeedCell", for: indexPath)

        print("DEBUG: cellForRowAt called for row \(indexPath.row), feeds count: \(feeds.count)")

        // Safety check to prevent index out of bounds errors
        guard indexPath.row < feeds.count else {
            print("DEBUG: [WARNING] Requested cell at index \(indexPath.row) but feeds array only has \(feeds.count) items")

            var config = cell.defaultContentConfiguration()
            config.text = "Loading..."
            cell.contentConfiguration = config

            // Try to restore from backup if we have an empty feeds array but should have items
            if feeds.isEmpty && preloaded {
                print("DEBUG: Attempting to restore feeds in cellForRowAt because index was out of bounds")

                if let backupData = UserDefaults.standard.array(forKey: "folder_\(folder.id)_feeds_backup") as? [[String: String]] {
                    let restoredFeeds = backupData.map { dict -> RSSFeed in
                        RSSFeed(url: dict["url"] ?? "", title: dict["title"] ?? "Untitled Feed", lastUpdated: Date())
                    }

                    if !restoredFeeds.isEmpty {
                        print("DEBUG: Restored \(restoredFeeds.count) feeds from backup in cellForRowAt")

                        // Update feeds on main thread
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.feeds = restoredFeeds
                            self.tableView.reloadData()
                        }
                    }
                }
            }

            return cell
        }

        let feed = feeds[indexPath.row]
        print("DEBUG: Configuring cell for feed: \(feed.title)")

        var config = cell.defaultContentConfiguration()
        config.text = feed.title
        config.secondaryText = feed.url
        cell.contentConfiguration = config

        // Set an identifier tag on the cell to help with debugging
        cell.tag = indexPath.row + 1000

        // Verify feed object is still valid after configuration
        DispatchQueue.main.async { [weak self, weak cell, feed] in
            guard let _ = self, let cell = cell else { return }

            // If this feed still exists in our array, mark the cell as good
            if cell.tag == indexPath.row + 1000 {
                print("DEBUG: Cell \(indexPath.row) still showing feed: \(feed.title)")
            }
        }

        return cell
    }

    // MARK: - UITableViewDelegate Methods

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if editMode {
            // In selection mode, toggle checkmark
            let feed = feeds[indexPath.row]
            selectedFeeds.insert(feed.url)
            if let cell = tableView.cellForRow(at: indexPath) {
                cell.accessoryType = .checkmark
            }
            updateDeleteButton()
        } else {
            // Normal mode: no bulk action
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if editMode {
            let feed = feeds[indexPath.row]
            selectedFeeds.remove(feed.url)
            if let cell = tableView.cellForRow(at: indexPath) {
                cell.accessoryType = .none
            }
            updateDeleteButton()
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Safety check
            guard indexPath.row < feeds.count else { return }

            let feed = feeds[indexPath.row]

            // Show loading indicator while removing feed
            loadingIndicator.startAnimating()

            // First update the UI immediately to maintain responsiveness
            var updatedFeeds = feeds
            updatedFeeds.remove(at: indexPath.row)
            feeds = updatedFeeds
            tableView.deleteRows(at: [indexPath], with: .fade)

            // Remove feed from folder in the backend
            StorageManager.shared.removeFeedFromFolder(feedURL: feed.url, folderId: folder.id) { [weak self] result in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    self.loadingIndicator.stopAnimating()

                    switch result {
                    case .success(_):
                        // No need to reload - we've already updated the UI
                        break
                    case .failure(let error):
                        // Show error and reload to restore correct state
                        self.showError("Failed to remove feed from folder: \(error.localizedDescription)")
                        self.loadFeeds() // Reload to get correct state
                    }
                }
            }
        }
    }
}

// MARK: - Unfoldered Feeds View Controller

class UnfolderedFeedsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let feeds: [RSSFeed]
    private var selectedFeeds: Set<String> = []
    private var editMode = false
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "UnfolderedFeedCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.allowsMultipleSelection = true
        return table
    }()
    
    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    init(feeds: [RSSFeed]) {
        self.feeds = feeds
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Unorganized Feeds"
        view.backgroundColor = AppColors.background
        setupTableView()
        setupNavigationBar()
    }
    
    private func setupTableView() {
        view.addSubview(instructionLabel)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigationBar() {
        // Add "Select" button on the right
        let editButton = UIBarButtonItem(
            title: "Select",
            style: .plain,
            target: self,
            action: #selector(editButtonTapped)
        )
        navigationItem.rightBarButtonItem = editButton
        
        // Create a custom back button with the standard back chevron
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonTapped)
        )
        navigationItem.leftBarButtonItem = backButton
    }
    
    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func editButtonTapped() {
        editMode = !editMode
        
        // Update UI based on mode
        if editMode {
            navigationItem.rightBarButtonItem?.title = "Cancel"
            instructionLabel.text = "Select feeds to add to a folder"
            instructionLabel.isHidden = false
            
            // Add "Select All" button
            let selectAllButton = UIBarButtonItem(
                title: "Select All",
                style: .plain,
                target: self,
                action: #selector(selectAllButtonTapped)
            )
            
            // Add back button with chevron
            let backButton = UIBarButtonItem(
                image: UIImage(systemName: "chevron.left"),
                style: .plain,
                target: self,
                action: #selector(backButtonTapped)
            )
            
            // Set both buttons
            navigationItem.leftBarButtonItems = [backButton, selectAllButton]
            
            // Add "Add to Folder" button
            let addToFolderButton = UIBarButtonItem(
                title: "Add (0)",
                style: .done,
                target: self,
                action: #selector(addToFolderButtonTapped)
            )
            addToFolderButton.isEnabled = false
            navigationItem.setRightBarButtonItems([navigationItem.rightBarButtonItem!, addToFolderButton], animated: true)
            
            // Ensure back button remains visible
            navigationItem.hidesBackButton = false
            
            // Reset selection
            selectedFeeds.removeAll()
            tableView.reloadData()
        } else {
            // Return to normal mode
            navigationItem.setRightBarButtonItems([navigationItem.rightBarButtonItem!], animated: true)
            
            // Reset left button to just back button with chevron
            let backButton = UIBarButtonItem(
                image: UIImage(systemName: "chevron.left"),
                style: .plain,
                target: self,
                action: #selector(backButtonTapped)
            )
            navigationItem.leftBarButtonItem = backButton
            
            instructionLabel.isHidden = true
            
            // Deselect all rows
            for row in 0..<feeds.count {
                let indexPath = IndexPath(row: row, section: 0)
                if tableView.cellForRow(at: indexPath)?.accessoryType == .checkmark {
                    tableView.cellForRow(at: indexPath)?.accessoryType = .none
                }
                tableView.deselectRow(at: indexPath, animated: false)
            }
            
            selectedFeeds.removeAll()
        }
    }
    
    @objc private func selectAllButtonTapped() {
        if selectedFeeds.count == feeds.count {
            // Deselect all
            selectedFeeds.removeAll()
            for row in 0..<feeds.count {
                let indexPath = IndexPath(row: row, section: 0)
                tableView.deselectRow(at: indexPath, animated: true)
                if let cell = tableView.cellForRow(at: indexPath) {
                    cell.accessoryType = .none
                }
            }
            navigationItem.leftBarButtonItem?.title = "Select All"
        } else {
            // Select all
            for (index, feed) in feeds.enumerated() {
                selectedFeeds.insert(feed.url)
                let indexPath = IndexPath(row: index, section: 0)
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
                if let cell = tableView.cellForRow(at: indexPath) {
                    cell.accessoryType = .checkmark
                }
            }
            navigationItem.leftBarButtonItem?.title = "Deselect All"
        }
        
        updateAddButton()
    }
    
    private func updateAddButton() {
        if let addButton = navigationItem.rightBarButtonItems?.last {
            let count = selectedFeeds.count
            addButton.title = count > 0 ? "Add (\(count))" : "Add"
            addButton.isEnabled = count > 0
        }
    }
    
    @objc private func addToFolderButtonTapped() {
        if selectedFeeds.isEmpty {
            return
        }
        
        // Fetch available folders
        StorageManager.shared.getFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let folders):
                if folders.isEmpty {
                    self.showCreateFolderDialog(for: Array(self.selectedFeeds))
                } else {
                    self.showSelectFolderDialog(for: Array(self.selectedFeeds), folders: folders)
                }
            case .failure(let error):
                self.showError("Failed to load folders: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - UITableViewDataSource Methods
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return feeds.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UnfolderedFeedCell", for: indexPath)
        
        let feed = feeds[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = feed.title
        config.secondaryText = feed.url
        cell.contentConfiguration = config
        
        // Set the cell's selection state
        if editMode && selectedFeeds.contains(feed.url) {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }
        
        return cell
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let feed = feeds[indexPath.row]
        
        if editMode {
            // In edit mode, allow multi-selection
            selectedFeeds.insert(feed.url)
            if let cell = tableView.cellForRow(at: indexPath) {
                cell.accessoryType = .checkmark
            }
            updateAddButton()
            
            // Update "Select All" button
            if selectedFeeds.count == feeds.count {
                navigationItem.leftBarButtonItem?.title = "Deselect All"
            }
        } else {
            // In normal mode, show folder selection for single feed
            tableView.deselectRow(at: indexPath, animated: true)
            showFolderSelectionDialog(for: feed)
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if editMode {
            // Only handle deselection in edit mode
            let feed = feeds[indexPath.row]
            selectedFeeds.remove(feed.url)
            
            if let cell = tableView.cellForRow(at: indexPath) {
                cell.accessoryType = .none
            }
            
            updateAddButton()
            
            // Update "Select All" button
            if selectedFeeds.count < feeds.count {
                navigationItem.leftBarButtonItem?.title = "Select All"
            }
        }
    }
    
    // MARK: - Folder Selection Handling
    
    private func showFolderSelectionDialog(for feed: RSSFeed) {
        // Fetch available folders
        StorageManager.shared.getFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let folders):
                if folders.isEmpty {
                    self.showCreateFolderDialog(for: [feed.url])
                } else {
                    self.showSelectFolderDialog(for: [feed.url], folders: folders)
                }
            case .failure(let error):
                self.showError("Failed to load folders: \(error.localizedDescription)")
            }
        }
    }
    
    private func showCreateFolderDialog(for feedURLs: [String]) {
        let alert = UIAlertController(
            title: "No Folders",
            message: "You don't have any folders yet. Create a new folder for these feeds?",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Folder Name"
        }
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let folderName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !folderName.isEmpty else {
                return
            }
            
            // Create new folder and add feed to it
            StorageManager.shared.createFolder(name: folderName) { result in
                switch result {
                case .success(let newFolder):
                    // Add all selected feeds to the new folder
                    let group = DispatchGroup()
                    var errors: [Error] = []
                    
                    for feedURL in feedURLs {
                        group.enter()
                        StorageManager.shared.addFeedToFolder(feedURL: feedURL, folderId: newFolder.id) { result in
                            switch result {
                            case .success(_):
                                break
                            case .failure(let error):
                                errors.append(error)
                            }
                            group.leave()
                        }
                    }
                    
                    group.notify(queue: .main) { 
                        if errors.isEmpty {
                            // All feeds added successfully
                            NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                            
                            // Exit edit mode
                            if self?.editMode == true {
                                self?.editButtonTapped()
                            }
                        } else {
                            self?.showError("Failed to add some feeds to folder")
                        }
                    }
                case .failure(let error):
                    self?.showError("Failed to create folder: \(error.localizedDescription)")
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showSelectFolderDialog(for feedURLs: [String], folders: [FeedFolder]) {
        let alert = UIAlertController(
            title: "Add to Folder",
            message: "Select a folder for \(feedURLs.count) feed\(feedURLs.count > 1 ? "s" : "")",
            preferredStyle: .actionSheet
        )
        
        // Add actions for each folder
        for folder in folders {
            alert.addAction(UIAlertAction(title: folder.name, style: .default) { [weak self] _ in
                // Add feeds to selected folder
                let group = DispatchGroup()
                var errors: [Error] = []
                
                for feedURL in feedURLs {
                    group.enter()
                    StorageManager.shared.addFeedToFolder(feedURL: feedURL, folderId: folder.id) { result in
                        switch result {
                        case .success(_):
                            break
                        case .failure(let error):
                            errors.append(error)
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    if errors.isEmpty {
                        // All feeds added successfully
                        NotificationCenter.default.post(name: Notification.Name("feedFoldersUpdated"), object: nil)
                        
                        // Exit edit mode
                        if self?.editMode == true {
                            self?.editButtonTapped()
                        }
                    } else {
                        self?.showError("Failed to add some feeds to folder")
                    }
                }
            })
        }
        
        // Add option to create new folder
        alert.addAction(UIAlertAction(title: "Create New Folder", style: .default) { [weak self] _ in
            self?.showCreateFolderDialog(for: feedURLs)
        })
        
        // Add cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = tableView
            if let selectedIndexPath = tableView.indexPathForSelectedRow {
                popoverController.sourceRect = tableView.rectForRow(at: selectedIndexPath)
            } else {
                popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
        }
        
        present(alert, animated: true)
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