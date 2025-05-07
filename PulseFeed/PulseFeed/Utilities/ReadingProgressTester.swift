import Foundation

class ReadingProgressTester {
    
    static let shared = ReadingProgressTester()
    
    /// Tests saving and retrieving reading progress
    func testReadingProgressStorage() {
        // Sample test article links
        let testLinks = [
            "https://example.com/article1",
            "https://example.com/article2",
            "https://example.com/article3"
        ]
        
        // Sample progress values
        let testProgressValues: [Float] = [0.25, 0.5, 0.75]
        
        // Save test values
        var saveSuccess = true
        for (index, link) in testLinks.enumerated() {
            let progress = testProgressValues[index]
            
            // Save reading progress synchronously
            let saveExpectation = XCTestExpectation(description: "Save reading progress")
            StorageManager.shared.saveReadingProgress(for: link, progress: progress) { success, error in
                if !success || error != nil {
                    saveSuccess = false
                    print("Failed to save reading progress for \(link): \(error?.localizedDescription ?? "Unknown error")")
                }
                saveExpectation.fulfill()
            }
            
            // Wait for save to complete
            let _ = XCTWaiter.wait(for: [saveExpectation], timeout: 5.0)
        }
        
        // Verify saved values
        var retrieveSuccess = true
        for (index, link) in testLinks.enumerated() {
            let expectedProgress = testProgressValues[index]
            
            // Retrieve reading progress synchronously
            let retrieveExpectation = XCTestExpectation(description: "Retrieve reading progress")
            var retrievedProgress: Float = 0
            
            StorageManager.shared.getReadingProgress(for: link) { result in
                switch result {
                case .success(let progress):
                    retrievedProgress = progress
                    if abs(progress - expectedProgress) > 0.01 {
                        retrieveSuccess = false
                        print("Progress mismatch for \(link): expected \(expectedProgress), got \(progress)")
                    }
                case .failure(let error):
                    retrieveSuccess = false
                    print("Failed to retrieve reading progress for \(link): \(error.localizedDescription)")
                }
                retrieveExpectation.fulfill()
            }
            
            // Wait for retrieval to complete
            let _ = XCTWaiter.wait(for: [retrieveExpectation], timeout: 5.0)
        }
        
        // Print test results
        if saveSuccess && retrieveSuccess {
            print("✅ Reading progress storage test passed")
        } else {
            print("❌ Reading progress storage test failed")
        }
    }
    
    /// Cleans up test data
    func cleanupTestData() {
        let cleanupExpectation = XCTestExpectation(description: "Clean up test data")
        
        StorageManager.shared.clearAllReadingProgress { success, error in
            if success {
                print("✅ Successfully cleared test reading progress data")
            } else if let error = error {
                print("❌ Failed to clear test data: \(error.localizedDescription)")
            }
            cleanupExpectation.fulfill()
        }
        
        // Wait for cleanup to complete
        let _ = XCTWaiter.wait(for: [cleanupExpectation], timeout: 5.0)
    }
}

// XCTest-like functionality for testing outside of a test target
class XCTestExpectation {
    let description: String
    private var fulfilled = false
    
    init(description: String) {
        self.description = description
    }
    
    func fulfill() {
        fulfilled = true
    }
    
    var isFulfilled: Bool {
        return fulfilled
    }
}

class XCTWaiter {
    static func wait(for expectations: [XCTestExpectation], timeout: TimeInterval) -> Bool {
        let endTime = Date().addingTimeInterval(timeout)
        
        while Date() < endTime {
            // Check if all expectations are fulfilled
            let allFulfilled = expectations.allSatisfy { $0.isFulfilled }
            if allFulfilled {
                return true
            }
            
            // Sleep briefly to avoid consuming too much CPU
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        // Timed out
        let fulfilledCount = expectations.filter { $0.isFulfilled }.count
        print("⚠️ Timed out waiting for expectations: \(fulfilledCount)/\(expectations.count) fulfilled")
        return false
    }
}

// XCTest-like assertion function
func XCTAssertEqual<T: Equatable>(_ first: T, _ second: T, accuracy: T? = nil, file: String = #file, line: Int = #line) -> Bool {
    if first == second {
        return true
    } else {
        print("❌ Assertion failed at \(file):\(line) - \(first) is not equal to \(second)")
        return false
    }
}