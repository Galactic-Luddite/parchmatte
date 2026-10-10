import Cocoa

/// A borderless, transparent, click-through panel holding a texture layer and
/// a lamp-tint layer. It never becomes key or main and never takes focus.
/// It is a non-activating panel because macOS only shows a background app's
/// windows on another app's full-screen Space when they are.
final class CoverWindow: NSPanel {
    private let textureLayer = CALayer()
    private let lampLayer = CAGradientLayer()
    private var restyle: (() -> Void)?
    private var backingObserver: NSObjectProtocol?
    private var restyleAfterRibbon = false
    private var ribbon: (renderer: RibbonRenderer, source: NSRect, restoring: Bool, started: TimeInterval, lampHidden: Bool)?
    private var ribbonTimer: Timer?
    private var invalidateRibbonDisplay: (() -> Void)?
    private var ribbonPhaseStarted: TimeInterval?
    private var ribbonMaterialPresented = false
    private var ribbonCenter: CGPoint?
    private var attachedRestingLevel: NSWindow.Level?
    private var attachedVariant: AttachedPaperGeometry.Variant?
    private var attachedOutput: AttachedPaperGeometry.Output?
    private var attachedObservedAt: TimeInterval = 0
    private var attachedSettledSince: TimeInterval?
    var isRibbonActive: Bool { ribbon != nil }
    private var restoreFadeUntil: TimeInterval = 0
    var isRestoreFadeActive: Bool { ProcessInfo.processInfo.systemUptime < restoreFadeUntil }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.autoresizingMask = [.width, .height]
        let root = CALayer()
        root.addSublayer(textureLayer)
        root.addSublayer(lampLayer)
        view.layer = root
        contentView = view

