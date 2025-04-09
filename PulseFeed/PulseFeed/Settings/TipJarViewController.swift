import UIKit
import StoreKit

class TipJarViewController: UIViewController, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    
    // Set of product identifiers
    private let productIDs: Set<String> = ["com.newatlantisstudios.pulsefeed.tip1",
                                             "com.newatlantisstudios.pulsefeed.tip3",
                                             "com.newatlantisstudios.pulsefeed.tip5"]
    private var products: [SKProduct] = []
    
    // MARK: - UI Elements

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Enjoying PulseFeed? Consider leaving a tip to support future development!"
        label.numberOfLines = 0 // Allows multiple lines
        label.textAlignment = .center
        label.font = UIFont.preferredFont(forTextStyle: .body)
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
        configuration.buttonSize = .medium

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
        configuration.buttonSize = .medium

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
        configuration.buttonSize = .medium

        let button = UIButton(configuration: configuration)
        button.tag = 5
        button.addTarget(self, action: #selector(tipButtonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tip Jar"
        view.backgroundColor = .systemBackground
        
        setupUI()
        SKPaymentQueue.default().add(self)
        fetchProducts()
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        let stack = UIStackView(arrangedSubviews: [tip1Button, tip3Button, tip5Button])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        
        view.addSubview(descriptionLabel) // Add the label to the view

        NSLayoutConstraint.activate([
            // Constraints for the description label
            descriptionLabel.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -30), // Position above the stack
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            descriptionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Existing constraints for the button stack
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
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
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("Product request failed with error: \(error.localizedDescription)")
        // Optionally update the UI to indicate an error occurred.
    }
    
    private func updateButtonsWithProductInfo() {
        for product in products {
            let priceString = priceStringFor(product: product)
            switch product.productIdentifier {
            case "com.newatlantisstudios.pulsefeed.tip1":
                tip1Button.setTitle("Tip \(priceString)", for: .normal)
            case "com.newatlantisstudios.pulsefeed.tip3":
                tip3Button.setTitle("Tip \(priceString)", for: .normal)
            case "com.newatlantisstudios.pulsefeed.tip5":
                tip5Button.setTitle("Tip \(priceString)", for: .normal)
            default:
                break
            }
        }
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
            productToPurchase = products.first(where: { $0.productIdentifier == "com.newatlantisstudios.pulsefeed.tip3" })
        case 5:
            productToPurchase = products.first(where: { $0.productIdentifier == "com.newatlantisstudios.pulsefeed.tip5" })
        default:
            break
        }
        
        guard let product = productToPurchase, SKPaymentQueue.canMakePayments() else {
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
                showAlert(title: "Thank You", message: "Your tip is appreciated!")
            case .failed:
                SKPaymentQueue.default().finishTransaction(transaction)
                let errorDescription = transaction.error?.localizedDescription ?? "Unknown error."
                showAlert(title: "Purchase Failed", message: errorDescription)
            default:
                break
            }
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
