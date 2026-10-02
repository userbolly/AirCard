import Foundation
import CryptoKit

struct WalletTapCounter: Codable, Equatable, Identifiable, Sendable {
    var id: String { Self.id(deviceID: deviceID, cardID: cardID) }
    let deviceID: String
    let cardID: String
    var shortcutKey = UUID().uuidString.lowercased()
    var name: String
    var enabled: Bool
    var appearance = TapCounterAppearance.standard
    var months: [String: Int] = [:]
    var revision = 0
    var appliedRevision: Int?
    var appliedMonth: String?
    var lastError: String?

    static func id(deviceID: String, cardID: String) -> String { deviceID + "|" + cardID }
    static func month(at date: Date = Date(), calendar: Calendar = .current) -> String {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let parts = local.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    func count(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        months[Self.month(at: date, calendar: calendar), default: 0]
    }

    func needsUpdate(at date: Date = Date()) -> Bool {
        appliedRevision != revision || appliedMonth != Self.month(at: date)
    }

    func label(at date: Date = Date(), calendar: Calendar = .current) -> String {
        let month = Self.month(at: date, calendar: calendar)
        let index = Int(month.suffix(2)) ?? 1
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        let style = appearance.normalized
        let count = count(at: date, calendar: calendar)
        let unit = style.unit == "taps" && count == 1 ? "tap" : style.unit
        var parts: [String] = []
        if !style.prefix.isEmpty { parts.append(style.prefix) }
        if style.showCardName { parts.append(name) }
        if style.showMonth { parts.append(formatter.shortMonthSymbols[max(0, min(11, index - 1))]) }
        parts.append("\(count)\(unit.isEmpty ? "" : " " + unit)")
        if !style.suffix.isEmpty { parts.append(style.suffix) }
        let result = parts.joined(separator: style.separator)
        return style.uppercase ? result.uppercased() : result
    }

    func artworkSignature(base: String, at date: Date = Date()) -> String {
        guard enabled else { return base }
        struct Fingerprint: Encodable { let base: String; let label: String; let style: TapCounterAppearance }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Fingerprint(base: base, label: label(at: date), style: appearance.normalized)) else { return base }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum WalletCounterError: LocalizedError {
    case invalidCard, missingArtwork, invalidCount, inboxTooLarge
    var errorDescription: String? {
        switch self {
        case .invalidCard: return "Choose a card scanned on the connected iPhone."
        case .missingArtwork: return "Choose the original skin image for this card first."
        case .invalidCount: return "Use a count from zero to one million."
        case .inboxTooLarge: return "The events file exceeds 10 MB. Choose a new events file in the counter setup."
        }
    }
}

/// The Mac only reads the Shortcuts inbox. Atomic local storage tracks delivered
/// events before artwork writes, and survives retries, truncation, and relaunches.
actor WalletTapCounterStore {
    private struct State: Codable {
        var records: [String: WalletTapCounter] = [:]
        var seen: Set<String> = []
    }
    private let fileURL: URL
    private var cached: State?
    private var inboxDigest: String?
    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirCard/TapCounters/store.json")
    }
    static var defaultInbox: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/AirCard-Taps/events.txt")
    }
    init(fileURL: URL = defaultFileURL) { self.fileURL = fileURL }

    static func validCard(_ id: String) -> Bool {
        (20...64).contains(id.count) && id.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+=-").contains($0)
        } && !(id.count == 36 && id.filter { $0 == "-" }.count == 4)
    }

    func records() throws -> [WalletTapCounter] { Array(try load().records.values) }

    @discardableResult
    func configure(deviceID: String, cardID: String, name: String, enabled: Bool,
                   appearance: TapCounterAppearance, count: Int? = nil, at date: Date = Date()) throws -> WalletTapCounter {
        guard !deviceID.isEmpty, Self.validCard(cardID) else { throw WalletCounterError.invalidCard }
        if let count, !(0...1_000_000).contains(count) { throw WalletCounterError.invalidCount }
        var state = try load()
        let id = WalletTapCounter.id(deviceID: deviceID, cardID: cardID)
        let name = String(name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(24))
        var record = state.records[id] ?? WalletTapCounter(deviceID: deviceID, cardID: cardID, name: name.isEmpty ? "Card" : name, enabled: enabled)
        record.name = name.isEmpty ? "Card" : name
        record.enabled = enabled
        record.appearance = appearance.normalized
        if let count { record.months[WalletTapCounter.month(at: date)] = count }
        record.revision += 1
        record.lastError = nil
        state.records[id] = record
        try persist(state)
        return record
    }

    func disable(deviceID: String, cardID: String) throws {
        var state = try load()
        let id = WalletTapCounter.id(deviceID: deviceID, cardID: cardID)
        guard var record = state.records[id] else { return }
        record.enabled = false
        record.revision += 1
        state.records[id] = record
        try persist(state)
    }

    @discardableResult
    func importInbox(_ url: URL, now: Date = Date(), calendar: Calendar = .current) throws -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= 10_000_000 else { throw WalletCounterError.inboxTooLarge }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest != inboxDigest else { return 0 }
        guard let text = String(data: data, encoding: .utf8) else { return 0 }
        let imported = try ingest(text, now: now, calendar: calendar)
        inboxDigest = digest
        return imported
    }

    @discardableResult
    func ingest(_ text: String, now: Date = Date(), calendar: Calendar = .current) throws -> Int {
        var state = try load()
        let mapping = Dictionary(uniqueKeysWithValues: state.records.values.map { ($0.shortcutKey, $0.id) })
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        var count = 0, changed = false
        let lines = text.components(separatedBy: "\n")
        for raw in lines.dropLast() {
            let pieces = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false)
            guard pieces.count == 2, let id = mapping[String(pieces[0])], var record = state.records[id],
                  let timestamp = fractional.date(from: String(pieces[1])) ?? standard.date(from: String(pieces[1])),
                  timestamp <= now.addingTimeInterval(86_400) else { continue }
            let event = record.shortcutKey + "|" + String(format: "%.3f", timestamp.timeIntervalSince1970)
            guard state.seen.insert(event).inserted else { continue }
            changed = true
            // Consume events while disabled so re-enabling does not back-count them.
            guard record.enabled else { continue }
            let month = WalletTapCounter.month(at: timestamp, calendar: calendar)
            record.months[month, default: 0] += 1
            record.revision += 1
            record.lastError = nil
            state.records[id] = record
            count += 1
        }
        if changed { try persist(state) }
        return count
    }

    func markApplied(_ snapshot: WalletTapCounter, month: String) throws {
        var state = try load()
        guard var record = state.records[snapshot.id] else { return }
        record.appliedRevision = snapshot.revision
        record.appliedMonth = month
        record.lastError = nil
        state.records[snapshot.id] = record
        try persist(state)
    }

    func markFailed(id: String, message: String) throws {
        var state = try load()
        guard var record = state.records[id] else { return }
        record.lastError = message
        state.records[id] = record
        try persist(state)
    }

    private func load() throws -> State {
        if let cached { return cached }
        let state = FileManager.default.fileExists(atPath: fileURL.path)
            ? try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL)) : State()
        cached = state
        return state
    }
    private func persist(_ state: State) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        cached = state
    }
}
