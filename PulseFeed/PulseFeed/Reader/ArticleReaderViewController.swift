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
    
    private var fontSize: CGFloat = 18
    private var lineHeight: CGFloat = 1.5
    private var fontColor: UIColor = .label
    private var backgroundColor: UIColor = .systemBackground
    
    var item: RSSItem?
    var htmlContent: String?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNavigationBar()
        loadArticleContent()
        
        // Listen for font size changes
        NotificationCenter.default.addObserver(self, selector: #selector(fontSizeChanged(_:)), name: Notification.Name("fontSizeChanged"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = backgroundColor
        
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
        
        // Setup web view
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = backgroundColor
        webView.isOpaque = false
        
        // Setup loading indicator
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()
        
        // Setup toolbar
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        setupToolbar()
        
        // Add subviews
        view.addSubview(titleLabel)
        view.addSubview(sourceLabel)
        view.addSubview(dateLabel)
        view.addSubview(webView)
        view.addSubview(loadingIndicator)
        view.addSubview(toolbar)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            sourceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            webView.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 16),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Load typography settings
        loadTypographySettings()
        
        // Update UI with article details
        updateArticleDetails()
    }
    
    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        
        // Create share button
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareArticle))
        
        // Create open in Safari button
        let safariButton = UIBarButtonItem(image: UIImage(systemName: "safari"), style: .plain, target: self, action: #selector(openInSafari))
        
        navigationItem.rightBarButtonItems = [shareButton, safariButton]
    }
    
    private func setupToolbar() {
        // Create toolbar items
        let decreaseFontButton = UIBarButtonItem(image: UIImage(systemName: "textformat.size.smaller"), style: .plain, target: self, action: #selector(decreaseFontSize))
        
        let increaseFontButton = UIBarButtonItem(image: UIImage(systemName: "textformat.size.larger"), style: .plain, target: self, action: #selector(increaseFontSize))
        
        let toggleModeButton = UIBarButtonItem(image: UIImage(systemName: "sun.max"), style: .plain, target: self, action: #selector(toggleReadingMode))
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        // Add items to toolbar
        toolbar.items = [decreaseFontButton, flexibleSpace, toggleModeButton, flexibleSpace, increaseFontButton]
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
            loadingIndicator.startAnimating()
            
            StorageManager.shared.getCachedArticleContent(link: item.link) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let cachedArticle):
                    // We have a cached version, use it
                    DispatchQueue.main.async {
                        self.loadingIndicator.stopAnimating()
                        
                        // Show cache indicator
                        self.showCachedIndicator(date: cachedArticle.cachedDate)
                        
                        // Display the cached content
                        self.displayContent(cachedArticle.content)
                        self.htmlContent = cachedArticle.content
                        
                        print("DEBUG: Loaded article from cache: \(item.title)")
                    }
                    
                case .failure:
                    // No cached version, check if we're offline
                    if StorageManager.shared.isDeviceOffline {
                        DispatchQueue.main.async {
                            self.loadingIndicator.stopAnimating()
                            self.showError("No internet connection and no cached version available")
                        }
                        return
                    }
                    
                    // We're online, fetch from network
                    let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                        guard let self = self else { return }
                        
                        DispatchQueue.main.async {
                            self.loadingIndicator.stopAnimating()
                            
                            if let error = error {
                                self.showError("Failed to load article: \(error.localizedDescription)")
                                return
                            }
                            
                            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                                self.showError("Failed to decode article content")
                                return
                            }
                            
                            // Extract and clean the content
                            let cleanedContent = self.extractReadableContent(from: html)
                            self.displayContent(cleanedContent)
                            self.htmlContent = cleanedContent
                            
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
                                }
                            }
                        }
                    }
                    task.resume()
                }
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
        
        // Adjust the top constraint of the titleLabel to accommodate the cached indicator
        if let firstConstraint = titleLabel.constraints.first(where: { $0.firstAttribute == .top }) {
            titleLabel.removeConstraint(firstConstraint)
            
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: cachedLabel.bottomAnchor, constant: 16)
            ])
        }
    }
    
    private func extractReadableContent(from html: String) -> String {
        // Use our ContentExtractor to extract readable content
        guard let item = item, let url = URL(string: item.link) else {
            return ContentExtractor.extractReadableContent(from: html, url: nil)
        }
        
        return ContentExtractor.extractReadableContent(from: html, url: url)
    }
    
    private func wrapInReadableHTML(content: String) -> String {
        // Get stored typography settings
        loadTypographySettings()
        
        // Use ContentExtractor to wrap content in readable HTML
        return ContentExtractor.wrapInReadableHTML(
            content: content,
            fontSize: fontSize,
            lineHeight: lineHeight,
            fontColor: fontColor.hexString,
            backgroundColor: backgroundColor.hexString,
            accentColor: AppColors.accent.hexString
        )
    }
    
    private func displayContent(_ html: String) {
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    private func updateArticleDetails() {
        guard let item = item else { return }
        
        titleLabel.text = item.title
        sourceLabel.text = item.source
        
        // Format date
        dateLabel.text = DateUtils.getTimeAgo(from: item.pubDate)
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
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        let isSepia = UserDefaults.standard.bool(forKey: "readerSepiaMode")
        
        if isSepia {
            backgroundColor = UIColor(hex: "F9F5E9") // Sepia background
            fontColor = UIColor(hex: "5B4636") // Sepia text color
        } else {
            backgroundColor = isDarkMode ? .black : .white
            fontColor = isDarkMode ? .white : .black
        }
    }
    
    @objc private func fontSizeChanged(_ notification: Notification) {
        // Reload the article with new font size
        if let content = htmlContent {
            displayContent(wrapInReadableHTML(content: content))
        }
    }
    
    // MARK: - Actions
    
    @objc private func shareArticle() {
        guard let item = item, let url = URL(string: item.link) else { return }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
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
                displayContent(wrapInReadableHTML(content: content))
            }
        }
    }
    
    @objc private func increaseFontSize() {
        if fontSize < 32 {
            fontSize += 2
            UserDefaults.standard.set(Float(fontSize), forKey: "readerFontSize")
            
            if let content = htmlContent {
                displayContent(wrapInReadableHTML(content: content))
            }
        }
    }
    
    @objc private func toggleReadingMode() {
        // Toggle between normal and sepia modes
        let isCurrentlySepia = UserDefaults.standard.bool(forKey: "readerSepiaMode")
        let newMode = !isCurrentlySepia
        UserDefaults.standard.set(newMode, forKey: "readerSepiaMode")
        
        // Update UI
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        
        if newMode {
            backgroundColor = UIColor(hex: "F9F5E9") // Sepia background
            fontColor = UIColor(hex: "5B4636") // Sepia text color
            view.backgroundColor = backgroundColor
        } else {
            backgroundColor = isDarkMode ? .black : .white
            fontColor = isDarkMode ? .white : .black
            view.backgroundColor = backgroundColor
        }
        
        // Update toolbar icon
        if let toggleModeButton = toolbar.items?[2] {
            toggleModeButton.image = UIImage(systemName: newMode ? "moon" : "sun.max")
        }
        
        // Reload content with new styles
        if let content = htmlContent {
            displayContent(wrapInReadableHTML(content: content))
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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