import CoreGraphics
import Foundation

/// The approved paper mesh, independent of window detection and rendering.
/// Coordinates use the reference's downward-positive Y. Golden fixtures were
/// generated from the original JavaScript, including lighting and face order.
enum RibbonGeometry {
    struct State {
        let collapse: Double
        let travel: Double
        let scale: Double
        let alpha: Double
    }
    struct Point { let x: Double; let y: Double; let z: Double }
    struct Face { let indices: [Int]; let depth: Double; let shade: Double }
    struct Mesh { let points: [Point]; let faces: [Face] }
    static let columns = 20
    static let rows = 14
    // A transition shrinks an actual window. Reject unsupported dimensions or
    // expansion before creating GPU vertices, including huge finite inputs.
    static let maximumSheetDimension: CGFloat = 65_536

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? max(0, min(1, value)) : 0
    }
    private static func smooth(_ value: Double) -> Double {
        let t = clamp(value)
        return t * t * (3 - 2 * t)
    }
    static func demoState(progress: Double) -> State {
        let p = clamp(progress)
        let t = clamp((p - 0.28) / 0.7)
        let travel = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        return State(collapse: smooth(p / 0.43), travel: travel,
                     scale: 1 - 0.66 * smooth((p - 0.73) / 0.27),
                     alpha: 0.6 * (1 - smooth((p - 0.88) / 0.12)))
    }
    static func mesh(size: CGSize, state: State) -> Mesh {
        guard size.width.isFinite, size.height.isFinite,
              (1...maximumSheetDimension).contains(size.width),
              (1...maximumSheetDimension).contains(size.height),
              state.scale.isFinite, (0...1).contains(state.scale)
        else { return Mesh(points: [], faces: []) }
        let collapse = clamp(state.collapse), travel = clamp(state.travel)
        let scale = state.scale
        let horizontalUnit = Double(size.width) / 326
        let verticalUnit = Double(size.height) / 212
        let angle = travel * 0.9, cosine = cos(angle), sine = sin(angle)
        var points: [Point] = []
        points.reserveCapacity((columns + 1) * (rows + 1))
        for j in 0...rows {
            for i in 0...columns {
                let u = Double(i) / Double(columns), v = Double(j) / Double(rows)
                let zig = cos(v * .pi * 6)
                var x = (u - 0.5) * Double(size.width) * (1 - 0.70 * collapse)
                    + sin(v * .pi * 2 + travel * 4) * 8 * horizontalUnit * collapse
                var y = (v - 0.5) * Double(size.height) * (1 - 0.94 * collapse)
                    + zig * 5 * verticalUnit * collapse
                let z = zig * 16 * horizontalUnit * collapse
                let rx = x * cosine - y * sine
                y = x * sine + y * cosine
                x = rx
                x *= 1 - 0.65 * travel
                y *= 1 - 0.65 * travel
                let perspective = 280 * horizontalUnit / (280 * horizontalUnit - z * 0.55)
                points.append(Point(x: x * scale * perspective, y: y * scale * perspective, z: z))
            }
        }
        var indexedFaces: [(index: Int, face: Face)] = []
        indexedFaces.reserveCapacity(columns * rows * 2)
        for j in 0..<rows {
            for i in 0..<columns {
                let a = j * (columns + 1) + i, b = a + 1
                let c = (j + 1) * (columns + 1) + i, d = c + 1
                for indices in [[a, b, c], [b, d, c]] {
                    let p = indices.map { points[$0] }
                    let ux = p[1].x - p[0].x, uy = p[1].y - p[0].y, uz = p[1].z - p[0].z
                    let vx = p[2].x - p[0].x, vy = p[2].y - p[0].y, vz = p[2].z - p[0].z
                    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
                    let length = sqrt(nx * nx + ny * ny + nz * nz)
                    let light = (nx * 0.3 - ny * 0.4 + abs(nz) * 0.72) / (length > 0 ? length : 1)
                    let face = Face(indices: indices, depth: (p[0].z + p[1].z + p[2].z) / 3,
                                    shade: collapse * 0.9 * (0.45 - light * 0.5))
                    indexedFaces.append((indexedFaces.count, face))
                }
            }
        }
        indexedFaces.sort {
            $0.face.depth == $1.face.depth ? $0.index < $1.index : $0.face.depth < $1.face.depth
        }
        return Mesh(points: points, faces: indexedFaces.map(\.face))
    }
}
