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
    @Published var modulesVersion = 0
    var resources = URL(fileURLWithPath: ".")
    /// The Wine modules' catalog in use, apart from the fixes'.
    var modulesDir = URL(fileURLWithPath: ".")

    private let extraKey = "extraFolders"

    /// Posted when the user has seen what the agent did; the menu bar drops its dot.
    static let seenNotification = Notification.Name("io.github.macgamefix.seen")

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

    // MARK: What a game runs on

    /// The CrossOver builds and D3DMetal versions this Mac carries, to choose from.
    lazy var choices = Runtimes.installedChoices()

    func runtime(_ hit: Hit) -> GameRuntime? { settings.runtime(for: hit.key, detected: hit.runtimes) }
    func chosen(_ hit: Hit) -> Bool { settings.runtimes[hit.key] != nil }
    func fit(_ hit: Hit) -> Fit { settings.fit(hit.game, key: hit.key, detected: hit.runtimes) }

    /// The user's word on what a game runs on; nil goes back to what was found.
    func choose(_ hit: Hit, _ runtime: GameRuntime?) {
        settings.runtimes[hit.key] = runtime
        settings.save()
        objectWillChange.send()
    }

    // MARK: Automatic

    func isKept(_ hit: Hit) -> Bool {
        settings.kept.contains { $0.key == hit.key }
    }

    func setKept(_ hit: Hit, _ on: Bool) {
        settings.kept.removeAll { $0.key == hit.key }
        if on {
            settings.kept.append(KeptGame(name: hit.game.name, folder: hit.folder.path,
                                          prefix: hit.game.needsPrefix ? hit.prefix?.path.path : nil))
        }
        settings.save()
        refreshEvents()
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

    /// Both catalogs now, the user asking: whatever is newer is installed.
    func checkNow() {
        guard !busy else { return }
        busy = true
        status = "Looking for new fixes and Wine modules…"
        Task {
            var lines: [String] = []
            for kind in CatalogKind.allCases {
                do {
                    let line = try await Updater.update(kind)
                    var state = AgentState.load()
                    state[keyPath: AgentState.offered(kind)] = 0
                    state[keyPath: AgentState.line(kind)] = line
                    state.save()
                    lines.append(line)
                } catch { lines.append("Could not update the \(kind.noun): \(error.localizedDescription)") }
            }
            loadCatalog()
            refreshEvents()
            updateLine = lines.joined(separator: " ")
            busy = false
            status = updateLine
            scan()
        }
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
            for i in hits.indices { hits[i] = await probe(hits[i]) }
            busy = false
            status = found.isEmpty ? "No supported game found in these folders." : "\(found.count) game(s) found."
        }
    }

    /// Asks the installer what it sees. Only the state word is kept: --status
    /// also prints paths, and the installer's own judgement is the only one.
    func probe(_ hit: Hit) async -> Hit {
        var hit = hit
        if hit.game.needsPrefix && hit.prefix == nil {
            hit.state = .unknown
            return hit
        }
        hit.state = await Fixer.status(hit.game, folder: hit.folder, prefix: hit.prefix?.path.path,
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
        if install {
            let doubtful = targets.compactMap { hit -> String? in
                switch fit(hit) {
                case .mismatch, .notNeeded: return "\(hit.game.name): \(fit(hit).label)"
                default: return nil
                }
            }
            if !doubtful.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Install fixes that do not fit?"
                alert.informativeText = doubtful.joined(separator: "\n\n")
                alert.addButton(withTitle: "Install Anyway")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
        }
        busy = true
        Task {
            var done = 0, failed = 0
            for hit in targets {
                done += 1
                status = "\(install ? "Installing" : "Removing") \(hit.game.name) (\(done) of \(targets.count))…"
                note(""); note("▸ \(hit.game.name) — \(hit.folder.path)")
                if let p = hit.prefix, hit.game.needsPrefix { note("  into \(p.label)") }
                let code = await Fixer.run(hit.game, folder: hit.folder, prefix: hit.prefix?.path.path,
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

    /// Only a CrossOver there are modules for, of its exact build and Wine, can be ticked.
    func engineSelectable(_ row: EngineRow) -> Bool { row.state != .noModules && row.state != .unknown }

    func setAllEngineKept(_ on: Bool) {
        for row in engineRows where engineSelectable(row) { setEngineKept(row, on) }
    }

    /// Installs, now, into every ticked CrossOver that does not have the current modules.
    func installSelectedEngine() {
        guard !busy else { return }
        let rows = engineRows.filter { engineKept($0) && engineSelectable($0) && $0.state != .installed }
        guard !rows.isEmpty else { status = "Every ticked CrossOver has the current modules."; return }
        busy = true
        Task {
            var failed = 0
            for (n, row) in rows.enumerated() {
                status = "Installing the modules into \(row.target.name) (\(n + 1) of \(rows.count))…"
                note(""); note("▸ Wine modules — \(row.target.name) — \(row.target.root.path)")
                let code = await Engine.run(row.target, catalog: modulesDir, []) { line in
                    Task { @MainActor in self.note("  " + line) }
                }
                await Task.yield()
                let state = await Engine.status(row.target, catalog: modulesDir)
                if let i = engineRows.firstIndex(where: { $0.id == row.id }) {
                    engineRows[i].state = state
                    engineRows[i].outcome = code == 0 && state == .installed ? nil : "Failed — see the log"
                }
                if code != 0 || state != .installed { failed += 1 }
            }
            busy = false
            status = failed == 0 ? "Installed into \(rows.count) CrossOver install(s)."
                : "\(failed) of \(rows.count) need attention — see the log."
        }
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
        }
    }

    func engineApply(_ row: EngineRow, install: Bool) {
        guard !busy else { return }
        busy = true
        status = "\(install ? "Installing the modules into" : "Removing the modules from") \(row.target.name)…"
        Task {
            note(""); note("▸ Wine modules — \(row.target.name) — \(row.target.root.path)")
            let code = await Engine.run(row.target, catalog: modulesDir, install ? [] : ["--restore"]) { line in
                Task { @MainActor in self.note("  " + line) }
            }
            await Task.yield()
            let state = await Engine.status(row.target, catalog: modulesDir)
            if let i = engineRows.firstIndex(where: { $0.id == row.id }) {
                engineRows[i].state = state
                // As with the games, the state asked afterwards is the authority.
                let took = install ? state == .installed : state == .absent
                engineRows[i].outcome = code != 0 ? "Failed — see the log in Settings"
                    : took ? nil : "Did not take — see the log in Settings"
            }
            // What the user chose here is what the agent keeps: in, or left out.
            let path = row.target.key
            if code == 0 {
                settings.modulesKept.removeAll { Engine.resolved($0) == path }
                settings.modulesDeclined.removeAll { Engine.resolved($0) == path }
                if install { settings.modulesKept.append(path) } else { settings.modulesDeclined.append(path) }
                settings.save()
            }
            busy = false
            status = code == 0 ? "Done: \(row.target.name)." : "\(row.target.name) needs attention."
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
                        Picker("Registry keys go into", selection: $hit.prefix) {
                            ForEach(hit.prefixes) { p in Text(p.label).tag(Optional(p)) }
                        }
                        .font(.caption)
                        .frame(maxWidth: 420)
                        .disabled(busy)
                    } else if let p = hit.prefix {
                        Text("Registry keys go into the \(p.label)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let b = hit.blocker {
                    Text(b).font(.caption).foregroundStyle(.red)
                }
                RuntimeLine(hit: hit, model: model)
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

/// The Wine modules: the part of MacGameFix that does change CrossOver.
struct EngineView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wine Modules").font(.title2.bold())
                Text("DualSense haptics on a USB cable: three Wine files that go into CrossOver itself. The originals are kept.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("They replace CrossOver's own in a CrossOver app or a NotProton runner, and Remove puts the "
                          + "originals back. Quit that CrossOver's games first. In a CrossOver app, macOS asks to allow "
                          + "MacGameFix under App Management, and the app is signed again ad hoc. A CrossOver or "
                          + "NotProton update puts CrossOver's own files back.")
            }
            HStack {
                Button("Look Again") { model.scanEngine() }.disabled(model.busy)
                Spacer()
                Text("Modules for: " + (model.engineBuilds.isEmpty ? "none in this catalog"
                     : model.engineBuilds.map(\.crossover).joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            if model.engineRows.isEmpty {
                VStack {
                    Spacer()
                    Text(model.busy ? "Looking…" : "No CrossOver or NotProton runner found.").foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(model.engineRows) { row in EngineRowView(row: row, model: model) }
                    .frame(minHeight: 260)
            }
        }
        .onAppear { if model.engineRows.isEmpty { model.scanEngine() } }
    }
}

struct EngineRowView: View {
    let row: EngineRow
    @ObservedObject var model: Model

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.target.name).font(.headline)
                    Spacer()
                    if let o = row.outcome { Text(o).font(.caption).foregroundStyle(.orange) }
                    Text(row.state.label).font(.callout).foregroundStyle(row.state.color)
                }
                Text("Build \(row.target.build)" + (row.target.fex ? " · Intel (Rosetta) and FEX sides" : " · Intel (Rosetta) side"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(row.target.root.path).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                HStack {
                    Button(row.state == .outdated ? "Update" : "Install") { model.engineApply(row, install: true) }
                        .disabled(model.busy || row.state == .installed || row.state == .noModules || row.state == .unknown)
                    Button("Remove") { model.engineApply(row, install: false) }
                        .disabled(model.busy || row.state == .absent || row.state == .noModules || row.state == .unknown)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
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
                Picker("Wine modules", selection: Binding(get: { model.modulesMode }, set: { model.setModulesMode($0) })) {
                    ForEach(Model.UpdateMode.allCases) { Text($0.label).tag($0) }
                }
                .help("New Wine modules from GitHub, on their own. On automatic they also go back into the "
                      + "NotProton runners you put them into after an update, and into a runner for a new "
                      + "CrossOver build. A CrossOver app is only ever reported.")
                if let waiting = model.waitingModules {
                    LabeledContent(String(localized: "New Wine modules ready (\(String(waiting)))")) {
                        Button("Install") { model.checkForModules() }.disabled(model.busy)
                    }
                    .foregroundStyle(.orange)
                }
                LabeledContent("In use") {
                    HStack {
                        Text(verbatim: "\(model.catalogVersion) · \(model.modulesVersion)")
                            .foregroundStyle(.secondary)
                            .help("The game fixes' catalog and the Wine modules' catalog.")
                        Button("Check Now") { model.checkNow() }.disabled(model.busy)
                    }
                }
            } header: {
                Text("Updates from GitHub")
            }

            Section {
                ForEach(model.engineRows) { row in
                    Toggle(isOn: Binding(get: { model.engineKept(row) }, set: { model.setEngineKept(row, $0) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.target.name).lineLimit(1).truncationMode(.middle)
                            Text(model.engineSelectable(row)
                                 ? "\(row.target.build) · \(row.state.label)"
                                 : "\(row.target.build) · no modules for this build")
                                .font(.caption)
                                .foregroundStyle(model.engineSelectable(row) ? row.state.color : .secondary)
                        }
                    }
                    .disabled(!model.engineSelectable(row) || model.busy)
                    .help(row.target.root.path)
                }
                if model.engineRows.isEmpty {
                    Text(model.busy ? "Looking…" : "No CrossOver or NotProton runner found.").foregroundStyle(.secondary)
                }
                Toggle("New CrossOver builds too", isOn: Binding(
                    get: { model.settings.modulesNewBuilds },
                    set: { model.settings.modulesNewBuilds = $0; model.settings.save(); model.objectWillChange.send() }))
                    .help("On Automatic: when NotProton adds a runner for a new CrossOver build and there are modules "
                          + "for it, they go there as well, once a ticked runner has them.")
                HStack {
                    Button("All") { model.setAllEngineKept(true) }
                    Button("None") { model.setAllEngineKept(false) }
                    Spacer()
                    Button("Install into Ticked Now") { model.installSelectedEngine() }
                        .disabled(model.busy || model.engineRows.isEmpty)
                }
            } header: {
                Text("Wine modules go into")
            } footer: {
                Text("Only a CrossOver of a build and Wine the modules were built for can be ticked. Unticking stops "
                     + "updates there and removes nothing.")
                    .font(.caption).foregroundStyle(.secondary)
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

/// What the game runs on, whether the fix fits it, and a way to say otherwise.
struct RuntimeLine: View {
    let hit: Hit
    @ObservedObject var model: Model
    @State private var editing = false

    var body: some View {
        let fit = model.fit(hit)
        let runtime = model.runtime(hit)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(runtime.map { (model.chosen(hit) ? "You said: " : "Runs on: ") + $0.summary }
                     ?? "Runs on: unknown")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(editing ? "Done" : "Change…") { editing.toggle() }.font(.caption).buttonStyle(.link)
            }
            Text(fit.label).font(.caption).foregroundStyle(color(fit))
            if editing { editor(runtime) }
        }
    }

    private func color(_ fit: Fit) -> Color {
        switch fit {
        case .fits: return .green
        case .notNeeded: return .secondary
        case .mismatch: return .red
        case .unknown: return .orange
        }
    }

    @ViewBuilder private func editor(_ current: GameRuntime?) -> some View {
        let base = current ?? GameRuntime(source: "your choice")
        VStack(alignment: .leading, spacing: 4) {
            if hit.runtimes.count > 1 {
                Picker("Found", selection: Binding(
                    get: { model.settings.runtimes[hit.key] },
                    set: { model.choose(hit, $0) })) {
                    Text("Not chosen").tag(GameRuntime?.none)
                    ForEach(hit.runtimes, id: \.self) { r in Text(r.summary).tag(Optional(r)) }
                }
            }
            Picker("CrossOver", selection: Binding(
                get: { base.build ?? "" },
                set: { var r = base; r.source = "your choice"; r.build = $0.isEmpty ? nil : $0; model.choose(hit, r) })) {
                Text("Unknown").tag("")
                ForEach(model.choices.builds, id: \.self) { b in
                    Text(GameRuntime(source: "", build: b).crossover.map { "\($0) (\(b))" } ?? b).tag(b)
                }
            }
            Picker("D3DMetal", selection: Binding(
                get: { base.noD3DMetal ? "none" : (base.d3dmetal ?? "") },
                set: { var r = base; r.source = "your choice"
                       r.noD3DMetal = $0 == "none"; r.d3dmetal = ($0.isEmpty || $0 == "none") ? nil : $0
                       model.choose(hit, r) })) {
                Text("Unknown").tag("")
                Text("None (FEX)").tag("none")
                ForEach(model.choices.d3dmetal, id: \.self) { v in Text(v).tag(v) }
            }
            Picker("Backend", selection: Binding(
                get: { base.backend ?? "" },
                set: { var r = base; r.source = "your choice"; r.backend = $0.isEmpty ? nil : $0; model.choose(hit, r) })) {
                Text("Automatic (D3DMetal)").tag("")
                Text("D3DMetal").tag("d3dmetal")
                Text("DXMT").tag("dxmt")
                Text("DXVK").tag("dxvk")
                Text("WineD3D").tag("wined3d")
            }
            if model.chosen(hit) {
                Button("Use what MacGameFix found") { model.choose(hit, nil) }.font(.caption)
            }
        }
        .font(.caption)
        .frame(maxWidth: 460)
        .disabled(model.busy)
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
/// --agent-once, --menu-report, --runtime-report, --engine-report,
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
        if args.contains("--runtime-report") {
            // Every supported game found, what it runs on, and whether its fix fits.
            let settings = AutoSettings.load()
            let (dir, _) = Catalog.active()
            for hit in Libraries.find(Catalog.games(in: dir), extra: []).hits {
                let runtime = settings.runtime(for: hit.key, detected: hit.runtimes)
                print("\(hit.game.name) | \(runtime?.summary ?? "unknown (\(hit.runtimes.count) found)") | "
                      + settings.fit(hit.game, key: hit.key, detected: hit.runtimes).label)
                if args.contains("--verbose") {
                    for r in hit.runtimes {
                        print("    found: \(r.summary)\(r.setUpHere ? " (set for this game in Steam, and run)" : "")")
                    }
                }
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
