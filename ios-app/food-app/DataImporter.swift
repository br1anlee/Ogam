import Foundation
import FirebaseFirestore
import FirebaseStorage

/// This script helps you import restaurant data from JSON to Firebase
/// Use this for bulk importing your 100+ Korean restaurants
class DataImporter {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    // MARK: - Import from JSON
    
    /// Import restaurants from a JSON file
    func importRestaurantsFromJSON(fileName: String) async throws {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            throw ImportError.fileNotFound
        }
        
        let data = try Data(contentsOf: url)
        let restaurants = try JSONDecoder().decode([Restaurant].self, from: data)
        
        print("📦 Found \(restaurants.count) restaurants in JSON file")
        
        for (index, restaurant) in restaurants.enumerated() {
            do {
                try await addRestaurant(restaurant)
                print("✅ [\(index + 1)/\(restaurants.count)] Added: \(restaurant.name)")
            } catch {
                print("❌ [\(index + 1)/\(restaurants.count)] Failed to add \(restaurant.name): \(error)")
            }
        }
        
        print("🎉 Import complete!")
    }
    
    /// Import restaurants from an array (for manual data entry)
    func importRestaurants(_ restaurants: [Restaurant]) async throws {
        print("📦 Importing \(restaurants.count) restaurants")
        
        for (index, restaurant) in restaurants.enumerated() {
            do {
                try await addRestaurant(restaurant)
                print("✅ [\(index + 1)/\(restaurants.count)] Added: \(restaurant.name)")
            } catch {
                print("❌ [\(index + 1)/\(restaurants.count)] Failed to add \(restaurant.name): \(error)")
            }
        }
        
        print("🎉 Import complete!")
    }
    
    // MARK: - Single Restaurant Import
    
    private func addRestaurant(_ restaurant: Restaurant) async throws {
        var restaurantData = restaurant
        restaurantData.id = nil // Let Firestore generate ID
        
        let docRef = try db.collection("restaurants").addDocument(from: restaurantData)
        print("   Added with ID: \(docRef.documentID)")
    }
    
    // MARK: - Image Upload
    
    /// Upload an image to Firebase Storage and return the download URL
    func uploadImage(localImageName: String, restaurantID: String) async throws -> String {
        guard let image = UIImage(named: localImageName) else {
            throw ImportError.imageNotFound
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw ImportError.imageCompressionFailed
        }
        
        let storageRef = storage.reference().child("restaurants/\(restaurantID)/main.jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    /// Batch upload images for all restaurants
    func uploadAllImages() async {
        let snapshot = try? await db.collection("restaurants").getDocuments()
        guard let documents = snapshot?.documents else { return }
        
        for doc in documents {
            guard let restaurant = try? doc.data(as: Restaurant.self),
                  let id = restaurant.id else { continue }
            
            do {
                let imageURL = try await uploadImage(localImageName: restaurant.imageName, restaurantID: id)
                
                // Update restaurant with image URL
                try await db.collection("restaurants").document(id).updateData([
                    "image_url": imageURL
                ])
                
                print("✅ Uploaded image for: \(restaurant.name)")
            } catch {
                print("❌ Failed to upload image for \(restaurant.name): \(error)")
            }
        }
    }
    
    // MARK: - Batch Operations
    
    /// Delete all restaurants (use with caution!)
    func deleteAllRestaurants() async throws {
        let snapshot = try await db.collection("restaurants").getDocuments()
        
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        try await batch.commit()
        print("🗑️ Deleted all restaurants")
    }
    
    /// Export current Firebase data to JSON (for backup)
    func exportToJSON() async throws -> String {
        let snapshot = try await db.collection("restaurants").getDocuments()
        
        let restaurants = snapshot.documents.compactMap { doc -> Restaurant? in
            try? doc.data(as: Restaurant.self)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(restaurants)
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ImportError.encodingFailed
        }
        
        print("✅ Exported \(restaurants.count) restaurants")
        return jsonString
    }
    
    enum ImportError: LocalizedError {
        case fileNotFound
        case imageNotFound
        case imageCompressionFailed
        case encodingFailed
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "JSON file not found in bundle"
            case .imageNotFound:
                return "Image not found in assets"
            case .imageCompressionFailed:
                return "Failed to compress image"
            case .encodingFailed:
                return "Failed to encode JSON"
            }
        }
    }
}

// MARK: - Sample Usage

/*
 To use this importer:
 
 1. Create a JSON file with your restaurant data:
 
 [
   {
     "name": "Myeongdong Kyoja",
     "cuisine": "Korean",
     "rating": 4.6,
     "address": "29 Myeongdong 10-gil, Jung-gu, Seoul",
     "description": "Famous for kalguksu (hand-cut noodles) and mandu (dumplings).",
     "image_name": "myeongdong_kyoja",
     "latitude": 37.5632,
     "longitude": 126.9850,
     "city": "Seoul",
     "neighborhood": "Myeongdong",
     "price_range": 2,
     "phone_number": "02-776-5348",
     "tags": ["Noodles", "Dumplings", "Traditional"],
     "hours": "10:30 AM - 9:00 PM"
   },
   // ... more restaurants
 ]
 
 2. In your app, call the importer:
 
 Task {
     let importer = DataImporter()
     try await importer.importRestaurantsFromJSON(fileName: "korean_restaurants")
 }
 
 3. (Optional) Upload images:
 
 Task {
     let importer = DataImporter()
     await importer.uploadAllImages()
 }
 
 */
