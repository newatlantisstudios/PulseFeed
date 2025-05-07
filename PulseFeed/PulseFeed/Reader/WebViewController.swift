import UIKit
import WebKit
import SafariServices

class WebViewController: UIViewController {
    
    // MARK: - Properties
    
    private let webView = WKWebView()
    private let progressView = UIProgressView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var originalURL: URL?
    private var webViewObservation: NSKeyValueObservation?
    
    // MARK: - Initialization
    
    init(url: URL) {
        self.originalURL = url
        super.init(nibName: nil, bundle: nil)
    }
    
    // No longer needed since we're not using storyboard initialization
    
    required init?(coder: NSCoder) {
        self.originalURL = URL(string: "about:blank")
        super.init(coder: coder)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupWebView()
        setupProgressBar()
        setupToolbar()
        
        // Load the URL if available
        if let url = originalURL {
            loadURL(url)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Invalidate KVO when view disappears
        webViewObservation?.invalidate()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Configure navigation bar
        navigationItem.largeTitleDisplayMode = .never
        
        // Set up back button
        navigationItem.backButtonTitle = "Back"
        
        // Add actions to navigation bar
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareURL))
        let safariButton = UIBarButtonItem(image: UIImage(systemName: "safari"), style: .plain, target: self, action: #selector(openInSafari))
        let readerButton = UIBarButtonItem(image: UIImage(systemName: "text.justify"), style: .plain, target: self, action: #selector(openInReader))
        
        navigationItem.rightBarButtonItems = [shareButton, safariButton, readerButton]
    }
    
    private func setupWebView() {
        // Configure webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)
        
        // Add loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.startAnimating()
        view.addSubview(loadingIndicator)
        
        // Set constraints
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupProgressBar() {
        // Configure progress view
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = AppColors.accent
        progressView.trackTintColor = AppColors.secondary.withAlphaComponent(0.2)
        progressView.progress = 0
        view.addSubview(progressView)
        
        // Set constraints
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])
        
        // Observe webView loading progress
        webViewObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, change in
            guard let self = self, let newValue = change.newValue else { return }
            
            // Update progress view
            DispatchQueue.main.async {
                self.progressView.progress = Float(newValue)
                
                // Hide progress view when loading completes
                if newValue >= 1.0 {
                    UIView.animate(withDuration: 0.3, delay: 0.3, options: .curveEaseOut, animations: {
                        self.progressView.alpha = 0
                    }, completion: nil)
                } else {
                    self.progressView.alpha = 1
                }
            }
        }
    }
    
    private func setupToolbar() {
        // Create toolbar
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.tintColor = AppColors.accent
        view.addSubview(toolbar)
        
        // Create toolbar items
        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(goBack))
        let forwardButton = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), style: .plain, target: self, action: #selector(goForward))
        let refreshButton = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshPage))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        // Add items to toolbar
        toolbar.items = [backButton, flexibleSpace, forwardButton, flexibleSpace, refreshButton]
        
        // Set constraints
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // Update webView bottom constraint to be above toolbar
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor)
        ])
    }
    
    // MARK: - WebView Methods
    
    private func loadURL(_ url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
        
        // Update title
        title = url.host
    }
    
    private func updateNavigationTitle() {
        if let title = webView.title, !title.isEmpty {
            self.title = title
        } else if let url = webView.url {
            self.title = url.host
        }
    }
    
    // MARK: - Actions
    
    @objc private func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    @objc private func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    @objc private func refreshPage() {
        webView.reload()
    }
    
    @objc private func shareURL() {
        guard let url = webView.url else { return }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // Set the source view for iPad
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func openInSafari() {
        // Use current URL or fall back to original URL
        guard let url = webView.url ?? originalURL else { return }
        
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let safariVC = SFSafariViewController(url: url, configuration: configuration)
        safariVC.dismissButtonStyle = .close
        safariVC.preferredControlTintColor = AppColors.accent
        
        present(safariVC, animated: true)
    }
    
    @objc private func openInReader() {
        // Use current URL or fall back to original URL
        guard let url = webView.url ?? originalURL else { return }
        
        // Create article reader with current URL
        let articleReader = ArticleReaderViewController()
        
        // Format date as string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let pubDateString = dateFormatter.string(from: Date())
        
        // Create a temporary RSSItem to pass to the reader
        let tempItem = RSSItem(
            title: webView.title ?? "Article",
            link: url.absoluteString,
            pubDate: pubDateString,
            source: webView.url?.host ?? "Web",
            description: "",
            content: nil,
            author: nil
        )
        
        articleReader.item = tempItem
        
        navigationController?.pushViewController(articleReader, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingIndicator.startAnimating()
        // Reset progress
        progressView.progress = 0
        progressView.alpha = 1
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        updateNavigationTitle()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        
        // Show error alert
        showError("Failed to load page: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
        
        // Show error alert
        showError("Failed to load page: \(error.localizedDescription)")
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}