import SwiftUI
import AppKit
import VisioCore

struct SettingsView: View {
    var onChange: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(onChange: onChange)
                .tabItem { Label("Général", systemImage: "gearshape") }
            CalendarsSettings(onChange: onChange)
                .tabItem { Label("Calendriers", systemImage: "calendar") }
            ProvidersSettings(onChange: onChange)
                .tabItem { Label("Services visio", systemImage: "video") }
        }
        .frame(width: 480, height: 400)
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

    private func persist() {
        settings.save(to: AppGroup.defaults)
        onChange()
    }
}
