//
//  food_appApp.swift
//  food-app
//
//  Created by Brian Lee on 3/29/26.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct food_appApp: App {
    @StateObject private var restaurantRepository = RestaurantRepository()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        // Configure Firebase on app launch
        FirebaseConfig.shared.configure()
        
        // Print configuration status (helpful for debugging)
        Config.printConfiguration()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(restaurantRepository)
        }
        .modelContainer(sharedModelContainer)
    }
}
