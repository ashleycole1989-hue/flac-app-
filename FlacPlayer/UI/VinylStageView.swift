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

    func setCover(_ image: UIImage?) {
        coverImage = image
        sleeve.setCover(image)
        renderedSide = 0
        setNeedsLayout()
    }

    func setCaption(title: String, artist: String) {
        sleeve.setCaption(title: title, artist: artist)
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

        let cardWidth = min(bounds.width * 0.62, bounds.height * 0.62, 260)
        let cardHeight = cardWidth * 1.08
        let cardY = min(max(18, bounds.height - cardHeight - 6), bounds.height * 0.30)
        let sleeveFrame = CGRect(
            x: (bounds.width - cardWidth) / 2,
            y: cardY,
            width: cardWidth,
            height: cardHeight
        )
        sleeveContainer.bounds = CGRect(origin: .zero, size: sleeveFrame.size)
        sleeveContainer.center = CGPoint(x: sleeveFrame.midX, y: sleeveFrame.midY)
        sleeve.frame = sleeveContainer.bounds
        sleeveContainer.layer.shadowPath = UIBezierPath(roundedRect: sleeveContainer.bounds, cornerRadius: 2).cgPath

        let vinylSide = cardWidth * 0.98
        let radius = vinylSide / 2
        let tucked = sleeveFrame.minY + radius
        var extended = sleeveFrame.minY + radius * 0.18
        extended = min(tucked, max(extended, radius + 2))
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
        } else if coverImage == nil {
            discView.image = nil
            renderedSide = 0
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
    private let band = UIView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 2
        backgroundColor = Theme.cardBand
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        artView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        band.backgroundColor = Theme.cardBand
        titleLabel.font = Theme.sans(17, .regular)
        titleLabel.textColor = Theme.ink
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        artistLabel.textAlignment = .center
        artistLabel.adjustsFontSizeToFitWidth = true
        artistLabel.minimumScaleFactor = 0.7
        addSubview(artView)
        addSubview(band)
        addSubview(titleLabel)
        addSubview(artistLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    func setCover(_ image: UIImage?) {
        artView.image = image
    }

    func setCaption(title: String, artist: String) {
        titleLabel.text = title
        artistLabel.attributedText = artist.isEmpty ? nil : Theme.tracked(artist, size: 11, color: Theme.muted, kern: 1.6)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bandHeight = bounds.height * 0.30
        let artHeight = bounds.height - bandHeight
        artView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: artHeight)
        band.frame = CGRect(x: 0, y: artHeight, width: bounds.width, height: bandHeight)
        titleLabel.frame = CGRect(x: 12, y: artHeight + bandHeight * 0.16, width: bounds.width - 24, height: 22)
        artistLabel.frame = CGRect(x: 12, y: titleLabel.frame.maxY + 2, width: bounds.width - 24, height: 16)
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
