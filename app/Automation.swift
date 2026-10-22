// MacGameFix in the background: an agent that keeps the fixes the user marked
// applied, a catalog of fixes that updates itself from the releases, and a
// report the user can send when a fix does not take.
//
// - The agent (a LaunchAgent running this binary with --agent, which lives in
//   the menu bar: MenuBar.swift) looks at every marked game every two minutes. When Steam has changed the game since the last
//   look (a new build, or a verify that put the original files back), or a new
//   catalog arrived, it asks the installer, and installs again when the fix is
//   gone -- only with the game closed and Steam done writing it.
// - The catalog is the installers and every file they name. A release carries
//   catalog.json (signed, with catalog.json.sig) and catalog.zip; the agent
//   takes a newer one only when the signature verifies with the key built into
//   this app and every file matches its hash, and switches to it at once.
// - Nothing is sent anywhere by itself. A failure becomes a notification whose
//   button opens GitHub's new-issue page, filled in and scrubbed of the user's
//   name, home folder and serial number, for the user to read and send.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CryptoKit
import Foundation
import IOKit
import UserNotifications

// MARK: - Settings the app writes and the agent reads

struct KeptGame: Codable, Hashable {
    var name: String
    var folder: String
    /// The prefixes chosen for a title that writes registry keys.
    var prefixes: [String] = []
    var key: String { gameKey(URL(fileURLWithPath: folder), name) }

    init(name: String, folder: String, prefixes: [String] = []) {
        self.name = name; self.folder = folder; self.prefixes = prefixes
    }

    private enum CodingKeys: String, CodingKey { case name, folder, prefixes, prefix }

    // Before 1.5.1 a game had one prefix, written as "prefix".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        folder = try c.decode(String.self, forKey: .folder)
        prefixes = try c.decodeIfPresent([String].self, forKey: .prefixes)
            ?? (try c.decodeIfPresent(String.self, forKey: .prefix)).map { [$0] } ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(folder, forKey: .folder)
        if !prefixes.isEmpty { try c.encode(prefixes, forKey: .prefixes) }
    }
}

struct AutoSettings: Codable {
    var kept: [KeptGame] = []
    /// Look for newer catalogs of fixes in the releases.
    var updates = true
    /// With `updates`, ask before installing a newer catalog instead of taking it.
    var askFirst = false
    /// The same two for the Wine modules, which update on their own (Engine.swift).
    var modulesUpdates = true
    var modulesAskFirst = false
    /// The CrossOver folders the user put the Wine modules into, which the agent
    /// keeps them in, and those the user took them out of, which it leaves alone.
    var modulesKept: [String] = []
    var modulesDeclined: [String] = []
    /// On automatic, also put them into a runner NotProton adds for a new CrossOver build.
    var modulesNewBuilds = true
    /// When the user last opened the window: what the agent did before it has been seen.
    var seen = Date.distantPast
    /// The menu bar shows a connected controller's battery.
    var padBattery = true
    /// What stands beside it: "raccoon" (the raccoon and a gamepad), "gamepad", or "none".
    var batteryIcon = "raccoon"
    /// CrossOver's games run from a bundle that says it is a game (GameMode.swift).
    var gameMode = false

    init() {}

    // Fields a later version added are absent from an older file: read what is there.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kept = try c.decodeIfPresent([KeptGame].self, forKey: .kept) ?? []
        updates = try c.decodeIfPresent(Bool.self, forKey: .updates) ?? true
        askFirst = try c.decodeIfPresent(Bool.self, forKey: .askFirst) ?? false
        modulesUpdates = try c.decodeIfPresent(Bool.self, forKey: .modulesUpdates) ?? true
        modulesAskFirst = try c.decodeIfPresent(Bool.self, forKey: .modulesAskFirst) ?? false
        modulesKept = try c.decodeIfPresent([String].self, forKey: .modulesKept) ?? []
        modulesDeclined = try c.decodeIfPresent([String].self, forKey: .modulesDeclined) ?? []
        modulesNewBuilds = try c.decodeIfPresent(Bool.self, forKey: .modulesNewBuilds) ?? true
        seen = try c.decodeIfPresent(Date.self, forKey: .seen) ?? .distantPast
        padBattery = try c.decodeIfPresent(Bool.self, forKey: .padBattery) ?? true
        batteryIcon = try c.decodeIfPresent(String.self, forKey: .batteryIcon) ?? "raccoon"
        gameMode = try c.decodeIfPresent(Bool.self, forKey: .gameMode) ?? false
    }

    static func load() -> AutoSettings {
        guard let data = try? Data(contentsOf: Paths.settings),
              let s = try? JSONDecoder().decode(AutoSettings.self, from: data) else { return AutoSettings() }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Paths.settings, options: .atomic) }
    }
}

