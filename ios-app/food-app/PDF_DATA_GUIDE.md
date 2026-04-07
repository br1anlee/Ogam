# PDF Restaurant Data Processing Guide

## Your Situation

You have:
- ✅ 100+ pages of Korean restaurants in PDF
- ✅ Organized by cuisine type
- ✅ Restaurant names
- ✅ Closest train station

You need:
- ❓ Full addresses
- ❓ GPS coordinates (latitude/longitude)

---

## 📋 Recommended Workflow

### Phase 1: Extract Data from PDF (30-60 min)

#### Option A: Manual Extraction (Most Accurate)

Create a Google Sheet with these columns:

| Restaurant Name | Cuisine Type | Train Station | City |
|----------------|--------------|---------------|------|
| Myeongdong Kyoja | Korean | Myeongdong Station | Seoul |
| Gwangjang Market | Street Food | Jongno 5-ga Station | Seoul |

**Steps:**
1. Create Google Sheets document
2. Copy restaurant names from PDF
3. Add cuisine type (from PDF categories)
4. Add train station name
5. Add city (Seoul, Busan, etc.)

#### Option B: PDF to Excel Conversion (Faster but needs cleanup)

**Tools:**
- Adobe Acrobat (File → Export → Spreadsheet)
- Online: https://www.ilovepdf.com/pdf_to_excel
- macOS Preview + copy/paste to Numbers/Excel

Then clean up the data in spreadsheet.

---

### Phase 2: Get Addresses & Coordinates (30-90 min)

Since you have **train station names**, we can work backwards to get coordinates!

#### Strategy 1: Use Train Station + Restaurant Name (Recommended)

Google Places API can find restaurants near train stations:

**Example search:**
```
"Myeongdong Kyoja near Myeongdong Station, Seoul"
```

This is actually **perfect** for Google Places API! It's very good at finding places near landmarks.

#### Strategy 2: Get Train Station Coordinates First

1. **Create train station lookup table:**

```csv
Station Name, Latitude, Longitude
Myeongdong Station, 37.5605, 126.9860
Gangnam Station, 37.4980, 127.0276
Hongik University Station, 37.5572, 126.9241
Jongno 5-ga Station, 37.5703, 126.9925
```

2. **Match restaurants to stations**
3. **Use station coordinates as approximate location**
4. **Let Google Places API find exact location**

---

### Phase 3: Automated Solution (Best for 100+ Restaurants)

I can create a script that:
1. Takes restaurant name + train station
2. Searches Google Places API
3. Gets exact coordinates automatically
4. Saves to JSON

**This is the BEST approach for your data!**

---

## 🚀 Automated Importer for Your PDF Data

Let me create a custom script for your specific case:

### Step 1: Prepare Simple CSV

Create a CSV file: `restaurants_from_pdf.csv`

```csv
name,cuisine,station,city
Myeongdong Kyoja,Korean,Myeongdong Station,Seoul
Gwangjang Market,Street Food,Jongno 5-ga Station,Seoul
Maple Tree House,Korean BBQ,Itaewon Station,Seoul
```

**You only need:**
- Restaurant name
- Cuisine type
- Station name
- City

**You DON'T need:**
- Addresses (Google will find them)
- Coordinates (Google will provide them)
- Descriptions (Google has them)

### Step 2: Run Automated Import

I'll create a script that:
```swift
// For each restaurant in CSV:
// 1. Search: "Restaurant Name near Station Name, City"
// 2. Get coordinates from Google
// 3. Get full address
// 4. Import to Firebase
// 5. Fetch reviews/photos
```

This does **everything automatically**!

---

## 💡 Example Processing

**Your PDF data:**
```
Korean BBQ
- Maple Tree House (Itaewon Station)
- Samwon Garden (Apgujeong Station)

Korean Soup
- Myeongdong Kyoja (Myeongdong Station)
```

**After processing:**
```json
[
  {
    "name": "Maple Tree House",
    "cuisine": "Korean BBQ",
    "station": "Itaewon Station",
    "city": "Seoul",
    "address": "80 Itaewon-ro, Yongsan-gu, Seoul", // From Google
    "latitude": 37.5342, // From Google
    "longitude": 126.9946, // From Google
    "google_rating": 4.7, // From Google
    "google_reviews": [...], // From Google
    "google_photos": [...] // From Google
  }
]
```

**Everything filled in automatically!**

---

## 🎯 Quick Start: Sample Your PDF

Let's test with 10 restaurants first:

**Give me:**
1. 10 restaurant names from your PDF
2. Their train stations
3. Cuisine type
4. City

**Example format:**
```
1. Myeongdong Kyoja - Myeongdong Station - Korean - Seoul
2. Maple Tree House - Itaewon Station - Korean BBQ - Seoul
3. ...
```

I'll:
1. Create the automated script
2. Process these 10
3. Import to Firebase
4. Fetch Google data
5. Show you the results

Then you can do the remaining 90+ yourself!

---

## 📊 Time Estimate

| Task | Time | Method |
|------|------|--------|
| Extract 10 restaurants | 5 min | Manual copy from PDF |
| Test automated import | 2 min | Run script |
| Verify results | 2 min | Check app |
| Extract remaining 90+ | 30-45 min | Copy from PDF |
| Import all | 3-5 min | Run script |
| **Total** | **~1 hour** | **Much faster than manual!** |

---

## ✅ What You Need to Do

### Option 1: Give Me 10 Samples Now (Recommended)

Share 10 restaurants in this format:
```
Restaurant Name | Cuisine | Station | City
```

I'll create the automated importer and you'll see it working in 5 minutes!

### Option 2: Extract to CSV Yourself

Create CSV with columns:
- name
- cuisine
- station
- city

Then I'll help you import it.

### Option 3: Share PDF Samples

If you can share a screenshot or sample of your PDF format, I can provide the exact extraction template.

---

## 🚀 Next Step

**What would you like to do?**

A. **Give me 10 sample restaurants now** → I'll create automated importer
B. **I'll create CSV myself** → I'll help you import
C. **Show me PDF format first** → I'll create extraction template

The automated approach will save you HOURS of work! 🎉
