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
        tableView.refreshControl?.endRefreshing()
    }
    
    @objc private func backButtonPressed() {
        navigationController?.popViewController(animated: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadFolders()
        loadFeeds()
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
        StorageManager.shared.load(forKey: "rssFeeds") { [weak self] (result: Result<[RSSFeed], Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let loadedFeeds):
                self.feeds = loadedFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }
                self.tableView.reloadData()
            case .failure(let error):
                print("Error loading feeds: \(error.localizedDescription)")
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
        // Get all feeds not in the current folder
        let folderFeedURLs = folder.feedURLs.map { StorageManager.shared.normalizeLink($0) }
        let unfolderedFeeds = feeds.filter { !folderFeedURLs.contains(StorageManager.shared.normalizeLink($0.url)) }
        
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
        
        print("DEBUG: Feed selection view loaded for folder: \(folder.name) (ID: \(folder.id))")
        print("DEBUG: Current folder has \(folder.feedURLs.count) feeds: \(folder.feedURLs)")
        print("DEBUG: Available feeds for selection: \(feeds.count)")
        if !feeds.isEmpty {
            print("DEBUG: Available feed URLs: \(feeds.map { $0.url })")
        }
        
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
        // Add "Done" button on the right
        let doneButton = UIBarButtonItem(
            title: "Add (0)",
            style: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        navigationItem.rightBarButtonItem = doneButton
        
        // Add back button
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonPressed)
        )
        backButton.tintColor = .systemBlue
        
        // Add "Select All" button
        let selectAllButton = UIBarButtonItem(
            title: "Select All",
            style: .plain,
            target: self,
            action: #selector(selectAllButtonTapped)
        )
        
        navigationItem.leftBarButtonItems = [backButton, selectAllButton]
    }
    
    @objc private func backButtonPressed() {
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

// MARK: - Hierarchical Folder Feeds View Controller

class HierarchicalFolderFeedsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let folder: HierarchicalFolder
    private var feeds: [RSSFeed] = []
    private var isShowingSubfolderFeeds = false
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = AppColors.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "FolderFeedCell")
        table.translatesAutoresizingMaskIntoConstraints = false
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
        loadFeeds()
        
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
    
    private func loadFeeds() {
        print("DEBUG: Loading feeds for folder: \(folder.name) (ID: \(folder.id))")
        print("DEBUG: Including subfolders: \(isShowingSubfolderFeeds)")
        
        StorageManager.shared.getFeedsInHierarchicalFolder(
            folderId: folder.id,
            includeSubfolders: isShowingSubfolderFeeds
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let folderFeeds):
                print("DEBUG: Successfully loaded \(folderFeeds.count) feeds for folder")
                if !folderFeeds.isEmpty {
                    print("DEBUG: Feed titles: \(folderFeeds.map { $0.title })")
                    print("DEBUG: Feed URLs: \(folderFeeds.map { $0.url })")
                }
                
                self.feeds = folderFeeds.sorted { $0.title.lowercased() < $1.title.lowercased() }
                print("DEBUG: After sorting, updating table with \(self.feeds.count) feeds")
                self.tableView.reloadData()
            case .failure(let error):
                print("DEBUG ERROR: Failed to load feeds in folder: \(error.localizedDescription)")
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