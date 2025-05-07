import UIKit

/// A utility class for processing, optimizing and resizing images
final class ImageProcessor {
    // Singleton instance
    static let shared = ImageProcessor()
    
    // Quality settings
    private enum Quality {
        case high   // 90% JPEG quality
        case medium // 70% JPEG quality 
        case low    // 50% JPEG quality
        
        var compressionQuality: CGFloat {
            switch self {
            case .high:   return 0.9
            case .medium: return 0.7
            case .low:    return 0.5
            }
        }
    }
    
    // Private initializer for singleton
    private init() {}
    
    // MARK: - Image Resizing
    
    /// Resizes an image to a specific size while maintaining aspect ratio
    /// - Parameters:
    ///   - image: The original image
    ///   - targetSize: The target size for the image
    /// - Returns: The resized image
    func resize(image: UIImage, to targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // Use the smaller ratio to ensure the entire image fits within the target size
        let scaleFactor = min(widthRatio, heightRatio)
        
        let scaledWidth  = size.width * scaleFactor
        let scaledHeight = size.height * scaleFactor
        let targetRect = CGRect(
            x: (targetSize.width - scaledWidth) / 2,
            y: (targetSize.height - scaledHeight) / 2,
            width: scaledWidth,
            height: scaledHeight
        )
        
        // Render the image
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        image.draw(in: targetRect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    /// Resizes an image to a maximum width while maintaining aspect ratio
    /// - Parameters:
    ///   - image: The original image
    ///   - maxWidth: The maximum width for the resized image
    /// - Returns: The resized image
    func resizeToMaxWidth(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let size = image.size
        
        // Check if resizing is needed
        if size.width <= maxWidth {
            return image
        }
        
        let scaleFactor = maxWidth / size.width
        let newHeight = size.height * scaleFactor
        let newSize = CGSize(width: maxWidth, height: newHeight)
        
        return resize(image: image, to: newSize)
    }
    
    /// Generates a thumbnail image
    /// - Parameters:
    ///   - image: The original image
    ///   - size: The size for the thumbnail
    /// - Returns: The thumbnail image
    func generateThumbnail(from image: UIImage, ofSize size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        return resize(image: image, to: size)
    }
    
    // MARK: - Image Optimization
    
    /// Optimizes an image for network transmission or storage
    /// - Parameters:
    ///   - image: The original image
    ///   - quality: The desired quality level (default: medium)
    /// - Returns: The optimized image data
    private func optimizedData(from image: UIImage, quality: Quality = .medium) -> Data? {
        // Check if the image needs resizing based on dimensions
        var processedImage = image
        let maxDimension: CGFloat = 1200  // Max width or height for images
        
        if image.size.width > maxDimension || image.size.height > maxDimension {
            if image.size.width > image.size.height {
                processedImage = resizeToMaxWidth(image, maxWidth: maxDimension)
            } else {
                let scaleFactor = maxDimension / image.size.height
                let newWidth = image.size.width * scaleFactor
                processedImage = resize(image: image, to: CGSize(width: newWidth, height: maxDimension))
            }
        }
        
        // Convert to JPEG with the specified quality
        return processedImage.jpegData(compressionQuality: quality.compressionQuality)
    }
    
    /// Creates a grayscale version of an image
    /// - Parameter image: The original image
    /// - Returns: A grayscale version of the image
    func grayscale(image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let context = CIContext(options: nil)
        let ciImage = CIImage(cgImage: cgImage)
        
        guard let filter = CIFilter(name: "CIColorMonochrome") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIColor(red: 0.7, green: 0.7, blue: 0.7), forKey: kCIInputColorKey)
        filter.setValue(1.0, forKey: kCIInputIntensityKey)
        
        guard let outputImage = filter.outputImage,
              let cgImg = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImg)
    }
    
    /// Applies a light blur effect to an image
    /// - Parameter image: The original image
    /// - Returns: A blurred version of the image
    func blur(image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let context = CIContext(options: nil)
        let ciImage = CIImage(cgImage: cgImage)
        
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(10.0, forKey: kCIInputRadiusKey)
        
        guard let outputImage = filter.outputImage,
              let cgImg = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImg)
    }
}

// MARK: - Image Processing Extensions
extension UIImage {
    /// Returns a resized version of the image
    /// - Parameter size: The target size
    /// - Returns: The resized image
    func resized(to size: CGSize) -> UIImage {
        return ImageProcessor.shared.resize(image: self, to: size)
    }
    
    /// Returns a version of the image resized to a maximum width
    /// - Parameter width: The maximum width
    /// - Returns: The resized image
    func resizedToMaxWidth(_ width: CGFloat) -> UIImage {
        return ImageProcessor.shared.resizeToMaxWidth(self, maxWidth: width)
    }
    
    /// Returns a thumbnail version of the image
    /// - Parameter size: The thumbnail size
    /// - Returns: The thumbnail image
    func thumbnail(ofSize size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        return ImageProcessor.shared.generateThumbnail(from: self, ofSize: size)
    }
    
    /// Returns optimized JPEG data for the image with medium quality
    /// - Returns: Optimized JPEG data
    func optimizedData() -> Data? {
        return self.jpegData(compressionQuality: 0.7)
    }
    
    /// Returns a grayscale version of the image
    /// - Returns: The grayscale image
    func grayscale() -> UIImage? {
        return ImageProcessor.shared.grayscale(image: self)
    }
    
    /// Returns a blurred version of the image
    /// - Returns: The blurred image
    func blurred() -> UIImage? {
        return ImageProcessor.shared.blur(image: self)
    }
}