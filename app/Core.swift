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
    static var settings: URL { support.appendingPathComponent("automatic.json") }
    static var state: URL { support.appendingPathComponent("agent-state.json") }
    static var installLock: URL { support.appendingPathComponent("installer.lock") }
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
    let carrierDir: String
    let script: String
    let needsPrefix: Bool
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
        switch backend {
        case "dxmt": parts.append("runs on DXMT")
        case "d3dmetal": parts.append("runs on D3DMetal")
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
            parts.append("not needed with Game Porting Toolkit \(notNeededFrom) or later; kept for earlier toolkits")
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
    case unknown, installed, absent, half, broken, noCarrier

    var label: String {
        switch self {
        case .unknown: return "…"
        case .installed: return "Installed"
        case .absent: return "Not installed"
        case .half: return "Half installed"
        case .broken: return "Needs repair"
        case .noCarrier: return "Cannot be fixed here"
        }
    }

    var color: Color {
        switch self {
        case .installed: return .green
        case .half, .broken: return .orange
        case .noCarrier: return .red
        default: return .secondary
        }
    }
}

/// One game found on disk.
struct Hit: Identifiable {
    let game: Game
    let folder: URL
    var prefixes: [Prefix] = []
    var prefix: Prefix?
    var state: FixState = .unknown
    var selected = false
    var outcome: String?
    /// What the game was found to run on: usually one, none when nothing tells.
    var runtimes: [GameRuntime] = []
    var key: String { gameKey(folder, game.name) }

    var id: String { folder.path + "|" + game.name }

    /// Why no button may touch this row, in the user's terms.
    var blocker: String? {
        if state == .noCarrier {
            return "The installer found nothing in this folder for the fix to ride on."
        }
        if game.needsPrefix && prefix == nil {
            return "No prefix for this game was found. Run it once with NotProton or CrossOver, then Scan again."
        }
        return nil
    }
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
                        h.prefix = h.prefixes.first
                    }
                    h.runtimes = Runtimes.detect(folder: folder)
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

enum Catalog {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func manifest(in dir: URL) -> CatalogManifest? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("catalog.json")) else { return nil }
        return try? JSONDecoder().decode(CatalogManifest.self, from: data)
    }

    /// The catalog to use: a downloaded one when it is newer than the bundle's
    /// and this app is new enough for it, else the bundle's own.
    static func active() -> (dir: URL, manifest: CatalogManifest?) {
        let bundled = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        let mine = manifest(in: bundled)
        let current = Paths.catalogs.appendingPathComponent("current").resolvingSymlinksInPath()
        if let theirs = manifest(in: current),
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
    /// The installer's word for a folder: installed, absent, half, broken; nil
    /// when it found nothing there for the fix to ride on.
    static func status(_ game: Game, folder: URL, prefix: String?, catalog: URL) async -> FixState {
        let out = Collected()
        let code = await run(game, folder: folder, prefix: prefix, catalog: catalog, ["--status"]) { out.add($0) }
        let word = out.all.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { ["installed", "broken", "half", "absent"].contains($0) }
        guard code == 0, let word else { return .noCarrier }
        switch word {
        case "installed": return .installed
        case "half": return .half
        case "broken": return .broken
        default: return .absent
        }
    }

    /// Runs the game's installer on its folder, holding the lock the app and the
    /// agent share, so the two never run an installer at once.
    static func run(_ game: Game, folder: URL, prefix: String?, catalog: URL, _ extra: [String],
                    onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        let lock = InstallLock()
        defer { lock.release() }
        let script = catalog.appendingPathComponent(game.script).path
        var env: [String: String] = [:]
        if game.needsPrefix, let prefix { env["MGVF_BOTTLE"] = prefix }
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
/// line of the process that runs it.
func isRunning(_ game: Game) -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = ["-axo", "args="]
    let pipe = Pipe()
    proc.standardOutput = pipe
    guard (try? proc.run()) != nil else { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    let exe = game.exe.lowercased()
    return String(decoding: data, as: UTF8.self).lowercased()
        .split(separator: "\n").contains { $0.contains(exe) }
}
