import UIKit

/// A simple view that displays a collection of tags
class TagsContainerView: UIView {
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillProportionally
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 30),
            
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
    
    func setTags(_ tags: [Tag]) {
        print("DEBUG: TagsContainerView - Setting \(tags.count) tags")
        
        // Remove existing tags
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add new tags
        for tag in tags {
            print("DEBUG: TagsContainerView - Adding tag: \(tag.name)")
            let tagView = createTagView(for: tag)
            stackView.addArrangedSubview(tagView)
        }
        
        // Update visibility based on if we have tags
        isHidden = tags.isEmpty
        print("DEBUG: TagsContainerView - Container hidden: \(isHidden)")
        
        // Force layout update
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    private func createTagView(for tag: Tag) -> UIView {
        // Create container view
        let tagView = UIView()
        tagView.backgroundColor = UIColor(hex: tag.colorHex).withAlphaComponent(0.2)
        tagView.layer.cornerRadius = 12
        tagView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create label
        let label = UILabel()
        label.text = tag.name
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor(hex: tag.colorHex)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to container
        tagView.addSubview(label)
        
        // Set constraints
        NSLayoutConstraint.activate([
            tagView.heightAnchor.constraint(equalToConstant: 24),
            
            label.topAnchor.constraint(equalTo: tagView.topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: tagView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: tagView.trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: tagView.bottomAnchor, constant: -4)
        ])
        
        return tagView
    }
}

class EnhancedRSSCell: UITableViewCell {
    static let identifier = "EnhancedRSSCell"
    
    // Properties to track bookmarked and hearted status
    var isBookmarked: Bool = false
    var isHearted: Bool = false
    
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
    
