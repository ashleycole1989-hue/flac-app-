import UIKit

protocol ClickWheelDelegate: AnyObject {
    func clickWheel(_ wheel: ClickWheelView, scrolled deltaRadians: CGFloat)
    func clickWheelDidFinishScrolling(_ wheel: ClickWheelView)
    func clickWheelMenu(_ wheel: ClickWheelView)
    func clickWheelPrevious(_ wheel: ClickWheelView)
    func clickWheelNext(_ wheel: ClickWheelView)
    func clickWheelCenter(_ wheel: ClickWheelView)
    func clickWheelPlay(_ wheel: ClickWheelView)
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
    private let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    private let momentumProxy = WheelMomentumProxy()
    private var momentumLink: CADisplayLink?
    private var lastAngle: CGFloat = 0
    private var lastSampleTime: CFTimeInterval = 0
    private var velocity: CGFloat = 0
    private var hapticBucket: CGFloat = 0
    private var notchAngle: CGFloat = -.pi / 2
    private var allowsMomentum = false
    private let hapticStep: CGFloat = .pi / 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 8)

        notchOrbit.isUserInteractionEnabled = false
        notch.backgroundColor = Theme.ink.withAlphaComponent(0.85)
        notch.layer.cornerRadius = 2
        notchOrbit.addSubview(notch)
        addSubview(notchOrbit)

        configure(menuButton, accessibility: "Library")
        configure(previousButton, accessibility: "Previous")
        configure(nextButton, accessibility: "Next")
        configure(playButton, accessibility: "Play")
        previousButton.setImage(UIImage(systemName: "backward.end.fill", withConfiguration: symbolConfig), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.end.fill", withConfiguration: symbolConfig), for: .normal)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: symbolConfig), for: .normal)
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
        allowsMomentum = browsing
        let title = browsing ? "MENU" : "LIBRARY"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.sans(10, .bold),
            .foregroundColor: Theme.ink.withAlphaComponent(0.86),
            .kern: 1.05
        ]
        menuButton.setAttributedTitle(NSAttributedString(string: title, attributes: attributes), for: .normal)
        menuButton.accessibilityLabel = browsing ? "Menu" : "Library"
        if !browsing { stopMomentum() }
    }

    func setPlaying(_ playing: Bool) {
        let name = playing ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name, withConfiguration: symbolConfig), for: .normal)
        playButton.accessibilityLabel = playing ? "Pause" : "Play"
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let circle = bounds.insetBy(dx: 1, dy: 1)
        ctx.addEllipse(in: circle)
        ctx.setFillColor(UIColor(white: 0.16, alpha: 1).cgColor)
        ctx.fillPath()

        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.045).cgColor)
        ctx.setLineWidth(1)
        var y: CGFloat = 0
        while y < bounds.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            y += 3
        }
        ctx.strokePath()
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: bounds.insetBy(dx: 2, dy: 2))

        let inner = bounds.width * 0.20
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        ctx.setFillColor(UIColor(white: 0.06, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
        ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.65).cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        let orbit = bounds.width * 0.34
        menuButton.bounds = CGRect(x: 0, y: 0, width: 88, height: 36)
        previousButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        nextButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        playButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        menuButton.center = CGPoint(x: mid.x, y: mid.y - orbit)
        previousButton.center = CGPoint(x: mid.x - orbit, y: mid.y)
        nextButton.center = CGPoint(x: mid.x + orbit, y: mid.y)
        playButton.center = CGPoint(x: mid.x, y: mid.y + orbit)
        let cap = bounds.width * 0.36
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
        let inner = bounds.width * 0.19
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
            if distance < bounds.width * 0.2 { return }
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
    private let gradient = CAGradientLayer()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [
            UIColor(white: 0.30, alpha: 1).cgColor,
            UIColor(white: 0.10, alpha: 1).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        label.text = "SELECT"
        label.font = Theme.sans(9, .bold)
        label.textColor = Theme.ink.withAlphaComponent(0.55)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        accessibilityLabel = "Select"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        let radius = bounds.width / 2
        layer.cornerRadius = radius
        gradient.cornerRadius = radius
        label.frame = bounds
    }

    override var isHighlighted: Bool {
        didSet { gradient.opacity = isHighlighted ? 0.62 : 1 }
    }
}
