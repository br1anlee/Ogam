import SwiftUI

/// Admin view for managing restaurant data
/// Add this to your app during development for easy data import
struct AdminView: View {
    @EnvironmentObject var repository: RestaurantRepository
    @State private var isImporting = false
    @State private var isUploadingImages = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var importedCount = 0
    
    var body: some View {
        NavigationStack {
            List {
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
                            Text("Import from JSON File")
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
                    .disabled(isImporting)
                    
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
