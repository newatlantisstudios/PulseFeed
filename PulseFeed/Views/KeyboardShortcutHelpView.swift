import UIKit

/// A view that displays keyboard shortcuts help to the user
class KeyboardShortcutHelpView: UIView {
    
    // MARK: - Properties
    
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let closeButton = UIButton(type: .system)
    
    // MARK: - Initialization
    
    init() {
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 10
        clipsToBounds = true
        
        // Set up close button
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = AppColors.primary
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        
        // Set up scroll view for content
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        
        // Set up stack view for sections
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            
            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])
        
        // Add target to close button
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        // Add title
        let titleLabel = createTitleLabel("Keyboard Shortcuts")
        stackView.addArrangedSubview(titleLabel)
        
        // Add sections
        let shortcutSections = KeyboardShortcutManager.getShortcutDocumentation()
        
        for section in shortcutSections {
            addSection(title: section.title, shortcuts: section.shortcuts)
        }
        
        // Add usage note
        let noteLabel = UILabel()
        noteLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        noteLabel.textColor = AppColors.secondary
        noteLabel.text = "Note: Keyboard shortcuts require a connected hardware keyboard."
        noteLabel.numberOfLines = 0
        stackView.addArrangedSubview(noteLabel)
    }
    
    private func createTitleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        label.textColor = AppColors.primary
        return label
    }
    
    private func addSection(title: String, shortcuts: [(key: String, description: String)]) {
        // Add section title
        let sectionLabel = UILabel()
        sectionLabel.text = title
        sectionLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        sectionLabel.textColor = AppColors.accent
        stackView.addArrangedSubview(sectionLabel)
        
        // Add divider
        let divider = UIView()
        divider.backgroundColor = AppColors.secondary.withAlphaComponent(0.3)
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stackView.addArrangedSubview(divider)
        
        // Add shortcuts table
        let tableStack = UIStackView()
        tableStack.axis = .vertical
        tableStack.spacing = 10
        tableStack.alignment = .fill
        tableStack.distribution = .fill
        
        for shortcut in shortcuts {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 16
            rowStack.alignment = .center
            rowStack.distribution = .fill
            
            // Key label
            let keyLabel = UILabel()
            keyLabel.text = shortcut.key
            keyLabel.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
            keyLabel.textColor = AppColors.primary
            keyLabel.backgroundColor = AppColors.secondary.withAlphaComponent(0.1)
            keyLabel.layer.cornerRadius = 6
            keyLabel.clipsToBounds = true
            keyLabel.textAlignment = .center
            keyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            keyLabel.setContentHuggingPriority(.required, for: .horizontal)
            keyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
            
            // Add padding to key label
            keyLabel.layoutMargins = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
            
            // Description label
            let descLabel = UILabel()
            descLabel.text = shortcut.description
            descLabel.font = UIFont.systemFont(ofSize: 15)
            descLabel.textColor = .label
            descLabel.numberOfLines = 0
            
            rowStack.addArrangedSubview(keyLabel)
            rowStack.addArrangedSubview(descLabel)
            
            tableStack.addArrangedSubview(rowStack)
        }
        
        stackView.addArrangedSubview(tableStack)
        
        // Add spacing after section
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
        stackView.addArrangedSubview(spacer)
    }
    
    // MARK: - Actions
    
    @objc private func closeTapped() {
        removeFromSuperview()
    }
    
    // MARK: - Helper Methods
    
    /// Display this help view on the given parent view
    func show(on view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerYAnchor.constraint(equalTo: view.centerYAnchor),
            widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85),
            heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.8)
        ])
        
        // Add animation
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
            self.transform = .identity
        }
    }
}