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
        cardView.addSubview(sourceLabel)
        cardView.addSubview(timeAgoLabel)
        
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
            
            // Source label constraints
            sourceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            sourceLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            sourceLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            
            // Time ago label constraints
            timeAgoLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            timeAgoLabel.leadingAnchor.constraint(equalTo: sourceLabel.trailingAnchor, constant: 8),
            timeAgoLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            timeAgoLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
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
    }
}