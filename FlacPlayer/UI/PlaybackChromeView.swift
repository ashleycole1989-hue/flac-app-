import UIKit

final class PlaybackChromeView: UIView {
    var onSeek: ((TimeInterval) -> Void)?
    var onAdd: (() -> Void)?

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let indexLabel = UILabel()
    private let elapsedLabel = UILabel()
    private let durationLabel = UILabel()
    private let scrubber = Scrubber()
    private let emptyTitle = UILabel()
    private let emptyDetail = UILabel()
    private let addButton = UIButton(type: .custom)
    private var trackVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        titleLabel.font = Theme.serif(22, .semibold)
        titleLabel.textColor = Theme.ink
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.65
        detailLabel.font = Theme.sans(12, .medium)
        detailLabel.textColor = Theme.muted
        indexLabel.font = Theme.mono(12)
        indexLabel.textColor = Theme.muted
        indexLabel.textAlignment = .right
        elapsedLabel.font = Theme.mono(12)
        elapsedLabel.textColor = Theme.muted
        durationLabel.font = Theme.mono(12)
        durationLabel.textColor = Theme.muted
        durationLabel.textAlignment = .right
        elapsedLabel.text = "0:00"
        durationLabel.text = "0:00"

        emptyTitle.font = Theme.serif(20, .medium)
        emptyTitle.textColor = Theme.ink
        emptyTitle.textAlignment = .center
        emptyTitle.text = "No music on this iPhone yet"
        emptyDetail.font = Theme.sans(13, .regular)
        emptyDetail.textColor = Theme.muted
        emptyDetail.textAlignment = .center
        emptyDetail.numberOfLines = 2
        emptyDetail.text = "Add FLAC, ALAC, or MP3 files. They stay on the device."
        addButton.setTitle("Add Music", for: .normal)
        addButton.setTitleColor(Theme.amber, for: .normal)
        addButton.titleLabel?.font = Theme.sans(15, .semibold)
        addButton.backgroundColor = UIColor(white: 0.14, alpha: 1)
        addButton.layer.cornerRadius = 18
        addButton.layer.borderWidth = 1
        addButton.layer.borderColor = Theme.amber.withAlphaComponent(0.35).cgColor
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        scrubber.onChange = { [weak self] time in
            self?.elapsedLabel.text = TimeFormat.string(time)
        }
        scrubber.onEnd = { [weak self] time in
            self?.onSeek?(time)
        }

        for item in [titleLabel, detailLabel, indexLabel, elapsedLabel, durationLabel, scrubber, emptyTitle, emptyDetail, addButton] {
            addSubview(item)
        }
        showEmpty()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        if trackVisible {
            titleLabel.frame = CGRect(x: 0, y: 0, width: width - 64, height: 28)
            indexLabel.frame = CGRect(x: width - 64, y: 4, width: 64, height: 20)
            detailLabel.frame = CGRect(x: 0, y: 30, width: width, height: 18)
            elapsedLabel.frame = CGRect(x: 0, y: 56, width: 54, height: 18)
            durationLabel.frame = CGRect(x: width - 64, y: 56, width: 64, height: 18)
            scrubber.frame = CGRect(x: 58, y: 52, width: width - 126, height: 28)
        } else {
            emptyTitle.frame = CGRect(x: 0, y: 0, width: width, height: 26)
            emptyDetail.frame = CGRect(x: 12, y: 28, width: width - 24, height: 40)
            addButton.frame = CGRect(x: (width - 160) / 2, y: 74, width: 160, height: 40)
        }
    }

    func showEmpty() {
        trackVisible = false
        titleLabel.isHidden = true
        detailLabel.isHidden = true
        indexLabel.isHidden = true
        elapsedLabel.isHidden = true
        durationLabel.isHidden = true
        scrubber.isHidden = true
        emptyTitle.isHidden = false
        emptyDetail.isHidden = false
        addButton.isHidden = false
        setNeedsLayout()
    }

    func showTrack(_ track: Track, index: Int, count: Int) {
        trackVisible = true
        titleLabel.isHidden = false
        detailLabel.isHidden = false
        indexLabel.isHidden = false
        elapsedLabel.isHidden = false
        durationLabel.isHidden = false
        scrubber.isHidden = false
        emptyTitle.isHidden = true
        emptyDetail.isHidden = true
        addButton.isHidden = true
        titleLabel.text = track.title
        let year = track.year.map(String.init)
        detailLabel.attributedText = Theme.tracked(
            [track.artist, track.album, year].compactMap { $0 }.joined(separator: "  ·  "),
            size: 11,
            color: Theme.muted,
            kern: 1.05
        )
        indexLabel.text = "\(index + 1) / \(max(count, 1))"
        setNeedsLayout()
    }

    func showStatus(_ text: String) {
        guard trackVisible else { return }
        detailLabel.attributedText = Theme.tracked(text, size: 11, color: Theme.amber, kern: 1.05)
    }

    func setElapsed(_ elapsed: TimeInterval, duration: TimeInterval) {
        scrubber.setTime(elapsed, duration: duration)
        elapsedLabel.text = TimeFormat.string(elapsed)
        durationLabel.text = TimeFormat.string(duration)
    }

    @objc private func addTapped() {
        onAdd?()
    }
}

