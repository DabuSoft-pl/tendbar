import AppKit

enum MenuBarLabel {
    static func image(text: String?) -> NSImage {
        let bird = NSImage(named: "MenuBarIcon") ?? NSImage()
        let birdSize = NSSize(width: 30, height: 18)
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let textSize = text.map { ($0 as NSString).size(withAttributes: attributes) } ?? .zero
        let gap: CGFloat = text == nil ? 0 : 4
        let size = NSSize(width: birdSize.width + gap + ceil(textSize.width), height: birdSize.height)
        let image = NSImage(size: size, flipped: false) { _ in
            bird.draw(in: NSRect(origin: .zero, size: birdSize))
            if let text {
                (text as NSString).draw(
                    at: NSPoint(x: birdSize.width + gap, y: (size.height - textSize.height) / 2),
                    withAttributes: attributes
                )
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = text.map { "Tendbar, \($0)" } ?? "Tendbar"
        return image
    }
}
