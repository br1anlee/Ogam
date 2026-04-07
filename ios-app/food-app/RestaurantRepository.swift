import Foundation
import FirebaseFirestore
import CoreLocation
import Combine

@MainActor
class RestaurantRepository: ObservableObject {
    @Published var restaurants: [Restaurant] = []
    @Published var isLoading = false
    @Published var error: RepositoryError?
    
    let db = Firestore.firestore()  // Changed from private to internal
    private var listener: ListenerRegistration?
    private let cacheManager = CacheManager()
    
    // MARK: - Cache Keys
    private let restaurantsCacheKey = "cached_restaurants"
    private let lastFetchKey = "last_restaurant_fetch"
    private let cacheExpirationInterval: TimeInterval = 3600 // 1 hour
    
    enum RepositoryError: LocalizedError {
        case fetchFailed(String)
        case cacheFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .fetchFailed(let message):
                return "Failed to fetch restaurants: \(message)"
            case .cacheFailed(let message):
                return "Cache error: \(message)"
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        // Load cached data immediately for offline support
        loadCachedRestaurants()
    }
    
    // MARK: - Real-time Listening
    func startListening() {
        isLoading = true
        
        listener = db.collection("restaurants")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                self.isLoading = false
                
                if let error = error {
                    print("Firestore error: \(error.localizedDescription)")
                    self.error = .fetchFailed(error.localizedDescription)
                    // Keep using cached data if fetch fails
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found")
                    return
                }
                
                self.restaurants = documents.compactMap { doc in
                    do {
                        return try doc.data(as: Restaurant.self)
                    } catch {
                        print("Error decoding restaurant: \(error)")
                        return nil
                    }
                }
                
                // Cache the results
                self.cacheRestaurants(self.restaurants)
                
                print("✅ Loaded \(self.restaurants.count) restaurants from Firestore")
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    // MARK: - One-time Fetch
    func fetchRestaurants() async {
        // Check if cache is still fresh
        if isCacheFresh() && !restaurants.isEmpty {
            print("Using fresh cached data")
            return
        }
        
        isLoading = true
        
        do {
            let snapshot = try await db.collection("restaurants").getDocuments()
            
            let fetchedRestaurants = snapshot.documents.compactMap { doc -> Restaurant? in
                do {
                    return try doc.data(as: Restaurant.self)
                } catch {
                    print("Error decoding restaurant: \(error)")
                    return nil
                }
            }
            
            self.restaurants = fetchedRestaurants
            cacheRestaurants(fetchedRestaurants)
            updateLastFetchTime()
            
            print("✅ Fetched \(fetchedRestaurants.count) restaurants")
            
        } catch {
            print("❌ Fetch failed: \(error.localizedDescription)")
            self.error = .fetchFailed(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    // MARK: - Search & Filter
    func searchRestaurants(
        cuisine: String? = nil,
        minRating: Double? = nil,
        city: String? = nil,
        tags: [String]? = nil
    ) async throws -> [Restaurant] {
        var query: Query = db.collection("restaurants")
        
        if let cuisine = cuisine {
            query = query.whereField("cuisine", isEqualTo: cuisine)
        }
        
        if let minRating = minRating {
            query = query.whereField("rating", isGreaterThanOrEqualTo: minRating)
        }
        
        if let city = city {
            query = query.whereField("city", isEqualTo: city)
        }
        
        let snapshot = try await query.getDocuments()
        
        var results = snapshot.documents.compactMap { doc -> Restaurant? in
            try? doc.data(as: Restaurant.self)
        }
        
        // Filter by tags locally (Firestore doesn't support array-contains with multiple values)
        if let tags = tags, !tags.isEmpty {
            results = results.filter { restaurant in
                guard let restaurantTags = restaurant.tags else { return false }
                return !Set(tags).isDisjoint(with: Set(restaurantTags))
            }
        }
        
        return results
    }
    
    func searchByLocation(
        near coordinate: CLLocationCoordinate2D,
        radiusInMeters: Double = 10000
    ) -> [Restaurant] {
        return restaurants.filter { restaurant in
            let distance = calculateDistance(from: coordinate, to: restaurant)
            return distance <= radiusInMeters
        }.sorted { restaurant1, restaurant2 in
            let dist1 = calculateDistance(from: coordinate, to: restaurant1)
            let dist2 = calculateDistance(from: coordinate, to: restaurant2)
            return dist1 < dist2
        }
    }
    
    func searchByText(_ searchText: String) -> [Restaurant] {
        guard !searchText.isEmpty else { return restaurants }
        
        let lowercased = searchText.lowercased()
        return restaurants.filter { restaurant in
            restaurant.name.localizedCaseInsensitiveContains(lowercased) ||
            restaurant.cuisine.localizedCaseInsensitiveContains(lowercased) ||
            restaurant.address.localizedCaseInsensitiveContains(lowercased) ||
            restaurant.description.localizedCaseInsensitiveContains(lowercased) ||
            (restaurant.neighborhood?.localizedCaseInsensitiveContains(lowercased) ?? false) ||
            (restaurant.tags?.contains(where: { $0.localizedCaseInsensitiveContains(lowercased) }) ?? false)
        }
    }
    
    // MARK: - CRUD Operations
    func addRestaurant(_ restaurant: Restaurant) async throws {
        var restaurantData = restaurant
        restaurantData.id = nil // Let Firestore generate ID
        
        do {
            let docRef = try db.collection("restaurants").addDocument(from: restaurantData)
            print("✅ Added restaurant with ID: \(docRef.documentID)")
        } catch {
            print("❌ Failed to add restaurant: \(error)")
            throw error
        }
    }
    
    func updateRestaurant(_ restaurant: Restaurant) async throws {
        guard let id = restaurant.id else {
            throw NSError(domain: "RestaurantRepository", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Restaurant ID is required for update"
            ])
        }
        
        do {
            try db.collection("restaurants").document(id).setData(from: restaurant, merge: true)
            print("✅ Updated restaurant: \(id)")
        } catch {
            print("❌ Failed to update restaurant: \(error)")
            throw error
        }
    }
    
    func deleteRestaurant(_ restaurant: Restaurant) async throws {
        guard let id = restaurant.id else {
            throw NSError(domain: "RestaurantRepository", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Restaurant ID is required for deletion"
            ])
        }
        
        do {
            try await db.collection("restaurants").document(id).delete()
            print("✅ Deleted restaurant: \(id)")
        } catch {
            print("❌ Failed to delete restaurant: \(error)")
            throw error
        }
    }
    
    // MARK: - Caching
    private func cacheRestaurants(_ restaurants: [Restaurant]) {
        do {
            let data = try JSONEncoder().encode(restaurants)
            UserDefaults.standard.set(data, forKey: restaurantsCacheKey)
            print("✅ Cached \(restaurants.count) restaurants")
        } catch {
            print("❌ Failed to cache restaurants: \(error)")
            self.error = .cacheFailed(error.localizedDescription)
        }
    }
    
    private func loadCachedRestaurants() {
        guard let data = UserDefaults.standard.data(forKey: restaurantsCacheKey) else {
            print("No cached restaurants found")
            return
        }
        
        do {
            let cachedRestaurants = try JSONDecoder().decode([Restaurant].self, from: data)
            self.restaurants = cachedRestaurants
            print("✅ Loaded \(cachedRestaurants.count) restaurants from cache")
        } catch {
            print("❌ Failed to load cached restaurants: \(error)")
        }
    }
    
    private func updateLastFetchTime() {
        UserDefaults.standard.set(Date(), forKey: lastFetchKey)
    }
    
    private func isCacheFresh() -> Bool {
        guard let lastFetch = UserDefaults.standard.object(forKey: lastFetchKey) as? Date else {
            return false
        }
        
        let timeSinceLastFetch = Date().timeIntervalSince(lastFetch)
        return timeSinceLastFetch < cacheExpirationInterval
    }
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: restaurantsCacheKey)
        UserDefaults.standard.removeObject(forKey: lastFetchKey)
        print("✅ Cache cleared")
    }
    
    // MARK: - Utilities
    private func calculateDistance(from coordinate: CLLocationCoordinate2D, to restaurant: Restaurant) -> Double {
        let location1 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let location2 = CLLocation(latitude: restaurant.latitude, longitude: restaurant.longitude)
        return location1.distance(from: location2)
    }
    
    // Don't need deinit - listener will be removed when object is deallocated
    // Removed to avoid main actor isolation issues
}

// MARK: - Cache Manager
class CacheManager {
    func clearAll() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}
