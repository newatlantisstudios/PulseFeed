import UIKit

/// A utility class for downloading and caching images from remote URLs
final class ImageLoader {
    // Singleton instance
    static let shared = ImageLoader()
    
    // Cache reference
    private let cache = ImageCache.shared
    
    // Active downloads
    private var activeDownloads: [URL: [(UIImage?) -> Void]] = [:]
    
    // URL session for downloads
    private let session: URLSession
    
    // Private initializer for singleton
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        
        session = URLSession(configuration: configuration)
    }
    
    // MARK: - Image Loading
    
    /// Loads an image from a URL with caching
    /// - Parameters:
    ///   - url: The URL of the image
    ///   - completion: Closure called when the image is loaded
    @discardableResult
    func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        // Generate cache key from URL
        let cacheKey = url.absoluteString
        
        // Check if the image is in the cache
        if let cachedImage = cache.image(for: cacheKey) {
            completion(cachedImage)
            return nil
        }
        
        // If there's already an active download for this URL, add this completion handler to it
        if var handlers = activeDownloads[url] {
            handlers.append(completion)
            activeDownloads[url] = handlers
            return nil
        }
        
        // Start a new download
        activeDownloads[url] = [completion]
        
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Get handlers for this URL
            let handlers = self.activeDownloads[url] ?? []
            self.activeDownloads[url] = nil
            
            // Process the downloaded data
            if let data = data, let image = UIImage(data: data) {
                // Cache the image
                self.cache.store(image, for: cacheKey)
                
                // Call all completion handlers on the main thread
                DispatchQueue.main.async {
                    for handler in handlers {
                        handler(image)
                    }
                }
            } else {
                // Call all completion handlers with nil
                DispatchQueue.main.async {
                    for handler in handlers {
                        handler(nil)
                    }
                }
            }
        }
        
        task.resume()
        return task
    }
    
    /// Cancels all active downloads
    func cancelAllDownloads() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        activeDownloads.removeAll()
    }
    
    /// Prefetches an image without a completion handler
    /// - Parameter url: The URL of the image to prefetch
    func prefetchImage(from url: URL) {
        let cacheKey = url.absoluteString
        
        // Skip if already in cache
        if cache.image(for: cacheKey) != nil {
            return
        }
        
        // Skip if already downloading
        if activeDownloads[url] != nil {
            return
        }
        
        // Start a low-priority download
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let image = UIImage(data: data) else { return }
            self.cache.store(image, for: cacheKey)
        }
        
        task.priority = URLSessionTask.lowPriority
        task.resume()
    }
}

// MARK: - UIImageView Extension
extension UIImageView {
    /// Loads an image from a URL with loading indicator and caching
    /// - Parameters:
    ///   - url: The URL of the image
    ///   - placeholder: Optional placeholder image to show while loading
    @discardableResult
    func loadImage(from url: URL, placeholder: UIImage? = nil) -> URLSessionDataTask? {
        // Show placeholder if specified
        self.image = placeholder
        
        // Show activity indicator
        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        
        activityIndicator.startAnimating()
        
        // Load the image
        return ImageLoader.shared.loadImage(from: url) { [weak self] image in
            DispatchQueue.main.async {
                activityIndicator.removeFromSuperview()
                
                if let image = image {
                    self?.image = image
                    
                    // Add a fade-in animation for smoother loading
                    self?.alpha = 0
                    UIView.animate(withDuration: 0.3) {
                        self?.alpha = 1
                    }
                } else if self?.image === placeholder {
                    // Keep placeholder if loading failed
                } else {
                    // Show error placeholder if no custom placeholder
                    self?.image = UIImage(systemName: "exclamationmark.triangle")
                }
            }
        }
    }
    
    /// Cancels any currently executing image loading operation
    func cancelImageLoading() {
        // Find and remove the activity indicator
        for subview in self.subviews {
            if let activityIndicator = subview as? UIActivityIndicatorView {
                activityIndicator.stopAnimating()
                activityIndicator.removeFromSuperview()
                break
            }
        }
    }
}