import Cocoa
import Metal
import QuartzCore

/// Public Metal renders only a CoverWindow-owned material snapshot. There is
/// one bound source texture; folded faces replace pixels instead of stacking
/// transparent layers, preserving the combined texture/lamp opacity budget.
final class RibbonRenderer {
    private final class PresentationStatistics {
        let lock = NSLock()
        var count = 0
        var queued = 0
        var skipped = 0
        var dropped = 0
        var slowestDraw: TimeInterval = 0
        var previous: TimeInterval = 0
        var largestGap: TimeInterval = 0
        func record(_ time: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            guard time > 0 else { dropped += 1; return }
            if previous > 0 { largestGap = max(largestGap, time - previous) }
            previous = time
            count += 1
        }
        func draw(_ result: DrawResult, duration: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            if result == .queued { queued += 1 }
            if result == .skipped { skipped += 1 }
            slowestDraw = max(slowestDraw, duration)
        }
        func report() {
            lock.lock(); defer { lock.unlock() }
            NSLog("Parchmatte: Ribbon presented frames=%d queued=%d skipped=%d dropped=%d largest_gap_ms=%.2f slowest_draw_ms=%.2f", count, queued, skipped, dropped, largestGap * 1000, slowestDraw * 1000)
        }
    }
    private let presentation = PresentationStatistics()
    let device: MTLDevice
    let layer = CAMetalLayer()
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let paper: MTLTexture
    private struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
        var shade: Float
        var fade: Float
    }
    private let buffers: [MTLBuffer]
    private let available = DispatchSemaphore(value: 3)
    private var bufferIndex = 0
    private static let vertexCount = RibbonGeometry.columns * RibbonGeometry.rows * 6

    // Shader compilation and device setup are invariant across covers. Warm
    // them once for the attached trial; textures/buffers stay per renderer.
    private static let sharedPipeline: (MTLDevice, MTLCommandQueue, MTLRenderPipelineState)? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float2 position; float2 uv; float shade; float fade; };
        struct O { float4 position [[position]]; float2 uv; float shade [[flat]]; float fade [[flat]]; };
        vertex O ribbonVertex(const device V *v [[buffer(0)]], uint i [[vertex_id]]) {
            O o; o.position = float4(v[i].position, 0, 1); o.uv=v[i].uv;
            o.shade=v[i].shade; o.fade=v[i].fade; return o;
        }
        fragment float4 ribbonFragment(O o [[stage_in]], texture2d<float> paper [[texture(0)]],
                                       constant float &maximumAlpha [[buffer(0)]]) {
            constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
            float4 p=paper.sample(s,o.uv);
            // Light changes the owned material's RGB, never its alpha budget.
            float brightness=clamp(1-o.shade, 0.0f, 2.0f);
            float fade=clamp(o.fade,0.0f,1.0f);
            float a=min(maximumAlpha,p.a*fade);
            float3 rgb=clamp(p.rgb*brightness*fade, float3(0), float3(a));
            return float4(rgb,a);
        }
        """
        let pipeline: MTLRenderPipelineState
        do {
            let library = try device.makeLibrary(source: shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "ribbonVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "ribbonFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = false
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Parchmatte: Ribbon pipeline unavailable: %@", String(describing: error))
            return nil
        }
        return (device, queue, pipeline)
    }()

    static func prepare() { _ = sharedPipeline }

    init?(paper source: CoverWindow.PaperSnapshot) {
        guard let (device, queue, pipeline) = Self.sharedPipeline else { return nil }
        self.pipeline = pipeline
        let image = source.image
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: image.width, height: image.height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
            withBytes: data, bytesPerRow: image.width * 4)
        var buffers: [MTLBuffer] = []
        for _ in 0..<3 {
            guard let buffer = device.makeBuffer(length: Self.vertexCount * MemoryLayout<Vertex>.stride,
                options: .storageModeShared) else { return nil }
            buffers.append(buffer)
        }
        self.device = device
        self.queue = queue
        self.paper = texture
        self.buffers = buffers
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.backgroundColor = NSColor.clear.cgColor
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 3
    }

    /// Caller commits the command. No waiting or unbounded GPU work is added
    /// to normal tracking; saturation drops this frame. Buffers remain owned
    /// by Metal until completion even if the cover cancels the transition.
    func render(mesh: RibbonGeometry.Mesh, to target: MTLTexture,
                canvasSize: CGSize, fade: Double) -> MTLCommandBuffer? {
        guard canvasSize.width >= 1, canvasSize.height >= 1,
              mesh.faces.count * 3 == Self.vertexCount,
              available.wait(timeout: .now()) == .success else { return nil }
        let buffer = buffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % buffers.count
        let vertices = buffer.contents().bindMemory(to: Vertex.self, capacity: Self.vertexCount)
        var n = 0
        for face in mesh.faces {
            for index in face.indices {
                let p = mesh.points[index]
                vertices[n] = Vertex(position: SIMD2(Float(p.x / canvasSize.width * 2), Float(-p.y / canvasSize.height * 2)),
                    uv: SIMD2(Float(index % (RibbonGeometry.columns + 1)) / Float(RibbonGeometry.columns),
                              Float(index / (RibbonGeometry.columns + 1)) / Float(RibbonGeometry.rows)),
                    shade: Float(face.shade), fade: Float(fade.isFinite ? max(0, min(1, fade)) : 0))
                n += 1
            }
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            available.signal()
            return nil
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setFragmentTexture(paper, index: 0)
        var maximumAlpha = Float(AppInfo.safeOpacity(AppInfo.maxOpacity))
        encoder.setFragmentBytes(&maximumAlpha, length: MemoryLayout<Float>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: n)
        encoder.endEncoding()
        let available = self.available
        command.addCompletedHandler { _ in available.signal() }
        return command
    }

    enum DrawResult { case queued, skipped, failed }

    /// The display link supplies a drawable only when the compositor wants
    /// a frame. Never call nextDrawable on the tracking/main run loop and
    /// never gate future draws on presentedTime (zero also means dropped).
    func draw(mesh: RibbonGeometry.Mesh, canvasSize: CGSize,
              drawable: CAMetalDrawable, fade: Double) -> DrawResult {
        let began = ProcessInfo.processInfo.systemUptime
        var outcome = DrawResult.failed
        defer { presentation.draw(outcome, duration: ProcessInfo.processInfo.systemUptime - began) }
        guard layer.device != nil else { return outcome }
        guard let command = render(mesh: mesh, to: drawable.texture, canvasSize: canvasSize, fade: fade) else {
            outcome = .skipped
            return outcome
        }
        let presentation = self.presentation
        drawable.addPresentedHandler { presentation.record($0.presentedTime) }
        // CAMetalDisplayLink requires rendering to be committed before the
        // supplied drawable is presented; it owns this presentation window.
        command.commit()
        drawable.present()
        outcome = .queued
        return outcome
    }

    func reportPresentation() { presentation.report() }
}
