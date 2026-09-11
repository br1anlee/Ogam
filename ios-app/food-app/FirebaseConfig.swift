import Foundation
import FirebaseCore
import FirebaseFirestore

class FirebaseConfig {
    static let shared = FirebaseConfig()
    
    private init() {}
    
    func configure() {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Enable offline persistence
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        
        Firestore.firestore().settings = settings
        
        print("✅ Firebase configured with offline persistence")
    }
    
    func enableNetwork() {
        Firestore.firestore().enableNetwork { error in
            if let error = error {
                print("❌ Failed to enable network: \(error)")
            } else {
                print("✅ Network enabled")
            }
        }
    }
    
    func disableNetwork() {
        Firestore.firestore().disableNetwork { error in
            if let error = error {
                print("❌ Failed to disable network: \(error)")
            } else {
                print("✅ Network disabled (offline mode)")
            }
        }
    }
}
