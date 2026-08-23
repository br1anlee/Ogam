#!/usr/bin/env python3
"""
Phase 1: Forward geocode (name/neighborhood/station → lat/lng)
Phase 2: Reverse geocode (lat/lng → real street address)

Run: python3 geocode_restaurants.py
Safe to Ctrl+C and re-run — both phases save progress independently.
"""

import json
import time
import os
import urllib.request
import urllib.parse
import sys

API_KEY       = "AIzaSyDbsvWn3QT5dbfRwgM22iYpKUFtGoBpUuo"
INPUT_FILE    = "ios-app/food-app/seoul_restaurants.json"
OUTPUT_FILE   = "ios-app/food-app/seoul_restaurants.json"
COORD_PROGRESS  = "geocode_progress.json"       # lat/lng cache from phase 1
ADDR_PROGRESS   = "address_progress.json"       # address cache from phase 2
DELAY = 0.12   # ~8 req/s — safe under Google's 50/s limit

SEOUL_LAT_MIN, SEOUL_LAT_MAX = 37.40, 37.72
SEOUL_LNG_MIN, SEOUL_LNG_MAX = 126.76, 127.28


def in_seoul(lat, lng):
    return (SEOUL_LAT_MIN <= lat <= SEOUL_LAT_MAX and
            SEOUL_LNG_MIN <= lng <= SEOUL_LNG_MAX)


def api_get(url):
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"    Request error: {e}", file=sys.stderr)
        return None


def forward_geocode(name, neighborhood, station):
    first_station = station.split(",")[0].strip() if station else ""
    queries = []
    if name and neighborhood:
        queries.append(f"{name}, {neighborhood}, 서울")
    if name and first_station:
        queries.append(f"{name}, {first_station}, 서울")
    if neighborhood:
        queries.append(f"{neighborhood}, 서울특별시")
    if first_station:
        queries.append(f"{first_station}, 서울")

    for query in queries:
        encoded = urllib.parse.quote(query)
        url = (f"https://maps.googleapis.com/maps/api/geocode/json"
               f"?address={encoded}&region=kr&language=ko&key={API_KEY}")
        data = api_get(url)
        time.sleep(DELAY)
        if data and data.get("status") == "OK" and data["results"]:
            loc = data["results"][0]["geometry"]["location"]
            lat, lng = loc["lat"], loc["lng"]
            if in_seoul(lat, lng):
                return lat, lng
    return None, None


