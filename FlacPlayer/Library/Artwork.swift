import UIKit

final class ArtPair: NSObject {
    let cover: UIImage
    let reflection: UIImage

    init(cover: UIImage, reflection: UIImage) {
        self.cover = cover
        self.reflection = reflection
    }
}

final class ArtworkCache {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSString, ArtPair>()
    private let queue = DispatchQueue(label: "flacplayer.artwork", qos: .userInitiated)

    private init() {
        memory.countLimit = 48
    }

    func load(path: String?, title: String, artist: String, completion: @escaping (UIImage, UIImage) -> Void) {
        let key = (path?.isEmpty == false ? path! : "ph:\(title)\t\(artist)") as NSString
        if let pair = memory.object(forKey: key) {
            completion(pair.cover, pair.reflection)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let pair = self.makePair(path: path, title: title, artist: artist)
            self.memory.setObject(pair, forKey: key)
            DispatchQueue.main.async {
                completion(pair.cover, pair.reflection)
            }
        }
    }

    func coverNow(path: String?, title: String, artist: String) -> UIImage {
        let key = (path?.isEmpty == false ? path! : "ph:\(title)\t\(artist)") as NSString
        if let pair = memory.object(forKey: key) {
            return pair.cover
        }
        let pair = makePair(path: path, title: title, artist: artist)
        memory.setObject(pair, forKey: key)
        return pair.cover
    }

    private func makePair(path: String?, title: String, artist: String) -> ArtPair {
        let cover: UIImage
        if let path, !path.isEmpty, let image = UIImage(contentsOfFile: path) {
            cover = image
        } else {
            cover = Artwork.placeholder(title: title, artist: artist)
        }
        return ArtPair(cover: cover, reflection: Artwork.reflection(from: cover))
    }
}

enum Artwork {
    static let noise: UIImage = makeNoise()

    private static let palette: [(UIColor, UIColor)] = [
        (UIColor(red: 0.45, green: 0.16, blue: 0.13, alpha: 1), UIColor(red: 0.93, green: 0.82, blue: 0.68, alpha: 1)),
        (UIColor(red: 0.14, green: 0.24, blue: 0.34, alpha: 1), UIColor(red: 0.82, green: 0.86, blue: 0.80, alpha: 1)),
        (UIColor(red: 0.30, green: 0.22, blue: 0.13, alpha: 1), UIColor(red: 0.93, green: 0.80, blue: 0.52, alpha: 1)),
        (UIColor(red: 0.15, green: 0.29, blue: 0.24, alpha: 1), UIColor(red: 0.80, green: 0.88, blue: 0.76, alpha: 1)),
        (UIColor(red: 0.36, green: 0.16, blue: 0.24, alpha: 1), UIColor(red: 0.95, green: 0.80, blue: 0.72, alpha: 1)),
        (UIColor(red: 0.20, green: 0.18, blue: 0.30, alpha: 1), UIColor(red: 0.82, green: 0.78, blue: 0.90, alpha: 1))
    ]

