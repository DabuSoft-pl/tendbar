import AppKit
import SwiftUI

/// Tendbar's own mark for the menu bar and the pill: a round bird on a bar, drawn from the app icon's shapes.
/// Outlined while nothing needs you, filled when something does. It is a template image, so it takes the color
/// of the menu bar or of `foregroundStyle`.
struct TendbarMark: View {
    var filled: Bool
    var height: CGFloat = 13

    var body: some View {
        Image(nsImage: Self.image(filled: filled))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(height: height)
            .accessibilityHidden(true)
    }

    static func image(filled: Bool) -> NSImage {
        filled ? filledImage : outlinedImage
    }

    // MARK: Drawing, in the 1024-point space of tools/make-icon.swift

    private static let bounds = CGRect(x: 236, y: 318, width: 624, height: 412)
    static let aspectRatio = bounds.width / bounds.height

    private static let shape: CGPath = {
        let body = ellipse(560, 560, 210, 150)
        let head = ellipse(690, 650, 95, 90)
        let beak = CGMutablePath()
        beak.move(to: CGPoint(x: 760, y: 690))
        beak.addLine(to: CGPoint(x: 860, y: 650))
        beak.addLine(to: CGPoint(x: 765, y: 615))
        beak.closeSubpath()
        let bar = CGPath(roundedRect: CGRect(x: 236, y: 318, width: 552, height: 50), cornerWidth: 25, cornerHeight: 25, transform: nil)
        return body.union(head).union(beak).union(bar)
    }()

    private static let eye = ellipse(690, 662, 22, 22)

    private static let filledImage = render { shape.subtracting(eye) }

    /// A stroke inside the outline, about 1.3 points at the menu bar's 13-point height.
    private static let outlinedImage = render {
        shape.copy(strokingWithWidth: 80, lineCap: .round, lineJoin: .round, miterLimit: 4)
            .intersection(shape)
            .union(eye)
    }

    private static func render(_ path: @escaping () -> CGPath) -> NSImage {
        let size = NSSize(width: 18 * aspectRatio, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.height / bounds.height
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.addPath(path())
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }
}
