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
                    HStack(spacing: 4) {
                        ForEach(settings.linkTemplate.blocks.indices, id: \.self) { index in
                            blockField(index)
                            if index < settings.linkTemplate.blocks.count - 1 {
                                Text("-").foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    Text("Laissez un bloc vide pour le tirer au hasard.")
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

    private func blockField(_ index: Int) -> some View {
        TextField("aléatoire", text: Binding(
            get: { settings.linkTemplate.blocks[index].value },
            set: { newValue in
                let limit = settings.linkTemplate.blocks[index].length
                settings.linkTemplate.blocks[index].value = String(newValue.prefix(limit))
                persist()
            }
        ))
        .font(.system(.body, design: .monospaced))
        .multilineTextAlignment(.center)
        .frame(width: 64)
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
        case .pink: return .pink
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

private extension IconColor {
    var displayName: String {
        switch self {
        case .white: return "Blanc"
        case .red: return "Rouge"
        case .pink: return "Rose"
        case .green: return "Vert"
        case .blue: return "Bleu"
        case .bicolor: return "Bicolore"
        }
    }
}
