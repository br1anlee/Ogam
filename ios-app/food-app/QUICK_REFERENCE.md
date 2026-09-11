# Quick Reference Guide - Firebase Integration

## 🎯 What We Built

✅ **Firebase Firestore** - Cloud database for 100+ restaurants  
✅ **Offline Caching** - App works without internet  
✅ **Image Support** - Firebase Storage for restaurant photos  
✅ **Real-time Sync** - Automatic updates across devices  
✅ **Data Import Tools** - Easy bulk import from JSON  

---

## 📁 New Files Created

| File | Purpose |
|------|---------|
| `RestaurantRepository.swift` | Manages all Firebase operations + caching |
| `FirebaseConfig.swift` | Firebase initialization with offline support |
| `DataImporter.swift` | Bulk import restaurants from JSON |
| `AdminView.swift` | UI for importing/managing data |
| `sample_restaurants.json` | Template for your restaurant data |
| `FIREBASE_SETUP.md` | Detailed setup instructions |

---

## 🚀 Quick Start (3 Steps)

### 1. Install Firebase Package
```
File → Add Package Dependencies
URL: https://github.com/firebase/firebase-ios-sdk
Add: FirebaseFirestore, FirebaseStorage
```

### 2. Download GoogleService-Info.plist
- Go to [Firebase Console](https://console.firebase.google.com)
- Create project → Add iOS app
- Download `GoogleService-Info.plist`
- Drag into Xcode project root

### 3. Import Your Data
```swift
// Option A: Use sample data (in AdminView)
Button("Import Sample") {
    importSampleData()
}

// Option B: Import from JSON
Task {
    let importer = DataImporter()
    try await importer.importRestaurantsFromJSON(fileName: "your_file")
}
```

---

## 🔧 Key Features

### Offline Support
```swift
// Already configured in FirebaseConfig.swift
settings.isPersistenceEnabled = true
settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
```

**How it works:**
1. First launch: Downloads all restaurants from Firebase
2. Saves to local cache (UserDefaults + Firestore cache)
3. Offline: Uses cached data
4. Online: Auto-syncs in background

### Real-time Updates
```swift
// In RestaurantRepository.swift
func startListening() {
    listener = db.collection("restaurants")
        .addSnapshotListener { snapshot, error in
            // Updates automatically when data changes
        }
}
```

**What this means:**
- Update restaurant in Firebase Console → App updates instantly
- No need to refresh manually
- Perfect for managing 100+ restaurants remotely

### Search & Filter
```swift
// Text search (works offline!)
repository.searchByText("bibimbap")

// Location-based search
repository.searchByLocation(near: userLocation, radiusInMeters: 5000)

// Advanced filtering
try await repository.searchRestaurants(
    cuisine: "Korean",
    minRating: 4.5,
    city: "Seoul",
    tags: ["BBQ", "Late Night"]
)
```

---

## 📊 Data Structure

### Firestore Collection: `restaurants`

```json
{
  "name": "Myeongdong Kyoja",
  "cuisine": "Korean",
  "rating": 4.6,
  "address": "29 Myeongdong 10-gil, Jung-gu, Seoul",
  "description": "Famous for kalguksu and mandu",
  "image_url": "https://firebasestorage.../main.jpg",
  "latitude": 37.5632,
  "longitude": 126.9850,
  "city": "Seoul",
  "neighborhood": "Myeongdong",
  "price_range": 2,
  "phone_number": "02-776-5348",
  "tags": ["Noodles", "Dumplings", "Traditional"],
  "hours": "10:30 AM - 9:00 PM",
  "is_open_now": true,
  "created_at": "2026-04-02T10:30:00Z",
  "updated_at": "2026-04-02T10:30:00Z"
}
```

### Storage Structure

```
restaurants/
  ├── {restaurant-id-1}/
  │   └── main.jpg
  ├── {restaurant-id-2}/
  │   └── main.jpg
  └── ...
```

---

## 🛠️ Common Tasks

### Add a Restaurant Programmatically
```swift
let restaurant = Restaurant(
    name: "New Restaurant",
    cuisine: "Korean",
    rating: 4.5,
    // ... other fields
)

try await repository.addRestaurant(restaurant)
```

### Update a Restaurant
```swift
var restaurant = existingRestaurant
restaurant.rating = 4.8
try await repository.updateRestaurant(restaurant)
```

### Delete a Restaurant
```swift
try await repository.deleteRestaurant(restaurant)
```

### Bulk Import from JSON
```swift
// 1. Create JSON file (see sample_restaurants.json)
// 2. Add to Xcode project
// 3. Import:
let importer = DataImporter()
try await importer.importRestaurantsFromJSON(fileName: "korean_restaurants")
```

### Upload Images
```swift
let importer = DataImporter()

// Upload single image
let url = try await importer.uploadImage(
    localImageName: "restaurant_photo",
    restaurantID: "abc123"
)

// Batch upload all images
await importer.uploadAllImages()
```

---

## 🎨 UI Changes Made

### ContentView
- Changed from hardcoded array to `@EnvironmentObject` repository
- Favorites now store IDs instead of full objects
- Added real-time listener on appear

### Search & Image Loading
- Uses `AsyncImage` for Firebase Storage URLs
- Fallback to local images if no URL
- Shows `ProgressView` while loading

### New Restaurant Fields Displayed
- Price range (₩ symbols)
- Phone number (clickable link)
- Hours
- Tags (horizontal scroll)

---

## 🐛 Debugging Tips

### Check if Firebase is Connected
```swift
// Look for this in console:
✅ Firebase configured with offline persistence
✅ Loaded X restaurants from Firestore
```

### Test Offline Mode
1. Run app once (loads data)
2. Enable Airplane Mode
3. Force quit and relaunch
4. Should show cached restaurants

### View Firestore Data
Firebase Console → Firestore Database → restaurants

### Check Storage
Firebase Console → Storage → restaurants/

### Clear Cache for Testing
```swift
repository.clearCache()
// or use Admin Panel
```

---

## 💰 Costs (Free Tier)

You'll stay FREE unless you have massive traffic:

| Resource | Free Limit | Your Usage |
|----------|------------|------------|
| Firestore Reads | 50K/day | ~1K/day ✅ |
| Firestore Writes | 20K/day | ~100/day ✅ |
| Storage | 5GB | ~500MB ✅ |
| Downloads | 1GB/day | ~100MB ✅ |

---

## 📱 Admin Panel Usage

Add to ContentView.swift:
```swift
#if DEBUG
AdminView()
    .tabItem {
        Label("Admin", systemImage: "wrench.and.screwdriver")
    }
#endif
```

Features:
- Import sample restaurants
- Import from JSON
- Upload images
- Export data backup
- Clear cache
- View statistics

**⚠️ Only shows in DEBUG builds** (won't appear in App Store)

---

## 🎯 Next Steps

1. ✅ Firebase configured
2. ✅ Import scripts ready
3. ⏭️ **Create your JSON file** with 100+ restaurants
4. ⏭️ Run import via Admin Panel
5. ⏭️ Upload restaurant images
6. ⏭️ Test offline functionality
7. ⏭️ Deploy to TestFlight

---

## 📚 Additional Resources

- [Firebase iOS Docs](https://firebase.google.com/docs/ios/setup)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Firebase Storage Guide](https://firebase.google.com/docs/storage/ios/start)
- [Offline Persistence](https://firebase.google.com/docs/firestore/manage-data/enable-offline)

---

## 💡 Pro Tips

**For 100+ Restaurants:**
- Use `importRestaurantsFromJSON()` instead of manual entry
- Keep images under 1MB (compress before upload)
- Add restaurants in batches of 20-30 for easier management

**Performance:**
- First load may take a few seconds (downloading all data)
- Subsequent loads are instant (cached)
- Real-time updates are minimal data transfer

**Data Management:**
- Keep a backup JSON file of all restaurants
- Use Admin Panel's export feature regularly
- Test with small dataset first (10 restaurants)

**Korean Specific:**
- Add both Korean and English names in description
- Use Seoul coordinates as default center
- Include neighborhood for better search

---

Need help? Check `FIREBASE_SETUP.md` for detailed instructions!
