import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var repository: RestaurantRepository
    @State private var favorites: Set<String> = []  // Now stores restaurant IDs

    let favoritesKey = "favorite_restaurants"

    var favoriteRestaurants: [Restaurant] {
        repository.restaurants.filter { restaurant in
            guard let id = restaurant.id else { return false }
            return favorites.contains(id)
        }
    }

    var body: some View {
        TabView {
            SearchMapView(
                favorites: $favorites,
                onFavoritesChanged: saveFavorites
            )
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                if favoriteRestaurants.isEmpty {
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
                    List(favoriteRestaurants.sorted(by: { $0.name < $1.name })) { restaurant in
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
        }
        .onAppear {
            loadFavorites()
            // Start listening to Firestore updates
            repository.startListening()
        }
        .onDisappear {
            repository.stopListening()
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
            let decodedFavorites = try JSONDecoder().decode([String].self, from: data)
            favorites = Set(decodedFavorites)
        } catch {
            print("Failed to load favorites:", error)
        }
    }
}

struct SearchMapView: View {
    @EnvironmentObject var repository: RestaurantRepository
    @Binding var favorites: Set<String>
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
            center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780), // Seoul, Korea
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var filteredRestaurants: [Restaurant] {
        let base = repository.restaurants

        let foodFiltered: [Restaurant]
        if foodQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            foodFiltered = base
        } else {
            foodFiltered = repository.searchByText(foodQuery)
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

        // Korean cities and neighborhoods
        switch trimmed {
        case "seoul", "서울":
            return CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        case "gangnam", "강남":
            return CLLocationCoordinate2D(latitude: 37.4979, longitude: 127.0276)
        case "hongdae", "홍대":
            return CLLocationCoordinate2D(latitude: 37.5563, longitude: 126.9236)
        case "itaewon", "이태원":
            return CLLocationCoordinate2D(latitude: 37.5346, longitude: 126.9946)
        case "myeongdong", "명동":
            return CLLocationCoordinate2D(latitude: 37.5636, longitude: 126.9826)
        case "busan", "부산":
            return CLLocationCoordinate2D(latitude: 35.1796, longitude: 129.0756)
        case "incheon", "인천":
            return CLLocationCoordinate2D(latitude: 37.4563, longitude: 126.7052)
        case "daegu", "대구":
            return CLLocationCoordinate2D(latitude: 35.8714, longitude: 128.6014)
        case "daejeon", "대전":
            return CLLocationCoordinate2D(latitude: 36.3504, longitude: 127.3845)
        case "gwangju", "광주":
            return CLLocationCoordinate2D(latitude: 35.1595, longitude: 126.8526)
        case "jeonju", "전주":
            return CLLocationCoordinate2D(latitude: 35.8242, longitude: 127.1480)
        // Keep LA locations for backward compatibility
        case "los angeles", "los angeles, ca":
            return CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        case "koreatown", "koreatown los angeles", "koreatown, los angeles, ca":
            return CLLocationCoordinate2D(latitude: 34.0617, longitude: -118.3009)
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
    @Binding var favorites: Set<String>
    let onFavoritesChanged: () -> Void
    let onSelect: () -> Void
    
    var isFavorite: Bool {
        guard let id = restaurant.id else { return false }
        return favorites.contains(id)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Use AsyncImage for Firebase Storage URLs
                if let imageURL = restaurant.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 88, height: 88)
                    .clipped()
                    .cornerRadius(12)
                } else {
                    // Fallback to local image
                    Image(restaurant.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipped()
                        .cornerRadius(12)
                }

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
    }

    func toggleFavorite() {
        guard let id = restaurant.id else { return }
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        onFavoritesChanged()
    }
}

struct RestaurantRowView: View {
    let restaurant: Restaurant
    @Binding var favorites: Set<String>
    let onFavoritesChanged: () -> Void
    
    var isFavorite: Bool {
        guard let id = restaurant.id else { return false }
        return favorites.contains(id)
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: RestaurantDetailView(restaurant: restaurant)) {
                HStack(spacing: 12) {
                    // Use AsyncImage for Firebase Storage URLs
                    if let imageURL = restaurant.imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(12)
                    } else {
                        // Fallback to local image
                        Image(restaurant.imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(12)
                    }

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
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }

        onFavoritesChanged()
    }
}

struct RestaurantDetailView: View {
    let restaurant: Restaurant

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Use AsyncImage for Firebase Storage URLs
                if let imageURL = restaurant.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(16)
                } else {
                    // Fallback to local image
                    Image(restaurant.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(16)
                }

                Text(restaurant.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                HStack {
                    Text(restaurant.cuisine)
                    Text("⭐️ \(restaurant.rating, specifier: "%.1f")")
                    
                    if let priceRange = restaurant.priceRange {
                        Text(String(repeating: "₩", count: priceRange))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.headline)
                .foregroundStyle(.secondary)

                Text(restaurant.address)
                    .font(.subheadline)
                
                if let phoneNumber = restaurant.phoneNumber {
                    Link(phoneNumber, destination: URL(string: "tel:\(phoneNumber)")!)
                        .font(.subheadline)
                }
                
                if let hours = restaurant.hours {
                    HStack {
                        Image(systemName: "clock")
                        Text(hours)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Text(restaurant.description)
                    .font(.body)
                
                if let tags = restaurant.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(16)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}