        lampLayer.type = .radial
        lampLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        lampLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        layoutLayers()
        // Moving to a display with a different pixel density needs the
        // texture re-rendered at that density.
        backingObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification, object: self, queue: .main
        ) { [weak self] _ in self?.backingChanged() }
    }

    private func backingChanged() {
        invalidatePreparedPaper()
        guard let ribbon else { restyle?(); return }
        // Genie can carry the panel from a 1x display onto a 2x display.
        // Keep its owned material and fold alive; update only the drawable
        // density, then regenerate the resting texture after the transition.
        restyleAfterRibbon = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ribbon.renderer.layer.contentsScale = backingScaleFactor
        ribbon.renderer.layer.drawableSize = CGSize(
            width: ribbon.source.width * backingScaleFactor,
            height: ribbon.source.height * backingScaleFactor)
        CATransaction.commit()
    }

    /// Covers are closed and replaced often (Space pool, re-homing), so the
    /// observer goes with the window rather than piling up.
    private func removeBackingObserver() {
        if let backingObserver { NotificationCenter.default.removeObserver(backingObserver) }
        backingObserver = nil
    }

    override func close() {
        invalidatePreparedPaper()
        cancelRibbon(reason: "close")
        removeBackingObserver()
        super.close()
    }

    override func orderOut(_ sender: Any?) {
        cancelRibbon(reason: "orderOut")
        super.orderOut(sender)
    }

    deinit { invalidatePreparedPaper(); invalidateRibbonDisplay?(); ribbonTimer?.invalidate(); removeBackingObserver() }

    /// Rounds the paper to match the covered window's corners, so none spills
    /// onto the desktop past them. Zero for whole-screen and full-screen covers.
    var cornerRadius: CGFloat = 0 {
        didSet {
            guard cornerRadius != oldValue else { return }
            invalidatePreparedPaper()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in [textureLayer, lampLayer] as [CALayer] {
                layer.cornerRadius = cornerRadius
                layer.cornerCurve = .continuous
                layer.masksToBounds = cornerRadius > 0
            }
            CATransaction.commit()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var applied: (CoverStyle, CGFloat, Bool)?
    // One prepared material across all covers, bounded by paperSnapshot's
    // pixel limit. Window-owned layers only; never a target/screen capture.
    private static weak var preparedOwner: CoverWindow?
    private static var preparedPaper: PaperSnapshot?

    private func invalidatePreparedPaper() {
        if Self.preparedOwner === self {
            Self.preparedOwner = nil
            Self.preparedPaper = nil
        }
    }

    func preparePaperForMotion() {
        guard !isRibbonActive else { return }
        if Self.preparedOwner === self, Self.preparedPaper?.logicalSize == frame.size { return }
        guard let paper = paperSnapshot() else { return }
        Self.preparedOwner = self
        Self.preparedPaper = paper
    }

    func motionPaperSnapshot() -> PaperSnapshot? {
        if Self.preparedOwner === self, let paper = Self.preparedPaper,
           paper.logicalSize == frame.size { return paper }
        return paperSnapshot()
    }

    /// Only this window can construct a source for the mesh. It contains our
    /// already-styled bundled texture/lamp, never target or screen pixels.
    struct PaperSnapshot {
        let image: CGImage
        let logicalSize: CGSize
        fileprivate init(image: CGImage, logicalSize: CGSize) {
            self.image = image
            self.logicalSize = logicalSize
        }
    }

    func paperSnapshot() -> PaperSnapshot? {
        let size = frame.size
        let scale = backingScaleFactor
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1, scale.isFinite, scale > 0 else { return nil }
        let width = ceil(size.width * scale), height = ceil(size.height * scale)
        // A bounded transient allocation, independent of cover count. Very
        // large unsupported covers keep the existing fade rather than stall.
        guard width <= 8192, height <= 8192, width * height <= 16_777_216,
              let context = CGContext(data: nil, width: Int(width), height: Int(height),
                  bitsPerComponent: 8, bytesPerRow: Int(width) * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        // Render only these owned layers, not the view/window/screen tree.
        textureLayer.render(in: context)
        if !lampLayer.isHidden { lampLayer.render(in: context) }
        guard let image = context.makeImage() else { return nil }
        return PaperSnapshot(image: image, logicalSize: size)
    }

    func apply(_ style: CoverStyle, hideFromCapture: Bool) {
        restyle = { [weak self] in self?.apply(style, hideFromCapture: hideFromCapture, force: true) }
        apply(style, hideFromCapture: hideFromCapture, force: false)
    }

    /// Re-renders only when something changed: settings changes restyle
    /// every cover, and most of them are already showing this style.
    private func apply(_ style: CoverStyle, hideFromCapture: Bool, force: Bool) {
        if !force, let applied, applied.0 == style, applied.1 == backingScaleFactor, applied.2 == hideFromCapture { return }
        cancelRibbon(reason: "restyle")
        invalidatePreparedPaper()
        applied = (style, backingScaleFactor, hideFromCapture)
        let texture = style.texture, softness = style.softness, opacity = style.opacity
        let lamp = style.lamp, lampMultiplier = LampStrength.multiplier(style.lampStrength)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let tile = texture.renderedTile(softness: softness, scale: backingScaleFactor, orientation: style.orientation)
        if let tile {
            textureLayer.backgroundColor = NSColor(patternImage: tile.image).cgColor
        } else {
            textureLayer.backgroundColor = nil
            NSLog("Parchmatte: failed to render texture %@", texture.rawValue)
        }
        let requestedLamp = lamp.tint.map { Double($0.alpha) * lampMultiplier } ?? 0
        let layerOpacities = AppInfo.coverOpacities(
            texture: opacity, maximumAlpha: tile?.maximumAlpha, lamp: requestedLamp
        )
        textureLayer.opacity = Float(layerOpacities.texture)
        if let tint = lamp.tint {
            let center = CGFloat(layerOpacities.lamp)
            lampLayer.colors = [
                tint.color.withAlphaComponent(center).cgColor,
                tint.color.withAlphaComponent(center * LampStrength.edgeRetention).cgColor,
            ]
            lampLayer.isHidden = false
        } else {
            lampLayer.isHidden = true
        }
        CATransaction.commit()
        sharingType = hideFromCapture ? .none : .readOnly
    }

    @discardableResult
    func beginRibbon(restoring: Bool) -> Bool {
        // A hidden cover has no compositor host for Metal presentation.
        // On macOS 13 retain the existing fade, not an unsynchronized timer.
        guard isVisible, #available(macOS 14.0, *) else { return false }
        let setup = ProcessInfo.processInfo.systemUptime
        cancelRibbon(reason: "replacement")
        let snapshot = motionPaperSnapshot()
        let materialReady = ProcessInfo.processInfo.systemUptime
        guard let snapshot, let renderer = RibbonRenderer(paper: snapshot),
              let root = contentView?.layer else {
            NSLog("Parchmatte: Ribbon material or renderer unavailable")
            return false
        }
        let rendererReady = ProcessInfo.processInfo.systemUptime
        let source = frame
        ribbon = (renderer, source, restoring, ProcessInfo.processInfo.systemUptime, lampLayer.isHidden)
        ribbonCenter = CGPoint(x: source.midX, y: source.midY)
        ribbonPhaseStarted = nil
        ribbonMaterialPresented = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.layer.frame = CGRect(origin: .zero, size: source.size)
        renderer.layer.contentsScale = backingScaleFactor
        renderer.layer.drawableSize = CGSize(width: source.width * backingScaleFactor,
                                            height: source.height * backingScaleFactor)
        root.addSublayer(renderer.layer)
        // A zero-alpha window can itself suppress display callbacks. Keep the
        // panel hosted and transparent via its empty mesh, not window alpha.
        if restoring { textureLayer.isHidden = true; lampLayer.isHidden = true }
        CATransaction.commit()
        // Departing static paper remains until the first queued mesh draw.
        alphaValue = 1
        let driver = RibbonDisplayDriver(layer: renderer.layer,
            framesPerSecond: screen?.maximumFramesPerSecond ?? 60) { [weak self] update in
                self?.drawRibbon(update)
            }
        invalidateRibbonDisplay = { driver.invalidate() }
        // Occlusion/lock/removal can stop display callbacks entirely. This
        // independent deadline bounds resources; it does not restore builds.
        let timer = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.finishRibbon(reason: "displayDeadline")
        }
        RunLoop.main.add(timer, forMode: .common)
        ribbonTimer = timer
        NSLog("Parchmatte: Ribbon begin phase=%@ setup_ms=%.2f material_ms=%.2f renderer_ms=%.2f", restoring ? "restore" : "minimize", (ProcessInfo.processInfo.systemUptime - setup) * 1000, (materialReady - setup) * 1000, (rendererReady - materialReady) * 1000)
        return true
    }

    /// Follow only observed target centers; no invented Dock destination.
    func observeRibbonTarget(_ target: NSRect) {
        guard let ribbon, !ribbon.restoring else { return }
        ribbonCenter = CGPoint(x: target.midX, y: target.midY)
    }

    @discardableResult
    func beginAttachedPaper(target: NSRect, variant: AttachedPaperGeometry.Variant, restoring: Bool, raiseDuringMotion: Bool = false) -> Bool {
        guard beginRibbon(restoring: restoring) else { return false }
        attachedVariant = variant
        if raiseDuringMotion {
            attachedRestingLevel = level
            // Host the empty Metal layer at the normal level until its first
            // draw. Only the motion material may rise above the native proxy.
            textureLayer.isHidden = true
            lampLayer.isHidden = true
        }
        ribbonTimer?.invalidate()
        observeAttachedPaper(target)
        // A stale observer must hide paper, not expose the old static square.
        // Fresh geometry keeps this transition alive for the actual OS motion.
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self, self.attachedVariant != nil else { return }
            if ProcessInfo.processInfo.systemUptime - self.attachedObservedAt > 0.16 {
                self.alphaValue = 0
                self.orderOut(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ribbonTimer = timer
        return true
    }

    func observeAttachedPaper(_ target: NSRect) {
        guard let ribbon, let variant = attachedVariant else { return }
        // The pure geometry uses downward-positive Y; negate AppKit's top.
        let source = CGRect(x: ribbon.source.minX, y: -ribbon.source.maxY,
                            width: ribbon.source.width, height: ribbon.source.height)
        let bounds = CGRect(x: target.minX, y: -target.maxY, width: target.width, height: target.height)
        attachedOutput = AttachedPaperGeometry.evaluate(source: source, target: bounds, variant: variant)
        attachedObservedAt = ProcessInfo.processInfo.systemUptime
        if attachedOutput?.progress == 0 {
            if attachedSettledSince == nil { attachedSettledSince = attachedObservedAt }
        } else { attachedSettledSince = nil }
    }

    @available(macOS 14.0, *)
    private func drawRibbon(_ update: CAMetalDisplayLink.Update) {
        guard let ribbon else { return }
        if let output = attachedOutput {
            if output.progress >= 1 {
                self.ribbon?.restoring = false
                finishRibbon(reason: "attached-docked")
                return
            }
            setFrameOrigin(NSPoint(x: output.center.x - ribbon.source.width / 2,
                                   y: -output.center.y - ribbon.source.height / 2))
            let result = ribbon.renderer.draw(mesh: output.mesh, canvasSize: ribbon.source.size,
                drawable: update.drawable, fade: output.fade)
            if result == .failed { alphaValue = 0; orderOut(nil); return }
            if result == .queued {
                if attachedRestingLevel != nil {
                    level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                textureLayer.isHidden = true
                lampLayer.isHidden = true
                CATransaction.commit()
                alphaValue = 1
                // Native bounds can be flat a few frames before the system's
                // animation proxy leaves. Keep the full material above it
                // during settlement, avoiding a bare frame at level handoff.
                if output.progress == 0, let settled = attachedSettledSince,
                   ProcessInfo.processInfo.systemUptime - settled >= 0.12 {
                    self.ribbon?.restoring = true
                    finishRibbon(reason: "attached-settled")
                }
            }
            return
        }
        if ribbonPhaseStarted == nil { ribbonPhaseStarted = update.targetPresentationTimestamp }
        let elapsed = update.targetPresentationTimestamp - ribbonPhaseStarted!
        // Fold completes in ~69ms; retain the approved relative phases.
        let t = min(1, max(0, elapsed / 0.16))
        if t >= 1 { finishRibbon(reason: "complete"); return }
        let state = RibbonGeometry.demoState(progress: ribbon.restoring ? 1 - t : t)
        let mesh = RibbonGeometry.mesh(size: ribbon.source.size, state: state)
        if let center = ribbonCenter, !ribbon.restoring {
            setFrameOrigin(NSPoint(x: center.x - ribbon.source.width / 2, y: center.y - ribbon.source.height / 2))
        }
        let result = ribbon.renderer.draw(mesh: mesh, canvasSize: ribbon.source.size,
            drawable: update.drawable, fade: state.alpha / AppInfo.maxOpacity)
        if result == .failed { failRibbon(); return }
        if result == .queued, !ribbonMaterialPresented {
            ribbonMaterialPresented = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textureLayer.isHidden = true
            lampLayer.isHidden = true
            CATransaction.commit()
            alphaValue = 1
        }
    }

    private func finishRibbon(reason: String) {
        guard let ribbon else { return }
        // A broken device cannot rely on another display callback to report
        // failure. Preserve the same late-failure fade and cleanup path.
        if ribbon.renderer.layer.device == nil { failRibbon(); return }
        let restoring = ribbon.restoring
        cancelRibbon(reason: reason)
        if restoring { alphaValue = 1 }
        else { alphaValue = 0; super.orderOut(nil) }
    }

    private func failRibbon() {
        guard let ribbon else { return }
        let restoring = ribbon.restoring
        cancelRibbon(reason: "drawableFailure")
        NSLog("Parchmatte: Ribbon drawable unavailable; returning to cover fade")
        alphaValue = 0
        if restoring {
            restoreFadeUntil = ProcessInfo.processInfo.systemUptime + 0.15
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.animator().alphaValue = 1
            }
        }
    }

    func cancelRibbon(reason: String = "manager") {
        invalidateRibbonDisplay?()
        invalidateRibbonDisplay = nil
        ribbonPhaseStarted = nil
        ribbonMaterialPresented = false
        ribbonTimer?.invalidate()
        ribbonTimer = nil
        if let restingLevel = attachedRestingLevel { level = restingLevel }
        attachedRestingLevel = nil
        attachedVariant = nil
        attachedOutput = nil
        attachedSettledSince = nil
        guard let old = ribbon else { return }
        NSLog("Parchmatte: Ribbon end phase=%@ reason=%@ elapsed_ms=%.2f", old.restoring ? "restore" : "minimize", reason, (ProcessInfo.processInfo.systemUptime - old.started) * 1000)
        old.renderer.reportPresentation()
        ribbon = nil
        ribbonCenter = nil
        if !old.restoring { alphaValue = 0 }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        old.renderer.layer.removeFromSuperlayer()
        textureLayer.isHidden = false
        lampLayer.isHidden = old.lampHidden
        CATransaction.commit()
        place(old.source)
        if restyleAfterRibbon {
            restyleAfterRibbon = false
            restyle?()
        }
    }

    /// Moves and resizes the window without animation, keeping layers in sync.
    func place(_ frame: NSRect) {
        guard frame != self.frame else { return }
        setFrame(frame, display: false)
        layoutLayers()
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: .zero, size: frame.size)
        textureLayer.frame = bounds
        lampLayer.frame = bounds
        CATransaction.commit()
    }
}
