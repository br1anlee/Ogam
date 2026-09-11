import Foundation
import FirebaseFirestore
import CoreLocation

/// Extended repository for managing Google Places data
extension RestaurantRepository {
    
    // MARK: - Fetch and Cache Google Data
    
    /// Fetch Google data for a single restaurant and cache it
    func fetchGoogleData(for restaurant: Restaurant, placesService: GooglePlacesService) async throws -> RestaurantGoogleData? {
        guard let restaurantId = restaurant.id else { return nil }
        
        // Check cache first
        if let cached = loadCachedGoogleData(for: restaurantId) {
            print("Using cached Google data for: \(restaurant.name)")
            return cached
        }
        
        // Fetch from API
        let location = CLLocationCoordinate2D(
            latitude: restaurant.latitude,
            longitude: restaurant.longitude
        )
        
        let googleData = try await placesService.fetchRestaurantData(
            name: restaurant.name,
            location: location
        )
        
        // Cache the data
        cacheGoogleData(googleData, for: restaurantId)
        
        // Optionally save to Firestore for persistence
        try await saveGoogleDataToFirestore(googleData, restaurantId: restaurantId)
        
        return googleData
    }
    
    /// Batch fetch Google data for all restaurants
    func fetchAllGoogleData(placesService: GooglePlacesService) async {
        print("📡 Starting batch fetch of Google data...")
        
        for restaurant in restaurants {
            do {
                _ = try await fetchGoogleData(for: restaurant, placesService: placesService)
                print("✅ Fetched Google data for: \(restaurant.name)")
            } catch {
                print("❌ Failed to fetch Google data for \(restaurant.name): \(error)")
            }
            
            // Rate limiting
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        
        print("✅ Batch fetch complete!")
    }
    
    // MARK: - Firestore Integration
    
    private func saveGoogleDataToFirestore(_ data: RestaurantGoogleData, restaurantId: String) async throws {
        let dataDict: [String: Any] = [
            "google_place_id": data.placeId,
            "google_rating": data.rating ?? 0,
            "google_ratings_total": data.userRatingsTotal ?? 0,
            "google_reviews": data.reviews.map { review in
                [
                    "author_name": review.authorName,
                    "rating": review.rating,
                    "text": review.text,
                    "time": review.time,
                    "relative_time": review.relativeTimeDescription
                ] as [String: Any]
            },
            "google_photo_urls": data.photoURLs.map { $0.absoluteString },
            "google_phone": data.phoneNumber ?? "",
            "google_website": data.website ?? "",
            "google_hours": data.openingHours ?? [],
            "google_price_level": data.priceLevel ?? 0,
            "google_data_updated": Date()
        ]
        
        try await db.collection("restaurants")
            .document(restaurantId)
            .setData(dataDict, merge: true)
        
        print("💾 Saved Google data to Firestore for restaurant: \(restaurantId)")
    }
    
    func loadGoogleDataFromFirestore(restaurantId: String) async throws -> RestaurantGoogleData? {
        let document = try await db.collection("restaurants")
            .document(restaurantId)
            .getDocument()
        
        guard let data = document.data(),
              let placeId = data["google_place_id"] as? String else {
            return nil
        }
        
        let reviews = (data["google_reviews"] as? [[String: Any]] ?? []).compactMap { reviewDict -> GoogleReview? in
            guard let authorName = reviewDict["author_name"] as? String,
                  let rating = reviewDict["rating"] as? Int,
                  let text = reviewDict["text"] as? String,
                  let time = reviewDict["time"] as? Int,
                  let relativeTime = reviewDict["relative_time"] as? String else {
                return nil
            }
            
            // Create GoogleReview using JSONSerialization to handle mixed types
            let reviewJSON: [String: Any] = [
                "author_name": authorName,
                "rating": rating,
                "text": text,
                "time": time,
                "relative_time_description": relativeTime
            ]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: reviewJSON) else {
                return nil
            }
            return try? JSONDecoder().decode(GoogleReview.self, from: jsonData)
        }
        
        let photoURLs = (data["google_photo_urls"] as? [String] ?? []).compactMap { URL(string: $0) }
        
        return RestaurantGoogleData(
            placeId: placeId,
            rating: data["google_rating"] as? Double,
            userRatingsTotal: data["google_ratings_total"] as? Int,
            reviews: reviews,
            photoURLs: photoURLs,
            phoneNumber: data["google_phone"] as? String,
            website: data["google_website"] as? String,
            openingHours: data["google_hours"] as? [String],
            priceLevel: data["google_price_level"] as? Int
        )
    }
    
    // MARK: - Local Caching
    
    private func cacheGoogleData(_ data: RestaurantGoogleData, for restaurantId: String) {
        do {
            let encoded = try JSONEncoder().encode(data)
            UserDefaults.standard.set(encoded, forKey: "google_data_\(restaurantId)")
        } catch {
            print("❌ Failed to cache Google data: \(error)")
        }
    }
    
    func loadCachedGoogleData(for restaurantId: String) -> RestaurantGoogleData? {
        guard let data = UserDefaults.standard.data(forKey: "google_data_\(restaurantId)") else {
            return nil
        }
        
        return try? JSONDecoder().decode(RestaurantGoogleData.self, from: data)
    }
    
    func prefetchRating(for restaurant: Restaurant, placesService: GooglePlacesService) {
        guard let id = restaurant.id,
              googleRatings[id] == nil,
              !fetchingRatingIDs.contains(id) else { return }

        // Serve from UserDefaults cache instantly — no API call
        if let cached = loadCachedGoogleData(for: id) {
            if let rating = cached.rating {
                googleRatings[id] = rating
            }
            return
        }

        // Not cached — fetch from Google Places API
        fetchingRatingIDs.insert(id)
        Task {
            do {
                let data = try await fetchGoogleData(for: restaurant, placesService: placesService)
                if let rating = data?.rating {
                    googleRatings[id] = rating
                }
            } catch { }
            fetchingRatingIDs.remove(id)
        }
    }

    func clearGoogleDataCache() {
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        
        dictionary.keys.forEach { key in
            if key.hasPrefix("google_data_") {
                defaults.removeObject(forKey: key)
            }
        }
        
        print("🗑️ Cleared all Google data cache")
    }
}
