import UIKit
import SafariServices
import Foundation
import CloudKit

// MARK: - UI Setup and Navigation Components
extension HomeFeedViewController {
    
    func setupLoadingIndicator() {
        // Setup main loading indicator
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.center = view.center
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        
        // Setup loading label below the indicator
        loadingLabel = UILabel()
        loadingLabel.textAlignment = .center
        loadingLabel.textColor = AppColors.secondary
        loadingLabel.font = UIFont.systemFont(ofSize: 14)
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)
        
        NSLayoutConstraint.activate([
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 12),
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            loadingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        // Initially hide the label
        loadingLabel.isHidden = true
    }
    
    func setupRefreshControl() {
        refreshControl.addTarget(
            self, action: #selector(HomeFeedViewController.refreshFeeds), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    func setupNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        // Use your new dynamic color here:
        appearance.backgroundColor = AppColors.navBarBackground

        // Make title text dynamic too (white in Dark Mode, black in Light Mode)
        let titleColor = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: titleColor,
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
        updateNavigationButtons()
    }
    
    func setupNavigationButtons() {
        // Create each bar button
        rssButton = createBarButton(
            imageName: "rss",
            action: #selector(rssButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )
        refreshButton = createBarButton(
            imageName: "refresh",
            action: #selector(refreshButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )
        bookmarkButton = createBarButton(
            imageName: "bookmark",
            action: #selector(bookmarkButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )
        heartButton = createBarButton(
            imageName: "heart",
            action: #selector(heartButtonTapped),
            tintColor: AppColors.dynamicIconColor
        )
        folderButton = createBarButton(
            imageName: "folder", // Using system image for folder
            action: #selector(folderButtonTapped),
            tintColor: AppColors.dynamicIconColor,
            isSystemImage: true
        )

        // We've moved the sort functionality to Settings, so no longer need a button here

        // Create your right-side buttons
        settingsButton = createBarButton(
            imageName: "settings",
            action: #selector(openSettings),
            tintColor: AppColors.dynamicIconColor
        )

        // Assign them in the order you want on the left side
        navigationItem.leftBarButtonItems = [
            rssButton,
            refreshButton,
            bookmarkButton,
            heartButton,
            folderButton
        ].compactMap { $0 } // Use properties and compactMap to handle potential nils

        // Assign the right-side buttons - only settings button remains
        navigationItem.rightBarButtonItems = [settingsButton].compactMap { $0 }
        
        // Initialize the read status indicator
        updateReadStatusIndicator()
    }
    
    func createBarButton(
        imageName: String,
        action: Selector,
        tintColor: UIColor = .white,
        renderOriginal: Bool = false,
        isSystemImage: Bool = false
    ) -> UIBarButtonItem {
        let renderingMode: UIImage.RenderingMode = renderOriginal ? .alwaysOriginal : .alwaysTemplate
        
        let buttonImage: UIImage?
        if isSystemImage {
            buttonImage = resizeImage(
                UIImage(systemName: imageName),
                targetSize: CGSize(width: 24, height: 24)
            )?.withRenderingMode(renderingMode)
        } else {
            buttonImage = resizeImage(
                UIImage(named: imageName),
                targetSize: CGSize(width: 24, height: 24)
            )?.withRenderingMode(renderingMode)
        }

        let button = UIBarButtonItem(
            image: buttonImage,
            style: .plain,
            target: self,
            action: action
        )
        button.tintColor = tintColor
        return button
    }
    
    func updateNavigationButtons() {
        guard let leftButtons = navigationItem.leftBarButtonItems, leftButtons.count >= 5 else {
            return
        }
        
        // leftButtons order: [rss, refresh, bookmark, heart, folder]
        // Update the RSS button image:
        let isFolderOrSmartFolder: Bool
        if case .folder = currentFeedType {
            isFolderOrSmartFolder = true
        } else if case .smartFolder = currentFeedType {
            isFolderOrSmartFolder = true
        } else {
            isFolderOrSmartFolder = false
        }
        
        if isFolderOrSmartFolder {
            // If we're in a folder or smart folder, show normal RSS icon
            rssButton?.image = resizeImage(
                UIImage(named: "rss"),
                targetSize: CGSize(width: 24, height: 24)
            )?.withRenderingMode(.alwaysTemplate)
        } else {
            let rssImageName = { if case .rss = currentFeedType { return "rssFilled" } else { return "rss" } }()
            rssButton?.image = resizeImage(
                UIImage(named: rssImageName),
                targetSize: CGSize(width: 24, height: 24)
            )?.withRenderingMode(.alwaysTemplate)
        }
        
        // Do not change the refresh button (index 1)
        
        // Update the read status indicator when in RSS mode, folder mode, or smart folder mode
        let isRssFeed = if case .rss = currentFeedType { true } else { false }
        
        var isFolderFeed = false
        if case .folder = currentFeedType {
            isFolderFeed = true
        }
        
        var isSmartFolderFeed = false
        if case .smartFolder = currentFeedType {
            isSmartFolderFeed = true
        }
        
        if isRssFeed || isFolderFeed || isSmartFolderFeed {
            updateReadStatusIndicator()
        }
        
        // Update the Bookmark button image:
        let bookmarkImageName = { if case .bookmarks = currentFeedType { return "bookmarkFilled" } else { return "bookmark" } }()
        bookmarkButton?.image = resizeImage(
            UIImage(named: bookmarkImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        
        // Update the Heart button image:
        let heartImageName = { if case .heart = currentFeedType { return "heartFilled" } else { return "heart" } }()
        heartButton?.image = resizeImage(
            UIImage(named: heartImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        
        // Update the Folder button image:
        // Apply different tint based on selection status
        if isFolderFeed || isSmartFolderFeed {
            folderButton?.tintColor = AppColors.primary
        } else {
            folderButton?.tintColor = AppColors.dynamicIconColor
        }
        
        let folderImageName = isFolderFeed ? "folder.fill" : "folder"
        
        // Since folder icon is using a system image, use UIImage(systemName:) instead
        folderButton?.image = resizeImage(
            UIImage(systemName: folderImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        
        // Update the title based on feed type
        updateTitle()
    }
    
    func setupTableView() {
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
        tableView.prefetchDataSource = self
        tableView.register(
            UITableViewCell.self, forCellReuseIdentifier: "RSSCell")
        tableView.register(
            EnhancedRSSCell.self, forCellReuseIdentifier: EnhancedRSSCell.identifier)
        
        // Set appropriate row height depending on the style
        tableView.estimatedRowHeight = useEnhancedStyle ? 120 : 60
        tableView.rowHeight = UITableView.automaticDimension
        
        // Add prefetching to improve scroll performance
        if #available(iOS 15.0, *) {
            tableView.isPrefetchingEnabled = true
        }
        
        // Listen for style changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStyleChanged),
            name: Notification.Name("articleStyleChanged"),
            object: nil)
        
        // Use the direct approach from updateFooterVisibility instead
        DispatchQueue.main.async {
            self.updateFooterVisibility()
        }
    }
    
    func resizeImage(_ image: UIImage?, targetSize: CGSize) -> UIImage? {
        guard let image = image else { return nil }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    // MARK: - TableView Footer Methods
    func setupTableViewFooter() {
        // Create a completely new footer view each time
        let newFooterView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 100))
        newFooterView.backgroundColor = AppColors.background
        
        // Store the new footer view
        footerView = newFooterView

        let markAllButton = UIButton(type: .system)
        markAllButton.translatesAutoresizingMaskIntoConstraints = false
        footerView?.addSubview(markAllButton)

        // Enhanced appearance with gradient background
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            AppColors.primary.cgColor,
            UIColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1.0).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradientLayer.cornerRadius = 22
        
        // Create a container view for the gradient
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 22
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 4
        containerView.layer.shadowOpacity = 0.2
        containerView.clipsToBounds = true // Ensure gradient stays within bounds
        footerView?.insertSubview(containerView, belowSubview: markAllButton)
        
        // Set the button appearance
        markAllButton.setTitleColor(.white, for: .normal)
        markAllButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        markAllButton.tintColor = .white
        markAllButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        markAllButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        
        // Update button state based on current items
        updateFooterButtonState(button: markAllButton)
        
        // Add action to the button
        markAllButton.addTarget(self, action: #selector(markAllAsReadTapped), for: .touchUpInside)
        
        // Store reference to the button for later updates
        footerRefreshButton = markAllButton
        
        // Setup constraints for subviews within the frame-based footer
        NSLayoutConstraint.activate([
            // Center container in footer
            containerView.centerXAnchor.constraint(equalTo: footerView!.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: footerView!.centerYAnchor),
            containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            containerView.heightAnchor.constraint(equalToConstant: 44),
            
            // Make button fill container
            markAllButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            markAllButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            markAllButton.widthAnchor.constraint(equalTo: containerView.widthAnchor),
            markAllButton.heightAnchor.constraint(equalTo: containerView.heightAnchor)
        ])
        
        // Apply gradient layer to the container and set initial frame
        containerView.layer.insertSublayer(gradientLayer, at: 0)
        gradientLayer.frame = containerView.bounds
        
        // Add observer for orientation changes to update the gradient and footer
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            // Recreate footer with new dimensions after rotation
            self.refreshFooterView()
        }
        
        // Also observe table view content size changes
        tableView.addObserver(self, forKeyPath: "contentSize", options: .new, context: nil)
        
        // Add animation for button press
        let buttonFeedback = UIImpactFeedbackGenerator(style: .medium)
        
        markAllButton.addAction(UIAction { [weak self] _ in
            buttonFeedback.impactOccurred()
            self?.markAllAsReadTapped(markAllButton)
        }, for: .touchUpInside)
        
        footerRefreshButton = markAllButton
    }
    
    func updateFooterVisibility() {
        // Show the footer for RSS feed type and folder feed type
        let isRssFeed = if case .rss = currentFeedType { true } else { false }
        
        var isFolderFeed = false
        if case .folder = currentFeedType {
            isFolderFeed = true
        }
        
        if isRssFeed || isFolderFeed {
            // Add a new method to ensure footer is correctly sized and positioned
            addFooterToTableView()
        } else {
            // Hide footer for bookmarks and heart feeds
            tableView.tableFooterView = nil
        }
    }
    
    func refreshFooterView() {
        let isRssFeed = if case .rss = currentFeedType { true } else { false }
        
        var isFolderFeed = false
        if case .folder = currentFeedType {
            isFolderFeed = true
        }
        
        if isRssFeed || isFolderFeed {
            // Recreate the footer with updated width
            setupTableViewFooter()
            
            // Update the table footer on main thread
            DispatchQueue.main.async {
                self.tableView.tableFooterView = self.footerView
                self.tableView.layoutIfNeeded()
            }
        }
    }
    
    func updateReadStatusIndicator() {
        // Check if all articles are read
        let hasArticles = !items.isEmpty
        let allRead = hasArticles && !items.contains { !$0.isRead }
        
        // Only modify the table footer when in RSS mode or folder mode
        let isRssFeed = if case .rss = currentFeedType { true } else { false }
        
        var isFolderFeed = false
        if case .folder = currentFeedType {
            isFolderFeed = true
        }
        
        if isRssFeed || isFolderFeed {
            // Always call addFooterToTableView to show the "Mark All as Read" button
            // instead of just showing a status label
            addFooterToTableView()
        }
    }
    
    func addFooterToTableView() {
        // Force update read status first
        for i in 0..<items.count {
            let normLink = normalizeLink(items[i].link)
            items[i].isRead = readLinks.contains(normLink)
        }
        
        // Create a container with correct width
        let footerHeight: CGFloat = 100
        let buttonHeight: CGFloat = 50
        let containerWidth = max(tableView.frame.width, UIScreen.main.bounds.width)
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: containerWidth, height: footerHeight))
        containerView.backgroundColor = AppColors.background
        
        // Create the button
        let markAllButton = UIButton(type: .system)
        markAllButton.translatesAutoresizingMaskIntoConstraints = false
        markAllButton.backgroundColor = AppColors.primary
        markAllButton.layer.cornerRadius = buttonHeight / 2
        markAllButton.layer.shadowColor = UIColor.black.cgColor
        markAllButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        markAllButton.layer.shadowRadius = 4
        markAllButton.layer.shadowOpacity = 0.3
        
        // Configure the button appearance
        markAllButton.setTitleColor(.white, for: .normal)
        markAllButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        
        // Set the button state based on current items
        updateFooterButtonState(button: markAllButton)
        
        // Add the button to the container
        containerView.addSubview(markAllButton)
        
        // Set up button constraints
        NSLayoutConstraint.activate([
            markAllButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            markAllButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            markAllButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            markAllButton.widthAnchor.constraint(equalTo: containerView.widthAnchor, constant: -80)
        ])
        
        // Add action to the button
        markAllButton.addTarget(self, action: #selector(markAllAsReadTapped), for: .touchUpInside)
        
        // Store reference and set as table footer
        footerRefreshButton = markAllButton
        tableView.tableFooterView = containerView
    }
    
    func updateFooterButtonState(button: UIButton) {
        // Determine if we should display "All Articles Read" or "Mark All as Read"
        let hasUnreadArticles = !items.isEmpty && items.contains { !$0.isRead }
        let title: String
        let buttonImage: UIImage?
        
        if items.isEmpty {
            title = "No Articles"
            buttonImage = UIImage(systemName: "tray")?.withRenderingMode(.alwaysTemplate)
        } else if hasUnreadArticles {
            title = "Mark All as Read"
            buttonImage = UIImage(systemName: "checkmark.circle")?.withRenderingMode(.alwaysTemplate)
        } else {
            title = "All Articles Read"
            buttonImage = UIImage(systemName: "checkmark.circle.fill")?.withRenderingMode(.alwaysTemplate)
        }
        
        button.setTitle(title, for: .normal)
        button.isEnabled = hasUnreadArticles
        button.setImage(buttonImage, for: .normal)
    }
    
    @objc func markAllAsReadTapped(_ sender: UIButton) {
        // Only proceed if there are articles
        guard !items.isEmpty else { return }
        
        // Count unread articles for more specific feedback
        let unreadCount = items.filter { !$0.isRead }.count
        
        // Don't show alert if all articles are already read
        guard unreadCount > 0 else {
            // Show a quick toast-like message
            let toast = UIAlertController(
                title: nil,
                message: "All articles are already marked as read",
                preferredStyle: .alert
            )
            present(toast, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                toast.dismiss(animated: true)
            }
            return
        }
        
        // Create a more informative alert
        let alert = UIAlertController(
            title: "Mark All as Read",
            message: "This will mark \(unreadCount) unread article\(unreadCount == 1 ? "" : "s") as read. Are you sure you want to continue?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        alert.addAction(UIAlertAction(title: "Mark All Read", style: .default, handler: { _ in
            // Add visual feedback - briefly disable the button and change text
            sender.isEnabled = false
            sender.setTitle("Marking...", for: .normal)
            sender.setImage(UIImage(systemName: "hourglass"), for: .normal)
            
            // Step 1: Update readLinks set with all article links
            for item in self.items {
                if !item.isRead {
                    let normLink = self.normalizeLink(item.link)
                    self.readLinks.insert(normLink)
                }
            }
            
            // Step 2: Update local items array (this is what affects the UI)
            for i in 0..<self.items.count {
                self.items[i].isRead = true
            }
            
            // Step 3: Also update the full allItems collection, but only for the current folder items
            if case .folder(let folderId) = self.currentFeedType {
                // When in folder view, only mark those specific articles as read in the full collection
                let currentItemLinks = Set(self.items.map { self.normalizeLink($0.link) })
                
                for i in 0..<self._allItems.count {
                    let normLink = self.normalizeLink(self._allItems[i].link)
                    if currentItemLinks.contains(normLink) {
                        self._allItems[i].isRead = true
                    }
                }
                
                print("DEBUG: Marked as read only the \(currentItemLinks.count) articles in the current folder")
            } else {
                // In other views, mark all as read
                for i in 0..<self._allItems.count {
                    self._allItems[i].isRead = true
                }
            }
            
            // Step 4: Save the new read state using ReadStatusTracker
            if case .folder(let folderId) = self.currentFeedType {
                // Get the links from the current folder
                let folderLinks = self.items.map { $0.link }
                ReadStatusTracker.shared.markArticles(links: folderLinks, as: true)
            } else {
                // Mark all items as read
                let allLinks = self._allItems.map { $0.link }
                ReadStatusTracker.shared.markArticles(links: allLinks, as: true)
            }
            
            // Step 5: Apply a fade animation to the table cells for better visual feedback
            UIView.transition(with: self.tableView,
                              duration: 0.5,
                              options: .transitionCrossDissolve,
                              animations: {
                                 self.tableView.reloadData()
                              },
                              completion: { _ in
                                 // Force one more reload to ensure all UI elements are updated
                                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                     // By this time, all articles should be marked as read
                                     self.tableView.reloadData()
                                     
                                     // Update the navigation indicator with the new status 
                                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                         self.updateReadStatusIndicator()
                                     }
                                 }
                              })
            
            // Step 6: Update storage in UserDefaults and iCloud
            if case .folder(let folderId) = self.currentFeedType {
                // For folder view, only save what we've already updated in readLinks
                self.scheduleSaveReadState()
            } else {
                // For all feeds view, use the global markAllAsRead for efficiency
                StorageManager.shared.markAllAsRead { success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error marking all as read: \(error.localizedDescription)")
                    } else {
                        // Update button state using our common method
                        self.updateFooterButtonState(button: sender)
                        
                        // Reset the button after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            // Update button state again, in case any additional updates occurred
                            self.updateFooterButtonState(button: sender)
                        }
                    }
                    
                    // Reload table view again to ensure UI is updated
                    self.tableView.reloadData()
                }
            }
            }
        }))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func checkAndShowAllReadMessage() {
        // First make sure we have the latest read status
        for i in 0..<items.count {
            let normLink = normalizeLink(items[i].link)
            items[i].isRead = readLinks.contains(normLink)
        }
        
        // Only show message if there are articles and none are unread
        let hasArticles = !items.isEmpty
        let allRead = hasArticles && !items.contains { !$0.isRead }
        
        let isRssFeed = if case .rss = currentFeedType { true } else { false }
        
        if allRead && isRssFeed {
            DispatchQueue.main.async {
                // Create an alert to show the message
                let alert = UIAlertController(
                    title: "All Articles Read",
                    message: "You've read all the articles in your feed.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                // Present the alert
                if let topVC = UIApplication.shared.connectedScenes
                    .filter({$0.activationState == .foregroundActive})
                    .compactMap({$0 as? UIWindowScene})
                    .first?.windows
                    .filter({$0.isKeyWindow}).first?.rootViewController {
                    
                    topVC.present(alert, animated: true)
                }
            }
        }
    }
    
    // MARK: - Button Actions
    
    @objc func rssButtonTapped() {
        if case .folder = currentFeedType {
            // If we're already in a folder, go back to all feeds
            currentFeedType = .rss
        } else if case .rss = currentFeedType {
            // If we're in all feeds, we'll now use the folder button instead
            // of showing folder selection here
            currentFeedType = .rss
        } else {
            // Otherwise just go to all feeds
            currentFeedType = .rss
        }
    }
    
    @objc func folderButtonTapped() {
        // Show folder selection dialog
        showFolderSelection()
    }

    @objc func bookmarkButtonTapped() {
        currentFeedType = .bookmarks
    }

    @objc func heartButtonTapped() {
        currentFeedType = .heart
    }
    
    func updateTitle() {
        switch currentFeedType {
        case .rss:
            title = "All Feeds"
        case .bookmarks:
            title = "Bookmarks"
        case .heart:
            title = "Favorites"
        case .folder:
            // Get folder name if we have it
            if let folder = currentFolder {
                title = folder.name
            } else if case .folder(let id) = currentFeedType {
                // Load folder name if needed
                StorageManager.shared.getFolders { [weak self] result in
                    if case .success(let folders) = result, 
                       let folder = folders.first(where: { $0.id == id }) {
                        self?.currentFolder = folder
                        DispatchQueue.main.async {
                            self?.title = folder.name
                        }
                    }
                }
                title = "Folder"
            } else {
                title = "Folder"
            }
        case .smartFolder:
            // Get smart folder name if we have it
            if let folder = currentSmartFolder {
                title = folder.name
            } else if case .smartFolder(let id) = currentFeedType {
                // Load smart folder name if needed
                StorageManager.shared.getSmartFolders { [weak self] result in
                    if case .success(let folders) = result, 
                       let folder = folders.first(where: { $0.id == id }) {
                        self?.currentSmartFolder = folder
                        DispatchQueue.main.async {
                            self?.title = folder.name
                        }
                    }
                }
                title = "Smart Folder"
            } else {
                title = "Smart Folder"
            }
        }
    }
    
    func showFolderSelection() {
        // Create a dispatch group to load both regular folders and smart folders
        let group = DispatchGroup()
        
        // Variables to store results
        var regularFolders: [FeedFolder] = []
        var smartFolders: [SmartFolder] = []
        var loadError: Error?
        
        // Load regular folders
        group.enter()
        StorageManager.shared.getFolders { result in
            switch result {
            case .success(let folders):
                regularFolders = folders.sorted { $0.name.lowercased() < $1.name.lowercased() }
            case .failure(let error):
                loadError = error
                print("Error loading regular folders: \(error.localizedDescription)")
            }
            group.leave()
        }
        
        // Load smart folders
        group.enter()
        StorageManager.shared.getSmartFolders { result in
            switch result {
            case .success(let folders):
                smartFolders = folders.sorted { $0.name.lowercased() < $1.name.lowercased() }
            case .failure(let error):
                print("Error loading smart folders: \(error.localizedDescription)")
                // Don't set loadError if regular folders loaded successfully
                if loadError == nil {
                    loadError = error
                }
            }
            group.leave()
        }
        
        // When both types of folders are loaded
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            if let error = loadError {
                // Show error alert
                let errorAlert = UIAlertController(
                    title: "Error",
                    message: "Failed to load folders. \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
                return
            }
            
            // Check if there are any folders at all
            if regularFolders.isEmpty && smartFolders.isEmpty {
                // Show alert that there are no folders
                let alert = UIAlertController(
                    title: "No Folders",
                    message: "You don't have any folders yet. Create folders in Settings > Folder Organization or Smart Folders.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            } else {
                // Show folder selection
                let folderAlert = UIAlertController(
                    title: "Select Folder",
                    message: "Choose a folder to view:",
                    preferredStyle: .actionSheet
                )
                
                // Add regular folders section if there are any
                if !regularFolders.isEmpty {
                    // Add a header for regular folders if we have both types
                    if !smartFolders.isEmpty {
                        let regularHeader = UIAlertAction(title: "📁 Regular Folders", style: .default) { _ in }
                        regularHeader.isEnabled = false
                        folderAlert.addAction(regularHeader)
                    }
                    
                    // Add actions for each regular folder
                    for folder in regularFolders {
                        let action = UIAlertAction(title: folder.name, style: .default) { [weak self] _ in
                            self?.showFolderFeed(folder: folder)
                        }
                        folderAlert.addAction(action)
                    }
                }
                
                // Add smart folders section if there are any
                if !smartFolders.isEmpty {
                    // Add a separator if we have both types
                    if !regularFolders.isEmpty {
                        let separator = UIAlertAction(title: "─────────────────", style: .default) { _ in }
                        separator.isEnabled = false
                        folderAlert.addAction(separator)
                        
                        // Add a header for smart folders
                        let smartHeader = UIAlertAction(title: "🔍 Smart Folders", style: .default) { _ in }
                        smartHeader.isEnabled = false
                        folderAlert.addAction(smartHeader)
                    }
                    
                    // Add actions for each smart folder
                    for folder in smartFolders {
                        let action = UIAlertAction(title: folder.name, style: .default) { [weak self] _ in
                            // Mark as using smart folder
                            self?.currentSmartFolder = folder
                            self?.currentFeedType = .smartFolder(id: folder.id)
                            
                            // Load all feeds and filter based on smart folder rules
                            self?.loadRSSFeeds()
                        }
                        folderAlert.addAction(action)
                    }
                }
                
                // Add cancel action
                folderAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                
                // For iPad
                if let popoverController = folderAlert.popoverPresentationController {
                    popoverController.barButtonItem = self.folderButton
                }
                
                self.present(folderAlert, animated: true)
            }
        }
    }
    
    func showFolderFeed(folder: FeedFolder) {
        // Store the current folder
        currentFolder = folder
        
        // Set the feed type to folder
        switch currentFeedType {
        case .folder(let id) where id == folder.id:
            // Already showing this folder - do nothing
            break
        default:
            currentFeedType = .folder(id: folder.id)
            
            // Load feeds in this folder
            loadFolderFeeds(folder: folder)
        }
    }
    
    func loadFolderFeeds(folder: FeedFolder) {
        // Start loading animation
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        startRefreshAnimation() 
        
        // Load all feeds in the folder
        StorageManager.shared.getFeedsInFolder(folderId: folder.id) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let folderFeeds):
                    if folderFeeds.isEmpty {
                        // No feeds in folder
                        self.items = []
                        self.tableView.reloadData()
                        
                        // Clean up UI
                        self.tableView.isHidden = false
                        self.loadingIndicator.stopAnimating()
                        self.stopRefreshAnimation()
                        self.refreshControl.endRefreshing()
                        self.updateFooterVisibility()
                        
                        // Cancel the refresh timeout timer since we're done
                        self.refreshTimeoutTimer?.invalidate()
                        self.refreshTimeoutTimer = nil
                    } else {
                        // We have feeds, load their items
                        self.loadArticlesForFeeds(folderFeeds)
                    }
                case .failure(let error):
                    print("Error loading folder feeds: \(error.localizedDescription)")
                    // Show error and return to all feeds
                    self.items = []
                    self.tableView.reloadData()
                    
                    // Clean up UI
                    self.tableView.isHidden = false
                    self.loadingIndicator.stopAnimating()
                    self.stopRefreshAnimation()
                    self.refreshControl.endRefreshing()
                    self.updateFooterVisibility()
                    
                    // Cancel the refresh timeout timer since we're done
                    self.refreshTimeoutTimer?.invalidate()
                    self.refreshTimeoutTimer = nil
                    
                    // Show error alert
                    let errorAlert = UIAlertController(
                        title: "Error",
                        message: "Failed to load feeds in folder. Please try again.",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                }
            }
        }
    }
    
    private func loadArticlesForFeeds(_ feeds: [RSSFeed]) {
        var folderItems: [RSSItem] = []
        let group = DispatchGroup()
        
        // Set a timeout to ensure UI is always restored, even if network calls hang
        let timeoutTimer = DispatchSource.makeTimerSource(queue: .main)
        timeoutTimer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Only proceed if loading is still happening
            if self.tableView.isHidden {
                print("DEBUG: Folder feed loading timed out")
                
                // Ensure we make the table visible
                self.items = folderItems
                self.tableView.reloadData()
                self.tableView.isHidden = false
                self.loadingIndicator.stopAnimating()
                self.loadingLabel.isHidden = true
                self.stopRefreshAnimation()
                self.updateFooterVisibility()
                
                // Show timeout message
                self.loadingLabel.text = "Some feeds timed out. Pull to refresh to try again."
                self.loadingLabel.isHidden = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.loadingLabel.isHidden = true
                }
            }
        }
        // Set timeout for 15 seconds
        timeoutTimer.schedule(deadline: .now() + 15)
        timeoutTimer.resume()
        
        // Update loading display
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.loadingLabel.text = "Loading folder with \(feeds.count) feeds..."
            self.loadingLabel.isHidden = false
        }
        
        // For each feed, load its articles
        for feed in feeds {
            group.enter()
            
            // Use a helper method to load the articles
            loadArticlesForFeed(feed) { [weak self] items in
                guard let self = self else {
                    group.leave()
                    return
                }
                
                // Add to folder items
                folderItems.append(contentsOf: items)
                group.leave()
            }
        }
        
        // When all articles are loaded
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // Cancel the timeout timer since we completed normally
            timeoutTimer.cancel()
            
            // Log result
            print("DEBUG: Loaded \(folderItems.count) items across all feeds in folder")
            
            // Get the "Hide Read Articles" setting
            let hideReadArticles = UserDefaults.standard.bool(forKey: "hideReadArticles")
            
            // Update read status and filter based on read setting
            var readFilteredItems: [RSSItem] = []
            
            for i in 0..<folderItems.count {
                let normLink = self.normalizeLink(folderItems[i].link)
                let isRead = self.readLinks.contains(normLink)
                
                folderItems[i].isRead = isRead
                
                // If setting is enabled (hideReadArticles), only include unread items
                // If setting is disabled, include all items
                if !isRead || !hideReadArticles {
                    readFilteredItems.append(folderItems[i])
                }
            }
            
            // Then filter by keywords if content filtering is enabled
            var filteredItems: [RSSItem] = []
            if self.isContentFilteringEnabled && !self.filterKeywords.isEmpty {
                // Filter out articles that match any of the filter keywords
                filteredItems = readFilteredItems.filter { !self.shouldFilterArticle($0) }
                print("DEBUG: Keyword filtered \(readFilteredItems.count) items to \(filteredItems.count) items")
            } else {
                // No keyword filtering, use all read-filtered items
                filteredItems = readFilteredItems
            }
            
            if hideReadArticles {
                print("DEBUG: Filtered \(folderItems.count) total items to \(readFilteredItems.count) unread items")
            } else {
                print("DEBUG: Showing all \(folderItems.count) items including read articles")
            }
            
            // Sort the filtered items
            var sortedItems = filteredItems
            self.sortFilteredItems(&sortedItems)
            
            // Update the items and reload table
            self.items = sortedItems
            self.tableView.reloadData()
            
            // Show the table
            self.tableView.isHidden = false
            self.loadingIndicator.stopAnimating()
            self.loadingLabel.isHidden = true
            self.stopRefreshAnimation()
            self.refreshControl.endRefreshing()
            self.updateFooterVisibility()
            
            // Scroll to top safely
            self.safeScrollToTop()
            
            // Cancel the refresh timeout timer since we're done
            self.refreshTimeoutTimer?.invalidate()
            self.refreshTimeoutTimer = nil
            
            // Final debug info
            if sortedItems.isEmpty {
                // Determine if it's because there are no articles at all
                // or if all articles have been read
                if folderItems.isEmpty {
                    print("DEBUG: No articles found for folder feeds")
                    
                    // Show empty state message
                    self.loadingLabel.text = "No articles found in this folder"
                    self.loadingLabel.isHidden = false
                } else {
                    print("DEBUG: All articles in this folder have been read")
                    
                    // Show "all read" message
                    self.loadingLabel.text = "All articles in this folder have been read"
                    self.loadingLabel.isHidden = false
                }
            }
        }
    }
    
    /// Helper method to parse RSS data
    private func parseRSSData(_ data: Data, source: String) -> [RSSItem] {
        // We'll implement our own simplified RSS parser here to avoid dependencies
        let parser = XMLParser(data: data)
        let delegate = SimpleRSSParser(source: source)
        parser.delegate = delegate
        
        if parser.parse() {
            return delegate.items
        } else {
            print("DEBUG: XML parsing failed for \(source)")
            return []
        }
    }
    
    /// A simple RSS parser delegate implementation
    private class SimpleRSSParser: NSObject, XMLParserDelegate {
        private(set) var items: [RSSItem] = []
        private var currentElement = ""
        private var currentTitle = ""
        private var currentLink = ""
        private var currentPubDate = ""
        private var currentDescription = ""
        private var parsingItem = false
        private var feedSource: String
        
        init(source: String) {
            self.feedSource = source
            super.init()
        }
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            currentElement = elementName
            
            if elementName == "item" || elementName == "entry" {
                parsingItem = true
                currentTitle = ""
                currentLink = ""
                currentPubDate = ""
                currentDescription = ""
            }
            
            // Handle Atom links which use href attribute
            if elementName == "link", let href = attributeDict["href"] {
                currentLink = href
            }
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if !parsingItem { return }
            
            switch currentElement {
            case "title":
                currentTitle += string
            case "link":
                if currentLink.isEmpty { // Only append if not already set by attribute
                    currentLink += string
                }
            case "pubDate", "published", "updated":
                currentPubDate += string
            case "description", "summary", "content":
                currentDescription += string
            default:
                break
            }
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if (elementName == "item" || elementName == "entry") && parsingItem {
                // Only add items with at least a title and link
                if !currentTitle.isEmpty && !currentLink.isEmpty {
                    let item = RSSItem(
                        title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                        pubDate: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines),
                        source: feedSource,
                        description: currentDescription.isEmpty ? nil : currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    
                    items.append(item)
                }
                
                parsingItem = false
            }
        }
    }
    
    /// Helper method to load articles for a specific feed
    internal func loadArticlesForFeed(_ feed: RSSFeed, completion: @escaping ([RSSItem]) -> Void) {
        print("DEBUG: Loading articles for feed: \(feed.title) - URL: \(feed.url)")
        
        // Set a timeout to ensure we always complete
        let timeoutTimer = DispatchWorkItem {
            print("DEBUG: Feed loading timed out for \(feed.title)")
            DispatchQueue.main.async {
                completion([])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutTimer)
        
        // First try loading from memory cache or network
        if let url = URL(string: feed.url) {
            // Process the RSS feed directly
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                // Cancel the timeout since we got a response
                timeoutTimer.cancel()
                
                guard let self = self else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }
                
                if let data = data, error == nil {
                    // Create a parser for the RSS feed
                    print("DEBUG: Attempting to parse RSS data for \(feed.title)")
                    
                    // This approach will directly use the XMLParser to parse the RSS feed data
                    // without requiring the RSSParser class
                    var items = self.parseRSSData(data, source: feed.title)
                    
                    if !items.isEmpty {
                        //print("DEBUG: Successfully parsed feed \(feed.title) - Found \(items.count) items")
                        
                        // Filter out read items
                        let unreadItems = items.filter { item in
                            let normalizedLink = self.normalizeLink(item.link)
                            return !self.readLinks.contains(normalizedLink)
                        }
                        
                        print("DEBUG: \(feed.title): \(items.count) total, \(unreadItems.count) unread")
                        
                        // Return items immediately
                        DispatchQueue.main.async {
                            completion(unreadItems)
                        }
                        return
                    } else {
                        print("DEBUG: No items found in feed \(feed.title)")
                    }
                }
                
                // If live feed fails, try the CloudKit backup
                print("DEBUG: Live feed failed, trying CloudKit backup for \(feed.title)")
                self.loadArticlesFromCloudKit(feed) { items in
                    DispatchQueue.main.async {
                        completion(items)
                    }
                }
            }
            task.resume()
        } else {
            // Invalid URL, try CloudKit backup
            // Cancel the timeout timer
            timeoutTimer.cancel()
            
            loadArticlesFromCloudKit(feed) { items in
                DispatchQueue.main.async {
                    completion(items)
                }
            }
        }
    }
    
    /// Helper to load articles from CloudKit backup
    private func loadArticlesFromCloudKit(_ feed: RSSFeed, completion: @escaping ([RSSItem]) -> Void) {
        // Use the container and database directly
        let database = CKContainer.default().privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "feedArticlesRecord-\(feed.url)")
        
        // Set a timeout to ensure we always complete
        let timeoutTimer = DispatchWorkItem {
            print("DEBUG: CloudKit fetch timed out for \(feed.title)")
            DispatchQueue.main.async {
                completion([])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeoutTimer)
        
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            // Cancel the timeout since we got a response
            timeoutTimer.cancel()
            
            guard let self = self else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            DispatchQueue.main.async {
                // Handle error cases
                if let ckError = error as? CKError {
                    print("DEBUG: CloudKit error for \(feed.title): \(ckError.localizedDescription)")
                    completion([])
                    return
                }
                
                if record == nil {
                    print("DEBUG: No CloudKit backup found for \(feed.title)")
                    completion([])
                    return
                }
                
                // Process the record data if available
                if let data = record?["articles"] as? Data {
                    do {
                        let articles = try JSONDecoder().decode([ArticleSummary].self, from: data)
                        print("DEBUG: Found \(articles.count) articles in CloudKit for \(feed.title)")
                        
                        // Convert to RSSItems and filter out read items
                        let items = articles.compactMap { article -> RSSItem? in
                            let normalizedLink = self.normalizeLink(article.link)
                            
                            // Skip read items
                            if self.readLinks.contains(normalizedLink) {
                                return nil
                            }
                            
                            return RSSItem(
                                title: article.title,
                                link: article.link,
                                pubDate: article.pubDate,
                                source: feed.title
                            )
                        }
                        
                        completion(items)
                    } catch {
                        print("Error decoding articles for feed \(feed.title): \(error.localizedDescription)")
                        completion([])
                    }
                } else {
                    print("DEBUG: No articles data found in CloudKit record for \(feed.title)")
                    completion([])
                }
            }
        }
    }

    // This will be handled in the main class file
    
    @objc func refreshButtonTapped() {
        // Cancel any existing timeout timer
        refreshTimeoutTimer?.invalidate()
        
        // 1) Hide tableView and show loading indicator
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        
        // 2) Start showing the refresh spinner
        if !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }
        
        // 3) Start refresh button animation
        startRefreshAnimation()
        
        // Reset the scroll position tracker to ensure we start at the top after refresh
        previousMinVisibleRow = 0
        
        // Create a hard timeout to ensure UI is restored no matter what
        refreshTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Only take action if table is still hidden
            if self.tableView.isHidden {
                print("DEBUG: Hard timeout triggered for refresh operation")
                
                // Force UI to be restored
                DispatchQueue.main.async {
                    self.tableView.isHidden = false
                    self.loadingIndicator.stopAnimating()
                    self.loadingLabel.isHidden = true
                    self.stopRefreshAnimation()
                    self.refreshControl.endRefreshing()
                    self.updateFooterVisibility()
                    
                    // Scroll to top safely
                    self.safeScrollToTop()
                    
                    // Show an error message
                    self.loadingLabel.text = "Refresh timed out. Please try again."
                    self.loadingLabel.isHidden = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.loadingLabel.isHidden = true
                    }
                }
            }
        }
        
        // 4) Based on the current feed type, refresh the appropriate content
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
            // For smart folder view, just reload all feeds
            // The smart folder filtering will happen in updateTableViewContent
            loadRSSFeeds()
            
        case .bookmarks:
            // Refresh bookmarked feeds
            loadBookmarkedFeeds()
            
        case .heart:
            // Refresh hearted feeds
            loadHeartedFeeds()
        }
    }
    
    @objc func openSettings() {
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
    }
    
    @objc func handleStyleChanged() {
        // Update table row height estimates
        tableView.estimatedRowHeight = useEnhancedStyle ? 120 : 60
        
        // Reload the table to apply new style
        tableView.reloadData()
    }
    
    // MARK: - Refresh Animation
    
    func startRefreshAnimation() {
        // Create a direct animation on the UIBarButtonItem
        guard let refreshButton = self.refreshButton else {
            print("Refresh button not available")
            return
        }
        
        // Create a UIImageView to hold the animation
        let imageView = UIImageView(image: UIImage(named: "refresh")?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = AppColors.dynamicIconColor
        imageView.contentMode = .scaleAspectFit
        
        // Set up the rotation animation
        let rotation = CABasicAnimation(keyPath: "transform.rotation")
        rotation.fromValue = 0.0
        rotation.toValue = CGFloat.pi * 2.0
        rotation.duration = 1.0
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        
        // Apply the animation
        imageView.layer.add(rotation, forKey: "rotationAnimation")
        
        // Resize to match bar button item size
        let resizedImageView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        imageView.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        imageView.center = CGPoint(x: resizedImageView.bounds.midX, y: resizedImageView.bounds.midY)
        resizedImageView.addSubview(imageView)
        
        // Replace the current button with this animated view
        refreshButton.customView = resizedImageView
    }
    
    func stopRefreshAnimation() {
        // Return to the normal button state
        guard let refreshButton = self.refreshButton else { return }
        
        // Remove the custom view to restore the normal button
        refreshButton.customView = nil
        
        // Recreate the standard button
        refreshButton.image = resizeImage(
            UIImage(named: "refresh"),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        refreshButton.tintColor = AppColors.dynamicIconColor
    }
    
    // MARK: - Sorting Logic
    func sortItems(ascending: Bool) {
        isSortedAscending = ascending
        // Save sort order to UserDefaults
        UserDefaults.standard.set(ascending, forKey: "articleSortAscending")
        
        // Sort the current items using the date utilities
        items.sort {
            // Get dates for both items
            let date1 = DateUtils.parseDate($0.pubDate)
            let date2 = DateUtils.parseDate($1.pubDate)
            
            // If both dates can be parsed, use them for comparison
            if let d1 = date1, let d2 = date2 {
                return ascending ? d1 < d2 : d1 > d2
            }
            
            // Handle other cases (one or both dates can't be parsed)
            if date1 != nil { return ascending ? false : true }
            if date2 != nil { return ascending ? true : false }
            
            if !$0.pubDate.isEmpty && !$1.pubDate.isEmpty {
                return ascending ? $0.pubDate < $1.pubDate : $0.pubDate > $1.pubDate
            }
            
            if $0.pubDate.isEmpty { return ascending ? true : false }
            if $1.pubDate.isEmpty { return ascending ? false : true }
            
            return false
        }
        
        // Also sort the allItems array if we're viewing the RSS feed
        if case .rss = currentFeedType {
            _allItems.sort {
                let date1 = DateUtils.parseDate($0.pubDate)
                let date2 = DateUtils.parseDate($1.pubDate)
                
                if let d1 = date1, let d2 = date2 {
                    return ascending ? d1 < d2 : d1 > d2
                }
                
                if date1 != nil { return ascending ? false : true }
                if date2 != nil { return ascending ? true : false }
                
                if !$0.pubDate.isEmpty && !$1.pubDate.isEmpty {
                    return ascending ? $0.pubDate < $1.pubDate : $0.pubDate > $1.pubDate
                }
                
                if $0.pubDate.isEmpty { return ascending ? true : false }
                if $1.pubDate.isEmpty { return ascending ? false : true }
                
                return false
            }
        }
        
        // Reload the table to show newly sorted items
        tableView.reloadData()
    }
    
    func updateTableViewContent() {
        switch currentFeedType {
        case .rss:
            if !hasLoadedRSSFeeds {
                // If feeds haven't been loaded yet, hide tableView and load them
                tableView.isHidden = true
                loadingIndicator.startAnimating()
                startRefreshAnimation() // Start refresh button animation
                items.removeAll()
                loadRSSFeeds()
            } else {
                // Use the cached items from the initial load.
                // Hide the tableView briefly while reloading
                tableView.isHidden = true
                loadingIndicator.startAnimating()
                startRefreshAnimation() // Start refresh button animation
                
                // Step 1: First filter by read status based on settings
                let hideReadArticles = UserDefaults.standard.bool(forKey: "hideReadArticles")
                var filteredItems = allItems
                
                if hideReadArticles {
                    // Hide read articles when setting is enabled
                    filteredItems = allItems.filter { !ReadStatusTracker.shared.isArticleRead(link: $0.link) && !$0.isRead }
                    print("DEBUG: Read status filtered \(allItems.count) items to \(filteredItems.count) items")
                }
                
                // Step 2: Apply content filtering if enabled
                if self.isContentFilteringEnabled && !self.filterKeywords.isEmpty {
                    // Filter out articles that match any of the filter keywords
                    items = filteredItems.filter { !self.shouldFilterArticle($0) }
                    print("DEBUG: Keyword filtered \(filteredItems.count) items to \(items.count) items")
                } else {
                    // No keyword filtering
                    items = filteredItems
                }
                tableView.reloadData()
                
                // Show tableView after a short delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tableView.isHidden = false
                    self.loadingIndicator.stopAnimating()
                    self.loadingLabel.isHidden = true
                    self.stopRefreshAnimation() // Stop refresh button animation
                    
                    // Extra step to ensure all UI elements are visible
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // This delayed call helps ensure the table is fully laid out
                        self.updateFooterVisibility() // Ensure footer is visible with correct state
                        self.updateReadStatusIndicator() // Update the nav bar indicator
                    }
                }
            }
        case .smartFolder(let id):
            // Handle smart folder case
            if let folder = currentSmartFolder, folder.id == id {
                loadSmartFolderContents(folder: folder)
            } else {
                // Smart folder not loaded yet, load it first
                StorageManager.shared.getSmartFolders { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        if case .success(let folders) = result,
                           let folder = folders.first(where: { $0.id == id }) {
                            self.currentSmartFolder = folder
                            self.loadSmartFolderContents(folder: folder)
                        } else {
                            // Smart folder not found, fall back to all feeds
                            self.currentFeedType = .rss
                            self.updateTableViewContent()
                        }
                    }
                }
            }
            
        case .bookmarks:
            // For bookmarks and heart feeds, briefly hide the tableView while loading
            tableView.isHidden = true
            loadingIndicator.startAnimating()
            startRefreshAnimation() // Start refresh button animation
            
            loadBookmarkedFeeds()
            
            // Show tableView after a short delay to ensure smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.tableView.isHidden = false
                self.loadingIndicator.stopAnimating()
                self.loadingLabel.isHidden = true
                self.stopRefreshAnimation() // Stop refresh button animation
                self.updateFooterVisibility() // Ensure footer is visible with correct state
                
                // Scroll to top of the list
                if !self.items.isEmpty {
                    self.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
                }
            }
        case .heart:
            // For bookmarks and heart feeds, briefly hide the tableView while loading
            tableView.isHidden = true
            loadingIndicator.startAnimating()
            startRefreshAnimation() // Start refresh button animation
            
            loadHeartedFeeds()
            
            // Show tableView after a short delay to ensure smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.tableView.isHidden = false
                self.loadingIndicator.stopAnimating()
                self.loadingLabel.isHidden = true
                self.stopRefreshAnimation() // Stop refresh button animation
                self.updateFooterVisibility() // Ensure footer is visible with correct state
                
                // Scroll to top of the list
                if !self.items.isEmpty {
                    self.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
                }
            }
        case .folder(let folderId):
            // For folder feeds, briefly hide the tableView while loading
            tableView.isHidden = true
            loadingIndicator.startAnimating()
            startRefreshAnimation() // Start refresh button animation
            
            // Check if we already have the folder
            if let folder = currentFolder, folder.id == folderId {
                loadFolderFeeds(folder: folder)
            } else {
                // Load the folder first
                StorageManager.shared.getFolders { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let folders):
                            if let folder = folders.first(where: { $0.id == folderId }) {
                                self.currentFolder = folder
                                self.loadFolderFeeds(folder: folder)
                            } else {
                                // Folder not found, return to all feeds
                                self.currentFeedType = .rss
                            }
                        case .failure(let error):
                            print("Error loading folder: \(error.localizedDescription)")
                            // Return to all feeds on error
                            self.currentFeedType = .rss
                        }
                    }
                }
            }
        }
        updateFooterVisibility()
    }
    
    func loadBookmarkedFeeds() {
        // First filter the complete list based on bookmarked links using normalized links
        var bookmarkedFilteredItems = self._allItems.filter { item in
            let normalizedLink = self.normalizeLink(item.link)
            return self.bookmarkedItems.contains { self.normalizeLink($0) == normalizedLink }
        }
        
        // Then apply keyword filtering if enabled
        var filteredItems: [RSSItem]
        if self.isContentFilteringEnabled && !self.filterKeywords.isEmpty {
            // Filter out articles that match any of the filter keywords
            filteredItems = bookmarkedFilteredItems.filter { !self.shouldFilterArticle($0) }
            print("DEBUG: Keyword filtered \(bookmarkedFilteredItems.count) bookmarked items to \(filteredItems.count) items")
        } else {
            // No keyword filtering, use all bookmarked items
            filteredItems = bookmarkedFilteredItems
        }
        
        // Sort the filtered items based on the current sort order
        sortFilteredItems(&filteredItems)
        self.items = filteredItems
        // Reload data before showing the tableView
        tableView.reloadData()
    }

    func loadHeartedFeeds() {
        // First filter the complete list based on hearted links using normalized links
        var heartedFilteredItems = self._allItems.filter { item in
            let normalizedLink = self.normalizeLink(item.link)
            return self.heartedItems.contains { self.normalizeLink($0) == normalizedLink }
        }
        
        // Then apply keyword filtering if enabled
        var filteredItems: [RSSItem]
        if self.isContentFilteringEnabled && !self.filterKeywords.isEmpty {
            // Filter out articles that match any of the filter keywords
            filteredItems = heartedFilteredItems.filter { !self.shouldFilterArticle($0) }
            print("DEBUG: Keyword filtered \(heartedFilteredItems.count) hearted items to \(filteredItems.count) items")
        } else {
            // No keyword filtering, use all hearted items
            filteredItems = heartedFilteredItems
        }
        
        // Sort the filtered items based on the current sort order
        sortFilteredItems(&filteredItems)
        self.items = filteredItems
        // Reload data before showing the tableView
        tableView.reloadData()
    }
    
    // Helper function to sort a given array of items based on the current setting
    func sortFilteredItems(_ itemsToSort: inout [RSSItem]) {
        itemsToSort.sort {
            // Get dates for both items
            let date1 = DateUtils.parseDate($0.pubDate)
            let date2 = DateUtils.parseDate($1.pubDate)
            
            // If both dates can be parsed, use them for comparison
            if let d1 = date1, let d2 = date2 {
                return self.isSortedAscending ? d1 < d2 : d1 > d2
            }
            
            // If only one date can be parsed, the one with a valid date should come first
            if date1 != nil {
                return self.isSortedAscending ? false : true  // Valid date first in descending order
            }
            if date2 != nil {
                return self.isSortedAscending ? true : false  // Valid date first in descending order
            }
            
            // If neither date can be parsed and both are not empty, compare strings
            if !$0.pubDate.isEmpty && !$1.pubDate.isEmpty {
                // Just use string comparison as a fallback
                return self.isSortedAscending ? $0.pubDate < $1.pubDate : $0.pubDate > $1.pubDate
            }
            
            // Place empty dates at the end
            if $0.pubDate.isEmpty {
                return self.isSortedAscending ? true : false
            }
            if $1.pubDate.isEmpty {
                return self.isSortedAscending ? false : true
            }
            
            // If we're here, both are empty - considered equal
            return false
        }
    }
}
