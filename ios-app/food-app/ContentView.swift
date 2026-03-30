import SwiftUI
import MapKit

struct ContentView: View {
    @State private var searchText = ""
    @State private var selectedCuisine = "All"
    @State private var favorites: Set<Restaurant> = []

    let cuisineOptions = ["All", "Korean", "Japanese"]
    let favoritesKey = "favorite_restaurants"

    let restaurants: [Restaurant] = [
        Restaurant(
            id: "hanbat",
            name: "Han Bat Sul Lung Tang",
            cuisine: "Korean",
            rating: 4.7,
            address: "4163 W 5th St, Los Angeles, CA",
            description: "Known for comforting seolleongtang and late-night Korean comfort food.",
            imageName: "hanbat",
            latitude: 34.0637,
            longitude: -118.3067
        ),
        Restaurant(
            id: "marugame",
            name: "Marugame Udon",
            cuisine: "Japanese",
            rating: 4.5,
            address: "700 W 7th St, Los Angeles, CA",
            description: "Fresh udon, tempura, and quick casual Japanese meals.",
            imageName: "marugame",
            latitude: 34.0489,
            longitude: -118.2572
        ),
        Restaurant(
            id: "bcd",
            name: "BCD Tofu House",
            cuisine: "Korean",
            rating: 4.6,
            address: "3575 Wilshire Blvd, Los Angeles, CA",
            description: "Popular for soft tofu soup, Korean side dishes, and casual group meals.",
            imageName: "bcd",
            latitude: 34.0615,
            longitude: -118.3009
        )
    ]
    var filteredRestaurants: [Restaurant] {
        restaurants.filter { restaurant in
            let matchesCuisine = selectedCuisine == "All" || restaurant.cuisine == selectedCuisine
            let matchesSearch =
                searchText.isEmpty ||
                restaurant.name.localizedCaseInsensitiveContains(searchText) ||
                restaurant.cuisine.localizedCaseInsensitiveContains(searchText) ||
                restaurant.address.localizedCaseInsensitiveContains(searchText)

            return matchesCuisine && matchesSearch
        }
    }

    var body: some View {
        TabView {
            NavigationStack {
                VStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(cuisineOptions, id: \.self) { cuisine in
                                Button(action: {
                                    selectedCuisine = cuisine
                                }) {
                                    Text(cuisine)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedCuisine == cuisine ? Color.blue : Color.gray.opacity(0.2))
                                        .foregroundColor(selectedCuisine == cuisine ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 8)

                    List(filteredRestaurants) { restaurant in
                        RestaurantRowView(
                            restaurant: restaurant,
                            favorites: $favorites,
                            onFavoritesChanged: saveFavorites
                        )
                    }
                    .listStyle(.plain)
                }
                .navigationTitle("Food App")
                .searchable(text: $searchText, prompt: "Search restaurants or cuisine")
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            NavigationStack {
                RestaurantMapView(restaurants: restaurants)
                    .navigationTitle("Map")
            }
            .tabItem {
                Label("Map", systemImage: "map")
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
        }
        .onAppear {
            loadFavorites()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(restaurant.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(16)

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
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RestaurantMapView: View {
    let restaurants: [Restaurant]

    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0575, longitude: -118.2870),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var body: some View {
        Map(position: $position) {
            ForEach(restaurants) { restaurant in
                Annotation(restaurant.name, coordinate: CLLocationCoordinate2D(latitude: restaurant.latitude, longitude: restaurant.longitude)) {
                    NavigationLink(destination: RestaurantDetailView(restaurant: restaurant)) {
                        VStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)

                        }
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    ContentView()
}
