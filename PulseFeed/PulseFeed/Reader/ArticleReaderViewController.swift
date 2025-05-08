import UIKit
import WebKit
import SafariServices

class ArticleReaderViewController: UIViewController {
    
    // MARK: - Properties
    
    let webView = WKWebView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    let titleLabel = UILabel()
    let sourceLabel = UILabel()
    let dateLabel = UILabel()
    let toolbar = UIToolbar()
    let progressView = UIProgressView()
    
    // Reading progress
    let readingProgressBar = ReadingProgressBar(frame: .zero)
    private var currentReadingProgress: Float = 0
    private var lastProgressUpdateTime: Date = Date()
    private var isTrackingProgress = true
    private var scrollObserver: NSKeyValueObservation?
    
    var typographySettings = TypographySettings.loadFromUserDefaults()
    var fontColor: UIColor = .label
    var backgroundColor: UIColor = .systemBackground
    var estimatedReadingTimeLabel: UILabel?
    
    var item: RSSItem? {
        didSet {
            // Keep article property in sync for backward compatibility
            article = item
        }
    }
    
    var article: RSSItem? { // Added for backward compatibility with SearchResultsViewController
        didSet {
            // Keep item property in sync
            if item != article {
                item = article
            }
        }
    }
    
    var htmlContent: String?
    private var webViewObservation: NSKeyValueObservation?
    
    // Navigation properties
    var allItems: [RSSItem] = []
    var currentItemIndex: Int = -1
    
    // Edge swipe visual indicators
    private let leftSwipeIndicator = UIView()
    private let rightSwipeIndicator = UIView()
    
    // This enum is kept for backward compatibility
    // It will be removed in future versions as we migrate to the theme system
    @available(*, deprecated, message: "Use ArticleThemeManager instead")
    enum ReadingMode: String {
        case regular = "regular"
        case sepia = "sepia"
        case dark = "dark"
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNavigationBar()
        setupThemeSupport()
        setupReadingProgressTracking()
        setupSwipeGestures()
        setupSwipeIndicators()
        findCurrentItemIndex()
        loadArticleContent()
        
        // Listen for font size and typography changes
        NotificationCenter.default.addObserver(self, selector: #selector(fontSizeChanged(_:)), name: Notification.Name("fontSizeChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(typographySettingsChanged(_:)), name: Notification.Name("typographySettingsChanged"), object: nil)
        
        // Set up web view progress tracking
        webViewObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, change in
            guard let self = self else { return }
            
            if let newValue = change.newValue {
                self.updateProgress(Float(newValue))
            }
        }
    }
    
    // MARK: - Swipe Gestures
    
    private func setupSwipeGestures() {
        // Use SwipeGestureManager to add gestures for article navigation
        SwipeGestureManager.shared.addArticleNavigationGestures(
            to: self,
            previousAction: { [weak self] in
                self?.navigateToPreviousArticle()
            },
            nextAction: { [weak self] in
                self?.navigateToNextArticle()
            }
        )
    }
    
    @objc func handleArticleSwipe(_ gesture: UISwipeGestureRecognizer) {
        // This method will be called by the SwipeGestureManager
        // Actions are handled via closures
    }
    
