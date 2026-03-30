import Foundation

struct Restaurant: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let cuisine: String
    let rating: Double
    let address: String
    let description: String
    let imageName: String
    let latitude: Double
    let longitude: Double
}
