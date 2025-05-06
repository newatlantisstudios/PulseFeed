import UIKit

class EnhancedRSSCell: UITableViewCell {
    static let identifier = "EnhancedRSSCell"
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let sourceLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = AppColors.secondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeAgoLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = AppColors.secondary
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let previewTextLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = AppColors.secondary
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let articleImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 4
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        return imageView
    }()
    
    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? 
                UIColor(hex: "1A1A1A") : UIColor(hex: "FFFFFF")
        }
        view.layer.cornerRadius = 8
        
        // Add subtle shadow
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowOpacity = 0.1
        view.layer.shadowRadius = 2
        
        return view
    }()
    
    // Constraints that we'll need to modify based on settings
    private var titleToPreviewConstraint: NSLayoutConstraint?
    private var previewToBottomConstraint: NSLayoutConstraint?
    private var titleToImageConstraint: NSLayoutConstraint?
    private var imageToPreviewConstraint: NSLayoutConstraint?
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = AppColors.background
        selectionStyle = .none
        
        contentView.addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(articleImageView)
        cardView.addSubview(previewTextLabel)
        cardView.addSubview(sourceLabel)
        cardView.addSubview(timeAgoLabel)
        
        // Base constraints that are always active
        NSLayoutConstraint.activate([
            // Card view constraints
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            // Title label constraints
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            
            // Image view constraints (will be enabled/disabled based on settings)
            articleImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            articleImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            
            // Preview text constraints (will be enabled/disabled based on settings)
            previewTextLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            previewTextLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            
            // Source label constraints
            sourceLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            sourceLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            
            // Time ago label constraints
            timeAgoLabel.leadingAnchor.constraint(equalTo: sourceLabel.trailingAnchor, constant: 8),
            timeAgoLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            timeAgoLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
        
        // Store constraints that will be modified dynamically
        titleToPreviewConstraint = previewTextLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
        previewToBottomConstraint = sourceLabel.topAnchor.constraint(equalTo: previewTextLabel.bottomAnchor, constant: 8)
        
        titleToImageConstraint = articleImageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
        imageToPreviewConstraint = previewTextLabel.topAnchor.constraint(equalTo: articleImageView.bottomAnchor, constant: 8)
        
        imageWidthConstraint = articleImageView.widthAnchor.constraint(equalTo: cardView.widthAnchor, constant: -32)
        imageHeightConstraint = articleImageView.heightAnchor.constraint(equalToConstant: 150)
        
        // Default layout is title directly to source/time (compact view)
        sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8).isActive = true
        timeAgoLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8).isActive = true
    }
    
    func configure(with item: RSSItem, fontSize: CGFloat, isRead: Bool) {
        titleLabel.text = item.title
        sourceLabel.text = item.source
        timeAgoLabel.text = DateUtils.getTimeAgo(from: item.pubDate)
        
        // Apply different styling based on read state
        titleLabel.textColor = isRead ? AppColors.secondary : AppColors.accent
        titleLabel.font = UIFont.systemFont(ofSize: fontSize, weight: isRead ? .regular : .medium)
        
        // Update card appearance for read state
        cardView.alpha = isRead ? 0.85 : 1.0
        
        // Set preview text based on user preferences
        configurePreviewText(item: item)
        
        // Configure image if available and enabled
        configureImage(item: item)
        
        // Apply compact/expanded mode
        applyViewMode()
    }
    
    private func configurePreviewText(item: RSSItem) {
        let previewMode = UserDefaults.standard.string(forKey: "previewTextLength") ?? "none"
        
        // Hide by default
        previewTextLabel.isHidden = true
        
        // Deactivate constraints
        previewToBottomConstraint?.isActive = false
        titleToPreviewConstraint?.isActive = false
        
        guard previewMode != "none", let description = item.description else {
            return
        }
        
        // Clean HTML from description
        let cleanedText = description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Set preview text length based on setting
        let maxLength: Int
        switch previewMode {
        case "short":
            maxLength = 100
        case "medium":
            maxLength = 250
        case "full":
            maxLength = 1000
        default:
            maxLength = 0
        }
        
        guard maxLength > 0 else { return }
        
        let previewText: String
        if cleanedText.count > maxLength {
            previewText = cleanedText.prefix(maxLength) + "..."
        } else {
            previewText = cleanedText
        }
        
        if !previewText.isEmpty {
            previewTextLabel.text = previewText
            previewTextLabel.isHidden = false
            
            // Activate preview text constraints
            titleToPreviewConstraint?.isActive = true
            previewToBottomConstraint?.isActive = true
        }
    }
    
    private func configureImage(item: RSSItem) {
        let showImages = UserDefaults.standard.bool(forKey: "showArticleImages")
        
        // Hide by default
        articleImageView.isHidden = true
        
        // Deactivate image constraints
        titleToImageConstraint?.isActive = false
        imageToPreviewConstraint?.isActive = false
        imageWidthConstraint?.isActive = false
        imageHeightConstraint?.isActive = false
        
        // If image display is disabled, return early
        guard showImages else { return }
        
        // If we had an image for this item, we would load it here
        // For now, just place a placeholder
        // In a real app, this would extract image URL from the RSS item and load it
        
        // Placeholder logic - in a real implementation, you would load the actual image
        if let _ = item.description?.range(of: "img src=") {
            // Just a placeholder for demo purposes
            articleImageView.backgroundColor = AppColors.accent.withAlphaComponent(0.2)
            articleImageView.isHidden = false
            
            // Activate image constraints
            titleToImageConstraint?.isActive = true
            imageWidthConstraint?.isActive = true
            imageHeightConstraint?.isActive = true
            
            // If we also have preview text, connect them
            if !previewTextLabel.isHidden {
                imageToPreviewConstraint?.isActive = true
            }
        }
    }
    
    private func applyViewMode() {
        let isCompact = UserDefaults.standard.bool(forKey: "compactArticleView")
        
        if isCompact {
            // In compact mode, limit title lines
            titleLabel.numberOfLines = 2
            previewTextLabel.numberOfLines = 1
            
            // Reduce image height in compact mode
            imageHeightConstraint?.constant = 100
        } else {
            // In expanded mode, allow more lines
            titleLabel.numberOfLines = 0
            previewTextLabel.numberOfLines = 5
            
            // Full height image in expanded mode
            imageHeightConstraint?.constant = 150
        }
    }
}