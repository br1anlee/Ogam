import SwiftUI

struct ContentView: View {
    @State private var searchText = ""

    let restaurants: [Restaurant] = [
        Restaurant(
            name: "Han Bat Sul Lung Tang",
            cuisine: "Korean",
            rating: 4.7,
            address: "4163 W 5th St, Los Angeles, CA",
            description: "Known for comforting seolleongtang and late-night Korean comfort food.",
            imageName: "hanbat"
        ),
        Restaurant(
            name: "Marugame Udon",
            cuisine: "Japanese",
            rating: 4.5,
            address: "700 W 7th St, Los Angeles, CA",
            description: "Fresh udon, tempura, and quick casual Japanese meals.",
            imageName: "marugame"
        ),
        Restaurant(
            name: "BCD Tofu House",
            cuisine: "Korean",
            rating: 4.6,
            address: "3575 Wilshire Blvd, Los Angeles, CA",
            description: "Popular for soft tofu soup, Korean side dishes, and casual group meals.",
            imageName: "bcd"
        )
    ]

    var filteredRestaurants: [Restaurant] {
        if searchText.isEmpty {
            return restaurants
        } else {
            return restaurants.filter { restaurant in
                restaurant.name.localizedCaseInsensitiveContains(searchText) ||
                restaurant.cuisine.localizedCaseInsensitiveContains(searchText) ||
                restaurant.address.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredRestaurants) { restaurant in
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
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Food App")
            .searchable(text: $searchText, prompt: "Search restaurants or cuisine")
        }
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

#Preview {
    ContentView()
}
