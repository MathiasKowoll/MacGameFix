// MacGameFix's core: running an installer, the table of games, and finding the
// game folders and prefixes. The window (MacGameFix.swift) and the background
// agent (Automation.swift) both use exactly this.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

// MARK: - Paths

enum Paths {
    /// The user's home. MACGAMEFIX_HOME stands in for it in the automation
    /// tests, since Foundation reads the home from the account, not from $HOME.
    static let home: URL = ProcessInfo.processInfo.environment["MACGAMEFIX_HOME"]
        .map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
    /// What the app and the agent keep: settings, the agent's state, catalogs.
    static var support: URL { home.appendingPathComponent("Library/Application Support/MacGameFix") }
    static var catalogs: URL { support.appendingPathComponent("catalog") }
    /// The Wine modules' catalogs, kept apart from the fixes'.
    static var modules: URL { support.appendingPathComponent("modules") }
    static var settings: URL { support.appendingPathComponent("automatic.json") }
    static var state: URL { support.appendingPathComponent("agent-state.json") }
    static var installLock: URL { support.appendingPathComponent("installer.lock") }
    /// The original executables of the macOS games whose app a fix changes.
    static var appBackup: URL { support.appendingPathComponent("app-backup") }
}

// MARK: - Running an installer

/// Collects bytes into lines across reads. A read can end in the middle of a
/// line, and handing that half to the log splits one message into two.
final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func take(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            let line = data[data.startIndex..<nl]
            lines.append(String(decoding: line, as: UTF8.self))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }

    func flush() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty else { return nil }
        defer { data.removeAll() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Runs a command, delivering each output line as it arrives, and returns the
/// exit status (-1 when it could not be started).
func runStreaming(_ executable: String, _ arguments: [String],
                          environment extra: [String: String],
                          onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
    await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        // The installers phrase their advice for a window rather than a
        // terminal when this is set -- and bottles.sh then insists on being told
        // which prefix, which is the behaviour wanted from any program.
        env["MGVF_FRONTEND"] = "app"
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        for (k, v) in extra { env[k] = v }
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            for line in buffer.take(chunk) { onLine(line) }
        }
        proc.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            if let tail = buffer.flush(), !tail.isEmpty { onLine(tail) }
            cont.resume(returning: finished.terminationStatus)
        }
        do {
            try proc.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            proc.terminationHandler = nil
            onLine("could not start \(executable): \(error.localizedDescription)")
            cont.resume(returning: -1)
        }
    }
}

/// Lines collected from one run, safe to append from the pipe's thread.
final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}

// MARK: - Model

/// One title, as build-app.sh wrote it into games.json.
struct Game: Decodable, Identifiable, Hashable {
    let name: String
    let exe: String
    /// Other executables the title runs as (Mortal Kombat 11's DirectX 11 one);
    /// absent from catalogs older than the field.
    let alsoRuns: [String]?
    let carrierDir: String
    let script: String
    let needsPrefix: Bool
    /// "prefix" for a fix whose DLLs go into the game's prefix and not its
    /// folder; "app" for one that changes a macOS game's own app; "folder", or
    /// absent in catalogs older than the field, for the rest.
    let scope: String?
    let symptom: String
    let backend: String
    let gptk: String
    /// A second toolkit generation measured working, beside `gptk`.
    let gptkAlso: String
    /// The CrossOver that ships the codec this title's videos need, or empty
    /// when it needs none. Stable 26.3 ships none of them.
    let codecShippedBy: String
    /// A CrossOver on which a fix that needs an engine of ours on 26.3 was
    /// measured needing none; empty otherwise.
    let engineFreeOn: String
    /// A Game Porting Toolkit from which the title plays without this fix.
    let notNeededFrom: String
    let why: String

    var id: String { name }

    /// NINJA GAIDEN 3's: its DLLs and overrides go into the prefix, a CrossOver
    /// bottle or a Steam Play prefix, and nothing into the game folder.
    var inPrefix: Bool { scope == "prefix" }

    /// Cyberpunk 2077's: a macOS game, whose executable the fix changes and
    /// whose app it signs again ad hoc. No Wine runs it.
    var inApp: Bool { scope == "app" }

    /// Where the fix's part outside the game folder goes, said before the place.
    var prefixWhat: String { inPrefix ? "Its DLLs and overrides go into" : "Registry keys go into" }

