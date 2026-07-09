import AVKit
import SwiftUI

// MARK: - GallerySheet (보관함 시트 진입점)

struct GallerySheet: View {
    @StateObject private var vm = GalleryViewModel()
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(vm.items) { item in
                                GalleryCell(item: item)
                                    .onTapGesture { vm.play(item) }
                                    .contextMenu {
                                        ShareLink(item: GalleryStore.shared.videoURL(for: item)) {
                                            Label("공유", systemImage: "square.and.arrow.up")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            vm.confirmDelete(item)
                                        } label: {
                                            Label("삭제", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("보관함")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $vm.playingItem) { item in
            InlineVideoPlayer(url: GalleryStore.shared.videoURL(for: item))
        }
        .alert("영상을 삭제하시겠습니까?", isPresented: $vm.showDeleteConfirm) {
            Button("삭제", role: .destructive) { vm.deleteConfirmed() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 작업은 되돌릴 수 없습니다.")
        }
        .onAppear { vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("저장된 타임랩스가 없습니다")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("녹화를 완료하면 여기에 보관됩니다")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - GalleryCell

private struct GalleryCell: View {
    let item: GalleryItem
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                    .aspectRatio(16 / 9, contentMode: .fit)

                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(item.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(durationLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .task { thumbnail = await GalleryStore.shared.generateThumbnail(for: item) }
    }

    private var durationLabel: String {
        let s = Int(item.duration)
        return s < 60 ? "\(s)초" : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - InlineVideoPlayer

private struct InlineVideoPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding()
            }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            p.play()
            player = p
        }
        .onDisappear { player?.pause() }
    }
}

// MARK: - GalleryViewModel

@MainActor
private final class GalleryViewModel: ObservableObject {
    @Published var items: [GalleryItem] = []
    @Published var playingItem: GalleryItem?
    @Published var showDeleteConfirm = false

    private var itemToDelete: GalleryItem?

    func load() {
        items = GalleryStore.shared.loadAll()
    }

    func play(_ item: GalleryItem) {
        playingItem = item
    }

    func confirmDelete(_ item: GalleryItem) {
        itemToDelete = item
        showDeleteConfirm = true
    }

    func deleteConfirmed() {
        guard let item = itemToDelete else { return }
        GalleryStore.shared.delete(item)
        items.removeAll { $0.id == item.id }
        itemToDelete = nil
    }
}
