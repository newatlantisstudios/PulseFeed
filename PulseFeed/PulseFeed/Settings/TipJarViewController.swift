import UIKit
import StoreKit

class TipJarViewController: UIViewController, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    
    // Set of product identifiers
    private let productIDs: Set<String> = ["com.newatlantisstudios.pulsefeed.tip1",
                                           "com.newatlantisstudios.pulsefeed.tip32",
                                           "com.newatlantisstudios.pulsefeed.tip5"]
    private var products: [SKProduct] = []
    
    // MARK: - UI Elements
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 16
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let headerImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemOrange
        imageView.image = UIImage(systemName: "heart.fill")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Enjoying PulseFeed? Consider leaving a tip to support future development!"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let thankYouLabel: UILabel = {
        let label = UILabel()
        label.text = "Your support helps keep PulseFeed ad-free and enables new features!"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // UI Buttons for each tip option.
    private lazy var tip1Button: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Loading..."
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemOrange
        configuration.buttonSize = .large
        
        let button = UIButton(configuration: configuration)
        button.tag = 1
        button.addTarget(self, action: #selector(tipButtonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var tip3Button: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Loading..."
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemOrange
        configuration.buttonSize = .large
        
        let button = UIButton(configuration: configuration)
        button.tag = 3
        button.addTarget(self, action: #selector(tipButtonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var tip5Button: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Loading..."
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemOrange
        configuration.buttonSize = .large
        
        let button = UIButton(configuration: configuration)
        button.tag = 5
        button.addTarget(self, action: #selector(tipButtonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tip Jar"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .always
        
        setupUI()
        setupLoadingState(isLoading: true)
        SKPaymentQueue.default().add(self)
        fetchProducts()
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Add header image and container view
        view.addSubview(headerImageView)
        view.addSubview(containerView)
        
        // Add elements to container
        containerView.addSubview(descriptionLabel)
        containerView.addSubview(thankYouLabel)
        
        // Create tip buttons stack
        let buttonStack = UIStackView(arrangedSubviews: [tip1Button, tip3Button, tip5Button])
        buttonStack.axis = .vertical
        buttonStack.spacing = 16
        buttonStack.distribution = .fillEqually
        buttonStack.alignment = .fill
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(buttonStack)
        
        // Add loading indicator
        containerView.addSubview(loadingIndicator)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Header image
            headerImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            headerImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            headerImageView.widthAnchor.constraint(equalToConstant: 80),
            headerImageView.heightAnchor.constraint(equalToConstant: 80),
            
            // Container view
            containerView.topAnchor.constraint(equalTo: headerImageView.bottomAnchor, constant: 24),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            containerView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            
            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Thank you label
            thankYouLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 8),
            thankYouLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            thankYouLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Button stack
            buttonStack.topAnchor.constraint(equalTo: thankYouLabel.bottomAnchor, constant: 24),
            buttonStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: buttonStack.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: buttonStack.centerYAnchor),
            
            // Button heights
            tip1Button.heightAnchor.constraint(equalToConstant: 50),
            tip3Button.heightAnchor.constraint(equalToConstant: 50),
            tip5Button.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Apply shadow to container
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowRadius = 4
    }
    
    private func setupLoadingState(isLoading: Bool) {
        if isLoading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
        
        tip1Button.isEnabled = !isLoading
        tip3Button.isEnabled = !isLoading
        tip5Button.isEnabled = !isLoading
        
        if isLoading {
            tip1Button.alpha = 0.7
            tip3Button.alpha = 0.7
            tip5Button.alpha = 0.7
        } else {
            tip1Button.alpha = 1.0
            tip3Button.alpha = 1.0
            tip5Button.alpha = 1.0
        }
    }
    
    // MARK: - In-App Purchase Methods
    
    private func fetchProducts() {
        let request = SKProductsRequest(productIdentifiers: productIDs)
        request.delegate = self
        request.start()
    }
    
    // SKProductsRequestDelegate method
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        products = response.products
        print("Valid products: \(products)")
        print("Invalid product identifiers: \(response.invalidProductIdentifiers)")
        DispatchQueue.main.async {
            self.updateButtonsWithProductInfo()
            self.setupLoadingState(isLoading: false)
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("Product request failed with error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.setupLoadingState(isLoading: false)
            self.showAlert(title: "Error", message: "Failed to load tip options. Please try again later.")
        }
    }
    
    private func updateButtonsWithProductInfo() {
        for product in products {
            let priceString = priceStringFor(product: product)
            var configuration: UIButton.Configuration
            
            switch product.productIdentifier {
            case "com.newatlantisstudios.pulsefeed.tip1":
                configuration = createButtonConfiguration(title: "Small Tip \(priceString)", icon: "cup.and.saucer.fill")
                tip1Button.configuration = configuration
            case "com.newatlantisstudios.pulsefeed.tip32":
                configuration = createButtonConfiguration(title: "Medium Tip \(priceString)", icon: "mug.fill")
                tip3Button.configuration = configuration
            case "com.newatlantisstudios.pulsefeed.tip5":
                configuration = createButtonConfiguration(title: "Large Tip \(priceString)", icon: "takeoutbag.and.cup.and.straw.fill")
                tip5Button.configuration = configuration
            default:
                break
            }
        }
    }
    
    private func createButtonConfiguration(title: String, icon: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemOrange
        configuration.buttonSize = .large
        
        if let image = UIImage(systemName: icon) {
            configuration.image = image
            configuration.imagePadding = 8
            configuration.imagePlacement = .leading
        }
        
        return configuration
    }
    
    private func priceStringFor(product: SKProduct) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price) ?? "\(product.price)"
    }
    
    @objc private func tipButtonTapped(_ sender: UIButton) {
        var productToPurchase: SKProduct?
        switch sender.tag {
        case 1:
            productToPurchase = products.first(where: { $0.productIdentifier == "com.newatlantisstudios.pulsefeed.tip1" })
        case 3:
            productToPurchase = products.first(where: { $0.productIdentifier == "com.newatlantisstudios.pulsefeed.tip32" })
        case 5:
            productToPurchase = products.first(where: { $0.productIdentifier == "com.newatlantisstudios.pulsefeed.tip5" })
        default:
            break
        }
        
        setupLoadingState(isLoading: true)
        
        guard let product = productToPurchase, SKPaymentQueue.canMakePayments() else {
            setupLoadingState(isLoading: false)
            let alert = UIAlertController(title: "Error",
                                          message: "In-App Purchases are disabled or product not found.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            return
        }
        
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    // SKPaymentTransactionObserver method
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                SKPaymentQueue.default().finishTransaction(transaction)
                showThankYouAlert()
                setupLoadingState(isLoading: false)
            case .failed:
                SKPaymentQueue.default().finishTransaction(transaction)
                let errorDescription = transaction.error?.localizedDescription ?? "Unknown error."
                showAlert(title: "Purchase Failed", message: errorDescription)
                setupLoadingState(isLoading: false)
            case .purchasing:
                // Transaction is in process - keep loading state
                break
            case .restored:
                SKPaymentQueue.default().finishTransaction(transaction)
                setupLoadingState(isLoading: false)
            case .deferred:
                setupLoadingState(isLoading: false)
            @unknown default:
                setupLoadingState(isLoading: false)
            }
        }
    }
    
    private func showThankYouAlert() {
        DispatchQueue.main.async {
            // Create a custom alert view
            let alertController = UIAlertController(title: "Thank You!", message: "Your support is greatly appreciated and helps fund new features!", preferredStyle: .alert)
            
            // Add a heart image to the alert
            let imageView = UIImageView(image: UIImage(systemName: "heart.fill"))
            imageView.tintColor = .systemPink
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            
            // Customize alert appearance by adding subviews to its contentView
            alertController.view.addSubview(imageView)
            
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: alertController.view.centerXAnchor),
                imageView.bottomAnchor.constraint(equalTo: alertController.view.bottomAnchor, constant: -20),
                imageView.widthAnchor.constraint(equalToConstant: 40),
                imageView.heightAnchor.constraint(equalToConstant: 40)
            ])
            
            // Add an OK action
            alertController.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Present the alert
            self.present(alertController, animated: true)
        }
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title,
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
}