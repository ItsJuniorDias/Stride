// Cuts a rendered panorama into App Store slides (opaque PNGs, no alpha)
// and writes a scaled-down preview of the carousel with the store's gaps.
// swift slice.swift <panorama.png> <out dir> <slide width> <slide height> <name>...
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let panoramaURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let width = Int(args[3])!, height = Int(args[4])!
let names = Array(args[5...])

guard let source = CGImageSourceCreateWithURL(panoramaURL as CFURL, nil),
      let panorama = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Can't read \(panoramaURL.path)")
}
guard panorama.width >= width * names.count, panorama.height >= height else {
    fatalError("Panorama is \(panorama.width)×\(panorama.height), expected \(width * names.count)×\(height)")
}

func opaqueContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Can't write \(url.path)") }
}

try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var slides: [CGImage] = []
for (index, name) in names.enumerated() {
    let crop = panorama.cropping(to: CGRect(x: index * width, y: 0, width: width, height: height))!
    let context = opaqueContext(width, height)
    context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
    let slide = context.makeImage()!
    write(slide, to: outDir.appendingPathComponent("\(name).png"))
    slides.append(slide)
}

let scale = 0.18, gap = 36.0
let previewW = Int(Double(width * names.count) * scale + gap * Double(names.count + 1))
let previewH = Int(Double(height) * scale + gap * 2)
let preview = opaqueContext(previewW, previewH)
preview.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
preview.fill(CGRect(x: 0, y: 0, width: previewW, height: previewH))
preview.interpolationQuality = .high
for (index, slide) in slides.enumerated() {
    let rect = CGRect(x: gap + Double(index) * (Double(width) * scale + gap), y: gap,
                      width: Double(width) * scale, height: Double(height) * scale)
    preview.saveGState()
    preview.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil))
    preview.clip()
    preview.draw(slide, in: rect)
    preview.restoreGState()
}
write(preview.makeImage()!, to: outDir.appendingPathComponent("preview.png"))
print("\(names.count) slides → \(outDir.path)")
