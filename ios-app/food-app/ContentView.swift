import SwiftUI
import MapKit
import CoreLocation

func priceSymbol(for level: Int) -> String {
    let symbol: String
    switch Locale.current.currency?.identifier {
    case "KRW": symbol = "₩"
    case "JPY": symbol = "¥"
    case "EUR": symbol = "€"
    case "GBP": symbol = "£"
    default:    symbol = "$"
    }
    return String(repeating: symbol, count: level)
}

private enum OpenStatus {
    case openNow(closingAt: Date)
    case closingSoon(minutes: Int, closingAt: Date)
    case closed(openingAt: Date)
    case closedToday                          // closed the entire day — no opening time
    case openingSoon(minutes: Int, openingAt: Date)
    case unknown
}

/// Parses a single time-range string like "10:00 AM – 10:00 PM", "10 AM – 9 PM", or "10:00 AM - 10:00 PM".
private func parseOpenStatus(from hours: String) -> OpenStatus {
    // Accept both en dash (Google) and regular hyphen
    let raw = hours.replacingOccurrences(of: "\u{2013}", with: "-")
    let parts = raw.components(separatedBy: " - ")
    guard parts.count == 2 else { return .unknown }

    // Try "h:mm a" first, then "h a" (Google omits ":00" for round hours like "11 AM")
    func parseTime(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "h:mm a"
        if let d = fmt.date(from: s) { return d }
        fmt.dateFormat = "h a"
        return fmt.date(from: s)
    }

    guard let openTime = parseTime(parts[0]),
          let closeTime = parseTime(parts[1]) else {
        return .unknown
    }

    let now = Date()
    let cal = Calendar.current

    let todayOpen = cal.date(bySettingHour: cal.component(.hour, from: openTime),
                             minute: cal.component(.minute, from: openTime),
                             second: 0, of: now)!
    var todayClose = cal.date(bySettingHour: cal.component(.hour, from: closeTime),
                              minute: cal.component(.minute, from: closeTime),
                              second: 0, of: now)!

    // Handle hours that wrap past midnight (e.g. 6 PM – 2 AM)
    if todayClose <= todayOpen {
        todayClose = cal.date(byAdding: .day, value: 1, to: todayClose)!
    }

    let minutesToClose = Int(todayClose.timeIntervalSince(now) / 60)
    let minutesToOpen  = Int(todayOpen.timeIntervalSince(now) / 60)

    if now >= todayOpen && now < todayClose {
        return minutesToClose <= 60
            ? .closingSoon(minutes: minutesToClose, closingAt: todayClose)
            : .openNow(closingAt: todayClose)
    } else if minutesToOpen > 0 && minutesToOpen <= 60 {
        return .openingSoon(minutes: minutesToOpen, openingAt: todayOpen)
    } else {
        return .closed(openingAt: todayOpen)
    }
}

/// Parses Google Places weekday_text array (e.g. ["Monday: 10:00 AM – 10:00 PM", ...])
/// and returns the open status for the current day.
private func parseOpenStatusFromWeekly(_ days: [String]) -> OpenStatus {
    let cal = Calendar.current
    let todayName = cal.weekdaySymbols[cal.component(.weekday, from: Date()) - 1]

    guard let todayEntry = days.first(where: { $0.hasPrefix(todayName) }),
          let colonRange = todayEntry.range(of: ": ") else { return .unknown }

    let timeRange = String(todayEntry[colonRange.upperBound...])

    switch timeRange.lowercased() {
    case "closed":          return .closedToday
    case "open 24 hours":   return .openNow(closingAt: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)))
    default:                return parseOpenStatus(from: timeRange)
    }
}

private func formatHourTime(_ date: Date) -> String {
    let mins = Calendar.current.component(.minute, from: date)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = mins == 0 ? "h a" : "h:mm a"
    return fmt.string(from: date)
}

