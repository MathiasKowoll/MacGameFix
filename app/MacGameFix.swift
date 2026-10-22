// MacGameFix -- fixes that go into a game's own folder, and Wine modules.
//
// Every game fix this app carries lives in a game's own folder: a proxy DLL
// beside the game, and for a few titles registry keys in that game's own prefix.
// NINJA GAIDEN 3's is the one that lives in the prefix instead: DLLs in the
// system32 of its bottle or Steam Play prefix, and overrides for that executable
// alone. None of them changes CrossOver, so they work with CrossOver as
// CodeWeavers ships it, with CrossOver Preview, and with a Steam Play tool such
// as NotProton. Cyberpunk 2077's is for a macOS game, with no Wine: it changes
// four bytes of the game's executable, from a recipe for each build of the
// game, and signs its app again ad hoc.
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
    /// Which CrossOvers Game Mode covers, or why none (GameMode.swift).
    @Published var gameModeLine = ""
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
    /// The CrossOver apps macOS refused to let this app change, by name, from the
    /// last look; the Wine Modules tab offers App Management for them.
    @Published var appManagementBlocked: [String] = []
    /// The CrossOver builds the Wine modules' catalog carries modules for.
    @Published var engineBuilds: [EngineBuild] = []
    /// The Game Feel tab's options, observations and presets.
    @Published var pad = PadStore.load()
    @Published var padGames: [InstalledGame] = []
    /// Every Steam game's folder, for the Report tab, and the fix the catalog has
    /// for each one that has one, by ProbeGame.id.
    @Published var probeGames: [ProbeGame] = []
    @Published var probeFixes: [String: String] = [:]
    let padPresets = PadPresets.load()
    /// Trying the haptics and the triggers on the pad, from the Game Feel sheets.
    let padTester = PadTester()
    /// pad.conf and pad.d written by this launch, so they carry its keys and presets.
    private var padWritten = false
    /// App Management looked at by this launch.
    private var appManagementChecked = false
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
        // Keeping a fix that changes a macOS game's app lets the agent change
        // the app in the background, so it is asked about as installing is.
        if on, hit.game.inApp, !isKept(hit), !confirmGameApps([hit], keep: true) { objectWillChange.send(); return }
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
        if !hits[i].selectable { hits[i].selected = false }
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

    /// Game Mode for CrossOver's games: the bundles and links put in place, or taken away.
    func setGameMode(_ on: Bool) {
        settings.gameMode = on
        settings.save()
        objectWillChange.send()
        Task {
            let line = await Task.detached { () -> String in
                if !on { GameMode.remove(); return "" }
                GameMode.keep()
                return GameMode.coverage()
            }.value
            gameModeLine = line
        }
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

    var selected: [Hit] { hits.filter { $0.selected && $0.selectable } }

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
        if hit.game.needsPrefix {
            hit.state = await Fixer.status(hit.game, folder: hit.folder, prefixes: hit.chosen.map(\.path.path),
                                           catalog: resources)
        } else {
            let look = await Fixer.look(hit.game, folder: hit.folder, prefix: nil, catalog: resources)
            (hit.state, hit.build, hit.note) = (look.state, look.build, look.note)
        }
        if !hit.selectable { hit.selected = false }
        return hit
    }

    func apply(install: Bool) {
        guard !busy else { return }
        // A row waiting for a recipe is only removed: what MacGameFix kept for
        // the game's earlier builds goes.
        let targets = selected.filter { install ? $0.blocker == nil && $0.state != .installed : $0.state != .absent }
        guard !targets.isEmpty else {
            status = install ? "Nothing selected needs installing." : "Nothing selected is installed."
            return
        }
        if install, !confirmGameApps(targets.filter(\.game.inApp)) { return }
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
                    let took = install ? h.state == .installed
                        : h.state == .absent || (hit.state == .noRecipe && h.state == .noRecipe)
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

    /// A fix that changes a macOS game's own app is asked about first, as a
    /// CrossOver app is in Wine Modules: it signs the app again. Keep asks too,
    /// since the agent then does it in the background.
    private func confirmGameApps(_ hits: [Hit], keep: Bool = false) -> Bool {
        guard !hits.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = hits.count == 1 ? "Change \(hits[0].game.name)'s app?" : "Change \(hits.count) games' apps?"
        alert.informativeText = (hits.count == 1
            ? "MacGameFix writes the recipe's bytes into its executable and signs it again ad hoc, so the developer's "
                + "signature no longer covers the executable."
            : "MacGameFix writes the recipe's bytes into the executables of "
                + ListFormatter.localizedString(byJoining: hits.map(\.game.name))
                + " and signs each again ad hoc, so the developers' signatures no longer cover them.")
            + " macOS may ask you to allow MacGameFix under App Management. Remove puts the original back from the "
            + "copy MacGameFix keeps."
            + (keep ? " With Keep on, the agent does this in the background whenever the fix is missing, after a game "
                + "update too, without asking again." : "")
        alert.addButton(withTitle: keep ? "Keep" : "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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

    /// Whether the agent keeps the modules there from now on. The switch in Wine
    /// Modules sets this and also installs or removes them (setEngineOn).
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
        alert.informativeText = "MacGameFix puts its Wine modules into " + rows.map(\.target.name).joined(separator: ", ")
            + ". macOS asks you to allow MacGameFix under App Management, and the app is signed again ad hoc, "
            + "so CodeWeavers' signature no longer covers it. Turning it off puts CrossOver's own files back."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Whether macOS lets MacGameFix change this CrossOver's files: App
    /// Management, for a CrossOver app; a runner is not an app and needs none.
    /// The asking is a write, an empty file made and removed beside the modules,
    /// which also puts MacGameFix in System Settings' list when it is refused.
    nonisolated static func mayChange(_ target: EngineTarget) -> Bool {
        guard target.app != nil else { return true }
        let probe = target.root.appendingPathComponent("lib/wine/.macgamefix-access")
        guard FileManager.default.createFile(atPath: probe.path, contents: Data()) else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }

    /// The rows macOS lets this app change. A refused write makes macOS show its
    /// own notification, so nothing more is asked here: a CrossOver app it refused
    /// is kept in appManagementBlocked, for the Wine Modules tab's notice.
    func allowedToChange(_ rows: [EngineRow]) -> [EngineRow] {
        let blocked = rows.filter { !Model.mayChange($0.target) }
        let checked = Set(rows.map(\.target.name))
        appManagementBlocked = appManagementBlocked.filter { !checked.contains($0) } + blocked.map(\.target.name)
        return rows.filter { row in !blocked.contains { $0.id == row.id } }
    }

    /// Check Again: each CrossOver app the modules are kept in, or that was refused.
    func checkAppManagement() {
        _ = allowedToChange(engineRows.filter {
            $0.target.app != nil && (engineKept($0) || appManagementBlocked.contains($0.target.name))
        })
    }

    func openAppManagement() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Installs into, or removes from, each of these CrossOver installs in turn.
    func engineBatch(_ rows: [EngineRow], install: Bool) {
        guard !busy, !rows.isEmpty else { return }
        let allowed = allowedToChange(rows)
        let refused = rows.filter { row in !allowed.contains { $0.id == row.id } }.map(\.target.name)
        let needs = refused.isEmpty ? "" : " " + ListFormatter.localizedString(byJoining: refused)
            + " " + (refused.count == 1 ? "needs" : "need") + " App Management: see Wine Modules."
        guard !allowed.isEmpty else { status = needs.trimmingCharacters(in: .whitespaces); return }
        let rows = allowed
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
            status = (failed == 0 ? "Done." : "\(failed) of \(rows.count) need attention — see the log in Settings.") + needs
        }
    }

    // MARK: The controllers

    /// The Game Feel tab is there while a CrossOver has the Wine modules that
    /// read its options in: those that carry winebus.so. An older build of them
    /// reads them too, so a new build of the modules does not hide the tab.
    var padAvailable: Bool {
        engineRows.contains { row in
            [.installed, .outdated].contains(row.state) && (engineBuilds.first { $0.build == row.target.build }?.files.keys
                .contains { $0.hasSuffix("unix/winebus.so") } ?? false)
        }
    }

    /// The Steam games on this Mac, and what the modules logged since the last look.
    func scanPad() {
        let extra = extraFolders
        Task {
            let games = await Task.detached { () -> [InstalledGame] in
                // Which game each exe is, for the modules in a CrossOver bottle.
                PadExes.keep()
                return SteamGames.installed(extra: extra)
            }.value
            padGames = games
            var store = PadStore.exists ? PadStore.load() : pad
            if store.absorbLog(names: { Dictionary(games.map { ($0.appid, $0.name) }, uniquingKeysWith: { a, _ in a }) }) {
                store.save()
            }
            pad = store
            // What the store says of each game decides its XInput by default.
            if padAvailable, await store.learnStore(games) {
                var fresh = PadStore.load()
                for (appid, game) in store.games where game.dualSense != nil || game.storeUnknown {
                    var entry = fresh.games[appid] ?? PadGame(name: game.name)
                    entry.dualSense = game.dualSense
                    entry.storeUnknown = game.storeUnknown
                    fresh.games[appid] = entry
                }
                fresh.save()
                fresh.writeConfig(presets: padPresets)
                pad = fresh
            }
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

    /// The modules' diagnostics for one game, for a report.
    func setPadDiagnose(_ game: InstalledGame, _ on: Bool) {
        setPad { store in
            var entry = store.games[game.appid] ?? PadGame(name: game.name)
            entry.name = game.name
            entry.diagnose = on
            store.games[game.appid] = entry.isEmpty ? nil : entry
        }
    }

    /// One game's report, saved where the user chooses, and a new issue opened
    /// with the template it belongs to, for the user to attach it.
    func padReport(_ game: InstalledGame) {
        guard savePadReport(game, as: "MacGameFix report") else { return }
        if let link = Issue.new(template: "controller.yml",
                                ["title": "[Controller] \(game.name)",
                                 "game": "\(game.name) (Steam app \(game.appid))"]) {
            NSWorkspace.shared.open(link)
        }
    }

    /// The same report, and the settings form opened with the game's settings in
    /// it, for settings that felt right to become a game's suggested ones.
    func padShare(_ game: InstalledGame) {
        guard savePadReport(game, as: "MacGameFix settings") else { return }
        let store = PadStore.exists ? PadStore.load() : pad
        if let link = store.shareIssue(appid: game.appid, name: game.name, presets: padPresets) {
            NSWorkspace.shared.open(link)
        }
    }

    /// The same report, and the form for a game that vibrates opened with the pad, the
    /// connection and the identity the modules saw last and the library the game's folder
    /// shows, for the list of games played for vibration.
    func padVibrates(_ game: InstalledGame) {
        guard savePadReport(game, as: "MacGameFix vibration report") else { return }
        let store = PadStore.exists ? PadStore.load() : pad
        let presets = padPresets, extra = extraFolders
        let log = (try? String(contentsOf: PadStore.log, encoding: .utf8)) ?? ""
        Task {
            let library = await Task.detached {
                ProbeGames.all(extra: extra).first { $0.appid == game.appid }.flatMap { Probe.look($0).padLibrary }
            }.value
            if let link = store.vibratesIssue(appid: game.appid, name: game.name, presets: presets,
                                              library: library, log: log) {
                NSWorkspace.shared.open(link)
            }
        }
    }

    /// Saves a game's report where the user chooses and shows it in the Finder;
    /// false if the user cancels or it could not be written.
    private func savePadReport(_ game: InstalledGame, as kind: String) -> Bool {
        let store = PadStore.exists ? PadStore.load() : pad
        let text = store.report(appid: game.appid, name: game.name, presets: padPresets,
                                engines: engineRows.map { ($0.target.name, $0.target.build, $0.state.label) })
        return saveReport(text, as: kind, for: game.name)
    }

    private func saveReport(_ text: String, as kind: String, for name: String) -> Bool {
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: " ")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(kind) - \(safe) - \(day).md"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch {
            note("The report could not be saved: \(error.localizedDescription)")
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    // MARK: The Report tab

    /// Every Steam game's folder, looked for again, with the fix the catalog has for it.
    func scanProbe() {
        let extra = extraFolders
        Task {
            let (games, fixes) = await Task.detached { () -> ([ProbeGame], [String: String]) in
                let games = ProbeGames.all(extra: extra)
                let catalog = Catalog.games(in: Catalog.active().dir)
                var fixes: [String: String] = [:]
                for game in games {
                    if let fix = catalog.first(where: { $0.isRooted(at: game.folder) }) { fixes[game.id] = fix.name }
                }
                return (games, fixes)
            }.value
            probeGames = games
            probeFixes = fixes
        }
    }

    /// A game's report, saved where the user chooses, and the issue form for a game
    /// that does not work opened with the game and what goes wrong in it.
    func probeReport(_ game: ProbeGame, symptom: ProbeSymptom, findings: ProbeFindings) {
        let engines = engineRows.map { ($0.target.name, $0.target.build, $0.state.label) }
        let log = (try? String(contentsOf: PadStore.log, encoding: .utf8)) ?? ""
        let padLines = log.split(separator: "\n").map(String.init).filter { $0.contains(" game=\(game.appid) ") }
        let text = Probe.report(game, symptom: symptom.rawValue, findings: findings, fix: probeFixes[game.id],
                                engines: engines, padLines: padLines)
        guard saveReport(text, as: "MacGameFix game report", for: game.name) else { return }
        if let link = Issue.new(template: "game-report.yml",
                                ["title": "[Game] \(game.name)",
                                 "game": "\(game.name) (Steam app \(game.appid))",
                                 "what": symptom.rawValue + ". "]) {
            NSWorkspace.shared.open(link)
        }
    }

    /// A game's own options; a game left with none and nothing seen is forgotten.
    func setPadGame(_ game: InstalledGame, _ change: (inout PadOptions) -> Void) {
        setPad { store in
            var entry = store.games[game.appid] ?? PadGame(name: game.name)
            entry.name = game.name
            change(&entry.options)
            store.games[game.appid] = entry.isEmpty ? nil : entry
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
            // Game Mode's links, put back here too for anyone who keeps the agent off.
            if settings.gameMode {
                gameModeLine = await Task.detached { () -> String in
                    GameMode.keep()
                    return GameMode.coverage()
                }.value
            }
            // Once a launch: whether macOS lets this app change the CrossOver apps the
            // modules are kept in. A refusal shows macOS's own notification, and the
            // Wine Modules tab its notice; no alert of ours (one beside macOS's was
            // one too many, 2026-10-20).
            if !appManagementChecked {
                appManagementChecked = true
                let apps = rows.filter { $0.target.app != nil && engineKept($0) }
                if !apps.isEmpty { _ = allowedToChange(apps) }
            }
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

/// The size of the window's content, for the sheets that hang from it.
private struct WindowSizeEnvironment: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    var windowSize: CGSize {
        get { self[WindowSizeEnvironment.self] }
        set { self[WindowSizeEnvironment.self] = newValue }
    }
}

extension View {
    /// A Game Feel sheet: as large as its options want, and never larger than the
    /// window, whose edges cut off a sheet that does not fit. The form scrolls.
    func padSheetSize(in window: CGSize) -> some View {
        frame(width: window.width > 0 ? min(820, max(520, window.width - 40)) : 820,
              height: window.height > 0 ? min(860, max(400, window.height - 40)) : 860)
    }
}

struct ContentView: View {
    @StateObject private var model = Model()
    @State private var windowSize = CGSize.zero

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
                ReportView(model: model).padding(.top, 6)
                    .tabItem { Text("Report") }
                SettingsView(model: model).padding(.top, 6)
                    .tabItem { Text("Settings") }
            }
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout)
            }
        }
        .padding(16)
        // Five tabs of 107 pt each (the width "Wine Modules" sets), centred clear of the window's buttons:
        // at 620 pt they went behind the toolbar's overflow menu (seen 2026-10-20).
        .frame(minWidth: 720, minHeight: 460)
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { windowSize = $0 }
        .environment(\.windowSize, windowSize)
        .onAppear { model.scan() }
    }
}

