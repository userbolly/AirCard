import SwiftUI
import AppKit

struct CounterEditorRequest: Identifiable {
    let deviceID: String
    let card: CardItem
    var id: String { WalletTapCounter.id(deviceID: deviceID, cardID: card.id) }
}

struct TapCounterSettingsView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let request: CounterEditorRequest
    @State private var name: String
    @State private var enabled: Bool
    @State private var appearance: TapCounterAppearance
    @State private var correction: Int
    @State private var countEdited = false
    @State private var saving = false
    @State private var error: String?
    @State private var showSetup = false

    init(vm: AppViewModel, request: CounterEditorRequest) {
        self.vm = vm; self.request = request
        let counter = vm.tapCounters[request.id]
        _name = State(initialValue: counter?.name ?? request.card.displayName ?? "My card")
        _enabled = State(initialValue: counter?.enabled ?? true)
        _appearance = State(initialValue: counter?.appearance ?? .standard)
        _correction = State(initialValue: counter?.count() ?? 0)
    }

    private var draft: WalletTapCounter {
        var record = vm.tapCounters[request.id] ?? WalletTapCounter(deviceID: request.deviceID,
            cardID: request.card.id, name: name, enabled: enabled)
        record.name = name; record.enabled = enabled; record.appearance = appearance
        if countEdited { record.months[WalletTapCounter.month()] = correction }
        return record
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Monthly tap counter").font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }.disabled(saving).keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : "Save") {
                    saving = true
                    error = nil
                    let firstSave = vm.tapCounters[request.id] == nil
                    Task {
                        do {
                            try await vm.saveCounter(deviceID: request.deviceID, cardID: request.card.id,
                                name: name, enabled: enabled, appearance: appearance,
                                count: countEdited ? correction : nil)
                            countEdited = false
                            correction = vm.tapCounters[request.id]?.count() ?? 0
                            saving = false
                            if firstSave { showSetup = true }
                        } catch { self.error = error.localizedDescription; saving = false }
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(saving || vm.isFlashing || (enabled && request.card.customImage == nil))
            }
            .padding(20)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    if let base = request.card.customImage,
                       let preview = TapCounterRenderer.image(base: base, counter: draft) {
                        Image(nsImage: preview).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Card preview, \(draft.label())")
                    } else { Label("Assign the original skin first", systemImage: "photo") }
                    Text("Live preview").font(.headline)
                    Text("Plain text with no background. Save, then use Flash Skins to apply it to Wallet.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("\(vm.tapCounters[request.id]?.count() ?? 0) recorded taps this month")
                        .font(.callout.monospacedDigit())
                    Text("Each new month starts at zero. The image refreshes when this Mac can reach the iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Auto-apply connected counter updates", isOn: $vm.counterAutoApply)
                    Text("AirCard must be open, and the card must be matched in this connection’s scan.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply this card now") {
                        vm.applySkin(cardIDs: [request.card.id])
                    }
                    .disabled(vm.isFlashing || vm.device?.udid != request.deviceID)
                    Text("Applies saved settings. Saving an appearance never adds a tap.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).frame(width: 380, alignment: .leading)
                Divider()
                Form {
                    Section("Card") {
                        Toggle("Enable monthly counter", isOn: $enabled)
                        TextField("Name", text: $name)
                    }
                    Section("Text style") {
                        Picker("Font", selection: $appearance.font) { ForEach(CounterFont.allCases) { Text($0.rawValue).tag($0) } }
                        Picker("Weight", selection: $appearance.weight) { ForEach(CounterWeight.allCases) { Text($0.rawValue).tag($0) } }
                        slider("Size", value: $appearance.fontSize, range: 20...120, unit: "px")
                        ColorPicker("Text color", selection: color(\.textColor), supportsOpacity: false)
                        Toggle("Uppercase", isOn: $appearance.uppercase)
                    }
                    Section("Position") {
                        Picker("Anchor", selection: $appearance.anchor) { ForEach(CounterAnchor.allCases) { Text($0.rawValue).tag($0) } }
                            .onChange(of: appearance.anchor) { _, anchor in
                                appearance.horizontalInset = anchor == .center ? 0 : 3.125
                                appearance.verticalInset = anchor == .center ? 0 : 13
                            }
                        slider("Horizontal", value: $appearance.horizontalInset,
                               range: appearance.anchor == .center ? -50...50 : 0...90, unit: "%")
                        slider("Vertical", value: $appearance.verticalInset,
                               range: appearance.anchor == .center ? -50...50 : 0...90, unit: "%")
                    }
                    Section("Text effects") {
                        Toggle("Shadow", isOn: $appearance.shadowEnabled)
                        if appearance.shadowEnabled {
                            ColorPicker("Shadow color", selection: color(\.shadowColor), supportsOpacity: true)
                            slider("Blur", value: $appearance.shadowBlur, range: 0...20, unit: "px")
                        }
                        slider("Outline", value: $appearance.outlineWidth, range: 0...8, unit: "%")
                        if appearance.outlineWidth > 0 { ColorPicker("Outline color", selection: color(\.outlineColor), supportsOpacity: false) }
                    }
                    Section("Label format") {
                        Toggle("Show month", isOn: $appearance.showMonth)
                        Toggle("Show card name", isOn: $appearance.showCardName)
                        TextField("Prefix", text: $appearance.prefix)
                        TextField("Unit (blank for number only)", text: $appearance.unit)
                        TextField("Suffix", text: $appearance.suffix)
                        TextField("Separator", text: $appearance.separator)
                        Button("Reset appearance") { appearance = .standard }
                    }
                    Section("Count correction") {
                        TextField("This month", value: correctedCount, format: .number)
                        Stepper("Adjust by one", value: correctedCount, in: 0...1_000_000)
                        Text("Use this to correct a test run or missed event. Appearance edits keep incoming taps intact.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        DisclosureGroup("Set up automatic counting in Shortcuts", isExpanded: $showSetup) {
                            Text("Save this card first, then use its event template in a Wallet Transaction automation.")
                            if let counter = vm.tapCounters[request.id] {
                                Button("Copy event template") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(counter.shortcutKey + "|[Formatted Date]", forType: .string)
                                }
                            }
                            Button("Create iCloud events folder") {
                                do { try vm.chooseCounterInbox(WalletTapCounterStore.defaultInbox.deletingLastPathComponent()) }
                                catch { self.error = error.localizedDescription }
                            }
                            Button("Choose synced events folder…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url {
                                    do { try vm.chooseCounterInbox(url) } catch { self.error = error.localizedDescription }
                                }
                            }
                            Text("Inbox: \(vm.counterInboxURL.path)").font(.caption).textSelection(.enabled)
                            Text(vm.counterStatus).font(.caption).foregroundStyle(.secondary)
                            Text("1. Shortcuts → Automation → Transaction. Select this card and Run Immediately.\n2. Format the Current Date using yyyy-MM-dd'T'HH:mm:ss.SSSXXX.\n3. Add a Text action with the copied template. Replace [Formatted Date] with the date action’s output.\n4. Append that text as a new line to iCloud Drive → Shortcuts → AirCard-Taps → events.txt.")
                                .font(.callout).textSelection(.enabled)
                            Link("Full setup guide", destination: URL(string: "https://github.com/userbolly/AirCard/blob/feature/monthly-tap-counter/docs/monthly-counters.md")!)
                        }
                    }
                    if let error { Section { Text(error).foregroundStyle(.red) } }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 960, height: 720)
        .onChange(of: vm.tapCounters[request.id]?.count()) { _, count in
            if !countEdited { correction = count ?? 0 }
        }
    }

    private var correctedCount: Binding<Int> {
        Binding(get: { correction }, set: { correction = $0; countEdited = true })
    }

    private func color(_ key: WritableKeyPath<TapCounterAppearance, CounterColor>) -> Binding<Color> {
        Binding(get: { Color(nsColor: appearance[keyPath: key].uiColor) },
                set: { appearance[keyPath: key] = CounterColor(NSColor($0)) })
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title, value: "\(Int(value.wrappedValue)) \(unit)")
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
        }
    }
}
