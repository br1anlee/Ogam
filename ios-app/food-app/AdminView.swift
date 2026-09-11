import SwiftUI
import FirebaseFirestore

/// Admin view for managing restaurant data
/// Add this to your app during development for easy data import
struct AdminView: View {
    @EnvironmentObject var repository: RestaurantRepository
    @State private var isImporting = false
    @State private var isUploadingImages = false
    @State private var isDeDuplicating = false
    @State private var isReindexing = false
    @State private var reindexProgress = ""
    @State private var isRefreshingHours = false
    @State private var hoursRefreshProgress = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var importedCount = 0

    // Quick Add by Name
    @State private var quickAddName = ""
    @State private var quickAddCuisine = ""
    @State private var isQuickAdding = false
    @State private var searchResults: [TextSearchResult] = []
    @State private var quickAddPreview: Restaurant? = nil
    
    var body: some View {
        NavigationStack {
            List {
                Section("Quick Add by Name") {
                    HStack {
                        TextField("Restaurant name", text: $quickAddName)
                            .onSubmit { if !quickAddName.trimmingCharacters(in: .whitespaces).isEmpty { searchAndPreview() } }
                        if isQuickAdding && quickAddPreview == nil && searchResults.isEmpty {
                            ProgressView()
                                .padding(.leading, 4)
                        } else {
                            Button {
                                searchAndPreview()
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(quickAddName.trimmingCharacters(in: .whitespaces).isEmpty || isQuickAdding)
                        }
                    }
                    TextField("Cuisine type (e.g. Korean BBQ)", text: $quickAddCuisine)

                    if let preview = quickAddPreview {
                        // — Preview card after picking a result —
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preview.name)
                                .font(.headline)
                            Text(preview.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if preview.rating > 0 {
                                Text("⭐️ \(preview.rating, specifier: "%.1f")  |  \(preview.phoneNumber ?? "No phone")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button {
                            saveQuickAdd(preview)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Save to Firebase")
                            }
                        }

                        Button(role: .destructive) {
                            quickAddPreview = nil
                            searchResults = []
                        } label: {
                            Text("Back to Results")
                        }

                    } else if !searchResults.isEmpty {
                        // — Search results list —
                        ForEach(searchResults) { result in
                            Button {
                                loadPreview(for: result)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        if let addr = result.formattedAddress {
                                            Text(addr)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if let r = result.rating {
                                        Text("⭐️ \(r, specifier: "%.1f")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if isQuickAdding {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isQuickAdding)
                        }

                        Button(role: .destructive) {
                            searchResults = []
                            quickAddName = ""
                            quickAddCuisine = ""
                        } label: {
                            Text("Cancel")
                        }

                    }
                }

                Section("Data Import") {
                    Button {
                        importSampleData()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Sample Restaurants")
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting)

                    Button {
                        importFromJSON()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Import from JSON File (sample_restaurants)")
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting)

                    Button {
                        importFullDataset()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.doc.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text("Import Full Seoul Dataset")
                                    .font(.headline)
                                Text("seoul_restaurants.json — batch upload")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting)
                    
                    // NEW: PDF Import Test
                    Button {
                        importFromPDF()
                    } label: {
                        HStack {
                            Image(systemName: "doc.richtext.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("Import 10 Test Restaurants")
                                    .font(.headline)
                                Text("From PDF CSV (with Google data)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting)
                }
                
                Section("Image Upload") {
                    Button {
                        uploadAllImages()
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Upload All Images to Firebase")
                            Spacer()
                            if isUploadingImages {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isUploadingImages)
                }
                
                Section("Google Places Data") {
                    Button {
                        refreshGoogleHours()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Refresh Google Hours")
                                Text(isRefreshingHours ? hoursRefreshProgress : "Fetches open/closed hours for all restaurants")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isRefreshingHours { ProgressView() }
                        }
                    }
                    .disabled(isRefreshingHours || isImporting)

                    Button {
                        fetchGoogleDataForAll()
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text("Fetch Google Reviews & Photos")
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting || isRefreshingHours)

                    Button {
                        repository.clearGoogleDataCache()
                        alertMessage = "Google data cache cleared"
                        showAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Google Data Cache")
                        }
                    }
                }
                
                Section("Database Operations") {
                    Button {
                        Task {
                            await repository.fetchRestaurants()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh from Firebase")
                        }
                    }

                    Button {
                        reindexSearchTokens()
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reindex Search Tokens")
                                Text(isReindexing ? reindexProgress : "Makes all restaurants searchable by name")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isReindexing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isReindexing)
                    
                    Button {
                        repository.clearCache()
                        alertMessage = "Cache cleared successfully"
                        showAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Cache")
                        }
                    }
                    
                    Button {
                        exportData()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export to JSON")
                        }
                    }
                }
                
                Section("Dangerous Operations") {
                    Button(role: .destructive) {
                        removeDuplicates()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                            Text("Remove Duplicate Restaurants")
                            Spacer()
                            if isDeDuplicating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeDuplicating)

                    Button(role: .destructive) {
                        deleteAllData()
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All Restaurants")
                        }
                    }
                }
                
                Section("Statistics") {
                    HStack {
                        Text("Total Restaurants")
                        Spacer()
                        Text("\(repository.restaurants.count)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Imported in This Session")
                        Spacer()
                        Text("\(importedCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Cache Status")
                        Spacer()
                        Text(repository.restaurants.isEmpty ? "Empty" : "Loaded")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Admin Panel")
            .alert("Result", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - Import Functions
    
    func importSampleData() {
        isImporting = true
        
        Task {
            let sampleRestaurants = [
                Restaurant(
                    name: "Myeongdong Kyoja",
                    cuisine: "Korean",
                    rating: 4.6,
                    address: "29 Myeongdong 10-gil, Jung-gu, Seoul",
                    description: "Famous for kalguksu (hand-cut noodles) and mandu (dumplings).",
                    imageName: "myeongdong_kyoja",
                    latitude: 37.5632,
                    longitude: 126.9850,
                    city: "Seoul",
                    neighborhood: "Myeongdong",
                    priceRange: 2,
                    phoneNumber: "02-776-5348",
                    tags: ["Noodles", "Dumplings", "Traditional"],
                    hours: "10:30 AM - 9:00 PM"
                ),
                Restaurant(
                    name: "Tosokchon Samgyetang",
                    cuisine: "Korean",
                    rating: 4.7,
                    address: "85-1 Cheongun-dong, Jongno-gu, Seoul",
                    description: "Renowned for ginseng chicken soup near Gyeongbokgung Palace.",
                    imageName: "tosokchon",
                    latitude: 37.5810,
                    longitude: 126.9697,
                    city: "Seoul",
                    neighborhood: "Jongno",
                    priceRange: 3,
                    phoneNumber: "02-737-7444",
                    tags: ["Soup", "Ginseng", "Traditional"],
                    hours: "10:00 AM - 10:00 PM"
                ),
                Restaurant(
                    name: "Gwangjang Market",
                    cuisine: "Korean Street Food",
                    rating: 4.8,
                    address: "88 Changgyeonggung-ro, Jongno-gu, Seoul",
                    description: "Historic market famous for bindaetteok and mayak gimbap.",
                    imageName: "gwangjang_market",
                    latitude: 37.5701,
                    longitude: 126.9997,
                    city: "Seoul",
                    neighborhood: "Jongno",
                    priceRange: 1,
                    tags: ["Street Food", "Market", "Budget Friendly"],
                    hours: "9:00 AM - 11:00 PM"
                )
            ]
            
            do {
                let importer = DataImporter()
                try await importer.importRestaurants(sampleRestaurants)
                
                await MainActor.run {
                    importedCount += sampleRestaurants.count
                    alertMessage = "Successfully imported \(sampleRestaurants.count) sample restaurants!"
                    showAlert = true
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Import failed: \(error.localizedDescription)"
                    showAlert = true
                    isImporting = false
                }
            }
        }
    }
    
    func importFromJSON() {
        isImporting = true
        
        Task {
            do {
                let importer = DataImporter()
                try await importer.importRestaurantsFromJSON(fileName: "sample_restaurants")
                
                await MainActor.run {
                    alertMessage = "Successfully imported restaurants from JSON!"
                    showAlert = true
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "JSON import failed: \(error.localizedDescription)"
                    showAlert = true
                    isImporting = false
                }
            }
        }
    }
    
    func uploadAllImages() {
        isUploadingImages = true
        
        Task {
            let importer = DataImporter()
            await importer.uploadAllImages()
            
            await MainActor.run {
                alertMessage = "Image upload complete!"
                showAlert = true
                isUploadingImages = false
            }
        }
    }
    
    func exportData() {
        Task {
            do {
                let importer = DataImporter()
                let jsonString = try await importer.exportToJSON()
                
                // In a real app, you'd save this to Files or share it
                print("Exported JSON:")
                print(jsonString)
                
                await MainActor.run {
                    alertMessage = "Export complete! Check console for JSON output."
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Export failed: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    func deleteAllData() {
        Task {
            do {
                let importer = DataImporter()
                try await importer.deleteAllRestaurants()
                
                await MainActor.run {
                    importedCount = 0
                    alertMessage = "All restaurants deleted from Firebase"
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Delete failed: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    func refreshGoogleHours() {
        isRefreshingHours = true
        let total = repository.restaurants.filter { $0.googleHours == nil || $0.googleHours!.isEmpty }.count
        guard total > 0 else {
            alertMessage = "All restaurants already have hours data."
            showAlert = true
            isRefreshingHours = false
            return
        }
        hoursRefreshProgress = "0 / \(total)"
        Task {
            let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
            await repository.refreshGoogleHours(placesService: placesService) { done, total in
                hoursRefreshProgress = "\(done) / \(total)"
            }
            await MainActor.run {
                alertMessage = "Hours refreshed for \(total) restaurant(s). Open/closed status will now appear in the list."
                showAlert = true
                isRefreshingHours = false
                hoursRefreshProgress = ""
            }
        }
    }

    func fetchGoogleDataForAll() {
        isImporting = true

        Task {
            let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
            await repository.fetchAllGoogleData(placesService: placesService)

            await MainActor.run {
                alertMessage = "Fetched Google data for all restaurants!"
                showAlert = true
                isImporting = false
            }
        }
    }
    
    func importFullDataset() {
        isImporting = true
        Task {
            do {
                let importer = DataImporter()
                try await importer.importRestaurantsFromJSON(fileName: "seoul_restaurants")
                await MainActor.run {
                    alertMessage = "Full Seoul dataset imported successfully!"
                    showAlert = true
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Import failed: \(error.localizedDescription)"
                    showAlert = true
                    isImporting = false
                }
            }
        }
    }

    func searchAndPreview() {
        isQuickAdding = true
        searchResults = []   // clear immediately so the spinner shows
        quickAddPreview = nil
        Task {
            do {
                let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
                let results = try await placesService.searchRestaurants(query: quickAddName)
                await MainActor.run {
                    searchResults = results
                    isQuickAdding = false
                    if results.isEmpty {
                        alertMessage = "No results found for \"\(quickAddName)\"."
                        showAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Search failed: \(error.localizedDescription)"
                    showAlert = true
                    isQuickAdding = false
                }
            }
        }
    }

    func loadPreview(for result: TextSearchResult) {
        isQuickAdding = true
        Task {
            do {
                let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
                let restaurant = try await placesService.createRestaurant(from: result, cuisine: quickAddCuisine)
                await MainActor.run {
                    quickAddPreview = restaurant
                    isQuickAdding = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Failed to load details: \(error.localizedDescription)"
                    showAlert = true
                    isQuickAdding = false
                }
            }
        }
    }

    func saveQuickAdd(_ restaurant: Restaurant) {
        Task {
            // Check Firestore for an existing restaurant with the same name
            let snapshot = try? await repository.db.collection("restaurants")
                .whereField("name", isEqualTo: restaurant.name)
                .limit(to: 1)
                .getDocuments()

            if let count = snapshot?.documents.count, count > 0 {
                await MainActor.run {
                    alertMessage = "'\(restaurant.name)' already exists in the database."
                    showAlert = true
                }
                return
            }

            do {
                try await repository.addRestaurant(restaurant)
                await MainActor.run {
                    importedCount += 1
                    alertMessage = "Added \(restaurant.name) to Firebase!"
                    showAlert = true
                    quickAddPreview = nil
                    searchResults = []
                    quickAddName = ""
                    quickAddCuisine = ""
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Save failed: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    func reindexSearchTokens() {
        isReindexing = true
        reindexProgress = "Loading restaurants..."
        Task {
            do {
                // Page through entire collection
                var allDocs: [QueryDocumentSnapshot] = []
                var lastDoc: DocumentSnapshot? = nil
                while true {
                    var query = repository.db.collection("restaurants")
                        .order(by: FieldPath.documentID())
                        .limit(to: 500)
                    if let last = lastDoc {
                        query = query.start(afterDocument: last)
                    }
                    let snapshot = try await query.getDocuments()
                    allDocs.append(contentsOf: snapshot.documents)
                    await MainActor.run { reindexProgress = "Loaded \(allDocs.count) restaurants..." }
                    if snapshot.documents.count < 500 { break }
                    lastDoc = snapshot.documents.last
                }

                // Build batches of updateData calls
                let chunks = stride(from: 0, to: allDocs.count, by: 400).map {
                    Array(allDocs[$0..<min($0 + 400, allDocs.count)])
                }

                var updated = 0
                for (i, chunk) in chunks.enumerated() {
                    let batch = repository.db.batch()
                    for doc in chunk {
                        let data = doc.data()
                        let name = data["name"] as? String ?? ""
                        let cuisine = data["cuisine"] as? String ?? ""
                        let address = data["address"] as? String ?? ""
                        let city = data["city"] as? String
                        let neighborhood = data["neighborhood"] as? String
                        let tokens = Restaurant.makeSearchTokens(
                            name: name,
                            cuisine: cuisine,
                            address: address,
                            city: city,
                            neighborhood: neighborhood
                        )
                        batch.updateData(["search_tokens": tokens], forDocument: doc.reference)
                    }
                    try await batch.commit()
                    updated += chunk.count
                    await MainActor.run {
                        reindexProgress = "Updated \(updated)/\(allDocs.count) (\(i + 1)/\(chunks.count) batches)"
                    }
                }

                await MainActor.run {
                    alertMessage = "Reindex complete — \(allDocs.count) restaurants are now fully searchable."
                    showAlert = true
                    isReindexing = false
                    reindexProgress = ""
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Reindex failed: \(error.localizedDescription)"
                    showAlert = true
                    isReindexing = false
                    reindexProgress = ""
                }
            }
        }
    }

    func removeDuplicates() {
        isDeDuplicating = true
        Task {
            do {
                // Page through every document in the collection
                var allDocs: [QueryDocumentSnapshot] = []
                var lastDoc: DocumentSnapshot? = nil
                while true {
                    var query = repository.db.collection("restaurants")
                        .order(by: FieldPath.documentID())
                        .limit(to: 500)
                    if let last = lastDoc {
                        query = query.start(afterDocument: last)
                    }
                    let snapshot = try await query.getDocuments()
                    allDocs.append(contentsOf: snapshot.documents)
                    if snapshot.documents.count < 500 { break }
                    lastDoc = snapshot.documents.last
                }

                // Group documents by lowercased name
                var groups: [String: [QueryDocumentSnapshot]] = [:]
                for doc in allDocs {
                    let name = (doc.data()["name"] as? String ?? "")
                        .lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    groups[name, default: []].append(doc)
                }

                let duplicateGroups = groups.filter { $0.value.count > 1 }
                guard !duplicateGroups.isEmpty else {
                    await MainActor.run {
                        alertMessage = "No duplicates found — database is clean."
                        showAlert = true
                        isDeDuplicating = false
                    }
                    return
                }

                // For each duplicate group, keep the most complete document
                var toDelete: [QueryDocumentSnapshot] = []
                for (_, docs) in duplicateGroups {
                    let scored: [(QueryDocumentSnapshot, Int)] = docs.map { doc in
                        let d = doc.data()
                        var score = 0
                        if let url = d["image_url"] as? String, !url.isEmpty { score += 2 }
                        if let lat = d["latitude"] as? Double, lat != 0 { score += 1 }
                        if let phone = d["phone_number"] as? String, !phone.isEmpty { score += 1 }
                        if let hood = d["neighborhood"] as? String, !hood.isEmpty { score += 1 }
                        if let tokens = d["search_tokens"] as? [String], !tokens.isEmpty { score += 1 }
                        if let hours = d["hours"] as? String, !hours.isEmpty { score += 1 }
                        return (doc, score)
                    }.sorted { $0.1 > $1.1 }

                    // Keep the highest-scored doc; mark the rest for deletion
                    toDelete.append(contentsOf: scored.dropFirst().map { $0.0 })
                }

                // Delete in batches of 400
                let chunks = stride(from: 0, to: toDelete.count, by: 400).map {
                    Array(toDelete[$0..<min($0 + 400, toDelete.count)])
                }
                for chunk in chunks {
                    let batch = repository.db.batch()
                    for doc in chunk { batch.deleteDocument(doc.reference) }
                    try await batch.commit()
                }

                await MainActor.run {
                    alertMessage = "Removed \(toDelete.count) duplicate(s) across \(duplicateGroups.count) restaurant name(s)."
                    showAlert = true
                    isDeDuplicating = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Dedup failed: \(error.localizedDescription)"
                    showAlert = true
                    isDeDuplicating = false
                }
            }
        }
    }

    func importFromPDF() {
        isImporting = true
        
        Task {
            do {
                let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
                let importer = PDFRestaurantImporter(placesService: placesService)
                
                print("🚀 Starting PDF import...")
                try await importer.importFromCSV(fileName: "restaurants_from_pdf")
                
                await MainActor.run {
                    importedCount += 10
                    alertMessage = "Successfully imported 10 restaurants with reviews, photos, and all Google data!"
                    showAlert = true
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Import failed: \(error.localizedDescription)"
                    showAlert = true
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - Add Admin Tab to ContentView

// To use this, add another tab to your TabView in ContentView:
/*
 
 // Add this inside your TabView in ContentView.swift:
 
 #if DEBUG
 AdminView()
     .tabItem {
         Label("Admin", systemImage: "wrench.and.screwdriver")
     }
 #endif
 
 */

#Preview {
    AdminView()
        .environmentObject(RestaurantRepository())
}
