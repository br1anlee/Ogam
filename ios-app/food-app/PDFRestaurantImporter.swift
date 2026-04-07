import Foundation
import CoreLocation
import FirebaseFirestore

/// Specialized importer for PDF restaurant data with train stations
/// Automatically gets addresses and coordinates from Google Places
class PDFRestaurantImporter {
    private let db = Firestore.firestore()
    private let placesService: GooglePlacesService
    
    init(placesService: GooglePlacesService) {
        self.placesService = placesService
    }
    
    // MARK: - Simple Restaurant Data (from PDF)
    
    struct PDFRestaurant: Codable {
        let name: String
        let cuisine: String
        let station: String
        let city: String
        let description: String?
        
        /// Search query for Google Places
        var searchQuery: String {
            "\(name) near \(station), \(city)"
        }
    }
    
    // MARK: - Import from CSV
    
    /// Import restaurants from CSV file with columns: name, cuisine, station, city
    func importFromCSV(fileName: String) async throws {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "csv") else {
            throw ImportError.fileNotFound
        }
        
        let csvString = try String(contentsOf: url, encoding: .utf8)
        let lines = csvString.components(separatedBy: .newlines)
        
        // Skip header row
        let dataLines = lines.dropFirst().filter { !$0.isEmpty }
        
        var imported = 0
        var failed = 0
        
        for (index, line) in dataLines.enumerated() {
            let columns = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            guard columns.count >= 4 else {
                print("⚠️  Skipping line \(index + 2): Invalid format")
                failed += 1
                continue
            }
            
            let pdfRestaurant = PDFRestaurant(
                name: columns[0],
                cuisine: columns[1],
                station: columns[2],
                city: columns[3],
                description: columns.count > 4 ? columns[4] : nil
            )
            
            do {
                try await importSingleRestaurant(pdfRestaurant)
                imported += 1
                print("✅ [\(imported)/\(dataLines.count)] Imported: \(pdfRestaurant.name)")
            } catch {
                failed += 1
                print("❌ [\(imported + failed)/\(dataLines.count)] Failed: \(pdfRestaurant.name) - \(error)")
            }
            
            // Rate limiting
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        
        print("\n📊 Import Summary:")
        print("   ✅ Imported: \(imported)")
        print("   ❌ Failed: \(failed)")
        print("   📈 Success rate: \(Int(Double(imported) / Double(imported + failed) * 100))%")
    }
    
    // MARK: - Import Single Restaurant
    
    func importSingleRestaurant(_ pdfRestaurant: PDFRestaurant) async throws {
        print("🔍 Searching Google for: \(pdfRestaurant.searchQuery)")
        
        // Search Google Places using restaurant name + station
        guard let placeId = try await placesService.findPlace(
            name: pdfRestaurant.searchQuery,
            location: getStationCoordinate(pdfRestaurant.station, city: pdfRestaurant.city)
        ) else {
            throw ImportError.notFoundOnGoogle
        }
        
        print("   Found Place ID: \(placeId)")
        
        // Get detailed information
        let placeDetails = try await placesService.getPlaceDetails(placeId: placeId)
        
        // Create restaurant with Google data
        let restaurant = Restaurant(
            name: pdfRestaurant.name,
            cuisine: pdfRestaurant.cuisine,
            rating: placeDetails.rating ?? 4.0,
            address: placeDetails.formattedAddress ?? "\(pdfRestaurant.station), \(pdfRestaurant.city)",
            description: pdfRestaurant.description ?? placeDetails.name,
            imageName: "placeholder",
            imageURL: placeDetails.photos?.first.map { photo in
                placesService.getPhotoURL(photoReference: photo.photoReference)?.absoluteString
            } ?? nil,
            latitude: placeDetails.geometry?.location.lat ?? 37.5665,
            longitude: placeDetails.geometry?.location.lng ?? 126.9780,
            city: pdfRestaurant.city,
            neighborhood: extractNeighborhood(from: pdfRestaurant.station),
            priceRange: placeDetails.priceLevel,
            phoneNumber: placeDetails.formattedPhoneNumber,
            tags: generateTags(cuisine: pdfRestaurant.cuisine, station: pdfRestaurant.station),
            isOpenNow: placeDetails.openingHours?.openNow,
            hours: placeDetails.openingHours?.weekdayText?.joined(separator: ", ")
        )
        
        // Add to Firestore
        var restaurantData = restaurant
        restaurantData.id = nil // Let Firestore generate ID
        
        let docRef = try db.collection("restaurants").addDocument(from: restaurantData)
        print("   💾 Saved to Firestore with ID: \(docRef.documentID)")
        
        // Save Google data
        let googleData = RestaurantGoogleData(
            placeId: placeId,
            rating: placeDetails.rating,
            userRatingsTotal: placeDetails.userRatingsTotal,
            reviews: placeDetails.reviews ?? [],
            photoURLs: placeDetails.photos?.compactMap { photo in
                placesService.getPhotoURL(photoReference: photo.photoReference)
            } ?? [],
            phoneNumber: placeDetails.formattedPhoneNumber,
            website: placeDetails.website,
            openingHours: placeDetails.openingHours?.weekdayText,
            priceLevel: placeDetails.priceLevel
        )
        
        try await saveGoogleData(googleData, restaurantId: docRef.documentID)
        print("   🌟 Saved Google reviews & photos")
    }
    
