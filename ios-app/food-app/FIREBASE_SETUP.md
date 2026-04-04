# Firebase Setup Instructions for Korean Restaurant App

## Step 1: Install Firebase SDK

1. **Add Firebase Package to Xcode:**
   - Open your project in Xcode
   - Go to `File` → `Add Package Dependencies...`
   - Enter this URL: `https://github.com/firebase/firebase-ios-sdk`
   - Click "Add Package"
   - Select these products:
     - `FirebaseAuth`
     - `FirebaseFirestore`
     - `FirebaseStorage`

## Step 2: Create Firebase Project

1. **Go to Firebase Console:**
   - Visit: https://console.firebase.google.com
   - Click "Add project" or use existing project
   - Name it: `korean-restaurant-app` (or your choice)

2. **Add iOS App:**
   - Click "Add app" → iOS icon
   - Enter your **Bundle ID** (find in Xcode: Target → General → Bundle Identifier)
   - Download `GoogleService-Info.plist`
   - **IMPORTANT:** Drag this file into your Xcode project root

3. **Enable Firestore:**
   - In Firebase Console, go to **Firestore Database**
   - Click "Create database"
   - Choose **Test mode** (for development)
   - Select closest region (e.g., `asia-northeast3` for Seoul)

4. **Enable Storage:**
   - Go to **Storage** in Firebase Console
   - Click "Get Started"
   - Choose **Test mode**

## Step 3: Configure Firestore Security Rules

In Firebase Console → Firestore Database → Rules, paste this:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow anyone to read restaurants and their Google data
    match /restaurants/{restaurant} {
      allow read: if true;
      allow write: if false;  // Change to true if you want users to add restaurants
    }
    
    // Optional: Store user-specific data (favorites, notes, etc.)
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Optional: User reviews (if you add this feature)
    match /user_reviews/{reviewId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && request.auth.uid == resource.data.userId;
    }
  }
}
```

**Note:** Google data (reviews, photos, ratings) will be stored as fields within restaurant documents, so no additional rules needed!

## Step 4: Configure Storage Security Rules

In Firebase Console → Storage → Rules:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /restaurants/{restaurantId}/{allPaths=**} {
      allow read: if true;
      allow write: if false;  // Change to true for user uploads
    }
  }
}
```

## Step 5: Import Your Restaurant Data

### Option A: Use the DataImporter (Recommended)

1. **Prepare your JSON file:**
   - Use `sample_restaurants.json` as a template
   - Add your 100+ Korean restaurants
   - Save it in your Xcode project

2. **Run the import:**
   ```swift
   // Add this to your ContentView onAppear or create a separate admin view
   Task {
       let importer = DataImporter()
       try await importer.importRestaurantsFromJSON(fileName: "your_restaurants")
   }
   ```

### Option B: Manual Import via Firebase Console

1. Go to Firestore Database → Start collection → `restaurants`
2. Manually add each restaurant as a document

### Option C: Use Firebase Admin SDK (Advanced)

Create a Node.js script to bulk import from CSV/Excel:

```javascript
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const restaurants = require('./restaurants.json');

async function importData() {
  for (const restaurant of restaurants) {
    await db.collection('restaurants').add(restaurant);
    console.log(`Added: ${restaurant.name}`);
  }
}

importData();
```

## Step 6: Upload Images to Firebase Storage

### Option 1: Programmatically (via DataImporter)

```swift
Task {
    let importer = DataImporter()
    await importer.uploadAllImages()
}
```

### Option 2: Manually

1. Go to Firebase Console → Storage
2. Create folder: `restaurants/{restaurant-id}/`
3. Upload images manually
4. Update Firestore documents with `image_url` field

### Option 3: Use gsutil (Command Line)

```bash
# Install Google Cloud SDK
# Then upload in bulk:
gsutil -m cp -r ./restaurant_images/* gs://your-bucket/restaurants/
```

## Step 7: Test Your Setup

1. **Run the app**
2. **Check Console for logs:**
   - `✅ Firebase configured with offline persistence`
   - `✅ Loaded X restaurants from Firestore`

3. **Try offline mode:**
   - Turn on Airplane Mode
   - App should still show cached restaurants

## Step 8: Enable Offline Persistence (Already Done!)

The `FirebaseConfig.swift` already enables this:

```swift
settings.isPersistenceEnabled = true
settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
```

## Troubleshooting

### Problem: "GoogleService-Info.plist not found"
**Solution:** Make sure you dragged the file into Xcode (not just Finder)

### Problem: "No restaurants loading"
**Solution:** 
1. Check Firebase Console → Firestore → ensure data exists
2. Check security rules allow read access
3. Check Console.app for error messages

### Problem: "Images not loading"
**Solution:**
1. Ensure `image_url` field exists in Firestore
2. Check Storage security rules
3. Verify image URLs are public

### Problem: "App crashes on launch"
**Solution:**
1. Make sure Firebase is configured in `food_appApp.swift`
2. Check that `GoogleService-Info.plist` is in target membership

## Production Checklist

Before publishing to App Store:

- [ ] Update Firestore security rules (remove `allow read: if true`)
- [ ] Update Storage security rules
- [ ] Enable App Check for abuse prevention
- [ ] Set up Firebase Analytics
- [ ] Enable crash reporting (Crashlytics)
- [ ] Review Firebase pricing (should be free for most apps)
- [ ] Add proper error handling for network failures

## Firebase Pricing (Free Tier Limits)

| Service | Free Tier | Your Usage (estimated) |
|---------|-----------|------------------------|
| Firestore Reads | 50K/day | ~1K/day (100 users × 10 reads) |
| Firestore Writes | 20K/day | ~100/day (favorites, updates) |
| Storage | 5GB total | ~500MB (100 restaurants × 5MB images) |
| Storage Downloads | 1GB/day | ~100MB/day |

**You'll easily stay within free tier!** 🎉

## Next Steps

1. ✅ Firebase is configured
2. ✅ Repository with caching created
3. ✅ Import script ready
4. ⏭️ Import your 100+ restaurants
5. ⏭️ Upload restaurant images
6. ⏭️ Test offline functionality
7. ⏭️ Add more features (filters, reviews, etc.)

Need help? Check Firebase docs: https://firebase.google.com/docs/ios/setup
