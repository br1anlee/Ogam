import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var repository: RestaurantRepository
    @State private var favorites: Set<Restaurant> = []

    let favoritesKey = "favorite_restaurants"

    var body: some View {
        TabView {
            SearchMapView(
                restaurants: repository.restaurants,
                favorites: $favorites,
                onFavoritesChanged: saveFavorites
            )
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                if favorites.isEmpty {
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
                    List(Array(favorites).sorted(by: { $0.name < $1.name })) { restaurant in
                        RestaurantRowView(
                            restaurant: restaurant,
                            favorites: $favorites,
                            onFavoritesChanged: saveFavorites
                        )
                    }
                    .navigationTitle("Saved")
                }
            }
            .tabItem {
                Label("Saved", systemImage: "heart")
            }

            #if DEBUG
            AdminView()
                .tabItem {
                    Label("Admin", systemImage: "wrench.and.screwdriver")
                }
            #endif
        }
        .onAppear {
            loadFavorites()
            repository.startListening()
        }
    }

    func saveFavorites() {
        do {
            let favoritesArray = Array(favorites)
            let data = try JSONEncoder().encode(favoritesArray)
            UserDefaults.standard.set(data, forKey: favoritesKey)
        } catch {
            print("Failed to save favorites:", error)
        }
    }

    func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey) else { return }

        do {
            let decodedFavorites = try JSONDecoder().decode([Restaurant].self, from: data)
            favorites = Set(decodedFavorites)
        } catch {
            print("Failed to load favorites:", error)
        }
    }
}

struct SearchMapView: View {
    let restaurants: [Restaurant]
    @Binding var favorites: Set<Restaurant>
    let onFavoritesChanged: () -> Void

    @StateObject private var locationManager = LocationManager()

    @State private var foodQuery = ""
    @State private var locationQuery = ""
    @State private var hasCenteredInitially = false
    @State private var selectedRestaurant: Restaurant?
    @State private var pendingSelectionID: String? = nil
    @State private var isListExpanded = true
    @State private var focusedRestaurantID: String? = nil
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0575, longitude: -118.2870),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var filteredRestaurants: [Restaurant] {
        let base = restaurants

        let foodFiltered: [Restaurant]
        if foodQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            foodFiltered = base
        } else {
            foodFiltered = base.filter { restaurant in
                restaurant.name.localizedCaseInsensitiveContains(foodQuery) ||
                restaurant.cuisine.localizedCaseInsensitiveContains(foodQuery) ||
                restaurant.address.localizedCaseInsensitiveContains(foodQuery) ||
                restaurant.description.localizedCaseInsensitiveContains(foodQuery)
            }
        }

        guard let center = coordinateForLocationQuery() else {
            return foodFiltered
        }

        return foodFiltered.filter { restaurant in
            distance(from: center, to: restaurant) <= 10000
        }
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

                        TextField("Current location, ZIP, city, neighborhood", text: $locationQuery)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .submitLabel(.search)
                            .frame(maxWidth: .infinity)

                        Button("Search") {
                            runLocationSearch()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                    .onSubmit {
                        runLocationSearch()
                    }
                    .padding()
                    .background(.ultraThinMaterial)

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
                guard let newLocation, !hasCenteredInitially else { return }

                position = .region(
                    MKCoordinateRegion(
                        center: newLocation,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                )
                hasCenteredInitially = true
            }
            .sheet(item: $selectedRestaurant) { restaurant in
                NavigationStack {
                    RestaurantDetailView(restaurant: restaurant)
                }
            }
        }
    }

    var bottomResultsPanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut) {
                    isListExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(filteredRestaurants.count) Restaurants")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(isListExpanded ? "Tap to hide" : "Tap to show")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isListExpanded ? "chevron.down" : "chevron.up")
                        .foregroundStyle(.primary)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .buttonStyle(.plain)

            if isListExpanded {
                if filteredRestaurants.isEmpty {
                    VStack(spacing: 8) {
                        Text("No results found")
                            .font(.headline)
                        Text("Try another search term or location.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filteredRestaurants) { restaurant in
                                RestaurantSheetRowView(
                                    restaurant: restaurant,
                                    favorites: $favorites,
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
                        }
                    }
                    .frame(maxHeight: 250)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 12)
        .shadow(radius: 6)
    }

    func runLocationSearch() {
        if let coordinate = coordinateForLocationQuery() {
            position = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                )
            )
        }
    }

    func recenterToUser() {
        guard let userLocation = locationManager.userLocation else { return }
        withAnimation(.easeInOut) {
            position = .region(
                MKCoordinateRegion(
                    center: userLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
        }
    }

    func centerMap(on restaurant: Restaurant) {
        position = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: restaurant.latitude, longitude: restaurant.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        )
    }

    func coordinateForLocationQuery() -> CLLocationCoordinate2D? {
        let trimmed = locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if trimmed.isEmpty || trimmed == "current location" {
            return locationManager.userLocation
        }

        switch trimmed {
        case "los angeles", "los angeles, ca":
            return CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        case "koreatown", "koreatown los angeles", "koreatown, los angeles, ca":
            return CLLocationCoordinate2D(latitude: 34.0617, longitude: -118.3009)
        case "alhambra", "alhambra, ca":
            return CLLocationCoordinate2D(latitude: 34.0953, longitude: -118.1270)
        case "culver city", "culver city, ca":
            return CLLocationCoordinate2D(latitude: 34.0211, longitude: -118.3965)
        default:
            return nil
        }
    }

    func distance(from center: CLLocationCoordinate2D, to restaurant: Restaurant) -> Double {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let restaurantLocation = CLLocation(latitude: restaurant.latitude, longitude: restaurant.longitude)
        return centerLocation.distance(from: restaurantLocation)
    }
}

