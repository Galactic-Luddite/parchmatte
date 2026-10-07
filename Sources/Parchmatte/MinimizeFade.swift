import CoreGraphics
import Foundation

/// Experimental minimize-only paper suppression driven by public geometry.
struct MinimizeFade {
    enum Action { case none, fadeOut, fadeIn }
    private let primeStretch: CGFloat
    private let minimumStretch: CGFloat

    init(detectShallowStretch: Bool = false) {
        // Cross-display Genie can stretch only ~6% before curving toward
        // the Dock. Keep the existing fade thresholds unless trialed.
        primeStretch = detectShallowStretch ? 1.02 : 1.08
        minimumStretch = detectShallowStretch ? 1.04 : 1.12
    }

    private(set) var isHidden = false
    private(set) var isRestoring = false
    private var previous: CGRect?
    private var previousTime: TimeInterval?
    private var resting: CGRect?
    /// The undistorted material footprint, retained through thumbnail/absence.
    var restingRect: CGRect? { resting }
    private var stableSince: TimeInterval?
    // Component-wise extrema across the entire stationary period. These
    // bound origin and size variation independently, rather than area.
    private var stableMinimum: CGRect?
    private var stableMaximum: CGRect?
    private var genieUntil: TimeInterval = 0
    private var fadeInUntil: TimeInterval = 0
    private var stretch: (horizontal: Bool, slope: Double, at: TimeInterval)?
    private var awaitingCollapse = false

    func isFadingIn(at time: TimeInterval) -> Bool { time < fadeInUntil }