    // MARK: - Batch Import from Array
    
    /// Import multiple restaurants programmatically
    func importBatch(_ restaurants: [PDFRestaurant]) async {
        print("📦 Starting batch import of \(restaurants.count) restaurants...")
        
        var imported = 0
        var failed = 0
        
        for restaurant in restaurants {
            do {
                try await importSingleRestaurant(restaurant)
                imported += 1
            } catch {
                failed += 1
                print("❌ Failed: \(restaurant.name) - \(error)")
            }
            
            // Rate limiting
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        print("\n✅ Batch import complete!")
        print("   Imported: \(imported)")
        print("   Failed: \(failed)")
    }
    
    // MARK: - Helper Functions
    
    private func getStationCoordinate(_ station: String, city: String) -> CLLocationCoordinate2D {
        // Seoul stations
        let seoulStations: [String: CLLocationCoordinate2D] = [
            "myeongdong station": CLLocationCoordinate2D(latitude: 37.5605, longitude: 126.9860),
            "gangnam station": CLLocationCoordinate2D(latitude: 37.4980, longitude: 127.0276),
            "hongik university station": CLLocationCoordinate2D(latitude: 37.5572, longitude: 126.9241),
            "hongdae station": CLLocationCoordinate2D(latitude: 37.5572, longitude: 126.9241),
            "itaewon station": CLLocationCoordinate2D(latitude: 37.5346, longitude: 126.9946),
            "jongno 5-ga station": CLLocationCoordinate2D(latitude: 37.5703, longitude: 126.9925),
            "dongdaemun station": CLLocationCoordinate2D(latitude: 37.5711, longitude: 127.0098),
            "apgujeong station": CLLocationCoordinate2D(latitude: 37.5273, longitude: 127.0276),
            "sinchon station": CLLocationCoordinate2D(latitude: 37.5556, longitude: 126.9364),
            "yeouido station": CLLocationCoordinate2D(latitude: 37.5219, longitude: 126.9245),
            "seoul station": CLLocationCoordinate2D(latitude: 37.5547, longitude: 126.9707),
            "gwanghwamun station": CLLocationCoordinate2D(latitude: 37.5713, longitude: 126.9760)
        ]
        
        let normalized = station.lowercased()
        
        if let coordinate = seoulStations[normalized] {
            return coordinate
        }
        
        // Default to city center if station not found
        if city.lowercased().contains("seoul") {
            return CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        } else if city.lowercased().contains("busan") {
            return CLLocationCoordinate2D(latitude: 35.1796, longitude: 129.0756)
        }
        
        return CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780) // Default Seoul
    }
    
    private func extractNeighborhood(from station: String) -> String? {
        let cleaned = station.replacingOccurrences(of: " Station", with: "")
            .replacingOccurrences(of: " station", with: "")
        return cleaned
    }
    
    private func generateTags(cuisine: String, station: String) -> [String] {
        var tags: [String] = []
        
        // Add cuisine-based tags
        if cuisine.lowercased().contains("bbq") {
            tags.append(contentsOf: ["BBQ", "Grilled"])
        }
        if cuisine.lowercased().contains("street") {
            tags.append(contentsOf: ["Street Food", "Casual"])
        }
        if cuisine.lowercased().contains("soup") {
            tags.append("Soup")
        }
        
        // Add neighborhood
        if let neighborhood = extractNeighborhood(from: station) {
            tags.append(neighborhood)
        }
        
        return tags
    }
    
    private func saveGoogleData(_ data: RestaurantGoogleData, restaurantId: String) async throws {
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
    }
    
    enum ImportError: LocalizedError {
        case fileNotFound
        case invalidFormat
        case notFoundOnGoogle
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "CSV file not found in bundle"
            case .invalidFormat:
                return "Invalid CSV format"
            case .notFoundOnGoogle:
                return "Restaurant not found on Google Places"
            }
        }
    }
}
