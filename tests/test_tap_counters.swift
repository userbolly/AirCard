import Foundation
import AppKit

@main
struct CounterTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("store.json")
        let store = WalletTapCounterStore(fileURL: file)
        let a = String(repeating: "A", count: 27) + "=", b = String(repeating: "B", count: 27) + "="
        let formatter = ISO8601DateFormatter()
        let october = formatter.date(from: "2026-10-12T12:00:00Z")!
        let november = formatter.date(from: "2026-11-12T12:00:00Z")!
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = try await store.configure(deviceID: "phone", cardID: a, name: "SoFi", enabled: true, appearance: .standard)
        let second = try await store.configure(deviceID: "phone", cardID: b, name: "Other", enabled: true, appearance: .standard)
        let sameOnOtherPhone = try await store.configure(deviceID: "second-phone", cardID: a, name: "Second phone", enabled: true, appearance: .standard)
        let line = first.shortcutKey + "|2026-10-12T12:00:00.123Z\n"
        let other = second.shortcutKey + "|2026-10-12T12:00:00.123Z\n"
        let imported = try await store.ingest(line + other + line, now: november, calendar: utc)
        precondition(imported == 2)
        var records = try await store.records()
        precondition(records.first { $0.id == first.id }!.count(at: october, calendar: utc) == 1)
        precondition(records.first { $0.id == second.id }!.count(at: october, calendar: utc) == 1)
        precondition(records.first { $0.id == sameOnOtherPhone.id }!.count(at: october, calendar: utc) == 0)
        precondition(records.first { $0.id == first.id }!.count(at: november, calendar: utc) == 0)
        let reopened = WalletTapCounterStore(fileURL: file)
        let repeated = try await reopened.ingest(line + other, now: november, calendar: utc)
        precondition(repeated == 0)
        print("PASS: per-card/device counts, monthly reset, deduplication, and relaunch persistence")

        let incomplete = first.shortcutKey + "|2026-10-12T12:00:01.000Z"
        let partialCount = try await store.ingest(incomplete, now: november, calendar: utc)
        precondition(partialCount == 0)
        let completeCount = try await store.ingest(incomplete + "\n", now: november, calendar: utc)
        precondition(completeCount == 1)
        let invalid = try await store.ingest(first.shortcutKey + "|bad timestamp\nunknown|2026-10-12T12:00:05Z\n", now: november, calendar: utc)
        precondition(invalid == 0)
        async let duplicateOne = store.ingest(line, now: november, calendar: utc)
        async let duplicateTwo = store.ingest(line, now: november, calendar: utc)
        let results = try await (duplicateOne, duplicateTwo)
        precondition(results.0 == 0 && results.1 == 0)
        print("PASS: partial writes, invalid events, and concurrent duplicate deliveries")

        try await store.disable(deviceID: "phone", cardID: a)
        _ = try await store.ingest(first.shortcutKey + "|2026-10-12T12:00:02.000Z\n", now: november, calendar: utc)
        let reenabled = try await store.configure(deviceID: "phone", cardID: a, name: "SoFi", enabled: true, appearance: .standard)
        precondition(reenabled.count(at: october, calendar: utc) == 2)
        let offEvent = try await store.ingest(first.shortcutKey + "|2026-10-12T12:00:02.000Z\n", now: november, calendar: utc)
        precondition(offEvent == 0)
        var style = TapCounterAppearance.standard
        style.font = .serif; style.fontSize = 77; style.showMonth = false; style.unit = ""
        let restyled = try await store.configure(deviceID: "phone", cardID: a, name: "SoFi", enabled: true, appearance: style)
        precondition(restyled.count(at: october, calendar: utc) == 2)
        let styleReload = try await WalletTapCounterStore(fileURL: file).records()
        precondition(styleReload.first { $0.id == first.id }!.appearance == style)
        precondition(styleReload.first { $0.id == second.id }!.appearance == .standard)
        print("PASS: disabled events, preserved history, and independent appearance settings")

        let captured = restyled
        _ = try await store.ingest(first.shortcutKey + "|2026-10-12T12:00:03.000Z\n", now: november, calendar: utc)
        try await store.markApplied(captured, month: "2026-10")
        records = try await store.records()
        let newer = records.first { $0.id == first.id }!
        precondition(newer.appliedRevision != newer.revision)
        try await store.markFailed(id: first.id, message: "Disconnected")
        let failed = try await WalletTapCounterStore(fileURL: file).records().first { $0.id == first.id }!
        precondition(failed.count(at: october, calendar: utc) == 3 && failed.lastError == "Disconnected")
        try await store.markApplied(newer, month: "2026-10")
        let after = try await store.records().first { $0.id == first.id }!
        precondition(after.count(at: october, calendar: utc) == 3 && after.lastError == nil)
        print("PASS: saved counts survive failed writes and taps during a write remain pending")

        let corruptFile = directory.appendingPathComponent("corrupt.json")
        let corrupt = Data("bad JSON".utf8); try corrupt.write(to: corruptFile)
        do { _ = try await WalletTapCounterStore(fileURL: corruptFile).records(); preconditionFailure("Corruption must be surfaced") }
        catch { precondition(error is DecodingError) }
        let preserved = try Data(contentsOf: corruptFile)
        precondition(preserved == corrupt)
        precondition(!WalletTapCounterStore.validCard("../../other/card.pkpass"))
        var eastern = utc; eastern.timeZone = TimeZone(identifier: "America/New_York")!
        precondition(WalletTapCounter.month(at: formatter.date(from: "2026-11-01T03:59:59Z")!, calendar: eastern) == "2026-10")
        precondition(WalletTapCounter.month(at: formatter.date(from: "2026-11-01T04:00:00Z")!, calendar: eastern) == "2026-11")
        precondition(WalletTapCounter.month(at: formatter.date(from: "2027-01-01T05:00:00Z")!, calendar: eastern) == "2027-01")
        print("PASS: corrupt-store protection, path validation, and local month/year boundaries")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1536, pixelsHigh: 969,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = TapCounterRenderer.canvas
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSBezierPath(rect: CGRect(origin: .zero, size: TapCounterRenderer.canvas)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let base = NSImage(data: bitmap.representation(using: .png, properties: [:])!)!
        var renderCounter = WalletTapCounter(deviceID: "phone", cardID: a, name: "SoFi", enabled: true)
        renderCounter.months[WalletTapCounter.month()] = 12
        renderCounter.appearance.textColor = .black
        let png = TapCounterRenderer.png(base: base, counter: renderCounter)!
        let output = NSBitmapImageRep(data: png)!
        precondition(output.pixelsWide == 1536 && output.pixelsHigh == 969)
        precondition(output.colorAt(x: 80, y: 780)!.redComponent > 0.95) // No old box.
        precondition(output.colorAt(x: 70, y: 925)!.redComponent > 0.95) // Wallet number area clear.
        var ink = 0
        for x in 40..<450 { for y in 775..<875 { if output.colorAt(x: x, y: y)!.redComponent < 0.3 { ink += 1 } } }
        precondition(ink > 100)
        var topRight = renderCounter
        topRight.appearance.anchor = .topRight; topRight.appearance.font = .rounded; topRight.appearance.fontSize = 80
        let custom = TapCounterRenderer.png(base: base, counter: topRight)!
        precondition(custom != png)
        renderCounter.enabled = false
        let uncounted = NSBitmapImageRep(data: TapCounterRenderer.png(base: base, counter: renderCounter)!)!
        precondition(uncounted.colorAt(x: 75, y: 820)!.redComponent > 0.95)
        print("PASS: plain text without a box, position/style rendering, and disabling the counter")
        if let previewPath = ProcessInfo.processInfo.environment["AIRCARD_COUNTER_PREVIEW"] {
            try png.write(to: URL(fileURLWithPath: previewPath))
        }
    }
}