def reverse_geocode(lat, lng):
    """Return a clean Korean street address for the given coordinates."""
    url = (f"https://maps.googleapis.com/maps/api/geocode/json"
           f"?latlng={lat},{lng}&language=ko&region=kr&key={API_KEY}")
    data = api_get(url)
    time.sleep(DELAY)
    if not data or data.get("status") != "OK":
        return None

    # Pick the most detailed result that has a street number
    for result in data["results"]:
        addr = result.get("formatted_address", "")
        # Strip country prefix "대한민국 "
        addr = addr.replace("대한민국 ", "").strip()
        # Prefer results that look like a real street address (contain a number)
        if any(c.isdigit() for c in addr):
            return addr

    # Fallback: first result formatted address
    addr = data["results"][0].get("formatted_address", "")
    return addr.replace("대한민국 ", "").strip() or None


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def main():
    if not os.path.exists(INPUT_FILE):
        print(f"❌  Input file not found: {INPUT_FILE}")
        print("    Run from ~/Desktop/food-app/")
        sys.exit(1)

    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        restaurants = json.load(f)
    print(f"Loaded {len(restaurants)} restaurants\n")

    # ── PHASE 1: Forward geocoding (coordinates) ──────────────────────────────
    coord_cache = {}
    if os.path.exists(COORD_PROGRESS):
        with open(COORD_PROGRESS, "r") as f:
            coord_cache = json.load(f)
        already = sum(1 for v in coord_cache.values() if v[0] is not None)
        print(f"Phase 1: coord cache loaded — {already}/{len(coord_cache)} already geocoded")
    else:
        print("Phase 1: forward geocoding coordinates...")

    geocoded = failed = skipped = 0
    for i, r in enumerate(restaurants):
        name         = r.get("name") or ""
        neighborhood = r.get("neighborhood") or ""
        station      = r.get("station") or ""
        key = f"{i}:{name}"

        lat = r.get("latitude")
        lng = r.get("longitude")

        if lat and lng and in_seoul(lat, lng):
            r["latitude"] = lat
            r["longitude"] = lng
            coord_cache.setdefault(key, [lat, lng])
            skipped += 1
            continue

        if key in coord_cache:
            lat, lng = coord_cache[key]
            r["latitude"] = lat
            r["longitude"] = lng
            (geocoded if lat else failed).__class__  # just a touch
            if lat:
                geocoded += 1
            else:
                failed += 1
            continue

        lat, lng = forward_geocode(name, neighborhood, station)
        r["latitude"] = lat
        r["longitude"] = lng
        coord_cache[key] = [lat, lng]

        if lat:
            geocoded += 1
            print(f"[{i+1:4d}] ✅  {name[:40]:<40} → {lat:.4f}, {lng:.4f}")
        else:
            failed += 1
            print(f"[{i+1:4d}] ❌  {name[:40]:<40} — not found")

        if (i + 1) % 50 == 0:
            save_json(COORD_PROGRESS, coord_cache)
            print(f"  ── checkpoint: {geocoded} geocoded, {failed} failed ──")

    save_json(COORD_PROGRESS, coord_cache)
    print(f"\nPhase 1 done: {geocoded} geocoded | {failed} failed | {skipped} had coords\n")

    # ── PHASE 2: Reverse geocoding (addresses) ────────────────────────────────
    addr_cache = {}
    if os.path.exists(ADDR_PROGRESS):
        with open(ADDR_PROGRESS, "r") as f:
            addr_cache = json.load(f)
        print(f"Phase 2: address cache loaded — {len(addr_cache)} already reversed")
    else:
        print("Phase 2: reverse geocoding addresses...")

    addr_done = addr_failed = addr_skipped = 0
    for i, r in enumerate(restaurants):
        name = r.get("name") or ""
        key  = f"{i}:{name}"
        lat  = r.get("latitude")
        lng  = r.get("longitude")

        # Skip restaurants without coordinates
        if not lat or not lng or not in_seoul(lat, lng):
            continue

        # Already has a real address
        existing_addr = r.get("address") or ""
        if existing_addr and len(existing_addr) > 5 and key not in addr_cache:
            addr_cache[key] = existing_addr
            addr_skipped += 1
            continue

        # Use cached address
        if key in addr_cache:
            r["address"] = addr_cache[key] or ""
            if addr_cache[key]:
                addr_done += 1
            else:
                addr_failed += 1
            continue

        # Reverse geocode
        addr = reverse_geocode(lat, lng)
        r["address"] = addr or ""
        addr_cache[key] = addr

        if addr:
            addr_done += 1
            print(f"[{i+1:4d}] 📍  {name[:30]:<30} → {addr}")
        else:
            addr_failed += 1
            print(f"[{i+1:4d}] ❌  {name[:30]:<30} — no address")

        if (i + 1) % 50 == 0:
            save_json(ADDR_PROGRESS, addr_cache)
            save_json(OUTPUT_FILE, restaurants)
            print(f"  ── checkpoint: {addr_done} addressed, {addr_failed} failed ──")

    save_json(ADDR_PROGRESS, addr_cache)
    save_json(OUTPUT_FILE, restaurants)

    total = len(restaurants)
    print(f"\n{'='*60}")
    print(f"Phase 2 done: {addr_done} addresses | {addr_failed} failed | {addr_skipped} skipped")
    print(f"Output written to: {OUTPUT_FILE}")
    print(f"\nNext steps:")
    print(f"  1. Delete existing restaurants from Firebase")
    print(f"  2. Build & run the app in Xcode")
    print(f"  3. Triple-tap Saved tab → Admin → 'Import Full Seoul Dataset'")


if __name__ == "__main__":
    main()