// MARK: - What the agent remembers

struct AgentEvent: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var game: String
    var message: String
    var failed: Bool
    /// GitHub's new-issue page, filled in, for a failure.
    var report: String?

    /// Something the user would want to look at: new fixes, or a failure.
    var asksForALook: Bool { failed || game.isEmpty }
}

struct GameMemory: Codable {
    var build = ""
    var catalog = 0
    var checked = Date.distantPast
    var state = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        build = try c.decodeIfPresent(String.self, forKey: .build) ?? ""
        catalog = try c.decodeIfPresent(Int.self, forKey: .catalog) ?? 0
        checked = try c.decodeIfPresent(Date.self, forKey: .checked) ?? .distantPast
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
    }
}

struct AgentState: Codable {
    var games: [String: GameMemory] = [:]
    var events: [AgentEvent] = []
    var lastUpdateCheck = Date.distantPast
    var lastUpdate = ""
    /// A newer, verified catalog the user was asked about and has not installed; 0 for none.
    var available = 0
    /// The same three for the Wine modules' catalog.
    var lastModulesCheck = Date.distantPast
    var lastModulesUpdate = ""
    var availableModules = 0
    /// The CrossOver folders the agent has seen, to tell a new NotProton runner
    /// from one the user simply never chose; and what it last said of each.
    var engineSeen: [String]?
    var engineNoted: [String: String] = [:]

    init() {}

    // Fields a later version added are absent from an older file: read what is there.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        games = try c.decodeIfPresent([String: GameMemory].self, forKey: .games) ?? [:]
        events = try c.decodeIfPresent([AgentEvent].self, forKey: .events) ?? []
        lastUpdateCheck = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck) ?? .distantPast
        lastUpdate = try c.decodeIfPresent(String.self, forKey: .lastUpdate) ?? ""
        available = try c.decodeIfPresent(Int.self, forKey: .available) ?? 0
        lastModulesCheck = try c.decodeIfPresent(Date.self, forKey: .lastModulesCheck) ?? .distantPast
        lastModulesUpdate = try c.decodeIfPresent(String.self, forKey: .lastModulesUpdate) ?? ""
        availableModules = try c.decodeIfPresent(Int.self, forKey: .availableModules) ?? 0
        engineSeen = try c.decodeIfPresent([String].self, forKey: .engineSeen)
        engineNoted = try c.decodeIfPresent([String: String].self, forKey: .engineNoted) ?? [:]
    }

    /// The waiting catalog, while it is still newer than the one in use.
    var waiting: Int? {
        available > (Catalog.active().manifest?.version ?? 0) ? available : nil
    }
    var waitingModules: Int? {
        availableModules > (Catalog.active(.modules).manifest?.version ?? 0) ? availableModules : nil
    }

    /// Where each kind's check is remembered.
    static func checked(_ kind: CatalogKind) -> WritableKeyPath<AgentState, Date> {
        kind == .fixes ? \.lastUpdateCheck : \.lastModulesCheck
    }
    static func line(_ kind: CatalogKind) -> WritableKeyPath<AgentState, String> {
        kind == .fixes ? \.lastUpdate : \.lastModulesUpdate
    }
    static func offered(_ kind: CatalogKind) -> WritableKeyPath<AgentState, Int> {
        kind == .fixes ? \.available : \.availableModules
    }

    static func load() -> AgentState {
        guard let data = try? Data(contentsOf: Paths.state),
              let s = try? JSONDecoder().decode(AgentState.self, from: data) else { return AgentState() }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Paths.state, options: .atomic) }
    }

    /// Whether something the agent did asks for a look and came after `seen`:
    /// the menu bar's dot.
    func news(since seen: Date) -> Bool { events.contains { $0.date > seen && $0.asksForALook } }

    mutating func record(_ event: AgentEvent) {
        events.append(event)
        if events.count > 50 { events.removeFirst(events.count - 50) }
    }
}

