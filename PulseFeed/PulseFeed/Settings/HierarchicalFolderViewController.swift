import UIKit

class HierarchicalFolderViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
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
    
    private var allFolders: [HierarchicalFolder] = []
    private var currentFolders: [HierarchicalFolder] = [] // Folders to display at current level
    private var parentFolder: HierarchicalFolder? // Current parent folder (nil if at root)
    private var isRootLevel: Bool { return parentFolder == nil }
    
    private var feeds: [RSSFeed] = []
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = parentFolder?.name ?? "Folders"
        view.backgroundColor = AppColors.background
        setupNavigationBar()
        setupTableView()
        setupNotifications()
        setupRefreshControl()

        // Always add a back button (for both root and subfolders)
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonPressed)
        )
        backButton.tintColor = .systemBlue

        if let leftBarButtonItem = navigationItem.leftBarButtonItem {
            navigationItem.leftBarButtonItems = [backButton, leftBarButtonItem]
        } else {
            navigationItem.leftBarButtonItem = backButton
        }

        // Load folders from UserDefaults immediately for responsive UI
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                let loadedFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                print("Loaded \(loadedFolders.count) folders directly from UserDefaults on load")
                self.allFolders = loadedFolders

                // Filter folders for current level
                if let parent = self.parentFolder {
                    // Get folders with this parent
                    self.currentFolders = loadedFolders.filter { $0.parentId == parent.id }
                                          .sorted { $0.sortIndex < $1.sortIndex }
                } else {
                    // Get root folders
                    self.currentFolders = loadedFolders.filter { $0.parentId == nil }
                                          .sorted { $0.sortIndex < $1.sortIndex }
                }

                self.tableView.reloadData()
            } catch {
                print("Error decoding folders from UserDefaults on load: \(error.localizedDescription)")
            }
        }

        // Force sync from CloudKit on first load to ensure we have the latest folders
        if StorageManager.shared.method == .cloudKit {
            print("DEBUG-PERSIST: Forcing CloudKit sync for hierarchical folders")
            StorageManager.shared.syncHierarchicalFolders { success in
                print("DEBUG-PERSIST: CloudKit sync completed with success: \(success)")
                if success {
                    DispatchQueue.main.async {
                        self.loadFolders()
                    }
                }
            }
        } else {
            // Force UserDefaults synchronization
            UserDefaults.standard.synchronize()
            // Then load folders
            self.loadFolders()

            // Also load feeds to ensure they're available for add feeds dialogs
            self.loadFeeds()
        }
    }

    private func setupRefreshControl() {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshFolders), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    @objc private func refreshFolders() {
        // Force reload folders
        UserDefaults.standard.synchronize() // Force sync of UserDefaults
        loadFolders()
        loadFeeds() // Also reload feeds
        tableView.refreshControl?.endRefreshing()
    }
    
    @objc private func backButtonPressed() {
        navigationController?.popViewController(animated: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // When view reappears, make sure to always refresh the folder data from source
        print("DEBUG-DELETE: View reappearing, forcing refresh of folder data")

        // First, synchronize UserDefaults to ensure we have latest data
        UserDefaults.standard.synchronize()

        // Then update our local folder with latest data
        StorageManager.shared.getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            if case .success(let folders) = result,
               let parentId = self.parentFolder?.id,
               let updatedFolder = folders.first(where: { $0.id == parentId }) {

                print("DEBUG-DELETE: Found updated parent folder with \(updatedFolder.feedURLs.count) feeds")
                self.parentFolder = updatedFolder
            }

            // Always reload folders and feeds
            DispatchQueue.main.async {
                self.loadFolders()
                self.loadFeeds()
            }
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupNavigationBar() {
        // Add button
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addButtonTapped)
        )
        
        navigationItem.rightBarButtonItem = addButton
        
        // We've removed edit and import buttons
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
        // Remove any existing observers first to prevent duplicates
        NotificationCenter.default.removeObserver(self, name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
        
        // Add the observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(foldersUpdated),
            name: Notification.Name("hierarchicalFoldersUpdated"),
            object: nil
        )
        
        print("Added notification observer for hierarchicalFoldersUpdated")
    }
    
    // MARK: - Data Loading Methods
    
    private func loadFolders() {
        print("Loading folders in view controller")
        
        // First try to load directly from UserDefaults for immediate response
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                let loadedFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                print("Loaded \(loadedFolders.count) folders directly from UserDefaults")
                self.allFolders = loadedFolders
                
                // Filter folders for current level
                if let parent = self.parentFolder {
                    // Get folders with this parent
                    self.currentFolders = loadedFolders.filter { $0.parentId == parent.id }
                                          .sorted { $0.sortIndex < $1.sortIndex }
                } else {
                    // Get root folders
                    self.currentFolders = loadedFolders.filter { $0.parentId == nil }
                                          .sorted { $0.sortIndex < $1.sortIndex }
                }
                
                self.tableView.reloadData()
            } catch {
                print("Error decoding folders from UserDefaults: \(error.localizedDescription)")
            }
        }
        
        // Also load from StorageManager to ensure we have the latest data
        StorageManager.shared.getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let loadedFolders):
                print("Loaded \(loadedFolders.count) folders from StorageManager")
                self.allFolders = loadedFolders
                
                // Filter folders for current level
                if let parent = self.parentFolder {
                    // Get folders with this parent
                    self.currentFolders = loadedFolders.filter { $0.parentId == parent.id }
                                          .sorted { $0.sortIndex < $1.sortIndex }
                } else {
                    // Get root folders
                    self.currentFolders = loadedFolders.filter { $0.parentId == nil }
                                          .sorted { $0.sortIndex < $1.sortIndex }
                }
                
                self.tableView.reloadData()
                
            case .failure(let error):
                print("Error loading folders from StorageManager: \(error.localizedDescription)")
                // Only show error if we don't already have folders from UserDefaults
                if self.allFolders.isEmpty {
                    self.showError("Failed to load folders: \(error.localizedDescription)")
                    self.currentFolders = []
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    private func loadFeeds() {
        print("DEBUG-FEEDS: Loading RSS feeds for feed selection")
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }

            switch result {
            case .success(let loadedFeeds):
                print("DEBUG-FEEDS: Successfully loaded \(loadedFeeds.count) RSS feeds")
                self.feeds = loadedFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }

                // Log a few feeds for debugging
                if !loadedFeeds.isEmpty {
                    let sampleSize = min(3, loadedFeeds.count)
                    let sampleFeeds = Array(loadedFeeds.prefix(sampleSize))
                    print("DEBUG-FEEDS: Sample feeds: \(sampleFeeds.map { $0.title })")
                }

                self.tableView.reloadData()
            case .failure(let error):
                print("DEBUG-FEEDS: Error loading feeds: \(error.localizedDescription)")
                self.feeds = []
            }
        }
    }
    
    // MARK: - Action Methods
    
    @objc private func addButtonTapped() {
        let alert = UIAlertController(
            title: "Add New",
            message: nil,
            preferredStyle: .actionSheet
        )
        
        // Add folder option
        alert.addAction(UIAlertAction(title: "New Folder", style: .default) { [weak self] _ in
            self?.showCreateFolderDialog()
        })
        
        // Add feeds to current folder option (if not at root)
        if let currentFolder = parentFolder {
            alert.addAction(UIAlertAction(title: "Add Feeds to Folder", style: .default) { [weak self] _ in
                self?.showAddFeedsDialog(for: currentFolder)
            })
        }
        
        // Cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popoverController = alert.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(alert, animated: true)
    }
    
    // Edit button functionality removed
    
    // Import button functionality removed
    
    @objc private func foldersUpdated() {
        print("Received hierarchicalFoldersUpdated notification")
        DispatchQueue.main.async {
            self.loadFolders()
        }
    }

    
    private func importFolders() {
        StorageManager.shared.importFlatFoldersToHierarchical { [weak self] result in
            switch result {
            case .success(_):
                self?.loadFolders()
                self?.showInfo("Folders imported successfully")
            case .failure(let error):
                self?.showError("Failed to import folders: \(error.localizedDescription)")
            }
        }
    }
    
    private func showCreateFolderDialog() {
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
    
    private func createFolder(name: String) {
        print("Creating folder: \(name) with parent: \(parentFolder?.id ?? "root")")
        StorageManager.shared.createHierarchicalFolder(name: name, parentId: parentFolder?.id) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let newFolder):
                // Folder created successfully
                print("Folder created successfully: \(newFolder.name) with ID: \(newFolder.id)")
                
                // Force reload folders immediately instead of relying on notification
                DispatchQueue.main.async {
                    // Manual refresh to ensure the folders list is updated
                    self.refreshFolders()
                    
                    // Show success confirmation
                    self.showInfo("Folder '\(name)' created successfully")
                    
                    // Manually update currentFolders and UI if UserDefaults has the folder
                    if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
                        do {
                            let allFolders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                            self.allFolders = allFolders
                            
                            // Filter folders for current level
                            if let parent = self.parentFolder {
                                self.currentFolders = allFolders.filter { $0.parentId == parent.id }
                                                     .sorted { $0.sortIndex < $1.sortIndex }
                            } else {
                                self.currentFolders = allFolders.filter { $0.parentId == nil }
                                                     .sorted { $0.sortIndex < $1.sortIndex }
                            }
                            
                            print("Manually updated folders: \(self.currentFolders.count) folders at current level")
                            self.tableView.reloadData()
                        } catch {
                            print("Error decoding folders for manual update: \(error)")
                        }
                    }
                }
            case .failure(let error):
                print("Failed to create folder: \(error.localizedDescription)")
                self.showError("Failed to create folder: \(error.localizedDescription)")
            }
        }
    }
    
    private func showFolderOptions(for folder: HierarchicalFolder, at indexPath: IndexPath) {
        let alert = UIAlertController(title: folder.name, message: nil, preferredStyle: .actionSheet)
        
        // Open folder action
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            self?.openFolder(folder)
        })
        
        // Rename action
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.showRenameDialog(for: folder)
        })
        
        // Add subfolder action
        alert.addAction(UIAlertAction(title: "Add Subfolder", style: .default) { [weak self] _ in
            self?.showCreateSubfolderDialog(for: folder)
        })
        
        // Add feeds action
        alert.addAction(UIAlertAction(title: "Add Feeds", style: .default) { [weak self] _ in
            self?.showAddFeedsDialog(for: folder)
        })
        
        // View feeds action
        alert.addAction(UIAlertAction(title: "View Feeds", style: .default) { [weak self] _ in
            self?.showFeedsInFolder(folder)
        })
        
        // Move folder action
        alert.addAction(UIAlertAction(title: "Move Folder", style: .default) { [weak self] _ in
            self?.showMoveFolderDialog(for: folder)
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
    
    private func openFolder(_ folder: HierarchicalFolder) {
        let folderVC = HierarchicalFolderViewController()
        folderVC.parentFolder = folder
        
        // Create a custom back button with a title
        let backButton = UIBarButtonItem()
        backButton.title = "Back"
        navigationItem.backBarButtonItem = backButton
        
        navigationController?.pushViewController(folderVC, animated: true)
    }
    
    private func showRenameDialog(for folder: HierarchicalFolder) {
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
    
    private func showCreateSubfolderDialog(for parentFolder: HierarchicalFolder) {
        let alert = UIAlertController(
            title: "New Subfolder",
            message: "Enter a name for the new subfolder",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Subfolder Name"
        }
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let folderName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !folderName.isEmpty else {
                return
            }
            
            self?.createSubfolder(name: folderName, parentId: parentFolder.id)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func createSubfolder(name: String, parentId: String) {
        print("Creating subfolder: \(name) with parent ID: \(parentId)")
        StorageManager.shared.createHierarchicalFolder(name: name, parentId: parentId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let newFolder):
                // Subfolder created successfully
                print("Subfolder created successfully: \(newFolder.name) with ID: \(newFolder.id)")
                
                // Force reload folders immediately instead of relying on notification
                DispatchQueue.main.async {
                    self.loadFolders()
                    
                    // Show success confirmation
                    self.showInfo("Subfolder '\(name)' created successfully")
                }
            case .failure(let error):
                print("Failed to create subfolder: \(error.localizedDescription)")
                self.showError("Failed to create subfolder: \(error.localizedDescription)")
            }
        }
    }
    
    private func showAddFeedsDialog(for folder: HierarchicalFolder) {
        print("DEBUG-FEEDS: Showing add feeds dialog for folder: \(folder.name)")
        print("DEBUG-FEEDS: Total available feeds: \(feeds.count)")
        print("DEBUG-FEEDS: Folder currently has \(folder.feedURLs.count) feeds")

        // If no feeds are loaded, load them now
        if feeds.isEmpty {
            print("DEBUG-FEEDS: No feeds loaded yet, loading them now before showing dialog")
            StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
                guard let self = self else { return }

                switch result {
                case .success(let loadedFeeds):
                    print("DEBUG-FEEDS: Late-loaded \(loadedFeeds.count) feeds")
                    self.feeds = loadedFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }

                    // Now continue with showing the dialog with the loaded feeds
                    DispatchQueue.main.async {
                        self.continueShowingAddFeedsDialog(for: folder)
                    }

                case .failure(let error):
                    print("DEBUG-FEEDS: Error late-loading feeds: \(error.localizedDescription)")
                    self.feeds = []

                    // Show an error message
                    DispatchQueue.main.async {
                        self.showError("Could not load feeds. Please try again.")
                    }
                }
            }
        } else {
            // Feeds are already loaded, continue with showing the dialog
            continueShowingAddFeedsDialog(for: folder)
        }
    }

    private func continueShowingAddFeedsDialog(for folder: HierarchicalFolder) {
        // Get all feeds not in the current folder
        let folderFeedURLs = folder.feedURLs.map { StorageManager.shared.normalizeLink($0) }
        let unfolderedFeeds = feeds.filter { !folderFeedURLs.contains(StorageManager.shared.normalizeLink($0.url)) }

        print("DEBUG-FEEDS: Showing feed selection with \(unfolderedFeeds.count) available unfoldered feeds")

        // If no feeds are available, show an error
        if unfolderedFeeds.isEmpty {
            if feeds.isEmpty {
                showError("No feeds found in your system. Add RSS feeds first before adding to folders.")
            } else if folderFeedURLs.count == feeds.count {
                showError("All available feeds are already in this folder.")
            } else {
                showError("No additional feeds available to add to this folder.")
            }
            return
        }

        let feedSelectionVC = HierarchicalFeedSelectionViewController(
            feeds: unfolderedFeeds,
            folder: folder
        )
        navigationController?.pushViewController(feedSelectionVC, animated: true)
    }
    
    private func showFeedsInFolder(_ folder: HierarchicalFolder) {
        print("DEBUG: Showing feeds for folder: \(folder.name) (ID: \(folder.id))")
        print("DEBUG: Folder has \(folder.feedURLs.count) feeds: \(folder.feedURLs)")
        let folderFeedsVC = HierarchicalFolderFeedsViewController(folder: folder)
        navigationController?.pushViewController(folderFeedsVC, animated: true)
    }
    
    private func showMoveFolderDialog(for folder: HierarchicalFolder) {
        let destinationsVC = FolderDestinationViewController(
            folderToMove: folder,
            allFolders: allFolders
        )
        navigationController?.pushViewController(destinationsVC, animated: true)
    }
    
    private func confirmDeleteFolder(_ folder: HierarchicalFolder) {
        // Check if this folder has subfolders
        let hasSubfolders = allFolders.contains { $0.parentId == folder.id }
        print("DEBUG: Confirming delete for folder \(folder.name) (ID: \(folder.id)), hasSubfolders: \(hasSubfolders)")
        
        let message = hasSubfolders
            ? "Are you sure you want to delete the folder '\(folder.name)'? This folder contains subfolders."
            : "Are you sure you want to delete the folder '\(folder.name)'? This will not delete the feeds inside it."
        
        let alert = UIAlertController(
            title: "Delete Folder",
            message: message,
            preferredStyle: .alert
        )
        
        if hasSubfolders {
            // Option to delete with subfolders
            alert.addAction(UIAlertAction(title: "Delete With Subfolders", style: .destructive) { [weak self] _ in
                print("DEBUG: User selected to delete folder with subfolders")
                self?.deleteFolder(id: folder.id, deleteSubfolders: true)
            })
            
            // Option to delete just this folder
            alert.addAction(UIAlertAction(title: "Delete Only This Folder", style: .destructive) { [weak self] _ in
                print("DEBUG: User selected to delete folder without subfolders")
                self?.deleteFolder(id: folder.id, deleteSubfolders: false)
            })
        } else {
            // Simple delete action if no subfolders
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                print("DEBUG: User selected to delete folder (no subfolders)")
                self?.deleteFolder(id: folder.id, deleteSubfolders: false)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func updateFolder(_ folder: HierarchicalFolder) {
        StorageManager.shared.updateHierarchicalFolder(folder) { [weak self] result in
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
    
    private func deleteFolder(id: String, deleteSubfolders: Bool) {
        print("DEBUG: Starting deletion process for folder ID: \(id), deleteSubfolders: \(deleteSubfolders)")
        
        // First verify the folder exists before attempting deletion
        if let folder = allFolders.first(where: { $0.id == id }) {
            print("DEBUG: Found folder to delete: \(folder.name) (ID: \(folder.id))")
            
            // Check for subfolders before deleting
            let subfolders = allFolders.filter { $0.parentId == id }
            if !deleteSubfolders && !subfolders.isEmpty {
                print("DEBUG: Folder has \(subfolders.count) subfolders but deleteSubfolders is false")
                self.showError("Cannot delete folder with subfolders unless you choose to delete them too.")
                return
            }
            
            // Proceed with deletion
            StorageManager.shared.deleteHierarchicalFolder(id: id, deleteSubfolders: deleteSubfolders) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(_):
                    // Folder deleted successfully
                    print("DEBUG: Folder deleted successfully from storage")
                    
                    // Force refresh the UI by reloading data and then navigating back
                    DispatchQueue.main.async {
                        // Force synchronize UserDefaults
                        UserDefaults.standard.synchronize()
                        
                        // Force reload local data
                        self.refreshFolders()
                        
                        // Show success message
                        self.showInfo("Folder \(folder.name) deleted successfully")
                        
                        // If this is a subfolder view, navigate back after deleting the current folder
                        if folder.id == self.parentFolder?.id {
                            print("DEBUG: Deleted current folder, navigating back")
                            self.navigationController?.popViewController(animated: true)
                        }
                    }
                case .failure(let error):
                    print("DEBUG: Failed to delete folder: \(error.localizedDescription)")
                    self.showError("Failed to delete folder: \(error.localizedDescription)")
                }
            }
        } else {
            print("DEBUG: ERROR - Folder with ID \(id) not found for deletion")
            self.showError("Folder not found")
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
    
    private func showInfo(_ message: String) {
        let alert = UIAlertController(
            title: "Information",
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
        return currentFolders.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderCell", for: indexPath)
        
        let folder = currentFolders[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = folder.name
        
        // Count feeds and subfolders
        let feedCount = folder.feedURLs.count
        let subfolderCount = allFolders.filter { $0.parentId == folder.id }.count
        
        // Update secondary text
        var details = [String]()
        if feedCount > 0 {
            details.append("\(feedCount) \(feedCount == 1 ? "feed" : "feeds")")
        }
        if subfolderCount > 0 {
            details.append("\(subfolderCount) \(subfolderCount == 1 ? "subfolder" : "subfolders")")
        }
        config.secondaryText = details.joined(separator: ", ")
        
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let folder = currentFolders[indexPath.row]
        
        // Show actions for the selected folder
        let actionSheet = UIAlertController(title: folder.name, message: nil, preferredStyle: .actionSheet)
        
        // Open action
        actionSheet.addAction(UIAlertAction(title: "Open Folder", style: .default) { [weak self] _ in
            self?.openFolder(folder)
        })
        
        // Rename action
        actionSheet.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.showRenameDialog(for: folder)
        })
        
        // Add subfolder action
        actionSheet.addAction(UIAlertAction(title: "Add Subfolder", style: .default) { [weak self] _ in
            self?.showCreateSubfolderDialog(for: folder)
        })
        
        // Add feeds action
        actionSheet.addAction(UIAlertAction(title: "Add Feeds", style: .default) { [weak self] _ in
            self?.showAddFeedsDialog(for: folder)
        })
        
        // View feeds action
        actionSheet.addAction(UIAlertAction(title: "View Feeds", style: .default) { [weak self] _ in
            self?.showFeedsInFolder(folder)
        })
        
        // Delete action
        actionSheet.addAction(UIAlertAction(title: "Delete Folder", style: .destructive) { [weak self] _ in
            print("DEBUG: Delete option selected from folder menu for folder: \(folder.name)")
            self?.confirmDeleteFolder(folder)
        })
        
        // Cancel action
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.sourceView = tableView
            popoverController.sourceRect = tableView.rectForRow(at: indexPath)
        }
        
        present(actionSheet, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let folder = currentFolders[indexPath.row]
        
        // Delete action
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.confirmDeleteFolder(folder)
            completion(true)
        }
        deleteAction.backgroundColor = .systemRed
        
        // Edit action
        let editAction = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, completion in
            self?.showFolderOptions(for: folder, at: indexPath)
            completion(true)
        }
        editAction.backgroundColor = .systemBlue
        
        return UISwipeActionsConfiguration(actions: [deleteAction, editAction])
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // Reorder the folders
        let movedFolder = currentFolders[sourceIndexPath.row]
        currentFolders.remove(at: sourceIndexPath.row)
        currentFolders.insert(movedFolder, at: destinationIndexPath.row)
        
        // Update sort indices
        for (index, folder) in currentFolders.enumerated() {
            var updatedFolder = folder
            updatedFolder.sortIndex = index
            
            StorageManager.shared.reorderHierarchicalFolder(folderId: folder.id, newSortIndex: index) { result in
                if case .failure(let error) = result {
                    print("Failed to update folder sort index: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Folder Destination View Controller

class FolderDestinationViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let folderToMove: HierarchicalFolder
    private let allFolders: [HierarchicalFolder]
    private var filteredFolders: [HierarchicalFolder] = []
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "DestinationCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    init(folderToMove: HierarchicalFolder, allFolders: [HierarchicalFolder]) {
        self.folderToMove = folderToMove
        self.allFolders = allFolders
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Move Folder"
        view.backgroundColor = AppColors.background
        setupTableView()
        filterFolders()
        
        // Add a manual back button
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
    
    private func filterFolders() {
        // Filter out:
        // 1. The folder being moved
        // 2. All its descendants (to prevent circular references)
        // 3. Keep this list of descendants
        let descendantIds = FolderManager.getAllDescendantFolders(from: allFolders, forFolderId: folderToMove.id)
            .map { $0.id }
        
        filteredFolders = allFolders.filter { folder in
            folder.id != folderToMove.id && !descendantIds.contains(folder.id)
        }
        
        tableView.reloadData()
    }
    
    private func moveFolder(to destinationId: String?) {
        StorageManager.shared.moveHierarchicalFolder(folderId: folderToMove.id, toParentId: destinationId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                // Folder moved successfully
                self.navigationController?.popViewController(animated: true)
            case .failure(let error):
                self.showError("Failed to move folder: \(error.localizedDescription)")
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
        return 2 // Root level + other folders
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1 // Root level
        } else {
            return filteredFolders.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DestinationCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        
        if indexPath.section == 0 {
            // Root level option
            config.text = "Root Level"
            config.secondaryText = "Move to top level"
            
            // Show checkmark if the folder is already at root level
            cell.accessoryType = folderToMove.parentId == nil ? .checkmark : .none
        } else {
            // Other folder option
            let folder = filteredFolders[indexPath.row]
            config.text = folder.name
            
            // Get the full path
            let path = FolderManager.getFolderPath(from: allFolders, forFolderId: folder.id)
            config.secondaryText = path
            
            // Show checkmark if this is the current parent
            cell.accessoryType = folderToMove.parentId == folder.id ? .checkmark : .none
        }
        
        cell.contentConfiguration = config
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Root Level" : "Folders"
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 {
            // Move to root level
            moveFolder(to: nil)
        } else {
            // Move to selected folder
            let destinationFolder = filteredFolders[indexPath.row]
            moveFolder(to: destinationFolder.id)
        }
    }
}

// MARK: - Hierarchical Feed Selection View Controller

class HierarchicalFeedSelectionViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    private let feeds: [RSSFeed]
    private let folder: HierarchicalFolder
    private var selectedFeeds: Set<String> = []

    // Helper methods to keep compiler happy (these are stubs to make it compile)
    private func restoreFeeds() -> [RSSFeed]? {
        return nil
    }

    private func loadFeeds() {
        // Empty stub - this is just to satisfy the compiler
        print("Stub method called")
    }
    
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
        label.text = "📋 Tap multiple feeds below to select them, then press 'Add'"
        label.textAlignment = .center
        label.font = UIFont.boldSystemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    init(feeds: [RSSFeed], folder: HierarchicalFolder) {
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

        print("DEBUG-MULTI: Feed selection view loaded for folder: \(folder.name) (ID: \(folder.id))")
        print("DEBUG-MULTI: Current folder has \(folder.feedURLs.count) feeds: \(folder.feedURLs)")
        print("DEBUG-MULTI: Available feeds for selection: \(feeds.count)")
        if !feeds.isEmpty {
            print("DEBUG-MULTI: Available feed URLs: \(feeds.map { $0.url })")
        }

        setupTableView()
        setupNavigationBar()

        // Explicitly ensure multiple selection is enabled
        tableView.allowsMultipleSelection = true
        tableView.allowsMultipleSelectionDuringEditing = true
        print("DEBUG-MULTI: tableView.allowsMultipleSelection = \(tableView.allowsMultipleSelection)")
        print("DEBUG-MULTI: tableView.allowsMultipleSelectionDuringEditing = \(tableView.allowsMultipleSelectionDuringEditing)")

        // This will activate edit mode if it helps with multiple selection
        tableView.setEditing(true, animated: false)
        print("DEBUG-MULTI: tableView.isEditing = \(tableView.isEditing)")
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
        // Add text "Add" button on the right with tint color to make it more noticeable
        let doneButton = UIBarButtonItem(
            title: "Add (0)",
            style: .plain,
            target: self,
            action: #selector(doneButtonTapped)
        )
        doneButton.tintColor = .systemBlue
        navigationItem.rightBarButtonItem = doneButton

        // Add back button
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonPressed)
        )
        backButton.tintColor = .systemBlue

        // Set back button (no Select All button)
        navigationItem.leftBarButtonItem = backButton
    }
    
    @objc private func backButtonPressed() {
        navigationController?.popViewController(animated: true)
    }
    
    private func updateDoneButton() {
        let count = selectedFeeds.count
        navigationItem.rightBarButtonItem?.title = count > 0 ? "Add (\(count))" : "Add (0)"
        navigationItem.rightBarButtonItem?.isEnabled = count > 0
    }
    
    // No longer using selectAllButtonTapped - We're using direct selection
    
    @objc private func doneButtonTapped() {
        if selectedFeeds.isEmpty {
            print("DEBUG: No feeds selected, returning to previous screen")
            navigationController?.popViewController(animated: true)
            return
        }
        
        print("DEBUG: Adding \(selectedFeeds.count) feeds to folder \(folder.name) (ID: \(folder.id))")
        print("DEBUG: Selected feed URLs: \(selectedFeeds)")
        
        // Show loading indicator
        let loadingAlert = UIAlertController(
            title: "Adding Feeds",
            message: "Please wait while the feeds are added to the folder...",
            preferredStyle: .alert
        )
        present(loadingAlert, animated: true)
        
        // Add selected feeds to folder
        let group = DispatchGroup()
        var errors: [Error] = []
        var successfulAdditions: [String] = []
        
        // First, verify the folder exists in current data
        print("DEBUG: Verifying folder exists before adding feeds")
        checkFolderExists(folder.id) { [weak self] exists in
            guard let self = self else { return }
            
            if !exists {
                print("DEBUG: ERROR - Folder not found in system before adding feeds!")
                loadingAlert.dismiss(animated: true) {
                    self.showError("Folder not found. Please try refreshing the app.")
                }
                return
            }
            
            print("DEBUG: Folder verified, proceeding with feed addition")
            
            // Debug: Normalize all URLs first for consistency
            let normalizedSelectedFeeds = self.selectedFeeds.map { StorageManager.shared.normalizeLink($0) }
            print("DEBUG: Normalized selected feed URLs: \(normalizedSelectedFeeds)")
            
            // Add each feed to the folder
            for feedURL in self.selectedFeeds {
                let normalizedURL = StorageManager.shared.normalizeLink(feedURL)
                print("DEBUG: Processing feed: \(feedURL) (normalized: \(normalizedURL))")
                
                group.enter()
                StorageManager.shared.addFeedToHierarchicalFolder(feedURL: feedURL, folderId: self.folder.id) { result in
                    switch result {
                    case .success(_):
                        print("DEBUG: Successfully added feed: \(feedURL)")
                        successfulAdditions.append(feedURL)
                    case .failure(let error):
                        print("DEBUG: Failed to add feed: \(feedURL) - Error: \(error.localizedDescription)")
                        errors.append(error)
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                
                print("DEBUG: Completed adding feeds. Successes: \(successfulAdditions.count), Errors: \(errors.count)")
                
                // Dismiss loading alert
                loadingAlert.dismiss(animated: true) {
                    if errors.isEmpty {
                        print("DEBUG: All feeds added successfully, updating UI")
                        
                        // Force save to UserDefaults to ensure folders are updated immediately
                        self.ensureUserDefaultsUpdated()
                        
                        // Post notification that folders have been updated
                        NotificationCenter.default.post(name: Notification.Name("hierarchicalFoldersUpdated"), object: nil)
                        
                        // Verify the folder now has the added feeds
                        self.verifyFeedsAdded(successfulAdditions)
                        
                        // Show success message and then navigate back
                        let successAlert = UIAlertController(
                            title: "Success",
                            message: "Added \(self.selectedFeeds.count) feeds to the folder",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                            self.navigationController?.popViewController(animated: true)
                        })
                        self.present(successAlert, animated: true)
                    } else {
                        // Show error
                        print("DEBUG: Some feeds failed to add: \(errors.map { $0.localizedDescription })")
                        self.showError("Failed to add some feeds to folder: \(errors.first?.localizedDescription ?? "Unknown error")")
                    }
                }
            }
        }
    }
    
    private func checkFolderExists(_ folderId: String, completion: @escaping (Bool) -> Void) {
        // First check UserDefaults
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                let folders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                if folders.contains(where: { $0.id == folderId }) {
                    print("DEBUG: Folder found in UserDefaults")
                    completion(true)
                    return
                }
            } catch {
                print("DEBUG: Error decoding folders from UserDefaults: \(error)")
            }
        }
        
        // If not in UserDefaults, check StorageManager
        StorageManager.shared.getHierarchicalFolders { result in
            switch result {
            case .success(let folders):
                let exists = folders.contains(where: { $0.id == folderId })
                print("DEBUG: Folder exists in StorageManager: \(exists)")
                completion(exists)
            case .failure(let error):
                print("DEBUG: Error checking if folder exists: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    private func ensureUserDefaultsUpdated() {
        print("DEBUG: Ensuring UserDefaults is updated with the latest folder data")
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                var folders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                print("DEBUG: Found \(folders.count) folders in UserDefaults")
                
                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    print("DEBUG: Found folder at index \(index): \(folders[index].name)")
                    print("DEBUG: Current feeds in folder: \(folders[index].feedURLs.count)")
                    
                    // Add selected feeds to folder
                    var feedsAdded = 0
                    for feedURL in selectedFeeds {
                        // Add if not already present
                        let normalizedURL = StorageManager.shared.normalizeLink(feedURL)
                        if !folders[index].feedURLs.contains(where: { StorageManager.shared.normalizeLink($0) == normalizedURL }) {
                            folders[index].feedURLs.append(normalizedURL)
                            feedsAdded += 1
                        }
                    }
                    
                    print("DEBUG: Added \(feedsAdded) feeds to UserDefaults data")
                    print("DEBUG: New feeds count: \(folders[index].feedURLs.count)")
                    
                    // Save back to UserDefaults
                    if let encodedData = try? JSONEncoder().encode(folders) {
                        UserDefaults.standard.set(encodedData, forKey: "hierarchicalFolders")
                        UserDefaults.standard.synchronize()
                        print("DEBUG: Successfully updated and synchronized UserDefaults")
                    } else {
                        print("DEBUG: Error encoding updated folders")
                    }
                } else {
                    print("DEBUG: ERROR - Folder not found in UserDefaults during update!")
                }
            } catch {
                print("DEBUG: Error updating UserDefaults: \(error)")
            }
        } else {
            print("DEBUG: No folder data found in UserDefaults during update!")
        }
    }
    
    private func verifyFeedsAdded(_ addedFeeds: [String]) {
        print("DEBUG: Verifying feeds were added to folder")
        
        StorageManager.shared.getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let folders):
                if let folder = folders.first(where: { $0.id == self.folder.id }) {
                    print("DEBUG: Verification - Folder has \(folder.feedURLs.count) feeds")
                    
                    // Check each added feed
                    for feedURL in addedFeeds {
                        let normalizedURL = StorageManager.shared.normalizeLink(feedURL)
                        let isFound = folder.feedURLs.contains { StorageManager.shared.normalizeLink($0) == normalizedURL }
                        print("DEBUG: Verification - Feed \(feedURL) is in folder: \(isFound ? "YES" : "NO")")
                    }
                } else {
                    print("DEBUG: Verification - Folder not found!")
                }
            case .failure(let error):
                print("DEBUG: Verification failed: \(error.localizedDescription)")
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

        // Add tap gesture recognizer for custom selection handling
        if cell.gestureRecognizers?.isEmpty ?? true {
            print("DEBUG-MULTI: Adding tap gesture to cell at index \(indexPath.row)")
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCellTap(_:)))
            tapGesture.numberOfTapsRequired = 1
            cell.addGestureRecognizer(tapGesture)
            cell.tag = indexPath.row // Store the row index in the tag for later reference
            cell.isUserInteractionEnabled = true
        }

        // Make selection style more visible but custom - blue background when selected
        cell.selectionStyle = .default

        // Use a custom indicator for selection state
        if selectedFeeds.contains(feed.url) {
            cell.accessoryType = .checkmark
            cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
            print("DEBUG-MULTI: Pre-setting selection state for row \(indexPath.row)")
        } else {
            cell.accessoryType = .none
            cell.backgroundColor = UIColor.clear
        }

        return cell
    }

    @objc private func handleCellTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let cell = gestureRecognizer.view as? UITableViewCell else { return }
        let rowIndex = cell.tag

        print("DEBUG-MULTI: 👆 Custom tap handler called for row \(rowIndex)")

        // Sanity check
        guard rowIndex >= 0 && rowIndex < feeds.count else {
            print("DEBUG-MULTI: ❌ Row index out of bounds: \(rowIndex)")
            return
        }

        let feed = feeds[rowIndex]

        // Toggle selection state
        if selectedFeeds.contains(feed.url) {
            // Deselect
            selectedFeeds.remove(feed.url)
            cell.accessoryType = .none
            cell.backgroundColor = UIColor.clear
            print("DEBUG-MULTI: 🔴 Custom handler DESELECTED row \(rowIndex)")
        } else {
            // Select
            selectedFeeds.insert(feed.url)
            cell.accessoryType = .checkmark
            cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
            print("DEBUG-MULTI: 🔵 Custom handler SELECTED row \(rowIndex)")
        }

        // Update the indexPath for tableView methods
        let indexPath = IndexPath(row: rowIndex, section: 0)

        // Sync the tableView selection state with our custom state
        if selectedFeeds.contains(feed.url) {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else {
            tableView.deselectRow(at: indexPath, animated: false)
        }

        print("DEBUG-MULTI: Total selected feeds count: \(selectedFeeds.count)")
        updateDoneButton()
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("DEBUG-MULTI: 🔵 SELECTED row at index \(indexPath.row)")
        print("DEBUG-MULTI: tableView.allowsMultipleSelection = \(tableView.allowsMultipleSelection)")
        print("DEBUG-MULTI: tableView.isEditing = \(tableView.isEditing)")

        // Print currently selected rows
        let selectedRows = tableView.indexPathsForSelectedRows
        print("DEBUG-MULTI: Currently selected rows: \(selectedRows?.map { $0.row } ?? [])")

        let feed = feeds[indexPath.row]
        selectedFeeds.insert(feed.url)
        print("DEBUG-MULTI: Added feed URL to selectedFeeds: \(feed.url)")

        // Update UI
        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .checkmark
            print("DEBUG-MULTI: Added checkmark to cell at index \(indexPath.row)")

            // Make sure the row is visually selected
            if !cell.isSelected {
                print("DEBUG-MULTI: 🚨 Cell not showing as selected, forcing selection")
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        }

        print("DEBUG-MULTI: Total selected feeds count: \(selectedFeeds.count)")
        updateDoneButton()
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        print("DEBUG-MULTI: 🔴 DESELECTED row at index \(indexPath.row)")
        print("DEBUG-MULTI: tableView.allowsMultipleSelection = \(tableView.allowsMultipleSelection)")

        // Print remaining selected rows
        let selectedRows = tableView.indexPathsForSelectedRows
        print("DEBUG-MULTI: Remaining selected rows: \(selectedRows?.map { $0.row } ?? [])")

        let feed = feeds[indexPath.row]
        selectedFeeds.remove(feed.url)
        print("DEBUG-MULTI: Removed feed URL from selectedFeeds: \(feed.url)")

        // Update UI
        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .none
            print("DEBUG-MULTI: Removed checkmark from cell at index \(indexPath.row)")
        }

        print("DEBUG-MULTI: Total selected feeds count: \(selectedFeeds.count)")
        updateDoneButton()
    }

    // Add a method to handle special selection behavior
    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        print("DEBUG-MULTI: shouldBeginMultipleSelectionInteractionAt called for index \(indexPath.row)")
        return true
    }

    func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        print("DEBUG-MULTI: didBeginMultipleSelectionInteractionAt called for index \(indexPath.row)")
    }

    // This is a key method - set to false to make sure the table doesn't immediately deselect after selection
    func tableView(_ tableView: UITableView, shouldDeselectRowAt indexPath: IndexPath) -> Bool {
        print("DEBUG-MULTI: 🚧 shouldDeselectRowAt called for index \(indexPath.row)")
        // Return true only if user explicitly taps to deselect, otherwise we want to maintain selection
        return true
    }

    // The most important part - manually handle cell highlighting and selection
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        print("DEBUG-MULTI: ⚠️ willSelectRowAt called for index \(indexPath.row)")
        return indexPath
    }
}