/// The games and their fixes, which go into each game's own folder.
struct GamesView: View {
    @ObservedObject var model: Model
    /// Every supported game on this Mac first, whatever was chosen last time.
    @State private var filter = GamesFilter.all

    /// Fixed: the game has its fix in place. All fixes adds the fixes for games not on this Mac.
    enum GamesFilter: String, CaseIterable, Identifiable {
        case all = "All", fixed = "Fixed", notFixed = "Not fixed", allFixes = "All fixes"
        var id: String { rawValue }
    }

    /// A row: a game found on this Mac, or, under All fixes, one the catalog has a fix for that is not here.
    struct GameRow: Identifiable {
        let game: Game
        let hit: Hit?
        var id: String { hit?.id ?? "fix|" + game.name }
    }

    /// Fixed counts a fix of an older build, a half one and one that needs repair: each is on disk.
    private func shows(_ hit: Hit) -> Bool {
        if model.onlyReview && model.keptLine(hit)?.needsUser != true { return false }
        switch filter {
        case .all, .allFixes: return true
        case .fixed: return [.installed, .outdated, .half, .broken].contains(hit.state)
        case .notFixed: return [.absent, .noCarrier, .noRecipe, .blocked].contains(hit.state)
        }
    }

    private var shownHits: [Hit] { model.hits.filter(shows) }