    static func placeholder(title: String, artist: String) -> UIImage {
        let size = CGSize(width: 360, height: 360)
        let colors = palette[stableIndex(title + artist)]
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            colors.0.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            let ring = UIBezierPath(ovalIn: CGRect(x: 46, y: 46, width: 268, height: 268))
            colors.1.withAlphaComponent(0.16).setStroke()
            ring.lineWidth = 1
            ring.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let titleRect = CGRect(x: 28, y: 132, width: 304, height: 78)
            (title as NSString).draw(in: titleRect, withAttributes: [
                .font: Theme.serif(26, .semibold),
                .foregroundColor: colors.1,
                .paragraphStyle: paragraph
            ])
            let artistRect = CGRect(x: 28, y: 214, width: 304, height: 28)
            (artist.uppercased() as NSString).draw(in: artistRect, withAttributes: [
                .font: Theme.sans(11, .semibold),
                .foregroundColor: colors.1.withAlphaComponent(0.75),
                .paragraphStyle: paragraph,
                .kern: 1.4
            ])
        }
    }

    static func reflection(from image: UIImage) -> UIImage {
        let width = max(image.size.width, 1)
        let height = max(image.size.height * 0.36, 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: height)
            cg.scaleBy(x: 1, y: -1)
            image.draw(in: CGRect(
                x: 0,
                y: -(image.size.height - height),
                width: width,
                height: image.size.height
            ))
            cg.restoreGState()
            cg.setBlendMode(.destinationIn)
            let colors = [
                UIColor.black.withAlphaComponent(0.40).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: height),
                    options: []
                )
            }
        }
    }

    static func fitted(_ image: UIImage, maxPointSize: CGFloat) -> UIImage {
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > maxPointSize, maxDim > 0 else { return image }
        let ratio = maxPointSize / maxDim
        let size = CGSize(width: floor(image.size.width * ratio), height: floor(image.size.height * ratio))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func saveJPEG(_ image: UIImage, key: String) -> String? {
        let fittedImage = fitted(image, maxPointSize: 360)
        guard let data = fittedImage.jpegData(compressionQuality: 0.84) else { return nil }
        let folder = cacheFolder()
        let url = folder.appendingPathComponent(stableHex(key) + ".jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    /// Grooves, label art, and spindle baked into one image so a single layer can spin.
    static func vinyl(artwork: UIImage, diameter: CGFloat, scale: CGFloat) -> UIImage {
        let side = max(diameter, 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(scale, 1)
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            let center = CGPoint(x: side / 2, y: side / 2)
            let radius = side / 2

            cg.saveGState()
            cg.addEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
            cg.clip()

            let colors = [
                UIColor(white: 0.20, alpha: 1).cgColor,
                UIColor(white: 0.03, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: center.x - radius * 0.18, y: center.y - radius * 0.22),
                    startRadius: radius * 0.05,
                    endCenter: center,
                    endRadius: radius,
                    options: []
                )
            }

            let labelRadius = radius * 0.34
            var groove = radius - 3
            let inner = labelRadius + 5
            while groove > inner {
                let band = UIBezierPath(arcCenter: center, radius: groove, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                let bright = groove.truncatingRemainder(dividingBy: 9) < 1.6
                UIColor.white.withAlphaComponent(bright ? 0.10 : 0.045).setStroke()
                band.lineWidth = bright ? 0.8 : 0.45
                band.stroke()
                groove -= 2.15
            }

            UIColor.white.withAlphaComponent(0.22).setStroke()
            let rim = UIBezierPath(arcCenter: center, radius: radius - 1.4, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            rim.lineWidth = 1.2
            rim.stroke()

            cg.saveGState()
            let labelRect = CGRect(
                x: center.x - labelRadius,
                y: center.y - labelRadius,
                width: labelRadius * 2,
                height: labelRadius * 2
            )
            cg.addEllipse(in: labelRect)
            cg.clip()
            artwork.draw(in: labelRect)
            cg.restoreGState()

            UIColor.black.withAlphaComponent(0.55).setStroke()
            let labelRing = UIBezierPath(arcCenter: center, radius: labelRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            labelRing.lineWidth = 1
            labelRing.stroke()

            let hole = radius * 0.035
            UIColor.black.setFill()
            UIBezierPath(arcCenter: center, radius: hole, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            UIColor.white.withAlphaComponent(0.35).setStroke()
            let holeRing = UIBezierPath(arcCenter: center, radius: hole + 1.2, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            holeRing.lineWidth = 0.8
            holeRing.stroke()

            cg.restoreGState()
        }
    }

    private static func cacheFolder() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func stableIndex(_ string: String) -> Int {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(hash % UInt64(palette.count))
    }

    static func stableHex(_ string: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private static func makeNoise() -> UIImage {
        let side = 128
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        var state: UInt64 = 0x6a09e667f3bcc909
        for index in 0..<(side * side) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8((state >> 33) & 0xff)
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = 255
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: side,
                height: side,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return UIImage()
        }
        return UIImage(cgImage: image)
    }
}