enum SortOption: String, CaseIterable, Identifiable {
    case rating = "Rating"
    case distance = "Distance"
    case priceLowToHigh = "Price"
    case alphabetical = "A-Z"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .rating: return "star.fill"
        case .distance: return "location.fill"
        case .priceLowToHigh: return "dollarsign.circle"
        case .alphabetical: return "textformat.abc"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var repository: RestaurantRepository
    @State private var favoriteIDs: Set<String> = []
    @State private var showAdmin = false

    let favoritesKey = "favorite_restaurants"

    var savedRestaurants: [Restaurant] {
        repository.restaurants
            .filter { favoriteIDs.contains($0.id ?? "") }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        TabView {
            SearchMapView(
                restaurants: repository.restaurants,
                favoriteIDs: $favoriteIDs,
                onFavoritesChanged: saveFavorites,
                onLoadMore: { await repository.loadMore() }
            )
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                if savedRestaurants.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart")
                            .font(.system(size: 40))
                            .foregroundStyle(.gray)

                        Text("No saved restaurants yet")
                            .font(.headline)

                        Text("Tap the heart on a restaurant to save it.")
                            .foregroundStyle(.secondary)
                    }
                    .navigationTitle("Saved")
                } else {
                    List(savedRestaurants) { restaurant in
                        RestaurantRowView(
                            restaurant: restaurant,
                            favoriteIDs: $favoriteIDs,
                            onFavoritesChanged: saveFavorites
                        )
                    }
                    .navigationTitle("Saved")
                }
            }
            .onTapGesture(count: 3) {
                withAnimation { showAdmin.toggle() }
            }
            .tabItem {
                Label("Saved", systemImage: "heart")
            }

            if showAdmin {
                AdminView()
                    .tabItem {
                        Label("Admin", systemImage: "wrench.and.screwdriver")
                    }
            }
        }
        .onAppear {
            loadFavorites()
            repository.startListening()
        }
    }

    func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: favoritesKey)
    }

    func loadFavorites() {
        let stored = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        favoriteIDs = Set(stored)
    }
}

struct SearchMapView: View {
    let restaurants: [Restaurant]
    @Binding var favoriteIDs: Set<String>
    let onFavoritesChanged: () -> Void
    let onLoadMore: () async -> Void

    @EnvironmentObject private var repository: RestaurantRepository
    @StateObject private var locationManager = LocationManager()

    @State private var foodQuery = ""
    @State private var committedFoodQuery = ""
    @State private var locationQuery = ""
    @State private var dbSearchResults: [Restaurant] = []
    @State private var isSearchingDB = false
    @State private var hasCenteredInitially = false
    @State private var selectedRestaurant: Restaurant?
    @State private var pendingSelectionID: String? = nil
    @State private var isListExpanded = false
    @State private var focusedRestaurantID: String? = nil

    // Live search / autocomplete
    @FocusState private var foodFieldFocused: Bool
    @State private var autocompleteItems: [String] = []
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    // Filter state
    @State private var showFilterSheet = false
    @State private var selectedCuisines: Set<String> = []
    @State private var selectedPriceRange: Set<Int> = []
    @State private var minimumRating: Double = 0.0
    @State private var showOpenNowOnly = false
    @State private var sortOption: SortOption = .rating
    @State private var searchCoordinate: CLLocationCoordinate2D?

    // Viewport-based filtering (Yelp-style)
    @State private var visibleRegion: MKCoordinateRegion? = nil
    @State private var hasMovedMap = false

