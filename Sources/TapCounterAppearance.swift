import AppKit

enum CounterFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "System", rounded = "Rounded", monospaced = "Monospaced", serif = "Serif"
    var id: Self { self }
}

enum CounterWeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular = "Regular", medium = "Medium", semibold = "Semibold", bold = "Bold", heavy = "Heavy"
    var id: Self { self }
    var uiWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }
}

enum CounterAnchor: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottomLeft = "Bottom left", bottomRight = "Bottom right"
    case topLeft = "Top left", topRight = "Top right", center = "Center"
    var id: Self { self }
}

struct CounterColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1
    static let white = CounterColor(red: 1, green: 1, blue: 1)
    static let black = CounterColor(red: 0, green: 0, blue: 0)
    var uiColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    init(_ color: NSColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        (color.usingColorSpace(.sRGB) ?? .white).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

struct TapCounterAppearance: Codable, Equatable, Sendable {
    var font: CounterFont = .system
    var weight: CounterWeight = .semibold
    var fontSize: Double = 44
    var textColor: CounterColor = .white
    var anchor: CounterAnchor = .bottomLeft
    var horizontalInset: Double = 3.125
    var verticalInset: Double = 13
    var shadowEnabled = false
    var shadowColor: CounterColor = .black
    var shadowBlur: Double = 3
    var outlineWidth: Double = 0
    var outlineColor: CounterColor = .black
    var showMonth = true
    var showCardName = false
    var uppercase = false
    var prefix = ""
    var suffix = ""
    var unit = "taps"
    var separator = " · "

    static let standard = TapCounterAppearance()

    var normalized: Self {
        var value = self
        value.fontSize = min(120, max(20, fontSize))
        value.horizontalInset = min(100, max(anchor == .center ? -100 : 0, horizontalInset))
        value.verticalInset = min(100, max(anchor == .center ? -100 : 0, verticalInset))
        value.shadowBlur = min(20, max(0, shadowBlur))
        value.outlineWidth = min(8, max(0, outlineWidth))
        value.prefix = String(prefix.prefix(24)).replacingOccurrences(of: "\n", with: " ")
        value.suffix = String(suffix.prefix(24)).replacingOccurrences(of: "\n", with: " ")
        value.unit = String(unit.prefix(16)).replacingOccurrences(of: "\n", with: " ")
        value.separator = String(separator.prefix(6)).replacingOccurrences(of: "\n", with: " ")
        return value
    }

    var uiFont: NSFont {
        let size = normalized.fontSize
        if font == .monospaced { return NSFont.monospacedSystemFont(ofSize: size, weight: weight.uiWeight) }
        let system = NSFont.systemFont(ofSize: size, weight: weight.uiWeight)
        let design: NSFontDescriptor.SystemDesign = font == .rounded ? .rounded : font == .serif ? .serif : .default
        return NSFont(descriptor: system.fontDescriptor.withDesign(design) ?? system.fontDescriptor, size: size) ?? system
    }
}
