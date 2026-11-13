import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ top: UInt32, _ bottom: UInt32) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
}

func ellipse(_ c: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat, angle: CGFloat = 0) -> CGPath {
    var t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &t)
}

func draw(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size) / 1024
    c.scaleBy(x: s, y: s)
    c.setAllowsAntialiasing(true)
    c.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.35))
    c.addPath(squircle)
    c.setFillColor(rgb(0x1c1c20))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(squircle)
    c.clip()
    c.drawLinearGradient(gradient(0x303036, 0x141417), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    c.addPath(squircle)
    c.setStrokeColor(rgb(0xffffff, 0.08))
    c.setLineWidth(3)
    c.strokePath()

    let barRect = CGRect(x: 236, y: 318, width: 552, height: 44)
    c.addPath(CGPath(roundedRect: barRect, cornerWidth: 22, cornerHeight: 22, transform: nil))
    c.setFillColor(rgb(0xe9e6df))
    c.fillPath()

    for x in [468.0, 548.0] {
        c.addPath(CGPath(roundedRect: CGRect(x: x - 7, y: 358, width: 14, height: 98), cornerWidth: 7, cornerHeight: 7, transform: nil))
        c.setFillColor(rgb(0xc9780f))
        c.fillPath()
    }

    c.saveGState()
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 395, y: 560))
    tail.addCurve(to: CGPoint(x: 205, y: 470), control1: CGPoint(x: 320, y: 560), control2: CGPoint(x: 250, y: 520))
    tail.addCurve(to: CGPoint(x: 228, y: 436), control1: CGPoint(x: 195, y: 458), control2: CGPoint(x: 210, y: 436))
    tail.addCurve(to: CGPoint(x: 430, y: 470), control1: CGPoint(x: 320, y: 430), control2: CGPoint(x: 390, y: 450))
    tail.closeSubpath()
    c.addPath(tail)
    c.clip()
    c.drawLinearGradient(gradient(0xff9a1f, 0xe9760a), start: CGPoint(x: 300, y: 580), end: CGPoint(x: 300, y: 420), options: [])
    c.restoreGState()

    c.saveGState()
    let torso = ellipse(c, center: CGPoint(x: 520, y: 540), rx: 190, ry: 128, angle: 0.12)
    c.addPath(torso)
    c.clip()
    c.drawLinearGradient(gradient(0xffb340, 0xff8a00), start: CGPoint(x: 520, y: 690), end: CGPoint(x: 520, y: 400), options: [])
    c.restoreGState()

    c.saveGState()
    c.addPath(ellipse(c, center: CGPoint(x: 660, y: 640), rx: 82, ry: 78))
    c.clip()
    c.drawLinearGradient(gradient(0xffc15a, 0xff9a1f), start: CGPoint(x: 660, y: 720), end: CGPoint(x: 660, y: 560), options: [])
    c.restoreGState()

    let beak = CGMutablePath()
    beak.move(to: CGPoint(x: 722, y: 662))
    beak.addLine(to: CGPoint(x: 806, y: 632))
    beak.addLine(to: CGPoint(x: 724, y: 608))
    beak.closeSubpath()
    c.addPath(beak)
    c.setFillColor(rgb(0xf5f1e8))
    c.fillPath()

    c.addPath(ellipse(c, center: CGPoint(x: 500, y: 540), rx: 112, ry: 62, angle: 0.28))
    c.setFillColor(rgb(0xd9710a))
    c.fillPath()

    c.addPath(ellipse(c, center: CGPoint(x: 684, y: 656), rx: 13, ry: 13))
    c.setFillColor(rgb(0x17120a))
    c.fillPath()
    c.addPath(ellipse(c, center: CGPoint(x: 689, y: 661), rx: 4, ry: 4))
    c.setFillColor(rgb(0xffffff, 0.9))
    c.fillPath()

    c.restoreGState()
    return c.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let entries: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)@\(entry.scale)x.png"
    write(draw(size: pixels), to: output.appendingPathComponent(name))
    images.append(["size": "\(entry.points)x\(entry.points)", "idiom": "mac", "filename": name, "scale": "\(entry.scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("Contents.json"))
write(draw(size: 1024), to: URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "preview.png"))
