import Foundation
import CoreLocation

/// Service for fetching restaurant data from Google Places API
/// Retrieves reviews, photos, and detailed information
class GooglePlacesService {
    private let apiKey: String
    private let baseURL = "https://maps.googleapis.com/maps/api"
    
    enum PlacesError: LocalizedError {
        case invalidURL
        case noData
        case decodingError
        case apiError(String)
        case noAPIKey
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .noData:
                return "No data received from API"
            case .decodingError:
                return "Failed to decode API response"
            case .apiError(let message):
                return "API Error: \(message)"
            case .noAPIKey:
                return "Google Places API key not configured"
            }
        }
    }
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Find Place by Name & Location
    
    /// Search for a place to get its Place ID
    func findPlace(name: String, location: CLLocationCoordinate2D) async throws -> String? {
        let endpoint = "\(baseURL)/place/findplacefromtext/json"
        
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "input", value: name),
            URLQueryItem(name: "inputtype", value: "textquery"),
            URLQueryItem(name: "locationbias", value: "point:\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "fields", value: "place_id"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        guard let url = components?.url else {
            throw PlacesError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(FindPlaceResponse.self, from: data)
        
        if response.status != "OK" {
            throw PlacesError.apiError(response.status)
        }
        
        return response.candidates.first?.placeId
    }
    
    // MARK: - Get Place Details
    
    /// Get detailed information including reviews and photos
    func getPlaceDetails(placeId: String) async throws -> PlaceDetails {
        let endpoint = "\(baseURL)/place/details/json"
        
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "place_id", value: placeId),
            URLQueryItem(name: "fields", value: "name,rating,user_ratings_total,reviews,photos,formatted_address,formatted_phone_number,opening_hours,website,price_level,geometry"),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "language", value: "en") // Change to "ko" for Korean reviews
        ]
        
        guard let url = components?.url else {
            throw PlacesError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(PlaceDetailsResponse.self, from: data)
        
        if response.status != "OK" {
            throw PlacesError.apiError(response.status)
        }
        
        guard let result = response.result else {
            throw PlacesError.noData
        }
        
        return result
    }
    
    // MARK: - Get Photo URL
    
    /// Generate photo URL from photo reference
    func getPhotoURL(photoReference: String, maxWidth: Int = 800) -> URL? {
        var components = URLComponents(string: "\(baseURL)/place/photo")
        components?.queryItems = [
            URLQueryItem(name: "photo_reference", value: photoReference),
            URLQueryItem(name: "maxwidth", value: String(maxWidth)),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        return components?.url
    }
    
    // MARK: - Fetch All Restaurant Data
    
    /// Complete method to fetch reviews and photos for a restaurant
    func fetchRestaurantData(name: String, location: CLLocationCoordinate2D) async throws -> RestaurantGoogleData {
        // First, find the place ID
        guard let placeId = try await findPlace(name: name, location: location) else {
            throw PlacesError.noData
        }
        
        // Then get detailed information
        let details = try await getPlaceDetails(placeId: placeId)
        
        // Convert photos to URLs
        let photoURLs = details.photos?.compactMap { photo in
            getPhotoURL(photoReference: photo.photoReference)
        } ?? []
        
        return RestaurantGoogleData(
            placeId: placeId,
            rating: details.rating,
            userRatingsTotal: details.userRatingsTotal,
            reviews: details.reviews ?? [],
            photoURLs: photoURLs,
            phoneNumber: details.formattedPhoneNumber,
            website: details.website,
            openingHours: details.openingHours?.weekdayText,
            priceLevel: details.priceLevel
        )
    }
    
    // MARK: - Search by Name and Create Restaurant

    /// Search Google Places by name, fetch all details, and return a Restaurant ready for Firebase
    func searchAndCreateRestaurant(query: String, cuisine: String, description: String) async throws -> Restaurant {
        // Step 1: Text search to get place_id
        let endpoint = "\(baseURL)/place/textsearch/json"
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "type", value: "restaurant"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else { throw PlacesError.invalidURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TextSearchResponse.self, from: data)

        guard response.status == "OK", let first = response.results.first else {
            throw PlacesError.apiError(response.status == "OK" ? "No results found" : response.status)
        }

        // Step 2: Get full details
        let details = try await getPlaceDetails(placeId: first.placeId)

        // Step 3: Build photo URL from first available photo
        let photoURLString = details.photos?.first.flatMap {
            getPhotoURL(photoReference: $0.photoReference)
        }?.absoluteString

        // Step 4: Format hours as a single string
        let hoursString = details.openingHours?.weekdayText?.joined(separator: ", ") ?? ""

        let finalDescription = description.isEmpty
            ? "\(details.name) — \(details.formattedAddress ?? "")"
            : description

        return Restaurant(
            name: details.name,
            cuisine: cuisine.isEmpty ? "Restaurant" : cuisine,
            rating: details.rating ?? 0.0,
            address: details.formattedAddress ?? "",
            description: finalDescription,
            imageName: "placeholder",
            imageURL: photoURLString,
            latitude: details.geometry?.location.lat ?? 0,
            longitude: details.geometry?.location.lng ?? 0,
            priceRange: details.priceLevel,
            phoneNumber: details.formattedPhoneNumber,
            hours: hoursString
        )
    }

    // MARK: - Search for Multiple Results

    /// Returns up to 5 candidate results for the given query without fetching full details
    func searchRestaurants(query: String) async throws -> [TextSearchResult] {
        let endpoint = "\(baseURL)/place/textsearch/json"
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "type", value: "restaurant"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components?.url else { throw PlacesError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TextSearchResponse.self, from: data)
        guard response.status == "OK" else {
            throw PlacesError.apiError(response.status)
        }
        return Array(response.results.prefix(5))
    }

    /// Fetch full details for a single search result and return a Restaurant ready for Firebase
    func createRestaurant(from result: TextSearchResult, cuisine: String) async throws -> Restaurant {
        let details = try await getPlaceDetails(placeId: result.placeId)
        let photoURLString = details.photos?.first.flatMap {
            getPhotoURL(photoReference: $0.photoReference)
        }?.absoluteString
        let hoursString = details.openingHours?.weekdayText?.joined(separator: ", ") ?? ""
        return Restaurant(
            name: details.name,
            cuisine: cuisine.isEmpty ? "Restaurant" : cuisine,
            rating: details.rating ?? 0.0,
            address: details.formattedAddress ?? "",
            description: "\(details.name) — \(details.formattedAddress ?? "")",
            imageName: "placeholder",
            imageURL: photoURLString,
            latitude: details.geometry?.location.lat ?? 0,
            longitude: details.geometry?.location.lng ?? 0,
            priceRange: details.priceLevel,
            phoneNumber: details.formattedPhoneNumber,
            hours: hoursString
        )
    }

    // MARK: - Batch Fetch for Multiple Restaurants
    
    /// Fetch data for multiple restaurants (with rate limiting)
    func batchFetchRestaurantData(_ restaurants: [Restaurant]) async -> [String: RestaurantGoogleData] {
        var results: [String: RestaurantGoogleData] = [:]
        
        for restaurant in restaurants {
            do {
                let location = CLLocationCoordinate2D(
                    latitude: restaurant.latitude,
                    longitude: restaurant.longitude
                )
                
                let data = try await fetchRestaurantData(
                    name: restaurant.name,
                    location: location
                )
                
                if let id = restaurant.id {
                    results[id] = data
                }
                
                print("✅ Fetched data for: \(restaurant.name)")
                
                // Rate limiting - Google allows ~100 requests per second
                // Be conservative to avoid hitting limits
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                
            } catch {
                print("❌ Failed to fetch data for \(restaurant.name): \(error.localizedDescription)")
            }
        }
        
        return results
    }
}

