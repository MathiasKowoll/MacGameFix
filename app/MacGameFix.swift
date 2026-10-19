// MacGameFix -- fixes that go into a game's own folder, and Wine modules.
//
// Every game fix this app carries lives in a game's own folder: a proxy DLL
// beside the game, and for one title registry keys in that game's own prefix.
// None of them changes CrossOver, so they work with CrossOver as CodeWeavers
// ships it, with CrossOver Preview, and with a Steam Play tool such as NotProton.
// The one exception is its own tab: the Wine modules (Engine.swift), which go
// into a CrossOver app or a NotProton runner.
//
// The app decides nothing about a fix. The installers under Resources are the
// same files fixes/ holds, and they answer every question about a game folder
// themselves: --status says what is there, a plain run installs, --restore
// undoes. This file is the window: it finds the folders, asks, and shows the
// answers. Core.swift runs the installers; Automation.swift keeps marked fixes
// applied in the background and takes newer fixes from the releases; MenuBar.swift
// is that background agent's menu bar item.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit
import CryptoKit
import UniformTypeIdentifiers

// MARK: - State

@MainActor
final class Model: ObservableObject {
    @Published var hits: [Hit] = []
    @Published var libraries: [URL] = []
    @Published var log: [String] = []
    @Published var busy = false { didSet { WindowApp.busy = busy } }
    @Published var status = ""

    @Published var games: [Game] = []
    @Published var catalogVersion = 0
    @Published var settings = AutoSettings.load()
    @Published var agentOn = LaunchAgent.enabled
    @Published var events: [AgentEvent] = []
    @Published var updateLine = ""
    /// A newer catalog the agent verified and was told to ask about first.
    @Published var waitingCatalog: Int?
    @Published var waitingModules: Int?
    @Published var modulesLine = ""
    /// What the agent knows of each marked game.
    @Published var keptLines: [KeptLine] = []
    /// Only the games that need the user; the menu bar opens the window so.
    @Published var onlyReview = CommandLine.arguments.contains("--review")
    /// The CrossOver apps and NotProton runners the Wine modules can go into.
    @Published var engineRows: [EngineRow] = []
    /// The CrossOver builds the Wine modules' catalog carries modules for.
    @Published var engineBuilds: [EngineBuild] = []
    /// The Game Feel tab's options, observations and presets.
    @Published var pad = PadStore.load()
    @Published var padGames: [InstalledGame] = []
    let padPresets = PadPresets.load()
    /// pad.conf and pad.d written by this launch, so they carry its keys and presets.
    private var padWritten = false
    @Published var modulesVersion = 0
    var resources = URL(fileURLWithPath: ".")
    /// The Wine modules' catalog in use, apart from the fixes'.
    var modulesDir = URL(fileURLWithPath: ".")

    private let extraKey = "extraFolders"

    /// Posted when the user has seen what the agent did; the menu bar drops its dot.
    static let seenNotification = Notification.Name("io.github.macgamefix.seen")
    /// Posted when a setting the menu bar shows changes.
    static let settingsNotification = Notification.Name("io.github.macgamefix.settings")

    init() {
        loadCatalog()
        refreshEvents()
        settings.seen = Date()
        settings.save()
        DistributedNotificationCenter.default().postNotificationName(Self.seenNotification, object: nil,
                                                                     deliverImmediately: true)
        // A moved app leaves the agent pointing at the old place, and an older
        // app wrote an older job. A menu bar item the user quit comes back
        // when the window opens.
        if agentOn, let me = Bundle.main.executablePath {
            if LaunchAgent.isCurrent(executable: me) {
                LaunchAgent.start()
            } else {
                try? LaunchAgent.enable(executable: me)
            }
        }
    }

    /// The catalog in use: the bundle's, or a newer verified download.
    func loadCatalog() {
        let (dir, manifest) = Catalog.active()
        resources = dir
        games = Catalog.games(in: dir)
        let modules = Catalog.active(.modules)
        modulesDir = modules.dir
        engineBuilds = Engine.builds(in: modules.dir)
        modulesVersion = modules.manifest?.version ?? 0
        catalogVersion = manifest?.version ?? 0
    }

    func refreshEvents() {
        let state = AgentState.load()
        events = state.events.reversed()
        keptLines = KeptLine.all(settings: settings, state: state)
        if !state.lastUpdate.isEmpty { updateLine = state.lastUpdate }
        waitingCatalog = state.waiting
        waitingModules = state.waitingModules
        modulesLine = state.lastModulesUpdate
    }

    func keptLine(_ hit: Hit) -> KeptLine? { keptLines.first { $0.key == hit.key } }
    var toReview: [KeptLine] { keptLines.filter(\.needsUser) }

    /// Stops keeping a game whose folder is gone.
    func forget(_ line: KeptLine) {
        settings.kept.removeAll { $0.key == line.key }
        settings.save()
        refreshEvents()
    }

    // MARK: Automatic

    func isKept(_ hit: Hit) -> Bool {
        settings.kept.contains { $0.key == hit.key }
    }

    func setKept(_ hit: Hit, _ on: Bool) {
        settings.kept.removeAll { $0.key == hit.key }
        if on {
            settings.kept.append(KeptGame(name: hit.game.name, folder: hit.folder.path,
                                          prefixes: hit.game.needsPrefix ? hit.chosen.map(\.path.path) : []))
        }
        settings.save()
        refreshEvents()
    }

    /// Adds a prefix to those a fix writes its registry keys into, or takes one
    /// out, and asks the installer again about those left. A game kept applied
    /// keeps the new set. What is already in a prefix taken out stays there
    /// until the fix is removed with that prefix chosen.
    func choosePrefix(_ hit: Hit, _ prefix: Prefix, _ on: Bool) {
        guard let i = hits.firstIndex(where: { $0.id == hit.id }) else { return }
        hits[i].chosen = hits[i].prefixes.filter { $0 == prefix ? on : hits[i].chosen.contains($0) }
        if hits[i].blocker != nil { hits[i].selected = false }
        if let k = settings.kept.firstIndex(where: { $0.key == hit.key }) {
            settings.kept[k].prefixes = hits[i].chosen.map(\.path.path)
            settings.save()
        }
        let id = hit.id
        Task {
            guard let j = hits.firstIndex(where: { $0.id == id }) else { return }
            let probed = await probe(hits[j])
            if let j = hits.firstIndex(where: { $0.id == id }) { hits[j].state = probed.state }
        }
    }

