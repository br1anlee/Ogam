import Foundation
import FirebaseFirestore

struct Restaurant: Identifiable, Hashable, Codable {
    @DocumentID var id: String?
    let name: String
    let cuisine: String
    let rating: Double
    let address: String
    let description: String
    let imageName: String  // Keep for local images during migration
    let imageURL: String?  // New: Firebase Storage URL
    let latitude: Double
    let longitude: Double
    
    // New fields for Korean restaurants
    let city: String?
    let neighborhood: String?
    let priceRange: Int?  // 1-4 (₩ to ₩₩₩₩)
    let phoneNumber: String?
    let tags: [String]?
    let isOpenNow: Bool?
    let hours: String?
    
    // Firestore metadata
    let createdAt: Date?
    let updatedAt: Date?

    // Lowercase word tokens from name + cuisine, used for array-contains search
    var searchTokens: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cuisine
        case rating
        case address
        case description
        case imageName = "image_name"
        case imageURL = "image_url"
        case latitude
        case longitude
        case city
        case neighborhood
        case priceRange = "price_range"
        case phoneNumber = "phone_number"
        case tags
        case isOpenNow = "is_open_now"
        case hours
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case searchTokens = "search_tokens"
    }

    // Convenience initializer for backward compatibility
    init(
        id: String? = nil,
        name: String,
        cuisine: String,
        rating: Double,
        address: String,
        description: String,
        imageName: String,
        imageURL: String? = nil,
        latitude: Double,
        longitude: Double,
        city: String? = nil,
        neighborhood: String? = nil,
        priceRange: Int? = nil,
        phoneNumber: String? = nil,
        tags: [String]? = nil,
        isOpenNow: Bool? = nil,
        hours: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        searchTokens: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.cuisine = cuisine
        self.rating = rating
        self.address = address
        self.description = description
        self.imageName = imageName
        self.imageURL = imageURL
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
        self.neighborhood = neighborhood
        self.priceRange = priceRange
        self.phoneNumber = phoneNumber
        self.tags = tags
        self.isOpenNow = isOpenNow
        self.hours = hours
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.searchTokens = searchTokens
    }

    /// Generates lowercase word tokens for Firestore array-contains search.
    /// e.g. "짠 JJAN Korean Gastropub" + "Korean" → ["짠", "jjan", "korean", "gastropub"]
    static func makeSearchTokens(name: String, cuisine: String) -> [String] {
        let combined = "\(name) \(cuisine)"
        let words = combined.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        return Array(Set(words))
    }
    
    // Computed property for image display
    var displayImageURL: String {
        imageURL ?? imageName
    }
}