    // Initialized to match the default map position so the list is always viewport-filtered,
    // even before the user's location is known.
    @State private var committedRegion: MKCoordinateRegion? = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.0575, longitude: -118.2870),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0575, longitude: -118.2870),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var availableCuisines: [String] {
        var counts: [String: Int] = [:]
        for r in restaurants { counts[r.cuisine, default: 0] += 1 }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(12)
            .map(\.key)
            .sorted()
    }

    var hasActiveFilters: Bool {
        !selectedCuisines.isEmpty ||
        !selectedPriceRange.isEmpty ||
        minimumRating > 0 ||
        showOpenNowOnly
    }

    var filteredRestaurants: [Restaurant] {
        let hasTextQuery = !committedFoodQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Merge in-memory restaurants with any DB search results (deduplicated by ID)
        var pool = restaurants
        if hasTextQuery && !dbSearchResults.isEmpty {
            let existingIDs = Set(restaurants.compactMap(\.id))
            let newFromDB = dbSearchResults.filter { !existingIDs.contains($0.id ?? "") }
            pool = restaurants + newFromDB
        }

        var results = pool

        // Text search — contains match across in-memory pool
        if hasTextQuery {
            results = results.filter { restaurant in
                restaurant.name.localizedCaseInsensitiveContains(committedFoodQuery) ||
                restaurant.cuisine.localizedCaseInsensitiveContains(committedFoodQuery) ||
                restaurant.address.localizedCaseInsensitiveContains(committedFoodQuery) ||
                restaurant.description.localizedCaseInsensitiveContains(committedFoodQuery) ||
                (restaurant.city?.localizedCaseInsensitiveContains(committedFoodQuery) ?? false) ||
                (restaurant.neighborhood?.localizedCaseInsensitiveContains(committedFoodQuery) ?? false)
            }
        }

        // Viewport filter — skip when a text search is active (show results city-wide).
        // Fall back to visibleRegion so the list always reflects what's on screen.
        if !hasTextQuery, let region = committedRegion ?? visibleRegion {
            let latMin = region.center.latitude  - region.span.latitudeDelta  / 2
            let latMax = region.center.latitude  + region.span.latitudeDelta  / 2
            let lngMin = region.center.longitude - region.span.longitudeDelta / 2
            let lngMax = region.center.longitude + region.span.longitudeDelta / 2
            results = results.filter { r in
                guard r.latitude != 0 || r.longitude != 0 else { return false }
                return r.latitude  >= latMin && r.latitude  <= latMax &&
                       r.longitude >= lngMin && r.longitude <= lngMax
            }
        }

        // Cuisine filter
        if !selectedCuisines.isEmpty {
            results = results.filter { selectedCuisines.contains($0.cuisine) }
        }

        // Price range filter
        if !selectedPriceRange.isEmpty {
            results = results.filter { restaurant in
                guard let price = restaurant.priceRange else { return false }
                return selectedPriceRange.contains(price)
            }
        }

        // Minimum rating filter
        if minimumRating > 0 {
            results = results.filter { $0.rating >= minimumRating }
        }

        // Open now filter
        if showOpenNowOnly {
            results = results.filter { $0.isOpenNow == true }
        }

        // Sort
        switch sortOption {
        case .rating:
            results.sort { $0.rating > $1.rating }
        case .distance:
            if let userLoc = locationManager.userLocation {
                results.sort { distance(from: userLoc, to: $0) < distance(from: userLoc, to: $1) }
            }
        case .priceLowToHigh:
            results.sort { ($0.priceRange ?? 5) < ($1.priceRange ?? 5) }
        case .alphabetical:
            results.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }

        return results
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()

                    ForEach(filteredRestaurants) { restaurant in
                        Annotation("", coordinate: CLLocationCoordinate2D(latitude: restaurant.latitude, longitude: restaurant.longitude)) {
                            Button {
                                selectedRestaurant = restaurant
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 28, height: 28)
                                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                                    Image(systemName: "fork.knife")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    let newRegion = context.region
                    visibleRegion = newRegion
                    guard let committed = committedRegion else { return }
                    let latDiff = abs(newRegion.center.latitude  - committed.center.latitude)
                    let lngDiff = abs(newRegion.center.longitude - committed.center.longitude)
                    let spanDiff = abs(newRegion.span.latitudeDelta - committed.span.latitudeDelta)
                    if latDiff > 0.005 || lngDiff > 0.005 || spanDiff > 0.01 {
                        withAnimation(.easeInOut) { hasMovedMap = true }
                    }
                }
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button {
                        recenterToUser()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 96)
                    .accessibilityLabel("Recenter on your location")
                }

                VStack(spacing: 0) {
                    // ── Yelp-style stacked search bars ──────────────────
                    VStack(spacing: 0) {
                        // Food field
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Restaurants, food, cuisines", text: $foodQuery)
                                .focused($foodFieldFocused)
                                .submitLabel(.search)
                                .onChange(of: foodQuery) { _, newValue in
                                    handleFoodQueryChange(newValue)
                                }
                                .onSubmit {
                                    foodFieldFocused = false
                                    autocompleteItems = []
                                    runFoodSearch()
                                    runLocationSearch()
                                }
                            if !foodQuery.isEmpty {
                                Button {
                                    foodQuery = ""
                                    dbSearchResults = []
                                    committedFoodQuery = ""
                                    autocompleteItems = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color(.systemGray3))
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 38)

                        // Location field
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                            TextField("City, neighborhood, ZIP", text: $locationQuery)
                                .submitLabel(.search)
                                .onSubmit {
                                    foodFieldFocused = false
                                    autocompleteItems = []
                                    runFoodSearch()
                                    runLocationSearch()
                                }
                            if !locationQuery.isEmpty {
                                Button {
                                    locationQuery = ""
                                    committedRegion = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color(.systemGray3))
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Autocomplete dropdown
                    if foodFieldFocused && !autocompleteItems.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(autocompleteItems, id: \.self) { item in
                                Button {
                                    foodQuery = item
                                    handleFoodQueryChange(item)
                                    foodFieldFocused = false
                                    autocompleteItems = []
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(item)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                }
                                if item != autocompleteItems.last {
                                    Divider().padding(.leading, 40)
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    }

                    // ── Quick filter pills (always visible) ─────────────
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            QuickFilterChip(
                                label: "Open Now",
                                icon: "clock.fill",
                                isActive: showOpenNowOnly
                            ) { showOpenNowOnly.toggle() }

                            QuickFilterChip(
                                label: "4.0+",
                                icon: "star.fill",
                                isActive: minimumRating >= 4.0
                            ) { minimumRating = minimumRating >= 4.0 ? 0 : 4.0 }

                            ForEach(1...4, id: \.self) { price in
                                QuickFilterChip(
                                    label: priceSymbol(for: price),
                                    isActive: selectedPriceRange.contains(price)
                                ) {
                                    if selectedPriceRange.contains(price) {
                                        selectedPriceRange.remove(price)
                                    } else {
                                        selectedPriceRange.insert(price)
                                    }
                                }
                            }

                            Button {
                                showFilterSheet = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "line.3.horizontal.decrease")
                                    Text("More")
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(hasActiveFilters ? Color.blue : Color(.systemGray5))
                                .foregroundStyle(hasActiveFilters ? .white : .primary)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(.ultraThinMaterial)

                    // Active filter chips strip (selected cuisines + clear all)
                    if !selectedCuisines.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(selectedCuisines).sorted(), id: \.self) { cuisine in
                                    FilterChipView(label: cuisine) {
                                        selectedCuisines.remove(cuisine)
                                    }
                                }
                                Button("Clear All") {
                                    selectedCuisines.removeAll()
                                    selectedPriceRange.removeAll()
                                    minimumRating = 0
                                    showOpenNowOnly = false
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                        }
                        .background(.ultraThinMaterial)
                    }

                    if hasMovedMap {
                        HStack {
                            Button {
                                withAnimation(.easeInOut) {
                                    committedRegion = visibleRegion
                                    hasMovedMap = false
                                }
                            } label: {
                                Label("Search this area", systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .shadow(radius: 3)
                            }
                            .transition(.scale.combined(with: .opacity))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .animation(.easeInOut, value: hasMovedMap)
                    }

                    Spacer()
                }

                bottomResultsPanel
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                locationManager.requestLocationAccess()
            }
            .onReceive(locationManager.$userLocation) { newLocation in
                guard let newLocation else { return }
                if !hasCenteredInitially {
                    let region = MKCoordinateRegion(
                        center: newLocation,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                    position = .region(region)
                    hasCenteredInitially = true
                    searchCoordinate = newLocation
                    committedRegion = region
                    visibleRegion = region
                    hasMovedMap = false
                    // Auto-fill location field with current city name
                    if locationQuery.isEmpty {
                        Task {
                            let cl = CLLocation(latitude: newLocation.latitude, longitude: newLocation.longitude)
                            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(cl).first,
                               let city = placemark.locality {
                                locationQuery = city
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedRestaurant) { restaurant in
                NavigationStack {
                    RestaurantDetailView(restaurant: restaurant)
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheetView(
                    selectedCuisines: $selectedCuisines,
                    selectedPriceRange: $selectedPriceRange,
                    minimumRating: $minimumRating,
                    showOpenNowOnly: $showOpenNowOnly,
                    cuisines: availableCuisines
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    var bottomResultsPanel: some View {
        VStack(spacing: 0) {
            // Header: drag handle + count/sort row — swipe down to collapse, swipe up to expand
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                HStack(alignment: .center) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isListExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(filteredRestaurants.count)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("places")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: isListExpanded ? "chevron.down" : "chevron.up")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Menu {
                        ForEach(SortOption.allCases) { option in
                            Button {
                                sortOption = option
                            } label: {
                                if sortOption == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: sortOption.systemImage)
                            Text(sortOption.rawValue)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(.ultraThinMaterial)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        let dy = value.translation.height
                        if isListExpanded && dy > 50 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isListExpanded = false
                            }
                        } else if !isListExpanded && dy < -50 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isListExpanded = true
                            }
                        }
                    }
            )

            if isListExpanded {
                if filteredRestaurants.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "fork.knife.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No restaurants found")
                            .font(.headline)
                        Text("Try moving the map or searching by name.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(.ultraThinMaterial)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredRestaurants) { restaurant in
                                RestaurantSheetRowView(
                                    restaurant: restaurant,
                                    favoriteIDs: $favoriteIDs,
                                    onFavoritesChanged: onFavoritesChanged,
                                    onSelect: {
                                        if pendingSelectionID == restaurant.id {
                                            selectedRestaurant = restaurant
                                            pendingSelectionID = nil
                                        } else {
                                            centerMap(on: restaurant)
                                            pendingSelectionID = restaurant.id
                                        }
                                    }
                                )
                                Divider()
                            }

                            if filteredRestaurants.count >= 10 {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { await onLoadMore() }
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 520)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 12)
        .shadow(radius: 6)
    }

    func runFoodSearch() {
        let query = foodQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            dbSearchResults = []
            committedFoodQuery = ""
            return
        }
        committedFoodQuery = query
        withAnimation(.easeInOut) { isListExpanded = true }
        isSearchingDB = true
        Task {
            dbSearchResults = await repository.searchByName(query)
            isSearchingDB = false
        }
    }

    func handleFoodQueryChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            dbSearchResults = []
            committedFoodQuery = ""
            autocompleteItems = []
            searchDebounceTask?.cancel()
            return
        }
        // Update in-memory filter immediately (fast, no network)
        committedFoodQuery = trimmed
        withAnimation(.easeInOut) { isListExpanded = true }
        // Refresh autocomplete from in-memory restaurants
        autocompleteItems = generateAutocomplete(for: trimmed)
        // Debounce Firestore search to avoid firing on every keystroke
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            isSearchingDB = true
            dbSearchResults = await repository.searchByName(trimmed)
            isSearchingDB = false
        }
    }

    func generateAutocomplete(for query: String) -> [String] {
        let q = query.lowercased()
        var suggestions: [String] = []
        // Matching cuisine types first
        let cuisines = Set(restaurants.map(\.cuisine))
            .filter { $0.localizedCaseInsensitiveContains(q) }
            .sorted()
        suggestions.append(contentsOf: cuisines.prefix(3))
        // Then matching restaurant names
        let names = restaurants
            .filter { $0.name.localizedCaseInsensitiveContains(q) }
            .prefix(4)
            .map(\.name)
        suggestions.append(contentsOf: names)
        // Deduplicate preserving order, cap at 5
        var seen = Set<String>()
        return suggestions.filter { seen.insert($0).inserted }.prefix(5).map { $0 }
    }

    func runLocationSearch() {
        let trimmed = locationQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed.lowercased() == "current location" {
            searchCoordinate = locationManager.userLocation
            if let coord = searchCoordinate {
                let region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                position = .region(region)
                committedRegion = region
                visibleRegion = region
                hasMovedMap = false
            }
            return
        }

        Task {
            do {
                let placemarks = try await CLGeocoder().geocodeAddressString(trimmed)
                if let placemark = placemarks.first, let coordinate = placemark.location?.coordinate {
                    searchCoordinate = coordinate
                    // Use a span wide enough to cover a full city (~18km), shrink for neighborhoods
                    let isNeighborhood = placemark.subLocality != nil
                    let delta = isNeighborhood ? 0.08 : 0.18
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
                    )
                    position = .region(region)
                    committedRegion = region
                    visibleRegion = region
                    hasMovedMap = false
                }
            } catch {
                print("Geocoding failed: \(error.localizedDescription)")
            }
        }
    }

    func recenterToUser() {
        guard let userLocation = locationManager.userLocation else { return }
        let region = MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        withAnimation(.easeInOut) { position = .region(region) }
        committedRegion = region
        visibleRegion = region
        hasMovedMap = false
    }

    func centerMap(on restaurant: Restaurant) {
        position = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: restaurant.latitude, longitude: restaurant.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        )
    }

    func distance(from center: CLLocationCoordinate2D, to restaurant: Restaurant) -> Double {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let restaurantLocation = CLLocation(latitude: restaurant.latitude, longitude: restaurant.longitude)
        return centerLocation.distance(from: restaurantLocation)
    }
}