    func setBatteryIcon(_ icon: String) {
        settings.batteryIcon = icon
        settings.save()
        DistributedNotificationCenter.default().postNotificationName(Self.settingsNotification, object: nil,
                                                                     deliverImmediately: true)
        objectWillChange.send()
    }

    func setPadBattery(_ on: Bool) {
        settings.padBattery = on
        settings.save()
        DistributedNotificationCenter.default().postNotificationName(Self.settingsNotification, object: nil,
                                                                     deliverImmediately: true)
        objectWillChange.send()
    }

    func setAgent(_ on: Bool) {
        if on, let me = Bundle.main.executablePath {
            do { try LaunchAgent.enable(executable: me) } catch { note("Could not start the agent: \(error.localizedDescription)") }
        } else {
            LaunchAgent.disable()
        }
        agentOn = LaunchAgent.enabled
    }

    /// How new fixes arrive: installed by themselves, offered first, or not looked for.
    enum UpdateMode: String, CaseIterable, Identifiable {
        case automatic, ask, off
        var id: String { rawValue }
        var label: String {
            switch self {
            case .automatic: return "Automatic"
            case .ask: return "Ask first"
            case .off: return "Off"
            }
        }
    }

    var updateMode: UpdateMode {
        !settings.updates ? .off : settings.askFirst ? .ask : .automatic
    }

    func setUpdateMode(_ mode: UpdateMode) {
        settings.updates = mode != .off
        settings.askFirst = mode == .ask
        settings.save()
        objectWillChange.send()
    }

    /// The same, on their own, for the Wine modules.
    var modulesMode: UpdateMode {
        !settings.modulesUpdates ? .off : settings.modulesAskFirst ? .ask : .automatic
    }

    func setModulesMode(_ mode: UpdateMode) {
        settings.modulesUpdates = mode != .off
        settings.modulesAskFirst = mode == .ask
        settings.save()
        objectWillChange.send()
    }


    /// Installs the newer Wine modules' catalog now.
    func checkForModules() {
        guard !busy else { return }
        busy = true
        status = "Looking for new Wine modules…"
        Task {
            var line: String
            do {
                line = try await Updater.update(.modules)
                var state = AgentState.load()
                state.availableModules = 0
                state.lastModulesUpdate = line
                state.save()
            } catch { line = "Could not update: \(error.localizedDescription)" }
            loadCatalog()
            refreshEvents()
            busy = false
            status = line
            scanEngine()
        }
    }

    func checkForFixes() {
        guard !busy else { return }
        busy = true
        status = "Looking for new fixes…"
        Task {
            do {
                updateLine = try await Updater.update()
                // What the user installed by hand is no longer waiting for them.
                var state = AgentState.load()
                state.available = 0
                state.lastUpdate = updateLine
                state.save()
            } catch { updateLine = "Could not update: \(error.localizedDescription)" }
            loadCatalog()
            refreshEvents()
            busy = false
            status = updateLine
            scan()
        }
    }

    var extraFolders: [URL] {
        get { (UserDefaults.standard.stringArray(forKey: extraKey) ?? []).map { URL(fileURLWithPath: $0) } }
        set { UserDefaults.standard.set(newValue.map(\.path), forKey: extraKey) }
    }

    var selected: [Hit] { hits.filter { $0.selected && $0.blocker == nil } }

    func note(_ s: String) { log.append(s) }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose a Steam library, its steamapps/common folder, or a game folder."
        guard panel.runModal() == .OK else { return }
        var list = extraFolders
        for u in panel.urls where !list.contains(u) { list.append(u) }
        extraFolders = list
        scan()
    }

    func removeExtra(_ url: URL) {
        extraFolders = extraFolders.filter { $0 != url }
        scan()
    }

    func scan() {
        guard !busy else { return }
        busy = true
        status = "Looking for games…"
        let extra = extraFolders
        let games = self.games
        Task {
            let (libs, found) = await Task.detached { Libraries.find(games, extra: extra) }.value
            libraries = libs
            hits = found
            // A game kept applied keeps the prefixes it was marked with, of those still there.
            for i in hits.indices where hits[i].game.needsPrefix {
                if let kept = settings.kept.first(where: { $0.key == hits[i].key }) {
                    let chosen = hits[i].prefixes.filter { kept.prefixes.contains($0.path.path) }
                    if !chosen.isEmpty { hits[i].chosen = chosen }
                }
            }
            for i in hits.indices { hits[i] = await probe(hits[i]) }
            busy = false
            status = found.isEmpty ? "No supported game found in these folders." : "\(found.count) game(s) found."
            // The CrossOver installs too, which a tab opened during this look could not ask for.
            if engineRows.isEmpty { scanEngine() }
        }
    }

    /// Asks the installer what it sees. Only the state word is kept: --status
    /// also prints paths, and the installer's own judgement is the only one.
    func probe(_ hit: Hit) async -> Hit {
        var hit = hit
        if hit.game.needsPrefix && hit.chosen.isEmpty {
            hit.state = .unknown
            return hit
        }
        hit.state = await Fixer.status(hit.game, folder: hit.folder, prefixes: hit.chosen.map(\.path.path),
                                       catalog: resources)
        if hit.state == .noCarrier { hit.selected = false }
        return hit
    }

    func apply(install: Bool) {
        guard !busy else { return }
        let targets = selected.filter { install ? $0.state != .installed : $0.state != .absent }
        guard !targets.isEmpty else {
            status = install ? "Nothing selected needs installing." : "Nothing selected is installed."
            return
        }
        busy = true
        Task {
            var done = 0, failed = 0
            for hit in targets {
                done += 1
                status = "\(install ? "Installing" : "Removing") \(hit.game.name) (\(done) of \(targets.count))…"
                note(""); note("▸ \(hit.game.name) — \(hit.folder.path)")
                if hit.game.needsPrefix { for p in hit.chosen { note("  into the \(p.label)") } }
                let code = await Fixer.run(hit.game, folder: hit.folder, prefixes: hit.chosen.map(\.path.path),
                                           catalog: resources, install ? [] : ["--restore"]) { line in
                    Task { @MainActor in self.note("  " + line) }
                }
                await Task.yield()
                if let i = hits.firstIndex(where: { $0.id == hit.id }) {
                    var h = await probe(hits[i])
                    // The re-probe is the authority, not the exit code.
                    let took = install ? h.state == .installed : h.state == .absent
                    if code != 0 { failed += 1; h.outcome = "Failed — see the log" }
                    else if !took { failed += 1; h.outcome = "Did not take — see the log" }
                    // A success is already in the state beside it, and in the status line.
                    else { h.outcome = nil }
                    h.selected = false
                    hits[i] = h
                }
            }
            busy = false
            status = failed == 0 ? "Done: \(done) game(s)." : "Done, \(failed) of \(done) need attention."
        }
    }
}