    private func setupSwipeIndicators() {
        // Setup edge indicators that appear when user swipes
        leftSwipeIndicator.backgroundColor = AppColors.primary.withAlphaComponent(0.5)
        leftSwipeIndicator.layer.cornerRadius = 8
        leftSwipeIndicator.clipsToBounds = true
        leftSwipeIndicator.translatesAutoresizingMaskIntoConstraints = false
        leftSwipeIndicator.alpha = 0
        
        rightSwipeIndicator.backgroundColor = AppColors.primary.withAlphaComponent(0.5)
        rightSwipeIndicator.layer.cornerRadius = 8
        rightSwipeIndicator.clipsToBounds = true
        rightSwipeIndicator.translatesAutoresizingMaskIntoConstraints = false
        rightSwipeIndicator.alpha = 0
        
        // Create arrow indicators
        let leftArrow = UIImageView(image: UIImage(systemName: "chevron.left"))
        leftArrow.tintColor = .white
        leftArrow.translatesAutoresizingMaskIntoConstraints = false
        
        let rightArrow = UIImageView(image: UIImage(systemName: "chevron.right"))
        rightArrow.tintColor = .white
        rightArrow.translatesAutoresizingMaskIntoConstraints = false
        
        leftSwipeIndicator.addSubview(leftArrow)
        rightSwipeIndicator.addSubview(rightArrow)
        
        view.addSubview(leftSwipeIndicator)
        view.addSubview(rightSwipeIndicator)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            leftSwipeIndicator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            leftSwipeIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            leftSwipeIndicator.widthAnchor.constraint(equalToConstant: 40),
            leftSwipeIndicator.heightAnchor.constraint(equalToConstant: 60),
            
            rightSwipeIndicator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            rightSwipeIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            rightSwipeIndicator.widthAnchor.constraint(equalToConstant: 40),
            rightSwipeIndicator.heightAnchor.constraint(equalToConstant: 60),
            
            leftArrow.centerXAnchor.constraint(equalTo: leftSwipeIndicator.centerXAnchor),
            leftArrow.centerYAnchor.constraint(equalTo: leftSwipeIndicator.centerYAnchor),
            
            rightArrow.centerXAnchor.constraint(equalTo: rightSwipeIndicator.centerXAnchor),
            rightArrow.centerYAnchor.constraint(equalTo: rightSwipeIndicator.centerYAnchor)
        ])
    }
    
    private func findCurrentItemIndex() {
        // Find the current item's index in the array
        if let item = item {
            currentItemIndex = allItems.firstIndex(where: { $0.link == item.link }) ?? -1
        }
    }
    
    private func setupReadingProgressTracking() {
        guard item != nil else { return }
        
        // Configure reading progress bar
        readingProgressBar.translatesAutoresizingMaskIntoConstraints = false
        readingProgressBar.progressColor = AppColors.accent
        readingProgressBar.trackColor = AppColors.secondary.withAlphaComponent(0.2)
        readingProgressBar.height = 3
        
        // Add to view hierarchy - needs to be above the content but below loading indicators
        view.addSubview(readingProgressBar)
        view.bringSubviewToFront(progressView) // Keep the loading progress view on top
        
        // Set up constraints
        NSLayoutConstraint.activate([
            readingProgressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            readingProgressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            readingProgressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            readingProgressBar.heightAnchor.constraint(equalToConstant: 3)
        ])
        
        // Load previous reading progress
        loadSavedReadingProgress()
        
        // Set up scroll tracking
        setupScrollTracking()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        webViewObservation?.invalidate()
        scrollObserver?.invalidate()
        
        // Save final reading progress before deinitializing
        if currentReadingProgress > 0.01 {
            guard let item = item else { return }
            StorageManager.shared.saveReadingProgress(for: item.link, progress: currentReadingProgress, completion: { _, _ in })
        }
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        // Load typography settings
        loadTypographySettings()
        
        view.backgroundColor = backgroundColor
        
        // Setup progress view
        progressView.progressTintColor = AppColors.accent
        progressView.trackTintColor = AppColors.secondary.withAlphaComponent(0.2)
        progressView.progress = 0
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup title label
        titleLabel.font = typographySettings.fontFamily.font(withSize: 22, weight: .bold)
        titleLabel.textColor = fontColor
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup source label
        sourceLabel.font = typographySettings.fontFamily.font(withSize: 14, weight: .medium)
        sourceLabel.textColor = AppColors.secondary
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup date label
        dateLabel.font = typographySettings.fontFamily.font(withSize: 14)
        dateLabel.textColor = AppColors.secondary
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup reading time
        estimatedReadingTimeLabel = UILabel()
        estimatedReadingTimeLabel?.font = typographySettings.fontFamily.font(withSize: 14, weight: .regular)
        estimatedReadingTimeLabel?.textColor = AppColors.secondary
        estimatedReadingTimeLabel?.textAlignment = .right
        estimatedReadingTimeLabel?.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup web view
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = backgroundColor
        webView.isOpaque = false
        
        // Enable WKWebView to respect dark mode
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = backgroundColor
        }
        webView.scrollView.indicatorStyle = traitCollection.userInterfaceStyle == .dark ? .white : .default
        webView.allowsBackForwardNavigationGestures = false
        
        // Setup loading indicator
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()
        
        // Setup toolbar
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        setupToolbar()
        
        // Add subviews
        view.addSubview(progressView)
        view.addSubview(titleLabel)
        view.addSubview(sourceLabel)
        view.addSubview(dateLabel)
        if let estimatedReadingTimeLabel = estimatedReadingTimeLabel {
            view.addSubview(estimatedReadingTimeLabel)
        }
        view.addSubview(webView)
        view.addSubview(loadingIndicator)
        view.addSubview(toolbar)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),
            
            titleLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            sourceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        
        if let readingTimeLabel = estimatedReadingTimeLabel {
            NSLayoutConstraint.activate([
                readingTimeLabel.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 8),
                readingTimeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                readingTimeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                
                webView.topAnchor.constraint(equalTo: readingTimeLabel.bottomAnchor, constant: 16),
            ])
        } else {
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 16),
            ])
        }
        
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Update UI with article details
        updateArticleDetails()
    }
    
    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        
        // Create share button
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareArticle))
        
        // Create open in Safari button
        let safariButton = UIBarButtonItem(image: UIImage(systemName: "safari"), style: .plain, target: self, action: #selector(openInSafari))
        
        // Create a save for offline reading button
        let cacheButton = UIBarButtonItem(image: UIImage(systemName: "arrow.down.circle"), style: .plain, target: self, action: #selector(toggleOfflineCache))
        
        navigationItem.rightBarButtonItems = [shareButton, safariButton, cacheButton]
        
        // Configure the back button with a proper title
        navigationItem.backButtonTitle = "Back"
    }
    
    private func setupToolbar() {
        // Create toolbar items
        let decreaseFontButton = UIBarButtonItem(image: UIImage(systemName: "textformat.size.smaller"), style: .plain, target: self, action: #selector(decreaseFontSize))
        
        let increaseFontButton = UIBarButtonItem(image: UIImage(systemName: "textformat.size.larger"), style: .plain, target: self, action: #selector(increaseFontSize))
        
        // Create reading mode button based on current theme
        let themeManager = ArticleThemeManager.shared
        let currentThemeName = themeManager.selectedTheme.name
        
        var modeIcon: UIImage?
        switch currentThemeName {
        case "System":
            modeIcon = UIImage(systemName: "sun.max")
        case "Light":
            modeIcon = UIImage(systemName: "sun.max.fill")
        case "Sepia":
            modeIcon = UIImage(systemName: "book")
        case "Dark":
            modeIcon = UIImage(systemName: "moon")
        default:
            modeIcon = UIImage(systemName: "paintpalette")
        }
        
        let toggleModeButton = UIBarButtonItem(image: modeIcon, style: .plain, target: self, action: #selector(toggleReadingMode))
        
        // Text justification button
        let justifyButton = UIBarButtonItem(image: UIImage(systemName: "text.justify"), style: .plain, target: self, action: #selector(toggleTextJustification))
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        // Add items to toolbar
        toolbar.items = [decreaseFontButton, flexibleSpace, toggleModeButton, flexibleSpace, justifyButton, flexibleSpace, increaseFontButton]
        toolbar.tintColor = AppColors.accent
    }
    
    // MARK: - Article Content
    
    private func loadArticleContent() {
        guard let item = item, let url = URL(string: item.link) else {
            showError("Invalid article URL")
            return
        }
        
        if let content = htmlContent {
            // If HTML content is already provided, use it
            displayContent(content)
        } else if let itemContent = item.content, !itemContent.isEmpty {
            // If the item already has full content (from full-text extraction), use it
            // but still cache it for offline reading
            displayContent(itemContent)
            self.htmlContent = itemContent
            
            // Calculate reading time
            self.calculateReadingTime(for: itemContent)
            
            // Cache the article for offline reading
            StorageManager.shared.cacheArticleContent(
                link: item.link,
                content: itemContent,
                title: item.title,
                source: item.source
            ) { success, error in
                if let error = error {
                    print("DEBUG: Failed to cache article: \(error.localizedDescription)")
                } else if success {
                    print("DEBUG: Successfully cached article with pre-extracted content: \(item.title)")
                    
                    // Update the navigation bar buttons
                    DispatchQueue.main.async {
                        self.updateOfflineCacheButton()
                    }
                }
            }
        } else {
            // First check if we have a cached version of this article
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.loadingIndicator.startAnimating()
                self.progressView.isHidden = false
                self.updateProgress(0.2)
            }
            
            StorageManager.shared.getCachedArticleContent(link: item.link) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let cachedArticle):
                    // We have a cached version, use it
                    DispatchQueue.main.async {
                        self.updateProgress(0.8)
                        self.loadingIndicator.stopAnimating()
                        
                        // Show cache indicator
                        self.showCachedIndicator(date: cachedArticle.cachedDate)
                        
                        // Display the cached content
                        self.displayContent(cachedArticle.content)
                        self.htmlContent = cachedArticle.content
                        
                        print("DEBUG: Loaded article from cache: \(item.title)")
                        self.updateProgress(1.0)
                        
                        // Hide progress view after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.progressView.isHidden = true
                        }
                    }
                    
                case .failure:
                    // No cached version, check if we're offline
                    if StorageManager.shared.isDeviceOffline {
                        DispatchQueue.main.async {
                            self.loadingIndicator.stopAnimating()
                            self.showError("No internet connection and no cached version available")
                            self.progressView.isHidden = true
                        }
                        return
                    }
                    
                    // We're online, fetch from network
                    DispatchQueue.main.async {
                        self.updateProgress(0.3)
                    }
                    
                    // Move the network request and processing to a background queue
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self = self else { return }
                        
                        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                            guard let self = self else { return }
                            
                            if let error = error {
                                DispatchQueue.main.async {
                                    self.loadingIndicator.stopAnimating()
                                    self.showError("Failed to load article: \(error.localizedDescription)")
                                    self.progressView.isHidden = true
                                }
                                return
                            }
                            
                            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                                DispatchQueue.main.async {
                                    self.loadingIndicator.stopAnimating()
                                    self.showError("Failed to decode article content")
                                    self.progressView.isHidden = true
                                }
                                return
                            }
                            
                            DispatchQueue.main.async {
                                self.updateProgress(0.6)
                            }
                            
                            // Extract and clean the content on the background thread
                            let cleanedContent = self.extractReadableContent(from: html, url: url)
                            
                            // Return to main thread for UI updates
                            DispatchQueue.main.async {
                                self.updateProgress(0.8)
                                
                                // Estimate reading time
                                self.calculateReadingTime(for: cleanedContent)
                                
                                // Display the content
                                self.displayContent(cleanedContent)
                                self.htmlContent = cleanedContent
                                
                                self.updateProgress(0.9)
                                
                                // Cache the article for offline reading
                                StorageManager.shared.cacheArticleContent(
                                    link: item.link,
                                    content: cleanedContent,
                                    title: item.title,
                                    source: item.source
                                ) { success, error in
                                    if let error = error {
                                        print("DEBUG: Failed to cache article: \(error.localizedDescription)")
                                    } else if success {
                                        print("DEBUG: Successfully cached article: \(item.title)")
                                        
                                        // Update the navigation bar buttons
                                        DispatchQueue.main.async {
                                            self.updateOfflineCacheButton()
                                        }
                                    }
                                }
                                
                                // Complete loading
                                self.loadingIndicator.stopAnimating()
                                self.updateProgress(1.0)
                                
                                // Hide progress view after a short delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.progressView.isHidden = true
                                }
                            }
                        }
                        task.resume()
                    }
                }
            }
        }
    }
    
    private func updateOfflineCacheButton() {
        // Update the cache button based on whether the article is cached
        guard let item = item else { return }
        
        StorageManager.shared.isArticleCached(link: item.link) { [weak self] isCached in
            DispatchQueue.main.async {
                guard let self = self, let rightBarButtonItems = self.navigationItem.rightBarButtonItems, rightBarButtonItems.count >= 3 else { return }
                
                let cacheButton = rightBarButtonItems[2]
                cacheButton.image = UIImage(systemName: isCached ? "arrow.down.circle.fill" : "arrow.down.circle")
            }
        }
    }
    
    private func showCachedIndicator(date: Date) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let dateString = formatter.string(from: date)
        
        let cachedLabel = UILabel()
        cachedLabel.text = "Offline Mode (Cached \(dateString))"
        cachedLabel.font = UIFont.systemFont(ofSize: 12)
        cachedLabel.textColor = .white
        cachedLabel.backgroundColor = AppColors.primary.withAlphaComponent(0.8)
        cachedLabel.textAlignment = .center
        cachedLabel.layer.cornerRadius = 4
        cachedLabel.clipsToBounds = true
        cachedLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(cachedLabel)
        
        NSLayoutConstraint.activate([
            cachedLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            cachedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cachedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cachedLabel.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        // Adjust the top constraint of the progressView to accommodate the cached indicator
        for constraint in progressView.constraints where constraint.firstAttribute == .top {
            constraint.constant = 28
        }
    }
    
    private func calculateReadingTime(for html: String) {
        // This calculation can be expensive for large articles
        // Ensure it runs on a background thread if called from main thread
        let performCalculation = {
            let text = html.removingHTMLTags()
            let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            
            // Average reading speed is about 200-250 words per minute
            let readingSpeed = 220
            let minutes = max(1, wordCount / readingSpeed)
            
            DispatchQueue.main.async { [weak self] in
                self?.estimatedReadingTimeLabel?.text = "\(minutes) min read"
            }
        }
        
        // Check if we're already on a background thread
        if Thread.isMainThread {
            DispatchQueue.global(qos: .userInitiated).async {
                performCalculation()
            }
        } else {
            performCalculation()
        }
    }
    
    private func extractReadableContent(from html: String, url: URL?) -> String {
        // Since this method is now always called from a background thread,
        // we can directly extract the content without additional threading
        return ContentExtractor.extractReadableContent(from: html, url: url)
    }
    
    func wrapInReadableHTML(content: String) -> String {
        // Get stored typography settings
        loadTypographySettings()
        
        // Check if we should use justified text
        let useJustifiedText = UserDefaults.standard.bool(forKey: "readerJustifiedText")
        let justifiedClass = useJustifiedText ? " justified" : ""
        
        // Get accent color from theme manager
        let themeManager = ArticleThemeManager.shared
        let (_, _, accentColor) = themeManager.getCurrentThemeColors(for: traitCollection)
        
        // Use ContentExtractor to wrap content in readable HTML
        let wrappedHTML = ContentExtractor.wrapInReadableHTML(
            content: "<div class=\"content\(justifiedClass)\">\(content)</div>",
            fontSize: typographySettings.fontSize,
            lineHeight: typographySettings.lineHeight,
            fontColor: fontColor.hexString,
            backgroundColor: backgroundColor.hexString,
            accentColor: accentColor.hexString
        )
        
        return wrappedHTML
    }
    
    func displayContent(_ html: String) {
        // Ensure we're on the main thread for WebView updates
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.displayContent(html)
            }
            return
        }
        
        // Wrap the content in readable HTML
        let wrappedHTML = wrapInReadableHTML(content: html)
        
        // Load the content into the web view
        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }
    
    private func updateArticleDetails() {
        guard let item = item else { return }
        
        titleLabel.text = item.title
        sourceLabel.text = item.source
        
        // Format date
        dateLabel.text = DateUtils.getTimeAgo(from: item.pubDate)
        
        // Update navigation title
        navigationItem.title = item.source
        
        // Update offline cache button
        updateOfflineCacheButton()
    }
    
    // MARK: - Reading Progress
    
    private func updateProgress(_ progress: Float) {
        progressView.setProgress(progress, animated: true)
    }
    
    // MARK: - Reading Progress Tracking
    
    private func setupScrollTracking() {
        // Set up scroll position observer to track reading progress
        scrollObserver = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, change in
            guard let self = self, self.isTrackingProgress else { return }
            
            // Only update progress every 500ms to avoid excessive updates
            let now = Date()
            if now.timeIntervalSince(self.lastProgressUpdateTime) < 0.5 {
                return
            }
            self.lastProgressUpdateTime = now
            
            self.updateReadingProgress()
        }
    }
    
    private func updateReadingProgress() {
        // Calculate reading progress based on scroll position
        let scrollView = webView.scrollView
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.size.height
        let contentOffset = scrollView.contentOffset.y
        
        // Avoid division by zero
        guard contentHeight > frameHeight else {
            return
        }
        
        // Calculate reading progress as percentage (0.0 to 1.0)
        let maxScrollableHeight = contentHeight - frameHeight
        var progress = Float(contentOffset / maxScrollableHeight)
        
        // Ensure progress is within valid range
        progress = min(1.0, max(0.0, progress))
        
        // Update the progress UI
        readingProgressBar.setProgress(progress, animated: true)
        
        // Store current progress for saving
        if abs(Float(progress) - currentReadingProgress) > 0.05 { // Only update if changed by more than 5%
            currentReadingProgress = progress
            saveReadingProgress()
        }
    }
    
    private func loadSavedReadingProgress() {
        guard let item = item else { return }
        
        StorageManager.shared.getReadingProgress(for: item.link) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let progress):
                    self.currentReadingProgress = progress
                    self.readingProgressBar.setProgress(progress, animated: false)
                    
                    // If progress is beyond the beginning, scroll to that position after content is loaded
                    if progress > 0.05 { // Only if progress is beyond the first 5%
                        self.scrollToSavedPosition = true
                    }
                case .failure:
                    // If there's an error, start from the beginning
                    self.currentReadingProgress = 0
                    self.readingProgressBar.setProgress(0, animated: false)
                }
            }
        }
    }
    
    private func saveReadingProgress() {
        guard let item = item else { return }
        
        // Only save if progress is meaningful (beyond the first 1%)
        // This helps avoid saving meaningless progress data for articles just opened
        if currentReadingProgress > 0.01 {
            StorageManager.shared.saveReadingProgress(for: item.link, progress: currentReadingProgress) { _, _ in
                // Nothing to do on completion
            }
        }
    }
    
    // Variable to track if we need to scroll to saved position
    private var scrollToSavedPosition = false
    
    // MARK: - Typography Settings
    
    func loadTypographySettings() {
        // Load typography settings
        typographySettings = TypographySettings.loadFromUserDefaults()
        
        // Get colors from theme manager
        let themeManager = ArticleThemeManager.shared
        let (textColor, bgColor, _) = themeManager.getCurrentThemeColors(for: traitCollection)
        
        // Update color properties
        fontColor = textColor
        backgroundColor = bgColor
        
        // Update UI with new colors
        view.backgroundColor = backgroundColor
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        titleLabel.textColor = fontColor
    }
    
    @objc private func fontSizeChanged(_ notification: Notification) {
        // Reload the article with new font size
        if let content = htmlContent {
            displayContent(content)
        }
    }
    
    @objc private func typographySettingsChanged(_ notification: Notification) {
        // Reload typography settings and update UI
        loadTypographySettings()
        
        // Update title and labels
        titleLabel.font = typographySettings.fontFamily.font(withSize: 22, weight: .bold)
        sourceLabel.font = typographySettings.fontFamily.font(withSize: 14, weight: .medium)
        dateLabel.font = typographySettings.fontFamily.font(withSize: 14)
        estimatedReadingTimeLabel?.font = typographySettings.fontFamily.font(withSize: 14, weight: .regular)
        
        // Reload the article content with new typography settings
        if let content = htmlContent {
            displayContent(content)
        }
    }
    
    // MARK: - Article Navigation
    
    func navigateToNextArticle() {
        guard !allItems.isEmpty, currentItemIndex >= 0, currentItemIndex < allItems.count - 1 else {
            // Show indicator that we're at the end of the list
            showNoMoreArticlesIndicator(direction: .next)
            return
        }
        
        // Save reading progress for current article
        saveReadingProgress()
        
        // Show visual indicator
        showNavigationIndicator(direction: .next)
        
        // Navigate to the next article
        currentItemIndex += 1
        loadNewArticle(allItems[currentItemIndex])
    }
    
    func navigateToPreviousArticle() {
        guard !allItems.isEmpty, currentItemIndex > 0 else {
            // Show indicator that we're at the beginning of the list
            showNoMoreArticlesIndicator(direction: .previous)
            return
        }
        
        // Save reading progress for current article
        saveReadingProgress()
        
        // Show visual indicator
        showNavigationIndicator(direction: .previous)
        
        // Navigate to the previous article
        currentItemIndex -= 1
        loadNewArticle(allItems[currentItemIndex])
    }
    
    private func loadNewArticle(_ newItem: RSSItem) {
        // Save the current article's reading progress before switching
        if let currentItem = item, currentReadingProgress > 0.01 {
            StorageManager.shared.saveReadingProgress(for: currentItem.link, progress: currentReadingProgress, completion: { _, _ in })
        }
        
        // Update the item
        item = newItem
        htmlContent = nil
        currentReadingProgress = 0
        scrollToSavedPosition = false
        
        // Reset UI
        loadingIndicator.startAnimating()
        progressView.isHidden = false
        progressView.progress = 0
        
        // Update UI
        updateArticleDetails()
        
        // Load the new article content
        loadArticleContent()
        
        // Add haptic feedback for navigation
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    enum NavigationDirection {
        case previous
        case next
    }
    
    private func showNavigationIndicator(direction: NavigationDirection) {
        // Show the appropriate edge indicator
        let indicator = direction == .previous ? leftSwipeIndicator : rightSwipeIndicator
        
        // Animate indicator
        UIView.animate(withDuration: 0.2, animations: {
            indicator.alpha = 1.0
        }, completion: { _ in
            UIView.animate(withDuration: 0.2, delay: 0.3, options: [], animations: {
                indicator.alpha = 0.0
            }, completion: nil)
        })
    }
    
    private func showNoMoreArticlesIndicator(direction: NavigationDirection) {
        // Show a toast message indicating no more articles
        let message = direction == .previous ? "No previous articles" : "No more articles"
        showToast(message: message)
        
        // Add a subtle haptic feedback to indicate we're at the end
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    // MARK: - Actions
    
    @objc private func shareArticle() {
        guard let item = item, let url = URL(string: item.link) else { return }
        
        let activityVC = UIActivityViewController(activityItems: [item.title, url], applicationActivities: nil)
        
        // Set the source view for iPad
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func openInSafari() {
        guard let item = item, let url = URL(string: item.link) else { return }
        
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        let safariVC = SFSafariViewController(url: url, configuration: configuration)
        safariVC.dismissButtonStyle = .close
        safariVC.preferredControlTintColor = AppColors.accent
        
        present(safariVC, animated: true)
    }
    
    @objc private func decreaseFontSize() {
        if typographySettings.fontSize > 12 {
            typographySettings.fontSize -= 2
            typographySettings.saveToUserDefaults()
            
            if let content = htmlContent {
                displayContent(content)
            }
        }
    }
    
    @objc private func increaseFontSize() {
        if typographySettings.fontSize < 32 {
            typographySettings.fontSize += 2
            typographySettings.saveToUserDefaults()
            
            if let content = htmlContent {
                displayContent(content)
            }
        }
    }
    
    @objc private func toggleReadingMode() {
        // Cycle through built-in themes using the theme manager
        let themeManager = ArticleThemeManager.shared
        let currentThemeName = themeManager.selectedTheme.name
        
        // Define the cycle sequence
        let themeSequence = ["System", "Light", "Sepia", "Dark"]
        
        // Find the current theme in the sequence
        if let currentIndex = themeSequence.firstIndex(of: currentThemeName) {
            // Get the next theme in the sequence
            let nextIndex = (currentIndex + 1) % themeSequence.count
            let nextThemeName = themeSequence[nextIndex]
            
            // Apply the next theme
            themeManager.selectTheme(named: nextThemeName)
            
            // Update the toolbar icon
            let modeImage: UIImage?
            switch nextThemeName {
            case "System":
                modeImage = UIImage(systemName: "sun.max")
            case "Light":
                modeImage = UIImage(systemName: "sun.max.fill")
            case "Sepia":
                modeImage = UIImage(systemName: "book")
            case "Dark":
                modeImage = UIImage(systemName: "moon")
            default:
                modeImage = UIImage(systemName: "paintpalette")
            }
            
            if let toggleModeButton = toolbar.items?[2] {
                toggleModeButton.image = modeImage
            }
        } else {
            // If current theme is not in the sequence, default to System
            themeManager.selectTheme(named: "System")
        }
    }
    
    @objc private func toggleTextJustification() {
        // Toggle justified text setting
        let isJustified = UserDefaults.standard.bool(forKey: "readerJustifiedText")
        UserDefaults.standard.set(!isJustified, forKey: "readerJustifiedText")
        
        // Update the toolbar button
        if let justifyButton = toolbar.items?[4] {
            justifyButton.image = UIImage(systemName: !isJustified ? "text.justify.leading" : "text.justify")
        }
        
        // Reload content with new justification setting
        if let content = htmlContent {
            displayContent(content)
        }
    }
    
    @objc private func toggleOfflineCache() {
        guard let item = item else { return }
        
        // Check if article is already cached
        StorageManager.shared.isArticleCached(link: item.link) { [weak self] isCached in
            guard let self = self else { return }
            
            if isCached {
                // Article is cached, ask if user wants to remove it
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "Remove from Offline Reading",
                        message: "Do you want to remove this article from your offline reading list?",
                        preferredStyle: .alert
                    )
                    
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
                        // Remove article from cache
                        StorageManager.shared.removeCachedArticle(link: item.link) { success, error in
                            DispatchQueue.main.async {
                                if success {
                                    // Update button
                                    if let rightBarButtonItems = self.navigationItem.rightBarButtonItems, rightBarButtonItems.count >= 3 {
                                        let cacheButton = rightBarButtonItems[2]
                                        cacheButton.image = UIImage(systemName: "arrow.down.circle")
                                    }
                                    
                                    // Show confirmation
                                    self.showToast(message: "Article removed from offline reading")
                                } else if let error = error {
                                    self.showError("Failed to remove article: \(error.localizedDescription)")
                                }
                            }
                        }
                    })
                    
                    self.present(alert, animated: true)
                }
            } else {
                // Article is not cached, cache it
                if let content = self.htmlContent {
                    DispatchQueue.main.async {
                        // Show loading indicator
                        let loadingAlert = UIAlertController(
                            title: "Saving for Offline Reading",
                            message: "Please wait...",
                            preferredStyle: .alert
                        )
                        
                        let loadingIndicator = UIActivityIndicatorView(style: .medium)
                        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
                        loadingIndicator.startAnimating()
                        
                        loadingAlert.view.addSubview(loadingIndicator)
                        
                        NSLayoutConstraint.activate([
                            loadingIndicator.centerYAnchor.constraint(equalTo: loadingAlert.view.centerYAnchor, constant: 10),
                            loadingIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor)
                        ])
                        
                        self.present(loadingAlert, animated: true)
                        
                        // Cache the article
                        StorageManager.shared.cacheArticleContent(
                            link: item.link,
                            content: content,
                            title: item.title,
                            source: item.source
                        ) { success, error in
                            DispatchQueue.main.async {
                                // Dismiss loading alert
                                loadingAlert.dismiss(animated: true) {
                                    if success {
                                        // Update button
                                        if let rightBarButtonItems = self.navigationItem.rightBarButtonItems, rightBarButtonItems.count >= 3 {
                                            let cacheButton = rightBarButtonItems[2]
                                            cacheButton.image = UIImage(systemName: "arrow.down.circle.fill")
                                        }
                                        
                                        // Show confirmation
                                        self.showToast(message: "Article saved for offline reading")
                                    } else if let error = error {
                                        self.showError("Failed to save article: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showError("No content available to save for offline reading")
                    }
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showToast(message: String) {
        let toastContainer = UIView()
        toastContainer.backgroundColor = AppColors.primary.withAlphaComponent(0.9)
        toastContainer.alpha = 0
        toastContainer.layer.cornerRadius = 16
        toastContainer.clipsToBounds = true
        
        let toastLabel = UILabel()
        toastLabel.textColor = UIColor.white
        toastLabel.text = message
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        toastLabel.numberOfLines = 0
        
        toastContainer.addSubview(toastLabel)
        view.addSubview(toastContainer)
        
        toastContainer.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            toastContainer.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -16),
            toastContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastContainer.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
            
            toastLabel.topAnchor.constraint(equalTo: toastContainer.topAnchor, constant: 8),
            toastLabel.leadingAnchor.constraint(equalTo: toastContainer.leadingAnchor, constant: 16),
            toastLabel.trailingAnchor.constraint(equalTo: toastContainer.trailingAnchor, constant: -16),
            toastLabel.bottomAnchor.constraint(equalTo: toastContainer.bottomAnchor, constant: -8),
        ])
        
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            toastContainer.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.2, delay: 2, options: .curveEaseOut, animations: {
                toastContainer.alpha = 0
            }, completion: { _ in
                toastContainer.removeFromSuperview()
            })
        })
    }
    
    // MARK: - Handle Dark Mode Changes
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            // Get current theme
            let themeManager = ArticleThemeManager.shared
            let currentThemeName = themeManager.selectedTheme.name
            
            // Only update if we're using the system theme that adapts to dark mode
            if currentThemeName == "System" {
                loadTypographySettings()
                
                // Reload the article to update colors
                if let content = htmlContent {
                    displayContent(content)
                }
            }
        }
    }
    
    // MARK: - Keyboard Shortcuts Support
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var keyCommands: [UIKeyCommand]? {
        // Keyboard shortcuts temporarily disabled
        return []
    }
    
    /// Keyboard shortcut help temporarily disabled
    @objc func showKeyboardShortcutHelp() {
        // Keyboard shortcuts disabled
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Become first responder to capture keyboard events
        becomeFirstResponder()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Resign first responder when leaving the view
        resignFirstResponder()
    }
}

