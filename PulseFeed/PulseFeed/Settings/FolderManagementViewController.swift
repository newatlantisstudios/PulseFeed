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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(foldersUpdated),
            name: Notification.Name("feedFoldersUpdated"),
            object: nil
        )
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
        navigationController?.pushViewController(folderFeedsVC, animated: true)
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

class FolderFeedsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let folder: FeedFolder
    private var feeds: [RSSFeed] = []
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FolderFeedCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    init(folder: FeedFolder) {
        self.folder = folder
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = folder.name
        view.backgroundColor = AppColors.background
        setupTableView()
        loadFeeds()
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
    
    private func loadFeeds() {
        StorageManager.shared.getFeedsInFolder(folderId: folder.id) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let folderFeeds):
                self.feeds = folderFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }
                self.tableView.reloadData()
            case .failure(let error):
                print("Error loading feeds in folder: \(error.localizedDescription)")
                self.showError("Failed to load feeds in folder")
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderFeedCell", for: indexPath)
        
        let feed = feeds[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = feed.title
        config.secondaryText = feed.url
        cell.contentConfiguration = config
        
        return cell
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let feed = feeds[indexPath.row]
            
            // Remove feed from folder
            StorageManager.shared.removeFeedFromFolder(feedURL: feed.url, folderId: folder.id) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(_):
                    // Reload the feeds
                    self.loadFeeds()
                case .failure(let error):
                    self.showError("Failed to remove feed from folder: \(error.localizedDescription)")
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