    // Cache indicator - create once and reuse
    private let cacheIndicator: UIView = {
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 12))
        indicator.backgroundColor = AppColors.cacheIndicator
        indicator.layer.cornerRadius = 6
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isHidden = true // Hide by default
        return indicator
    }()
    
    // Duplicate indicator badge
    private let duplicateBadge: UILabel = {
        let label = UILabel()
        label.backgroundColor = UIColor(hex: "1E90FF") // Blue color for duplicates
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true // Hide by default
        return label
    }()
    
    // Duplicate indicator border
    private let duplicateBorder: UIView = {
        let view = UIView()
        view.layer.borderColor = UIColor(hex: "1E90FF").cgColor
        view.layer.borderWidth = 2
        view.backgroundColor = .clear
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true // Hide by default
        return view
    }()
    
    // Tags container
    private let tagsContainerView = TagsContainerView()
    
    // Constraints that we'll need to modify based on settings
    private var titleToPreviewConstraint: NSLayoutConstraint?
    private var previewToBottomConstraint: NSLayoutConstraint?
    private var titleToImageConstraint: NSLayoutConstraint?
    private var imageToPreviewConstraint: NSLayoutConstraint?
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var tagsToBottomConstraint: NSLayoutConstraint?
    private var previewToTagsConstraint: NSLayoutConstraint?
    
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
        
        // Add the duplicate border behind the card to highlight the entire cell
        contentView.addSubview(duplicateBorder)
        
        contentView.addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(articleImageView)
        cardView.addSubview(previewTextLabel)
        cardView.addSubview(tagsContainerView)
        cardView.addSubview(sourceLabel)
        cardView.addSubview(timeAgoLabel)
        cardView.addSubview(cacheIndicator) // Add cache indicator to card view
        
        // Add duplicate indicator views
        contentView.addSubview(duplicateBorder)
        contentView.addSubview(duplicateBadge)
        
        // Base constraints that are always active
        NSLayoutConstraint.activate([
            // Card view constraints
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            // Duplicate border constraints (slightly larger than the card view)
            duplicateBorder.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            duplicateBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            duplicateBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            duplicateBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            
            // Duplicate badge constraints (positioned at the top right)
            duplicateBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            duplicateBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            duplicateBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            duplicateBadge.heightAnchor.constraint(equalToConstant: 20),
            
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
            
            // Tags container constraints
            tagsContainerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            tagsContainerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            
            // Source label constraints
            sourceLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            sourceLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            
            // Time ago label constraints
            timeAgoLabel.leadingAnchor.constraint(equalTo: sourceLabel.trailingAnchor, constant: 8),
            timeAgoLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            timeAgoLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            
            // Cache indicator constraints - always positioned but visibility toggled
            cacheIndicator.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            cacheIndicator.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            cacheIndicator.widthAnchor.constraint(equalToConstant: 12),
            cacheIndicator.heightAnchor.constraint(equalToConstant: 12),
            
            // Duplicate badge constraints
            duplicateBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            duplicateBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            duplicateBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            duplicateBadge.heightAnchor.constraint(equalToConstant: 20),
            
            // Duplicate border constraints (slightly larger than the card view)
            duplicateBorder.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            duplicateBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            duplicateBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            duplicateBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
        
        // Store constraints that will be modified dynamically
        titleToPreviewConstraint = previewTextLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
        previewToBottomConstraint = sourceLabel.topAnchor.constraint(equalTo: previewTextLabel.bottomAnchor, constant: 8)
        
        titleToImageConstraint = articleImageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
        imageToPreviewConstraint = previewTextLabel.topAnchor.constraint(equalTo: articleImageView.bottomAnchor, constant: 8)
        
        imageWidthConstraint = articleImageView.widthAnchor.constraint(equalTo: cardView.widthAnchor, constant: -32)
        imageHeightConstraint = articleImageView.heightAnchor.constraint(equalToConstant: 150)
        
        // Tags constraints
        tagsToBottomConstraint = sourceLabel.topAnchor.constraint(equalTo: tagsContainerView.bottomAnchor, constant: 8)
        previewToTagsConstraint = tagsContainerView.topAnchor.constraint(equalTo: previewTextLabel.bottomAnchor, constant: 8)
        
        // Default layout is title directly to source/time (compact view)
        sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8).isActive = true
        timeAgoLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8).isActive = true
        
        // Hide tags container by default
        tagsContainerView.isHidden = true
    }
    
    // Original configure method with required parameters
    func configure(with item: RSSItem, fontSize: CGFloat, isRead: Bool, isCached: Bool = false) {
        titleLabel.text = item.title
        sourceLabel.text = item.source
        timeAgoLabel.text = DateUtils.getTimeAgo(from: item.pubDate)
        
        // Apply different styling based on read state
        titleLabel.textColor = isRead ? AppColors.secondary : AppColors.accent
        titleLabel.font = UIFont.systemFont(ofSize: fontSize, weight: isRead ? .regular : .medium)
        
        // Update card appearance for read state
        cardView.alpha = isRead ? 0.85 : 1.0
        
        // Reset duplicate indicators
        resetDuplicateIndicators()
        
        // Set preview text based on user preferences
        configurePreviewText(item: item)
        
        // Configure image if available and enabled
        configureImage(item: item)
        
        // Configure tags
        configureTags(item: item)
        
        // Apply compact/expanded mode
        applyViewMode()
        
        // Set cache indicator visibility
        cacheIndicator.isHidden = !isCached
    }
    
    /// Add a duplicate count badge to the cell
    /// - Parameter count: Number of articles in the duplicate group
    func addDuplicateBadge(count: Int) {
        guard count > 1 else {
            duplicateBadge.isHidden = true
            return
        }
        
        // Configure badge with count
        duplicateBadge.text = "\(count)"
        
        // Make badge wide enough to fit the text with padding
        let badgeWidth = duplicateBadge.intrinsicContentSize.width + 8
        duplicateBadge.widthAnchor.constraint(equalToConstant: max(20, badgeWidth)).isActive = true
        
        // Style the badge
        duplicateBadge.layer.backgroundColor = UIColor(hex: "1E90FF").cgColor
        
        // Show the badge
        duplicateBadge.isHidden = false
        
        // Add a subtle blue border to indicate this is the primary article
        duplicateBorder.isHidden = false
        duplicateBorder.layer.borderColor = UIColor(hex: "1E90FF").withAlphaComponent(0.5).cgColor
    }
    
    /// Mark this cell as a duplicate article (not the primary version)
    func markAsDuplicate() {
        // Style changes to indicate this is a secondary duplicate
        cardView.alpha = 0.8
        
        // Add a dimmed blue border
        duplicateBorder.isHidden = false
        duplicateBorder.layer.borderColor = UIColor(hex: "1E90FF").withAlphaComponent(0.3).cgColor
        duplicateBorder.layer.borderWidth = 1
        
        // Add a subtle prefix to the title
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
        
        // Make sure the duplicate badge has rounded corners
        duplicateBadge.layer.cornerRadius = duplicateBadge.bounds.height / 2
    }
    
    // Overloaded configure method for backward compatibility with SearchResultsViewController
    func configure(with item: RSSItem) {
        let fontSize = UserDefaults.standard.float(forKey: "fontSize")
        let isRead = item.isRead
        configure(with: item, fontSize: CGFloat(fontSize), isRead: isRead)
    }
    
    private func configurePreviewText(item: RSSItem) {
        let previewMode = UserDefaults.standard.string(forKey: "previewTextLength") ?? "none"
        
        // Hide by default
        previewTextLabel.isHidden = true
        
        // Deactivate constraints
        previewToBottomConstraint?.isActive = false
        titleToPreviewConstraint?.isActive = false
        previewToTagsConstraint?.isActive = false
        
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
            
            // If tags are visible, connect preview to tags
            if !tagsContainerView.isHidden {
                previewToTagsConstraint?.isActive = true
            } else {
                // Otherwise connect preview to bottom
                previewToBottomConstraint?.isActive = true
            }
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
        
        // Extract image URL from the RSS item's description
        if let description = item.description,
           let imageUrlString = extractImageUrl(from: description),
           let imageUrl = URL(string: imageUrlString) {
            
            // Clear previous image and background color
            articleImageView.image = nil
            articleImageView.backgroundColor = .clear
            
            // Create a placeholder image
            let placeholder = UIImage(systemName: "photo")?.withTintColor(AppColors.accent.withAlphaComponent(0.3), renderingMode: .alwaysOriginal)
            
            // Load the image with caching
            articleImageView.loadImage(from: imageUrl, placeholder: placeholder)
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
    
    private func configureTags(item: RSSItem) {
        // Reset tags
        tagsContainerView.setTags([])
        
        // Deactivate tag constraints
        tagsToBottomConstraint?.isActive = false
        previewToTagsConstraint?.isActive = false
        
        // Hide tags container initially until we get tags
        tagsContainerView.isHidden = true
        
        print("DEBUG: EnhancedRSSCell - Fetching tags for item: \(item.title)")
        print("DEBUG: EnhancedRSSCell - Item link: \(item.link)")
        
        // Fetch tags for the item
        item.getTags { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let tags):
                    print("DEBUG: EnhancedRSSCell - Got \(tags.count) tags for item: \(item.title)")
                    if !tags.isEmpty {
                        // Log each tag
                        for tag in tags {
                            print("DEBUG: EnhancedRSSCell - Tag: \(tag.name), Color: \(tag.colorHex)")
                        }
                        
                        // Set tags in the container
                        self.tagsContainerView.setTags(tags)
                        self.tagsContainerView.isHidden = false
                        
                        // Activate constraints
                        self.tagsToBottomConstraint?.isActive = true
                        
                        // If preview is visible, connect preview to tags
                        if !self.previewTextLabel.isHidden {
                            self.previewToTagsConstraint?.isActive = true
                            self.previewToBottomConstraint?.isActive = false
                        }
                        
                        // Force layout update
                        self.setNeedsLayout()
                        self.layoutIfNeeded()
                        
                        print("DEBUG: EnhancedRSSCell - Tags container is now visible: \(!self.tagsContainerView.isHidden)")
                    } else {
                        // If no tags, hide the container
                        self.tagsContainerView.isHidden = true
                        print("DEBUG: EnhancedRSSCell - No tags, hiding container")
                    }
                case .failure(let error):
                    // If tags fetch fails, keep tags hidden
                    self.tagsContainerView.isHidden = true
                    print("DEBUG: EnhancedRSSCell - Failed to get tags: \(error.localizedDescription)")
                }
            }
        }
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