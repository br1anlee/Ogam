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

        let rawData = try Data(contentsOf: url)

        // Parse as raw dictionaries so we can sanitize null values before decoding
        guard var rawArray = try JSONSerialization.jsonObject(with: rawData) as? [[String: Any]] else {
            throw ImportError.fileNotFound
        }

        rawArray = rawArray.map { dict in
            var d = dict
            // Fill required non-optional fields that may be null in the source JSON
            if d["rating"] == nil || d["rating"] is NSNull { d["rating"] = 0.0 }
            if d["latitude"] == nil || d["latitude"] is NSNull { d["latitude"] = 0.0 }
            if d["longitude"] == nil || d["longitude"] is NSNull { d["longitude"] = 0.0 }
            if (d["image_name"] as? String) == nil { d["image_name"] = "placeholder" }
            if (d["address"] as? String) == nil { d["address"] = "" }
            if (d["description"] as? String) == nil { d["description"] = "" }
            // Map station → tags so the nearest subway station is searchable
            if let station = d["station"] as? String, !station.isEmpty {
                var tags = d["tags"] as? [String] ?? []
                if !tags.contains(station) { tags.append(station) }
                d["tags"] = tags
            }
            d.removeValue(forKey: "station")
            return d
        }

        // Build Restaurant objects directly from dictionaries to avoid
        // @DocumentID Codable issues when the "id" key is absent from JSON
        let restaurants: [Restaurant] = rawArray.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let cuisine = dict["cuisine"] as? String else { return nil }
            return Restaurant(
                name: name,
                cuisine: cuisine,
                rating: dict["rating"] as? Double ?? 0.0,
                address: dict["address"] as? String ?? "",
                description: dict["description"] as? String ?? "",
                imageName: dict["image_name"] as? String ?? "placeholder",
                latitude: dict["latitude"] as? Double ?? 0.0,
                longitude: dict["longitude"] as? Double ?? 0.0,
                city: dict["city"] as? String,
                neighborhood: dict["neighborhood"] as? String,
                priceRange: dict["price_range"] as? Int,
                phoneNumber: dict["phone_number"] as? String,
                tags: dict["tags"] as? [String],
                hours: dict["hours"] as? String
            )
        }

        print("📦 Found \(restaurants.count) restaurants in \(fileName).json")

        try await batchImport(restaurants)

        print("🎉 Import complete!")
    }

    /// Batch import using Firestore batch writes (500 ops max per batch)
    private func batchImport(_ restaurants: [Restaurant]) async throws {
        // Fetch existing names to skip duplicates
        print("🔍 Checking for duplicates...")
        let snapshot = try await db.collection("restaurants").getDocuments()
        let existingNames = Set(snapshot.documents.compactMap { $0.data()["name"] as? String })

        let unique = restaurants.filter { !existingNames.contains($0.name) }
        let skipped = restaurants.count - unique.count
        if skipped > 0 {
            print("⚠️  Skipping \(skipped) duplicate(s) already in the database")
        }
        if unique.isEmpty {
            print("✅ Nothing new to import — all restaurants already exist")
            return
        }

        let batchSize = 400
        let chunks = stride(from: 0, to: unique.count, by: batchSize).map {
            Array(unique[$0..<min($0 + batchSize, unique.count)])
        }

        for (index, chunk) in chunks.enumerated() {
            let batch = db.batch()
            for restaurant in chunk {
                var r = restaurant
                r.id = nil
                r.searchTokens = Restaurant.makeSearchTokens(name: r.name, cuisine: r.cuisine)
                let docRef = db.collection("restaurants").document()
                try batch.setData(from: r, forDocument: docRef)
            }
            try await batch.commit()
            print("✅ Batch \(index + 1)/\(chunks.count) committed (\(chunk.count) restaurants)")
        }
        print("📊 Import summary: \(unique.count) added, \(skipped) skipped as duplicates")
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
