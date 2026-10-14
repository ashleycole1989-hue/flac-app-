import UIKit

enum Theme {
    static let background = UIColor(red: 0.067, green: 0.067, blue: 0.071, alpha: 1)
    static let backgroundLift = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let ink = UIColor(white: 0.96, alpha: 1)
    static let muted = UIColor(white: 0.62, alpha: 1)
    static let amber = UIColor(red: 0.86, green: 0.62, blue: 0.36, alpha: 1)
    static let teal = UIColor(red: 0.45, green: 0.63, blue: 0.66, alpha: 1)
    static let cardBand = UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1)
    static let cardboard = UIColor(red: 0.74, green: 0.58, blue: 0.39, alpha: 1)
    static let cardboardDark = UIColor(red: 0.36, green: 0.25, blue: 0.15, alpha: 1)
    static let groove = UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)

    static func serif(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func sans(_ size: CGFloat, _ weight: UIFont.Weight = .medium) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }

    static func tracked(_ text: String, size: CGFloat, color: UIColor, kern: CGFloat = 1.3) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: sans(size, .semibold),
            .foregroundColor: color,
            .kern: kern
        ])
    }
}
