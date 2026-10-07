import AppKit
import CoreImage
import Foundation

struct Record: Codable {
    let texture: String
    let softnessStep: Int
    let scale: Int
    let lamp: String
    let glow: String
    let strength: Double
    let maximumAlpha: Double
    let requestedLamp: Double
    let currentTextureOpacity: Double
    let currentLampOpacity: Double
    let currentMaximumCompositeAlpha: Double
    let candidateTextureOpacity: Double
    let candidateLampOpacity: Double
    let candidateMaximumCompositeAlpha: Double
    let premultipliedAlphaValid: Bool
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift render_budget_experiment.swift TEXTURE_DIR OUTPUT_DIR\n".utf8))
    exit(2)
}
let textureDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let textures = ["parchmatte", "matte", "chalkboard", "linen", "press", "vellum", "felt"]
let lamps: [(String, Double)] = [
    ("off", 0), ("candlelight", 0.16), ("lateNight", 0.24),
    ("readingLamp", 0.12), ("goldenHour", 0.16), ("gallery", 0.08), ("aurora", 0.10),
]
let glows: [(String, Double)] = [("subtle", 0.7), ("medium", 1), ("warm", 1.35)]
let strengths = [0.0, 0.15, 0.30, 0.45, 0.60]
let cap = 0.6
let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

func wrapped(_ tile: CIImage, extent: CGRect) -> CIImage {
    var result = tile
    for dy in -1...1 {
        for dx in -1...1 where dx != 0 || dy != 0 {
            result = tile.transformed(by: CGAffineTransform(
                translationX: CGFloat(dx) * extent.width, y: CGFloat(dy) * extent.height
            )).composited(over: result)
        }
    }
    return result
}

func alphaMeasurement(_ image: CGImage) -> (maximum: Double, premultipliedValid: Bool) {
    let rowBytes = image.width * 4
    var bytes = [UInt8](repeating: 0, count: rowBytes * image.height)
    let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let bitmapContext = CGContext(data: &bytes, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: rowBytes,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap.rawValue) else {
        return (0, false)
    }
    bitmapContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    var maximum: UInt8 = 0
    var valid = true
    for index in stride(from: 0, to: bytes.count, by: 4) {
        let alpha = bytes[index + 3]
        maximum = max(maximum, alpha)
        valid = valid && bytes[index] <= alpha && bytes[index + 1] <= alpha && bytes[index + 2] <= alpha
    }
    return (Double(maximum) / 255, valid)
}

var records: [Record] = []
var processedMeasurements: [String: (Double, Bool)] = [:]
for texture in textures {
    let url = textureDirectory.appendingPathComponent("\(texture).png")
    guard let sourceImage = NSImage(contentsOf: url),
          let source = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("cannot load \(url.path)")
    }
    let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
    for step in 0...20 {
        let amount = Double(step) / 20
        var softened = wrapped(CIImage(cgImage: source, options: [.colorSpace: NSNull()]), extent: extent)
        if amount > 0 {
            softened = softened
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: amount * 1.2])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 + amount * 1.6)),
                ])
        }
        guard let output = context.createCGImage(softened.cropped(to: extent), from: extent, format: .RGBA8,
                                                 colorSpace: source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!) else {
            fatalError("cannot render \(texture) step \(step)")
        }
        let measurement = alphaMeasurement(output)
        for scale in [1, 2] {
            processedMeasurements["\(texture)-\(step)-\(scale)"] = measurement
            for lamp in lamps {
                for glow in glows {
                    let requestedLamp = min(cap, lamp.1 * glow.1)
                    for strength in strengths {
                        let currentBudget = max(0, 1 - (1 - cap) / (1 - strength))
                        let currentLamp = min(requestedLamp, currentBudget)
                        let currentComposite = currentLamp + measurement.maximum * strength * (1 - currentLamp)
                        let candidateTexture = measurement.maximum > 0
                            ? min(strength, max(0, (cap - requestedLamp) / (measurement.maximum * (1 - requestedLamp))))
                            : strength
                        let candidateComposite = requestedLamp + measurement.maximum * candidateTexture * (1 - requestedLamp)
                        records.append(Record(
                            texture: texture, softnessStep: step, scale: scale,
                            lamp: lamp.0, glow: glow.0, strength: strength,
                            maximumAlpha: measurement.maximum, requestedLamp: requestedLamp,
                            currentTextureOpacity: strength, currentLampOpacity: currentLamp,
                            currentMaximumCompositeAlpha: currentComposite,
                            candidateTextureOpacity: candidateTexture, candidateLampOpacity: requestedLamp,
                            candidateMaximumCompositeAlpha: candidateComposite,
                            premultipliedAlphaValid: measurement.premultipliedValid
                        ))
                    }
                }
            }
        }
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(records).write(to: outputDirectory.appendingPathComponent("render-budget.json"))
var csv = "texture,softness_step,scale,lamp,glow,strength,maximum_alpha,requested_lamp,current_texture,current_lamp,current_composite,candidate_texture,candidate_lamp,candidate_composite,premultiplied_valid\n"
for record in records {
    csv += "\(record.texture),\(record.softnessStep),\(record.scale),\(record.lamp),\(record.glow),\(record.strength),\(record.maximumAlpha),\(record.requestedLamp),\(record.currentTextureOpacity),\(record.currentLampOpacity),\(record.currentMaximumCompositeAlpha),\(record.candidateTextureOpacity),\(record.candidateLampOpacity),\(record.candidateMaximumCompositeAlpha),\(record.premultipliedAlphaValid)\n"
}
try csv.write(to: outputDirectory.appendingPathComponent("render-budget.csv"), atomically: true, encoding: .utf8)

let maxCandidate = records.map(\.candidateMaximumCompositeAlpha).max() ?? 0
let invalidPremultiplied = processedMeasurements.values.filter { !$0.1 }.count
print("records=\(records.count) processed=\(processedMeasurements.count) maxCandidate=\(maxCandidate) invalidPremultiplied=\(invalidPremultiplied)")
