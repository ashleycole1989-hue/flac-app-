import UIKit

/// Taptic Engine ticks for the click wheel. iPhone 7 has the hardware for this.
final class Haptics {
    private let selection = UISelectionFeedbackGenerator()
    private let button = UIImpactFeedbackGenerator(style: .light)
    private let latch = UIImpactFeedbackGenerator(style: .rigid)

    func prepare() {
        selection.prepare()
        button.prepare()
        latch.prepare()
    }

    func tick() {
        selection.selectionChanged()
        selection.prepare()
    }

    func press() {
        button.impactOccurred(intensity: 0.72)
        button.prepare()
    }

    func select() {
        latch.impactOccurred(intensity: 1)
        latch.prepare()
    }
}
