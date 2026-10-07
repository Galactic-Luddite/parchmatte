import CoreGraphics
import Foundation

/// Real-app experimental placements. Inputs are public bounds in downward-Y
/// coordinates; the material and reference mesh still belong to Parchmatte.
/// These are inferred shapes, not the WindowServer's private Genie mesh.
enum AttachedPaperGeometry {
    enum Variant: String, CaseIterable { case curve, sheet, soft }
    struct Output {
        let progress: Double
        let fade: Double
        let center: CGPoint
        let mesh: RibbonGeometry.Mesh
    }
    static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    static func evaluate(source: CGRect, target: CGRect, variant: Variant) -> Output {
        let center = CGPoint(x: target.midX, y: target.midY)
        guard source.width >= 1, source.height >= 1, target.width >= 1, target.height >= 1,
              [source.minX, source.minY, source.width, source.height,
               target.minX, target.minY, target.width, target.height].allSatisfy(\.isFinite)
        else { return Output(progress: 1, fade: 0, center: .zero, mesh: .init(points: [], faces: [])) }
        let dx = target.midX - source.midX, dy = target.midY - source.midY
        let distance = hypot(dx, dy)
        let diagonal = hypot(source.width, source.height)
        let ratio = min(target.width / source.width, target.height / source.height)
        let nearRest = abs(dx) <= 2 && abs(dy) <= 2
            && abs(target.width - source.width) <= 2 && abs(target.height - source.height) <= 2
        let progress = nearRest ? 0 : ratio < 0.10 ? 1
            : min(1, 0.43 * smooth(distance / (diagonal * 0.2)) + 0.57 * smooth(1 - ratio))
        let state = RibbonGeometry.demoState(progress: progress)
        let shapeState = variant == .sheet
            ? RibbonGeometry.State(collapse: state.collapse * 0.45, travel: state.travel,
                                   scale: state.scale, alpha: state.alpha) : state
        let original = RibbonGeometry.mesh(size: source.size, state: shapeState)
        guard progress > 0 else { return Output(progress: 0, fade: 1, center: center, mesh: original) }

        let fold = smooth(progress / 0.43)
        let angle = atan2(dy, dx) * fold
        let cosine = cos(angle), sine = sin(angle)
        let points = original.points.enumerated().map { index, point -> RibbonGeometry.Point in
            let u = Double(index % (RibbonGeometry.columns + 1)) / Double(RibbonGeometry.columns)
            let v = Double(index / (RibbonGeometry.columns + 1)) / Double(RibbonGeometry.rows)
            // Bend the long folded axis into an arc instead of translating a
            // rigid strip. A sheet trial additionally narrows its trailing end.
            let taper = variant == .sheet ? 1 - fold * v * 0.65 : 1
            let x = point.x * taper
            let bend = (pow(u - 0.5, 2) - 0.125) * source.height * 0.24 * fold
            let y = point.y + bend
            return .init(x: x * cosine - y * sine, y: x * sine + y * cosine, z: point.z)
        }
        let radiusX = max(1, points.map { abs($0.x) }.max() ?? 1)
        let radiusY = max(1, points.map { abs($0.y) }.max() ?? 1)
        let fit = min(1, min(min(source.width, target.width) / (2 * radiusX),
                            min(source.height, target.height) / (2 * radiusY)))
        let inset = 1 - 0.15 * smooth(progress / 0.15)
        // Curve toward the side carrying the visible sheet. This offset is
        // deliberately a trial parameter; pixel capture never enters this code.
        let amount = 0.15 * hypot(target.width, target.height) * fold
        let directionX: Double = dx < 0 ? -1 : 1
        let directionY: Double = dy < 0 ? -1 : 1
        let normal = CGPoint(x: directionX * abs(dy) / max(1, distance),
                             y: -directionY * abs(dx) / max(1, distance))
        let positioned = CGPoint(x: center.x + normal.x * amount, y: center.y + normal.y * amount)
        let fade = variant == .soft ? 1 - smooth((progress - 0.68) / 0.32)
                                   : state.alpha / 0.6
        return Output(progress: progress, fade: fade, center: positioned,
            mesh: .init(points: points.map { .init(x: $0.x * fit * inset, y: $0.y * fit * inset, z: $0.z) },
                        faces: original.faces))
    }
}
