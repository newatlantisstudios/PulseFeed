import UIKit

// MARK: - ImageCache
/// A utility class for caching and retrieving images
final class ImageCache {
    // Singleton instance
    static let shared = ImageCache()
    
    // In-memory cache
    private let memoryCache = NSCache<NSString, UIImage>()
    
    // File manager for disk operations
    private let fileManager = FileManager.default
    
    // Cache directory URL
    private lazy var cacheDirectoryURL: URL = {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheDirectory = cachesDirectory.appendingPathComponent("ImageCache")
        
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        return cacheDirectory
    }()
    
    // Memory cache size limit - 100MB
    private let memoryCacheSizeLimit = 100 * 1024 * 1024
    
    // Maximum disk cache size - 500MB
    private let diskCacheSizeLimit = 500 * 1024 * 1024
    
    // Private initializer for singleton
    private init() {
        // Configure memory cache
        memoryCache.name = "com.pulsefeed.imagecache"
        memoryCache.totalCostLimit = memoryCacheSizeLimit
        
        // Set up automatic cache clearing on memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearMemoryCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Perform initial cleanup to ensure cache isn't oversized
        cleanDiskCache()
    }
    
    // MARK: - Cache Operations
    
    /// Stores an image in the cache
    /// - Parameters:
    ///   - image: The image to store
    ///   - key: The unique key for the image
    func store(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * 4) // Approximate memory usage (RGBA)
        
        // Store in memory cache
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
        
        // Store on disk asynchronously
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self, let data = image.jpegData(compressionQuality: 0.8) else { return }
            let fileURL = self.fileURL(for: key)
            try? data.write(to: fileURL)
        }
    }
    
    /// Retrieves an image from the cache
    /// - Parameter key: The unique key for the image
    /// - Returns: The cached image if found, nil otherwise
    func image(for key: String) -> UIImage? {
        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: key as NSString) {
            return cachedImage
        }
        
        // Check disk cache
        let fileURL = fileURL(for: key)
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // Move back to memory cache
            store(image, for: key)
            return image
        }
        
        return nil
    }
    
    /// Removes an image from the cache
    /// - Parameter key: The unique key for the image
    func removeImage(for key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        
        let fileURL = fileURL(for: key)
        try? fileManager.removeItem(at: fileURL)
    }
    
    /// Clears all cached images
    func clearCache() {
        clearMemoryCache()
        clearDiskCache()
    }
    
    // MARK: - Cache Management
    
    /// Clears the memory cache
    @objc func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
    
    /// Clears the disk cache
    func clearDiskCache() {
        try? fileManager.removeItem(at: cacheDirectoryURL)
        try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }
    
    /// Cleans the disk cache by removing least recently used files if over size limit
    func cleanDiskCache() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            // Get all cached files with their attributes
            let fileURLs = try? self.fileManager.contentsOfDirectory(
                at: self.cacheDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: []
            )
            
            guard let cachedFiles = fileURLs else { return }
            
            // Calculate total size and prepare file info
            var totalSize: UInt64 = 0
            var fileInfos: [(url: URL, date: Date, size: UInt64)] = []
            
            for fileURL in cachedFiles {
                guard let attributes = try? self.fileManager.attributesOfItem(atPath: fileURL.path),
                      let modificationDate = attributes[.modificationDate] as? Date,
                      let fileSize = attributes[.size] as? UInt64 else {
                    continue
                }
                
                totalSize += fileSize
                fileInfos.append((fileURL, modificationDate, fileSize))
            }
            
            // Sort by modification date (oldest first)
            fileInfos.sort { $0.date < $1.date }
            
            // Remove oldest files until we're under the size limit
            for fileInfo in fileInfos {
                if totalSize <= self.diskCacheSizeLimit {
                    break
                }
                
                try? self.fileManager.removeItem(at: fileInfo.url)
                totalSize -= fileInfo.size
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Generates a file URL for a given cache key
    /// - Parameter key: The cache key
    /// - Returns: The file URL
    private func fileURL(for key: String) -> URL {
        // Create a hash of the key for file naming
        let hashedKey = key.sha256()
        return cacheDirectoryURL.appendingPathComponent(hashedKey)
    }
}

// MARK: - String Extension for Hashing
extension String {
    /// Creates a SHA-256 hash of the string
    func sha256() -> String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// Add Common Crypto import
import CommonCrypto