// MARK: - WKNavigationDelegate

extension ArticleReaderViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        
        // Apply image caching script to the WebView
        let imageCachingScript = """
        document.addEventListener('DOMContentLoaded', function() {
            const images = document.querySelectorAll('img[data-cached="true"]');
            images.forEach(img => {
                if (!img.src) return;
                
                img.addEventListener('load', function() {
                    console.log('Image loaded successfully: ' + img.src);
                });
                
                img.addEventListener('error', function() {
                    console.log('Error loading image: ' + img.src);
                    // Apply fallback styling for failed images
                    this.style.background = '#f0f0f0';
                    this.style.display = 'flex';
                    this.style.alignItems = 'center';
                    this.style.justifyContent = 'center';
                    this.style.color = '#999';
                    this.style.padding = '20px';
                    this.style.border = '1px solid #ddd';
                    this.style.borderRadius = '8px';
                });
                
                // Apply lazy loading
                if ('loading' in HTMLImageElement.prototype) {
                    img.loading = 'lazy';
                }
            });
        });
        """
        
        webView.evaluateJavaScript(imageCachingScript) { _, error in
            if let error = error {
                print("Error executing image caching script: \(error)")
            }
        }
        
        // If we have a saved reading position, scroll to it after a short delay
        // to ensure the content is fully rendered
        if scrollToSavedPosition {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                // Temporarily disable progress tracking during programmatic scrolling
                self.isTrackingProgress = false
                
                // Calculate the scroll position based on saved progress
                let scrollView = self.webView.scrollView
                let contentHeight = scrollView.contentSize.height
                let frameHeight = scrollView.frame.size.height
                let maxScrollableHeight = contentHeight - frameHeight
                
                // Calculate y offset based on reading progress
                let targetOffset = CGFloat(self.currentReadingProgress) * maxScrollableHeight
                
                // Scroll to position with animation
                scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: true)
                
                // Re-enable tracking after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isTrackingProgress = true
                }
                
                // Reset flag
                self.scrollToSavedPosition = false
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        showError("Failed to load content: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow the initial load
        if navigationAction.navigationType == .other {
            decisionHandler(.allow)
            return
        }
        
        // For links clicked in the article, open them in WebViewController
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            decisionHandler(.cancel)
            
            // Check user preference for link handling
            let useInAppBrowser = UserDefaults.standard.bool(forKey: "useInAppBrowser")
            
            if useInAppBrowser {
                // Open in our custom WebViewController
                let webViewController = WebViewController(url: url)
                navigationController?.pushViewController(webViewController, animated: true)
            } else {
                // Fallback to opening in external browser
                UIApplication.shared.open(url)
            }
            return
        }
        
        decisionHandler(.allow)
    }
}

// MARK: - UIColor Extension

// UIColor.hexString is already defined in AppColors.swift