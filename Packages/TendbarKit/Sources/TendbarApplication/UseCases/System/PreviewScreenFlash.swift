@MainActor
public final class PreviewScreenFlash {
    private let flasher: ScreenFlashing

    public init(flasher: ScreenFlashing) {
        self.flasher = flasher
    }

    public func execute() {
        flasher.flash(.attention)
    }
}