// MARK: - Wine modules

/// One CrossOver the Wine modules can go into, with what its installer says.
struct EngineRow: Identifiable {
    let target: EngineTarget
    var state: EngineState = .unknown
    /// What the last install or removal left, when it needs the user.
    var outcome: String?

    var id: String { target.id }
}

extension Model {
    /// Whether the agent keeps the modules in this CrossOver: the Settings box.
    func engineKept(_ row: EngineRow) -> Bool {
        settings.modulesKept.contains { Engine.resolved($0) == row.target.key }
    }

    /// Ticking a box keeps the modules there; unticking leaves that CrossOver
    /// alone from then on, and removes nothing (Remove, in Wine Modules, does).
    func setEngineKept(_ row: EngineRow, _ on: Bool) {
        let key = row.target.key
        settings.modulesKept.removeAll { Engine.resolved($0) == key }
        settings.modulesDeclined.removeAll { Engine.resolved($0) == key }
        if on { settings.modulesKept.append(key) } else { settings.modulesDeclined.append(key) }
        settings.save()
        objectWillChange.send()
    }

    /// Only a CrossOver there are modules for, of its exact build and Wine, can be turned on.
    func engineSelectable(_ row: EngineRow) -> Bool { row.state != .noModules && row.state != .unknown }

    /// The switch in Wine Modules is the action: on installs into that CrossOver
    /// and keeps the modules there, off puts CrossOver's own files back and leaves
    /// it alone. A CrossOver app is asked about first, since it changes the app.
    func setEngineOn(_ row: EngineRow, _ on: Bool) {
        if on, row.target.app != nil, !confirmApp([row]) { objectWillChange.send(); return }
        setEngineKept(row, on)
        engineBatch([row], install: on)
    }

    /// All, or None: every CrossOver there are modules for, after one question.
    func setAllEngine(_ on: Bool) {
        let rows = engineRows.filter { engineSelectable($0) && engineKept($0) != on }
        guard !rows.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = on ? "Install the Wine modules into \(rows.count) CrossOver install(s)?"
            : "Remove the Wine modules from \(rows.count) CrossOver install(s)?"
        alert.informativeText = rows.map(\.target.name).joined(separator: "\n")
        alert.addButton(withTitle: on ? "Install" : "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if on, rows.contains(where: { $0.target.app != nil }), !confirmApp(rows.filter { $0.target.app != nil }) { return }
        for row in rows { setEngineKept(row, on) }
        engineBatch(rows, install: on)
    }

    private func confirmApp(_ rows: [EngineRow]) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Change CrossOver itself?"
        alert.informativeText = "MacGameFix puts three Wine files into " + rows.map(\.target.name).joined(separator: ", ")
            + ". macOS asks you to allow MacGameFix under App Management, and the app is signed again ad hoc, "
            + "so CodeWeavers' signature no longer covers it. Turning it off puts CrossOver's own files back."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Installs into, or removes from, each of these CrossOver installs in turn.
    func engineBatch(_ rows: [EngineRow], install: Bool) {
        guard !busy, !rows.isEmpty else { return }
        busy = true
        Task {
            var failed = 0
            for (n, row) in rows.enumerated() {
                status = "\(install ? "Installing the modules into" : "Removing the modules from") \(row.target.name)"
                    + (rows.count > 1 ? " (\(n + 1) of \(rows.count))…" : "…")
                note(""); note("▸ Wine modules — \(row.target.name) — \(row.target.root.path)")
                let code = await Engine.run(row.target, catalog: modulesDir, install ? [] : ["--restore"]) { line in
                    Task { @MainActor in self.note("  " + line) }
                }
                await Task.yield()
                // As with the games, the state asked afterwards is the authority.
                let state = await Engine.status(row.target, catalog: modulesDir)
                let took = install ? state == .installed : state == .absent
                if let i = engineRows.firstIndex(where: { $0.id == row.id }) {
                    engineRows[i].state = state
                    engineRows[i].outcome = code == 0 && took ? nil : "Failed — see the log in Settings"
                }
                if code != 0 || !took { failed += 1 }
            }
            busy = false
            status = failed == 0 ? "Done." : "\(failed) of \(rows.count) need attention — see the log in Settings."
        }
    }

    // MARK: The controllers

    /// The Game Feel tab is there while a CrossOver has the Wine modules that
    /// read its options in: those that carry winebus.so.
    var padAvailable: Bool {
        engineRows.contains { row in
            row.state == .installed && (engineBuilds.first { $0.build == row.target.build }?.files.keys
                .contains { $0.hasSuffix("unix/winebus.so") } ?? false)
        }
    }

    /// The Steam games on this Mac, and what the modules logged since the last look.
    func scanPad() {
        let extra = extraFolders
        Task {
            let games = await Task.detached { SteamGames.installed(extra: extra) }.value
            padGames = games
            var store = PadStore.exists ? PadStore.load() : pad
            if store.absorbLog(names: { Dictionary(games.map { ($0.appid, $0.name) }, uniquingKeysWith: { a, _ in a }) }) {
                store.save()
            }
            pad = store
        }
    }

    /// A change to the options: kept, and written for the modules at once. It
    /// starts from pad.json as it is, since the agent adds what it reads of the log.
    func setPad(_ change: (inout PadStore) -> Void) {
        var store = PadStore.exists ? PadStore.load() : pad
        change(&store)
        store.save()
        store.writeConfig(presets: padPresets)
        pad = store
    }

    /// A game's own options; a game left with none and nothing seen is forgotten.
    func setPadGame(_ game: InstalledGame, _ change: (inout PadOptions) -> Void) {
        setPad { store in
            var entry = store.games[game.appid] ?? PadGame(name: game.name)
            entry.name = game.name
            change(&entry.options)
            store.games[game.appid] = entry.options.isEmpty && entry.seen.isEmpty ? nil : entry
        }
    }

    func exportPad() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacGameFix controllers.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pad.export(presets: padPresets).write(to: url, options: .atomic)
            status = "Exported the controller settings of \(pad.games.count) game(s)."
        } catch {
            status = "Could not export: \(error.localizedDescription)"
        }
    }

    /// On, and behind: newer modules came, or something put CrossOver's own files back.
    func engineBehind(_ row: EngineRow) -> Bool {
        engineKept(row) && [.outdated, .absent, .half].contains(row.state)
    }

    /// Finds the CrossOver apps and runners and asks the installer about each.
    func scanEngine() {
        guard !busy else { return }
        busy = true
        status = "Looking at CrossOver and the NotProton runners…"
        Task {
            let found = await Task.detached { Engine.targets() }.value
            var rows = found.map { EngineRow(target: $0) }
            for i in rows.indices { rows[i].state = await Engine.status(rows[i].target, catalog: modulesDir) }
            engineRows = rows
            busy = false
            status = found.isEmpty ? "No CrossOver or NotProton runner found." : "\(found.count) CrossOver install(s) found."
            // The first time the modules that read them are in, the options start
            // as they were measured; after that they are written once a launch, so
            // the files carry this version's keys and suggested settings.
            if padAvailable && !padWritten {
                padWritten = true
                let fresh = !PadStore.exists
                setPad { if fresh { $0 = PadStore() } }
            }
        }
    }

}

