import AVFoundation
import MediaPlayer
import UIKit
import os

protocol PlaybackEngineDelegate: AnyObject {
    func engineDidUpdateTransport(_ engine: PlaybackEngine)
}

/// Core Audio playback through AVAudioEngine. iOS 11+ decodes FLAC inside AVAudioFile,
/// so the A10 uses the system decoder instead of a bundled libFLAC.
final class PlaybackEngine {
    weak var delegate: PlaybackEngineDelegate?

    private(set) var queue: [Track] = []
    private(set) var index = 0
    private(set) var transport: Transport = .idle
    private(set) var duration: TimeInterval = 0
    private(set) var lastError: String?

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var sfx = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var playerConnected = false
    private var playToken = 0
    private var originFrame: AVAudioFramePosition = 0
    private var pendingTime: TimeInterval = 0
    private var sampleRate: Double = 44100
    private var frozenElapsed: TimeInterval?
    private var playerHasBuffer = false
    private var breakSkips = 0
    private var currentFile: AVAudioFile?
    private var nowArtwork: MPMediaItemArtwork?
    private var nowArtworkPath: String?

    private let clickBuffer: AVAudioPCMBuffer?
    private let dropBuffer: AVAudioPCMBuffer?
    private let sfxFormat: AVAudioFormat?
    private let log = Logger(subsystem: "local.flacplayer", category: "audio")
    private let store: LibraryStore

    var volume: Float {
        didSet {
            let clamped = min(1, max(0, volume))
            if clamped != volume {
                volume = clamped
                return
            }
            player.volume = clamped
            UserDefaults.standard.set(clamped, forKey: Keys.volume)
        }
    }

    var currentTrack: Track? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var elapsed: TimeInterval {
        if let frozenElapsed { return frozenElapsed }
        guard sampleRate > 0 else { return 0 }
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else {
            return Double(originFrame) / sampleRate
        }
        let frame = originFrame + playerTime.sampleTime
        return min(max(0, Double(frame) / playerTime.sampleRate), max(duration, 0))
    }

    init(store: LibraryStore) {
        self.store = store
        let stored = UserDefaults.standard.object(forKey: Keys.volume) as? Float
        volume = stored ?? 1
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        sfxFormat = format
        if let format {
            clickBuffer = Self.tone(format: format, duration: 0.045, body: 1800, bodyDecay: 70, noise: 0.22, thump: 0)
            dropBuffer = Self.tone(format: format, duration: 0.16, body: 110, bodyDecay: 16, noise: 0.18, thump: 90)
        } else {
            clickBuffer = nil
            dropBuffer = nil
        }
        configureSession()
        configureGraph()
        installRemoteCommands()
        observeSession()
    }

