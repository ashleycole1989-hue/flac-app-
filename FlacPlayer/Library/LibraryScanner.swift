import Foundation
import Darwin
import os

protocol LibraryScannerDelegate: AnyObject {
    func libraryScanner(_ scanner: LibraryScanner, didUpdate albums: [Album], scanning: Bool, status: String?)
    func libraryScanner(_ scanner: LibraryScanner, didImport path: String)
}

final class LibraryScanner {
    weak var delegate: LibraryScannerDelegate?

    private let store: LibraryStore
    private let scanQueue = DispatchQueue(label: "flacplayer.scan", qos: .utility)
    private let log = Logger(subsystem: "local.flacplayer", category: "scan")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var watching = false
    private var scanning = false
    private var needsAnotherScan = false
    private var scanWork: DispatchWorkItem?

    private let audioExtensions: Set<String> = ["flac", "mp3", "m4a", "aac", "wav", "aiff", "aif", "alac", "caf"]

    init(store: LibraryStore) {
        self.store = store
    }

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var musicDirectory: URL {
        documentsURL.appendingPathComponent("Music", isDirectory: true)
    }

    func start() {
        try? FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
        scanQueue.async { [weak self] in
            guard let self else { return }
            self.startWatchingLocked()
            let cached = self.store.fetchAlbums()
            self.publish(cached, scanning: true, status: "INDEXING")
            self.scheduleScanLocked()
        }
    }

    func requestScan() {
        scanQueue.async { [weak self] in
            self?.scheduleScanLocked()
        }
    }

    func importURLs(_ urls: [URL], autoplay: Bool) {
        scanQueue.async { [weak self] in
            guard let self else { return }
            var firstPath: String?
            for url in urls {
                if let dest = self.copyIn(url), firstPath == nil {
                    firstPath = dest
                }
            }
            if autoplay, let firstPath {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.libraryScanner(self, didImport: firstPath)
                }
            }
            self.scheduleScanLocked()
        }
    }

    private func scheduleScanLocked() {
        scanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanIfNeeded()
        }
        scanWork = work
        scanQueue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func scanIfNeeded() {
        if scanning {
            needsAnotherScan = true
            return
        }
        scanning = true
        performScan()
        scanning = false
        if needsAnotherScan {
            needsAnotherScan = false
            scanIfNeeded()
        }
    }

    private func performScan() {
        let cached = store.fetchAlbums()
        publish(cached, scanning: true, status: cached.isEmpty ? "INDEXING" : nil)

        let files = collectFiles()
        let stamps = store.stamps()
        var seen = Set<String>()
        var pending: [StoredTrack] = []
        var changed = false

        for (index, file) in files.enumerated() {
            autoreleasepool {
                seen.insert(file.url.path)
                let stamp = stamps[file.url.path]
                let artworkMissing = stamp?.artworkPath.isEmpty == false
                    && !FileManager.default.fileExists(atPath: stamp?.artworkPath ?? "")
                let current = stamp != nil
                    && stamp?.fileSize == file.size
                    && abs((stamp?.mtime ?? 0) - file.mtime) < 1
                    && !artworkMissing
                if current { return }

                let meta = MetadataReader.read(url: file.url)
                let artworkPath: String
                if let image = meta.artwork {
                    let key = meta.albumArtist + "\u{1f}" + meta.album + "\u{1f}" + file.url.path
                    artworkPath = Artwork.saveJPEG(image, key: key) ?? ""
                } else {
                    artworkPath = ""
                }
                pending.append(StoredTrack(
                    path: file.url.path,
                    title: meta.title,
                    artist: meta.artist,
                    albumArtist: meta.albumArtist,
                    album: meta.album,
                    year: meta.year,
                    trackNumber: meta.trackNumber,
                    discNumber: meta.discNumber,
                    duration: meta.duration,
                    artworkPath: artworkPath,
                    fileSize: file.size,
                    mtime: file.mtime
                ))
                changed = true
            }

            if pending.count >= 8 {
                store.upsertMany(pending)
                pending.removeAll(keepingCapacity: true)
                let status = "INDEXING \(index + 1)/\(files.count)"
                publish(store.fetchAlbums(), scanning: true, status: status)
            }
        }

        if !pending.isEmpty {
            store.upsertMany(pending)
        }
        store.prune(keeping: seen)
        publish(store.fetchAlbums(), scanning: false, status: nil)
        if changed {
            log.info("Library index updated, \(files.count, privacy: .public) files")
        }
    }

    private func publish(_ albums: [Album], scanning: Bool, status: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.libraryScanner(self, didUpdate: albums, scanning: scanning, status: status)
        }
    }

    private struct ListedFile {
        var url: URL
        var size: Int64
        var mtime: TimeInterval
    }

    private func collectFiles() -> [ListedFile] {
        var files: [ListedFile] = []
        var seen = Set<String>()
        for root in roots() {
            for file in list(root) where seen.insert(file.url.path).inserted {
                files.append(file)
            }
        }
        return files
    }

    private func roots() -> [URL] {
        var roots = [documentsURL]
        let pointer = documentsURL.appendingPathComponent("library.path")
        if let text = try? String(contentsOf: pointer, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
                   isDirectory.boolValue,
                   FileManager.default.isReadableFile(atPath: trimmed) {
                    roots.append(URL(fileURLWithPath: trimmed, isDirectory: true))
                }
            }
        }
        for path in [
            "/var/mobile/Media/FlacPlayer",
            "/private/var/mobile/Media/FlacPlayer",
            "/var/jb/var/mobile/Media/FlacPlayer"
        ] {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               FileManager.default.isReadableFile(atPath: path) {
                roots.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        return roots
    }

    private func list(_ root: URL) -> [ListedFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var files: [ListedFile] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            if size <= 0 { continue }
            files.append(ListedFile(
                url: url,
                size: size,
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0
            ))
        }
        return files
    }

    private func copyIn(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let ext = url.pathExtension.lowercased()
        guard audioExtensions.contains(ext) else { return nil }
        let musicPath = musicDirectory.standardizedFileURL.path
        let sourcePath = url.standardizedFileURL.path
        if sourcePath.hasPrefix(musicPath) {
            return sourcePath
        }
        try? FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination.path
        } catch {
            log.error("Import failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = musicDirectory.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = musicDirectory.appendingPathComponent(next)
            number += 1
        }
        return candidate
    }

    private func startWatchingLocked() {
        guard !watching else { return }
        watching = true
        watch(documentsURL)
        watch(musicDirectory)
    }

    private func watch(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: scanQueue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleScanLocked()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        sources.append(source)
    }
}
