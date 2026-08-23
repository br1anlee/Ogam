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
    @State private var committedRegion: MKCoordinateRegion? = nil
    @State private var hasMovedMap = false

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
                restaurant.description.localizedCaseInsensitiveContains(committedFoodQuery)
            }
        }

        // Viewport filter — skip when a text search is active (show results city-wide)
        if !hasTextQuery, let region = committedRegion {
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
                                VStack(spacing: 4) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(.red)

                                    Text(restaurant.name)
                                        .font(.caption2)
                                        .padding(6)
                                        .background(.thinMaterial)
                                        .cornerRadius(8)
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
                    HStack(spacing: 8) {
                        TextField("Korean BBQ, ramen, cafe", text: $foodQuery)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .submitLabel(.search)
                            .frame(maxWidth: .infinity)
                            .onChange(of: foodQuery) { _, newValue in
                                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                    dbSearchResults = []
                                    committedFoodQuery = ""
                                }
                            }
                            .onSubmit { runFoodSearch() }

                        TextField("Current location, ZIP, city, neighborhood", text: $locationQuery)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .submitLabel(.search)
                            .frame(maxWidth: .infinity)

                        Button("Search") {
                            runFoodSearch()
                            runLocationSearch()
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showFilterSheet = true
                        } label: {
                            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.title3)
                                .foregroundStyle(hasActiveFilters ? .blue : .primary)
                        }
                    }
                    .controlSize(.small)
                    .onSubmit {
                        runLocationSearch()
                    }
                    .padding()
                    .background(.ultraThinMaterial)

                    if hasActiveFilters {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(selectedCuisines).sorted(), id: \.self) { cuisine in
                                    FilterChipView(label: cuisine) {
                                        selectedCuisines.remove(cuisine)
                                    }
                                }

                                ForEach(Array(selectedPriceRange).sorted(), id: \.self) { price in
                                    FilterChipView(label: priceSymbol(for: price)) {
                                        selectedPriceRange.remove(price)
                                    }
                                }

                                if minimumRating > 0 {
                                    FilterChipView(label: String(format: "%.1f+ stars", minimumRating)) {
                                        minimumRating = 0
                                    }
                                }

                                if showOpenNowOnly {
                                    FilterChipView(label: "Open Now") {
                                        showOpenNowOnly = false
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
            HStack {
                Button {
                    withAnimation(.easeInOut) { isListExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(filteredRestaurants.count) Restaurants")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(isListExpanded ? "Tap to hide" : "Tap to show")
                            .font(.caption)
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
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                }

                Button {
                    withAnimation(.easeInOut) { isListExpanded.toggle() }
                } label: {
                    Image(systemName: isListExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)

            if isListExpanded {
                if filteredRestaurants.isEmpty {
                    VStack(spacing: 8) {
                        Text("No restaurants found nearby")
                            .font(.headline)
                        Text("Restaurant locations are loading in the background. Try searching by name or cuisine in the meantime.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
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
                if let coordinate = placemarks.first?.location?.coordinate {
                    searchCoordinate = coordinate
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
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

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RestaurantImageView(restaurant: restaurant, size: 88)

                VStack(alignment: .leading, spacing: 6) {
                    Text(restaurant.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(restaurant.cuisine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let rating = displayRating {
                        Text("⭐️ \(rating, specifier: "%.1f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(restaurant.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : .gray)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.clear)
        }
        .buttonStyle(.plain)
        .task {
            repository.prefetchRating(for: restaurant, placesService: placesService)
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
            VStack(alignment: .leading, spacing: 16) {
                Text(restaurant.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                HStack {
                    Text(restaurant.cuisine)
                    let displayRating = googleData?.rating ?? (restaurant.rating > 0 ? restaurant.rating : nil)
                    if let rating = displayRating {
                        Text("⭐️ \(rating, specifier: "%.1f")")
                    }
                }
                .font(.headline)
                .foregroundStyle(.secondary)

                Button {
                    openInMaps(restaurant: restaurant)
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                        Text(restaurant.address)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .padding()
                    .background(Color(.systemGray6))
                    .foregroundStyle(.blue)
                    .cornerRadius(12)
                }

                Text(restaurant.description)
                    .font(.body)

                Divider()

                if isLoading {
                    ProgressView("Loading reviews...")
                        .frame(maxWidth: .infinity)
                        .padding()
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
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadReviews()
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
