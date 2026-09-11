# Google Places API Setup Guide

## Getting Your API Key

### Step 1: Create Google Cloud Project

1. **Go to Google Cloud Console:**
   - Visit: https://console.cloud.google.com
   - Sign in with your Google account

2. **Create a New Project:**
   - Click the project dropdown (top left)
   - Click "New Project"
   - Name it: `korean-restaurant-app`
   - Click "Create"

### Step 2: Enable Places API

1. **Navigate to APIs & Services:**
   - In the left menu, go to **APIs & Services** → **Library**

2. **Enable Required APIs:**
   - Search for "Places API" and enable it
   - Search for "Places API (New)" and enable it (recommended)
   - Search for "Maps JavaScript API" and enable it (optional, for web)

### Step 3: Create API Key

1. **Go to Credentials:**
   - APIs & Services → **Credentials**
   - Click "+ CREATE CREDENTIALS" → "API key"
   - Copy your API key

2. **Restrict Your API Key (Important!):**
   - Click "Edit API key"
   - **Application restrictions:**
     - Select "iOS apps"
     - Add your bundle ID (e.g., `com.yourname.food-app`)
   - **API restrictions:**
     - Select "Restrict key"
     - Choose:
       - Places API
       - Places API (New)
   - Click "Save"

### Step 4: Add API Key to Your App

1. **Open `Config.swift`:**
```swift
static let googlePlacesAPIKey = "AIzaSy..."  // Paste your key here
```

2. **⚠️ Security Best Practice:**
   - Add `Config.swift` to `.gitignore`
   - Never commit API keys to public repositories
   - For production, use a backend server or Firebase Functions

### Step 5: Enable Billing (Required!)

Google Places API requires a billing account, but offers free tier:

1. **Set up billing:**
   - Go to **Billing** in Google Cloud Console
   - Add a payment method

2. **Free Tier Limits:**
   - **Places Details**: $17 per 1,000 requests
   - **Find Place**: $17 per 1,000 requests  
   - **Place Photos**: $7 per 1,000 requests
   - **Monthly credit**: $200 FREE
   
   **You get ~10,000 free requests per month!**

3. **Set Budget Alerts:**
   - Billing → Budgets & alerts
   - Set alert at $10, $50, etc.

---

## Understanding Costs

### What You're Charged For:

| API Call | Cost per 1,000 | Free Monthly |
|----------|----------------|--------------|
| Find Place (search) | $17 | ~700 calls |
| Place Details | $17 | ~700 calls |
| Place Photos | $7 | ~1,700 calls |

### Your App Usage (Estimated):

**One-time import (100 restaurants):**
- 100 Find Place calls = $1.70
- 100 Place Details = $1.70
- 500 Photo URLs = $3.50
- **Total: ~$7** (within free tier!)

**Daily usage (100 users):**
- Most data is cached
- Minimal API calls after initial import
- **Cost: $0-1/day**

---

## Implementation in Your App

### Fetching Data for One Restaurant

```swift
let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)

Task {
    do {
        let googleData = try await repository.fetchGoogleData(
            for: restaurant,
            placesService: placesService
        )
        
        // Data includes:
        // - reviews
        // - photoURLs
        // - rating
        // - phone number
        // - website
        // - opening hours
        
    } catch {
        print("Error: \(error)")
    }
}
```

### Batch Import via Admin Panel

1. Open Admin Panel tab in your app
2. Tap "Fetch Google Reviews & Photos"
3. Wait for completion (takes ~1-2 min for 100 restaurants)
4. Data is cached locally + saved to Firestore

### Viewing Reviews

In `RestaurantDetailView`, tap "View Google Reviews" button:
- Shows Google rating & review count
- Displays photo gallery from Google
- Lists up to 5 recent reviews
- Shows opening hours, phone, website

---

## Caching Strategy (Saves Money!)

### Local Cache (UserDefaults)
- First fetch from Google API
- Store in UserDefaults immediately
- Reuse for 24 hours
- No cost for cached data

### Firestore Cache
- Google data saved to restaurant documents
- Syncs across devices
- Persists after app deletion
- Refresh manually when needed

### How to Clear Cache