    private var rows: [GameRow] {
        var rows = shownHits.map { GameRow(game: $0.game, hit: $0) }
        if filter == .allFixes && !model.onlyReview {
            let found = Set(model.hits.map(\.game.name))
            rows += model.games.filter { !found.contains($0.name) }.map { GameRow(game: $0, hit: nil) }
            rows.sort { $0.game.name.localizedCaseInsensitiveCompare($1.game.name) == .orderedAscending }
        }
        return rows
    }

    /// The table's selection is the hits' own, so Install and Remove Selected act on it.
    private var selection: Binding<Set<Hit.ID>> {
        Binding(get: { Set(model.hits.filter(\.selected).map(\.id)) },
                set: { ids in
                    for i in model.hits.indices {
                        model.hits[i].selected = ids.contains(model.hits[i].id) && model.hits[i].selectable
                    }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacGameFix").font(.title2.bold())
                Text("Fixes go into each game's own folder, a few also into its prefix or bottle, one into a macOS game's app, and never change CrossOver. Quit a game before changing its fix.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("The Windows games' fixes work with CrossOver as it ships, CrossOver Preview, and Steam Play tools such as NotProton.")
            }

            HStack {
                Button("Scan") { model.scan() }.disabled(model.busy)
                Button("Add Folder…") { model.addFolder() }.disabled(model.busy)
                Spacer()
                Button("Select All") { selection.wrappedValue = Set(shownHits.map(\.id)) }
                    .disabled(model.busy || shownHits.isEmpty)
                Button("Install Selected") { model.apply(install: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy || model.selected.isEmpty)
                Button("Remove Selected") { model.apply(install: false) }
                    .disabled(model.busy || model.selected.isEmpty)
            }

            HStack {
                Picker("Show", selection: $filter) {
                    ForEach(GamesFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if !model.toReview.isEmpty {
                    Toggle("Only the marked games to review (\(model.toReview.count))", isOn: $model.onlyReview)
                        .font(.callout)
                }
                Spacer()
                if filter == .allFixes {
                    Text("\(model.games.count) fix(es), \(Set(model.hits.map(\.game.name)).count) of their games on this Mac")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !model.hits.isEmpty {
                    Text("\(shownHits.count) of \(model.hits.count) game(s)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(model.busy ? "Looking…"
                         : model.hits.isEmpty ? "No supported game found yet."
                         : filter == .fixed ? "No game is fixed yet. Not fixed shows the supported games found."
                         : "No game here.")
                        .foregroundStyle(.secondary)
                    Text("Supported: " + model.games.map(\.name).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Table(rows, selection: selection) {
                    TableColumn("Game") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.game.name).fontWeight(.semibold)
                            Text(row.game.symptom).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 3)
                        .help((row.hit.map { $0.folder.path + "\n\n" } ?? "") + row.game.why)
                    }
                    .width(min: 150, ideal: 200)
                    TableColumn("Requires") { row in
                        Text(row.game.requirementNote ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            .help(row.game.requirementNote ?? "")
                    }
                    .width(min: 100, ideal: 140)
                    TableColumn("Status") { row in
                        if let hit = row.hit { GameStatusCell(hit: hit, model: model) }
                        else { Text("Not on this Mac").foregroundStyle(.secondary) }
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn("Keep") { row in
                        if let hit = row.hit {
                            Toggle("", isOn: Binding(get: { model.isKept(hit) }, set: { model.setKept(hit, $0) }))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .disabled((!hit.keepable && !model.isKept(hit)) || model.busy)
                                .help("Keep it applied: put it back after a game update.")
                        }
                    }
                    .width(44)
                    TableColumn("Goes into") { row in
                        if let hit = row.hit { GamePrefixCell(hit: hit, model: model) }
                        else { Text("—").font(.caption).foregroundStyle(.secondary) }
                    }
                    .width(min: 110, ideal: 140)
                }
                .frame(minHeight: 260)
            }
        }
    }
}

/// A game's state, and below it what went wrong: the last install, what stops the
/// buttons, or the agent's background attempt with its report.
struct GameStatusCell: View {
    let hit: Hit
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.state.label).foregroundStyle(hit.state.color)
            if let o = hit.outcome {
                Text(o).font(.caption).foregroundStyle(.orange).lineLimit(2).help(o)
            }
            if let b = hit.blocker {
                // Waiting for a recipe is not a fault: a catalog update ends it.
                Text(b).font(.caption).foregroundStyle(hit.state == .noRecipe ? Color.secondary : Color.red).lineLimit(2).help(b)
            }
            if let line = model.keptLine(hit), line.word == "Failed" {
                let detail = "In the background: \(line.detail ?? "the fix did not take.")"
                Text(detail).font(.caption).foregroundStyle(.orange).lineLimit(2).help(detail)
                if let r = line.report, let url = URL(string: r) {
                    Button("Report on GitHub…") { NSWorkspace.shared.open(url) }.font(.caption).buttonStyle(.link)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// Where a fix that writes registry keys, or puts DLLs into a prefix, goes: a menu
/// of every prefix and bottle found, any number of them checked. Two bottles of the
/// same name (CrossOver's and another root's) are told apart by their folder.
struct GamePrefixCell: View {
    let hit: Hit
    @ObservedObject var model: Model

    private func name(_ p: Prefix) -> String {
        guard hit.prefixes.filter({ $0.label == p.label }).count > 1 else { return p.label }
        let root = p.path.deletingLastPathComponent()
        return p.label + " (" + root.deletingLastPathComponent().lastPathComponent + "/" + root.lastPathComponent + ")"
    }

    var body: some View {
        if hit.game.inApp {
            Text("Its app").font(.caption).foregroundStyle(.secondary)
                .help("Changes the game's executable and signs it again ad hoc; the original is kept in MacGameFix's app-backup folder.")
        } else if !hit.game.needsPrefix {
            Text(hit.game.inPrefix ? "Its prefix" : "Its folder").font(.caption).foregroundStyle(.secondary)
        } else if hit.prefixes.count <= 1 {
            Text(hit.chosen.first.map(name) ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .help(hit.game.prefixWhat + " " + (hit.chosen.first.map(name) ?? "no prefix found") + ".")
        } else {
            Menu {
                ForEach(hit.prefixes) { p in
                    Toggle(name(p), isOn: Binding(get: { hit.chosen.contains(p) },
                                                  set: { on in model.choosePrefix(hit, p, on) }))
                }
            } label: {
                Text(hit.chosen.isEmpty ? "Choose…"
                     : hit.chosen.count == 1 ? name(hit.chosen[0]) : "\(hit.chosen.count) places")
                    .font(.caption)
            }
            .disabled(model.busy)
            .help(hit.game.prefixWhat + ": " + (hit.chosen.isEmpty ? "none chosen" : hit.chosen.map(name).joined(separator: ", ")) + ".")
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
            if !model.appManagementBlocked.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("macOS does not let MacGameFix change "
                              + ListFormatter.localizedString(byJoining: model.appManagementBlocked) + ".",
                              systemImage: "lock.shield")
                        Text("Turn MacGameFix on in System Settings › Privacy & Security › App Management, then "
                             + "check again. A new build of MacGameFix may need it turned on again.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button("Check Again") { model.checkAppManagement() }
                            Button("Open App Management…") { model.openAppManagement() }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
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
                    Text("The DualSense's haptics and triggers, on a cable and over Bluetooth")
                    Text("On installs the Wine modules into that CrossOver; off puts CrossOver's own back.")
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

/// Report: every Steam game on this Mac. For one that does not work, what MacGameFix
/// finds in it, the steps before a report, and the report an issue starts from.
struct ReportView: View {
    @ObservedObject var model: Model
    @State private var search = ""
    @State private var page = 0
    @State private var selection: ProbeGame.ID?
    @State private var reporting: ProbeGame?
    @AppStorage("reportPerPage") private var perPage = 15

    private var filtered: [ProbeGame] {
        guard !search.isEmpty else { return model.probeGames }
        return model.probeGames.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.appid == search }
    }
    private var pages: Int { max(1, (filtered.count + perPage - 1) / perPage) }
    private var shown: [ProbeGame] { Array(filtered.dropFirst(min(page, pages - 1) * perPage).prefix(perPage)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("A game that does not work").font(.headline)
                Text("Click it. MacGameFix looks at what the game is made of, without changing anything in it, and walks "
                     + "you through a report for an issue on GitHub, which is where it gets fixed. The report names that game alone.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    Spacer()
                    Button("Look Again") { model.scanProbe() }
                }
                Table(shown, selection: $selection) {
                    TableColumn("Game") { game in
                        HStack(spacing: 10) {
                            PadCover(appid: game.appid, height: 42)
                            Text(game.name)
                        }
                        .padding(.vertical, 2)
                    }
                    TableColumn("Runs in") { game in
                        Text(game.places.isEmpty ? "—" : game.places.joined(separator: ", ")).foregroundStyle(.secondary)
                    }
                    TableColumn("MacGameFix") { game in
                        Text(model.probeFixes[game.id] == nil ? "—" : "Has a fix").foregroundStyle(.secondary)
                    }
                }
                .onChange(of: selection) { _, id in
                    if let id, let game = model.probeGames.first(where: { $0.id == id }) { reporting = game }
                }
                HStack {
                    Text(model.probeGames.isEmpty ? "No Steam game found."
                         : filtered.isEmpty ? "No game matches." : "\(filtered.count) game(s)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Show", selection: $perPage) {
                        ForEach([15, 25, 50, 100], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .fixedSize()
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(page == 0)
                    Text("Page \(min(page, pages - 1) + 1) of \(pages)").font(.caption).monospacedDigit()
                    Button { page = min(pages - 1, page + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(page >= pages - 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .sheet(item: $reporting, onDismiss: { selection = nil }) { game in ReportSheet(game: game, model: model) }
        .onChange(of: search) { _, _ in page = 0 }
        .onChange(of: perPage) { _, _ in page = 0 }
        .onAppear { if model.probeGames.isEmpty { model.scanProbe() } }
    }
}

/// One game's report, step by step: what goes wrong, what MacGameFix found in the
/// game, what to do before the report, and the report.
struct ReportSheet: View {
    let game: ProbeGame
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSize) private var windowSize
    @State private var symptom = ProbeSymptom.start
    @State private var findings: ProbeFindings?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("What goes wrong", selection: $symptom) {
                        ForEach(ProbeSymptom.allCases) { Text($0.rawValue).tag($0) }
                    }
                } header: {
                    HStack(alignment: .center, spacing: 14) {
                        PadCover(appid: game.appid, height: 96)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.name).font(.title3)
                            Text("Steam app \(game.appid). "
                                 + (game.places.isEmpty ? "No prefix or bottle found beside its library."
                                    : "Runs in: " + game.places.joined(separator: ", ") + "."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Text(model.probeFixes[game.id].map { "MacGameFix has a fix for it in Games: \($0)." }
                                 ?? "MacGameFix has no fix for it yet.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                }
                Section {
                    if let findings {
                        ForEach(Array(findings.summary.enumerated()), id: \.offset) { _, row in
                            LabeledContent(row.0) { Text(row.1).multilineTextAlignment(.trailing) }
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking through the game's folder…").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("1. What MacGameFix found in the game")
                } footer: {
                    Text("Read from the game's folder alone; nothing in it was changed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("2. Before you make the report") {
                    ForEach(Array(symptom.steps.enumerated()), id: \.offset) { n, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(n + 1).").monospacedDigit().foregroundStyle(.secondary)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if symptom == .controller {
                        if model.padAvailable {
                            Toggle("Diagnose this game", isOn: Binding(
                                get: { model.pad.games[game.appid]?.diagnose == true },
                                set: { model.setPadDiagnose(InstalledGame(appid: game.appid, name: game.name), $0) }))
                                .help("The Wine modules log what this game writes to the pad, from its next start. "
                                      + "Turn it off again afterwards.")
                        } else {
                            Text("The Wine modules are in no CrossOver yet: turn them on in Wine Modules first.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Saves the report and opens a new issue on GitHub. Attach the report there, with any "
                             + "screenshot, and say what happens in your own words.")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Save the Report and Open an Issue…") {
                            if let findings { model.probeReport(game, symptom: symptom, findings: findings) }
                        }
                        .disabled(findings == nil)
                    }
                } header: {
                    Text("3. The report")
                } footer: {
                    Text("The report names this game alone, writes your home folder as ~ and leaves your Mac's name out. "
                         + "It adds the game's own log when the game writes one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .padSheetSize(in: windowSize)
        .task {
            let game = game
            findings = await Task.detached { Probe.look(game) }.value
        }
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
    @State private var global = false
    @AppStorage("gameFeelPerPage") private var perPage = 15

    private var filtered: [InstalledGame] {
        guard !search.isEmpty else { return model.padGames }
        return model.padGames.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.appid == search }
    }
    private var pages: Int { max(1, (filtered.count + perPage - 1) / perPage) }
    private var shown: [InstalledGame] { Array(filtered.dropFirst(min(page, pages - 1) * perPage).prefix(perPage)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Every game").font(.headline)
                    Text(model.pad.defaults.summary.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Every Game's Settings…") { global = true }
                    .help("What every game gets unless it has settings of its own: the connection, XInput, the "
                          + "haptics' strength and the trigger effects, each with a thirty-second try.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Divider()

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
                        HStack(spacing: 10) {
                            PadCover(appid: game.appid, height: 42)
                            Text(game.name).foregroundStyle(ownOptions(game).isEmpty ? Color.primary : Color.accentColor)
                        }
                        .padding(.vertical, 2)
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
                    Picker("Show", selection: $perPage) {
                        ForEach([15, 25, 50, 100], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .fixedSize()
                    .help("How many games a page shows.")
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(page == 0)
                    Text("Page \(min(page, pages - 1) + 1) of \(pages)").font(.caption).monospacedDigit()
                    Button { page = min(pages - 1, page + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(page >= pages - 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .sheet(item: $editing, onDismiss: { selection = nil }) { game in PadGameSheet(game: game, model: model) }
        .sheet(isPresented: $global) { PadGlobalSheet(model: model) }
        .onChange(of: search) { _, _ in page = 0 }
        .onChange(of: perPage) { _, _ in page = 0 }
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
/// row whose value is the game's own is in the accent colour. Showing the pad as
/// a DualShock 4 is a row of one game's form alone (PadOptions.asDualShock4).
struct PadOptionRows: View {
    let flag: (WritableKeyPath<PadOptions, Bool?>) -> Binding<Bool>
    let choice: (WritableKeyPath<PadOptions, String?>) -> Binding<String>
    let own: (PartialKeyPath<PadOptions>) -> Bool
    var perGame = false

    /// Shown as a DualShock 4, Bluetooth is a cable (PadOptions.lines) and the
    /// identity wins over the Edge's, so those rows say so and cannot be changed;
    /// XInput can carry the game's rumble to the motors (ds4XInputRumble), never
    /// the pad itself.
    private var asDualShock4: Bool { perGame && flag(\.asDualShock4).wrappedValue }

    private func title(_ text: String, _ key: PartialKeyPath<PadOptions>) -> Text {
        own(key) ? Text(text).foregroundColor(.accentColor) : Text(text)
    }

    /// A title with what it does under it, always in view.
    private func label(_ text: String, _ key: PartialKeyPath<PadOptions>, _ about: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title(text, key)
            Text(about).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// XInput's choice; shown as a DualShock 4 it is the game's own rumble or
    /// nothing (PadOptions.ds4XInputRumble), never the pad as a controller.
    private var xinputChoice: Binding<String> {
        guard asDualShock4 else { return choice(\.xinput) }
        let rumble = flag(\.ds4XInputRumble)
        return Binding(get: { rumble.wrappedValue ? "rumble" : "off" },
                       set: { rumble.wrappedValue = $0 == "rumble" })
    }

    private var xinputAbout: String {
        if asDualShock4 {
            return xinputChoice.wrappedValue == "rumble"
                ? "For a game that shows PlayStation buttons through the DualShock 4 but rumbles only through "
                  + "XInput: its rumble goes to the motors. No game played has vibrated through it: Crysis 2 "
                  + "Remastered, played with it on 2026-10-22, sent XInput no rumble."
                : "XInput gets nothing. A game that rumbles through the DualShock 4, as Mortal Kombat 11 does, "
                  + "needs nothing more."
        }
        switch choice(\.xinput).wrappedValue {
        case "rumble": return "The pad stays itself, and a game that rumbles through XInput, such as Beast of "
            + "Reincarnation, gets its rumble on the motors. For a game the Steam store lists for the DualSense."
        case "pad": return "The pad itself is the game's XInput controller, with Sony's ids so the game can show "
            + "PlayStation buttons; its rumble goes to the motors and the trigger effects below apply. For a game "
            + "that reads nothing else. Steam Input must be off for the game."
        default: return "XInput gets nothing of the pad."
        }
    }

    var body: some View {
        Toggle(isOn: asDualShock4 ? .constant(true) : flag(\.bluetoothAsCable)) {
            label("Bluetooth as a cable", \.bluetoothAsCable,
                  asDualShock4 ? "On while the pad is shown as a DualShock 4: the game sees a DualShock 4 on a cable."
                  : "A DualSense or DualSense Edge on Bluetooth is shown to games as the same pad on a cable, so they "
                  + "give it haptics and adaptive triggers as wired.")
        }
        .disabled(asDualShock4)
        Toggle(isOn: flag(\.fullMotorPower)) {
            label("Full motor power on the Edge", \.fullMotorPower,
                  asDualShock4 ? "Shown as a DualShock 4, the game cannot set the motor power: a DualShock 4 has "
                  + "none. This claims it at full for either pad."
                  : "Sony's library claims a standard DualSense's motor power at full and never an Edge's, which then "
                  + "keeps the reduction it stores; this claims it for the Edge too.")
        }
        // Shown as a DualShock 4 the game's file says edge=edge (PadOptions.lines), whatever this row holds.
        Toggle(isOn: asDualShock4 ? .constant(false) : flag(\.edgeAsDualSense)) {
            label("Show the Edge as a standard DualSense", \.edgeAsDualSense,
                  asDualShock4 ? "Off while the pad is shown as a DualShock 4: the game sees a DualShock 4, whichever "
                  + "pad it is."
                  : "For a game whose Sony library does not know the Edge. The game loses the Edge's back buttons and Fn.")
        }
        .disabled(asDualShock4)
        if perGame {
            Toggle(isOn: flag(\.asDualShock4)) {
                label("Show the pad as a DualShock 4", \.asDualShock4,
                      "For a game whose controller code knows only the PS4 pad, such as Mortal Kombat 11, which "
                      + "vibrates through it (played on 2026-10-22). The pad is shown to the game as a DualShock 4 "
                      + "on a cable, over Bluetooth too.")
            }
        }
        Picker(selection: xinputChoice) {
            Text("Off").tag("off")
            Text("Its rumble on the motors").tag("rumble")
            if !asDualShock4 { Text("The pad as an XInput controller").tag("pad") }
        } label: { label("XInput", asDualShock4 ? \PadOptions.ds4XInputRumble : \PadOptions.xinput, xinputAbout) }
        Toggle(isOn: flag(\.rumbleHaptics)) {
            label("Rumble on the haptic actuators", \.rumbleHaptics,
                  "Over Bluetooth, a game's motor rumble played on the haptic actuators, as PlayStation games play theirs: the heavy "
                  + "motor a deep 65 Hz on the left, the light one a finer 160 Hz on the right, at the haptics' "
                  + "strength over Bluetooth below. Only while the game plays no haptics of its own; on a cable the "
                  + "pad's own rumble plays. For an XInput game.")
        }
    }
}

private let padTriggerNames = ["off": "Off", "resist": "Resist", "weapon": "Weapon", "slope": "Slope",
                                "vibrate": "Vibrate", "rumble": "Rumble with the motor", "recoil": "Recoil with the motor"]

/// What each trigger effect does, what it suits, and its default strength. The
/// layouts are those of NotProton's controller bridge (engine/README.md, "XInput,
/// and the triggers").
private let padTriggerAbout: [String: (feel: String, suits: String, strength: String)] = [
    "off": ("Free, as the game leaves it.", "", ""),
    "resist": ("Even resistance from about a third of the way down to the end, like a stiff spring.",
               "A brake, or anything held down.", "4"),
    "weapon": ("Builds up from a third of the way and gives way with a click past the middle, like a gun's trigger.",
               "Shooting on R2, aiming on L2.", "7"),
    "slope": ("Light at first and firmer the further it goes.", "An accelerator, drawing a bow.", "8, at the end"),
    "vibrate": ("Buzzes at 25 Hz once pressed past the first fifth, whatever the game does.",
                "An engine, a tool.", "3"),
    "rumble": ("Vibrates at 40 Hz with the game's own rumble, and is still when the game is: R2 with the light "
               + "motor, L2 with the heavy one.", "An XInput game, to feel hits in the fingers.", "8, a cap"),
    "recoil": ("Stiffens with the game's own rumble and frees when it stops, so each shot or hit kicks back; "
               + "with whichever motor is the stronger.", "Shooting in an XInput game.", "8, a cap"),
]

/// The effects side by side, in a popover from the triggers' section.
private struct PadTriggerGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What each effect does").font(.headline)
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Effect"); Text("How it feels"); Text("Suits"); Text("Default strength")
                }
                .font(.caption).foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(PadTrigger.effects, id: \.self) { e in
                    GridRow {
                        Text(padTriggerNames[e] ?? e).fontWeight(.medium)
                        Text(padTriggerAbout[e]?.feel ?? "").frame(width: 300, alignment: .leading)
                        Text(padTriggerAbout[e]?.suits ?? "").frame(width: 200, alignment: .leading)
                        Text(padTriggerAbout[e]?.strength ?? "")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("While the other is pressed: a second effect that replaces a trigger's own while the other "
                 + "trigger is held, a weapon on R2 while L2 aims, say. The other counts as pressed from about a sixth "
                 + "of its travel.")
                .font(.caption).foregroundStyle(.secondary).frame(width: 640, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Strength runs from 1, light, to 8, the pad's strongest; Default is each effect's own. The pad "
                 + "keeps an effect until something else is written: the Wine modules release the triggers when the "
                 + "game's Wine stops, or when the next game starts.")
                .font(.caption).foregroundStyle(.secondary).frame(width: 640, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }
}

/// Trigger effects for a game that sets none of its own, an XInput title above
/// all: an effect and a strength per trigger. A game that sets an effect of its
/// own takes that trigger over.
struct PadTriggersSection<Footer: View>: View {
    let spec: (WritableKeyPath<PadOptions, String?>) -> Binding<String>
    let own: (PartialKeyPath<PadOptions>) -> Bool
    @ViewBuilder let footer: () -> Footer
    @State private var guide = false


    private func effect(_ key: WritableKeyPath<PadOptions, String?>) -> Binding<String> {
        let b = spec(key)
        return Binding(get: { PadTrigger(b.wrappedValue)?.effect ?? "off" },
                       set: { e in b.wrappedValue = PadTrigger(effect: e, strength: PadTrigger(b.wrappedValue)?.strength ?? 0).spec })
    }

    private func strength(_ key: WritableKeyPath<PadOptions, String?>) -> Binding<Int> {
        let b = spec(key)
        return Binding(get: { PadTrigger(b.wrappedValue)?.strength ?? 0 },
                       set: { n in b.wrappedValue = PadTrigger(effect: PadTrigger(b.wrappedValue)?.effect ?? "off", strength: n).spec })
    }

    /// One trigger's effect; a second one, for while the other is pressed, says
    /// "the same" where the first says off.
    private func row(_ label: String, _ key: WritableKeyPath<PadOptions, String?>, second: String? = nil) -> some View {
        GridRow {
            Text(label).foregroundStyle(second == nil ? .primary : .secondary)
            HStack(spacing: 6) {
                Picker("", selection: effect(key)) {
                    ForEach(PadTrigger.effects, id: \.self) { e in
                        Text(e == "off" && second != nil ? "The same as \(second!)" : padTriggerNames[e] ?? e).tag(e)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.accentColor)
                    .opacity(own(key) ? 1 : 0)
            }
            Picker("", selection: strength(key)) {
                Text("Default").tag(0)
                ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(effect(key).wrappedValue == "off")
        }
    }

    var body: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("Effect").foregroundStyle(.secondary)
                    Text("Strength").foregroundStyle(.secondary)
                }
                row("R2", \.triggerR2)
                row("  while L2 is pressed", \.triggerR2WithL2, second: "R2")
                row("L2", \.triggerL2)
                row("  while R2 is pressed", \.triggerL2WithR2, second: "L2")
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach([("R2", \PadOptions.triggerR2), ("L2", \PadOptions.triggerL2)], id: \.0) { label, key in
                        let chosen = effect(key).wrappedValue
                        Text("\(label), \((padTriggerNames[chosen] ?? chosen).lowercased()): \(padTriggerAbout[chosen]?.feel ?? "")")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("What Each Effect Does…") { guide = true }
                    .popover(isPresented: $guide, arrowEdge: .trailing) { PadTriggerGuide() }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trigger effects")
                Text("For a game that sets none of its own, such as an XInput title. A game that sets one takes "
                     + "that trigger over.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            footer()
        }
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

/// A game's cover, from Steam's own cache on this Mac (appcache/librarycache:
/// library_600x900.jpg, else header.jpg), made small once and kept.
@MainActor
final class PadCovers {
    static let shared = PadCovers()
    private var images: [String: NSImage] = [:]
    private var none: Set<String> = []

    func image(_ appid: String) -> NSImage? {
        if let image = images[appid] { return image }
        if none.contains(appid) { return nil }
        let dir = Paths.home.appendingPathComponent("Library/Application Support/Steam/appcache/librarycache/\(appid)")
        let names = ["library_600x900.jpg", "header.jpg"]
        guard let url = names.map({ dir.appendingPathComponent($0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 300,
              ] as CFDictionary)
        else { none.insert(appid); return nil }
        let image = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
        images[appid] = image
        return image
    }
}

/// A game's cover at a height, or a gamepad where Steam keeps none.
struct PadCover: View {
    let appid: String
    let height: CGFloat

    var body: some View {
        Group {
            if let image = PadCovers.shared.image(appid) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "gamecontroller").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: height * 2 / 3, height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 15))
    }
}

/// A thirty-second try of the haptics or the triggers on the pad connected now,
/// with the settings shown.
struct PadTryRow: View {
    @ObservedObject var tester: PadTester
    let kind: PadTester.Kind
    let options: PadOptions

    var body: some View {
        HStack(spacing: 10) {
            Text(tester.running == kind || (tester.running == nil && !tester.status.isEmpty) ? tester.status
                 : kind == .haptics ? "Plays a rumble soft, medium and strong, then hits left and right, at the strength above for the pad connected and how it is connected."
                 : "Sets the effects above on the pad connected; rumble and recoil follow a stand-in for a game's rumble.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(tester.running == kind ? "Stop" : "Try for \(PadTester.seconds) Seconds") {
                if tester.running == kind { tester.stop() } else { tester.start(kind, with: options) }
            }
            .help("Close any game first: the try writes to the pad as the Wine modules do.")
        }
        .padding(.top, 2)
    }
}

/// Every game's options, in a sheet of their own.
struct PadGlobalSheet: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSize) private var windowSize

    private func flag(_ key: WritableKeyPath<PadOptions, Bool?>) -> Binding<Bool> {
        Binding(get: { model.pad.defaults[keyPath: key] ?? false }, set: { on in model.setPad { $0.defaults[keyPath: key] = on } })
    }
    private func text(_ key: WritableKeyPath<PadOptions, String?>) -> Binding<String> {
        Binding(get: { model.pad.defaults[keyPath: key] ?? "off" }, set: { v in model.setPad { $0.defaults[keyPath: key] = v } })
    }
    private func gain(_ key: WritableKeyPath<PadOptions, Double?>) -> Binding<Double> {
        Binding(get: { model.pad.defaults[keyPath: key] ?? 1 }, set: { v in model.setPad { $0.defaults[keyPath: key] = v } })
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    PadOptionRows(flag: flag, choice: text, own: { _ in false })
                    Toggle("Diagnostics in the modules' log", isOn: Binding(
                        get: { model.pad.diagnostics }, set: { on in model.setPad { $0.diagnostics = on } }))
                        .help("What a game writes to the pad and reads from it, and a level meter of its haptics, in "
                              + "/tmp/macgamefix-\(getuid())/pad.log.")
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Every game")
                        Text("The Wine modules read these when a game starts; in CrossOver, when Steam or the game "
                             + "opens the bottle, so make a change before you open it there, or quit and open it "
                             + "again. The haptics' strength is read each time a game starts its haptics. A game's "
                             + "own settings win, and so do its suggested ones.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PadHapticsSection(gain: gain, own: { _ in false }) {
                    PadTryRow(tester: model.padTester, kind: .haptics, options: model.pad.defaults)
                }
                PadTriggersSection(spec: text, own: { _ in false }) {
                    VStack(alignment: .leading, spacing: 6) {
                        PadTryRow(tester: model.padTester, kind: .triggers, options: model.pad.defaults)
                        Text("Measured with NOTPROTON_RAW_CONTROLLERS=1 in the game's launch options and Steam Input off.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .padSheetSize(in: windowSize)
        .onDisappear { model.padTester.stop() }
    }
}

/// One game's own options, in the same form as every game's. A value set back
/// to what the game would get anyway is no longer its own.
struct PadGameSheet: View {
    let game: InstalledGame
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSize) private var windowSize

    private var preset: PadPreset? { model.padPresets[game.appid] }
    private var own: PadOptions { model.pad.games[game.appid]?.options ?? PadOptions() }
    /// What the game gets without options of its own.
    private var base: PadOptions { model.pad.base(game.appid, presets: model.padPresets) }
    private var effective: PadOptions { own.over(base) }

    private func flag(_ key: WritableKeyPath<PadOptions, Bool?>) -> Binding<Bool> {
        Binding(get: { effective[keyPath: key] ?? false },
                set: { v in model.setPadGame(game) { $0[keyPath: key] = v == (base[keyPath: key] ?? false) ? nil : v } })
    }

    private func gain(_ key: WritableKeyPath<PadOptions, Double?>) -> Binding<Double> {
        Binding(get: { effective[keyPath: key] ?? 1 },
                set: { v in model.setPadGame(game) { $0[keyPath: key] = v == (base[keyPath: key] ?? 1) ? nil : v } })
    }

    private func trigger(_ key: WritableKeyPath<PadOptions, String?>) -> Binding<String> {
        Binding(get: { effective[keyPath: key] ?? "off" },
                set: { v in model.setPadGame(game) { $0[keyPath: key] = v == (base[keyPath: key] ?? "off") ? nil : v } })
    }

    private func isOwn(_ key: PartialKeyPath<PadOptions>) -> Bool {
        switch own[keyPath: key] {
        case let v as Bool?: return v != nil
        case let v as Double?: return v != nil
        case let v as String?: return v != nil
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    PadOptionRows(flag: flag, choice: trigger, own: isOwn, perGame: true)
                } header: {
                    HStack(alignment: .center, spacing: 14) {
                        PadCover(appid: game.appid, height: 96)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.name).font(.title3)
                            Text("In blue, or marked with a dot, what is this game's own; the rest follows "
                                 + (preset == nil ? "every game's." : "the suggested settings, then every game's."))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("They apply under NotProton, from the game's next start. A CrossOver bottle does not "
                                 + "tell the modules which game runs, so there every game's settings apply.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 4)
                }
                PadHapticsSection(gain: gain, own: isOwn) {
                    PadTryRow(tester: model.padTester, kind: .haptics, options: effective)
                }
                PadTriggersSection(spec: trigger, own: isOwn) {
                    PadTryRow(tester: model.padTester, kind: .triggers, options: effective)
                }
                Section("About this game") {
                    HStack {
                        Toggle("Diagnose this game", isOn: Binding(get: { model.pad.games[game.appid]?.diagnose == true },
                                                                   set: { model.setPadDiagnose(game, $0) }))
                            .help("The Wine modules log what this game writes to the pad, the haptics' levels and delays, "
                                  + "for this game alone, from its next start.")
                        Spacer()
                        Button("It Vibrates…") { model.padVibrates(game) }
                            .help("Saves this game's report and opens a new issue on GitHub that says it vibrates, with "
                                  + "the controller, the connection and what the pad was shown to the game as, as the "
                                  + "Wine modules saw them, for the list of games played for vibration.")
                        Button("Share These Settings…") { model.padShare(game) }
                            .help("Saves this game's report and opens a new issue on GitHub with these settings in it, "
                                  + "to attach it to.")
                        Button("Make a Report…") { model.padReport(game) }
                            .help("Saves this game's report and opens a new issue on GitHub to attach it to.")
                    }
                    Text("To report a problem: turn on Diagnose, play the moment that goes wrong, close the game, then "
                         + "make a report and attach it to the issue that opens. The report names this game alone, and "
                         + "your home folder is written ~.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("If these settings feel right, share them the same way: shared settings that a report backs "
                         + "become this game's suggested ones for everyone.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("If it vibrates, say so the same way, once for each controller and connection you played: "
                         + "a game's report that it vibrates adds it to the list of games played for vibration.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        if let preset {
                            Text("Suggested: \(preset.options.summary.joined(separator: ", ")). \(preset.measured)")
                        }
                        switch model.pad.games[game.appid]?.dualSense {
                        case true?: Text("The Steam store lists it as supporting the DualSense.")
                        case false?: Text("The Steam store does not list it as supporting the DualSense, so it gets the pad as an XInput controller.")
                        case nil: Text("Not asked of the Steam store yet.")
                        }
                        let seen = (model.pad.games[game.appid]?.seen.keys.sorted() ?? []).map(\.label)
                        if !seen.isEmpty { Text("Seen: " + seen.joined(separator: ", ") + ".") }
                        Text("Steam app \(game.appid)")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padSheetSize(in: windowSize)
        .onDisappear { model.padTester.stop() }
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
                Toggle("Game Mode for CrossOver's games", isOn: Binding(get: { model.settings.gameMode },
                                                                        set: { model.setGameMode($0) }))
                    .help("macOS turns Game Mode on for a game in full screen whose app says it is a game. A game in "
                          + "CrossOver runs from a copy of Wine that does not say so; with this on, it runs from one "
                          + "that does, kept in MacGameFix's folder. CrossOver itself is not changed, and turning "
                          + "this off takes it all away.")
                if model.settings.gameMode && !model.gameModeLine.isEmpty {
                    Text(model.gameModeLine).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Game Mode")
            } footer: {
                Text("Play in full screen: the green button, or Control-Command-F. Game Mode also doubles what a "
                     + "wireless controller's Bluetooth link carries, which a DualSense's haptics need.")
                    .font(.caption).foregroundStyle(.secondary)
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
            // Room for the Games table's five columns; a window the user sized keeps its size.
            .defaultSize(width: 1080, height: 760)
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
            // What the Game Feel tab does on a change: the log read, the store
            // asked about each game, pad.json kept, pad.conf and pad.d/ written.
            wait {
                var store = PadStore.load()
                let installed = SteamGames.installed()
                store.absorbLog(names: { Dictionary(installed.map { ($0.appid, $0.name) }, uniquingKeysWith: { a, _ in a }) })
                _ = await store.learnStore(installed)
                store.save()
                store.writeConfig(presets: PadPresets.load())
                PadExes.keep()
                print("pad.conf and \((try? FileManager.default.contentsOfDirectory(atPath: PadStore.perGame.path).count) ?? 0) per-game file(s) written")
                return 0
            }
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
                                 : (hit.game.inPrefix ? "DLLs into the " : "keys into the ")
                                   + hit.chosen.map(\.label).joined(separator: " and the "))
                }
                print(parts.joined(separator: " | "))
            }
            exit(0)
        }
        if args.contains("--game-mode-keep") || args.contains("--game-mode-remove") || args.contains("--game-mode-report") {
            // Game Mode for CrossOver's games (GameMode.swift): put in place, taken away, or reported.
            if args.contains("--game-mode-remove") { GameMode.remove(); exit(0) }
            if args.contains("--game-mode-keep") { GameMode.keep().forEach { print($0) } }
            for loader in GameMode.loaders() {
                let dir = GameMode.winetemp(for: loader.path)
                let macos = GameMode.bundle(for: loader).appendingPathComponent("Contents/MacOS").path + "/"
                let links = ((try? FileManager.default.contentsOfDirectory(atPath: dir?.path ?? "")) ?? [])
                    .filter { (try? FileManager.default.destinationOfSymbolicLink(atPath: dir!.appendingPathComponent($0).path))?
                        .hasPrefix(macos) == true }
                print("\(loader.target.name) | \(loader.arch) | \(dir?.lastPathComponent ?? "no folder") | \(links.count) linked")
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
        if let i = args.firstIndex(of: "--pad-game-report"), i + 2 < args.count {
            // A game's report, as Make a Report writes it, for the tests.
            let (dir, _) = Catalog.active(.modules)
            let appid = args[i + 1], path = args[i + 2]
            wait {
                var engines: [(name: String, build: String, state: String)] = []
                for t in Engine.targets() { engines.append((t.name, t.build, await Engine.status(t, catalog: dir).label)) }
                let store = PadStore.load()
                let name = store.games[appid]?.name ?? SteamGames.installed().first { $0.appid == appid }?.name ?? appid
                try? store.report(appid: appid, name: name, presets: PadPresets.load(), engines: engines)
                    .write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
                return 0
            }
        }
        if let i = args.firstIndex(of: "--probe-report"), i + 2 < args.count {
            // The Report tab's report for a game, for the tests: --probe-report <app id> <path> [symptom].
            let appid = args[i + 1], path = args[i + 2]
            guard let game = ProbeGames.all().first(where: { $0.appid == appid }) else { print("no such game: \(appid)"); exit(1) }
            let symptom = i + 3 < args.count ? ProbeSymptom.allCases.first { "\($0)" == args[i + 3] } ?? .other : .other
            let fix = Catalog.games(in: Catalog.active().dir).first { $0.isRooted(at: game.folder) }?.name
            let log = (try? String(contentsOf: PadStore.log, encoding: .utf8)) ?? ""
            let text = Probe.report(game, symptom: symptom.rawValue, findings: Probe.look(game), fix: fix, engines: [],
                                    padLines: log.split(separator: "\n").map(String.init).filter { $0.contains(" game=\(appid) ") })
            try? text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            exit(0)
        }
        if args.contains("--probe-games") {
            // The Report tab's games, for the tests.
            for game in ProbeGames.all() { print("\(game.appid) | \(game.name) | \(game.places.joined(separator: ", "))") }
            exit(0)
        }
        if let appid = value("--pad-share-url") {
            // The settings form Share These Settings opens for a game, for the tests.
            let store = PadStore.load()
            let name = store.games[appid]?.name ?? SteamGames.installed().first { $0.appid == appid }?.name ?? appid
            print(store.shareIssue(appid: appid, name: name, presets: PadPresets.load())?.absoluteString ?? "")
            exit(0)
        }
        if let appid = value("--pad-vibrates-url") {
            // The form It Vibrates opens for a game, for the tests.
            let store = PadStore.load()
            let name = store.games[appid]?.name ?? SteamGames.installed().first { $0.appid == appid }?.name ?? appid
            let library = ProbeGames.all().first { $0.appid == appid }.flatMap { Probe.look($0).padLibrary }
            let log = (try? String(contentsOf: PadStore.log, encoding: .utf8)) ?? ""
            print(store.vibratesIssue(appid: appid, name: name, presets: PadPresets.load(), library: library,
                                      log: log)?.absoluteString ?? "")
            exit(0)
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