// MARK: - The agent

enum Agent {
    /// Looks again at a game that has not changed after this long anyway.
    static let recheck: TimeInterval = 6 * 3600
    static let updateEvery: TimeInterval = 24 * 3600

    /// One kind of catalog, when it is time or when asked: asked first, the
    /// release's catalog is verified and offered once and nothing is installed;
    /// otherwise it is taken. `force` is the user asking, which installs.
    private static func updateCatalog(_ kind: CatalogKind, now: Date, force: Bool, on: Bool, ask: Bool,
                                      state: inout AgentState, events: inout [AgentEvent]) async {
        guard force || (on && now.timeIntervalSince(state[keyPath: AgentState.checked(kind)]) > updateEvery)
        else { return }
        state[keyPath: AgentState.checked(kind)] = now
        let what = kind == .fixes ? "New fixes" : "New Wine modules"
        if ask && !force {
            do {
                if let version = try await Updater.check(kind) {
                    if state[keyPath: AgentState.offered(kind)] != version {
                        events.append(AgentEvent(date: now, game: "",
                                                 message: "\(what) are ready (catalog \(version)). Install them from the "
                                                     + "menu bar or MacGameFix's Settings.", failed: false))
                    }
                    state[keyPath: AgentState.offered(kind)] = version
                    state[keyPath: AgentState.line(kind)] = "\(what) are ready: catalog \(version)."
                } else {
                    state[keyPath: AgentState.offered(kind)] = 0
                    state[keyPath: AgentState.line(kind)] =
                        "The \(kind.noun) are up to date (catalog \(Catalog.active(kind).manifest?.version ?? 0))."
                }
            } catch {
                state[keyPath: AgentState.line(kind)] = "Update check failed: \(error.localizedDescription)"
            }
            return
        }
        let before = Set(Catalog.games(in: Catalog.active().dir).map(\.name))
        do {
            let line = try await Updater.update(kind)
            state[keyPath: AgentState.offered(kind)] = 0
            state[keyPath: AgentState.line(kind)] = line
            let added = kind == .fixes
                ? Catalog.games(in: Catalog.active().dir).map(\.name).filter { !before.contains($0) } : []
            if !added.isEmpty {
                events.append(AgentEvent(date: now, game: "", message: "New fixes: " + added.joined(separator: ", "),
                                         failed: false))
            } else if line.hasPrefix(what) {
                events.append(AgentEvent(date: now, game: "",
                                         message: kind == .fixes ? "The fixes were updated." : "The Wine modules were updated.",
                                         failed: false))
            }
        } catch {
            state[keyPath: AgentState.line(kind)] = "Update check failed: \(error.localizedDescription)"
        }
    }