// MARK: - Interface

struct HitRow: View {
    @Binding var hit: Hit
    let busy: Bool
    let kept: Bool
    let onKeep: (Bool) -> Void
    @ObservedObject var model: Model

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $hit.selected)
                .labelsHidden()
                .disabled(hit.blocker != nil || busy)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(hit.game.name).font(.headline)
                    Spacer()
                    if let o = hit.outcome {
                        Text(o).font(.caption).foregroundStyle(.orange)
                    }
                    Text(hit.state.label).font(.callout).foregroundStyle(hit.state.color)
                }
                Text(hit.folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(hit.game.symptom).font(.caption)
                if let r = hit.game.requirementNote {
                    Text(r).font(.caption).foregroundStyle(.secondary)
                }
                if hit.game.needsPrefix {
                    if hit.prefixes.count > 1 {
                        Text("Registry keys go into:").font(.caption).foregroundStyle(.secondary)
                        ForEach(hit.prefixes) { p in
                            Toggle(p.label, isOn: Binding(
                                get: { hit.chosen.contains(p) },
                                set: { on in model.choosePrefix(hit, p, on) }))
                                .toggleStyle(.checkbox)
                                .font(.caption)
                                .disabled(busy)
                        }
                    } else if let p = hit.chosen.first {
                        Text("Registry keys go into the \(p.label)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let b = hit.blocker {
                    Text(b).font(.caption).foregroundStyle(.red)
                }
                if let line = model.keptLine(hit), line.word == "Failed" {
                    HStack(alignment: .firstTextBaseline) {
                        Text("In the background: \(line.detail ?? "the fix did not take.")")
                            .font(.caption).foregroundStyle(.orange)
                        if let r = line.report, let url = URL(string: r) {
                            Button("Report on GitHub…") { NSWorkspace.shared.open(url) }.font(.caption).buttonStyle(.link)
                        }
                    }
                }
                Toggle("Keep it applied: put it back after a game update", isOn: Binding(get: { kept }, set: onKeep))
                    .font(.caption)
                    .disabled(hit.blocker != nil || busy)
            }
        }
        .padding(.vertical, 4)
        .help(hit.game.why)
    }
}

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabView {
                GamesView(model: model).padding(.top, 6)
                    .tabItem { Text("Games") }
                EngineView(model: model).padding(.top, 6)
                    .tabItem { Text("Wine Modules") }
                if model.padAvailable {
                    ControllersView(model: model).padding(.top, 6)
                        .tabItem { Text("Game Feel") }
                }
                SettingsView(model: model).padding(.top, 6)
                    .tabItem { Text("Settings") }
            }
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 460)
        .onAppear { model.scan() }
    }
}

/// The games and their fixes, which go into each game's own folder.
struct GamesView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacGameFix").font(.title2.bold())
                Text("Fixes go into each game's own folder and never change CrossOver. Quit a game before changing its fix.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("They work with CrossOver as it ships, CrossOver Preview, and Steam Play tools such as NotProton.")
            }

            HStack {
                Button("Scan") { model.scan() }.disabled(model.busy)
                Button("Add Folder…") { model.addFolder() }.disabled(model.busy)
                Spacer()
                Button("Select All") {
                    for i in model.hits.indices where model.hits[i].blocker == nil { model.hits[i].selected = true }
                }.disabled(model.busy || model.hits.isEmpty)
                Button("Install Selected") { model.apply(install: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy || model.selected.isEmpty)
                Button("Remove Selected") { model.apply(install: false) }
                    .disabled(model.busy || model.selected.isEmpty)
            }

            if model.hits.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(model.busy ? "Looking…" : "No supported game found yet.").foregroundStyle(.secondary)
                    Text("Supported: " + model.games.map(\.name).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                if !model.toReview.isEmpty {
                    Toggle("Only the marked games to review (\(model.toReview.count))", isOn: $model.onlyReview)
                        .font(.callout)
                }
                List {
                    ForEach($model.hits) { $hit in
                        if !model.onlyReview || model.keptLine(hit)?.needsUser == true {
                            HitRow(hit: $hit, busy: model.busy, kept: model.isKept(hit),
                                   onKeep: { model.setKept(hit, $0) }, model: model)
                        }
                    }
                }
                .frame(minHeight: 260)
            }
        }
    }
}