// MARK: - Hierarchical Folder Feeds View Controller

class HierarchicalFolderFeedsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    // Changed from 'let' to 'var' to allow updating with latest data
    private var folder: HierarchicalFolder

    // Footer UI elements that need to be stored as properties
    private var footerContainer: UIView?
    private var instructionFooterLabel: UILabel?

    // Make sure layout is maintained and footer stays visible
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure footer stays visible by bringing it to front
        if let footerContainer = self.footerContainer {
            view.bringSubviewToFront(footerContainer)
        }

        // Check if our feeds array is empty but should have data
        if feeds.isEmpty && !folder.feedURLs.isEmpty {
            print("DEBUG: viewDidLayoutSubviews - feeds are empty but should have data, forcing reload")
            loadFeeds()
        }
    }

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
            // If feeds are empty but folder has feeds, try to restore from backup
            if _feeds.isEmpty && !folder.feedURLs.isEmpty {
                print("DEBUG: Feeds are empty but folder has \(folder.feedURLs.count) feeds, attempting to restore")
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

                // Update footer visibility if available
                if newValue.isEmpty {
                    print("DEBUG: Feeds are empty - checking if we need to recover them")
                }
            }
        }
    }

    private var isShowingSubfolderFeeds = false

    // Multiple selection properties
    private var selectedFeeds: Set<String> = []

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FolderFeedCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.allowsMultipleSelection = true // Always allow multiple selection
        return table
    }()

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["This Folder", "Include Subfolders"])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    init(folder: HierarchicalFolder) {
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
        setupRefreshControl()
        setupNavigationBar()

        // Explicitly enable multiple selection for deletion and make it very clear
        tableView.allowsMultipleSelection = true
        tableView.allowsMultipleSelectionDuringEditing = true
        // For iOS 13+ users who might long-press, make sure that works too
        if #available(iOS 13.0, *) {
            tableView.allowsMultipleSelectionDuringEditing = true
        }
        print("DEBUG-MULTI: Multiple selection explicitly enabled in HierarchicalFolderFeedsViewController")
        print("DEBUG-MULTI: allowsMultipleSelection = \(tableView.allowsMultipleSelection)")
        print("DEBUG-MULTI: allowsMultipleSelectionDuringEditing = \(tableView.allowsMultipleSelectionDuringEditing)")

        // Add a clear visual indicator in the view to explain multiple selection
        let infoLabel = UILabel()
        infoLabel.text = "Tap multiple feeds to select them for deletion"
        infoLabel.textAlignment = .center
        infoLabel.font = UIFont.boldSystemFont(ofSize: 14)
        infoLabel.textColor = .secondaryLabel
        infoLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.05)
        infoLabel.layer.cornerRadius = 8
        infoLabel.layer.masksToBounds = true
        infoLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(infoLabel)
        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            infoLabel.heightAnchor.constraint(equalToConstant: 30)
        ])

        // Adjust table view top constraint
        for constraint in view.constraints {
            if constraint.firstItem === tableView && constraint.firstAttribute == .top {
                constraint.isActive = false
                break
            }
        }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 8),
        ])

        // Force UserDefaults synchronization to ensure we have the latest data
        UserDefaults.standard.synchronize()

        // Ensure folder has been properly loaded before continuing
        verifyAndLoadFolder()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // When view reappears, make sure to always refresh the folder data from source
        print("DEBUG-DELETE: HierarchicalFolderFeedsViewController - View reappearing, forcing refresh of folder data")

        // First, synchronize UserDefaults to ensure we have latest data
        UserDefaults.standard.synchronize()

        // Create a property for the footer if it doesn't exist yet
        if self.footerContainer == nil {
            // Create a permanent fixed footer that won't disappear
            let footerContainer = UIView()
            footerContainer.backgroundColor = AppColors.background
            footerContainer.translatesAutoresizingMaskIntoConstraints = false

            // Add a subtle shadow
            footerContainer.layer.shadowColor = UIColor.black.cgColor
            footerContainer.layer.shadowOffset = CGSize(width: 0, height: -1)
            footerContainer.layer.shadowOpacity = 0.1
            footerContainer.layer.shadowRadius = 2

            // Create the instruction label
            let instructionLabel = UILabel()
            instructionLabel.text = "📋 Tap multiple feeds to select them, then press 'Delete'"
            instructionLabel.textAlignment = .center
            instructionLabel.font = UIFont.boldSystemFont(ofSize: 14)
            instructionLabel.textColor = .label
            instructionLabel.numberOfLines = 0
            instructionLabel.translatesAutoresizingMaskIntoConstraints = false

            // Create a separator line
            let separatorView = UIView()
            separatorView.backgroundColor = .separator
            separatorView.translatesAutoresizingMaskIntoConstraints = false

            // Add views to container
            footerContainer.addSubview(separatorView)
            footerContainer.addSubview(instructionLabel)

            // Add container to main view
            view.addSubview(footerContainer)

            // Setup container constraints
            NSLayoutConstraint.activate([
                footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                footerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])

            // Setup separator constraints
            NSLayoutConstraint.activate([
                separatorView.topAnchor.constraint(equalTo: footerContainer.topAnchor),
                separatorView.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
                separatorView.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
                separatorView.heightAnchor.constraint(equalToConstant: 0.5)
            ])

            // Setup label constraints
            NSLayoutConstraint.activate([
                instructionLabel.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
                instructionLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 16),
                instructionLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -16),
                instructionLabel.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor, constant: -8),
                instructionLabel.heightAnchor.constraint(equalToConstant: 20)
            ])

            // Store references for future access
            self.footerContainer = footerContainer
            self.instructionFooterLabel = instructionLabel

            // Adjust table view bottom constraint
            let inset: CGFloat = 40

            // Add extra inset to prevent cells from being hidden behind the footer
            self.tableView.contentInset.bottom = inset
            self.tableView.verticalScrollIndicatorInsets.bottom = inset

            // Make sure the footer stays visible by bringing it to front
            self.view.bringSubviewToFront(footerContainer)
        }

        // Then update our local folder with latest data
        StorageManager.shared.getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            let folderId = self.folder.id
            if case .success(let folders) = result,
               let updatedFolder = folders.first(where: { $0.id == folderId }) {

                print("DEBUG-DELETE: Found updated folder with \(updatedFolder.feedURLs.count) feeds")
                self.folder = updatedFolder

                // Now load feeds with the updated folder data
                DispatchQueue.main.async {
                    self.loadFeeds()
                }
            } else {
                // If we can't find the updated folder, still try to load feeds with current data
                print("DEBUG-DELETE: Could not find updated folder, using current data")
                DispatchQueue.main.async {
                    self.loadFeeds()
                }
            }
        }
    }

    private func verifyAndLoadFolder() {
        print("DEBUG-PERSIST: Verifying folder exists: \(folder.id) - \(folder.name)")
        print("DEBUG-PERSIST: Feed count in folder object: \(folder.feedURLs.count)")

        // Force StorageManager to load the latest data for this folder
        StorageManager.shared.getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let folders):
                print("DEBUG-PERSIST: Loaded \(folders.count) folders from storage")

                if let updatedFolder = folders.first(where: { $0.id == self.folder.id }) {
                    print("DEBUG-PERSIST: Found folder in storage with \(updatedFolder.feedURLs.count) feeds")

                    // Update our folder object with the latest data
                    if updatedFolder.feedURLs.count > self.folder.feedURLs.count {
                        print("DEBUG-PERSIST: Updating folder with newer data")
                        self.folder = updatedFolder
                    }
                } else {
                    print("DEBUG-PERSIST: WARNING - Folder not found in storage")
                }

                // Update title with current folder name
                DispatchQueue.main.async {
                    self.title = self.folder.name
                    // Now load the feeds
                    self.loadFeeds()
                }

            case .failure(let error):
                print("DEBUG-PERSIST: Error verifying folder: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.loadFeeds() // Still try to load feeds anyway
                }
            }
        }
    }

    private func setupNavigationBar() {
        // Add a manual back button
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonPressed)
        )
        backButton.tintColor = .systemBlue

        // Add delete button (initially disabled)
        let deleteButton = UIBarButtonItem(
            title: "Delete (0)",
            style: .plain,
            target: self,
            action: #selector(removeFeedsButtonTapped)
        )
        deleteButton.tintColor = .systemRed
        deleteButton.isEnabled = false

        // Set up navigation items
        navigationItem.leftBarButtonItem = backButton
        navigationItem.rightBarButtonItem = deleteButton

        // Create a permanent instructional footer
        let footerContainer = UIView()
        footerContainer.backgroundColor = AppColors.background
        footerContainer.translatesAutoresizingMaskIntoConstraints = false

        // Create the instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "📋 Tap multiple feeds to select them, then press 'Delete'"
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.boldSystemFont(ofSize: 13)
        instructionLabel.textColor = .secondaryLabel
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false

        // Create a separator line
        let separatorView = UIView()
        separatorView.backgroundColor = .separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false

        // Add views to container
        footerContainer.addSubview(separatorView)
        footerContainer.addSubview(instructionLabel)

        // Add container to main view
        view.addSubview(footerContainer)

        // Setup container constraints
        NSLayoutConstraint.activate([
            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // Setup separator constraints
        NSLayoutConstraint.activate([
            separatorView.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            separatorView.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        // Setup label constraints
        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 16),
            instructionLabel.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -16),
            instructionLabel.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor, constant: -8),
            instructionLabel.heightAnchor.constraint(equalToConstant: 20)
        ])

        // Ensure it's always on top of other views
        view.bringSubviewToFront(footerContainer)

        // Adjust table view bottom constraint to make room for footer
        for constraint in view.constraints {
            if constraint.firstItem === tableView && constraint.firstAttribute == .bottom {
                constraint.isActive = false
                break
            }
        }

        NSLayoutConstraint.activate([
            tableView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor)
        ])

        // Add bottom content inset to ensure cells aren't hidden behind footer
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 30, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 30, right: 0)
    }

    private func setupRefreshControl() {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshFeeds), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    @objc private func refreshFeeds() {
        print("DEBUG: Manual refresh of feeds triggered")
        // Force sync of UserDefaults
        UserDefaults.standard.synchronize()

        dumpFolderContents()
        loadFeeds()
        tableView.refreshControl?.endRefreshing()
    }

    private func dumpFolderContents() {
        print("DEBUG: ----- DUMPING FOLDER CONTENTS -----")

        // Print current folder data
        print("DEBUG: Current folder in memory: \(folder.name) (ID: \(folder.id))")
        print("DEBUG: Feeds count in memory: \(folder.feedURLs.count)")
        print("DEBUG: Feed URLs in memory: \(folder.feedURLs)")

        // Manually check folder data in UserDefaults
        print("DEBUG: Checking UserDefaults for folder data")
        if let data = UserDefaults.standard.data(forKey: "hierarchicalFolders") {
            do {
                let folders = try JSONDecoder().decode([HierarchicalFolder].self, from: data)
                print("DEBUG: Found \(folders.count) folders in UserDefaults")
                print("DEBUG: Root folders: \(folders.filter { $0.parentId == nil }.count)")
                print("DEBUG: Folder IDs: \(folders.map { $0.id })")

                if let currentFolder = folders.first(where: { $0.id == folder.id }) {
                    print("DEBUG: Found current folder in UserDefaults: \(currentFolder.name)")
                    print("DEBUG: Feeds count in UserDefaults: \(currentFolder.feedURLs.count)")
                    print("DEBUG: Feed URLs in UserDefaults: \(currentFolder.feedURLs)")

                    // Check for normalized URL matches
                    print("DEBUG: Checking feed URL normalization...")
                    for url in currentFolder.feedURLs {
                        let normalizedURL = StorageManager.shared.normalizeLink(url)
                        print("DEBUG: Original: \(url)")
                        print("DEBUG: Normalized: \(normalizedURL)")

                        // Check if the normalized URL exists in the feeds array
                        let matchingFeed = self.feeds.first { feed in
                            StorageManager.shared.normalizeLink(feed.url) == normalizedURL
                        }
                        print("DEBUG: Matching feed found: \(matchingFeed != nil ? "YES" : "NO")")
                        if let feed = matchingFeed {
                            print("DEBUG: Matching feed title: \(feed.title)")
                            print("DEBUG: Matching feed URL: \(feed.url)")
                        }
                    }

                    // Check folder children
                    let childFolders = folders.filter { $0.parentId == currentFolder.id }
                    print("DEBUG: Subfolder count: \(childFolders.count)")
                    if !childFolders.isEmpty {
                        print("DEBUG: Subfolder names: \(childFolders.map { $0.name })")
                    }
                } else {
                    print("DEBUG: Current folder NOT found in UserDefaults")
                }
            } catch {
                print("DEBUG: Error decoding folders from UserDefaults: \(error)")
            }
        } else {
            print("DEBUG: No folder data in UserDefaults")
        }

        // Try to load from StorageManager
        print("DEBUG: Checking for folder data via StorageManager")
        StorageManager.shared.getHierarchicalFolders { result in
            switch result {
            case .success(let folders):
                print("DEBUG: Found \(folders.count) folders via StorageManager")
                print("DEBUG: All folders: \(folders.map { "\($0.name) (ID: \($0.id))" })")

                if let currentFolder = folders.first(where: { $0.id == self.folder.id }) {
                    print("DEBUG: Found current folder via StorageManager: \(currentFolder.name)")
                    print("DEBUG: Feeds count via StorageManager: \(currentFolder.feedURLs.count)")
                    print("DEBUG: Feed URLs via StorageManager: \(currentFolder.feedURLs)")

                    // Verify feeds exist in system
                    print("DEBUG: Checking if feeds exist in the system")
                    StorageManager.shared.load(forKey: "rssFeeds") { (result: Result<[RSSFeed], Error>) in
                        switch result {
                        case .success(let allFeeds):
                            print("DEBUG: Total feeds in system: \(allFeeds.count)")
                            for url in currentFolder.feedURLs {
                                let normalizedURL = StorageManager.shared.normalizeLink(url)
                                let matchingSystemFeed = allFeeds.first { StorageManager.shared.normalizeLink($0.url) == normalizedURL }
                                print("DEBUG: Feed \(url) exists in system: \(matchingSystemFeed != nil ? "YES" : "NO")")
                            }
                        case .failure(let error):
                            print("DEBUG: Error loading feeds: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print("DEBUG: Current folder NOT found via StorageManager")
                }
            case .failure(let error):
                print("DEBUG: Error loading folders via StorageManager: \(error.localizedDescription)")
            }
        }

        // Check CloudKit sync status
        print("DEBUG: Checking CloudKit sync status")
        if UserDefaults.standard.bool(forKey: "useCloudSync") {
            print("DEBUG: CloudKit sync is enabled")

            // Load feeds to check if they match
            StorageManager.shared.load(forKey: "rssFeeds") { (result: Result<[RSSFeed], Error>) in
                switch result {
                case .success(let systemFeeds):
                    print("DEBUG: System has \(systemFeeds.count) feeds")
                    print("DEBUG: Checking if current feeds match system feeds")

                    let folderFeedURLs = self.folder.feedURLs.map { StorageManager.shared.normalizeLink($0) }
                    let matchingFeeds = systemFeeds.filter { feed in
                        folderFeedURLs.contains(StorageManager.shared.normalizeLink(feed.url))
                    }

                    print("DEBUG: Found \(matchingFeeds.count) matching feeds of \(folderFeedURLs.count) in folder")
                case .failure(let error):
                    print("DEBUG: Error loading RSS feeds: \(error.localizedDescription)")
                }
            }
        } else {
            print("DEBUG: CloudKit sync is disabled")
        }

        print("DEBUG: ----- END FOLDER DUMP -----")
    }

    @objc private func backButtonPressed() {
        // Simply pop back to the previous screen
        navigationController?.popViewController(animated: true)
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
        isShowingSubfolderFeeds = sender.selectedSegmentIndex == 1
        loadFeeds()
    }

    // Direct selection mode is now used instead of toggle edit mode

    private func updateRemoveButton() {
        // Update the Delete button based on selection count
        let count = selectedFeeds.count
        navigationItem.rightBarButtonItem?.title = "Delete (\(count))"
        navigationItem.rightBarButtonItem?.isEnabled = count > 0

        // If no items are selected, we need to make sure the table is still showing
        if count == 0 && tableView.isHidden {
            tableView.isHidden = false

            // Force layout and reload if table is empty
            if tableView.numberOfRows(inSection: 0) == 0 && !feeds.isEmpty {
                print("DEBUG-PERSIST: Table is hidden with zero rows but \(feeds.count) feeds exist - force reload")
                tableView.reloadData()
            }
        }
    }

    @objc private func removeFeedsButtonTapped() {
        guard !selectedFeeds.isEmpty else { return }

        let feedCount = selectedFeeds.count
        let alert = UIAlertController(
            title: "Delete Feeds",
            message: "Are you sure you want to delete \(feedCount) \(feedCount == 1 ? "feed" : "feeds") from this folder?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.bulkRemoveFeedsFromFolder()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func bulkRemoveFeedsFromFolder() {
        print("DEBUG-DELETE: Starting bulk removal process")
        print("DEBUG-DELETE: Selected feed URLs to remove: \(selectedFeeds)")

        // Store the selected feeds locally to use after operation completes
        let feedURLsToRemove = Array(selectedFeeds)

        // Show loading indicator
        let loadingAlert = UIAlertController(
            title: "Deleting Feeds",
            message: "Please wait while the feeds are removed from the folder...",
            preferredStyle: .alert
        )
        present(loadingAlert, animated: true)

        print("DEBUG-DELETE: First updating local folder data")

        // Fetch the latest folder data to make sure we're working with current data
        StorageManager.shared.getHierarchicalFolders { [weak self] foldersResult in
            guard let self = self else { return }

            switch foldersResult {
            case .success(var folderData):
                // Find and update the folder directly
                if let index = folderData.firstIndex(where: { $0.id == self.folder.id }) {
                    print("DEBUG-DELETE: Found folder in data, updating local copy")

                    // Update our local copy of the folder with the latest data
                    self.folder = folderData[index]

                    // Now perform the bulk removal
                    print("DEBUG-DELETE: Calling StorageManager.bulkRemoveFeedsFromHierarchicalFolder")
                    StorageManager.shared.bulkRemoveFeedsFromHierarchicalFolder(
                        feedURLs: feedURLsToRemove,
                        folderId: self.folder.id
                    ) { [weak self] result in
                        guard let self = self else { return }

                        print("DEBUG-DELETE: Bulk removal operation completed")

                        // Dismiss loading indicator and handle result
                        DispatchQueue.main.async {
                            loadingAlert.dismiss(animated: true) {
                                switch result {
                                case .success:
                                    print("DEBUG-DELETE: Successfully removed \(feedURLsToRemove.count) feeds")

                                    // Clear the selection
                                    self.selectedFeeds.removeAll()

                                    // Show success message
                                    let feedCount = feedURLsToRemove.count
                                    let successAlert = UIAlertController(
                                        title: "Success",
                                        message: "Successfully deleted \(feedCount) \(feedCount == 1 ? "feed" : "feeds") from the folder.",
                                        preferredStyle: .alert
                                    )
                                    successAlert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                                        // Manually update the UI with the new feed list (don't wait for notification)
                                        StorageManager.shared.getHierarchicalFolders { result in
                                            if case .success(let updatedFolders) = result,
                                               let updatedFolder = updatedFolders.first(where: { $0.id == self.folder.id }) {
                                                // Update our local folder data with the latest
                                                self.folder = updatedFolder
                                            }

                                            // Force reload data
                                            print("DEBUG-DELETE: Forcing reload of feed data")

                                            // Force reload data with a delay to ensure proper UI update
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                print("DEBUG-DELETE: Clearing and reloading feed table")
                                                // Clear table first
                                                self.feeds = []
                                                self.tableView.reloadData()

                                                // Then reload with fresh data
                                                self.loadFeeds()

                                                // Setup the UI state properly
                                                self.selectedFeeds.removeAll()
                                                self.updateRemoveButton()
                                            }
                                        }
                                    })

                                    // Present the success message
                                    self.present(successAlert, animated: true)

                                    // Update the Delete button immediately
                                    self.updateRemoveButton()

                                case .failure(let error):
                                    print("DEBUG-DELETE: Error removing feeds: \(error.localizedDescription)")
                                    self.showError("Failed to delete feeds: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                } else {
                    // Folder not found in current data
                    print("DEBUG-DELETE: ERROR - Folder not found in current data")
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            self.showError("Folder not found. Please try refreshing the app.")
                        }
                    }
                }

            case .failure(let error):
                // Failed to get folder data
                print("DEBUG-DELETE: ERROR - Failed to get folder data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self.showError("Failed to get folder data: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func loadFeeds() {
        print("DEBUG-DELETE: 📂 Loading feeds for folder: \(folder.name) (ID: \(folder.id))")
        print("DEBUG-DELETE: Including subfolders: \(isShowingSubfolderFeeds)")

        // Ensure we have the most recent folder data
        StorageManager.shared.getHierarchicalFolders { [weak self] result in
            guard let self = self else { return }

            if case .success(let folders) = result,
               let latestFolder = folders.first(where: { $0.id == self.folder.id }) {
                print("DEBUG-DELETE: Updating folder with latest data from storage")
                print("DEBUG-DELETE: Found folder with \(latestFolder.feedURLs.count) feeds")

                // Update our local copy with the latest data
                self.folder = latestFolder
            }

            // Continue with loading feeds using the latest folder data
            DispatchQueue.main.async {
                self.proceedWithLoadingFeeds()
            }
        }
    }

    private func proceedWithLoadingFeeds() {
        print("DEBUG: proceedWithLoadingFeeds called - starting load with crash protection")

        // Make sure we have a valid folder
        guard folder.feedURLs.count > 0 else {
            print("DEBUG: [ERROR] Folder has no feeds, cannot proceed with loading")
            return
        }

        // If we recently made changes to the feeds, ensure selection is cleared
        if selectedFeeds.isEmpty == false {
            print("DEBUG-DELETE: Clearing selection of \(selectedFeeds.count) feeds before reloading")
            selectedFeeds.removeAll()
            updateRemoveButton()
        }

        // Important: Ensure table is visible before we start loading
        tableView.isHidden = false

        // Show a placeholder while loading starts to happen
        if feeds.isEmpty {
            print("DEBUG: Showing loading placeholder in table")
            DispatchQueue.main.async {
                // Force reload to show the placeholder
                self.tableView.reloadData()
            }
        }

        // Show a loading indicator to prevent empty appearance
        let loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.startAnimating()
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.center = view.center
        view.addSubview(loadingIndicator)

        print("DEBUG-DELETE: Current folder ID: \(folder.id), contains \(folder.feedURLs.count) feeds")

        StorageManager.shared.getFeedsInHierarchicalFolder(
            folderId: folder.id,
            includeSubfolders: isShowingSubfolderFeeds
        ) { [weak self] result in
            guard let self = self else { return }

            // Clean up UI on main thread
            DispatchQueue.main.async {
                loadingIndicator.stopAnimating()
                loadingIndicator.removeFromSuperview()
            }

            switch result {
            case .success(let folderFeeds):
                print("DEBUG-DELETE: Successfully loaded \(folderFeeds.count) feeds for folder")

                // Update on main thread
                DispatchQueue.main.async {
                    // Store and sort the feeds
                    self.feeds = folderFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }

                    if self.feeds.isEmpty {
                        print("DEBUG-DELETE: ⚠️ No feeds found for this folder!")
                    } else {
                        print("DEBUG-DELETE: Loading \(self.feeds.count) feeds into table")
                    }

                    // Make sure the table is visible
                    self.tableView.isHidden = false

                    // Update layout first, then reload
                    self.view.setNeedsLayout()
                    self.view.layoutIfNeeded()

                    print("DEBUG-DELETE: Reloading table data")
                    self.tableView.reloadData()

                    // After reloading, verify we have rows showing
                    print("DEBUG-DELETE: Table now has \(self.tableView.numberOfRows(inSection: 0)) visible rows")

                    // If for some reason the table is still empty but we have feeds, force another reload
                    if self.tableView.numberOfRows(inSection: 0) == 0 && !self.feeds.isEmpty {
                        print("DEBUG-DELETE: 🚨 Table still empty, forcing another reload")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.tableView.reloadData()
                        }
                    }

                    // Make sure the button reflects current state
                    self.selectedFeeds.removeAll()
                    self.updateRemoveButton()
                }

            case .failure(let error):
                print("DEBUG-DELETE: ❌ Failed to load feeds in folder: \(error.localizedDescription)")

                // Show error on main thread
                DispatchQueue.main.async {
                    self.showError("Failed to load feeds in folder")
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
        print("DEBUG: HierarchicalFolderFeedsViewController numberOfRowsInSection - feeds count: \(count)")

        // If feeds array is empty but we know we should have feeds based on folder data
        if count == 0 && !folder.feedURLs.isEmpty {
            print("DEBUG: [WARNING] TableView has 0 rows but folder has \(folder.feedURLs.count) feeds - forcing reload")

            // Force an async reload to make sure we get the data - use a higher priority
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Try to reload feeds with high priority
                self.proceedWithLoadingFeeds()

                // Also set up a backup timer in case first attempt fails
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, self.feeds.isEmpty else { return }
                    print("DEBUG: [EMERGENCY] Still no feeds after 1 second - trying again")
                    self.loadFeeds()
                }
            }

            // Return exactly 1 for a placeholder row - we'll show a loading message
            return 1
        }

        // Normal case - we have feeds
        if count > 0 {
            return count
        }

        // Last resort - always show at least one row to prevent crashes
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderFeedCell", for: indexPath)

        // Critical crash protection: Ensure we have feeds and the index is valid
        guard !feeds.isEmpty, indexPath.row < feeds.count else {
            // Configure cell as a placeholder while feeds are loading
            var config = cell.defaultContentConfiguration()
            config.text = "Loading feeds..."
            config.secondaryText = "Please wait"
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            cell.accessoryType = .none
            cell.backgroundColor = UIColor.clear

            // Force a data reload if this shouldn't be empty
            if !folder.feedURLs.isEmpty && feeds.isEmpty {
                print("DEBUG: [CRITICAL] Cell requested but feeds array is empty - forcing reload")
                DispatchQueue.main.async { [weak self] in
                    self?.loadFeeds()
                }
            }

            // Remove any previous gesture recognizers to avoid conflicts
            if let gestureRecognizers = cell.gestureRecognizers {
                for recognizer in gestureRecognizers {
                    cell.removeGestureRecognizer(recognizer)
                }
            }

            return cell
        }

        // Normal case - we have feeds and the index is valid
        let feed = feeds[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = feed.title
        config.secondaryText = feed.url
        cell.contentConfiguration = config

        // Make selection style clear and visible
        cell.selectionStyle = .default

        // Remove any existing gesture recognizers that might interfere with standard selection
        if let gestureRecognizers = cell.gestureRecognizers, !gestureRecognizers.isEmpty {
            print("DEBUG-DELETE: Removing tap gestures from cell at index \(indexPath.row)")
            for recognizer in gestureRecognizers {
                cell.removeGestureRecognizer(recognizer)
            }
        }

        // Explicitly verify multiple selection is enabled for this table view
        if !tableView.allowsMultipleSelection {
            print("DEBUG-MULTI: Enabling multiple selection for table view")
            tableView.allowsMultipleSelection = true
        }

        // Store the index in the tag for lookup during selection
        cell.tag = indexPath.row
        cell.isUserInteractionEnabled = true

        // Show checkmark and blue background if selected
        if selectedFeeds.contains(feed.url) {
            cell.accessoryType = .checkmark
            cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            print("DEBUG-DELETE: Pre-selected cell at index \(indexPath.row)")
        } else {
            cell.accessoryType = .none
            cell.backgroundColor = UIColor.clear
        }

        return cell
    }

    // Disabled custom tap handler in favor of standard UITableView selection
    /*
    @objc private func handleFeedCellTap(_ gestureRecognizer: UITapGestureRecognizer) {
        // This custom tap gesture handler is no longer used
        // We're using standard table view selection instead to fix the multiple selection issue
    }
    */

    // MARK: - UITableViewDelegate Methods

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("DEBUG-MULTI: 🔵 Selected row at index \(indexPath.row) in FeedsViewController")

        // Critical crash protection
        guard indexPath.row < feeds.count else {
            print("DEBUG-MULTI: ❌ Row index out of bounds: \(indexPath.row), max: \(feeds.count - 1)")
            tableView.deselectRow(at: indexPath, animated: false)
            return
        }

        let feed = feeds[indexPath.row]

        // Add to selected feeds set
        selectedFeeds.insert(feed.url)
        print("DEBUG-MULTI: Selected feed URL: \(feed.url)")

        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .checkmark
            print("DEBUG-MULTI: Added checkmark to cell at index \(indexPath.row)")

            // Add a visual indicator by changing the background color
            cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)

            // Make sure the rest of the UI knows this row is selected
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }

        // Print currently selected rows
        let selectedRows = tableView.indexPathsForSelectedRows
        print("DEBUG-MULTI: Selected rows count: \(selectedRows?.count ?? 0)")
        print("DEBUG-MULTI: Currently selected rows: \(selectedRows?.map { $0.row } ?? [])")

        // Double verification that multiple selection is working
        print("DEBUG-MULTI: ✅ allowsMultipleSelection = \(tableView.allowsMultipleSelection)")
        print("DEBUG-MULTI: ✅ allowsMultipleSelectionDuringEditing = \(tableView.allowsMultipleSelectionDuringEditing)")
        print("DEBUG-DELETE: Currently selected rows: \(selectedRows?.map { $0.row } ?? [])")
        print("DEBUG-DELETE: Total selected feeds: \(selectedFeeds.count)")

        updateRemoveButton()
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        print("DEBUG-DELETE: 🔴 Deselected row at index \(indexPath.row) in FeedsViewController")

        // Critical crash protection
        guard indexPath.row < feeds.count else {
            print("DEBUG-DELETE: ❌ Row index out of bounds: \(indexPath.row), max: \(feeds.count - 1)")
            return
        }

        let feed = feeds[indexPath.row]
        selectedFeeds.remove(feed.url)
        print("DEBUG-DELETE: Removed feed URL: \(feed.url)")

        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .none
            // Remove visual indicator
            cell.backgroundColor = UIColor.clear
        }

        // Print remaining selected rows
        let selectedRows = tableView.indexPathsForSelectedRows
        print("DEBUG-DELETE: Remaining selected rows: \(selectedRows?.map { $0.row } ?? [])")
        print("DEBUG-DELETE: Total selected feeds: \(selectedFeeds.count)")

        updateRemoveButton()
    }

    // Handle cell selection more explicitly with validation
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        print("DEBUG-DELETE: willSelectRowAt called for index \(indexPath.row)")

        // Critical crash protection - validate the index path
        guard !feeds.isEmpty, indexPath.row < feeds.count else {
            print("DEBUG-DELETE: ❌ Prevented selection of invalid row \(indexPath.row)")
            return nil
        }

        return indexPath
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        print("DEBUG-DELETE: shouldBeginMultipleSelectionInteractionAt called for index \(indexPath.row)")

        // Validation to prevent out-of-bounds access
        guard !feeds.isEmpty, indexPath.row < feeds.count else {
            print("DEBUG-DELETE: ⚠️ Invalid index for multiple selection interaction: \(indexPath.row)")
            return false
        }

        return true // Allow multiple selection interaction
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Critical crash protection - validate the index path
            guard !feeds.isEmpty, indexPath.row < feeds.count else {
                print("DEBUG-DELETE: ❌ Prevented deletion of invalid row \(indexPath.row)")
                return
            }

            let feed = feeds[indexPath.row]

            // Remove feed from folder
            StorageManager.shared.removeFeedFromHierarchicalFolder(feedURL: feed.url, folderId: folder.id) { [weak self] result in
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