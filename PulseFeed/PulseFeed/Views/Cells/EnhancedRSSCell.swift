import UIKit

class EnhancedRSSCell: UITableViewCell {
    static let identifier = "EnhancedRSSCell"

    // Properties to track item state
    var isBookmarked: Bool = false
    var isHearted: Bool = false
    var isRead: Bool = false
    var isArchived: Bool = false
    var isCached: Bool = false

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
        view.backgroundColor = .clear // Use clear background for simpler style
        return view
    }()

    // Cache indicator - create once and reuse
    private let cacheIndicator: UIView = {
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 12))
        indicator.backgroundColor = AppColors.cacheIndicator
        indicator.layer.cornerRadius = 6
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isHidden = true // Hide by default
        return indicator
    }()

    // Simple duplicate indicator
    private let duplicateBadge: UILabel = {
        let label = UILabel()
        label.backgroundColor = UIColor(hex: "1E90FF")
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // Simple duplicate border
    private let duplicateBorder: UIView = {
        let view = UIView()
        view.layer.borderColor = UIColor(hex: "1E90FF").cgColor
        view.layer.borderWidth = 1
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()


    // Constraints that we'll need to modify based on settings
    private var titleToPreviewConstraint: NSLayoutConstraint?
    private var previewToBottomConstraint: NSLayoutConstraint?
    private var titleToImageConstraint: NSLayoutConstraint?
    private var imageToPreviewConstraint: NSLayoutConstraint?
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?

    // Track if we should display action buttons (hide on macOS Catalyst)
    private var shouldShowActionButtons: Bool {
        return !PlatformUtils.isMac
    }
    
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

        // Simple content hierarchy
        contentView.addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(articleImageView) // Kept but hidden
        cardView.addSubview(previewTextLabel)
        cardView.addSubview(sourceLabel)
        cardView.addSubview(timeAgoLabel)
        cardView.addSubview(cacheIndicator)

        // On macOS Catalyst, context menu is used instead of action buttons
        if PlatformUtils.isMac {
            // Make sure any action buttons or UI elements that should be hidden are not shown
            self.accessoryType = .none
            self.editingAccessoryType = .none
        }
        
        // Duplicate indicators
        contentView.addSubview(duplicateBorder)
        contentView.addSubview(duplicateBadge)
        
        // Basic constraints
        NSLayoutConstraint.activate([
            // Content area
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            
            // Duplicate border
            duplicateBorder.topAnchor.constraint(equalTo: contentView.topAnchor),
            duplicateBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            duplicateBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            duplicateBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Duplicate badge
            duplicateBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            duplicateBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            duplicateBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            duplicateBadge.heightAnchor.constraint(equalToConstant: 18),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            
            // Image 
            articleImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            articleImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            
            // Preview text
            previewTextLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            previewTextLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            
            
            // Source
            sourceLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            sourceLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -6),
            
            // Time
            timeAgoLabel.leadingAnchor.constraint(equalTo: sourceLabel.trailingAnchor, constant: 8),
            timeAgoLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            timeAgoLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -6),
            
            // Cache indicator
            cacheIndicator.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 6),
            cacheIndicator.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -6),
            cacheIndicator.widthAnchor.constraint(equalToConstant: 10),
            cacheIndicator.heightAnchor.constraint(equalToConstant: 10),
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
    
    // Basic configure method
    func configure(with item: RSSItem, fontSize: CGFloat, isRead: Bool, isCached: Bool = false,
                   isBookmarked: Bool = false, isHearted: Bool = false, isArchived: Bool = false) {
        // Store state
        self.isRead = isRead
        self.isCached = isCached
        self.isBookmarked = isBookmarked
        self.isHearted = isHearted
        self.isArchived = isArchived

        // Set basic text content
        titleLabel.text = item.title
        sourceLabel.text = item.source
        timeAgoLabel.text = DateUtils.getTimeAgo(from: item.pubDate)

        // Basic styling based on read state
        titleLabel.textColor = isRead ? AppColors.secondary : AppColors.accent
        titleLabel.font = UIFont.systemFont(ofSize: fontSize, weight: isRead ? .regular : .medium)
        backgroundColor = isRead ? AppColors.background.withAlphaComponent(0.95) : AppColors.background

        // Reset all indicators
        resetDuplicateIndicators()

        // Set preview text based on user preferences
        configurePreviewText(item: item)


        // Set cache indicator visibility
        cacheIndicator.isHidden = !isCached

        // On macOS Catalyst, ensure no action buttons are showing
        if PlatformUtils.isMac {
            // Remove any accessory views that might be showing
            self.accessoryView = nil

            // Remove any secondary actions or swipe actions
            self.accessoryType = .none
            self.editingAccessoryType = .none
        }
    }
    
    /// Add a basic duplicate count badge to the cell
    /// - Parameter count: Number of articles in the duplicate group
    func addDuplicateBadge(count: Int) {
        guard count > 1 else {
            duplicateBadge.isHidden = true
            return
        }
        
        // Set badge text and show it
        duplicateBadge.text = "\(count)"
        duplicateBadge.isHidden = false
        duplicateBorder.isHidden = false
    }
    
    /// Simple marking for duplicate article
    func markAsDuplicate() {
        // Slightly dim the cell
        backgroundColor = AppColors.background.withAlphaComponent(0.9)
        
        // Show border
        duplicateBorder.isHidden = false
        
        // Add prefix to title
        if !titleLabel.text!.hasPrefix("⤷ ") {
            titleLabel.text = "⤷ " + titleLabel.text!
        }
    }
    
    /// Reset all duplicate indicators to default state
    private func resetDuplicateIndicators() {
        duplicateBadge.isHidden = true
        duplicateBorder.isHidden = true
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }
    
    // Overloaded configure method for backward compatibility with SearchResultsViewController
    func configure(with item: RSSItem) {
        let fontSize = UserDefaults.standard.float(forKey: "fontSize")
        let isRead = item.isRead
        configure(with: item, fontSize: CGFloat(fontSize), isRead: isRead)
    }
    
    private func configurePreviewText(item: RSSItem) {
        // Preview text length feature has been removed, always use "none"
        let previewMode = "none"

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
            
            // Connect preview to bottom
            previewToBottomConstraint?.isActive = true
        }
    }
    
    private func configureImage(item: RSSItem) {
        // Images are now permanently disabled
        
        // Hide by default
        articleImageView.isHidden = true
        
        // Deactivate image constraints
        titleToImageConstraint?.isActive = false
        imageToPreviewConstraint?.isActive = false
        imageWidthConstraint?.isActive = false
        imageHeightConstraint?.isActive = false
    }
    
    
    private func extractImageUrl(from htmlString: String) -> String? {
        // Simple regex to extract image URL from html content
        let pattern = "img\\s+[^>]*src\\s*=\\s*['\"]([^'\"]+)['\"]"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let matches = regex.matches(in: htmlString, options: [], range: NSRange(location: 0, length: htmlString.count))
        
        guard let match = matches.first,
              let range = Range(match.range(at: 1), in: htmlString) else {
            return nil
        }
        
        return String(htmlString[range])
    }
}
