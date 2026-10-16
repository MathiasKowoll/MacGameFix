// MacGameFix in the background: an agent that keeps the fixes the user marked
// applied, a catalog of fixes that updates itself from the releases, and a
// report the user can send when a fix does not take.
//
// - The agent (a LaunchAgent running this binary with --agent) looks at every
//   marked game every two minutes. When Steam has changed the game since the last
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
    /// The prefix chosen for a title that writes registry keys.
    var prefix: String?
    var key: String { folder + "|" + name }
}

struct AutoSettings: Codable {
    var kept: [KeptGame] = []
    /// Take newer catalogs from the releases.
    var updates = true

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
}

struct GameMemory: Codable {
    var build = ""
    var catalog = 0
    var checked = Date.distantPast
    var state = ""
}

struct AgentState: Codable {
    var games: [String: GameMemory] = [:]
    var events: [AgentEvent] = []
    var lastUpdateCheck = Date.distantPast
    var lastUpdate = ""

    static func load() -> AgentState {
        guard let data = try? Data(contentsOf: Paths.state),
              let s = try? JSONDecoder().decode(AgentState.self, from: data) else { return AgentState() }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Paths.state, options: .atomic) }
    }

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

    /// One look at every marked game, and at the releases when it is time.
    /// Returns what it did, for the log and the tests.
    static func pass(now: Date = Date(), notify: Bool) async -> [AgentEvent] {
        let settings = AutoSettings.load()
        var state = AgentState.load()
        var events: [AgentEvent] = []

        if settings.updates && now.timeIntervalSince(state.lastUpdateCheck) > updateEvery {
            state.lastUpdateCheck = now
            let before = Set(Catalog.games(in: Catalog.active().dir).map(\.name))
            do {
                let line = try await Updater.update()
                state.lastUpdate = line
                let added = Catalog.games(in: Catalog.active().dir).map(\.name).filter { !before.contains($0) }
                if !added.isEmpty {
                    events.append(AgentEvent(date: now, game: "", message: "New fixes: " + added.joined(separator: ", "),
                                             failed: false))
                }
            } catch {
                state.lastUpdate = "Update check failed: \(error.localizedDescription)"
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
            guard changed || now.timeIntervalSince(memory.checked) > recheck else { continue }
            if isRunning(game) { continue } // Looked at again once it is closed.

            let word = await Fixer.status(game, folder: folder, prefix: kept.prefix, catalog: catalogDir)
            var event: AgentEvent?
            if word == .installed {
                if memory.state != "installed" && !memory.state.isEmpty {
                    event = AgentEvent(date: now, game: game.name, message: "The fix is in place.", failed: false)
                }
            } else if word == .noCarrier {
                event = failure(game, now, "The installer found nothing in the game folder for the fix to ride on.",
                                output: [], catalog: catalog)
            } else {
                let out = Collected()
                let code = await Fixer.run(game, folder: folder, prefix: kept.prefix, catalog: catalogDir, []) {
                    out.add($0)
                }
                let after = await Fixer.status(game, folder: folder, prefix: kept.prefix, catalog: catalogDir)
                if code == 0 && after == .installed {
                    event = AgentEvent(date: now, game: game.name,
                                       message: changed && !memory.build.isEmpty && memory.build != build
                                           ? "Steam changed the game; the fix is back in place."
                                           : "The fix was missing and is back in place.",
                                       failed: false)
                } else {
                    event = failure(game, now,
                                    code != 0 ? "The installer failed (status \(code))." : "The fix did not take.",
                                    output: out.all, catalog: catalog)
                }
                memory.state = after == .installed ? "installed" : "failed"
            }
            if word == .installed { memory.state = "installed" }
            if word == .noCarrier { memory.state = "failed" }
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

    /// The LaunchAgent's process: a pass every two minutes, for as long as it runs.
    static func runForever() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Notifier.start()
        Task {
            while true {
                let events = await pass(notify: true)
                for e in events { print("\(e.date) \(e.game): \(e.message)") }
                try? await Task.sleep(nanoseconds: 120 * 1_000_000_000)
            }
        }
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

    /// Takes a newer catalog from the latest release, or from `source`: a folder
    /// holding catalog.json, catalog.json.sig and catalog.zip, for the tests.
    /// Returns a line saying what happened.
    @discardableResult
    static func update(from source: URL? = nil, publicKey key: String = publicKey) async throws -> String {
        let (manifestURL, signatureURL, zipURL) = try await assets(source)
        let manifestData = try await fetch(manifestURL)
        let signature = try await fetch(signatureURL)
        guard let raw = Data(base64Encoded: key),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              publicKey.isValidSignature(Data(base64Encoded: String(decoding: signature, as: UTF8.self)
                  .trimmingCharacters(in: .whitespacesAndNewlines)) ?? signature, for: manifestData)
        else { throw Failure.signature }
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: manifestData)
        let active = Catalog.active().manifest?.version ?? 0
        guard manifest.version > active else { return "The fixes are up to date (catalog \(active))." }
        guard !Catalog.versionLess(Catalog.appVersion, manifest.minimumApp) else {
            throw Failure.app(manifest.minimumApp)
        }
        let zip = try await fetch(zipURL)
        guard hex(SHA256.hash(data: zip)) == manifest.zipSHA256 else { throw Failure.hash("catalog.zip") }

        let fm = FileManager.default
        try fm.createDirectory(at: Paths.catalogs, withIntermediateDirectories: true)
        let staging = Paths.catalogs.appendingPathComponent(".incoming-\(UUID().uuidString)")
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
            guard !name.contains("/"), !name.hasPrefix("."), name != "catalog.json" else { throw Failure.unsafe(name) }
            guard let data = fm.contents(atPath: files.appendingPathComponent(name).path),
                  hex(SHA256.hash(data: data)) == sum else { throw Failure.hash(name) }
            if name.hasPrefix("install-") && name.hasSuffix(".sh") {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: files.appendingPathComponent(name).path)
            }
        }
        try manifestData.write(to: files.appendingPathComponent("catalog.json"))

        // In place under its version, then the switch, in one rename.
        let target = Paths.catalogs.appendingPathComponent(String(manifest.version))
        try? fm.removeItem(at: target)
        try fm.moveItem(at: files, to: target)
        let link = Paths.catalogs.appendingPathComponent(".current-\(UUID().uuidString)")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: String(manifest.version))
        guard rename(link.path, Paths.catalogs.appendingPathComponent("current").path) == 0 else {
            try? fm.removeItem(at: link)
            throw Failure.missing("a place to put the catalog")
        }
        // Keep the one before, for a look back; drop the rest.
        let versions = ((try? fm.contentsOfDirectory(atPath: Paths.catalogs.path)) ?? [])
            .compactMap(Int.init).sorted(by: >)
        for old in versions.dropFirst(2) {
            try? fm.removeItem(at: Paths.catalogs.appendingPathComponent(String(old)))
        }
        return "New fixes installed: catalog \(manifest.version)."
    }

    private static func assets(_ source: URL?) async throws -> (URL, URL, URL) {
        if let source {
            return (source.appendingPathComponent("catalog.json"), source.appendingPathComponent("catalog.json.sig"),
                    source.appendingPathComponent("catalog.zip"))
        }
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable { let assets: [Asset] }
        let release = try JSONDecoder().decode(Release.self, from: try await fetch(releases))
        func named(_ n: String) throws -> URL {
            guard let a = release.assets.first(where: { $0.name == n }) else { throw Failure.missing(n) }
            return a.browser_download_url
        }
        return (try named("catalog.json"), try named("catalog.json.sig"), try named("catalog.zip"))
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
    /// signature of catalog.json with the private key at `keyFile`.
    static func makeRelease(from resources: URL, to out: URL, keyFile: URL, version: Int,
                            minimumApp: String, names: [String]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let flat = out.appendingPathComponent("catalog")
        try? fm.removeItem(at: flat)
        try fm.createDirectory(at: flat, withIntermediateDirectories: true)
        var files: [String: String] = [:]
        for name in names {
            let data = try Data(contentsOf: resources.appendingPathComponent(name))
            try data.write(to: flat.appendingPathComponent(name))
            files[name] = hex(SHA256.hash(data: data))
        }
        let zip = out.appendingPathComponent("catalog.zip")
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
        try manifestData.write(to: out.appendingPathComponent("catalog.json"))
        let keyText = try String(contentsOf: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: keyText) else { throw Failure.signature }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        try (try key.signature(for: manifestData)).base64EncodedString()
            .write(to: out.appendingPathComponent("catalog.json.sig"), atomically: true, encoding: .utf8)
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

            _Please say which runner you use (CrossOver, CrossOver Preview, NotProton) and what the game shows._
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

    /// The program the installed agent runs, so a moved app can be noticed.
    static var installedProgram: String? {
        guard let d = NSDictionary(contentsOf: plist), let args = d["ProgramArguments"] as? [String] else { return nil }
        return args.first
    }

    static func enable(executable: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let log = Paths.home.appendingPathComponent("Library/Logs/MacGameFix-agent.log").path
        let d: NSDictionary = [
            "Label": label,
            "ProgramArguments": [executable, "--agent"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 60,
            "ProcessType": "Background",
            "StandardOutPath": log,
            "StandardErrorPath": log,
        ]
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try d.write(to: plist)
        launchctl(["bootstrap", "gui/\(getuid())", plist.path])
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
