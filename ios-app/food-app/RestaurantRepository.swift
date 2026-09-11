import Foundation
import FirebaseFirestore
import CoreLocation

@MainActor
class RestaurantRepository: ObservableObject {
    @Published var restaurants: [Restaurant] = []
    @Published var isLoading = false
    @Published var error: RepositoryError?
    
    let db = Firestore.firestore()  // Changed from private to internal
    private var listener: ListenerRegistration?
    private let cacheManager = CacheManager()
    private var isGeocoding = false
    var fetchingRatingIDs: Set<String> = []

    @Published var hasMore = true
    @Published var isLoadingMore = false
    @Published var googleRatings: [String: Double] = [:]
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 200
    
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
    
    // MARK: - Paginated Loading
    func startListening() {
        guard !isLoading else { return }
        isLoading = true
        lastDocument = nil
        hasMore = true
        Task {
            await loadPage(appending: false)
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        await loadPage(appending: true)
        isLoadingMore = false
    }

    private func loadPage(appending: Bool) async {
        var query: Query = db.collection("restaurants")
            .order(by: FieldPath.documentID())
            .limit(to: pageSize)

        if appending, let last = lastDocument {
            query = query.start(afterDocument: last)
        }

        do {
            let snapshot = try await query.getDocuments()
            let docs = snapshot.documents
            lastDocument = docs.last
            hasMore = docs.count == pageSize

            let loaded = docs.compactMap { doc -> Restaurant? in
                do { return try doc.data(as: Restaurant.self) }
                catch { print("Decode error: \(error)"); return nil }
            }

            if appending {
                self.restaurants.append(contentsOf: loaded)
            } else {
                self.restaurants = loaded
                isLoading = false
            }

            cacheRestaurants(self.restaurants)
            geocodeUngeocodedRestaurants()
            print("✅ Loaded \(loaded.count) restaurants (total: \(self.restaurants.count), hasMore: \(hasMore))")
        } catch {
            print("❌ Load failed: \(error.localizedDescription)")
            self.error = .fetchFailed(error.localizedDescription)
            if !appending { isLoading = false }
        }
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
        restaurantData.id = nil
        restaurantData.searchTokens = Restaurant.makeSearchTokens(name: restaurant.name, cuisine: restaurant.cuisine)

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

    // Plain Codable mirror of Restaurant — avoids @DocumentID's Firestore-only encoding restriction
    private struct CachedRestaurant: Codable {
        let id: String?
        let name: String
        let cuisine: String
        let rating: Double
        let address: String
        let description: String
        let imageName: String
        let imageURL: String?
        let latitude: Double
        let longitude: Double
        let city: String?
        let neighborhood: String?
        let priceRange: Int?
        let phoneNumber: String?
        let tags: [String]?
        let isOpenNow: Bool?
        let hours: String?
        let searchTokens: [String]?

        init(_ r: Restaurant) {
            id = r.id; name = r.name; cuisine = r.cuisine; rating = r.rating
            address = r.address; description = r.description; imageName = r.imageName
            imageURL = r.imageURL; latitude = r.latitude; longitude = r.longitude
            city = r.city; neighborhood = r.neighborhood; priceRange = r.priceRange
            phoneNumber = r.phoneNumber; tags = r.tags; isOpenNow = r.isOpenNow
            hours = r.hours; searchTokens = r.searchTokens
        }

        func toRestaurant() -> Restaurant {
            Restaurant(
                id: id, name: name, cuisine: cuisine, rating: rating,
                address: address, description: description, imageName: imageName,
                imageURL: imageURL, latitude: latitude, longitude: longitude,
                city: city, neighborhood: neighborhood, priceRange: priceRange,
                phoneNumber: phoneNumber, tags: tags, isOpenNow: isOpenNow,
                hours: hours, searchTokens: searchTokens
            )
        }
    }

    private func cacheRestaurants(_ restaurants: [Restaurant]) {
        do {
            let cacheable = restaurants.map { CachedRestaurant($0) }
            let data = try JSONEncoder().encode(cacheable)
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
            let cached = try JSONDecoder().decode([CachedRestaurant].self, from: data)
            self.restaurants = cached.map { $0.toRestaurant() }
            print("✅ Loaded \(self.restaurants.count) restaurants from cache")
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
    
    // MARK: - Background Geocoding

    /// Geocodes up to 30 restaurants per session that are missing coordinates.
    /// Uses neighborhood/station names with CLGeocoder (free, no API key needed).
    /// Coordinates are saved back to Firestore so they persist for all users.
    func geocodeUngeocodedRestaurants() {
        guard !isGeocoding else { return }
        let ungeocoded = restaurants.filter {
            $0.latitude == 0 && $0.longitude == 0 && $0.id != nil
        }
        guard !ungeocoded.isEmpty else { return }

        isGeocoding = true
        let batch = Array(ungeocoded.prefix(25))
        print("📍 Geocoding \(batch.count) of \(ungeocoded.count) restaurants without coordinates...")

        Task {
            defer { isGeocoding = false }
            let geocoder = CLGeocoder()
            for restaurant in batch {
                guard let id = restaurant.id else { continue }

                let locationHint: String
                if let tags = restaurant.tags,
                   let station = tags.first(where: { $0.hasSuffix("역") }) {
                    locationHint = station
                } else {
                    locationHint = restaurant.neighborhood ?? restaurant.name
                }
                let query = "\(locationHint), Seoul, South Korea"

                do {
                    let placemarks = try await geocoder.geocodeAddressString(query)
                    if let coord = placemarks.first?.location?.coordinate {
                        try await db.collection("restaurants").document(id).updateData([
                            "latitude": coord.latitude,
                            "longitude": coord.longitude
                        ])
                        print("📍 Geocoded \(restaurant.name)")
                    }
                } catch {
                    // Skip on rate-limit or not-found and continue
                }

                // Stay well under Apple's 50 requests/60s limit
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            print("📍 Geocoding batch complete.")
        }
    }

    // MARK: - Name Search
    func searchByName(_ query: String) async -> [Restaurant] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let qLower = q.lowercased()

        // Run token search (array-contains on search_tokens) and name prefix search in parallel.
        // Token search handles names where the query word appears in the middle (e.g. "JJAN" in "짠 JJAN...").
        // Prefix search handles older documents that predate the search_tokens field.
        async let tokenSnapshot = db.collection("restaurants")
            .whereField("search_tokens", arrayContains: qLower)
            .limit(to: 25)
            .getDocuments()

        async let prefixSnapshot = db.collection("restaurants")
            .whereField("name", isGreaterThanOrEqualTo: q)
            .whereField("name", isLessThanOrEqualTo: q + "\u{f8ff}")
            .limit(to: 25)
            .getDocuments()

        var seen = Set<String>()
        var results: [Restaurant] = []

        for snapshot in [try? await tokenSnapshot, try? await prefixSnapshot] {
            let batch = snapshot?.documents.compactMap { try? $0.data(as: Restaurant.self) } ?? []
            for r in batch {
                let key = r.id ?? r.name
                if !seen.contains(key) {
                    seen.insert(key)
                    results.append(r)
                }
            }
        }

        return results
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