/// The Wine modules: the part of MacGameFix that does change CrossOver. Each
/// CrossOver has a switch, and the switch is the action; the tab also has the
/// modules' own updates.
struct EngineView: View {
    @ObservedObject var model: Model

    var body: some View {
        Form {
            Section {
                ForEach(model.engineRows) { row in EngineSwitch(row: row, model: model) }
                if model.engineRows.isEmpty {
                    Text(model.busy ? "Looking…" : "No CrossOver or NotProton runner found.").foregroundStyle(.secondary)
                }
                Toggle("New CrossOver builds too", isOn: Binding(
                    get: { model.settings.modulesNewBuilds },
                    set: { model.settings.modulesNewBuilds = $0; model.settings.save(); model.objectWillChange.send() }))
                    .help("With updates on Automatic: when NotProton adds a runner for a new CrossOver build and "
                          + "there are modules for it, they go there too, once a runner that is on has them.")
                HStack {
                    Button("All") { model.setAllEngine(true) }
                    Button("None") { model.setAllEngine(false) }
                    Spacer()
                    let behind = model.engineRows.filter { model.engineBehind($0) }
                    if !behind.isEmpty {
                        Button("Update All") { model.engineBatch(behind, install: true) }
                            .help("Brings the modules up to date in every CrossOver that is on and behind.")
                    }
                    Button("Look Again") { model.scanEngine() }
                }
                .disabled(model.busy)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DualSense haptics on a USB cable")
                    Text("On installs three Wine files into that CrossOver; off puts CrossOver's own back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .help("Unlike the game fixes, these go into CrossOver itself. Quit that CrossOver's games first. "
                      + "In a CrossOver app, macOS asks to allow MacGameFix under App Management, and the app is "
                      + "signed again ad hoc.")
            } footer: {
                Text("Only a CrossOver of a build and Wine the modules were built for can be turned on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Updates") {
                Picker("New Wine modules", selection: Binding(get: { model.modulesMode }, set: { model.setModulesMode($0) })) {
                    ForEach(Model.UpdateMode.allCases) { Text($0.label).tag($0) }
                }
                .help("New Wine modules from GitHub, on their own, once a day. On Automatic they also go back "
                      + "into the runners that are on after a CrossOver or NotProton update. “Ask first” checks "
                      + "the signature and tells you. A CrossOver app is only ever reported.")
                if let waiting = model.waitingModules {
                    LabeledContent(String(localized: "New Wine modules ready (\(String(waiting)))")) {
                        Button("Install") { model.checkForModules() }.disabled(model.busy)
                    }
                    .foregroundStyle(.orange)
                }
                LabeledContent("Catalog") {
                    HStack {
                        Text(verbatim: String(model.modulesVersion)).foregroundStyle(.secondary)
                            .help("Modules for: " + model.engineBuilds.map(\.crossover).joined(separator: ", "))
                        Button("Check Now") { model.checkForModules() }.disabled(model.busy)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if model.engineRows.isEmpty { model.scanEngine() } }
    }
}

/// Game Feel: the DualSense options, for every game and for each one. Only while a CrossOver
/// has the Wine modules that read them. Every game's are on top; below, the
/// games in pages, each opening the same form for its own.
struct ControllersView: View {
    @ObservedObject var model: Model
    @State private var search = ""
    @State private var page = 0
    @State private var selection: InstalledGame.ID?
    @State private var editing: InstalledGame?
    private let perPage = 15

    private var filtered: [InstalledGame] {
        guard !search.isEmpty else { return model.padGames }
        return model.padGames.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.appid == search }
    }
    private var pages: Int { max(1, (filtered.count + perPage - 1) / perPage) }
    private var shown: [InstalledGame] { Array(filtered.dropFirst(min(page, pages - 1) * perPage).prefix(perPage)) }

    var body: some View {
        VSplitView {
            Form {
                Section {
                    PadOptionRows(
                        flag: { key in Binding(get: { model.pad.defaults[keyPath: key] ?? false },
                                               set: { on in model.setPad { $0.defaults[keyPath: key] = on } }) },
                        own: { _ in false })
                    Toggle("Diagnostics in the modules' log", isOn: Binding(
                        get: { model.pad.diagnostics }, set: { on in model.setPad { $0.diagnostics = on } }))
                        .help("What a game writes to the pad and reads from it, and a level meter of its haptics, in "
                              + "/tmp/macgamefix-\(getuid())/pad.log.")
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Every game")
                        Text("The Wine modules read these when a game starts. A game's own settings win.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                PadHapticsSection(
                    gain: { key in Binding(get: { model.pad.defaults[keyPath: key] ?? 1 },
                                           set: { v in model.setPad { $0.defaults[keyPath: key] = v } }) },
                    own: { _ in false }
                ) {
                    Text("Measured with NOTPROTON_RAW_CONTROLLERS=1 in the game's launch options and Steam Input off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 200, idealHeight: 560)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Per game").font(.headline)
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    Spacer()
                    Button("Look Again") { model.scanPad() }
                    Button("Export…") { model.exportPad() }
                        .help("The settings and what was seen of each game, to share. No paths or accounts.")
                }
                Table(shown, selection: $selection) {
                    TableColumn("Game") { game in
                        Text(game.name).foregroundStyle(ownOptions(game).isEmpty ? Color.primary : Color.accentColor)
                    }
                    TableColumn("Settings") { game in Text(settings(game)).foregroundStyle(.secondary) }
                    TableColumn("Seen") { game in Text(seen(game)).foregroundStyle(.secondary) }
                }
                .onChange(of: selection) { _, id in
                    if let id, let game = model.padGames.first(where: { $0.id == id }) { editing = game }
                }
                HStack {
                    Text(model.padGames.isEmpty ? "No Steam game found."
                         : filtered.isEmpty ? "No game matches." : "\(filtered.count) game(s)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(page == 0)
                    Text("Page \(min(page, pages - 1) + 1) of \(pages)").font(.caption).monospacedDigit()
                    Button { page = min(pages - 1, page + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(page >= pages - 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(minHeight: 260)
        }
        .sheet(item: $editing, onDismiss: { selection = nil }) { game in PadGameSheet(game: game, model: model) }
        .onChange(of: search) { _, _ in page = 0 }
        .onAppear { model.scanPad() }
    }

    private func ownOptions(_ game: InstalledGame) -> PadOptions { model.pad.games[game.appid]?.options ?? PadOptions() }

    private func settings(_ game: InstalledGame) -> String {
        let changes = model.pad.effective(game.appid, presets: model.padPresets).differences(from: model.pad.defaults)
        guard !changes.isEmpty else { return "As every game" }
        return changes.summary.joined(separator: ", ") + (ownOptions(game).isEmpty ? " (suggested)" : "")
    }

    private func seen(_ game: InstalledGame) -> String {
        (model.pad.games[game.appid]?.seen.keys.sorted() ?? []).map(\.label).joined(separator: ", ")
    }
}

/// The gains offered: the soft limit keeps the strongest hits under the pad's top.
private let padGains: [Double] = [1, 1.5, 2, 2.5, 3]

/// The options' rows, for every game and for one: the same form either way. A
/// row whose value is the game's own is in the accent colour.
struct PadOptionRows: View {
    let flag: (WritableKeyPath<PadOptions, Bool?>) -> Binding<Bool>
    let own: (PartialKeyPath<PadOptions>) -> Bool

    private func title(_ text: String, _ key: PartialKeyPath<PadOptions>) -> Text {
        own(key) ? Text(text).foregroundColor(.accentColor) : Text(text)
    }

    var body: some View {
        Toggle(isOn: flag(\.bluetoothAsCable)) { title("Bluetooth as a cable", \.bluetoothAsCable) }
            .help("A DualSense or DualSense Edge on Bluetooth is shown to games as the same pad on a cable: "
                  + "haptics and adaptive triggers as wired.")
        Toggle(isOn: flag(\.fullMotorPower)) { title("Full motor power on the Edge", \.fullMotorPower) }
            .help("Sony's library claims a standard DualSense's motor power at full in every report and never "
                  + "an Edge's, which then stays at the reduction it stores.")
        Toggle(isOn: flag(\.edgeAsDualSense)) { title("Show the Edge as a standard DualSense", \.edgeAsDualSense) }
            .help("For a title whose Sony library does not know the Edge. The game loses the Edge's back buttons "
                  + "and Fn.")
    }
}

/// The haptics' strength, per connection and per pad, as a table: a pad does not
/// feel the same stream alike on a cable and over Bluetooth, and some games need
/// more on one. A dot marks what is the game's own.
struct PadHapticsSection<Footer: View>: View {
    let gain: (WritableKeyPath<PadOptions, Double?>) -> Binding<Double>
    let own: (PartialKeyPath<PadOptions>) -> Bool
    @ViewBuilder let footer: () -> Footer

    private func cell(_ key: WritableKeyPath<PadOptions, Double?>, _ help: String) -> some View {
        HStack(spacing: 6) {
            Picker("", selection: gain(key)) {
                ForEach(padGains, id: \.self) { Text(PadOptions.times($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.accentColor)
                .opacity(own(key) ? 1 : 0)
        }
        .help(help)
    }

    var body: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("DualSense").foregroundStyle(.secondary)
                    Text("DualSense Edge").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Cable")
                    cell(\.hapticsGainCable, "A standard DualSense on a cable.")
                    cell(\.edgeHapticsGainCable, "2× in Spider-Man 2, as over Bluetooth.")
                }
                GridRow {
                    Text("Bluetooth")
                    cell(\.hapticsGainBluetooth,
                         "Spider-Man 2 felt the same at 1× as on a cable; F1 23 needed 2× to feel as steady.")
                    cell(\.edgeHapticsGainBluetooth,
                         "2× made an Edge over Bluetooth feel like a standard DualSense in Spider-Man 2.")
                }
            }
        } header: {
            Text("Haptics strength")
        } footer: {
            footer()
        }
    }
}

/// One game's own options, in the same form as every game's. A value set back
/// to what the game would get anyway is no longer its own.
struct PadGameSheet: View {
    let game: InstalledGame
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss

    private var preset: PadPreset? { model.padPresets[game.appid] }
    private var own: PadOptions { model.pad.games[game.appid]?.options ?? PadOptions() }
    /// What the game gets without options of its own.
    private var base: PadOptions { (preset?.options ?? PadOptions()).over(model.pad.defaults) }
    private var effective: PadOptions { own.over(base) }

    private func flag(_ key: WritableKeyPath<PadOptions, Bool?>) -> Binding<Bool> {
        Binding(get: { effective[keyPath: key] ?? false },
                set: { v in model.setPadGame(game) { $0[keyPath: key] = v == (base[keyPath: key] ?? false) ? nil : v } })
    }

    private func gain(_ key: WritableKeyPath<PadOptions, Double?>) -> Binding<Double> {
        Binding(get: { effective[keyPath: key] ?? 1 },
                set: { v in model.setPadGame(game) { $0[keyPath: key] = v == (base[keyPath: key] ?? 1) ? nil : v } })
    }

    private func isOwn(_ key: PartialKeyPath<PadOptions>) -> Bool {
        switch own[keyPath: key] {
        case let v as Bool?: return v != nil
        case let v as Double?: return v != nil
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    PadOptionRows(flag: flag, own: isOwn)
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.name)
                        Text("In blue, or marked with a dot, what is this game's own; the rest follows "
                             + (preset == nil ? "every game's." : "the suggested settings, then every game's."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                PadHapticsSection(gain: gain, own: isOwn) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let preset {
                            Text("Suggested: \(preset.options.summary.joined(separator: ", ")). \(preset.measured)")
                        }
                        let seen = (model.pad.games[game.appid]?.seen.keys.sorted() ?? []).map(\.label)
                        if !seen.isEmpty { Text("Seen: " + seen.joined(separator: ", ") + ".") }
                        Text("Steam app \(game.appid)")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !own.isEmpty {
                    Button(preset == nil ? "Use Every Game's" : "Use the Suggested") {
                        model.setPadGame(game) { $0 = PadOptions() }
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 540, height: 470)
    }
}

/// One CrossOver: its name, its build and what is in it, the button that brings
/// its modules up to date when they are behind, and the switch.
struct EngineSwitch: View {
    let row: EngineRow
    @ObservedObject var model: Model

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.target.name).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(model.engineSelectable(row) ? "\(row.target.build) · \(row.state.label)"
                         : "\(row.target.build) · no modules for this build")
                        .foregroundStyle(model.engineSelectable(row) ? row.state.color : .secondary)
                    if let o = row.outcome { Text(o).foregroundStyle(.orange) }
                }
                .font(.caption)
            }
            Spacer()
            // On, and something put CrossOver's own files back or newer modules came.
            if model.engineBehind(row) {
                Button(row.state == .outdated ? "Update" : "Install Again") { model.engineBatch([row], install: true) }
                    .disabled(model.busy)
            }
            Toggle("", isOn: Binding(get: { model.engineKept(row) }, set: { model.setEngineOn(row, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!model.engineSelectable(row) || model.busy)
        }
        .help(row.target.root.path)
    }
}

/// What runs in the background, the updates, where games are looked for, and the log.
/// Short labels; what each does is in its tooltip, so the tab fits a small screen.
struct SettingsView: View {
    @ObservedObject var model: Model

    var body: some View {
        Form {
            Section("Background") {
                Toggle("Run from the menu bar", isOn: Binding(get: { model.agentOn }, set: { model.setAgent($0) }))
                    .help("MacGameFix starts when you log in and stays in the menu bar. Every two minutes it puts "
                          + "back the fix of a game marked “Keep it applied” after Steam updates or verifies it, "
                          + "once the game is closed.")
                Toggle("Show the controller's battery", isOn: Binding(get: { model.settings.padBattery },
                                                                      set: { model.setPadBattery($0) }))
                    .disabled(!model.agentOn)
                    .help("Beside the raccoon in the menu bar: a gamepad and the battery left in a connected "
                          + "controller, the lowest if there are several. The menu lists each one.")
                Picker("Icon", selection: Binding(get: { model.settings.batteryIcon }, set: { model.setBatteryIcon($0) })) {
                    Text("Raccoon and gamepad").tag("raccoon")
                    Text("Gamepad").tag("gamepad")
                    Text("Battery only").tag("none")
                }
                .disabled(!model.agentOn || !model.settings.padBattery)
                .help("What stands beside the battery in the menu bar. With no controller connected, the gamepad "
                      + "stays if it is chosen; otherwise the raccoon shows.")
                ForEach(model.keptLines.filter { $0.word == "Folder not found" }, id: \.key) { line in
                    LabeledContent {
                        Button("Stop Keeping It") { model.forget(line) }
                    } label: {
                        Text("\(line.name): folder gone").foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Picker("Game fixes", selection: Binding(get: { model.updateMode }, set: { model.setUpdateMode($0) })) {
                    ForEach(Model.UpdateMode.allCases) { Text($0.label).tag($0) }
                }
                .help("New fixes from GitHub, looked for once a day. “Ask first” checks the signature and tells "
                      + "you; nothing is installed until you say so.")
                if let waiting = model.waitingCatalog {
                    LabeledContent(String(localized: "New fixes ready (\(String(waiting)))")) {
                        Button("Install") { model.checkForFixes() }.disabled(model.busy)
                    }
                    .foregroundStyle(.orange)
                }
                LabeledContent("Catalog") {
                    HStack {
                        Text(verbatim: String(model.catalogVersion)).foregroundStyle(.secondary)
                        Button("Check Now") { model.checkForFixes() }.disabled(model.busy)
                    }
                }
            } header: {
                Text("Game fix updates")
            } footer: {
                Text("The Wine modules have their own, in Wine Modules.").font(.caption).foregroundStyle(.secondary)
            }

            if !model.events.isEmpty {
                Section("Recent") {
                    ForEach(model.events.prefix(5)) { e in
                        HStack(alignment: .firstTextBaseline) {
                            Text(e.game.isEmpty ? e.message : "\(e.game): \(e.message)")
                                .foregroundStyle(e.failed ? .orange : .primary)
                                .lineLimit(2)
                            Spacer()
                            Text(e.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                            if let r = e.report, let url = URL(string: r) {
                                Button("Report…") { NSWorkspace.shared.open(url) }
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section {
                DisclosureGroup("Folders searched (\(model.libraries.count))") {
                    ForEach(model.libraries, id: \.self) { lib in
                        HStack {
                            Text(lib.path).font(.caption).lineLimit(1).truncationMode(.middle).help(lib.path)
                            Spacer()
                            if model.extraFolders.contains(lib) {
                                Button("Remove") { model.removeExtra(lib) }.font(.caption).disabled(model.busy)
                            }
                        }
                    }
                }
                Button("Add Folder…") { model.addFolder() }.disabled(model.busy)
            } header: {
                Text("Games")
            }

            Section {
                DisclosureGroup("Log") {
                    ScrollView {
                        Text(model.log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 160)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if model.engineRows.isEmpty { model.scanEngine() } }
    }
}

/// The window's process ends with its window: the agent, when it is on, is a
/// process of its own in the menu bar, and a window process left without a
/// window only sat in the Dock. One that is installing or removing a fix
/// finishes that first.
@MainActor
final class WindowApp: NSObject, NSApplicationDelegate {
    static var busy = false {
        didSet {
            if !busy && quitWaiting {
                quitWaiting = false
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
    }
    private static var quitWaiting = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.busy else { return .terminateNow }
        Self.quitWaiting = true
        return .terminateLater
    }
}

struct MacGameFixApp: App {
    @NSApplicationDelegateAdaptor(WindowApp.self) private var delegate

    var body: some Scene {
        WindowGroup("MacGameFix") { ContentView() }
            .windowResizability(.contentMinSize)
    }
}

/// One binary, several ways to run: the window; --agent, which the LaunchAgent
/// starts and which lives in the menu bar; and, for the tests and the release,
/// --agent-once, --menu-report, --games-report, --engine-report,
/// --engine-install, --engine-remove, --update-from, --make-catalog and
/// --new-signing-key, which do one thing and exit.
@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        func wait(_ work: @escaping @Sendable () async -> Int32) -> Never {
            let done = DispatchSemaphore(value: 0)
            let box = ExitBox()
            Task.detached { box.code = await work(); done.signal() }
            done.wait()
            exit(box.code)
        }
        if args.contains("--agent") { MainActor.assumeIsolated { Agent.runForever() } }
        if args.contains("--menu-report") {
            // The menu bar item's summary, the games behind it, and its dot.
            let settings = AutoSettings.load(), state = AgentState.load()
            let lines = KeptLine.all(settings: settings, state: state)
            print("news | \(state.news(since: settings.seen) ? "yes" : "no")")
            for group in KeptLine.summary(lines) { print("summary | \(group.text)") }
            for line in lines {
                print("\(line.name) | \(line.word)\(line.detail.map { " | " + $0 } ?? "")\(line.report == nil ? "" : " | report")")
            }
            exit(0)
        }
        if args.contains("--agent-once") {
            wait {
                for e in await Agent.pass(notify: false) {
                    print("\(e.failed ? "FAILED" : "ok") \(e.game): \(e.message)")
                    if let r = e.report { print("report \(r)") }
                }
                return 0
            }
        }
        if args.contains("--pad-write") {
            // What the Game Feel tab does on a change: the log read, pad.json kept,
            // pad.conf and pad.d/ written.
            var store = PadStore.load()
            store.absorbLog(names: { Dictionary(SteamGames.installed().map { ($0.appid, $0.name) },
                                                uniquingKeysWith: { a, _ in a }) })
            store.save()
            store.writeConfig(presets: PadPresets.load())
            print("pad.conf and \((try? FileManager.default.contentsOfDirectory(atPath: PadStore.perGame.path).count) ?? 0) per-game file(s) written")
            exit(0)
        }
        if let i = args.firstIndex(of: "--pad-export"), i + 1 < args.count {
            // The Export button's file, without the panel.
            try? PadStore.load().export(presets: PadPresets.load()).write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        if args.contains("--pad-report") {
            // Each game the options or the log know: what it gets and what was seen.
            let store = PadStore.load(), presets = PadPresets.load()
            print("every game | " + store.defaults.lines.joined(separator: " "))
            for appid in Set(store.games.keys).union(presets.keys).sorted() {
                let seen = (store.games[appid]?.seen.keys.sorted() ?? []).map(\.rawValue).joined(separator: ",")
                print("\(appid) | \(store.games[appid]?.name ?? presets[appid]?.title ?? "") | "
                      + store.effective(appid, presets: presets).lines.joined(separator: " ") + " | seen \(seen)")
            }
            exit(0)
        }
        if args.contains("--games-report") {
            // Every supported game found, what its fix requires, and for a fix
            // that writes registry keys, where they go.
            let (dir, _) = Catalog.active()
            for hit in Libraries.find(Catalog.games(in: dir), extra: []).hits {
                var parts = [hit.game.name, hit.game.requirementNote ?? "no special requirement"]
                if hit.game.needsPrefix {
                    parts.append(hit.chosen.isEmpty ? "no prefix"
                                 : "keys into the " + hit.chosen.map(\.label).joined(separator: " and the "))
                }
                print(parts.joined(separator: " | "))
            }
            exit(0)
        }
        if args.contains("--engine-report") {
            // Every CrossOver app and NotProton runner, and what the Wine modules' installer says of it.
            let (dir, _) = Catalog.active(.modules)
            wait {
                for t in Engine.targets() {
                    print("\(t.name) | \(t.build)\(t.fex ? " | fex" : "") | \(await Engine.status(t, catalog: dir))")
                }
                return 0
            }
        }
        if let root = value("--engine-install") ?? value("--engine-remove") {
            // One CrossOver, by the folder that holds lib/wine, for the tests.
            let (dir, _) = Catalog.active(.modules)
            let path = Engine.resolved(root)
            guard let target = Engine.targets().first(where: { $0.key == path })
            else { print("not a CrossOver this app knows: \(root)"); exit(1) }
            let remove = args.contains("--engine-remove")
            wait {
                let code = await Engine.run(target, catalog: dir, remove ? ["--restore"] : []) { print($0) }
                // As from the window: what is put in is kept, what is taken out is left alone.
                if code == 0 {
                    var settings = AutoSettings.load()
                    settings.modulesKept.removeAll { Engine.resolved($0) == target.key }
                    settings.modulesDeclined.removeAll { Engine.resolved($0) == target.key }
                    if remove { settings.modulesDeclined.append(target.key) } else { settings.modulesKept.append(target.key) }
                    settings.save()
                }
                return code
            }
        }
        if let source = value("--update-from") {
            let key = value("--pubkey") ?? Updater.publicKey
            let kind: CatalogKind = value("--kind") == "modules" ? .modules : .fixes
            wait {
                do {
                    print(try await Updater.update(kind, from: URL(fileURLWithPath: source), publicKey: key))
                    return 0
                } catch {
                    print("refused: \(error.localizedDescription)")
                    return 1
                }
            }
        }
        if let path = value("--new-signing-key") {
            // A publisher's key: the private half to the file, the public half
            // printed, for Updater.publicKey.
            let key = Curve25519.Signing.PrivateKey()
            guard FileManager.default.createFile(atPath: path, contents: Data((key.rawRepresentation
                .base64EncodedString() + "\n").utf8), attributes: [.posixPermissions: 0o600]) else { exit(1) }
            print(key.publicKey.rawRepresentation.base64EncodedString())
            exit(0)
        }
        if let out = value("--make-catalog"), let key = value("--key") {
            let resources = value("--from").map { URL(fileURLWithPath: $0) }
                ?? Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
            // Each catalog the folder has a manifest for: the fixes', and the Wine modules'.
            let kinds = CatalogKind.allCases.filter { Catalog.manifest(in: resources, $0) != nil }
            guard !kinds.isEmpty else { print("no catalog.json"); exit(1) }
            do {
                for kind in kinds {
                    let manifest = Catalog.manifest(in: resources, kind)!
                    try Updater.makeRelease(kind, from: resources, to: URL(fileURLWithPath: out),
                                            keyFile: URL(fileURLWithPath: key), version: manifest.version,
                                            minimumApp: manifest.minimumApp, names: manifest.files.keys.sorted())
                    print("\(kind.stem) \(manifest.version) written to \(out)")
                }
                exit(0)
            } catch {
                print("could not write the catalog: \(error.localizedDescription)")
                exit(1)
            }
        }
        MacGameFixApp.main()
    }
}

private final class ExitBox: @unchecked Sendable { var code: Int32 = 0 }