final class VolumeHUD: UIView {
    private let track = UIView()
    private let fill = UIView()
    private var amount: CGFloat = 1
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        alpha = 0
        track.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        track.layer.cornerRadius = 3
        fill.backgroundColor = Theme.amber
        fill.layer.cornerRadius = 3
        addSubview(track)
        addSubview(fill)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        let height = bounds.height * amount
        fill.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
    }

    func show(_ volume: Float) {
        amount = CGFloat(min(1, max(0, volume)))
        isHidden = false
        alpha = 1
        setNeedsLayout()
        layoutIfNeeded()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.35) {
                self?.alpha = 0
            } completion: { _ in
                if self?.alpha == 0 { self?.isHidden = true }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}

private final class Scrubber: UIControl {
    var onChange: ((TimeInterval) -> Void)?
    var onEnd: ((TimeInterval) -> Void)?

    private var duration: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var dragging = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = "Playback position"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    func setTime(_ elapsed: TimeInterval, duration: TimeInterval) {
        self.duration = duration
        guard !dragging else { return }
        self.elapsed = elapsed
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let y = bounds.midY
        let left: CGFloat = 4
        let right = bounds.width - 4
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: left, y: y))
        ctx.addLine(to: CGPoint(x: right, y: y))
        ctx.strokePath()

        let fraction = duration > 0 ? CGFloat(min(max(elapsed / duration, 0), 1)) : 0
        let x = left + (right - left) * fraction
        ctx.setStrokeColor(Theme.amber.cgColor)
        ctx.move(to: CGPoint(x: left, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y))
        ctx.strokePath()

        ctx.setFillColor(Theme.ink.cgColor)
        ctx.fillEllipse(in: CGRect(x: x - 6, y: y - 6, width: 12, height: 12))
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        dragging = true
        update(with: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        update(with: touch)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { update(with: touch) }
        dragging = false
        onEnd?(elapsed)
    }

    override func cancelTracking(with event: UIEvent?) {
        dragging = false
    }

    override func accessibilityIncrement() {
        let next = min(duration, elapsed + 5)
        onEnd?(next)
    }

    override func accessibilityDecrement() {
        let next = max(0, elapsed - 5)
        onEnd?(next)
    }

    private func update(with touch: UITouch) {
        guard duration > 0 else { return }
        let x = touch.location(in: self).x
        let fraction = min(1, max(0, (x - 4) / max(bounds.width - 8, 1)))
        elapsed = duration * TimeInterval(fraction)
        setNeedsDisplay()
        onChange?(elapsed)
    }
}
