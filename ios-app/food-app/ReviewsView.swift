import SwiftUI

/// View to display Google Reviews for a restaurant
struct ReviewsView: View {
    let restaurant: Restaurant
    @EnvironmentObject var repository: RestaurantRepository
    
    @State private var googleData: RestaurantGoogleData?
    @State private var isLoading = true
    @State private var error: Error?
    
    // Initialize with your API key
    private let placesService = GooglePlacesService(apiKey: Config.googlePlacesAPIKey)
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        .navigationTitle("Reviews")
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

struct ReviewsContentView: View {
    let restaurant: Restaurant
    let googleData: RestaurantGoogleData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Overall Rating Summary
            RatingSummaryView(googleData: googleData)
            
            Divider()
            
            // Photo Gallery
            if !googleData.photoURLs.isEmpty {
                PhotoGalleryView(photoURLs: googleData.photoURLs)
                Divider()
            }
            
            // Reviews List
            VStack(alignment: .leading, spacing: 16) {
                Text("Reviews")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if googleData.reviews.isEmpty {
                    Text("No reviews available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(googleData.reviews) { review in
                        ReviewCardView(review: review)
                        
                        if review.id != googleData.reviews.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct RatingSummaryView: View {
    let googleData: RestaurantGoogleData
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", googleData.rating ?? 0))
                            .font(.system(size: 48, weight: .bold))
                        
                        Image(systemName: "star.fill")
                            .font(.title)
                            .foregroundStyle(.yellow)
                    }
                    
                    if let total = googleData.userRatingsTotal {
                        Text("\(total) reviews")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Price Level
                if let priceLevel = googleData.priceLevel {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(priceSymbol(for: priceLevel))
                            .font(.title2)
                            .foregroundStyle(.orange)
                        
                        Text("Price Level")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Website Link
            if let website = googleData.website, let url = URL(string: website) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Visit Website")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .cornerRadius(12)
                }
            }
            
            // Phone Number
            if let phone = googleData.phoneNumber {
                Link(destination: URL(string: "tel:\(phone)")!) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text(phone)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .cornerRadius(12)
                }
            }
            
            // Opening Hours
            if let hours = googleData.openingHours {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(hours, id: \.self) { dayHours in
                            Text(dayHours)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "clock")
                        Text("Opening Hours")
                        Spacer()
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
}

struct PhotoGalleryView: View {
    let photoURLs: [URL]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photos from Google")
                .font(.title2)
                .fontWeight(.bold)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(photoURLs, id: \.absoluteString) { photoURL in
                        AsyncImage(url: photoURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .overlay {
                                    ProgressView()
                                }
                        }
                        .frame(width: 280, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

struct ReviewCardView: View {
    let review: GoogleReview
    @State private var isExpanded = false
    
    var shouldTruncate: Bool {
        review.text.count > 200
    }
    
    var displayText: String {
        if shouldTruncate && !isExpanded {
            return String(review.text.prefix(200)) + "..."
        }
        return review.text
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author Info
            HStack(spacing: 12) {
                if let photoURL = review.authorPhotoURL, let url = URL(string: photoURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.gray)
                            }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.gray)
                        }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < review.rating ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(index < review.rating ? .yellow : .gray)
                        }
                        
                        Text("•")
                            .foregroundStyle(.secondary)
                        
                        Text(review.relativeTimeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Review Text
            Text(displayText)
                .font(.body)
                .lineLimit(isExpanded ? nil : 6)
            
            // Read More Button
            if shouldTruncate {
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show Less" : "Read More")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EmptyReviewsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.bubble")
                .font(.system(size: 60))
                .foregroundStyle(.gray)
            
            Text("No Reviews Available")
                .font(.headline)
            
            Text("This restaurant doesn't have Google reviews yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct ErrorView: View {
    let error: Error
    let retry: () async -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("Failed to Load Reviews")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task {
                    await retry()
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    NavigationStack {
        ReviewsView(restaurant: Restaurant(
            name: "Sample Restaurant",
            cuisine: "Korean",
            rating: 4.5,
            address: "123 Main St",
            description: "Great food",
            imageName: "sample",
            latitude: 37.5665,
            longitude: 126.9780
        ))
        .environmentObject(RestaurantRepository())
    }
}