    mutating func observe(_ rect: CGRect?, at time: TimeInterval, nearDisplayEdge: Bool) -> Action {
        guard let rect, rect.width > 0, rect.height > 0 else {
            previous = nil
            previousTime = nil
            stableSince = nil
            stableMinimum = nil
            stableMaximum = nil
            isRestoring = false
            genieUntil = 0
            stretch = nil
            awaitingCollapse = false
            return .none
        }
        let old = previous
        let elapsed = previousTime.map { time - $0 }
        // Bound the full observed range to two points. A +/-2pt radius
        // around an intermediate 602pt sample would accept both 600 and 604,
        // allowing a repeated Genie to poison the real restore footprint.
        let minimum = stableMinimum.map {
            CGRect(x: min(rect.minX, $0.minX), y: min(rect.minY, $0.minY),
                width: min(rect.width, $0.width), height: min(rect.height, $0.height))
        } ?? rect
        let maximum = stableMaximum.map {
            CGRect(x: max(rect.minX, $0.minX), y: max(rect.minY, $0.minY),
                width: max(rect.width, $0.width), height: max(rect.height, $0.height))
        } ?? rect
        let still = maximum.minX - minimum.minX <= 2 && maximum.minY - minimum.minY <= 2
            && maximum.width - minimum.width <= 2 && maximum.height - minimum.height <= 2
        if !still || stableSince == nil {
            stableSince = time
            stableMinimum = rect
            stableMaximum = rect
        } else {
            stableMinimum = minimum
            stableMaximum = maximum
        }
        previous = rect
        previousTime = time
        if resting == nil { resting = rect }

        if isHidden {
            // An early fade starts while the box is still larger than its
            // resting frame. A brief forward-animation pause is not restore.
            // Wait for contraction, absence, or the undistorted original size.
            // If an app imitated Genie but then stopped, one second of still
            // geometry recovers its paper rather than leaving it hidden.
            if awaitingCollapse, let resting {
                let contracted = rect.width < resting.width * 0.9 || rect.height < resting.height * 0.9
                let originalSize = abs(rect.width - resting.width) <= 2 && abs(rect.height - resting.height) <= 2
                let longStill = stableSince.map { time - $0 >= 1 } ?? false
                if contracted || originalSize || longStill {
                    awaitingCollapse = false
                } else {
                    isRestoring = false
                    return .none
                }
            }
            // Restore only near the original size, after motion has settled.
            // A Dock thumbnail can be stationary too; it must stay paperless.
            isRestoring = resting.map {
                rect.width >= $0.width - 2 && rect.height >= $0.height - 2
            } ?? false
            if isRestoring,
               let stableSince, time - stableSince >= 0.12 {
                isHidden = false
                isRestoring = false
                self.resting = rect
                genieUntil = 0
                stretch = nil
                fadeInUntil = time + 0.15
                return .fadeIn
            }
            return .none
        }
        // Genie first stretches one dimension while translating on the other
        // axis. Its later bounding box can contract toward a fixed corner,
        // just like a normal resize. Fade at an ongoing stretch instead of
        // waiting for the later collapse. Require a previously stretched
        // frame and an increasing translation/stretch slope. Genie curves;
        // a proportional animated move/resize has a constant slope. One
        // move/resize jump or dragging an already wide window cannot qualify.
        // A curving app-driven move/resize can still imitate Genie; the
        // stationary recovery above bounds that experimental false fade.
        // Retain the late hint for an animation sampled too sparsely to catch
        // that early sequence. Public geometry cannot prove a minimize event.
        if let resting {
            // Prime before the stronger threshold so contraction or a
            // metadata pause cannot teach an intermediate restore size.
            // The Ribbon trial accepts shallow cross-display stretches;
            // ongoing curvature still distinguishes them from linear resize.
            let horizontal = rect.width > resting.width * primeStretch && abs(rect.height - resting.height) <= 2
                && abs(rect.minY - resting.minY) > 4
            let vertical = rect.height > resting.height * primeStretch && abs(rect.width - resting.width) <= 2
                && abs(rect.minX - resting.minX) > 4
            if horizontal || vertical {
                // A settled ordinary resize can share this shape. Only
                // motion renews the hint, so its stable size is eventually
                // adopted instead of keeping the old reference forever.
                if !still { genieUntil = time + 0.5 }
                if let old, let elapsed, elapsed > 0, elapsed <= 0.15 {
                    let continuing = (horizontal && rect.width > resting.width * minimumStretch
                        && old.width > resting.width * primeStretch
                        && rect.width > old.width + 2 && abs(rect.height - old.height) <= 2
                        && abs(rect.minY - old.minY) > 2)
                        || (vertical && rect.height > resting.height * minimumStretch
                            && old.height > resting.height * primeStretch
                            && rect.height > old.height + 2 && abs(rect.width - old.width) <= 2
                            && abs(rect.minX - old.minX) > 2)
                    if continuing {
                        let slope = Double(horizontal ? abs(rect.minY - old.minY) / (rect.width - old.width)
                            : abs(rect.minX - old.minX) / (rect.height - old.height))
                        let prior = stretch
                        stretch = (horizontal, slope, time)
                        if let prior, prior.horizontal == horizontal, time - prior.at <= 0.15,
                           slope > prior.slope * 1.3, slope - prior.slope > 0.1 {
                            isHidden = true
                            awaitingCollapse = true
                            stableSince = nil
                            return .fadeOut
                        }
                    } else {
                        stretch = nil
                    }
                }
            } else {
                stretch = nil
            }
        }
        if nearDisplayEdge, let old, let elapsed, elapsed > 0, elapsed <= 0.15,
           rect.width < old.width * 0.97, rect.height < old.height * 0.97,
           abs(rect.midX - old.midX) > 4, abs(rect.midY - old.midY) > 4,
           (time < genieUntil ||
            (abs(rect.minX - old.minX) > 4 && abs(rect.minY - old.minY) > 4
             && abs(rect.maxX - old.maxX) > 4 && abs(rect.maxY - old.maxY) > 4)) {
            isHidden = true
            stableSince = nil
            return .fadeOut
        }
        // A legitimate resize can be followed immediately by minimization.
        // Remember anchored/centered resizing without waiting for the still
        // debounce, or a smaller restored window could stay hidden forever.
        // A primed Genie box can share an anchor; never adopt its dimensions.
        if let old, time >= genieUntil,
           abs(rect.width - old.width) > 2 || abs(rect.height - old.height) > 2 {
            let anchored = (abs(rect.minX - old.minX) <= 2 && abs(rect.minY - old.minY) <= 2)
                || (abs(rect.maxX - old.maxX) <= 2 && abs(rect.maxY - old.maxY) <= 2)
            let centered = abs(rect.midX - old.midX) <= 2 && abs(rect.midY - old.midY) <= 2
            // Growing one axis can be the opening Genie distortion. Growing
            // both axes is an ordinary resize and must update the restore
            // size immediately too. Stable frames still update below.
            let smaller = rect.width <= old.width && rect.height <= old.height
            let larger = rect.width > old.width + 2 && rect.height > old.height + 2
            if (anchored || centered), smaller || larger {
                resting = rect
            }
        }
        // A stable public bounding box can be a paused Genie frame, too.
        // Keep the original size while its animation hint is still primed.
        if time >= genieUntil, let stableSince, time - stableSince >= 0.15 { resting = rect }
        return .none
    }
}