    /// One look at every marked game, and at the releases when it is time.
    /// `everything` looks at each marked game even when nothing changed it, and
    /// `updateNow` asks the releases at once; the menu's two commands.
    /// Returns what it did, for the log and the tests.
    static func pass(now: Date = Date(), notify: Bool, everything: Bool = false,
                     updateNow: Bool = false, modulesNow: Bool = false) async -> [AgentEvent] {
        let settings = AutoSettings.load()
        var state = AgentState.load()
        var events: [AgentEvent] = []

        await updateCatalog(.fixes, now: now, force: updateNow, on: settings.updates, ask: settings.askFirst,
                            state: &state, events: &events)
        await updateCatalog(.modules, now: now, force: modulesNow, on: settings.modulesUpdates,
                            ask: settings.modulesAskFirst, state: &state, events: &events)
        var kept = settings
        events += await Engine.keep(&kept, state: &state, now: now)
        if kept.modulesKept != settings.modulesKept { kept.save() }
        // A game installed since, a CrossOver updated, or a temporary folder macOS emptied.
        if settings.gameMode { GameMode.keep().forEach { print($0) } }
        // What the Wine modules saw each game do, kept before a restart empties /tmp.
        if PadStore.exists {
            // Which game each exe is, for the modules in a CrossOver bottle.
            PadExes.keep()
            var pad = PadStore.load()
            let installed = SteamGames.installed()
            if pad.absorbLog(names: { Dictionary(installed.map { ($0.appid, $0.name) },
                                                 uniquingKeysWith: { a, _ in a }) }) { pad.save() }
            // What the store says of a newly installed game decides its XInput by default.
            if await pad.learnStore(installed) {
                pad.save()
                pad.writeConfig(presets: PadPresets.load())
            }
        }

        let (catalogDir, manifest) = Catalog.active()
        let games = Catalog.games(in: catalogDir)
        for kept in settings.kept {
            guard let game = games.first(where: { $0.name == kept.name }) else { continue }
            let folder = URL(fileURLWithPath: kept.folder)
            guard game.isRooted(at: folder) else { continue }
            var memory = state.games[kept.key] ?? GameMemory()
            let steam = SteamApp.of(folder: folder)
            if let steam, !steam.settled { continue } // Steam is still writing the game.
            let build = steam?.buildid ?? ""
            let catalog = manifest?.version ?? 0
            let changed = memory.build != build || memory.catalog != catalog
            // The fix goes back into the game's folder whatever runs the game:
            // where it runs is the user's to check, and the window says what
            // each fix requires.
            guard changed || everything || now.timeIntervalSince(memory.checked) > recheck else { continue }
            if isRunning(game) { continue } // Looked at again once it is closed.

            let look = game.needsPrefix
                ? Fixer.Look(state: await Fixer.status(game, folder: folder, prefixes: kept.prefixes, catalog: catalogDir))
                : await Fixer.look(game, folder: folder, prefix: nil, catalog: catalogDir)
            let word = look.state
            // A fix for a macOS game's app that its installer will not install
            // here: an executable changed outside MacGameFix, patched or not, or
            // a Mac the fix is not for. Running it would only fail again.
            let refused = word == .blocked || (word == .half && game.inApp)
            var event: AgentEvent?
            if word == .installed {
                if memory.state != "installed" && !memory.state.isEmpty {
                    event = AgentEvent(date: now, game: game.name, message: "The fix is in place.", failed: false)
                }
            } else if word == .noCarrier {
                event = failure(game, now, "The installer found nothing in the game folder for the fix to ride on.",
                                output: [], catalog: catalog)
            } else if refused {
                // Not a failure of the fix, and nothing to report: the user is
                // told the installer's reason once a build, and the window
                // shows it beside the game.
                if memory.state != "blocked" || memory.build != build {
                    event = AgentEvent(date: now, game: game.name,
                                       message: look.note ?? "The installer cannot install the fix here.", failed: false)
                }
            } else if word == .noRecipe {
                // A fix made for each build of the game, and none for this one
                // in the catalog yet: nothing to run and nothing to report, said
                // once a build. A newer catalog makes `changed` true, and the
                // look after it installs.
                if memory.state != "norecipe" || memory.build != build {
                    event = AgentEvent(date: now, game: game.name,
                                       message: "No recipe for this build yet; MacGameFix puts it back when one arrives.",
                                       failed: false)
                }
            } else {
                let out = Collected()
                let code = await Fixer.run(game, folder: folder, prefixes: kept.prefixes, catalog: catalogDir, []) {
                    out.add($0)
                }
                let after = await Fixer.status(game, folder: folder, prefixes: kept.prefixes, catalog: catalogDir)
                if code == 0 && after == .installed {
                    let message = word == .outdated
                        ? "The fix is updated to the newer build."
                        : memory.state == "norecipe"
                            ? "A recipe for this build arrived; the fix is in place."
                            : changed && !memory.build.isEmpty && memory.build != build
                                ? "Steam changed the game; the fix is back in place."
                                : "The fix was missing and is back in place."
                    event = AgentEvent(date: now, game: game.name, message: message, failed: false)
                } else {
                    event = failure(game, now,
                                    code != 0 ? "The installer failed (status \(code))." : "The fix did not take.",
                                    output: out.all, catalog: catalog)
                }
                memory.state = after == .installed ? "installed" : "failed"
            }
            if word == .installed { memory.state = "installed" }
            if word == .noCarrier { memory.state = "failed" }
            if word == .noRecipe { memory.state = "norecipe" }
            if refused { memory.state = "blocked" }
            memory.build = build
            memory.catalog = catalog
            memory.checked = now
            state.games[kept.key] = memory
            if let event { events.append(event) }
        }
        for e in events { state.record(e) }
        state.save()
        if notify { for e in events { Notifier.post(e) } }
        return events
    }

