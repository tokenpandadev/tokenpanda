// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
#if DEBUG
// The PNG writer of the debug snapshot flags; release builds do not contain it.
import AppKit
import Text

/// Renders a screen or the item to a PNG through the view's own bitmap, at 2x. No screen capture, no permission.
@MainActor
public enum SnapshotWriter {
    static func png(of view: NSView, size: NSSize, scale: CGFloat = 2) -> Data? {
        view.frame = NSRect(origin: .zero, size: size)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        view.displayIgnoringOpacity(view.bounds, in: ctx)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    public static func writeScreen(_ screen: Screen, to url: URL) throws {
        let view = LineView()
        view.drawsStage = true
        view.lines = Grammar.popover(screen)
        guard let data = png(of: view, size: NSSize(width: LineView.width, height: view.contentHeight)) else { return }
        try data.write(to: url)
    }

    /// The item on a dark strip, as the draft's closed shot shows it.
    public static func writeItem(_ st: ItemState, to url: URL) throws {
        let image = ItemImage.make(st)
        let strip = StripView(image: image, stale: st.stale)
        guard let data = png(of: strip, size: NSSize(width: image.size.width + 24, height: 24)) else { return }
        try data.write(to: url)
    }

    final class StripView: NSView {
        let image: NSImage
        let stale: Bool
        init(image: NSImage, stale: Bool) { self.image = image; self.stale = stale; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(srgbRed: 28 / 255, green: 30 / 255, blue: 38 / 255, alpha: 1).setFill(); bounds.fill()
            // a template image on a dark bar is drawn white by the OS; here by hand
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                NSColor.white.set()
                self.image.draw(in: rect)
                rect.fill(using: .sourceIn)
                return true
            }
            tinted.draw(in: NSRect(x: 12, y: 1, width: image.size.width, height: image.size.height), from: .zero, operation: .sourceOver,
                        fraction: stale ? 0.5 : 0.92, respectFlipped: true, hints: nil)
        }
    }
}
#endif
