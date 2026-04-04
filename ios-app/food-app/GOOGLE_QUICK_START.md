# 🌟 Quick Start: Google Reviews Integration

## What You Can Now Do

✅ Fetch real reviews from Google  
✅ Display Google photos for each restaurant  
✅ Show accurate ratings from Google  
✅ Get phone numbers, websites, hours from Google  
✅ Cache everything to save API costs  

---

## 🚀 3-Minute Setup

### 1. Get Google Places API Key

```
1. Go to: https://console.cloud.google.com
2. Create project → Enable "Places API"
3. Create API key → Copy it
4. Enable billing (free tier = $200/month credit!)
```

### 2. Add API Key to App

Open `Config.swift`:
```swift
static let googlePlacesAPIKey = "AIzaSy..."  // Paste your key here
```

### 3. Import Google Data

**Option A - Admin Panel (Easiest):**
1. Run your app
2. Go to Admin tab
3. Tap "Fetch Google Reviews & Photos"
4. Wait ~2 minutes for 100 restaurants

**Option B - Programmatically:**
```swift
let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
await repository.fetchAllGoogleData(placesService: placesService)
```

### 4. View Reviews

1. Open any restaurant
2. Tap "View Google Reviews"
3. See photos, ratings, reviews! 🎉

---

## 📱 New Features

### Reviews Screen
- Google rating + review count
- Photo gallery (up to 10 photos)
- Up to 5 recent reviews
- Opening hours
- Phone number (clickable)
- Website link

### Data Cached Automatically
- First fetch: From Google API (~$0.07/restaurant)
- Subsequent views: From cache (FREE!)
- Syncs via Firebase across devices
- 24-hour cache expiration (configurable)

---

## 💰 Pricing

### One-Time Import (100 restaurants)
```
Find Place:     100 × $0.017 = $1.70
Place Details:  100 × $0.017 = $1.70
Photos:         500 × $0.007 = $3.50
─────────────────────────────────
Total:                        ~$7.00
Free tier credit:            $200/month
Your cost:                   $0.00 ✅
```

### Ongoing Costs
```
Daily: $0 (everything is cached)
Monthly: $0 (within free tier)
```

---

## 🔧 Configuration Options

### In `Config.swift`:

```swift
// Enable/disable Google reviews
static let enableGoogleReviews = true

// Rate limiting (requests per second)
static let googlePlacesRateLimit: TimeInterval = 0.1

// Cache expiration
static let googleDataCacheExpirationHours = 24

// Max items to fetch
static let maxPhotosPerRestaurant = 10
static let maxReviewsToDisplay = 5
```

---

## 🗂️ Where Data is Stored

### 1. Firestore (Persistent)
```
restaurants/{id}
  ├── google_place_id
  ├── google_rating
  ├── google_reviews (array)
  ├── google_photo_urls (array)
  ├── google_phone
  ├── google_website
  └── google_hours
```

### 2. UserDefaults (Local Cache)
```
google_data_{restaurant_id}
```

### 3. Memory (Runtime)
```swift
@Published var googleData: RestaurantGoogleData?
```

---

## 📚 Code Examples

### Fetch for Single Restaurant
```swift
let service = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)

let googleData = try await repository.fetchGoogleData(
    for: restaurant,
    placesService: service
)

print("Rating: \(googleData.rating ?? 0)")
print("Reviews: \(googleData.reviews.count)")
print("Photos: \(googleData.photoURLs.count)")
```

### Load from Cache
```swift
// Automatically checks cache first
let data = try await repository.fetchGoogleData(
    for: restaurant,
    placesService: service
) // Uses cache if available, only fetches if needed
```

### Clear Cache
```swift
// Clear all Google data cache
repository.clearGoogleDataCache()

// Or via Admin Panel:
// Admin → Google Places Data → Clear Google Data Cache
```

### Load from Firestore
```swift
let googleData = try await repository.loadGoogleDataFromFirestore(
    restaurantId: restaurant.id!
)
```

---

## 🎯 What Gets Fetched from Google