    static func failure(_ game: Game, _ now: Date, _ problem: String, output: [String], catalog: Int) -> AgentEvent {
        AgentEvent(date: now, game: game.name, message: problem, failed: true,
                   report: Report.url(game: game.name, problem: problem, output: output, catalog: catalog).absoluteString)
    }

    /// The LaunchAgent's process: a menu bar item, and a pass every two
    /// minutes, for as long as it runs. Quitting it from the menu ends it until
    /// the next login, or until the window opens again.
    @MainActor
    static func runForever() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MenuBarAgent()
        app.delegate = delegate
        app.run()
        exit(0)
    }
}

// MARK: - Signed catalogs

enum Updater {
    /// The key catalogs are signed with (Ed25519). Its private half stays with
    /// whoever publishes the releases; build-app.sh signs with it.
    static let publicKey = "Sbhi1/RDnZXimFuFHqskaAkEABp+Uuigo/uIscg19SU="
    static let releases = URL(string: "https://api.github.com/repos/MathiasKowoll/MacGameFix/releases/latest")!

    enum Failure: LocalizedError {
        case missing(String), signature, hash(String), unsafe(String), app(String)
        var errorDescription: String? {
            switch self {
            case .missing(let s): return "the release has no \(s)"
            case .signature: return "catalog.json is not signed with MacGameFix's key"
            case .hash(let s): return "\(s) does not match the signed catalog"
            case .unsafe(let s): return "the catalog names a file it may not: \(s)"
            case .app(let v): return "the new fixes need MacGameFix \(v) or later"
            }
        }
    }

    /// Where the agent looks, and the key it trusts: the latest release and
    /// Updater.publicKey, unless the tests name a folder and a test key.
    static var source: URL? {
        ProcessInfo.processInfo.environment["MACGAMEFIX_CATALOG_SOURCE"].map { URL(fileURLWithPath: $0) }
    }
    static var key: String { ProcessInfo.processInfo.environment["MACGAMEFIX_CATALOG_PUBKEY"] ?? publicKey }

    /// The release's manifest of one kind, its signature checked, and where its zip is.
    private static func signedManifest(_ kind: CatalogKind, _ source: URL?, key: String) async throws
        -> (manifest: CatalogManifest, data: Data, zip: URL) {
        let (manifestURL, signatureURL, zipURL) = try await assets(kind, source)
        let manifestData = try await fetch(manifestURL)
        let signature = try await fetch(signatureURL)
        guard let raw = Data(base64Encoded: key),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              publicKey.isValidSignature(Data(base64Encoded: String(decoding: signature, as: UTF8.self)
                  .trimmingCharacters(in: .whitespacesAndNewlines)) ?? signature, for: manifestData)
        else { throw Failure.signature }
        return (try JSONDecoder().decode(CatalogManifest.self, from: manifestData), manifestData, zipURL)
    }

    /// The version of a newer catalog this app can take, its signature checked
    /// but nothing downloaded or installed; nil when the fixes are up to date.
    static func check(_ kind: CatalogKind = .fixes, from source: URL? = Updater.source,
                      publicKey key: String = Updater.key) async throws -> Int? {
        let (manifest, _, _) = try await signedManifest(kind, source, key: key)
        guard manifest.version > (Catalog.active(kind).manifest?.version ?? 0) else { return nil }
        guard !Catalog.versionLess(Catalog.appVersion, manifest.minimumApp) else {
            throw Failure.app(manifest.minimumApp)
        }
        return manifest.version
    }

