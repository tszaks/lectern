// Draws the Lectern app icon (1024 x 1024 PNG).
// Run: xcrun swift mac/icon/make-icon.swift <output.png>
// Design: macOS rounded-square tile in dark ink, a paper slide on top, and one amber
// "notes" bar below it (the single accent). Depth comes from soft shadows, not borders.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255,
                                            CGFloat(hex & 255) / 255, a])!
}
// CoreGraphics counts y from the bottom; this helper takes y from the top, like a design tool.
func rect(_ x: CGFloat, _ yTop: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(size) - yTop - h, width: w, height: h)
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fillGradient(_ path: CGPath, _ top: UInt32, _ bottom: UInt32, _ r: CGRect) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY), options: [])
    ctx.restoreGState()
}

// 1. The tile (Apple's grid: 824 x 824 with 100 px margin), with a soft drop shadow.
let tileRect = rect(100, 100, 824, 824)
let tile = rounded(tileRect, 186)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tile); ctx.setFillColor(color(0x1E2924)); ctx.fillPath()
ctx.restoreGState()
fillGradient(tile, 0x2C3B34, 0x151D19, tileRect)
// A faint light along the top edge gives the tile some volume.
ctx.saveGState()
ctx.addPath(tile); ctx.clip()
let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: tileRect.maxY), end: CGPoint(x: 512, y: tileRect.maxY - 260), options: [])
ctx.restoreGState()

// 2. The slide: a paper card in 16:9, lifted by a shadow.
let slideRect = rect(212, 236, 600, 338)
let slide = rounded(slideRect, 30)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.45))
ctx.addPath(slide); ctx.setFillColor(color(0xF5F0E6)); ctx.fillPath()
ctx.restoreGState()
fillGradient(slide, 0xFBF8F2, 0xEDE5D6, slideRect)
// A big title line on the slide, in soft ink (drops out at small sizes, on purpose).
ctx.addPath(rounded(rect(272, 330, 300, 40), 20)); ctx.setFillColor(color(0x1E2924, 0.22)); ctx.fillPath()
ctx.addPath(rounded(rect(272, 398, 210, 40), 20)); ctx.setFillColor(color(0x1E2924, 0.12)); ctx.fillPath()

// 3. The notes: one amber bar (the accent) and one quiet bar.
let noteRect = rect(282, 652, 460, 56)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: color(0x000000, 0.35))
ctx.addPath(rounded(noteRect, 28)); ctx.setFillColor(color(0xE2A23B)); ctx.fillPath()
ctx.restoreGState()
fillGradient(rounded(noteRect, 28), 0xEDB24E, 0xD8932B, noteRect)
ctx.addPath(rounded(rect(282, 740, 330, 56), 28)); ctx.setFillColor(color(0xF5F0E6, 0.28)); ctx.fillPath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