**Via Admin Panel:**
```
Admin → Google Places Data → Clear Google Data Cache
```

**Programmatically:**
```swift
repository.clearGoogleDataCache()
```

---

## Testing

### Test with Free API Calls

1. **Start small:**
   - Test with 5-10 restaurants first
   - Check console for errors
   - Verify data appears in app

2. **Monitor usage:**
   - Google Cloud Console → APIs & Services → Dashboard
   - View request counts and costs

3. **Check logs:**
   ```
   ✅ Fetched data for: Restaurant Name
   💾 Saved Google data to Firestore
   ```

### Sample Test Code

```swift
// In AdminView or a test view
Button("Test Google API") {
    Task {
        let service = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
        let location = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        
        do {
            let data = try await service.fetchRestaurantData(
                name: "Myeongdong Kyoja",
                location: location
            )
            
            print("✅ Rating: \(data.rating ?? 0)")
            print("✅ Reviews: \(data.reviews.count)")
            print("✅ Photos: \(data.photoURLs.count)")
        } catch {
            print("❌ Error: \(error)")
        }
    }
}
```

---

## Troubleshooting

### "API key not configured"
**Solution:** Update `Config.swift` with your real API key

### "This API project is not authorized to use this API"
**Solution:** 
1. Check Places API is enabled in Google Cloud Console
2. Wait 1-2 minutes for propagation

### "The provided API key is invalid"
**Solution:**
1. Verify you copied the full key
2. Check API restrictions match your bundle ID
3. Try creating a new unrestricted key for testing

### "OVER_QUERY_LIMIT"
**Solution:**
1. You hit rate limits (too many requests too fast)
2. The app has rate limiting (0.1s delay) built in
3. Check billing is enabled

### "REQUEST_DENIED"
**Solution:**
1. Billing not enabled
2. API not enabled
3. API key restrictions too strict

### No results found
**Solution:**
1. Restaurant name might not match Google's database
2. Coordinates might be wrong
3. Try simpler search terms

---

## Best Practices

### 1. Rate Limiting
```swift
// Already implemented in GooglePlacesService
try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
```

### 2. Error Handling
```swift
do {
    let data = try await fetchGoogleData(...)
} catch GooglePlacesService.PlacesError.noAPIKey {
    // Show alert to configure API key
} catch {
    // Show retry button
}
```

### 3. Caching
- Cache aggressively (data doesn't change often)
- Only refresh when user manually requests
- Use Firestore to share cache across devices

### 4. Cost Optimization
- Import all data once
- Cache results indefinitely
- Only refresh on user request or after 30+ days
- Don't call API on every app launch

### 5. User Experience
- Show loading indicators
- Handle errors gracefully
- Provide offline fallback
- Allow manual refresh

---

## Security Recommendations

### Development
```swift
// Okay for testing
static let googlePlacesAPIKey = "AIzaSy..."
```

### Production Options

**Option 1: Environment Variables**
```swift
static let googlePlacesAPIKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] ?? ""
```

**Option 2: Info.plist**
```swift
static let googlePlacesAPIKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_API_KEY") as? String ?? ""
```

**Option 3: Firebase Functions (Best)**
- Create Cloud Function that calls Google Places API
- App calls your function (with Firebase auth)
- API key stays on server
- More secure, but more complex

---

## Alternative: Use Places SDK for iOS

Instead of REST API, you can use the native SDK:

```swift
import GooglePlaces

let placesClient = GMSPlacesClient.shared()

placesClient.fetchPlace(fromPlaceID: placeID, 
                        placeFields: [.name, .rating, .photos],
                        sessionToken: nil) { (place, error) in
    // Handle result
}
```

**Pros:**
- Native iOS integration
- Better typing

**Cons:**
- Larger binary size
- Same pricing
- More dependencies

---

## Next Steps

1. ✅ Get Google Cloud API key
2. ✅ Enable billing (for free tier)
3. ✅ Add key to `Config.swift`
4. ✅ Test with 1 restaurant
5. ⏭️ Batch import via Admin Panel
6. ⏭️ View reviews in app
7. ⏭️ Monitor costs in Google Cloud Console

---

**Need help?** Check Google's official docs: https://developers.google.com/maps/documentation/places/web-service/overview