struct RestaurantSheetRowView: View {
    let restaurant: Restaurant
    @Binding var favoriteIDs: Set<String>
    let onFavoritesChanged: () -> Void
    let onSelect: () -> Void

    @EnvironmentObject private var repository: RestaurantRepository
    private let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)

    private var isFavorite: Bool { favoriteIDs.contains(restaurant.id ?? "") }
    private var displayRating: Double? {
        if let id = restaurant.id, let cached = repository.googleRatings[id] { return cached }
        return restaurant.rating > 0 ? restaurant.rating : nil
    }
    private var resolvedOpenStatus: OpenStatus {
        let id = restaurant.id ?? ""
        // 1. Firestore-persisted Google hours (available after first Google data fetch)
        if let weeklyHours = restaurant.googleHours, !weeklyHours.isEmpty {
            return parseOpenStatusFromWeekly(weeklyHours)
        }
        // 2. In-memory cache from this session's prefetchRating
        if let weeklyHours = repository.googleHoursCache[id], !weeklyHours.isEmpty {
            return parseOpenStatusFromWeekly(weeklyHours)
        }
        // 3. Admin-added restaurants store hours as a comma-joined weekday string
        if let hours = restaurant.hours, !hours.isEmpty {
            let dayEntries = hours.components(separatedBy: ", ").filter { $0.contains(":") && $0.contains(" ") }
            if !dayEntries.isEmpty { return parseOpenStatusFromWeekly(dayEntries) }
            return parseOpenStatus(from: hours)
        }
        return .unknown
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                RestaurantImageView(restaurant: restaurant, size: 80)

                VStack(alignment: .leading, spacing: 5) {
                    Text(restaurant.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(restaurant.cuisine)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .clipShape(Capsule())

                        if let price = restaurant.priceRange {
                            Text(priceSymbol(for: price))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let rating = displayRating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }

                    openStatusView(for: resolvedOpenStatus)

                    Text(restaurant.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : Color(.systemGray3))
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .task {
            repository.prefetchRating(for: restaurant, placesService: placesService)
        }
    }

    @ViewBuilder
    private func openStatusView(for status: OpenStatus) -> some View {
        switch status {
        case .openNow(let closingAt):
            HStack(spacing: 3) {
                Text("Open Now")
                    .foregroundStyle(.green)
                Text("· Closes \(formatHourTime(closingAt))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
        case .closingSoon(let mins, let closingAt):
            HStack(spacing: 3) {
                Text("Closing in \(mins) min")
                    .foregroundStyle(.orange)
                Text("· \(formatHourTime(closingAt))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
        case .closed(let openingAt):
            HStack(spacing: 3) {
                Text("Closed")
                    .foregroundStyle(.red)
                Text("· Opens \(formatHourTime(openingAt))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
        case .openingSoon(let mins, let openingAt):
            HStack(spacing: 3) {
                Text("Opens in \(mins) min")
                    .foregroundStyle(.orange)
                Text("· \(formatHourTime(openingAt))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
        case .closedToday:
            Text("Closed Today")
                .foregroundStyle(.red)
                .font(.caption.weight(.medium))
        case .unknown:
            EmptyView()
        }
    }

    func toggleFavorite() {
        guard let id = restaurant.id else { return }
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        onFavoritesChanged()
    }
}

struct RestaurantRowView: View {
    let restaurant: Restaurant
    @Binding var favoriteIDs: Set<String>
    let onFavoritesChanged: () -> Void

    @EnvironmentObject private var repository: RestaurantRepository

    private var isFavorite: Bool { favoriteIDs.contains(restaurant.id ?? "") }
    private var displayRating: Double? {
        if let id = restaurant.id, let cached = repository.googleRatings[id] { return cached }
        return restaurant.rating > 0 ? restaurant.rating : nil
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: RestaurantDetailView(restaurant: restaurant)) {
                HStack(spacing: 12) {
                    RestaurantImageView(restaurant: restaurant, size: 80)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(restaurant.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(restaurant.cuisine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            if let rating = displayRating {
                                Text("⭐️ \(rating, specifier: "%.1f")")
                                Text("•")
                            }
                            Text(restaurant.address)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.gray)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? .red : .gray)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    func toggleFavorite() {
        guard let id = restaurant.id else { return }
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        onFavoritesChanged()
    }
}

struct RestaurantDetailView: View {
    let restaurant: Restaurant
    @EnvironmentObject var repository: RestaurantRepository

    @State private var googleData: RestaurantGoogleData?
    @State private var isLoading = true
    @State private var error: Error?

    private let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                heroImageView
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()

                VStack(alignment: .leading, spacing: 18) {
                    // Name
                    Text(restaurant.name)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    // Cuisine + rating + price row
                    HStack(spacing: 8) {
                        Text(restaurant.cuisine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange)
                            .clipShape(Capsule())

                        let displayRating = googleData?.rating ?? (restaurant.rating > 0 ? restaurant.rating : nil)
                        if let rating = displayRating {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }

                        if let price = restaurant.priceRange {
                            Text(priceSymbol(for: price))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Address
                    Button { openInMaps(restaurant: restaurant) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 18)
                            Text(restaurant.address)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.systemGray6))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)

                    // Description — skip auto-generated placeholder text
                    let desc = restaurant.description
                    if !desc.isEmpty && !desc.hasPrefix("\(restaurant.name) —") {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Google data
                    if isLoading {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Loading reviews…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 28)
                    } else if let error = error {
                        ErrorView(error: error, retry: loadReviews)
                    } else if let data = googleData {
                        ReviewsContentView(restaurant: restaurant, googleData: data)
                    } else {
                        EmptyReviewsView()
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadReviews() }
    }

    @ViewBuilder
    private var heroImageView: some View {
        if let urlString = restaurant.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                placeholderHero
            }
        } else {
            placeholderHero
        }
    }

    private var placeholderHero: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.45), Color.red.opacity(0.25)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "fork.knife")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    func openInMaps(restaurant: Restaurant) {
        let coordinate = CLLocationCoordinate2D(
            latitude: restaurant.latitude,
            longitude: restaurant.longitude
        )
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = restaurant.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    func loadReviews() async {
        isLoading = true
        error = nil

        do {
            googleData = try await repository.fetchGoogleData(
                for: restaurant,
                placesService: placesService
            )
            if let id = restaurant.id, let rating = googleData?.rating {
                repository.googleRatings[id] = rating
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

struct RestaurantImageView: View {
    let restaurant: Restaurant
    let size: CGFloat

    var body: some View {
        Group {
            if UIImage(named: restaurant.imageName) != nil {
                Image(restaurant.imageName)
                    .resizable()
                    .scaledToFill()
            } else if let url = googlePhotoURL ?? remoteImageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderView
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .cornerRadius(12)
    }

    private var remoteImageURL: URL? {
        guard let urlString = restaurant.imageURL else { return nil }
        return URL(string: urlString)
    }

    private var googlePhotoURL: URL? {
        guard let id = restaurant.id,
              let data = UserDefaults.standard.data(forKey: "google_data_\(id)"),
              let googleData = try? JSONDecoder().decode(RestaurantGoogleData.self, from: data),
              let firstURL = googleData.photoURLs.first else {
            return nil
        }
        return firstURL
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundStyle(.gray)
            }
    }
}

struct QuickFilterChip: View {
    let label: String
    var icon: String? = nil
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                }
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(isActive ? Color.blue : Color(.systemGray5))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

struct FilterChipView: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.blue.opacity(0.15))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
    }
}

struct FilterSheetView: View {
    @Binding var selectedCuisines: Set<String>
    @Binding var selectedPriceRange: Set<Int>
    @Binding var minimumRating: Double
    @Binding var showOpenNowOnly: Bool
    let cuisines: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuisine Type") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                        ForEach(cuisines, id: \.self) { cuisine in
                            Button {
                                if selectedCuisines.contains(cuisine) {
                                    selectedCuisines.remove(cuisine)
                                } else {
                                    selectedCuisines.insert(cuisine)
                                }
                            } label: {
                                Text(cuisine)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        selectedCuisines.contains(cuisine)
                                            ? Color.blue
                                            : Color(.systemGray5)
                                    )
                                    .foregroundStyle(
                                        selectedCuisines.contains(cuisine)
                                            ? .white
                                            : .primary
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Price Range") {
                    HStack(spacing: 12) {
                        ForEach(1...4, id: \.self) { level in
                            Button {
                                if selectedPriceRange.contains(level) {
                                    selectedPriceRange.remove(level)
                                } else {
                                    selectedPriceRange.insert(level)
                                }
                            } label: {
                                Text(priceSymbol(for: level))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        selectedPriceRange.contains(level)
                                            ? Color.orange
                                            : Color(.systemGray5)
                                    )
                                    .foregroundStyle(
                                        selectedPriceRange.contains(level)
                                            ? .white
                                            : .primary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Minimum Rating") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(minimumRating == 0 ? "Any" : String(format: "%.1f+ stars", minimumRating))
                            .font(.headline)
                        Slider(value: $minimumRating, in: 0...5, step: 0.5)
                            .tint(.yellow)
                        HStack {
                            Text("Any")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("5.0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Open Now Only", isOn: $showOpenNowOnly)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        selectedCuisines.removeAll()
                        selectedPriceRange.removeAll()
                        minimumRating = 0
                        showOpenNowOnly = false
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(RestaurantRepository())
}
