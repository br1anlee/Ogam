import Foundation

struct Restaurant: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let cuisine: String
    let rating: Double
    let address: String
    let description: String
    let imageName: String
}
