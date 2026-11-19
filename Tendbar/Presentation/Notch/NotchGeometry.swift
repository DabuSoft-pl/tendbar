import AppKit

struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    init?(notchOf screen: NSScreen) {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }
        screenFrame = screen.frame
        notchWidth = screen.frame.width - left.width - right.width
        notchHeight = screen.safeAreaInsets.top
    }

    init(menuBarOf screen: NSScreen) {
        screenFrame = screen.frame
        notchWidth = 0
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        notchHeight = menuBar > 0 ? menuBar : 24
    }

    static func current() -> NotchGeometry? {
        if let notch = NSScreen.screens.lazy.compactMap(NotchGeometry.init(notchOf:)).first { return notch }
        return NSScreen.screens.first.map(NotchGeometry.init(menuBarOf:))
    }

    var hasNotch: Bool {
        notchWidth > 0
    }

    static let panelWidth: CGFloat = 420
    static let panelExtraHeight: CGFloat = 360

    var panelFrame: CGRect {
        let height = notchHeight + Self.panelExtraHeight
        return CGRect(
            x: screenFrame.midX - Self.panelWidth / 2,
            y: screenFrame.maxY - height,
            width: Self.panelWidth,
            height: height
        )
    }
}
