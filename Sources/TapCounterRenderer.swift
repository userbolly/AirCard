import AppKit

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
}
