import UIKit

final class CoverFlowView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onSelect: (() -> Void)?

    private let layout = CoverFlowLayout()
    private let collectionView: UICollectionView
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let emptyLabel = UILabel()
    private let addButton = UIButton(type: .custom)
    private var albums: [Album] = []
    private var lastCaptionIndex = -1
    private var appliedCollectionSize: CGSize = .zero

    var onAdd: (() -> Void)?

    override init(frame: CGRect) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true

        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CoverCell.self, forCellWithReuseIdentifier: CoverCell.reuseID)
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.clipsToBounds = false
        collectionView.alwaysBounceHorizontal = true
        addSubview(collectionView)

        titleLabel.font = Theme.serif(22, .semibold)
        titleLabel.textColor = Theme.ink
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        detailLabel.font = Theme.sans(12, .medium)
        detailLabel.textColor = Theme.muted
        detailLabel.textAlignment = .center
        emptyLabel.font = Theme.serif(20, .medium)
        emptyLabel.textColor = Theme.ink
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "No albums yet"
        addButton.setTitle("Add Music", for: .normal)
        addButton.setTitleColor(Theme.amber, for: .normal)
        addButton.titleLabel?.font = Theme.sans(15, .semibold)
        addButton.backgroundColor = UIColor(white: 0.14, alpha: 1)
        addButton.layer.cornerRadius = 18
        addButton.layer.borderWidth = 1
        addButton.layer.borderColor = Theme.amber.withAlphaComponent(0.35).cgColor
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(emptyLabel)
        addSubview(addButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        collectionView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let captionHeight: CGFloat = 58
        titleLabel.frame = CGRect(x: 24, y: bounds.height - captionHeight, width: bounds.width - 48, height: 28)
        detailLabel.frame = CGRect(x: 24, y: titleLabel.frame.maxY, width: bounds.width - 48, height: 20)
        collectionView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: titleLabel.frame.minY - 6)
        emptyLabel.frame = CGRect(x: 32, y: bounds.midY - 70, width: bounds.width - 64, height: 60)
        addButton.frame = CGRect(x: (bounds.width - 160) / 2, y: emptyLabel.frame.maxY + 8, width: 160, height: 44)
        if collectionView.bounds.size != appliedCollectionSize, collectionView.bounds.width > 0 {
            appliedCollectionSize = collectionView.bounds.size
            layout.invalidateLayout()
        }
    }

    func setAlbums(_ albums: [Album]) {
        let previous = centeredAlbum()?.id
        self.albums = albums
        collectionView.reloadData()
        emptyLabel.isHidden = !albums.isEmpty
        addButton.isHidden = !albums.isEmpty
        titleLabel.isHidden = albums.isEmpty
        detailLabel.isHidden = albums.isEmpty
        if bounds.width > 0 {
            collectionView.layoutIfNeeded()
            if let previous, let index = albums.firstIndex(where: { $0.id == previous }) {
                scrollTo(index, animated: false)
            }
        }
        updateCaption()
    }

    func centeredAlbum() -> Album? {
        guard albums.indices.contains(currentIndex) else { return nil }
        return albums[currentIndex]
    }

    func center(on albumID: String, animated: Bool) {
        guard let index = albums.firstIndex(where: { $0.id == albumID }) else { return }
        scrollTo(index, animated: animated)
    }

    func scroll(byRadians delta: CGFloat) {
        guard albums.count > 1, layout.itemStride > 1 else { return }
        let dx = delta * layout.itemStride * 1.2
        var x = collectionView.contentOffset.x + dx
        let maxX = max(0, collectionView.contentSize.width - collectionView.bounds.width)
        x = min(max(0, x), maxX)
        collectionView.contentOffset.x = x
    }

    func finishScrolling() {
        scrollTo(currentIndex, animated: true)
    }

    func step(_ direction: Int) {
        guard !albums.isEmpty else { return }
        let next = min(max(0, currentIndex + direction), albums.count - 1)
        scrollTo(next, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        albums.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CoverCell.reuseID, for: indexPath) as! CoverCell
        cell.configure(albums[indexPath.item])
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let index = currentIndex
        guard index != lastCaptionIndex else { return }
        lastCaptionIndex = index
        updateCaption()
    }

    private var currentIndex: Int {
        guard layout.itemStride > 1, !albums.isEmpty else { return 0 }
        let raw = collectionView.contentOffset.x / layout.itemStride
        return min(max(0, Int(raw.rounded())), albums.count - 1)
    }

    private func scrollTo(_ index: Int, animated: Bool) {
        guard albums.indices.contains(index) else { return }
        let x = CGFloat(index) * layout.itemStride
        collectionView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
        lastCaptionIndex = index
        updateCaption()
    }

    private func updateCaption() {
        guard let album = centeredAlbum() else {
            titleLabel.text = nil
            detailLabel.text = nil
            return
        }
        titleLabel.text = album.title
        let year = album.year.map(String.init)
        let count = album.tracks.count == 1 ? "1 track" : "\(album.tracks.count) tracks"
        detailLabel.attributedText = Theme.tracked(
            [album.artist, year, count].compactMap { $0 }.joined(separator: "  ·  "),
            size: 11,
            color: Theme.muted,
            kern: 1.1
        )
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        guard abs(point.x - bounds.midX) < bounds.width * 0.22 else { return }
        onSelect?()
    }

    @objc private func addTapped() {
        onAdd?()
    }
}