### For Each Restaurant:

**1. Basic Info**
- Google Place ID
- Google rating (1-5 stars)
- Total review count

**2. Reviews**
- Author name
- Author photo
- Rating (1-5 stars)
- Review text
- Date posted

**3. Photos**
- Up to 10 high-quality photos
- Direct URLs (cached)
- Various sizes available

**4. Business Info**
- Phone number
- Website
- Opening hours (all days)
- Price level (1-4)

---

## 🛡️ Error Handling

The app handles these errors gracefully:

```swift
- API key not configured → Shows alert
- No internet → Uses cached data
- Restaurant not found → Shows empty state
- Rate limit hit → Automatic retry with delay
- API quota exceeded → Shows error, retry later
```

---

## 🎨 UI Components

### New Views Created:

1. **`ReviewsView`** - Main reviews screen
2. **`ReviewsContentView`** - Content with data
3. **`RatingSummaryView`** - Google rating display
4. **`PhotoGalleryView`** - Horizontal photo scroll
5. **`ReviewCardView`** - Individual review cards
6. **`ErrorView`** - Error state with retry
7. **`EmptyReviewsView`** - No reviews state

---

## 🧪 Testing

### Test with One Restaurant
```swift
// In AdminView or a test screen
let service = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
let location = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)

Task {
    let data = try await service.fetchRestaurantData(
        name: "Myeongdong Kyoja",
        location: location
    )
    
    print("Success! Got \(data.reviews.count) reviews")
}
```

### Monitor API Usage
```
Google Cloud Console → APIs & Services → Dashboard
→ View request counts and costs in real-time
```

---

## 🔒 Security Best Practices

### Development
```swift
// Config.swift
static let googlePlacesAPIKey = "AIzaSy..."  // OK for now
```

### Production (Choose One)

**1. Restrict API Key**
```
Google Cloud Console → Credentials → Edit API key
→ iOS apps → Add bundle ID
→ Restrict to Places API only
```

**2. Use Backend Proxy**
```
Create Firebase Function or backend server
→ App calls your server
→ Server calls Google API
→ API key never in app
```

**3. Environment Variables**
```swift
// Store in Xcode scheme or environment
static let googlePlacesAPIKey = ProcessInfo.processInfo
    .environment["GOOGLE_API_KEY"] ?? ""
```

---

## 📋 Checklist

Before using in production:

- [ ] Google Cloud project created
- [ ] Places API enabled
- [ ] Billing enabled (for free tier access)
- [ ] API key created and restricted
- [ ] API key added to `Config.swift`
- [ ] Budget alerts set up ($10, $50)
- [ ] Tested with 1-5 restaurants
- [ ] Batch imported all restaurants
- [ ] Verified data in Firestore
- [ ] Tested offline mode (cache working)
- [ ] Reviewed Google's Terms of Service
- [ ] Added attribution if required

---

## 🌐 Google Attribution Requirements

When displaying Google data, you must:

1. **Show "Powered by Google" logo** (for photos)
2. **Include attribution text** (for reviews)
3. **Link to original Google reviews** (if possible)

Example:
```swift
Text("Reviews from Google")
    .font(.caption)
    .foregroundStyle(.secondary)
```

Or use Google's official badge images.

---

## 🆘 Need Help?

**Detailed guides:**
- `GOOGLE_PLACES_SETUP.md` - Full setup instructions
- `FIREBASE_SETUP.md` - Firebase configuration
- `QUICK_REFERENCE.md` - General app reference

**Official docs:**
- https://developers.google.com/maps/documentation/places/web-service
- https://console.cloud.google.com

**Common issues:**
- API key issues → Check `GOOGLE_PLACES_SETUP.md` troubleshooting
- Billing problems → Enable billing in Google Cloud
- No data showing → Check console logs for errors

---

**You're all set!** 🎉

Your app now has:
✅ Firebase backend (100+ restaurants)  
✅ Offline caching  
✅ Google reviews & photos  
✅ Real-time sync  
✅ Admin panel for easy management  

Go build something awesome! 🚀
