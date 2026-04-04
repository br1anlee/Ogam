import Foundation

/// Configuration for API keys and app settings
/// ⚠️ DO NOT commit this file with real keys to version control!
/// Add Config.swift to .gitignore
enum Config {
    
    // MARK: - Google Places API
    
    /// Your Google Places API Key
    /// Get it from: https://console.cloud.google.com/google/maps-apis/credentials
    static let googlePlacesAPIKey = "GOOGLE_PLACES_API_KEY_REDACTED"
    
    // MARK: - Environment
    
    static var isProduction: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }
    
    // MARK: - Feature Flags
    
    static let enableGoogleReviews = true
    static let enableOfflineMode = true
    static let enableAnalytics = true
    
    // MARK: - API Settings
    
    static let googlePlacesRateLimit: TimeInterval = 0.1 // seconds between requests
    static let maxPhotosPerRestaurant = 10
    static let maxReviewsToDisplay = 5
    
    // MARK: - Cache Settings
    
    static let googleDataCacheExpirationHours = 24 // Refresh after 24 hours
    
    // MARK: - Validation
    
    static func validateAPIKeys() -> [String] {
        var errors: [String] = []
        
        if googlePlacesAPIKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE" {
            errors.append("Google Places API key not configured")
        }
        
        return errors
    }
    
    static func printConfiguration() {
        print("📋 App Configuration:")
        print("   Environment: \(isProduction ? "Production" : "Debug")")
        print("   Google Reviews: \(enableGoogleReviews ? "Enabled" : "Disabled")")
        print("   Offline Mode: \(enableOfflineMode ? "Enabled" : "Disabled")")
        
        let errors = validateAPIKeys()
        if !errors.isEmpty {
            print("⚠️  Configuration Warnings:")
            errors.forEach { print("   - \($0)") }
        } else {
            print("✅ All API keys configured")
        }
    }
}