private final class CoverFlowLayout: UICollectionViewLayout {
    private(set) var itemSize = CGSize(width: 180, height: 240)
    private(set) var spacing: CGFloat = 36

    var itemStride: CGFloat { itemSize.width + spacing }

    override func prepare() {
        guard let collectionView, collectionView.bounds.width > 20, collectionView.bounds.height > 20 else { return }
        let art = min(collectionView.bounds.width * 0.52, collectionView.bounds.height * 0.74)
        let side = min(max(128, art), 230)
        let newSize = CGSize(width: side, height: side * 1.34)
        let newSpacing = side * 0.2
        if newSize != itemSize || newSpacing != spacing {
            itemSize = newSize
            spacing = newSpacing
        }
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if newBounds.size == collectionView?.bounds.size {
            context.contentSizeAdjustment = .zero
        }
        return context
    }

    override var collectionViewContentSize: CGSize {
        guard let collectionView else { return .zero }
        let count = collectionView.numberOfItems(inSection: 0)
        if count == 0 { return collectionView.bounds.size }
        let inset = sideInset
        let width = inset + itemSize.width + CGFloat(max(count - 1, 0)) * itemStride + inset
        return CGSize(width: max(width, collectionView.bounds.width), height: collectionView.bounds.height)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView, itemStride > 1 else { return nil }
        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return nil }
        let expanded = rect.insetBy(dx: -itemSize.width, dy: -30)
        var start = Int((expanded.minX - sideInset) / itemStride) - 1
        var end = Int((expanded.maxX - sideInset) / itemStride) + 2
        start = max(0, start)
        end = min(count - 1, end)
        guard start <= end else { return nil }
        var attributes: [UICollectionViewLayoutAttributes] = []
        for index in start...end {
            if let item = layoutAttributesForItem(at: IndexPath(item: index, section: 0)) {
                attributes.append(item)
            }
        }
        return attributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        let centerX = sideInset + itemSize.width / 2 + CGFloat(indexPath.item) * itemStride
        attributes.size = itemSize
        attributes.center = CGPoint(x: centerX, y: collectionView.bounds.height * 0.46)
        let midpoint = collectionView.contentOffset.x + collectionView.bounds.width / 2
        let distance = itemStride > 1 ? (centerX - midpoint) / itemStride : 0
        let clamped = max(-1, min(1, distance))
        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 700
        transform = CATransform3DTranslate(transform, 0, 0, -abs(clamped) * 90)
        transform = CATransform3DRotate(transform, -clamped * (55 * .pi / 180), 0, 1, 0)
        attributes.transform3D = transform
        attributes.zIndex = Int(1000 - abs(distance) * 80)
        return attributes
    }

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView, itemStride > 1 else { return proposedContentOffset }
        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return proposedContentOffset }
        let raw = proposedContentOffset.x / itemStride
        let index: CGFloat
        if velocity.x > 0.25 {
            index = ceil(raw)
        } else if velocity.x < -0.25 {
            index = floor(raw)
        } else {
            index = round(raw)
        }
        let clamped = min(max(0, index), CGFloat(count - 1))
        return CGPoint(x: clamped * itemStride, y: 0)
    }

    private var sideInset: CGFloat {
        guard let collectionView else { return 0 }
        return max(0, (collectionView.bounds.width - itemSize.width) / 2)
    }
}

private final class CoverCell: UICollectionViewCell {
    static let reuseID = "CoverCell"

    private let artView = UIImageView()
    private let reflectionView = UIImageView()
    private let gloss = CAGradientLayer()
    private var token = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.isDoubleSided = false
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        artView.layer.cornerRadius = 2
        artView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        reflectionView.contentMode = .scaleAspectFill
        reflectionView.clipsToBounds = true
        gloss.colors = [
            UIColor.white.withAlphaComponent(0.18).cgColor,
            UIColor.clear.cgColor
        ]
        gloss.startPoint = CGPoint(x: 0.5, y: 0)
        gloss.endPoint = CGPoint(x: 0.5, y: 0.55)
        artView.layer.addSublayer(gloss)
        contentView.addSubview(artView)
        contentView.addSubview(reflectionView)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 8)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = bounds.width
        artView.frame = CGRect(x: 0, y: 0, width: side, height: side)
        reflectionView.frame = CGRect(x: 0, y: side, width: side, height: max(0, bounds.height - side))
        gloss.frame = artView.bounds
        layer.shadowPath = UIBezierPath(roundedRect: artView.frame, cornerRadius: 2).cgPath
    }

    func configure(_ album: Album) {
        token = album.id
        accessibilityLabel = "\(album.title), \(album.artist)"
        isAccessibilityElement = true
        let request = token
        ArtworkCache.shared.load(path: album.artworkPath, title: album.title, artist: album.artist) { [weak self] cover, reflection in
            guard let self, self.token == request else { return }
            self.artView.image = cover
            self.reflectionView.image = reflection
        }
    }
}
