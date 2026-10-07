import QuartzCore

/// Owns only the transient display subscription. The window retains this
/// through its cancellation closure; the delegate callback retains no window.
@available(macOS 14.0, *)
final class RibbonDisplayDriver: NSObject, CAMetalDisplayLinkDelegate {
    private let link: CAMetalDisplayLink
    private var active = true
    private var draw: ((CAMetalDisplayLink.Update) -> Void)?

    init(layer: CAMetalLayer, framesPerSecond: Int,
         draw: @escaping (CAMetalDisplayLink.Update) -> Void) {
        link = CAMetalDisplayLink(metalLayer: layer)
        self.draw = draw
        super.init()
        link.delegate = self
        let hz = Float(min(120, max(60, framesPerSecond)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: hz, preferred: hz)
        link.preferredFrameLatency = 1
        link.add(to: .main, forMode: .common)
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        draw?(update)
    }

    func invalidate() {
        guard active else { return }
        active = false
        draw = nil
        link.invalidate()
    }

    deinit { if active { link.invalidate() } }
}
