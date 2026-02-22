import SwiftUI
import AppKit

struct ContentView: View {
    private enum ChartVisualization: String, CaseIterable, Identifiable {
        case donut = "Donut"
        case galaxy = "Genre Galaxy"

        var id: String { rawValue }
    }

    @StateObject private var viewModel = LibraryViewModel()
    @State private var chartVisualization: ChartVisualization = .galaxy

    private let palette: [Color] = [
        Color(red: 0.25, green: 0.55, blue: 0.85),
        Color(red: 0.85, green: 0.45, blue: 0.35),
        Color(red: 0.45, green: 0.75, blue: 0.55),
        Color(red: 0.75, green: 0.55, blue: 0.85),
        Color(red: 0.95, green: 0.75, blue: 0.35),
        Color(red: 0.35, green: 0.65, blue: 0.75),
        Color(red: 0.8, green: 0.35, blue: 0.55),
        Color(red: 0.55, green: 0.55, blue: 0.55)
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                leftPane
                Divider()
                rightPane
            }

            Divider()

            HStack {
                Text(viewModel.status)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.isScanning {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 620)
        .toolbar {
            ToolbarItemGroup {
                Button("Scan Library") { viewModel.scanITunesLibrary() }
                    .disabled(viewModel.isScanning)
                Button("Choose Folder") { viewModel.chooseFolderAndScan() }
                    .disabled(viewModel.isScanning)
                Button("Recommend") { viewModel.recommend() }
                    .disabled(viewModel.tracks.isEmpty)
                Button("Spotify Settings") { viewModel.showSpotifySheet = true }
            }
        }
        .sheet(isPresented: $viewModel.showSpotifySheet) {
            SpotifySettingsView(viewModel: viewModel)
        }
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Library Overview")
                .font(.title2)
                .fontWeight(.semibold)

            Picker("Visualization", selection: $chartVisualization) {
                ForEach(ChartVisualization.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            let segments = viewModel.genreSlices.map { slice in
                PieChartSegment(
                    name: slice.name,
                    value: Double(slice.count),
                    color: palette[slice.colorIndex % palette.count]
                )
            }
            let totalCount = viewModel.genreSlices.reduce(0) { $0 + $1.count }
            let activeSlice = viewModel.genreSlices.first(where: { $0.name == viewModel.selectedGenre }) ?? viewModel.genreSlices.first
            let activeCount = activeSlice?.count ?? 0
            let activePercent = totalCount == 0 ? 0 : Int((Double(activeCount) / Double(totalCount) * 100).rounded())

            if chartVisualization == .donut {
                ZStack {
                    PieChart(segments: segments, selectedName: viewModel.selectedGenre) { segment in
                        viewModel.selectGenre(segment.name)
                    }
                    .frame(width: 340, height: 340)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .frame(width: 156, height: 156)

                    VStack(spacing: 4) {
                        Text(activeSlice?.name ?? "No Genre")
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text("\(activeCount) albums")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(activePercent)%")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 10)
                }
            } else {
                let galaxySegments = viewModel.genreSlices.map { slice in
                    GenreGalaxySegment(
                        name: slice.name,
                        value: Double(slice.count),
                        color: palette[slice.colorIndex % palette.count]
                    )
                }

                ZStack(alignment: .bottomLeading) {
                    GenreGalaxy(segments: galaxySegments, selectedName: viewModel.selectedGenre) { segment in
                        viewModel.selectGenre(segment.name)
                    }
                    .frame(width: 360, height: 360)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeSlice?.name ?? "No Genre")
                            .font(.headline)
                        Text("\(activeCount) albums · \(activePercent)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.genreSlices) { slice in
                    Button {
                        viewModel.selectGenre(slice.name)
                    } label: {
                        HStack {
                            Circle()
                                .fill(palette[slice.colorIndex % palette.count])
                                .frame(width: 10, height: 10)
                            Text("\(slice.name)")
                                .font(.callout)
                                .foregroundColor(.primary)
                            Spacer()
                            let percent = totalCount == 0 ? 0 : Int((Double(slice.count) / Double(totalCount) * 100).rounded())
                            Text("\(slice.count) · \(percent)%")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(minWidth: 360, maxWidth: 420, alignment: .topLeading)
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recommendations")
                    .font(.title2)
                    .fontWeight(.semibold)
                if let genre = viewModel.selectedGenre {
                    Text("• \(genre)")
                        .foregroundColor(.secondary)
                }
            }

            List(viewModel.recommendations) { recommendation in
                RecommendationRow(recommendation: recommendation)
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct RecommendationRow: View {
    let recommendation: Recommendation

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtView(recommendation: recommendation)
                .frame(width: 56, height: 56)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.headline)
                Text(recommendation.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(recommendation.source == .spotify ? "Not in your library · Spotify" : "From your library")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let url = recommendation.spotifyURL {
                Link("Open", destination: url)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AlbumArtView: View {
    let recommendation: Recommendation

    var body: some View {
        if let data = recommendation.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else if let url = recommendation.artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    PlaceholderArt()
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    PlaceholderArt()
                @unknown default:
                    PlaceholderArt()
                }
            }
        } else {
            PlaceholderArt()
        }
    }
}

private struct PlaceholderArt: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

private struct SpotifySettingsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spotify Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a Spotify app to get a Client ID and Client Secret. These are stored locally on your Mac.")
                .font(.callout)
                .foregroundColor(.secondary)

            Form {
                TextField("Client ID", text: $viewModel.spotifyClientId)
                SecureField("Client Secret", text: $viewModel.spotifyClientSecret)
            }

            HStack(spacing: 12) {
                Button("Save") {
                    viewModel.saveSpotifyCredentials()
                    dismiss()
                }
                Button("Clear") {
                    viewModel.clearSpotifyCredentials()
                }
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