    func cue(tracks: [Track], startingAt start: Int, elapsed: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(.main))
        invalidateBuffers()
        queue = tracks
        index = min(max(0, start), max(tracks.count - 1, 0))
        duration = currentTrack?.duration ?? 0
        sampleRate = 44100
        pendingTime = max(0, elapsed)
        frozenElapsed = pendingTime
        playerHasBuffer = false
        transport = tracks.isEmpty ? .idle : .cued
        lastError = nil
        refreshArtworkCache()
        notify()
    }

    func play(tracks: [Track], startingAt start: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        invalidateBuffers()
        queue = tracks
        index = min(max(0, start), max(tracks.count - 1, 0))
        breakSkips = 0
        startCurrent(at: 0, play: true)
    }

    func toggle() {
        dispatchPrecondition(condition: .onQueue(.main))
        switch transport {
        case .playing:
            pause()
        case .ended:
            pendingTime = 0
            frozenElapsed = 0
            startCurrent(at: 0, play: true)
        case .paused, .cued, .idle:
            resume()
        }
    }

    func pause() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard transport == .playing else { return }
        let time = elapsed
        frozenElapsed = time
        pendingTime = time
        player.pause()
        if engine.isRunning { engine.pause() }
        transport = .paused
        persist()
        notify()
    }

    func resume() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard currentTrack != nil else { return }
        if playerHasBuffer {
            do {
                if !engine.isRunning { try engine.start() }
            } catch {
                lastError = error.localizedDescription
                notify()
                return
            }
            frozenElapsed = nil
            player.play()
            transport = .playing
            notify()
            return
        }
        startCurrent(at: pendingTime, play: true)
    }

    func next() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !queue.isEmpty else { return }
        guard index + 1 < queue.count else {
            if transport == .playing { finishQueue() }
            return
        }
        index += 1
        if transport == .playing || playerHasBuffer {
            startCurrent(at: 0, play: transport == .playing)
        } else {
            duration = currentTrack?.duration ?? 0
            pendingTime = 0
            frozenElapsed = 0
            refreshArtworkCache()
            notify()
        }
    }

    func previous() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard currentTrack != nil else { return }
        if elapsed > 3 || index == 0 {
            seek(to: 0)
            return
        }
        index -= 1
        if transport == .playing || playerHasBuffer {
            startCurrent(at: 0, play: transport == .playing)
        } else {
            duration = currentTrack?.duration ?? 0
            pendingTime = 0
            frozenElapsed = 0
            transport = .cued
            refreshArtworkCache()
            notify()
        }
    }

    func seek(to time: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(.main))
        let clamped = min(max(0, time), max(duration - 0.05, 0))
        let wasPlaying = transport == .playing
        if playerHasBuffer {
            startCurrent(at: clamped, play: wasPlaying)
        } else {
            pendingTime = clamped
            frozenElapsed = clamped
            if transport == .cued || transport == .ended || transport == .idle {
                transport = currentTrack == nil ? .idle : .cued
            }
            notify()
        }
    }

    func adjustVolume(by delta: Float) {
        volume += delta
    }

    func playClick() {
        playBuffer(clickBuffer, volume: 0.42)
    }

    func playDrop() {
        playBuffer(dropBuffer, volume: 0.85)
    }

    func refreshNowPlaying() {
        publishNowPlaying()
    }

    private func startCurrent(at time: TimeInterval, play: Bool) {
        guard let track = currentTrack else {
            transport = .idle
            notify()
            return
        }
        playToken += 1
        let token = playToken
        if playerHasBuffer {
            player.stop()
        }
        playerHasBuffer = false
        currentFile = nil

        let url = URL(fileURLWithPath: track.path)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            skipBroken()
            return
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            lastError = error.localizedDescription
            log.error("Open failed: \(error.localizedDescription, privacy: .public)")
            skipBroken()
            return
        }

        let format = file.processingFormat
        sampleRate = format.sampleRate
        let length = file.length
        guard length > 0, sampleRate > 0 else {
            skipBroken()
            return
        }
        duration = Double(length) / sampleRate
        if abs(duration - track.duration) > 0.75 {
            queue[index].duration = duration
            store.updateDuration(path: track.path, duration: duration)
        }

        let start = min(max(0, AVAudioFramePosition(time * sampleRate)), max(length - 1, 0))
        let remaining = length - start
        guard remaining > 0 else {
            skipBroken()
            return
        }
        let count = AVAudioFrameCount(min(remaining, Int64(UInt32.max)))
        connect(format)
        currentFile = file

        originFrame = start
        pendingTime = Double(start) / sampleRate
        player.scheduleSegment(file, startingFrame: start, frameCount: count, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playToken == token else { return }
                self.handleSegmentEnd()
            }
        }
        playerHasBuffer = true
        breakSkips = 0
        lastError = nil
        frozenElapsed = play ? nil : pendingTime
        if play {
            do {
                if !engine.isRunning { try engine.start() }
            } catch {
                lastError = error.localizedDescription
                transport = .paused
                notify()
                return
            }
            player.play()
            transport = .playing
        } else {
            transport = .paused
        }
        refreshArtworkCache()
        persist()
        notify()
    }

    private func handleSegmentEnd() {
        guard transport == .playing else { return }
        if index + 1 < queue.count {
            index += 1
            startCurrent(at: 0, play: true)
        } else {
            finishQueue()
        }
    }

    private func finishQueue() {
        frozenElapsed = duration
        pendingTime = duration
        if playerHasBuffer {
            playToken += 1
            player.stop()
            playerHasBuffer = false
            currentFile = nil
        }
        if engine.isRunning { engine.pause() }
        transport = .ended
        persist()
        notify()
    }

    private func skipBroken() {
        breakSkips += 1
        if breakSkips > queue.count {
            lastError = "Can't play these files"
            transport = .ended
            notify()
            return
        }
        if index + 1 < queue.count {
            index += 1
            startCurrent(at: 0, play: true)
        } else {
            lastError = "Can't play this file"
            transport = .ended
            notify()
        }
    }

    private func connect(_ format: AVAudioFormat) {
        if let connectedFormat, formatsMatch(connectedFormat, format), playerConnected {
            return
        }
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        if playerConnected {
            engine.disconnectNodeOutput(player)
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        playerConnected = true
        connectedFormat = format
        player.volume = volume
        if wasRunning {
            try? engine.start()
        }
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
    }

    private func invalidateBuffers() {
        playToken += 1
        if playerHasBuffer {
            player.stop()
            playerHasBuffer = false
            currentFile = nil
        }
        if engine.isRunning { engine.pause() }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            log.error("Audio session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func configureGraph() {
        engine.attach(player)
        engine.attach(sfx)
        if let sfxFormat {
            engine.connect(sfx, to: engine.mainMixerNode, format: sfxFormat)
        }
        sfx.volume = 0.8
        player.volume = volume
        engine.prepare()
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer?, volume: Float) {
        guard let buffer else { return }
        sfx.volume = volume
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        sfx.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.transport != .playing else { return }
                if self.engine.isRunning { self.engine.pause() }
            }
        }
        if !sfx.isPlaying { sfx.play() }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(handleReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        DispatchQueue.main.async {
            if type == .began, self.transport == .playing {
            let time = self.elapsed
            self.frozenElapsed = time
            self.pendingTime = time
                self.transport = .paused
                self.notify()
            } else if type == .ended {
                let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                if options.contains(.shouldResume) {
                    self.resume()
                }
            }
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: value),
              reason == .oldDeviceUnavailable else { return }
        DispatchQueue.main.async {
            self.pause()
        }
    }

    @objc private func handleReset() {
        DispatchQueue.main.async {
            let wasPlaying = self.transport == .playing
            let time = self.elapsed
            self.engine.stop()
            self.engine = AVAudioEngine()
            self.player = AVAudioPlayerNode()
            self.sfx = AVAudioPlayerNode()
            self.playerConnected = false
            self.connectedFormat = nil
            self.playerHasBuffer = false
            self.configureSession()
            self.configureGraph()
            if self.currentTrack != nil {
                self.startCurrent(at: time, play: wasPlaying)
            }
        }
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func refreshArtworkCache() {
        let path = currentTrack?.artworkPath
        guard path != nowArtworkPath else { return }
        nowArtworkPath = path
        nowArtwork = nil
        if let path, let image = UIImage(contentsOfFile: path) {
            nowArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
    }

    private func publishNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: transport == .playing ? 1.0 : 0.0,
            MPMediaItemPropertyAlbumTrackNumber: track.trackNumber,
            MPMediaItemPropertyAlbumTrackCount: queue.count
        ]
        if let nowArtwork {
            info[MPMediaItemPropertyArtwork] = nowArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func persist() {
        guard let track = currentTrack else { return }
        let defaults = UserDefaults.standard
        defaults.set(track.path, forKey: Keys.track)
        defaults.set(elapsed, forKey: Keys.elapsed)
    }

    private func notify() {
        publishNowPlaying()
        delegate?.engineDidUpdateTransport(self)
    }

    private enum Keys {
        static let volume = "volume"
        static let track = "lastTrackPath"
        static let elapsed = "lastElapsed"
    }

    private static func tone(
        format: AVAudioFormat,
        duration: Double,
        body: Double,
        bodyDecay: Double,
        noise: Float,
        thump: Double
    ) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var state: UInt32 = 0xA5A5F00D
        let rate = format.sampleRate
        for index in 0..<Int(frames) {
            let time = Double(index) / rate
            state = state &* 1664525 &+ 1013904223
            let white = Float(Int32(bitPattern: state)) / Float(Int32.max)
            let env = exp(-time * bodyDecay)
            let sine = sin(2 * Double.pi * body * time)
            let thumpWave = thump > 0 ? sin(2 * Double.pi * thump * time) * exp(-time * 22) : 0
            let mixed = Float(sine) * Float(env) * 0.55 + white * noise * Float(env) + Float(thumpWave) * 0.7
            samples[index] = max(-1, min(1, mixed))
        }
        return buffer
    }
}
