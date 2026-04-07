# Restaurant Data Template

## How to Use This Template

This spreadsheet format will help you organize your 100+ Korean restaurants before converting to JSON.

### Columns Needed (Minimum)

| Column | Required | Description | Example |
|--------|----------|-------------|---------|
| name | ✅ Yes | Restaurant name (English or Korean) | "Myeongdong Kyoja" |
| address | ✅ Yes | Full address in Korea | "29 Myeongdong 10-gil, Jung-gu, Seoul" |
| latitude | ✅ Yes | GPS latitude | 37.5632 |
| longitude | ✅ Yes | GPS longitude | 126.9850 |
| cuisine | ✅ Yes | Type of cuisine | "Korean", "Korean BBQ", "Korean Street Food" |
| description | ✅ Yes | Brief description | "Famous for kalguksu and mandu" |
| city | ⭐ Recommended | City name | "Seoul", "Busan" |
| neighborhood | ⭐ Recommended | District/area | "Myeongdong", "Gangnam", "Hongdae" |
| price_range | ⭐ Recommended | 1-4 (₩ to ₩₩₩₩) | 2 |
| tags | Optional | Comma-separated | "Noodles, Traditional, Late Night" |
| rating | Optional | Initial rating (0-5) | 4.5 |

### How to Get Coordinates

**Option 1: Google Maps (Manual)**
1. Find restaurant on Google Maps
2. Right-click the location
3. Click the coordinates that appear
4. Copy latitude and longitude

**Option 2: Bulk Geocoding (For Many Restaurants)**
- Use: https://www.doogal.co.uk/BatchGeocoding.php
- Upload addresses
- Download coordinates as CSV

**Option 3: Google Sheets Script (Automated)**
```javascript
// Add this to Google Sheets: Extensions → Apps Script
function getCoordinates() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var addresses = sheet.getRange("B2:B" + sheet.getLastRow()).getValues();
  
  for (var i = 0; i < addresses.length; i++) {
    var address = addresses[i][0];
    if (address) {
      var geocoder = Maps.newGeocoder().geocode(address);
      if (geocoder.status == "OK") {
        var lat = geocoder.results[0].geometry.location.lat;
        var lng = geocoder.results[0].geometry.location.lng;
        
        sheet.getRange(i + 2, 3).setValue(lat); // Column C
        sheet.getRange(i + 2, 4).setValue(lng); // Column D
      }
    }
    Utilities.sleep(100); // Avoid rate limits
  }
}
```

---

## Sample Spreadsheet Layout

Create a spreadsheet with these columns:

```
A: name
B: address
C: latitude
D: longitude
E: cuisine
F: description
G: city
H: neighborhood
I: price_range
J: tags
```

**Example rows:**

| name | address | latitude | longitude | cuisine | description | city | neighborhood | price_range | tags |
|------|---------|----------|-----------|---------|-------------|------|--------------|-------------|------|
| Myeongdong Kyoja | 29 Myeongdong 10-gil, Jung-gu, Seoul | 37.5632 | 126.9850 | Korean | Famous for kalguksu and mandu | Seoul | Myeongdong | 2 | Noodles, Traditional |
| Gwangjang Market | 88 Changgyeonggung-ro, Jongno-gu, Seoul | 37.5701 | 126.9997 | Korean Street Food | Historic market with bindaetteok and mayak gimbap | Seoul | Jongno | 1 | Street Food, Market, Budget Friendly |
| Jungsik | 11 Seolleung-ro 158-gil, Gangnam-gu, Seoul | 37.5254 | 127.0408 | Korean Fine Dining | Two Michelin-starred modern Korean cuisine | Seoul | Gangnam | 4 | Fine Dining, Michelin Star, Modern |

---

## Converting to JSON

### Option A: Use Online Converter (Easiest)

1. Save your spreadsheet as CSV
2. Go to: https://csvjson.com/csv2json
3. Upload CSV
4. Download JSON
5. Save as `korean_restaurants.json`

### Option B: Google Sheets to JSON (Direct)

Use this Apps Script in Google Sheets:

```javascript
function convertToJSON() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var data = sheet.getDataRange().getValues();
  var headers = data[0];
  var jsonArray = [];
  
  for (var i = 1; i < data.length; i++) {
    var row = data[i];
    var obj = {};
    
    for (var j = 0; j < headers.length; j++) {
      var header = headers[j].toString().toLowerCase().replace(/ /g, '_');
      var value = row[j];
      
      // Handle special conversions
      if (header === 'tags' && value) {
        obj[header] = value.toString().split(',').map(t => t.trim());
      } else if (header === 'latitude' || header === 'longitude' || 
                 header === 'rating' || header === 'price_range') {
        obj[header] = Number(value);
      } else {
        obj[header] = value;
      }
    }
    
    // Add defaults
    obj.image_name = "placeholder";
    
    jsonArray.push(obj);
  }
  
  Logger.log(JSON.stringify(jsonArray, null, 2));
}
```

### Option C: Manual Template (For Small Batches)

I can provide you with a template to fill in manually if you prefer.

---

## Quick Start Templates

### Template 1: Minimal (Just Essentials)

```json
[
  {
    "name": "Restaurant Name",
    "address": "Full address in Seoul",
    "latitude": 37.5665,
    "longitude": 126.9780,
    "cuisine": "Korean",
    "description": "What they're famous for",
    "image_name": "placeholder"
  }
]
```

### Template 2: Recommended (Best for Google API)

```json
[
  {
    "name": "Myeongdong Kyoja",
    "address": "29 Myeongdong 10-gil, Jung-gu, Seoul",
    "latitude": 37.5632,
    "longitude": 126.9850,
    "cuisine": "Korean",
    "description": "Famous for kalguksu (hand-cut noodles) and mandu (dumplings)",
    "city": "Seoul",
    "neighborhood": "Myeongdong",
    "price_range": 2,
    "tags": ["Noodles", "Dumplings", "Traditional"],
    "image_name": "placeholder",
    "rating": 4.5
  }
]
```

---

## What Would You Like to Do?

**Choose your approach:**

### A. **I'll create a spreadsheet myself**
→ Use the template above
→ Convert to JSON when ready
→ I'll help you import

### B. **I need help with a few restaurants first (test with 5-10)**
→ Give me restaurant names
→ I'll create JSON for testing
→ Import to verify everything works

### C. **I have the data in another format**
→ Tell me what format (PDF, Word, etc.)
→ I'll help convert it

### D. **Just give me a working example to start**
→ I'll create 10 sample Korean restaurants
→ You can test the import
→ Then replace with your real data

Which approach works best for you? 🚀