    /// Takes a newer catalog of one kind from the latest release, or from
    /// `source`: a folder holding catalog.json, catalog.json.sig and catalog.zip
    /// (modules.json and so on for the Wine modules), for the tests. Returns a
    /// line saying what happened.
    @discardableResult
    static func update(_ kind: CatalogKind = .fixes, from source: URL? = Updater.source,
                       publicKey key: String = Updater.key) async throws -> String {
        let (manifest, manifestData, zipURL) = try await signedManifest(kind, source, key: key)
        let active = Catalog.active(kind).manifest?.version ?? 0
        guard manifest.version > active else { return "The \(kind.noun) are up to date (catalog \(active))." }
        guard !Catalog.versionLess(Catalog.appVersion, manifest.minimumApp) else {
            throw Failure.app(manifest.minimumApp)
        }
        let zip = try await fetch(zipURL)
        guard hex(SHA256.hash(data: zip)) == manifest.zipSHA256 else { throw Failure.hash("catalog.zip") }

        let fm = FileManager.default
        let store = kind.store
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        let staging = store.appendingPathComponent(".incoming-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let zipFile = staging.appendingPathComponent("catalog.zip")
        try zip.write(to: zipFile)
        let files = staging.appendingPathComponent("files")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipFile.path, files.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Failure.hash("catalog.zip") }

        // Exactly the files the signed catalog names, flat, each with its hash.
        let present = Set((try? fm.contentsOfDirectory(atPath: files.path)) ?? [])
        for name in present where manifest.files[name] == nil { throw Failure.unsafe(name) }
        for (name, sum) in manifest.files {
            guard !name.contains("/"), !name.hasPrefix("."), name != "\(kind.stem).json" else { throw Failure.unsafe(name) }
            guard let data = fm.contents(atPath: files.appendingPathComponent(name).path),
                  hex(SHA256.hash(data: data)) == sum else { throw Failure.hash(name) }
            if name.hasPrefix("install-") && name.hasSuffix(".sh") {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: files.appendingPathComponent(name).path)
            }
        }
        try manifestData.write(to: files.appendingPathComponent("\(kind.stem).json"))

        // In place under its version, then the switch, in one rename.
        let target = store.appendingPathComponent(String(manifest.version))
        try? fm.removeItem(at: target)
        try fm.moveItem(at: files, to: target)
        let link = store.appendingPathComponent(".current-\(UUID().uuidString)")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: String(manifest.version))
        guard rename(link.path, store.appendingPathComponent("current").path) == 0 else {
            try? fm.removeItem(at: link)
            throw Failure.missing("a place to put the catalog")
        }
        // Keep the one before, for a look back; drop the rest.
        let versions = ((try? fm.contentsOfDirectory(atPath: store.path)) ?? [])
            .compactMap(Int.init).sorted(by: >)
        for old in versions.dropFirst(2) {
            try? fm.removeItem(at: store.appendingPathComponent(String(old)))
        }
        return kind == .fixes ? "New fixes installed: catalog \(manifest.version)."
            : "New Wine modules installed: catalog \(manifest.version)."
    }

    private static func assets(_ kind: CatalogKind, _ source: URL?) async throws -> (URL, URL, URL) {
        let stem = kind.stem
        if let source {
            return (source.appendingPathComponent("\(stem).json"), source.appendingPathComponent("\(stem).json.sig"),
                    source.appendingPathComponent("\(stem).zip"))
        }
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable { let assets: [Asset] }
        let release = try JSONDecoder().decode(Release.self, from: try await fetch(releases))
        func named(_ n: String) throws -> URL {
            guard let a = release.assets.first(where: { $0.name == n }) else { throw Failure.missing(n) }
            return a.browser_download_url
        }
        return (try named("\(stem).json"), try named("\(stem).json.sig"), try named("\(stem).zip"))
    }

    private static func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        var request = URLRequest(url: url)
        request.setValue("MacGameFix/\(Catalog.appVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.missing(url.lastPathComponent) }
        return data
    }

    static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// For the release: a catalog folder (the app's Resources) becomes
    /// catalog.zip, catalog.json naming every file and the zip's hash, and the
    /// signature of catalog.json with the private key at `keyFile`; modules.zip
    /// and the rest for the Wine modules.
    static func makeRelease(_ kind: CatalogKind = .fixes, from resources: URL, to out: URL, keyFile: URL,
                            version: Int, minimumApp: String, names: [String]) throws {
        let fm = FileManager.default
        let stem = kind.stem
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let flat = out.appendingPathComponent(stem)
        try? fm.removeItem(at: flat)
        try fm.createDirectory(at: flat, withIntermediateDirectories: true)
        var files: [String: String] = [:]
        for name in names {
            let data = try Data(contentsOf: resources.appendingPathComponent(name))
            try data.write(to: flat.appendingPathComponent(name))
            files[name] = hex(SHA256.hash(data: data))
        }
        let zip = out.appendingPathComponent("\(stem).zip")
        try? fm.removeItem(at: zip)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", flat.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        try? fm.removeItem(at: flat)
        let manifest = CatalogManifest(version: version, minimumApp: minimumApp, files: files,
                                       zipSHA256: hex(SHA256.hash(data: try Data(contentsOf: zip))))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: out.appendingPathComponent("\(stem).json"))
        let keyText = try String(contentsOf: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: keyText) else { throw Failure.signature }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        try (try key.signature(for: manifestData)).base64EncodedString()
            .write(to: out.appendingPathComponent("\(stem).json.sig"), atomically: true, encoding: .utf8)
    }
}

