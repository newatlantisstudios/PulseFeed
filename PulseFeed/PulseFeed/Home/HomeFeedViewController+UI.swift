import UIKit
import SafariServices
import Foundation

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
            self, action: #selector(refreshFeeds), for: .valueChanged)
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
            heartButton
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
        renderOriginal: Bool = false
    ) -> UIBarButtonItem {
        let renderingMode: UIImage.RenderingMode = renderOriginal ? .alwaysOriginal : .alwaysTemplate
        let buttonImage = resizeImage(
            UIImage(named: imageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(renderingMode)

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
        guard let leftButtons = navigationItem.leftBarButtonItems, leftButtons.count >= 4 else {
            return
        }
        
        // leftButtons order: [rss, refresh, bookmark, heart]
        // Update the RSS button image:
        let rssImageName = (currentFeedType == .rss) ? "rssFilled" : "rss"
        rssButton?.image = resizeImage(
            UIImage(named: rssImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        
        // Do not change the refresh button (index 1)
        
        // Update the read status indicator when in RSS mode
        updateReadStatusIndicator()
        
        // Update the Bookmark button image:
        let bookmarkImageName = (currentFeedType == .bookmarks) ? "bookmarkFilled" : "bookmark"
        bookmarkButton?.image = resizeImage(
            UIImage(named: bookmarkImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
        
        // Update the Heart button image:
        let heartImageName = (currentFeedType == .heart) ? "heartFilled" : "heart"
        heartButton?.image = resizeImage(
            UIImage(named: heartImageName),
            targetSize: CGSize(width: 24, height: 24)
        )?.withRenderingMode(.alwaysTemplate)
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
        tableView.register(
            UITableViewCell.self, forCellReuseIdentifier: "RSSCell")
        tableView.register(
            EnhancedRSSCell.self, forCellReuseIdentifier: EnhancedRSSCell.identifier)
        
        // Set appropriate row height depending on the style
        tableView.estimatedRowHeight = useEnhancedStyle ? 120 : 60
        tableView.rowHeight = UITableView.automaticDimension
        
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
            UIColor(hex: "121212").cgColor,
            UIColor(hex: "2A2A2A").cgColor
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
        // Only show the footer for RSS feed type
        if currentFeedType == .rss {
            // Add a new method to ensure footer is correctly sized and positioned
            addFooterToTableView()
        } else {
            // Hide footer for bookmarks and heart feeds
            tableView.tableFooterView = nil
        }
    }
    
    func refreshFooterView() {
        if currentFeedType == .rss {
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
        
        // Only modify the table footer when in RSS mode
        if currentFeedType == .rss {
            // Create a footer view to show the read status
            let footerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 60))
            footerView.backgroundColor = AppColors.background
            
            // Create a label to display the status
            let statusLabel = UILabel()
            statusLabel.translatesAutoresizingMaskIntoConstraints = false
            statusLabel.textAlignment = .center
            statusLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
            
            // Set different text and color based on read status
            if allRead && hasArticles {
                statusLabel.text = "✓ All Articles Read"
                statusLabel.textColor = .systemGreen
            } else if hasArticles {
                statusLabel.text = "You have unread articles"
                statusLabel.textColor = AppColors.primary
            } else {
                statusLabel.text = "No articles available"
                statusLabel.textColor = .systemGray
            }
            
            // Add the label to the footer
            footerView.addSubview(statusLabel)
            
            // Set up constraints
            NSLayoutConstraint.activate([
                statusLabel.centerXAnchor.constraint(equalTo: footerView.centerXAnchor),
                statusLabel.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
                statusLabel.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 20),
                statusLabel.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -20)
            ])
            
            // Set as table footer
            tableView.tableFooterView = footerView
        }
    }
    
    func addFooterToTableView() {
        // Force update read status first
        for i in 0..<items.count {
            let normLink = normalizeLink(items[i].link)
            items[i].isRead = readLinks.contains(normLink)
        }
        
        // Update the read status indicator first, which creates a consistent footer
        updateReadStatusIndicator()
        
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
            
            // Step 3: Also update the full allItems collection
            for i in 0..<self._allItems.count {
                self._allItems[i].isRead = true
            }
            
            // Step 4: Save the new read state locally
            self.saveReadState()
            
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
        
        if allRead && currentFeedType == .rss {
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
        currentFeedType = .rss
    }

    @objc func bookmarkButtonTapped() {
        currentFeedType = .bookmarks
    }

    @objc func heartButtonTapped() {
        currentFeedType = .heart
    }

    @objc func openSettings() {
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
    }
    
    @objc func refreshButtonTapped() {
        // 1) Hide tableView and show loading indicator
        tableView.isHidden = true
        loadingIndicator.startAnimating()
        
        // 2) Manually begin showing the refresh spinner (it will be hidden with the tableView)
        if !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }
        
        // 3) Now do your actual refresh logic
        refreshFeeds()
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
        if currentFeedType == .rss {
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
                
                items = allItems
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
            }
        }
        updateFooterVisibility()
    }
    
    func loadBookmarkedFeeds() {
        // Filter the complete list based on bookmarked links using normalized links
        var filteredItems = self._allItems.filter { item in
            let normalizedLink = self.normalizeLink(item.link)
            return self.bookmarkedItems.contains { self.normalizeLink($0) == normalizedLink }
        }
        // Sort the filtered items based on the current sort order
        sortFilteredItems(&filteredItems)
        self.items = filteredItems
        // Reload data before showing the tableView
        tableView.reloadData()
    }

    func loadHeartedFeeds() {
        // Filter the complete list based on hearted links using normalized links
        var filteredItems = self._allItems.filter { item in
            let normalizedLink = self.normalizeLink(item.link)
            return self.heartedItems.contains { self.normalizeLink($0) == normalizedLink }
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