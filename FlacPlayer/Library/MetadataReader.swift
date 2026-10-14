import AVFoundation
import UIKit

struct ReadMetadata {
    var title: String
    var artist: String
    var albumArtist: String
    var album: String
    var year: Int?
    var trackNumber: Int
    var discNumber: Int
    var duration: TimeInterval
    var artwork: UIImage?
}

enum MetadataReader {
    private static let keys = ["duration", "commonMetadata", "availableMetadataFormats"]

    static func read(url: URL) -> ReadMetadata {
        let asset = AVURLAsset(url: url)
        let gate = SignalGate()
        asset.loadValuesAsynchronously(forKeys: keys) {
            gate.signal()
        }
        _ = gate.semaphore.wait(timeout: .now() + 12)

        var title = ""
        var artist = ""
        var albumArtist = ""
        var album = ""
        var releaseYear: Int?
        var trackNumber = 0
        var discNumber = 1
        var artwork: UIImage?
        var duration: TimeInterval = 0

        if asset.statusOfValue(forKey: "duration", error: nil) == .loaded {
            let seconds = CMTimeGetSeconds(asset.duration)
            if seconds.isFinite, seconds > 0 {
                duration = seconds
            }
        }

        var items = asset.commonMetadata
        if asset.statusOfValue(forKey: "availableMetadataFormats", error: nil) == .loaded {
            for format in asset.availableMetadataFormats {
                items.append(contentsOf: asset.metadata(forFormat: format))
            }
        }

        for item in items {
            let key = keyString(item)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            let value = cleaned(item.stringValue)

            if item.commonKey == .commonKeyTitle || key == "title" || identifier.contains("title") {
                if title.isEmpty, let value, !value.isEmpty { title = value }
            } else if item.commonKey == .commonKeyArtist || key == "artist" || identifier.hasSuffix("/artist") {
                if artist.isEmpty, let value, !value.isEmpty { artist = value }
            } else if key.contains("albumartist") || key == "aart" || identifier.contains("albumartist") {
                if let value, !value.isEmpty { albumArtist = value }
            } else if item.commonKey == .commonKeyAlbumName || key == "album" || identifier.contains("album") {
                if album.isEmpty, let value, !value.isEmpty, !key.contains("artist") { album = value }
            } else if key.contains("track") || key == "trck" || identifier.contains("tracknumber") {
                if trackNumber == 0, let value, let number = leadingInt(value) { trackNumber = number }
            } else if key.contains("disc") || key == "tpos" || identifier.contains("discnumber") {
                if let value, let number = leadingInt(value), number > 0 { discNumber = number }
            } else if item.commonKey == .commonKeyCreationDate
                        || key.contains("year") || key.contains("date") || key == "tyer" || key == "tdrc" {
                if releaseYear == nil {
                    if let parsed = yearNumber(from: item) {
                        releaseYear = parsed
                    } else if let value, let parsed = yearNumber(from: value) {
                        releaseYear = parsed
                    }
                }
            }

            if artwork == nil, isArtwork(item, key: key, identifier: identifier) {
                artwork = image(from: item)
            }
        }

        if title.isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
        if artist.isEmpty { artist = "Unknown Artist" }
        if album.isEmpty { album = "Unknown Album" }
        if albumArtist.isEmpty { albumArtist = artist }

        return ReadMetadata(
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            year: releaseYear,
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: duration,
            artwork: artwork
        )
    }

    private static func keyString(_ item: AVMetadataItem) -> String {
        if let string = item.key as? String {
            return string.lowercased()
        }
        if let number = item.key as? NSNumber {
            return number.stringValue.lowercased()
        }
        return ""
    }

    private static func cleaned(_ string: String?) -> String? {
        guard var string else { return nil }
        string = string.replacingOccurrences(of: "\0", with: "")
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func leadingInt(_ string: String) -> Int? {
        let digits = string.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private static func yearNumber(from item: AVMetadataItem) -> Int? {
        if let date = item.dateValue {
            let year = Calendar.current.component(.year, from: date)
            if (1900...2100).contains(year) { return year }
        }
        if let string = item.stringValue {
            return yearNumber(from: string)
        }
        return nil
    }

    private static func yearNumber(from string: String) -> Int? {
        let digits = string.prefix { $0.isNumber || $0 == " " }
        let trimmed = digits.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4, let year = Int(trimmed.prefix(4)), (1900...2100).contains(year) else {
            return nil
        }
        return year
    }

    private static func isArtwork(_ item: AVMetadataItem, key: String, identifier: String) -> Bool {
        if item.commonKey == .commonKeyArtwork { return true }
        if key.contains("artwork") || key == "covr" || key == "apic" { return true }
        if identifier.contains("picture") || identifier.contains("artwork") || identifier.contains("covr") {
            return true
        }
        return false
    }

    private static func image(from item: AVMetadataItem) -> UIImage? {
        if item.statusOfValue(forKey: "dataValue", error: nil) != .loaded {
            let gate = SignalGate()
            item.loadValuesAsynchronously(forKeys: ["dataValue"]) {
                gate.signal()
            }
            _ = gate.semaphore.wait(timeout: .now() + 4)
        }
        if let image = item.value as? UIImage {
            return image
        }
        if let data = item.dataValue, let image = image(from: data) {
            return image
        }
        if let data = item.value as? Data, let image = image(from: data) {
            return image
        }
        if let dictionary = item.value as? [String: Any], let data = dictionary["data"] as? Data {
            return image(from: data)
        }
        return nil
    }

    private static func image(from data: Data) -> UIImage? {
        if let image = UIImage(data: data) { return image }
        if let range = data.range(of: Data([0xFF, 0xD8, 0xFF])) {
            return UIImage(data: data.subdata(in: range.lowerBound..<data.endIndex))
        }
        if let range = data.range(of: Data([0x89, 0x50, 0x4E, 0x47])) {
            return UIImage(data: data.subdata(in: range.lowerBound..<data.endIndex))
        }
        return nil
    }
}

private final class SignalGate {
    let semaphore = DispatchSemaphore(value: 0)
    private var fired = false

    func signal() {
        if fired { return }
        fired = true
        semaphore.signal()
    }
}