// MARK: - A report the user sends

enum Report {
    static let newIssue = "https://github.com/MathiasKowoll/MacGameFix/issues/new"

    /// GitHub's new-issue page for a fix that failed, filled in. Nothing is sent
    /// until the user, signed in to GitHub, reads it and presses Submit.
    static func url(game: String, problem: String, output: [String], catalog: Int) -> URL {
        let mac = ProcessInfo.processInfo.operatingSystemVersion
        var tail = output.suffix(60).map(scrub)
        var body = ""
        func compose() {
            body = """
            **Game:** \(game)
            **What happened:** \(problem)
            **MacGameFix:** \(Catalog.appVersion), catalog \(catalog)
            **macOS:** \(mac.majorVersion).\(mac.minorVersion).\(mac.patchVersion)

            **Installer output:**
            ```
            \(tail.joined(separator: "\n"))
            ```

            _Please say which runner you use (CrossOver, CrossOver Preview, NotProton), or that it is a macOS game, and what the game shows._
            """
        }
        compose()
        // GitHub reads a long address badly: keep the newest lines that fit.
        while body.utf8.count > 5000 && !tail.isEmpty {
            tail.removeFirst()
            compose()
        }
        var c = URLComponents(string: newIssue)!
        c.queryItems = [URLQueryItem(name: "title", value: "\(game): \(problem)"), URLQueryItem(name: "body", value: body)]
        return c.url!
    }

    /// The installer's output without the user in it: the home folder, the
    /// account and full names, and this Mac's serial number.
    static func scrub(_ line: String) -> String {
        var s = line.replacingOccurrences(of: Paths.home.path, with: "~")
        s = s.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        for name in [NSUserName(), NSFullUserName()] where name.count >= 3 {
            s = s.replacingOccurrences(of: name, with: "<user>")
        }
        if let serial = serialNumber(), !serial.isEmpty { s = s.replacingOccurrences(of: serial, with: "<serial>") }
        return s
    }

    static func serialNumber() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}

// MARK: - Notifications

/// The agent's voice. A failure carries a button that opens the filled-in
/// report; nothing else happens until the user presses it.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        let report = UNNotificationAction(identifier: "report", title: "Report on GitHub…", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "failure", actions: [report], intentIdentifiers: [], options: [])
        ])
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(_ event: AgentEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.game.isEmpty ? "MacGameFix" : event.game
        content.body = event.message
        if event.failed, let report = event.report {
            content.categoryIdentifier = "failure"
            content.userInfo = ["report": report]
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if response.actionIdentifier == "report",
           let s = response.notification.request.content.userInfo["report"] as? String, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
        done()
    }
}

// MARK: - The LaunchAgent

enum LaunchAgent {
    static let label = "io.github.macgamefix.agent"
    static var plist: URL { Paths.home.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var enabled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    /// The job: started at login in the user's graphical session, started
    /// again if it crashes, and left stopped when the user quits it.
    static func job(executable: String) -> NSDictionary {
        let log = Paths.home.appendingPathComponent("Library/Logs/MacGameFix-agent.log").path
        return [
            "Label": label,
            "ProgramArguments": [executable, "--agent"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "LimitLoadToSessionType": "Aqua",
            "ThrottleInterval": 60,
            "ProcessType": "Interactive",
            "StandardOutPath": log,
            "StandardErrorPath": log,
        ]
    }

    /// Whether the installed job is the one this app would write: an older
    /// one, or one pointing at a moved app, is written again.
    static func isCurrent(executable: String) -> Bool {
        NSDictionary(contentsOf: plist) == job(executable: executable)
    }

    static func enable(executable: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try job(executable: executable).write(to: plist)
        launchctl(["bootstrap", "gui/\(getuid())", plist.path])
    }

    /// Starts the job if it is loaded and not running, as after Quit.
    static func start() {
        launchctl(["kickstart", "gui/\(getuid())/\(label)"])
    }

    static func disable() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plist)
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
