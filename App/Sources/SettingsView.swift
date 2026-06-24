import SwiftUI
import AppKit
import VisioCore

struct SettingsView: View {
    var onChange: () -> Void
    @State private var tab: Tab = .general

    private enum Tab { case general, calendars, providers }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(onChange: onChange)
                .tabItem { Label("Général", systemImage: "gearshape") }
                .tag(Tab.general)
            CalendarsSettings(onChange: onChange)
                .tabItem { Label("Calendriers", systemImage: "calendar") }
                .tag(Tab.calendars)
            ProvidersSettings(onChange: onChange)
                .tabItem { Label("Services visio", systemImage: "video") }
                .tag(Tab.providers)
        }
        .frame(width: 480, height: 400)
        // Always show Général when the window opens (don't restore the last tab).
        .onAppear { tab = .general }
    }
}

#Preview {
    SettingsView(onChange: {})
}

// MARK: - Calendars

private struct CalendarsSettings: View {
    var onChange: () -> Void
    @State private var settings = Settings.load(from: AppGroup.defaults)
    @State private var nodes: [CalendarNode] = EventKitCalendarService().calendars()

    private var bySource: [(source: String, calendars: [CalendarNode])] {
        Dictionary(grouping: nodes, by: \.sourceTitle)
            .map { (source: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Cochez les calendriers à inclure. Rien de coché = tous.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(bySource, id: \.source) { group in
                    Section(group.source) {
                        ForEach(group.calendars) { node in
                            Toggle(node.title, isOn: binding(for: node.id))
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear { settings = Settings.load(from: AppGroup.defaults) }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.selectedCalendarIDs.contains(id) },
            set: { isOn in
                if isOn { settings.selectedCalendarIDs.insert(id) }
                else { settings.selectedCalendarIDs.remove(id) }
                persist()
            }
        )
    }

    private func persist() {
        settings.save(to: AppGroup.defaults)
        onChange()
    }
}

// MARK: - Providers

private struct ProvidersSettings: View {
    var onChange: () -> Void
    @State private var settings = Settings.load(from: AppGroup.defaults)
    @State private var newName = ""
    @State private var newPattern = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Services visio reconnus (le motif est cherché dans l’URL).")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($settings.providers) { $provider in
                    HStack {
                        Toggle("", isOn: $provider.enabled).labelsHidden()
                        VStack(alignment: .leading) {
                            Text(provider.name)
                            Text(provider.pattern).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            settings.providers.removeAll { $0.id == provider.id }
                            persist()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                    .onChange(of: provider.enabled) { persist() }
                }
            }
            HStack {
                TextField("Nom", text: $newName)
                TextField("Motif (ex. vc.example.org)", text: $newPattern)
                Button("Ajouter") {
                    guard !newName.isEmpty, !newPattern.isEmpty else { return }
                    settings.providers.append(VideoProvider(name: newName, pattern: newPattern))
                    newName = ""; newPattern = ""
                    persist()
                }
            }
        }
        .padding()
        .onAppear { settings = Settings.load(from: AppGroup.defaults) }
    }

    private func persist() {
        settings.save(to: AppGroup.defaults)
        onChange()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    var onChange: () -> Void
    @State private var settings = VisioCore.Settings.load(from: AppGroup.defaults)
    private let browsers = LinkOpener.installedBrowsers()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Ouvrir les liens dans", selection: Binding(
                    get: { settings.openInBundleID },
                    set: { settings.openInBundleID = $0; persist() }
                )) {
                    Text("Navigateur par défaut").tag(String?.none)
                    if !browsers.isEmpty { Divider() }
                    ForEach(browsers) { browser in
                        Text(browser.name).tag(String?.some(browser.bundleID))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Couleur (appel imminent)")
                    HStack(spacing: 10) {
                        ForEach(IconColor.allCases, id: \.self) { color in
                            colorSwatch(color)
                        }
                    }
                }

                Section("Modèle de lien « Créer un lien »") {
                    TextField("URL de base", text: Binding(
                        get: { settings.linkTemplate.baseURL },
                        set: { settings.linkTemplate.baseURL = $0; persist() }
                    ))
                    HStack {
                        MaskComb(mask: $settings.linkTemplate.mask, onChange: persist)
                            .fixedSize()
                        Spacer()
                    }
                    Text("Laissez une case vide pour la tirer au hasard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Quitter visio-next") { NSApplication.shared.terminate(nil) }
            }
            .padding()
        }
        .onAppear { settings = VisioCore.Settings.load(from: AppGroup.defaults) }
    }

    private func colorSwatch(_ color: IconColor) -> some View {
        Button {
            settings.imminentColor = color
            persist()
        } label: {
            glyph(for: color)
                .frame(width: 20, height: 20)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.tint, lineWidth: settings.imminentColor == color ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(color.displayName)
    }

    @ViewBuilder private func glyph(for color: IconColor) -> some View {
        if color == .bicolor {
            Image("VisioIconColor").resizable().scaledToFit()
        } else {
            Image("VisioIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(swiftUIColor(color))
        }
    }

    private func swiftUIColor(_ color: IconColor) -> Color {
        switch color {
        case .white: return .white
        case .red: return .red
        case .orange: return .orange
        case .pink: return Color(red: 1.0, green: 0.18, blue: 0.60)
        case .green: return .green
        case .blue: return .blue
        case .bicolor: return .primary
        }
    }

    private func persist() {
        settings.save(to: AppGroup.defaults)
        onChange()
    }
}

// MARK: - Mask "comb" input (AppKit)

/// An OTP-style comb of single-character cells, backed by AppKit for proper text
/// behavior: native boxed/centered cells, auto-advance on type, backspace moves to the
/// previous cell, arrow keys and Tab move between cells, input lowercased to `[a-z0-9]`.
private struct MaskComb: NSViewRepresentable {
    @Binding var mask: [String]
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.setHuggingPriority(.required, for: .horizontal)

        var fields: [NSTextField] = []
        var groupIndex = 0
        var posInGroup = 0

        for index in mask.indices {
            let field = CombCell()
            field.tag = index
            field.delegate = context.coordinator
            field.alignment = .center
            field.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
            field.isBezeled = true
            field.bezelStyle = .squareBezel
            field.usesSingleLineMode = true
            field.placeholderAttributedString = NSAttributedString(string: "#", attributes: [
                .foregroundColor: NSColor.quaternaryLabelColor,   // faint marker = "random"
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            ])
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 28).isActive = true
            field.heightAnchor.constraint(equalToConstant: 30).isActive = true
            field.stringValue = index < mask.count ? mask[index] : ""
            stack.addArrangedSubview(field)
            fields.append(field)

            posInGroup += 1
            if groupIndex < LinkTemplate.groups.count - 1, posInGroup == LinkTemplate.groups[groupIndex] {
                let dash = NSTextField(labelWithString: "-")
                dash.textColor = .secondaryLabelColor
                stack.addArrangedSubview(dash)
                groupIndex += 1
                posInGroup = 0
            }
        }

        for i in 0..<max(0, fields.count - 1) { fields[i].nextKeyView = fields[i + 1] }
        context.coordinator.fields = fields
        return stack
    }

    func updateNSView(_ nsView: NSStackView, context: Context) {
        for field in context.coordinator.fields {
            let i = field.tag
            if i < mask.count, field.stringValue != mask[i] {
                field.stringValue = mask[i]
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: MaskComb
        var fields: [NSTextField] = []

        init(_ parent: MaskComb) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let char = field.stringValue.lowercased().last { $0.isLetter || $0.isNumber }.map(String.init) ?? ""
            field.stringValue = char
            setMask(field.tag, char)
            if !char.isEmpty { focus(field.tag + 1) }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }
            let i = field.tag
            switch selector {
            case #selector(NSResponder.deleteBackward(_:)):
                if field.stringValue.isEmpty {
                    if i > 0 { fields[i - 1].stringValue = ""; setMask(i - 1, ""); focus(i - 1) }
                } else {
                    field.stringValue = ""; setMask(i, "")
                }
                return true
            case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.insertBacktab(_:)):
                guard i > 0 else { return false }   // first cell → let the system move focus out
                focus(i - 1); return true
            case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.insertTab(_:)):
                guard i + 1 < fields.count else { return false }   // last cell → hand off to the system
                focus(i + 1); return true
            default:
                return false
            }
        }

        private func setMask(_ index: Int, _ value: String) {
            guard index >= 0, index < parent.mask.count else { return }
            parent.mask[index] = value
            parent.onChange()
        }

        private func focus(_ index: Int) {
            guard index >= 0, index < fields.count else { return }
            let field = fields[index]
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: field.stringValue.count)
        }
    }
}

/// A text field whose field editor draws no insertion-point caret — the focus ring
/// is enough to mark the active comb cell.
private final class CombCell: NSTextField {
    override class var cellClass: AnyClass? {
        get { CaretlessTextFieldCell.self }
        set {}
    }
}

private final class CaretlessTextFieldCell: NSTextFieldCell {
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        (editor as? NSTextView)?.insertionPointColor = .clear
        return editor
    }
}

private extension IconColor {
    var displayName: String {
        switch self {
        case .white: return "Blanc"
        case .red: return "Rouge"
        case .orange: return "Orange"
        case .pink: return "Rose"
        case .green: return "Vert"
        case .blue: return "Bleu"
        case .bicolor: return "Bicolore"
        }
    }
}
