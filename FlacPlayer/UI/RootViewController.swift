import UIKit
import UniformTypeIdentifiers

final class RootViewController: UIViewController, LibraryScannerDelegate, PlaybackEngineDelegate, ClickWheelDelegate, UIDocumentPickerDelegate {
    private let scanner: LibraryScanner
    private let engine: PlaybackEngine
    private let haptics = Haptics()

    private let backdrop = CAGradientLayer()
    private let grain = UIImageView(image: Artwork.noise)
    private let stage = VinylStageView()
    private let chrome = PlaybackChromeView()
    private let coverFlow = CoverFlowView()
    private let wheel = ClickWheelView()
    private let volumeHUD = VolumeHUD()
    private let indexingLabel = UILabel()
    private let tickProxy = TickProxy()
    private var tickLink: CADisplayLink?

    private var albums: [Album] = []
    private var mode: Mode = .playback
    private var displayedTrackPath: String?
    private var didRestore = false
    private var pendingPlayPath: String?
    private var foreground = true

    init(scanner: LibraryScanner, engine: PlaybackEngine) {
        self.scanner = scanner
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
        scanner.delegate = self
        engine.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        tickLink?.invalidate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Theme.background
        backdrop.type = .radial
        backdrop.colors = [Theme.backgroundLift.cgColor, Theme.background.cgColor]
        backdrop.startPoint = CGPoint(x: 0.5, y: 0.28)
        backdrop.endPoint = CGPoint(x: 1.15, y: 1.05)
        view.layer.addSublayer(backdrop)

        grain.alpha = 0.05
        grain.contentMode = .scaleToFill
        grain.isUserInteractionEnabled = false
        view.addSubview(grain)

        indexingLabel.font = Theme.sans(11, .semibold)
        indexingLabel.textColor = Theme.muted
        indexingLabel.isHidden = true
        indexingLabel.isUserInteractionEnabled = false

        coverFlow.alpha = 0
        coverFlow.isUserInteractionEnabled = false
        wheel.delegate = self
        wheel.setBrowsing(false)
        wheel.setPlaying(false)
        chrome.onSeek = { [weak self] time in
            self?.engine.seek(to: time)
        }
        chrome.onAdd = { [weak self] in
            self?.presentFolderPicker()
        }
        coverFlow.onAdd = { [weak self] in
            self?.presentFolderPicker()
        }
        coverFlow.onSelect = { [weak self] in
            self?.selectCenteredAlbum()
        }

        for item in [stage, chrome, coverFlow, wheel, volumeHUD, indexingLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        grain.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            grain.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grain.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grain.topAnchor.constraint(equalTo: view.topAnchor),
            grain.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            wheel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wheel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            wheel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.62),
            wheel.heightAnchor.constraint(equalTo: wheel.widthAnchor),

            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
            chrome.bottomAnchor.constraint(equalTo: wheel.topAnchor, constant: -6),
            chrome.heightAnchor.constraint(equalToConstant: 92),

            stage.topAnchor.constraint(equalTo: view.topAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: chrome.topAnchor, constant: -4),

            coverFlow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            coverFlow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coverFlow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            coverFlow.bottomAnchor.constraint(equalTo: wheel.topAnchor, constant: -8),

            volumeHUD.centerYAnchor.constraint(equalTo: wheel.centerYAnchor),
            volumeHUD.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            volumeHUD.widthAnchor.constraint(equalToConstant: 6),
            volumeHUD.heightAnchor.constraint(equalToConstant: 110),

            indexingLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            indexingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        stage.setCover(nil)
        haptics.prepare()

        tickProxy.owner = self
        let link = CADisplayLink(target: tickProxy, selector: #selector(TickProxy.tick))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        link.isPaused = true
        tickLink = link

        NotificationCenter.default.addObserver(self, selector: #selector(resignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        scanner.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
    }

    func importExternal(_ urls: [URL]) {
        scanner.importURLs(urls, autoplay: true)
    }

    func libraryScanner(_ scanner: LibraryScanner, didUpdate albums: [Album], scanning: Bool, status: String?) {
        let wasEmpty = self.albums.isEmpty
        self.albums = albums
        guard isViewLoaded else { return }
        coverFlow.setAlbums(albums)
        indexingLabel.text = status
        indexingLabel.isHidden = status == nil
        tryRestore(scanning: scanning)
        consumePendingImport()
        if albums.isEmpty, engine.currentTrack == nil, pendingPlayPath == nil {
            showLibrary(animated: false)
        } else if wasEmpty, !albums.isEmpty, engine.currentTrack == nil, mode == .playback, pendingPlayPath == nil {
            showLibrary(animated: true)
        }
    }

    func libraryScanner(_ scanner: LibraryScanner, didImport path: String) {
        pendingPlayPath = path
    }

    func engineDidUpdateTransport(_ engine: PlaybackEngine) {
        guard isViewLoaded else { return }
        if let track = engine.currentTrack {
            chrome.showTrack(track, index: engine.index, count: engine.queue.count)
            chrome.setElapsed(engine.elapsed, duration: engine.duration)
            if let error = engine.lastError {
                chrome.showStatus(error)
            }
            if displayedTrackPath != track.path {
                displayedTrackPath = track.path
                if let path = track.artworkPath, !path.isEmpty {
                    stage.setCover(ArtworkCache.shared.coverNow(path: path, title: track.album, artist: track.albumArtist))
                } else {
                    stage.setCover(nil)
                }
            }
        } else {
            displayedTrackPath = nil
            stage.setCover(nil)
            chrome.showEmpty()
        }
        wheel.setPlaying(engine.transport == .playing)
        syncLink()
        updateIdle()
        guard mode == .playback else { return }
        syncStage(animated: true)
    }

    func clickWheel(_ wheel: ClickWheelView, scrolled deltaRadians: CGFloat) {
        switch mode {
        case .playback:
            engine.adjustVolume(by: Float(deltaRadians) * 0.16)
            volumeHUD.show(engine.volume)
        case .library:
            coverFlow.scroll(byRadians: deltaRadians)
        }
    }

    func clickWheelDidFinishScrolling(_ wheel: ClickWheelView) {
        if mode == .library {
            coverFlow.finishScrolling()
        }
    }

    func clickWheelMenu(_ wheel: ClickWheelView) {
        haptics.press()
        engine.playClick()
        if mode == .playback {
            showLibrary(animated: true)
        } else {
            showPlayback(animated: true)
        }
    }

    func clickWheelPrevious(_ wheel: ClickWheelView) {
        haptics.press()
        engine.playClick()
        if mode == .library {
            coverFlow.step(-1)
        } else {
            engine.previous()
        }
    }

    func clickWheelNext(_ wheel: ClickWheelView) {
        haptics.press()
        engine.playClick()
        if mode == .library {
            coverFlow.step(1)
        } else {
            engine.next()
        }
    }

    func clickWheelCenter(_ wheel: ClickWheelView) {
        if mode == .library {
            selectCenteredAlbum()
        } else {
            haptics.press()
            engine.playClick()
            togglePlayback()
        }
    }

    func clickWheelPlay(_ wheel: ClickWheelView) {
        haptics.press()
        engine.playClick()
        showLibrary(animated: true)
    }

    func clickWheelDidHoldCenter(_ wheel: ClickWheelView) {
        presentFolderPicker()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            do {
                let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                scanner.useRootBookmark(data)
                showLibrary(animated: true)
            } catch {
                indexingLabel.isHidden = false
                indexingLabel.text = "Could not open that folder"
            }
            return
        }
        scanner.importURLs(urls, autoplay: false)
    }

    fileprivate func displayTick() {
        chrome.setElapsed(engine.elapsed, duration: engine.duration)
    }

    private func togglePlayback() {
        if engine.currentTrack == nil {
            let album = coverFlow.centeredAlbum() ?? albums.first
            guard let album, !album.tracks.isEmpty else { return }
            engine.play(tracks: album.tracks, startingAt: 0)
            if mode == .library { showPlayback(animated: true) }
            return
        }
        engine.toggle()
    }

    private func selectCenteredAlbum() {
        guard let album = coverFlow.centeredAlbum(), !album.tracks.isEmpty else { return }
        haptics.select()
        engine.playDrop()
        engine.play(tracks: album.tracks, startingAt: 0)
        showPlayback(animated: true)
    }

    private func showLibrary(animated: Bool) {
        guard mode != .library else { return }
        mode = .library
        wheel.setBrowsing(true)
        coverFlow.isUserInteractionEnabled = true
        chrome.isUserInteractionEnabled = false
        if let path = engine.currentTrack?.path,
           let album = albums.first(where: { $0.tracks.contains(where: { $0.path == path }) }) {
            coverFlow.center(on: album.id, animated: false)
        }
        stage.setSpinning(false)
        let fade = {
            UIView.animate(withDuration: 0.34, delay: 0.12, options: [.curveEaseIn, .allowUserInteraction]) {
                self.stage.alpha = 0
                self.chrome.alpha = 0
                self.coverFlow.alpha = 1
            }
        }
        if animated, stage.isRevealed {
            stage.setReveal(0, animated: true)
            fade()
        } else {
            stage.setReveal(0, animated: false)
            stage.alpha = 0
            chrome.alpha = 0
            coverFlow.alpha = 1
        }
        updateIdle()
        syncLink()
    }

    private func showPlayback(animated: Bool) {
        let wasLibrary = mode == .library
        mode = .playback
        wheel.setBrowsing(false)
        coverFlow.isUserInteractionEnabled = false
        chrome.isUserInteractionEnabled = true
        let reveal = { self.syncStage(animated: true) }
        guard animated, wasLibrary else {
            coverFlow.alpha = 0
            stage.alpha = 1
            chrome.alpha = 1
            reveal()
            updateIdle()
            syncLink()
            return
        }
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.coverFlow.alpha = 0
            self.stage.alpha = 1
            self.chrome.alpha = 1
        } completion: { _ in
            reveal()
        }
        updateIdle()
        syncLink()
    }

