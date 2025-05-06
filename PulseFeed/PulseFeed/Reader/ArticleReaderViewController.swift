import UIKit
import WebKit
import SafariServices

class ArticleReaderViewController: UIViewController {
    
    // MARK: - Properties
    
    private let webView = WKWebView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let sourceLabel = UILabel()
    private let dateLabel = UILabel()
    private let toolbar = UIToolbar()
    private let progressView = UIProgressView()
    
    private var fontSize: CGFloat = 18
    private var lineHeight: CGFloat = 1.5
    private var fontColor: UIColor = .label
    private var backgroundColor: UIColor = .systemBackground
    private var estimatedReadingTimeLabel: UILabel?
    
    var item: RSSItem?
    var htmlContent: String?
    private var webViewObservation: NSKeyValueObservation?
    
    // Reading modes
    enum ReadingMode: String {
        case regular = "regular"
        case sepia = "sepia"
        case dark = "dark"
    }
    
    private var currentReadingMode: ReadingMode {
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        let storedMode = UserDefaults.standard.string(forKey: "readerMode") ?? (isDarkMode ? "dark" : "regular")
        return ReadingMode(rawValue: storedMode) ?? (isDarkMode ? .dark : .regular)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNavigationBar()
        loadArticleContent()
        
        // Listen for font size changes
        NotificationCenter.default.addObserver(self, selector: #selector(fontSizeChanged(_:)), name: Notification.Name("fontSizeChanged"), object: nil)
        
        // Set up web view progress tracking
        webViewObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, change in
            guard let self = self else { return }
            
            if let newValue = change.newValue {
                self.updateProgress(Float(newValue))
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        webViewObservation?.invalidate()
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
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = fontColor
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup source label
        sourceLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        sourceLabel.textColor = AppColors.secondary
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup date label
        dateLabel.font = UIFont.systemFont(ofSize: 14)
        dateLabel.textColor = AppColors.secondary
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup reading time
        estimatedReadingTimeLabel = UILabel()
        estimatedReadingTimeLabel?.font = UIFont.systemFont(ofSize: 14, weight: .regular)
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
        
        // Create reading mode button based on current mode
        var modeIcon: UIImage?
        switch currentReadingMode {
        case .regular:
            modeIcon = UIImage(systemName: "sun.max")
        case .sepia:
            modeIcon = UIImage(systemName: "book")
        case .dark:
            modeIcon = UIImage(systemName: "moon")
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
    
    private func wrapInReadableHTML(content: String) -> String {
        // Get stored typography settings
        loadTypographySettings()
        
        // Check if we should use justified text
        let useJustifiedText = UserDefaults.standard.bool(forKey: "readerJustifiedText")
        let justifiedClass = useJustifiedText ? " justified" : ""
        
        // Use ContentExtractor to wrap content in readable HTML
        let wrappedHTML = ContentExtractor.wrapInReadableHTML(
            content: "<div class=\"content\(justifiedClass)\">\(content)</div>",
            fontSize: fontSize,
            lineHeight: lineHeight,
            fontColor: fontColor.hexString,
            backgroundColor: backgroundColor.hexString,
            accentColor: AppColors.accent.hexString
        )
        
        return wrappedHTML
    }
    
    private func displayContent(_ html: String) {
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
    
    // MARK: - Typography Settings
    
    private func loadTypographySettings() {
        // Load font size from UserDefaults
        let storedFontSize = UserDefaults.standard.float(forKey: "readerFontSize")
        fontSize = storedFontSize != 0 ? CGFloat(storedFontSize) : 18
        
        // Load line height
        let storedLineHeight = UserDefaults.standard.float(forKey: "readerLineHeight")
        lineHeight = storedLineHeight != 0 ? CGFloat(storedLineHeight) : 1.5
        
        // Set color based on current theme
        switch currentReadingMode {
        case .regular:
            // Use system colors
            backgroundColor = traitCollection.userInterfaceStyle == .dark ? .black : .white
            fontColor = traitCollection.userInterfaceStyle == .dark ? .white : .black
        case .sepia:
            backgroundColor = UIColor(hex: "F9F5E9") // Sepia background
            fontColor = UIColor(hex: "5B4636") // Sepia text color
        case .dark:
            backgroundColor = .black
            fontColor = .white
        }
        
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
        if fontSize > 12 {
            fontSize -= 2
            UserDefaults.standard.set(Float(fontSize), forKey: "readerFontSize")
            
            if let content = htmlContent {
                displayContent(content)
            }
        }
    }
    
    @objc private func increaseFontSize() {
        if fontSize < 32 {
            fontSize += 2
            UserDefaults.standard.set(Float(fontSize), forKey: "readerFontSize")
            
            if let content = htmlContent {
                displayContent(content)
            }
        }
    }
    
    @objc private func toggleReadingMode() {
        // Cycle through reading modes
        let newMode: ReadingMode
        
        switch currentReadingMode {
        case .regular:
            newMode = .sepia
        case .sepia:
            newMode = .dark
        case .dark:
            newMode = .regular
        }
        
        // Save new mode to UserDefaults
        UserDefaults.standard.set(newMode.rawValue, forKey: "readerMode")
        
        // Update colors
        switch newMode {
        case .regular:
            // Use system colors
            backgroundColor = traitCollection.userInterfaceStyle == .dark ? .black : .white
            fontColor = traitCollection.userInterfaceStyle == .dark ? .white : .black
        case .sepia:
            backgroundColor = UIColor(hex: "F9F5E9") // Sepia background
            fontColor = UIColor(hex: "5B4636") // Sepia text color
        case .dark:
            backgroundColor = .black
            fontColor = .white
        }
        
        // Update UI with new colors
        view.backgroundColor = backgroundColor
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        titleLabel.textColor = fontColor
        
        // Update toolbar icon
        let modeImage: UIImage?
        switch newMode {
        case .regular:
            modeImage = UIImage(systemName: "sun.max")
        case .sepia:
            modeImage = UIImage(systemName: "book")
        case .dark:
            modeImage = UIImage(systemName: "moon")
        }
        
        if let toggleModeButton = toolbar.items?[2] {
            toggleModeButton.image = modeImage
        }
        
        // Reload content with new styles
        if let content = htmlContent {
            displayContent(content)
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
            // Only update if we're using the regular reading mode
            if currentReadingMode == .regular {
                loadTypographySettings()
                
                // Reload the article to update colors
                if let content = htmlContent {
                    displayContent(content)
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension ArticleReaderViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
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
        
        // For links clicked in the article, open them in Safari
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
            return
        }
        
        decisionHandler(.allow)
    }
}

// MARK: - UIColor Extension

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        return String(
            format: "#%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255)
        )
    }
}