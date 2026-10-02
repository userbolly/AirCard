import Foundation
import AppKit

@main
struct WalletViewModelTests {
    @MainActor
    static func main() async throws {
        let suite = "AirCardWalletTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = String(repeating: "A", count: 27) + "="
        let b = String(repeating: "B", count: 27) + "="
        let c = String(repeating: "C", count: 27) + "="
        defaults.set([b, a, b], forKey: "mak5er.aircard.savedCards")
        let vm = AppViewModel(cardDefaults: defaults, connectOnLaunch: false)
        precondition(vm.cards.map(\.id) == [b, a])
        precondition(vm.currentVerifiedCards.isEmpty) // Saved records stay hidden until this scan sees them.
        precondition(vm.confirmedCardIDs.isEmpty) // Legacy IDs have no device provenance.
        vm.activateCardDevice("first-phone")
        vm.isScanningCards = true
        vm.walletCatalog = WalletCatalog(paymentStatus: "matched", payments: [
            .init(id: a, name: "Active A", source: "payment"),
            .init(id: b, name: "Active B", source: "payment")
        ], memberships: [], warnings: [], cacheUpdatedAt: nil)
        vm.reconcileMatchedPaymentCards()
        precondition(vm.currentVerifiedCards.isEmpty) // A cache alone is not enough.
        vm.recordScannedCard(a)
        vm.recordScannedCard(a)
        precondition(vm.currentScanIDs == [a] && vm.confirmedCardIDs == [a, b])
        precondition(vm.currentVerifiedCardIDs == [a, b])
        precondition(vm.cards.count == 2)
        vm.isScanningCards = false
        let activation = "A00000000310100100000020"
        precondition(!vm.recordActivatedPaymentCard(activation))
        vm.walletCatalog = WalletCatalog(paymentStatus: "matched", payments: [.init(id: b, name: "Active B", source: "payment", activationID: activation)], memberships: [], warnings: [], cacheUpdatedAt: nil)
        vm.reconcilePendingPaymentActivations()
        precondition(vm.cards.first(where: { $0.id == b })?.displayName == "Active B")
        vm.cards[0].customImageURL = URL(fileURLWithPath: "/skin-b.png")
        vm.cards[1].customImageURL = URL(fileURLWithPath: "/skin-a.png")
        vm.cards.reverse()
        vm.activateCardDevice("second-phone")
        precondition(vm.confirmedCardIDs.isEmpty)
        precondition(vm.cards.allSatisfy { $0.customImageURL == nil })
        vm.recordScannedCard(b)
        vm.activateCardDevice("first-phone")
        precondition(vm.cards.map(\.id) == [a, b])
        precondition(vm.confirmedCardIDs == [a, b])
        precondition(vm.cards[0].customImageURL?.path == "/skin-a.png")
        precondition(vm.cards[1].customImageURL?.path == "/skin-b.png")
        vm.clearAllCards()
        vm.activateCardDevice("second-phone")
        precondition(vm.confirmedCardIDs == [b])
        vm.activateCardDevice("first-phone")
        precondition(vm.cards.isEmpty) // Clear must not resurrect legacy JSON/defaults.
        let relaunched = AppViewModel(cardDefaults: defaults, connectOnLaunch: false)
        relaunched.activateCardDevice("first-phone")
        precondition(relaunched.cards.isEmpty)
        relaunched.activateCardDevice("second-phone")
        precondition(relaunched.confirmedCardIDs == [b])
        let countBeforePreload = relaunched.cards.count
        relaunched.recordPreloadedCard(c)
        relaunched.recordPreloadedCard(c)
        precondition(relaunched.cards.count == countBeforePreload + 1)
        precondition(relaunched.cards.first(where: { $0.id == c })?.confirmed == true)
        precondition(relaunched.currentVerifiedCards.map(\.id) == [c])
        print("Wallet view model migration, device isolation, repeat scans, skin identity and clear/relaunch passed")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let skinURL = temp.appendingPathComponent("original.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = CGSize(width: 160, height: 100)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.blue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 160, height: 100)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: skinURL)
        let counterSuite = "AirCardCounterModelTests." + UUID().uuidString
        let counterDefaults = UserDefaults(suiteName: counterSuite)!
        defer { counterDefaults.removePersistentDomain(forName: counterSuite) }
        let saved = [WalletSavedCard(id: a, confirmed: true, imagePath: skinURL.path, selected: false)]
        counterDefaults.set(try JSONEncoder().encode(saved), forKey: "mak5er.aircard.wallet.v2.counter-phone")
        let counterStore = WalletTapCounterStore(fileURL: temp.appendingPathComponent("counts.json"))
        let counterVM = AppViewModel(cardDefaults: counterDefaults, connectOnLaunch: false, counterStore: counterStore)
        counterVM.activateCardDevice("counter-phone")
        counterVM.device = DeviceInfo(udid: "counter-phone", connected: true)
        counterVM.currentScanIDs = [a]
        counterVM.counterInboxURL = temp.appendingPathComponent("empty-inbox.txt")
        let restored = counterVM.cards[0]
        let baseSignature = CardItem.signature(of: skinURL)!
        precondition(restored.skinSignature == baseSignature)
        counterVM.flashedSkins = ["counter-phone|" + a: baseSignature]
        precondition(counterVM.isSkinFlashed(restored))
        try await counterVM.saveCounter(deviceID: "counter-phone", cardID: a, name: "SoFi", enabled: true, appearance: .standard)
        let counter = counterVM.counter(for: a)!
        precondition(counter.count() == 0 && counterVM.counterPreviews[a] != nil)
        precondition(!counterVM.isSkinFlashed(restored))
        counterVM.flashedSkins["counter-phone|" + a] = counter.artworkSignature(base: baseSignature)
        precondition(counterVM.isSkinFlashed(restored))
        let timestamp = ISO8601DateFormatter()
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        _ = try await counterStore.ingest(counter.shortcutKey + "|" + timestamp.string(from: Date()) + "\n")
        try await counterVM.reloadCounters()
        precondition(counterVM.counter(for: a)!.count() == 1 && !counterVM.isSkinFlashed(restored))
        try await counterVM.saveCounter(deviceID: "counter-phone", cardID: a, name: "SoFi", enabled: true, appearance: .standard)
        precondition(counterVM.counter(for: a)!.count() == 1)
        do {
            try await counterVM.saveCounter(deviceID: "other-phone", cardID: a, name: "Wrong", enabled: true, appearance: .standard)
            preconditionFailure("A different phone must not configure this card")
        } catch WalletCounterError.invalidCard { }
        let reloadedVM = AppViewModel(cardDefaults: counterDefaults, connectOnLaunch: false, counterStore: WalletTapCounterStore(fileURL: temp.appendingPathComponent("counts.json")))
        reloadedVM.activateCardDevice("counter-phone")
        reloadedVM.device = DeviceInfo(udid: "counter-phone", connected: true)
        try await reloadedVM.reloadCounters()
        precondition(reloadedVM.cards[0].skinSignature == baseSignature)
        precondition(reloadedVM.counter(for: a)!.count() == 1 && reloadedVM.counterPreviews[a] != nil)
        print("Restored skin signatures, counter save/preview, new event tracking, device validation and relaunch passed")
    }
}
