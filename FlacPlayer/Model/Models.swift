import Foundation

struct Track: Equatable, Hashable {
    var id: Int64
    var path: String
    var title: String
    var artist: String
    var albumArtist: String
    var album: String
    var year: Int?
    var trackNumber: Int
    var discNumber: Int
    var duration: TimeInterval
    var artworkPath: String?

    var url: URL { URL(fileURLWithPath: path) }
}

struct Album: Equatable, Hashable {
    var id: String
    var title: String
    var artist: String
    var year: Int?
    var tracks: [Track]

    var artworkPath: String? {
        tracks.lazy.compactMap(\.artworkPath).first
    }
}

enum Transport: Equatable {
    case idle
    case cued
    case paused
    case playing
    case ended
}

enum TimeFormat {
    static func string(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
