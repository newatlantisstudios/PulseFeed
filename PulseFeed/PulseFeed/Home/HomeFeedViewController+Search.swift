import UIKit

// MARK: - Search Extensions

extension HomeFeedViewController: AdvancedSearchDelegate {
    
    /// Set up the search button in the navigation bar
    func setupSearchButton() {
        // Create a search icon button
        let searchButton = UIBarButtonItem(
            barButtonSystemItem: .search,
            target: self,
            action: #selector(searchButtonTapped)
        )
        
        // If we already have an array of right bar button items
        if let existingItems = navigationItem.rightBarButtonItems {
            // Add the search button to the beginning of the array
            navigationItem.rightBarButtonItems = [searchButton] + existingItems
        } else {
            // Otherwise just set it as the right bar button item
            navigationItem.rightBarButtonItem = searchButton
        }
    }
    
    @objc func searchButtonTapped() {
        // Create and present the advanced search view controller
        let searchVC = AdvancedSearchViewController()
        searchVC.setupWithData(articles: _allItems, bookmarkedItems: bookmarkedItems, heartedItems: heartedItems)
        searchVC.delegate = self
        
        let navController = UINavigationController(rootViewController: searchVC)
        present(navController, animated: true)
    }
    
    // MARK: - AdvancedSearchDelegate
    
    func didPerformSearch(with query: SearchQuery, results: [RSSItem]) {
        // Create and push search results view controller
        let resultsVC = SearchResultsViewController(query: query, results: results)
        navigationController?.pushViewController(resultsVC, animated: true)
    }
    
    func didSelectSavedSearch(_ query: SearchQuery) {
        // Execute the saved search query
        query.filterArticles(_allItems, in: bookmarkedItems, heartedItems: heartedItems) { [weak self] results in
            guard let self = self else { return }
            
            // Show the results
            self.didPerformSearch(with: query, results: results)
        }
    }
}