import UIKit

class ReadingProgressBar: UIView {
    
    // MARK: - Properties
    
    private let trackLayer = CALayer()
    private let progressLayer = CALayer()
    
    private var progress: Float = 0 {
        didSet {
            updateProgressLayer()
        }
    }
    
    // Colors
    var trackColor: UIColor = UIColor.systemGray.withAlphaComponent(0.3) {
        didSet {
            trackLayer.backgroundColor = trackColor.cgColor
        }
    }
    
    var progressColor: UIColor = UIColor.systemBlue {
        didSet {
            progressLayer.backgroundColor = progressColor.cgColor
        }
    }
    
    var height: CGFloat = 3 {
        didSet {
            frame.size.height = height
            setNeedsLayout()
        }
    }
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    // MARK: - Setup
    
    private func setupLayers() {
        // Set up the track layer (background)
        trackLayer.backgroundColor = trackColor.cgColor
        layer.addSublayer(trackLayer)
        
        // Set up the progress layer (foreground)
        progressLayer.backgroundColor = progressColor.cgColor
        layer.addSublayer(progressLayer)
        
        // Make sure the view is transparent
        backgroundColor = .clear
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Set the track layer frame to the full width of the view
        trackLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        
        // Update the progress layer width based on current progress
        updateProgressLayer()
    }
    
    // MARK: - Progress Update
    
    func setProgress(_ value: Float, animated: Bool = true) {
        // Ensure the progress value is between 0 and 1
        let clampedValue = min(1.0, max(0.0, value))
        
        if animated {
            // Animate the change
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            progress = clampedValue
            CATransaction.commit()
        } else {
            // Update without animation
            progress = clampedValue
        }
    }
    
    private func updateProgressLayer() {
        // Calculate the width based on progress
        let progressWidth = bounds.width * CGFloat(progress)
        
        // Update progress layer frame
        progressLayer.frame = CGRect(x: 0, y: 0, width: progressWidth, height: height)
    }
}