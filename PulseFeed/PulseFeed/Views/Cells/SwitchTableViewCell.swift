import UIKit

class SwitchTableViewCell: UITableViewCell {
    
    // MARK: - Properties
    
    var switchToggleHandler: ((Bool) -> Void)?
    
    // Alternate name for compatibility with existing code
    var onSwitchChanged: ((Bool) -> Void)? {
        get { return switchToggleHandler }
        set { switchToggleHandler = newValue }
    }
    
    // Make switchControl public so it can be accessed from other classes
    let switchControl: UISwitch = {
        let switchControl = UISwitch()
        switchControl.onTintColor = AppColors.accent
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        return switchControl
    }()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        contentView.addSubview(switchControl)
        
        NSLayoutConstraint.activate([
            switchControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            switchControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
        
        switchControl.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
    }
    
    // MARK: - Actions
    
    @objc private func switchValueChanged(_ sender: UISwitch) {
        switchToggleHandler?(sender.isOn)
    }
    
    // MARK: - Public Methods
    
    func configure(with title: String, subtitle: String? = nil, isOn: Bool) {
        textLabel?.text = title
        detailTextLabel?.text = subtitle
        switchControl.isOn = isOn
    }
}