    private func syncStage(animated: Bool) {
        switch engine.transport {
        case .playing:
            stage.setReveal(1, animated: animated)
            stage.setSpinning(true)
        case .paused:
            stage.setReveal(engine.currentTrack == nil ? 0 : 1, animated: animated)
            stage.setSpinning(false)
        case .cued, .ended, .idle:
            stage.setReveal(0, animated: animated)
            stage.setSpinning(false)
        }
    }

    private func tryRestore(scanning: Bool) {
        guard !didRestore else { return }
        guard let path = UserDefaults.standard.string(forKey: "lastTrackPath") else {
            didRestore = true
            return
        }
        guard let found = locate(path) else {
            if !scanning { didRestore = true }
            return
        }
        didRestore = true
        let elapsed = UserDefaults.standard.double(forKey: "lastElapsed")
        engine.cue(tracks: found.album.tracks, startingAt: found.index, elapsed: elapsed)
        coverFlow.center(on: found.album.id, animated: false)
    }

    private func consumePendingImport() {
        guard let path = pendingPlayPath, let found = locate(path) else { return }
        pendingPlayPath = nil
        didRestore = true
        engine.play(tracks: found.album.tracks, startingAt: found.index)
        showPlayback(animated: true)
    }

    private func locate(_ path: String) -> (album: Album, index: Int)? {
        for album in albums {
            if let index = album.tracks.firstIndex(where: { $0.path == path }) {
                return (album, index)
            }
        }
        return nil
    }

    private func presentFolderPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        picker.overrideUserInterfaceStyle = .dark
        present(picker, animated: true)
    }

    private func syncLink() {
        let running = foreground && mode == .playback && engine.transport == .playing
        tickLink?.isPaused = !running
    }

    private func updateIdle() {
        UIApplication.shared.isIdleTimerDisabled = foreground && mode == .playback && engine.transport == .playing
    }

    @objc private func resignActive() {
        foreground = false
        tickLink?.isPaused = true
        stage.setVisualSuspended(true)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @objc private func becomeActive() {
        foreground = true
        stage.setVisualSuspended(false)
        chrome.setElapsed(engine.elapsed, duration: engine.duration)
        syncLink()
        updateIdle()
    }

    private enum Mode {
        case playback
        case library
    }
}

private final class TickProxy: NSObject {
    weak var owner: RootViewController?
    @objc func tick() { owner?.displayTick() }
}
