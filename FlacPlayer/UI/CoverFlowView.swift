import UIKit

final class CoverFlowView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onSelect: (() -> Void)?

    private let layout = CoverFlowLayout()
    private let collectionView: UICollectionView
    private let emptyLabel = UILabel()
    private let emptyDetail = UILabel()
    private let addButton = UIButton(type: .custom)
    private let folderButton = UIButton(type: .custom)
    private var albums: [Album] = []
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

        emptyLabel.font = Theme.sans(20, .regular)
        emptyLabel.textColor = Theme.ink
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "Choose a music folder"
        emptyDetail.font = Theme.sans(13, .regular)
        emptyDetail.textColor = Theme.muted
        emptyDetail.textAlignment = .center
        emptyDetail.numberOfLines = 0
        emptyDetail.text = "Songs in that folder and every folder inside it are added with their cover art."
        addButton.setTitle("Choose Folder", for: .normal)
        addButton.setTitleColor(Theme.ink, for: .normal)
        addButton.titleLabel?.font = Theme.sans(15, .semibold)
        addButton.backgroundColor = UIColor(white: 0.16, alpha: 1)
        addButton.layer.cornerRadius = 18
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        folderButton.setTitle("Folder", for: .normal)
        folderButton.setTitleColor(Theme.muted, for: .normal)
        folderButton.titleLabel?.font = Theme.sans(12, .semibold)
        folderButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addSubview(emptyLabel)
        addSubview(emptyDetail)
        addSubview(addButton)
        addSubview(folderButton)

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
        collectionView.frame = bounds
        folderButton.frame = CGRect(x: bounds.width - 84, y: 4, width: 72, height: 32)
        emptyLabel.frame = CGRect(x: 32, y: bounds.midY - 78, width: bounds.width - 64, height: 28)
        emptyDetail.frame = CGRect(x: 36, y: emptyLabel.frame.maxY + 6, width: bounds.width - 72, height: 52)
        addButton.frame = CGRect(x: (bounds.width - 168) / 2, y: emptyDetail.frame.maxY + 12, width: 168, height: 44)
        if collectionView.bounds.size != appliedCollectionSize, collectionView.bounds.width > 0 {
            appliedCollectionSize = collectionView.bounds.size
            layout.invalidateLayout()
        }
    }

    func setAlbums(_ albums: [Album]) {
        let previous = centeredAlbum()?.id
        self.albums = albums
        collectionView.reloadData()
        let empty = albums.isEmpty
        emptyLabel.isHidden = !empty
        emptyDetail.isHidden = !empty
        addButton.isHidden = !empty
        folderButton.isHidden = empty
        if bounds.width > 0 {
            collectionView.layoutIfNeeded()
            if let previous, let index = albums.firstIndex(where: { $0.id == previous }) {
                scrollTo(index, animated: false)
            }
        }
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

    private var currentIndex: Int {
        guard layout.itemStride > 1, !albums.isEmpty else { return 0 }
        let raw = collectionView.contentOffset.x / layout.itemStride
        return min(max(0, Int(raw.rounded())), albums.count - 1)
    }

    private func scrollTo(_ index: Int, animated: Bool) {
        guard albums.indices.contains(index) else { return }
        let x = CGFloat(index) * layout.itemStride
        collectionView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
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
        let art = min(collectionView.bounds.width * 0.50, collectionView.bounds.height * 0.62)
        let side = min(max(120, art), 230)
        let newSize = CGSize(width: side, height: side)
        let newSpacing = side * 0.28
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
        attributes.center = CGPoint(x: centerX, y: collectionView.bounds.height * 0.42)
        let midpoint = collectionView.contentOffset.x + collectionView.bounds.width / 2
        let distance = itemStride > 1 ? (centerX - midpoint) / itemStride : 0
        let clamped = max(-1, min(1, distance))
        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 520
        transform = CATransform3DTranslate(transform, 0, 0, -abs(clamped) * 70)
        let tilt = abs(clamped) < 0.04 ? 0 : -clamped * (58 * .pi / 180)
        transform = CATransform3DRotate(transform, tilt, 0, 1, 0)
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
    private var token = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.isDoubleSided = false
        artView.contentMode = .scaleAspectFill
        artView.clipsToBounds = true
        artView.layer.cornerRadius = 2
        artView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        contentView.addSubview(artView)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 10)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        artView.frame = bounds
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }

    func configure(_ album: Album) {
        token = album.id
        accessibilityLabel = "\(album.title), \(album.artist)"
        isAccessibilityElement = true
        let request = token
        ArtworkCache.shared.load(path: album.artworkPath, title: album.title, artist: album.artist) { [weak self] cover, _ in
            guard let self, self.token == request else { return }
            self.artView.image = cover
        }
    }
}
