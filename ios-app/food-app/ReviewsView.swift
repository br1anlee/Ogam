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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Reviews")
                        .font(.title2.weight(.bold))
                    if !googleData.reviews.isEmpty {
                        Text("(\(googleData.reviews.count))")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                if googleData.reviews.isEmpty {
                    Text("No reviews available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    ForEach(googleData.reviews) { review in
                        ReviewCardView(review: review)
                    }
                }
            }
        }
    }
}

struct RatingSummaryView: View {
    let googleData: RestaurantGoogleData

    var body: some View {
        VStack(spacing: 16) {
            // Rating row
            if let rating = googleData.rating {
                HStack(alignment: .center, spacing: 12) {
                    // Big score
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 42, weight: .bold))

                    VStack(alignment: .leading, spacing: 4) {
                        // Visual stars
                        HStack(spacing: 3) {
                            ForEach(0..<5) { i in
                                Image(systemName: starIcon(for: i, rating: rating))
                                    .font(.subheadline)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        // Review count
                        if let total = googleData.userRatingsTotal {
                            Text("from \(total.formatted()) Google reviews")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let priceLevel = googleData.priceLevel {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(priceSymbol(for: priceLevel))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text("Price Level")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Action buttons — side by side
            HStack(spacing: 10) {
                if let website = googleData.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Label("Website", systemImage: "globe")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(14)
                    }
                }
                if let phone = googleData.phoneNumber, let url = URL(string: "tel:\(phone)") {
                    Link(destination: url) {
                        Label("Call", systemImage: "phone.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.green.opacity(0.1))
                            .foregroundStyle(.green)
                            .cornerRadius(14)
                    }
                }
            }

            // Opening hours collapsible
            if let hours = googleData.openingHours {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(hours, id: \.self) { day in
                            Text(day)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text("Opening Hours")
                        Spacer()
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding(14)
                .background(Color(.systemGray6))
                .cornerRadius(14)
            }
        }
    }
}

private func starIcon(for index: Int, rating: Double) -> String {
    let threshold = Double(index) + 0.5
    if rating >= Double(index + 1) { return "star.fill" }
    if rating >= threshold { return "star.leadinghalf.filled" }
    return "star"
}

struct PhotoGalleryView: View {
    let photoURLs: [URL]
    @State private var selectedPhotoIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.title2.weight(.bold))
                Text("(\(photoURLs.count))")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            // Yelp-style: large left photo + two stacked right thumbnails
            HStack(spacing: 3) {
                // Large featured photo
                photoCell(index: 0)
                    .frame(maxWidth: .infinity)

                if photoURLs.count > 1 {
                    VStack(spacing: 3) {
                        photoCell(index: 1)

                        ZStack {
                            photoCell(index: min(2, photoURLs.count - 1))

                            // "+X more" overlay on the third slot if there are extra photos
                            if photoURLs.count > 3 {
                                Rectangle()
                                    .fill(.black.opacity(0.52))
                                Text("+\(photoURLs.count - 2) more")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedPhotoIndex = photoURLs.count > 3 ? 2 : min(2, photoURLs.count - 1) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .fullScreenCover(item: Binding(
            get: { selectedPhotoIndex.map { PhotoSelection(index: $0) } },
            set: { selectedPhotoIndex = $0?.index }
        )) { selection in
            PhotoFullScreenView(photoURLs: photoURLs, initialIndex: selection.index)
        }
    }

    @ViewBuilder
    private func photoCell(index: Int) -> some View {
        if index < photoURLs.count {
            AsyncImage(url: photoURLs[index]) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color(.systemGray5)).overlay { ProgressView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { selectedPhotoIndex = index }
        } else {
            Rectangle().fill(Color(.systemGray5))
        }
    }
}

private struct PhotoSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

struct PhotoFullScreenView: View {
    let photoURLs: [URL]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(photoURLs: [URL], initialIndex: Int) {
        self.photoURLs = photoURLs
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(photoURLs.indices, id: \.self) { index in
                    AsyncImage(url: photoURLs[index]) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(20)
            }
        }
        .overlay(alignment: .bottom) {
            Text("\(currentIndex + 1) / \(photoURLs.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
                .padding(.bottom, 48)
        }
    }
}

struct ReviewCardView: View {
    let review: GoogleReview
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // Avatar
                Group {
                    if let urlStr = review.authorPhotoURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            avatarPlaceholder
                        }
                    } else {
                        avatarPlaceholder
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(review.authorName)
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < review.rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(i < review.rating ? .yellow : Color(.systemGray4))
                        }
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(review.relativeTimeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Text(review.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 4)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)

            if review.text.count > 200 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Show less" : "Read more")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(.systemGray4))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
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
