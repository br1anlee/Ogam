# Quick Start: Import from Your PDF

## ✅ Compilation Errors Fixed

I've fixed all the errors:
- Added `import CoreLocation` to RestaurantRepository+GooglePlaces
- Changed `db` from `private` to internal (accessible in extensions)
- Fixed dictionary type casting for Google data

Your project should now compile! 🎉

---

## 🚀 How to Import Your PDF Restaurant Data

### What You Have:
- Restaurant names
- Train station locations
- Cuisine categories

### What You Get Automatically:
- ✅ Full addresses (from Google)
- ✅ GPS coordinates (from Google)
- ✅ Reviews (from Google)
- ✅ Photos (from Google)
- ✅ Phone numbers (from Google)
- ✅ Hours (from Google)
- ✅ Ratings (from Google)

---

## 📝 Step 1: Create CSV from Your PDF

Create a file called `restaurants_from_pdf.csv`:

```csv
name,cuisine,station,city
Myeongdong Kyoja,Korean,Myeongdong Station,Seoul
Gwangjang Market,Korean Street Food,Jongno 5-ga Station,Seoul
Maple Tree House,Korean BBQ,Itaewon Station,Seoul
Tosokchon,Korean Soup,Gyeongbokgung Station,Seoul
Jungsik,Korean Fine Dining,Gangnam Station,Seoul
Noryangjin Fish Market,Korean Seafood,Noryangjin Station,Seoul
Hanilkwan,Korean Traditional,Yongsan Station,Seoul
Balwoo Gongyang,Temple Food,Anguk Station,Seoul
Mingles,Modern Korean,Gangnam Station,Seoul
Samwon Garden,Korean BBQ,Apgujeong Station,Seoul
```

**Just 4 columns needed!**
- name
- cuisine  
- station
- city

---

## 🎯 Step 2: Add CSV to Your Xcode Project

1. Save the CSV file
2. Drag it into your Xcode project
3. Make sure "Copy items if needed" is checked
4. Add to target

---

## 🚀 Step 3: Run the Import

### Option A: Via Admin Panel (Easiest)

Add this to your `AdminView.swift`:

```swift
Section("PDF Import") {
    Button {
        importFromPDF()
    } label: {
        HStack {
            Image(systemName: "doc.text")
            Text("Import from PDF CSV")
            Spacer()
            if isImporting {
                ProgressView()
            }
        }
    }
    .disabled(isImporting)
}

// Add this function
func importFromPDF() {
    isImporting = true
    
    Task {
        do {
            let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
            let importer = PDFRestaurantImporter(placesService: placesService)
            
            try await importer.importFromCSV(fileName: "restaurants_from_pdf")
            
            await MainActor.run {
                alertMessage = "Successfully imported restaurants from PDF!"
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
```

### Option B: Programmatically

```swift
Task {
    let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
    let importer = PDFRestaurantImporter(placesService: placesService)
    
    try await importer.importFromCSV(fileName: "restaurants_from_pdf")
}
```

---

## 📊 What Happens

For each restaurant:

1. **Search Google:** `"Myeongdong Kyoja near Myeongdong Station, Seoul"`
2. **Get Place ID:** Google identifies the restaurant
3. **Fetch Details:**
   - Address: "29 Myeongdong 10-gil, Jung-gu, Seoul"
   - Coordinates: 37.5632, 126.9850
   - Rating: 4.6
   - Reviews: 5 recent reviews
   - Photos: Up to 10 photos
   - Phone: "02-776-5348"
   - Hours: "10:30 AM - 9:00 PM"
4. **Save to Firestore:** Complete restaurant document
5. **Cache Locally:** For offline use

**All automatically!**

---

## 🎬 Live Example

**Your CSV:**
```csv
name,cuisine,station,city
Myeongdong Kyoja,Korean,Myeongdong Station,Seoul
```

**Console output:**
```
🔍 Searching Google for: Myeongdong Kyoja near Myeongdong Station, Seoul
   Found Place ID: ChIJ...
   💾 Saved to Firestore with ID: abc123
   🌟 Saved Google reviews & photos
✅ [1/1] Imported: Myeongdong Kyoja

📊 Import Summary:
   ✅ Imported: 1
   ❌ Failed: 0
   📈 Success rate: 100%
```

**Result in Firestore:**
```json
{
  "name": "Myeongdong Kyoja",
  "cuisine": "Korean",
  "address": "29 Myeongdong 10-gil, Jung-gu, Seoul",
  "latitude": 37.5632,
  "longitude": 126.9850,
  "rating": 4.6,
  "city": "Seoul",
  "neighborhood": "Myeongdong",
  "google_rating": 4.6,
  "google_reviews": [...],
  "google_photos": [...],
  "google_phone": "02-776-5348"
}
```

---

## 💰 Cost Estimate

For 100 restaurants:
```
Find Place:    100 × $0.017 = $1.70
Place Details: 100 × $0.017 = $1.70
Photos:        500 × $0.007 = $3.50
──────────────────────────────
Total:                    ~$7.00
Free tier:          $200/month
Your cost:               $0.00 ✅
```

---

## ⏱️ Time Estimate

- Extract 100 restaurants from PDF → CSV: **30-45 minutes**
- Import & process: **3-5 minutes**
- Total: **~45 minutes** for all 100+ restaurants!

---

## 🎯 Your Action Items

1. **Create CSV file** from your PDF:
   ```csv
   name,cuisine,station,city
   Restaurant 1,Cuisine,Station,Seoul
   Restaurant 2,Cuisine,Station,Seoul
   ...
   ```

2. **Add to Xcode project**

3. **Run import** (via Admin Panel or code)

4. **Watch it work!** 🎉

---

## 📋 Supported Stations (Built-in)

The importer knows these Seoul stations:
- Myeongdong Station
- Gangnam Station
- Hongdae/Hongik University Station
- Itaewon Station
- Jongno 5-ga Station
- Dongdaemun Station
- Apgujeong Station
- Sinchon Station
- Yeouido Station
- Seoul Station
- Gwanghwamun Station

**Don't see your station?** No problem! The Google search still works - it just uses city center as backup.

---

## 🆘 Need Help?

**Want to test with 10 restaurants first?**

Give me:
```
1. Restaurant Name - Station - Cuisine
2. Restaurant Name - Station - Cuisine
...
```

I'll create the CSV for you to test!

**Ready to proceed?** Create your CSV and run the import! 🚀