struct RestaurantSheetRowView: View {
    let restaurant: Restaurant
    @Binding var favorites: Set<Restaurant>
    let onFavoritesChanged: () -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(restaurant.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipped()
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 6) {
                    Text(restaurant.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(restaurant.cuisine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("⭐️ \(restaurant.rating, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(restaurant.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: toggleFavorite) {
                    Image(systemName: favorites.contains(restaurant) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.contains(restaurant) ? .red : .gray)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.clear)
        }
        .buttonStyle(.plain)
    }

    func toggleFavorite() {
        if favorites.contains(restaurant) {
            favorites.remove(restaurant)
        } else {
            favorites.insert(restaurant)
        }
        onFavoritesChanged()
    }
}

struct RestaurantRowView: View {
    let restaurant: Restaurant
    @Binding var favorites: Set<Restaurant>
    let onFavoritesChanged: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: RestaurantDetailView(restaurant: restaurant)) {
                HStack(spacing: 12) {
                    Image(restaurant.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(restaurant.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(restaurant.cuisine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("⭐️ \(restaurant.rating, specifier: "%.1f")")
                            Text("•")
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

            Button(action: {
                toggleFavorite()
            }) {
                Image(systemName: favorites.contains(restaurant) ? "heart.fill" : "heart")
                    .foregroundStyle(favorites.contains(restaurant) ? .red : .gray)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    func toggleFavorite() {
        if favorites.contains(restaurant) {
            favorites.remove(restaurant)
        } else {
            favorites.insert(restaurant)
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
                    Text("⭐️ \(restaurant.rating, specifier: "%.1f")")
                }
                .font(.headline)
                .foregroundStyle(.secondary)

                Text(restaurant.address)
                    .font(.subheadline)

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

    func loadReviews() async {
        isLoading = true
        error = nil

        do {
            googleData = try await repository.fetchGoogleData(
                for: restaurant,
                placesService: placesService
            )
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

#Preview {
    ContentView()
}
