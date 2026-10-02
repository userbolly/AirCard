import AppKit
import CoreText

enum TapCounterRenderer {
    static let canvas = CGSize(width: 1536, height: 969)

    static func png(base: NSImage, counter: WalletTapCounter?, at date: Date = Date()) -> Data? {
        guard base.size.width > 0, base.size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1536, pixelsHigh: 969,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let scale = max(canvas.width / base.size.width, canvas.height / base.size.height)
        let size = CGSize(width: base.size.width * scale, height: base.size.height * scale)
        base.draw(in: CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                             width: size.width, height: size.height), from: .zero, operation: .copy, fraction: 1)
        if let counter, counter.enabled {
            let style = counter.appearance.normalized
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            var attributes: [NSAttributedString.Key: Any] = [
                .font: style.uiFont, .foregroundColor: style.textColor.uiColor, .paragraphStyle: paragraph
            ]
            if style.shadowEnabled {
                let shadow = NSShadow()
                shadow.shadowColor = style.shadowColor.uiColor
                shadow.shadowBlurRadius = style.shadowBlur
                shadow.shadowOffset = CGSize(width: 1, height: -2)
                attributes[.shadow] = shadow
            }
            if style.outlineWidth > 0 {
                attributes[.strokeWidth] = -style.outlineWidth
                attributes[.strokeColor] = style.outlineColor.uiColor
            }
            let label = counter.label(at: date) as NSString
            let width = min(ceil(label.size(withAttributes: attributes).width) + 2, canvas.width - 16)
            let height = ceil(style.uiFont.ascender - style.uiFont.descender + style.uiFont.leading) + 4
            let insetX = canvas.width * style.horizontalInset / 100
            let insetY = canvas.height * style.verticalInset / 100
            let x: CGFloat, top: CGFloat
            switch style.anchor {
            case .bottomLeft: x = insetX; top = canvas.height - insetY - height
            case .bottomRight: x = canvas.width - insetX - width; top = canvas.height - insetY - height
            case .topLeft: x = insetX; top = insetY
            case .topRight: x = canvas.width - insetX - width; top = insetY
            case .center: x = (canvas.width - width) / 2 + insetX; top = (canvas.height - height) / 2 + insetY
            }
            let constrainedX = max(8, min(canvas.width - width - 8, x))
            let constrainedTop = max(8, min(canvas.height - height - 8, top))
            // AppKit bitmap coordinates start at the bottom. No box is drawn.
            label.draw(in: CGRect(x: constrainedX, y: canvas.height - constrainedTop - height,
                                  width: width, height: height), withAttributes: attributes)
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func image(base: NSImage, counter: WalletTapCounter?) -> NSImage? {
        png(base: base, counter: counter).flatMap { NSImage(data: $0) }
    }

    // Preview-only overlay measured from Wallet screenshots (529 × 334 card).
    // It deliberately does not participate in png(base:counter:), which is flashed.
    static func walletNumberGuide(digits: String, color: NSColor) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1536, pixelsHigh: 969,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext.current?.cgContext else { return nil }
        context.clear(CGRect(origin: .zero, size: canvas))
        let sx = canvas.width / 529, sy = canvas.height / 334
        context.setFillColor(color.cgColor)
        for x in [32.0, 44.0, 56.0, 68.0] {
            context.fillEllipse(in: CGRect(x: (x - 2.6) * sx, y: (334 - 300 - 2.6) * sy,
                                          width: 5.2 * sx, height: 5.2 * sy))
        }
        let number = String(digits.filter { $0.isASCII && $0.isNumber }.prefix(4))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: number.isEmpty ? "1234" : number,
            attributes: [.font: NSFont.systemFont(ofSize: 24 * sx, weight: .medium), .foregroundColor: color]))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 84 * sx, y: (334 - 307) * sy)
        CTLineDraw(line, context)
        return bitmap.representation(using: .png, properties: [:]).flatMap { NSImage(data: $0) }
    }
}