    /// Is this folder this game? Identity is the shipping executable, looked for
    /// where these titles keep it: the folder itself, the carrier's folder (The
    /// Witcher 3 keeps both in bin/x64_dx12), and Unreal's
    /// <Project>/Binaries/Win64.
    func isRooted(at folder: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent(exe).path) { return true }
        if !carrierDir.isEmpty,
           fm.fileExists(atPath: folder.appendingPathComponent(carrierDir).appendingPathComponent(exe).path) {
            return true
        }
        let subs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for sub in subs where sub.lastPathComponent != "Engine" {
            if fm.fileExists(atPath: sub.appendingPathComponent("Binaries/Win64").appendingPathComponent(exe).path) {
                return true
            }
        }
        return false
    }

    /// What the backend and toolkit fields mean to someone choosing settings.
    var requirementNote: String? {
        var parts: [String] = []
        if inApp { parts.append("macOS app; changes its executable") }
        switch backend {
        case "dxmt": parts.append("runs on DXMT")
        case "d3dmetal": parts.append("runs on D3DMetal")
        case "dxvk": parts.append("runs on DXVK")
        default: break
        }
        if !gptk.isEmpty {
            parts.append(gptkAlso.isEmpty ? "needs D3DMetal \(gptk)"
                                          : "needs D3DMetal \(gptk) or \(gptkAlso)")
        }
        if !codecShippedBy.isEmpty {
            parts.append("its videos need \(codecShippedBy), which ships their codec")
        }
        if !notNeededFrom.isEmpty {
            parts.append("not needed on D3DMetal \(notNeededFrom) or later; kept for earlier ones")
        }
        if !engineFreeOn.isEmpty {
            parts.append("needs \(engineFreeOn); stable CrossOver 26.3 needed MacGameVideoFix's engine, now archived")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Where a title's registry keys can go: a Steam Play prefix or a CrossOver
/// bottle. Both are a directory holding drive_c, which is what the installer
/// takes as MGVF_BOTTLE.
struct Prefix: Hashable, Identifiable {
    enum Kind: Hashable { case steamPlay, bottle }
    let kind: Kind
    let path: URL
    var id: String { path.path }
    var label: String {
        switch kind {
        case .steamPlay: return "Steam Play prefix (\(path.deletingLastPathComponent().lastPathComponent))"
        case .bottle: return "CrossOver bottle “\(path.lastPathComponent)”"
        }
    }
}

enum FixState: Equatable {
    case unknown, installed, outdated, absent, half, broken, noCarrier, noRecipe, blocked

    var label: String {
        switch self {
        case .unknown: return "…"
        case .installed: return "Installed"
        case .outdated: return "Older build: install to update"
        case .absent: return "Not installed"
        case .half: return "Half installed"
        case .broken: return "Needs repair"
        case .noCarrier: return "Cannot be fixed here"
        case .noRecipe: return "No recipe for this build yet"
        case .blocked: return "Cannot be installed here"
        }
    }

    var color: Color {
        switch self {
        case .installed: return .green
        case .outdated: return .blue
        case .half, .broken: return .orange
        case .noCarrier, .blocked: return .red
        default: return .secondary
        }
    }
}

/// One game found on disk.
struct Hit: Identifiable {
    let game: Game
    let folder: URL
    var prefixes: [Prefix] = []
    /// Where a fix that writes registry keys puts them: one or more of
    /// `prefixes`, each a run of its installer.
    var chosen: [Prefix] = []
    var state: FixState = .unknown
    /// The game's build, when its installer names it: a fix made for each build
    /// of the game says which one it found.
    var build: String?
    /// Why, in the installer's words, when it says so on a "Why:" line: what a
    /// fix for a macOS game's app gives for a row it cannot install.
    var note: String?
    var selected = false
    /// What went wrong the last time this game's fix was installed or removed.
    var outcome: String?
    var key: String { gameKey(folder, game.name) }

    var id: String { folder.path + "|" + game.name }

    /// Why no button may touch this row, in the user's terms.
    var blocker: String? {
        if state == .noCarrier {
            return "The installer found nothing in this folder for the fix to ride on."
        }
        if state == .noRecipe {
            return "MacGameFix waits for a recipe for " + (build.map { "the game's build \($0)" } ?? "the game's new build")
                + "; a catalog update brings it."
        }
        // A fix for a macOS game's app that its installer will not install
        // here: an executable changed outside MacGameFix, patched or not, or a
        // Mac the fix is not for. Its installer says which, and what to do.
        if state == .blocked {
            return note ?? "The installer cannot install the fix here."
        }
        if state == .half && game.inApp {
            return note ?? "The executable was patched outside MacGameFix; nothing can be installed or removed here."
        }
        if game.needsPrefix && prefixes.isEmpty {
            return "No prefix for this game was found. Run it once with NotProton or CrossOver, then Scan again."
        }
        if game.needsPrefix && chosen.isEmpty {
            return game.inPrefix ? "Choose at least one place for its DLLs." : "Choose at least one place for its registry keys."
        }
        return nil
    }

    /// Whether Keep can be turned on: not for a row that is blocked, but for
    /// one waiting for a recipe, which the agent installs once it comes. A
    /// kept row can always be turned off.
    var keepable: Bool { blocker == nil || state == .noRecipe }

    /// Whether the row can be selected: one that is not blocked, and one
    /// waiting for a recipe, which Remove Selected may still clear of the
    /// copies kept for the game's earlier builds. Install skips it.
    var selectable: Bool { blocker == nil || state == .noRecipe }
}

// MARK: - Finding libraries and prefixes

enum Libraries {
    static var home: URL { Paths.home }

    /// Every steamapps/common worth scanning: the native Steam's libraries (a
    /// Steam Play tool installs Windows games there), the libraries of the Steam
    /// inside each CrossOver bottle, and the folders the user added.
    static func all(extra: [URL]) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        func add(_ common: URL) {
            let key = common.standardizedFileURL.path.lowercased()
            guard seen.insert(key).inserted else { return }
            found.append(common)
        }
        let steam = home.appendingPathComponent("Library/Application Support/Steam")
        add(steam.appendingPathComponent("steamapps/common"))
        for vdf in [steam.appendingPathComponent("config/libraryfolders.vdf"),
                    steam.appendingPathComponent("steamapps/libraryfolders.vdf")] {
            guard let text = try? String(contentsOf: vdf, encoding: .utf8) else { continue }
            for p in paths(in: text) where p.hasPrefix("/") {
                add(URL(fileURLWithPath: p).appendingPathComponent("steamapps/common"))
            }
        }
        for bottle in bottles() {
            let vdf = bottle.appendingPathComponent(
                "drive_c/Program Files (x86)/Steam/config/libraryfolders.vdf")
            guard let text = try? String(contentsOf: vdf, encoding: .utf8) else { continue }
            for p in paths(in: text) {
                if let mac = translate(p, inBottle: bottle) {
                    add(mac.appendingPathComponent("steamapps/common"))
                }
            }
        }
        for u in extra { add(u) }
        return found
    }

    /// Bottle directories in every root a CrossOver on this Mac uses: the default
    /// one, and any CX_BOTTLE_PATH a copy's etc/CrossOver.conf redirects to.
    static func bottles() -> [URL] {
        let fm = FileManager.default
        var roots = [home.appendingPathComponent("Library/Application Support/CrossOver/Bottles")]
        let apps = ((try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"),
                                                 includingPropertiesForKeys: nil)) ?? [])
            + ((try? fm.contentsOfDirectory(at: home.appendingPathComponent("Applications"),
                                            includingPropertiesForKeys: nil)) ?? [])
        for app in apps where app.pathExtension == "app" {
            let conf = app.appendingPathComponent("Contents/SharedSupport/CrossOver/etc/CrossOver.conf")
            guard let text = try? String(contentsOf: conf, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.hasPrefix("\"CX_BOTTLE_PATH\"") {
                let parts = line.split(separator: "\"")
                if let v = parts.last, v.hasPrefix("/") { roots.append(URL(fileURLWithPath: String(v))) }
            }
        }
        var out: [URL] = []
        var seen = Set<String>()
        for root in roots {
            for b in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where fm.fileExists(atPath: b.appendingPathComponent("drive_c").path) {
                if seen.insert(b.standardizedFileURL.path).inserted { out.append(b) }
            }
        }
        return out
    }

    /// The "path" values of a libraryfolders.vdf, unescaped.
    static func paths(in vdf: String) -> [String] {
        vdf.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 4, parts[1] == "path" else { return nil }
            return String(parts[3]).replacingOccurrences(of: "\\\\", with: "\\")
        }
    }

    /// A Windows path to a macOS one, through the bottle's own drive map.
    static func translate(_ windowsPath: String, inBottle bottle: URL) -> URL? {
        let chars = Array(windowsPath)
        guard chars.count >= 2, chars[1] == ":" else { return nil }
        let link = bottle.appendingPathComponent("dosdevices/\(String(chars[0]).lowercased()):")
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
        let base = target.hasPrefix("/") ? URL(fileURLWithPath: target)
            : bottle.appendingPathComponent("dosdevices").appendingPathComponent(target)
        let rest = String(chars.dropFirst(2)).replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return (rest.isEmpty ? base : base.appendingPathComponent(rest)).standardizedFileURL
    }

    /// The places a game's registry keys could go.
    ///
    /// A Steam Play tool keeps one prefix per game, at
    /// steamapps/compatdata/<appid>/pfx beside the library, and the appid is read
    /// from the appmanifest whose installdir is this folder. A CrossOver bottle
    /// qualifies when its Steam declares the library the game sits in -- the
    /// same rule the installer uses, and never "any bottle with a dinput8", which
    /// once put a KINGDOM HEARTS key into a Battle.net bottle.
    static func prefixes(for folder: URL) -> [Prefix] {
        let fm = FileManager.default
        var out: [Prefix] = []
        let common = folder.deletingLastPathComponent()
        let steamapps = common.deletingLastPathComponent()
        if common.lastPathComponent == "common", steamapps.lastPathComponent == "steamapps" {
            let manifests = ((try? fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            for m in manifests {
                guard let text = try? String(contentsOf: m, encoding: .utf8),
                      installDir(in: text) == folder.lastPathComponent else { continue }
                let appid = m.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "appmanifest_", with: "")
                let pfx = steamapps.appendingPathComponent("compatdata/\(appid)/pfx")
                if fm.fileExists(atPath: pfx.appendingPathComponent("user.reg").path) {
                    out.append(Prefix(kind: .steamPlay, path: pfx))
                }
            }
            let library = steamapps.deletingLastPathComponent().standardizedFileURL.path.lowercased()
            for bottle in bottles() {
                let vdf = bottle.appendingPathComponent(
                    "drive_c/Program Files (x86)/Steam/config/libraryfolders.vdf")
                guard let text = try? String(contentsOf: vdf, encoding: .utf8),
                      fm.fileExists(atPath: bottle.appendingPathComponent("drive_c/windows/system32/dinput8.dll").path)
                else { continue }
                let declared = paths(in: text).compactMap { translate($0, inBottle: bottle)?.path.lowercased() }
                if declared.contains(library) { out.append(Prefix(kind: .bottle, path: bottle)) }
            }
        }
        return out
    }

    private static func installDir(in acf: String) -> String? {
        for line in acf.split(separator: "\n") {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 4, parts[1] == "installdir" { return String(parts[3]) }
        }
        return nil
    }
}

/// The key settings and state keep a game folder under. The same folder can
/// be written /var/... or /private/var/..., depending on which call returned
/// it; resolving it makes the two one.
func gameKey(_ folder: URL, _ name: String) -> String {
    folder.resolvingSymlinksInPath().standardizedFileURL.path + "|" + name
}

// MARK: - Finding the games

extension Libraries {
    /// Every supported game in these libraries, with the prefixes a fix that
    /// writes registry keys could use and what the game runs on.
    static func find(_ games: [Game], extra: [URL]) -> (libraries: [URL], hits: [Hit]) {
        let fm = FileManager.default
        let libs = all(extra: extra)
        var hits: [Hit] = []
        var seen = Set<String>()
        for lib in libs {
            // A folder the user added may be a game folder itself.
            var candidates = [lib]
            candidates += ((try? fm.contentsOfDirectory(at: lib, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            for folder in candidates {
                for g in games where g.isRooted(at: folder) {
                    let key = folder.standardizedFileURL.path + "|" + g.name
                    guard seen.insert(key).inserted else { continue }
                    var h = Hit(game: g, folder: folder)
                    if g.needsPrefix {
                        h.prefixes = prefixes(for: folder)
                        h.chosen = Array(h.prefixes.prefix(1))
                    }
                    hits.append(h)
                }
            }
        }
        hits.sort { $0.game.name.lowercased() < $1.game.name.lowercased() }
        return (libs, hits)
    }
}

// MARK: - The catalog in use

/// What a catalog of fixes carries: the installers and every file they name,
/// with games.json. The bundle holds one; a newer, verified one downloaded from
/// the releases replaces it without a new app (Automation.swift).
struct CatalogManifest: Codable {
    /// When the catalog was built, in seconds: the newer one wins.
    var version: Int
    /// The app version it needs, for a catalog that asks more of the app.
    var minimumApp: String
    /// Every file, by name, with its SHA-256.
    var files: [String: String]
    /// In a release's catalog.json only: the SHA-256 of catalog.zip.
    var zipSHA256: String?
}

/// The two catalogs a release carries, each signed and versioned on its own, so
/// that new Wine modules for a new CrossOver come without touching the game
/// fixes, and the other way round. Each has its own setting for updates.
enum CatalogKind: String, CaseIterable {
    case fixes, modules

    /// The manifest's name, in the bundle and among a release's assets; the
    /// zip and the signature share the stem (catalog.zip, modules.json.sig).
    var stem: String { self == .fixes ? "catalog" : "modules" }
    /// Where downloaded catalogs of this kind go, each under its version.
    var store: URL { self == .fixes ? Paths.catalogs : Paths.modules }
    /// For the lines the agent and the window write.
    var noun: String { self == .fixes ? "fixes" : "Wine modules" }
}

enum Catalog {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func manifest(in dir: URL, _ kind: CatalogKind = .fixes) -> CatalogManifest? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(kind.stem).json")) else { return nil }
        return try? JSONDecoder().decode(CatalogManifest.self, from: data)
    }

    /// The catalog to use: a downloaded one when it is newer than the bundle's
    /// and this app is new enough for it, else the bundle's own.
    static func active(_ kind: CatalogKind = .fixes) -> (dir: URL, manifest: CatalogManifest?) {
        let bundled = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        let mine = manifest(in: bundled, kind)
        let current = kind.store.appendingPathComponent("current").resolvingSymlinksInPath()
        if let theirs = manifest(in: current, kind),
           theirs.version > (mine?.version ?? 0),
           !versionLess(appVersion, theirs.minimumApp) {
            return (current, theirs)
        }
        return (bundled, mine)
    }

    static func games(in dir: URL) -> [Game] {
        struct Table: Decodable { let games: [Game] }
        let data = (try? Data(contentsOf: dir.appendingPathComponent("games.json"))) ?? Data()
        return (try? JSONDecoder().decode(Table.self, from: data))?.games ?? []
    }

    /// Dotted versions compared number by number: "1.10" is newer than "1.9".
    static func versionLess(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q }
        }
        return false
    }
}

// MARK: - One installer, from anywhere

enum Fixer {
    /// The installer's word for a folder: installed, outdated (an older build of
    /// the fix, which installing again replaces), absent, half, broken,
    /// noRecipe for a game build the fix has no recipe for yet, or blocked when
    /// it will not install here and says why; noCarrier when it found nothing
    /// there for the fix to ride on.
    static func status(_ game: Game, folder: URL, prefixes: [String], catalog: URL) async -> FixState {
        guard game.needsPrefix, !prefixes.isEmpty else {
            return await status(game, folder: folder, prefix: nil, catalog: catalog)
        }
        var states: [FixState] = []
        for p in prefixes { states.append(await status(game, folder: folder, prefix: p, catalog: catalog)) }
        return combined(states)
    }

    /// One word for several prefixes: theirs when they agree; else a fix the
    /// installer could not place, one it will not install, one with no recipe
    /// for the game's build, a broken one, an older build, or a fix in some of
    /// them only.
    static func combined(_ states: [FixState]) -> FixState {
        guard let first = states.first else { return .unknown }
        if states.allSatisfy({ $0 == first }) { return first }
        if states.contains(.noCarrier) { return .noCarrier }
        if states.contains(.blocked) { return .blocked }
        if states.contains(.noRecipe) { return .noRecipe }
        if states.contains(.broken) { return .broken }
        if states.allSatisfy({ $0 == .installed || $0 == .outdated }) { return .outdated }
        return .half
    }

    static func status(_ game: Game, folder: URL, prefix: String?, catalog: URL) async -> FixState {
        await look(game, folder: folder, prefix: prefix, catalog: catalog).state
    }

    /// What an installer's --status says: the word, the game's build when it
    /// names it on a "Game build:" line, as one made for each build of the
    /// game does, and its reason when it gives one on a "Why:" line.
    struct Look {
        var state: FixState
        var build: String? = nil
        var note: String? = nil
    }

    /// "norecipe" is the word of an installer made for each build of the game
    /// for a build it has no recipe for yet; "blocked", of one that will not
    /// install here, with its reason on the "Why:" line.
    static func look(_ game: Game, folder: URL, prefix: String?, catalog: URL) async -> Look {
        let out = Collected()
        let code = await run(game, folder: folder, prefix: prefix, catalog: catalog, ["--status"]) { out.add($0) }
        let lines = out.all.map { $0.trimmingCharacters(in: .whitespaces) }
        let word = lines.first { ["installed", "outdated", "broken", "half", "absent", "norecipe", "blocked"].contains($0) }
        func after(_ prefix: String) -> String? {
            lines.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        var look = Look(state: .noCarrier, build: after("Game build: "), note: after("Why: "))
        guard code == 0, let word else { return look }
        switch word {
        case "installed": look.state = .installed
        case "outdated": look.state = .outdated
        case "half": look.state = .half
        case "broken": look.state = .broken
        case "norecipe": look.state = .noRecipe
        case "blocked": look.state = .blocked
        default: look.state = .absent
        }
        return look
    }

    /// Runs the game's installer on its folder, holding the lock the app and the
    /// agent share, so the two never run an installer at once.
    /// The installer once for each prefix a fix that writes registry keys was
    /// given, stopping at the first that fails; once, for any other fix.
    static func run(_ game: Game, folder: URL, prefixes: [String], catalog: URL, _ extra: [String],
                    onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        guard game.needsPrefix, !prefixes.isEmpty else {
            return await run(game, folder: folder, prefix: nil, catalog: catalog, extra, onLine: onLine)
        }
        for p in prefixes {
            let code = await run(game, folder: folder, prefix: p, catalog: catalog, extra, onLine: onLine)
            if code != 0 { return code }
        }
        return 0
    }

    static func run(_ game: Game, folder: URL, prefix: String?, catalog: URL, _ extra: [String],
                    onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        let lock = InstallLock()
        defer { lock.release() }
        let script = catalog.appendingPathComponent(game.script).path
        var env: [String: String] = [:]
        if game.needsPrefix, let prefix { env["MGVF_BOTTLE"] = prefix }
        // Where a fix that changes a game's app keeps its original.
        if game.inApp { env["MGVF_APP_BACKUP"] = Paths.appBackup.path }
        return await runStreaming("/bin/bash", [script, folder.path] + extra, environment: env, onLine: onLine)
    }
}

/// An exclusive lock on a file in MacGameFix's support folder, held for one
/// installer run. Blocks until the other holder is done.
final class InstallLock: @unchecked Sendable {
    private var fd: Int32 = -1
    init() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        fd = open(Paths.installLock.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        if fd >= 0 { flock(fd, LOCK_EX) }
    }
    func release() {
        if fd >= 0 { flock(fd, LOCK_UN); close(fd); fd = -1 }
    }
    deinit { release() }
}

// MARK: - What Steam says about a game folder

struct SteamApp {
    let appid: String
    let buildid: String
    /// 4 is "fully installed"; anything else is Steam still writing the game.
    let stateFlags: String

    var settled: Bool { stateFlags == "4" }

    /// The appmanifest whose installdir is this folder, beside its library.
    static func of(folder: URL) -> SteamApp? {
        let common = folder.deletingLastPathComponent(), steamapps = common.deletingLastPathComponent()
        guard common.lastPathComponent == "common", steamapps.lastPathComponent == "steamapps" else { return nil }
        let manifests = ((try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
        for m in manifests {
            guard let text = try? String(contentsOf: m, encoding: .utf8) else { continue }
            var fields: [String: String] = [:]
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
                if parts.count >= 4, fields[String(parts[1])] == nil { fields[String(parts[1])] = String(parts[3]) }
            }
            guard fields["installdir"] == folder.lastPathComponent else { continue }
            return SteamApp(appid: fields["appid"] ?? "", buildid: fields["buildid"] ?? "",
                            stateFlags: fields["StateFlags"] ?? "")
        }
        return nil
    }
}

/// Is the game running? Under Wine its executable's name is in the command
/// line of the process that runs it, and a macOS game's is in its path.
func isRunning(_ game: Game) -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = ["-axo", "args="]
    let pipe = Pipe()
    proc.standardOutput = pipe
    guard (try? proc.run()) != nil else { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    let exes = ([game.exe] + (game.alsoRuns ?? [])).map { $0.lowercased() }
    return String(decoding: data, as: UTF8.self).lowercased()
        .split(separator: "\n").contains { line in exes.contains { line.contains($0) } }
}