// MARK: - Data Models

struct RestaurantGoogleData: Codable {
    let placeId: String
    let rating: Double?
    let userRatingsTotal: Int?
    let reviews: [GoogleReview]
    let photoURLs: [URL]
    let phoneNumber: String?
    let website: String?
    let openingHours: [String]?
    let priceLevel: Int?
    
    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case rating
        case userRatingsTotal = "user_ratings_total"
        case reviews
        case photoURLs = "photo_urls"
        case phoneNumber = "phone_number"
        case website
        case openingHours = "opening_hours"
        case priceLevel = "price_level"
    }
}

struct GoogleReview: Codable, Identifiable {
    let id: String
    let authorName: String
    let authorPhotoURL: String?
    let rating: Int
    let relativeTimeDescription: String
    let text: String
    let time: Int
    
    enum CodingKeys: String, CodingKey {
        case authorName = "author_name"
        case authorPhotoURL = "profile_photo_url"
        case rating
        case relativeTimeDescription = "relative_time_description"
        case text
        case time
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.authorName = try container.decode(String.self, forKey: .authorName)
        self.authorPhotoURL = try? container.decode(String.self, forKey: .authorPhotoURL)
        self.rating = try container.decode(Int.self, forKey: .rating)
        self.relativeTimeDescription = try container.decode(String.self, forKey: .relativeTimeDescription)
        self.text = try container.decode(String.self, forKey: .text)
        self.time = try container.decode(Int.self, forKey: .time)
        
        // Use time as ID, or combine with author name
        self.id = "\(time)_\(authorName)"
    }
}

// MARK: - API Response Models

struct FindPlaceResponse: Codable {
    let candidates: [PlaceCandidate]
    let status: String
}

struct PlaceCandidate: Codable {
    let placeId: String
    
    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
    }
}

struct PlaceDetailsResponse: Codable {
    let result: PlaceDetails?
    let status: String
}

struct PlaceDetails: Codable {
    let name: String
    let rating: Double?
    let userRatingsTotal: Int?
    let reviews: [GoogleReview]?
    let photos: [PlacePhoto]?
    let formattedAddress: String?
    let formattedPhoneNumber: String?
    let openingHours: OpeningHours?
    let website: String?
    let priceLevel: Int?
    let geometry: Geometry?
    
    enum CodingKeys: String, CodingKey {
        case name
        case rating
        case userRatingsTotal = "user_ratings_total"
        case reviews
        case photos
        case formattedAddress = "formatted_address"
        case formattedPhoneNumber = "formatted_phone_number"
        case openingHours = "opening_hours"
        case website
        case priceLevel = "price_level"
        case geometry
    }
}

struct PlacePhoto: Codable {
    let photoReference: String
    let height: Int
    let width: Int
    
    enum CodingKeys: String, CodingKey {
        case photoReference = "photo_reference"
        case height
        case width
    }
}

struct OpeningHours: Codable {
    let openNow: Bool?
    let weekdayText: [String]?
    
    enum CodingKeys: String, CodingKey {
        case openNow = "open_now"
        case weekdayText = "weekday_text"
    }
}

struct Geometry: Codable {
    let location: LocationCoordinate
}

struct LocationCoordinate: Codable {
    let lat: Double
    let lng: Double
}

// MARK: - Text Search Models

struct TextSearchResponse: Codable {
    let results: [TextSearchResult]
    let status: String
}

struct TextSearchResult: Codable, Identifiable {
    var id: String { placeId }
    let placeId: String
    let name: String
    let formattedAddress: String?
    let geometry: Geometry?
    let rating: Double?

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name
        case formattedAddress = "formatted_address"
        case geometry
        case rating
    }
}
