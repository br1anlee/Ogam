# Ogam

**Ogam** (오감) means "five senses" in Korean — the experience of discovering a great meal through sight, smell, sound, taste, and touch. This iOS app helps you find Korean restaurants in Los Angeles and Seoul, with live Google ratings, photos, hours, and reviews.

---

## Features

- **Map + List discovery** — Browse restaurants on an interactive map or scroll a list. Tap "Search This Area" to filter results to the current viewport (Yelp-style).
- **Live search with autocomplete** — Type a restaurant name, cuisine, city, neighborhood, or zip code. Results update as you type, with autocomplete suggestions pulled from the full restaurant catalog.
- **Real-time open/closed status** — Each card shows whether a restaurant is open now, closing soon, closed, or opening soon based on live Google Places hours.
- **Google Places integration** — Ratings, review counts, customer photos, weekly hours, phone number, and website are fetched from Google Places and cached locally.
- **Quick filters** — One-tap filter chips for Open Now, 4.0+ rating, and price range (₩ – ₩₩₩₩).
- **Favorites** — Save restaurants to your favorites list, persisted across sessions.
- **Restaurant detail view** — Full-screen photo carousel, hours breakdown, Google reviews, address, and contact info.
- **Admin panel** — Add new restaurants directly from the app, with automatic search-token indexing and geocoding.
- **Offline support** — Restaurant data is cached locally so the list loads instantly, even without a network connection.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Maps | MapKit |
| Location | CoreLocation, CLGeocoder |
| Backend | Firebase Firestore |
| Places data | Google Places API (New) |
| Caching | UserDefaults |
| Language | Swift 5.9+ |
| Platform | iOS 17+ |

---

## Project Structure

```
food-app/
├── food-app/
│   ├── ContentView.swift          # Main map + list + search UI
│   ├── Restaurant.swift           # Data model + search token generation
│   ├── RestaurantRepository.swift # Firestore CRUD, caching, geocoding
│   ├── RestaurantRepository+GooglePlaces.swift  # Google Places fetch & cache
│   ├── AdminView.swift            # Admin panel for adding restaurants
│   ├── Config.swift               # ⚠️ Gitignored — see setup below
│   └── GoogleService-Info.plist   # ⚠️ Gitignored — see setup below
└── food-app.xcodeproj
```

---

## Setup

### Prerequisites

- Xcode 15 or later
- An Apple Developer account (free tier works for simulator)
- A Firebase project with Firestore enabled
- A Google Cloud project with the **Places API (New)** enabled

### 1. Clone the repo

```bash
git clone https://github.com/br1anlee/Ogam.git
cd Ogam/ios-app
```

### 2. Configure Firebase

1. Go to the [Firebase Console](https://console.firebase.google.com) and open your project.
2. Add an iOS app with bundle ID `Brian.food-app`.
3. Download `GoogleService-Info.plist` and place it inside `food-app/food-app/`.

> `GoogleService-Info.plist` is gitignored and must never be committed.

### 3. Configure Google Places API

1. Go to the [Google Cloud Console](https://console.cloud.google.com/apis/credentials) and create an API key.
2. Enable the **Places API (New)** for your project.
3. Restrict the key to the iOS bundle ID `Brian.food-app` to prevent unauthorized use.
4. Copy `Config.swift.template` to `Config.swift`:

```bash
cp food-app/food-app/Config.swift.template food-app/food-app/Config.swift
```

5. Open `Config.swift` and replace `YOUR_GOOGLE_PLACES_API_KEY_HERE` with your key.

> `Config.swift` is gitignored and must never be committed.

### 4. Open in Xcode

```bash
open food-app.xcodeproj
```

Build and run on a simulator or device running iOS 17+.

---

## Firestore Data Model

Each document in the `restaurants` collection has this shape:

```json
{
  "name": "Quarters Korean BBQ",
  "cuisine": "Korean BBQ",
  "address": "3465 W 6th St, Los Angeles, CA 90020",
  "city": "Los Angeles",
  "neighborhood": "Koreatown",
  "latitude": 34.0627,
  "longitude": -118.3014,
  "rating": 4.5,
  "price_range": 3,
  "phone_number": "+1 213-XXX-XXXX",
  "tags": ["KBBQ", "date night"],
  "search_tokens": ["quarters", "korean", "bbq", "koreatown", "90020"],
  "google_hours": ["Monday: 11:00 AM – 11:00 PM", "..."],
  "google_rating": 4.6,
  "google_ratings_total": 3421
}
```

### Search Tokens

The `search_tokens` field is an array of lowercase words used for Firestore `array-contains` queries. Tokens are generated from the restaurant name, cuisine, city, neighborhood, and zip code extracted from the address. Run **Admin → Reindex Search Tokens** after adding restaurants manually to Firestore to backfill this field.

---

## Admin Panel

The admin panel is accessible from the main screen. It allows you to:

- Add a new restaurant with name, address, cuisine, city, neighborhood, price range, and coordinates.
- Reindex search tokens for all existing restaurants.
- Refresh Google Hours for restaurants missing opening hours data.
- Clear the local Google data cache.

Newly added restaurants appear in search results immediately without requiring an app restart.

---

## API Key Security

Both API keys are excluded from version control via `.gitignore`. Before shipping to production:

1. **Restrict your Google Places API key** by iOS bundle ID (`Brian.food-app`) in Google Cloud Console — this prevents the key from being used by other apps even if it is discovered.
2. **Restrict your Firebase API key** in Google Cloud Console the same way. Firebase keys are semi-public by design (they are embedded in the app binary), but bundle ID restriction is the recommended defense.

---

## License

MIT
