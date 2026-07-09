import Foundation

struct GalleryItem: Identifiable, Codable {
    let id: UUID
    let date: Date
    let duration: TimeInterval   // targetOutputDuration (초)
}
