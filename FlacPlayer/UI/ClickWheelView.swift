import UIKit

protocol ClickWheelDelegate: AnyObject {
    func clickWheel(_ wheel: ClickWheelView, scrolled deltaRadians: CGFloat)
    func clickWheelDidFinishScrolling(_ wheel: ClickWheelView)
    func clickWheelMenu(_ wheel: ClickWheelView)
    func clickWheelPrevious(_ wheel: ClickWheelView)
    func clickWheelNext(_ wheel: ClickWheelView)
    func clickWheelCenter(_ wheel: ClickWheelView)
    func clickWheelPlay(_ wheel: ClickWheelView)
    func clickWheelDidHoldCenter(_ wheel: ClickWheelView)
}

final class ClickWheelView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: ClickWheelDelegate?

    private let notchOrbit = UIView()
    private let notch = UIView()
    private let menuButton = WheelKey(type: .custom)
    private let previousButton = WheelKey(type: .custom)
    private let nextButton = WheelKey(type: .custom)
    private let playButton = WheelKey(type: .custom)
    private let centerButton = CenterCap()
    private let haptics = Haptics()
    private let momentumProxy = WheelMomentumProxy()
    private var momentumLink: CADisplayLink?
    private var lastAngle: CGFloat = 0
    private var lastSampleTime: CFTimeInterval = 0
    private var velocity: CGFloat = 0
    private var hapticBucket: CGFloat = 0
    private var notchAngle: CGFloat = -.pi / 2
    private var allowsMomentum = false
    private var browsing = false
    private var playing = false
    private let hapticStep: CGFloat = .pi / 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 8)

        notchOrbit.isHidden = true

        configure(menuButton, accessibility: "Menu")
        configure(previousButton, accessibility: "Previous")
        configure(nextButton, accessibility: "Next")
        configure(playButton, accessibility: "Library")
        setBrowsing(false)

        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        centerButton.addTarget(self, action: #selector(centerTapped), for: .touchUpInside)

        addSubview(menuButton)
        addSubview(previousButton)
        addSubview(nextButton)
        addSubview(playButton)
        addSubview(centerButton)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.55
        addGestureRecognizer(hold)

        momentumProxy.wheel = self
        let link = CADisplayLink(target: momentumProxy, selector: #selector(WheelMomentumProxy.step))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        link.isPaused = true
        momentumLink = link
        positionNotch(at: notchAngle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    deinit {
        momentumLink?.invalidate()
    }

    func setBrowsing(_ browsing: Bool) {
        self.browsing = browsing
        allowsMomentum = browsing
        menuButton.isHidden = browsing
        previousButton.isHidden = browsing
        nextButton.isHidden = browsing
        playButton.isHidden = browsing
        applyCenterSymbol()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.sans(11, .semibold),
            .foregroundColor: Theme.ink.withAlphaComponent(0.88),
            .kern: 1.4
        ]
        menuButton.setAttributedTitle(NSAttributedString(string: "MENU", attributes: attributes), for: .normal)
        menuButton.setImage(nil, for: .normal)
        playButton.setImage(nil, for: .normal)
        playButton.setAttributedTitle(NSAttributedString(string: "LIBRARY", attributes: attributes), for: .normal)
        let skipAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.sans(18, .semibold),
            .foregroundColor: Theme.ink.withAlphaComponent(0.88)
        ]
        previousButton.setImage(nil, for: .normal)
        nextButton.setImage(nil, for: .normal)
        previousButton.setAttributedTitle(NSAttributedString(string: "◀◀", attributes: skipAttributes), for: .normal)
        nextButton.setAttributedTitle(NSAttributedString(string: "▶▶", attributes: skipAttributes), for: .normal)
        if !browsing { stopMomentum() }
        setNeedsDisplay()
    }

    func setPlaying(_ playing: Bool) {
        self.playing = playing
        applyCenterSymbol()
    }

    private func applyCenterSymbol() {
        if browsing {
            centerButton.setSymbol(nil)
            centerButton.accessibilityLabel = "Play album"
            return
        }
        let name = playing ? "pause.fill" : "play.fill"
        centerButton.setSymbol(name)
        centerButton.accessibilityLabel = playing ? "Pause" : "Play"
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let circle = bounds.insetBy(dx: 1, dy: 1)
        ctx.setFillColor(UIColor(red: 43.0 / 255, green: 43.0 / 255, blue: 46.0 / 255, alpha: 1).cgColor)
        ctx.fillEllipse(in: circle)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: bounds.insetBy(dx: 1.5, dy: 1.5))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        let orbit = bounds.width * 0.34
        menuButton.bounds = CGRect(x: 0, y: 0, width: 96, height: 32)
        previousButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        nextButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        playButton.bounds = CGRect(x: 0, y: 0, width: 96, height: 32)
        menuButton.center = CGPoint(x: mid.x, y: mid.y - orbit)
        previousButton.center = CGPoint(x: mid.x - orbit, y: mid.y)
        nextButton.center = CGPoint(x: mid.x + orbit, y: mid.y)
        playButton.center = CGPoint(x: mid.x, y: mid.y + orbit)
        let cap = bounds.width * (browsing ? 0.52 : 0.42)
        centerButton.bounds = CGRect(x: 0, y: 0, width: cap, height: cap)
        centerButton.center = mid

        notchOrbit.bounds = bounds
        notchOrbit.center = mid
        notch.bounds = CGRect(x: 0, y: 0, width: 4, height: 12)
        notch.center = CGPoint(x: bounds.midX, y: 15)
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let distance = hypot(point.x - bounds.midX, point.y - bounds.midY)
        return distance <= bounds.width / 2 + 8
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: self)
        let distance = hypot(point.x - bounds.midX, point.y - bounds.midY)
        let outer = bounds.width / 2
        let inner = bounds.width * 0.27
        if distance < inner || distance > outer + 6 { return false }
        for key in [menuButton, previousButton, nextButton, playButton] where key.frame.contains(point) {
            return false
        }
        return true
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        let angle = atan2(point.y - bounds.midY, point.x - bounds.midX)
        let now = CACurrentMediaTime()
        switch gesture.state {
        case .began:
            stopMomentum()
            lastAngle = angle
            lastSampleTime = now
            velocity = 0
            haptics.prepare()
        case .changed:
            let distance = hypot(point.x - bounds.midX, point.y - bounds.midY)
            if distance < bounds.width * 0.27 { return }
            var delta = angle - lastAngle
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            let dt = now - lastSampleTime
            if dt > 0.001 {
                let instant = delta / CGFloat(dt)
                velocity = velocity * 0.6 + instant * 0.4
            }
            lastAngle = angle
            lastSampleTime = now
            apply(delta)
            positionNotch(at: angle)
        case .ended, .cancelled, .failed:
            if allowsMomentum, abs(velocity) > 1.1 {
                startMomentum()
            } else {
                delegate?.clickWheelDidFinishScrolling(self)
            }
        default:
            break
        }
    }

    fileprivate func momentumStep() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastSampleTime)
        lastSampleTime = now
        guard dt > 0 else { return }
        velocity *= CGFloat(Darwin.exp(-2.3 * Double(dt)))
        if abs(velocity) < 0.45 {
            stopMomentum()
            delegate?.clickWheelDidFinishScrolling(self)
            return
        }
        let delta = velocity * CGFloat(dt)
        apply(delta)
        positionNotch(at: notchAngle + delta)
    }

    private func apply(_ delta: CGFloat) {
        guard delta != 0 else { return }
        hapticBucket += delta
        while hapticBucket >= hapticStep {
            hapticBucket -= hapticStep
            haptics.tick()
        }
        while hapticBucket <= -hapticStep {
            hapticBucket += hapticStep
            haptics.tick()
        }
        delegate?.clickWheel(self, scrolled: delta)
    }

    private func positionNotch(at angle: CGFloat) {
        notchAngle = angle
        notchOrbit.transform = CGAffineTransform(rotationAngle: angle + .pi / 2)
    }

    private func startMomentum() {
        lastSampleTime = CACurrentMediaTime()
        momentumLink?.isPaused = false
    }

    private func stopMomentum() {
        momentumLink?.isPaused = true
        velocity = 0
    }

    @objc private func menuTapped() {
        stopMomentum()
        delegate?.clickWheelMenu(self)
    }

    @objc private func previousTapped() {
        stopMomentum()
        delegate?.clickWheelPrevious(self)
    }

    @objc private func nextTapped() {
        stopMomentum()
        delegate?.clickWheelNext(self)
    }

    @objc private func playTapped() {
        stopMomentum()
        delegate?.clickWheelPlay(self)
    }

    @objc private func centerTapped() {
        stopMomentum()
        delegate?.clickWheelCenter(self)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: self)
        let distance = hypot(point.x - bounds.midX, point.y - bounds.midY)
        guard distance < bounds.width * 0.24 else { return }
        delegate?.clickWheelDidHoldCenter(self)
    }

    private func configure(_ button: UIButton, accessibility: String) {
        button.tintColor = Theme.ink.withAlphaComponent(0.86)
        button.accessibilityLabel = accessibility
    }
}

private final class WheelMomentumProxy: NSObject {
    weak var wheel: ClickWheelView?
    @objc func step() { wheel?.momentumStep() }
}

private final class WheelKey: UIButton {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.4 : 1 }
    }
}

private final class CenterCap: UIControl {
    private let symbol = UIImageView()
    private let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.20, alpha: 1)
        symbol.contentMode = .scaleAspectFit
        symbol.tintColor = Theme.ink
        symbol.isUserInteractionEnabled = false
        addSubview(symbol)
        accessibilityLabel = "Play"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    func setSymbol(_ name: String?) {
        if let name {
            symbol.image = UIImage(systemName: name, withConfiguration: symbolConfig)
            symbol.isHidden = false
            backgroundColor = UIColor(white: 0.20, alpha: 1)
        } else {
            symbol.image = nil
            symbol.isHidden = true
            backgroundColor = UIColor(red: 26.0 / 255, green: 26.0 / 255, blue: 28.0 / 255, alpha: 1)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        let side = bounds.width * 0.34
        symbol.frame = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }
}
