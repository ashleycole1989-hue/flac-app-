import UIKit

/// Album jacket in front, vinyl behind it. `reveal` slides the record up out of the sleeve.
final class VinylStageView: UIView {
    private let sleeveContainer = UIView()
    private let sleeve = SleeveView()
    private let vinylHolder = UIView()
    private let discView = UIImageView()
    private let sheen = SheenView()

    private var reveal: CGFloat = 0
    private var coverImage: UIImage?
    private var renderedSide: CGFloat = 0
    private var wantsSpin = false
    private var visualSuspended = false
    private var animationAdded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false

        vinylHolder.layer.shadowColor = UIColor.black.cgColor
        vinylHolder.layer.shadowOpacity = 0.45
        vinylHolder.layer.shadowRadius = 16
        vinylHolder.layer.shadowOffset = CGSize(width: 0, height: 10)

        discView.contentMode = .scaleAspectFill
        discView.backgroundColor = .black
        discView.clipsToBounds = true

        sleeveContainer.layer.shadowColor = UIColor.black.cgColor
        sleeveContainer.layer.shadowOpacity = 0.4
        sleeveContainer.layer.shadowRadius = 18
        sleeveContainer.layer.shadowOffset = CGSize(width: 0, height: 12)

        addSubview(vinylHolder)
        vinylHolder.addSubview(discView)
        vinylHolder.addSubview(sheen)
        sleeveContainer.addSubview(sleeve)
        addSubview(sleeveContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    func setCover(_ image: UIImage) {
        coverImage = image
        sleeve.setCover(image)
        renderedSide = 0
        setNeedsLayout()
    }

    var isRevealed: Bool { reveal > 0.02 }

    func setReveal(_ value: CGFloat, animated: Bool, completion: (() -> Void)? = nil) {
        let next = min(1, max(0, value))
        if abs(next - reveal) < 0.001 {
            completion?()
            return
        }
        reveal = next
        let updates = {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        guard animated else {
            updates()
            completion?()
            return
        }
        UIView.animate(
            withDuration: 0.66,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction]
        ) {
            updates()
        } completion: { _ in
            completion?()
        }
    }

    func setSpinning(_ spinning: Bool) {
        wantsSpin = spinning
        guard !visualSuspended else { return }
        if spinning {
            startOrResume()
        } else {
            freeze()
        }
    }

    func setVisualSuspended(_ suspended: Bool) {
        visualSuspended = suspended
        if suspended {
            freeze()
        } else if wantsSpin {
            startOrResume()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 20, bounds.height > 20 else { return }

        let maxByHeight = (bounds.height - 8) / 1.72
        let sleeveSide = min(bounds.width * 0.64, maxByHeight, 280)
        let sleeveFrame = CGRect(
            x: (bounds.width - sleeveSide) / 2,
            y: bounds.height - sleeveSide,
            width: sleeveSide,
            height: sleeveSide
        )
        sleeveContainer.bounds = CGRect(origin: .zero, size: sleeveFrame.size)
        sleeveContainer.center = CGPoint(x: sleeveFrame.midX, y: sleeveFrame.midY)
        sleeve.frame = sleeveContainer.bounds
        sleeveContainer.layer.shadowPath = UIBezierPath(roundedRect: sleeveContainer.bounds, cornerRadius: 4).cgPath

        let vinylSide = sleeveSide * 0.90
        let radius = vinylSide / 2
        let tucked = sleeveFrame.midY + 8
        var extended = sleeveFrame.minY - radius * 0.42
        extended = max(extended, radius + 2)
        let centerY = tucked + (extended - tucked) * reveal

        vinylHolder.bounds = CGRect(x: 0, y: 0, width: vinylSide, height: vinylSide)
        vinylHolder.center = CGPoint(x: bounds.midX, y: centerY)
        vinylHolder.layer.shadowPath = UIBezierPath(ovalIn: vinylHolder.bounds).cgPath
        discView.frame = vinylHolder.bounds
        discView.layer.cornerRadius = vinylSide / 2
        sheen.frame = vinylHolder.bounds
        sheen.layer.cornerRadius = vinylSide / 2

        if let coverImage, abs(vinylSide - renderedSide) > 0.5 {
            renderedSide = vinylSide
            let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
            discView.image = Artwork.vinyl(artwork: coverImage, diameter: vinylSide, scale: scale)
        }
    }

    private func startOrResume() {
        guard wantsSpin, !visualSuspended else { return }
        let layer = discView.layer
        if !animationAdded {
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = CGFloat.pi * 2
            spin.duration = 60 / 33.333
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            layer.add(spin, forKey: "spin")
            animationAdded = true
            return
        }
        guard layer.speed == 0 else { return }
        let paused = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        let since = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        layer.beginTime = since
    }

    private func freeze() {
        let layer = discView.layer
        guard animationAdded, layer.speed > 0 else { return }
        let paused = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = paused
    }
}

private final class SleeveView: UIView {
    private let artView = UIImageView()
    private let lip = UIView()
    private let lipLine = UIView()
    private let slot = SlotFade()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 3
        backgroundColor = Theme.cardboard
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        lip.backgroundColor = Theme.cardboardDark
        lipLine.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        addSubview(artView)
        addSubview(slot)
        addSubview(lip)
        addSubview(lipLine)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    func setCover(_ image: UIImage) {
        artView.image = image
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.setAlpha(0.18)
        ctx.setBlendMode(.overlay)
        Artwork.noise.draw(in: rect)
        ctx.restoreGState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        artView.frame = bounds.insetBy(dx: 14, dy: 16)
        lip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 12)
        lipLine.frame = CGRect(x: 0, y: 12, width: bounds.width, height: 1)
        slot.frame = CGRect(x: 14, y: 13, width: bounds.width - 28, height: 22)
    }
}

private final class SlotFade: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.38).cgColor,
            UIColor.clear.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }
}

private final class SheenView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.type = .radial
        gradient.colors = [
            UIColor.white.withAlphaComponent(0.30).cgColor,
            UIColor.white.withAlphaComponent(0.06).cgColor,
            UIColor.clear.cgColor
        ]
        gradient.locations = [0, 0.42, 1]
        gradient.startPoint = CGPoint(x: 0.32, y: 0.28)
        gradient.endPoint = CGPoint(x: 1, y: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }
}
