import UIKit

class ThemePreviewCell: UITableViewCell {
    
    // MARK: - UI Components
    
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = 12
        view.tag = 100 // Tag to identify in the editor controller
        return view
    }()
    
    private let headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tag = 101 // Tag to identify in the editor controller
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Theme Preview"
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        label.tag = 102 // Tag to identify in the editor controller
        return label
    }()
    
    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "This is how your theme will look. Text should be readable on the background."
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 16)
        label.tag = 103 // Tag to identify in the editor controller
        return label
    }()
    
    private let linkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Accent Color for Links"
        label.font = UIFont.systemFont(ofSize: 16)
        label.tag = 104 // Tag to identify in the editor controller
        return label
    }()
    
    private let buttonView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 8
        view.tag = 105 // Tag to identify in the editor controller
        return view
    }()
    
    private let buttonLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Button"
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        return label
    }()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        
        // Add subviews
        contentView.addSubview(containerView)
        containerView.addSubview(headerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(bodyLabel)
        containerView.addSubview(linkLabel)
        containerView.addSubview(buttonView)
        buttonView.addSubview(buttonLabel)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 8),
            
            titleLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            bodyLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            linkLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 12),
            linkLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            linkLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            buttonView.topAnchor.constraint(equalTo: linkLabel.bottomAnchor, constant: 16),
            buttonView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            buttonView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            buttonView.heightAnchor.constraint(equalToConstant: 44),
            buttonView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            
            buttonLabel.centerXAnchor.constraint(equalTo: buttonView.centerXAnchor),
            buttonLabel.centerYAnchor.constraint(equalTo: buttonView.centerYAnchor)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with theme: AppTheme) {
        // Apply theme colors
        containerView.backgroundColor = theme.backgroundColorUI
        headerView.backgroundColor = theme.primaryColorUI
        titleLabel.textColor = theme.textColorUI
        bodyLabel.textColor = theme.textColorUI
        linkLabel.textColor = theme.accentColorUI
        buttonView.backgroundColor = theme.accentColorUI
        buttonLabel.textColor = .white // Button text is always white for contrast
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        // Reset to default state if needed
    }
}