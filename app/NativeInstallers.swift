// Native ports that come with an installer of their own.
//
// NightSightProductions' ports (DOOM of 2016 and four Wolfenstein games, on their Recomp-Framework)
// are not built from sources by MacGameFix as Batman and BioShock Infinite are (NativePort.swift):
// each one is released as a disk image with an installer, "Install <name>.app", that finds the
// player's Windows copy of the game, builds the port on the Mac in about a quarter of an hour, and
// leaves the game's app in Applications. Their author agreed (2026-11-28) to MacGameFix getting
// that installer and running it for the player, and keeping it up to date.
//
// So for each port MacGameFix downloads the installer, checks it, and opens it; the installer
// does the rest, with its own window. Which file: the one the signed fixes catalog names
// (native-installers.json), by its address, its size and its SHA-256, and no other. The
// installers are not notarized by Apple, and a file MacGameFix downloads carries no quarantine,
// so macOS would not ask before opening it: the catalog's hash is what stands for that question.
// A new release of a port reaches players when the catalog names it, which needs no new app.
//
// The disk image is mounted where the Finder does not show it, the installer is copied out, and
// the image is let go again, so nothing stays mounted while the installer runs.
//
// What MacGameFix knows of a port afterwards: whether its app is in Applications, and which
// version's installer it last opened for it (native-installers.installed, in its own folder).
// The app the installer builds is not asked for its version.
//
// The table has a schema version, as notproton-rows.json has; a newer one than this app reads is
// not used.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CryptoKit
import SwiftUI

enum NativeInstallers {
    /// The native-installers.json schema this app reads.
    static let schema = 1

    struct Table: Decodable {
        let schema: Int
        let ports: [Port]
    }

    struct Port: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let summary: String
        let by: String
        /// The Windows game's Steam app id, and its program in the game's folder.
        let steamApp: String
        let gameExecutable: String
        /// What the installer leaves in Applications, and the installer inside the disk image.
        let app: String
        let installer: String
        let version: String
        let url: String
        let sha256: String
        let size: Int
        let page: String
    }

    struct Failure: Error { let text: String }

    enum State: Equatable, Sendable {
        case notInstalled
        /// The port's app is there; the version whose installer MacGameFix last opened, if it did.
        case installed(String?)
        /// The app is there and the catalog names a later installer than the one last opened.
        case update(from: String, to: String)
    }

    static var folder: URL { Paths.support.appendingPathComponent("native-installers") }
    static var record: URL { Paths.support.appendingPathComponent("native-installers.installed") }

    /// The catalog's table; nil when there is none, or its schema is newer than this app reads.
    /// MACGAMEFIX_NATIVE_INSTALLERS stands in for the catalog's in the tests.
    static func table(in dir: URL = Catalog.active().dir) -> Table? {
        let file = ProcessInfo.processInfo.environment["MACGAMEFIX_NATIVE_INSTALLERS"].map { URL(fileURLWithPath: $0) }
            ?? dir.appendingPathComponent("native-installers.json")
        guard let data = try? Data(contentsOf: file),
              let table = try? JSONDecoder().decode(Table.self, from: data), table.schema <= schema else { return nil }
        return table
    }

    static func ports() -> [Port] {
        // Names that go into paths: nothing but what an app's name and an id are made of.
        (table()?.ports ?? []).filter { port in
            !port.id.isEmpty && port.id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
                && [port.app, port.installer].allSatisfy { $0.hasSuffix(".app") && !$0.contains("/") && !$0.hasPrefix(".") }
                && port.sha256.count == 64 && port.size > 0
        }
    }

    /// The version whose installer was last opened for each port, by id.
    static func recorded() -> [String: String] {
        var out: [String: String] = [:]
        for line in ((try? String(contentsOf: record, encoding: .utf8)) ?? "").split(separator: "\n") {
            let words = line.split(separator: " ", maxSplits: 1).map(String.init)
            if words.count == 2 { out[words[0]] = words[1] }
        }
        return out
    }

    static func note(_ port: Port) {
        var all = recorded()
        all[port.id] = port.version
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        try? (all.keys.sorted().map { "\($0) \(all[$0]!)" }.joined(separator: "\n") + "\n")
            .write(to: record, atomically: true, encoding: .utf8)
    }

    /// The Windows game's folder in a Steam library, where it holds the game's program.
    static func gameFolder(_ port: Port, extra: [URL] = []) -> URL? {
        let fm = FileManager.default
        for common in Libraries.all(extra: extra) {
            let manifest = common.deletingLastPathComponent().appendingPathComponent("appmanifest_\(port.steamApp).acf")
            guard let text = try? String(contentsOf: manifest, encoding: .utf8),
                  let dir = SteamGames.manifest(text)["installdir"], !dir.isEmpty, !dir.contains("/") else { continue }
            let folder = common.appendingPathComponent(dir)
            if fm.fileExists(atPath: folder.appendingPathComponent(port.gameExecutable).path) { return folder }
        }
        return nil
    }

    /// The port's app, where its installer puts it: Applications, or the user's own.
    static func installedApp(_ port: Port) -> URL? {
        var places = [Paths.home.appendingPathComponent("Applications")]
        // The tests' home stands for the whole Mac: its /Applications is not theirs to look in.
        if ProcessInfo.processInfo.environment["MACGAMEFIX_HOME"] == nil { places.insert(URL(fileURLWithPath: "/Applications"), at: 0) }
        return places.map { $0.appendingPathComponent(port.app) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func state(_ port: Port) -> State {
        guard installedApp(port) != nil else { return .notInstalled }
        guard let had = recorded()[port.id] else { return .installed(nil) }
        return had == port.version ? .installed(had) : .update(from: had, to: port.version)
    }

    static func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The port's disk image, downloaded unless the file is already there, and checked: the size
    /// and the SHA-256 the catalog names, or it is deleted and refused.
    static func fetch(_ port: Port) -> Result<URL, Failure> {
        let fm = FileManager.default
        let image = folder.appendingPathComponent("\(port.id)-\(port.version).dmg")
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { return .failure(Failure(text: error.localizedDescription)) }
        if sha256(image) != port.sha256.lowercased() {
            try? fm.removeItem(at: image)
            guard let from = URL(string: port.url), from.scheme == "https" || from.scheme == "file" else {
                return .failure(Failure(text: "The catalog's address for \(port.title) is not one to download from."))
            }
            do { try Data(contentsOf: from).write(to: image, options: .atomic) }
            catch { return .failure(Failure(text: "The installer could not be downloaded: \(error.localizedDescription)")) }
        }
        let size = (try? fm.attributesOfItem(atPath: image.path)[.size] as? Int) ?? -1
        guard size == port.size, sha256(image) == port.sha256.lowercased() else {
            try? fm.removeItem(at: image)
            return .failure(Failure(text: "The file downloaded is not the installer MacGameFix's catalog names "
                                    + "(another size or SHA-256). It was deleted and not opened."))
        }
        return .success(image)
    }

    /// The installer, taken out of its checked disk image into MacGameFix's folder, with the image
    /// let go again. Where it is, ready to open.
    static func stage(_ port: Port) -> Result<URL, Failure> {
        let fm = FileManager.default
        let image: URL
        switch fetch(port) {
        case .success(let url): image = url
        case .failure(let why): return .failure(why)
        }
        let mount = folder.appendingPathComponent("mount-\(port.id)")
        let home = folder.appendingPathComponent(port.id)
        let staged = home.appendingPathComponent(port.installer)
        _ = NotProtonPlugins.command("/usr/bin/hdiutil", ["detach", mount.path, "-force"], [:])
        try? fm.removeItem(at: mount)
        try? fm.removeItem(at: home)
        do {
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
        } catch { return .failure(Failure(text: error.localizedDescription)) }
        let (attached, said) = NotProtonPlugins.command(
            "/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path], [:])
        guard attached == 0 else {
            try? fm.removeItem(at: mount)
            return .failure(Failure(text: "The installer's disk image could not be opened: \(said.split(separator: "\n").last.map(String.init) ?? "hdiutil failed")"))
        }
        defer {
            _ = NotProtonPlugins.command("/usr/bin/hdiutil", ["detach", mount.path, "-force"], [:])
            try? fm.removeItem(at: mount)
        }
        let inside = mount.appendingPathComponent(port.installer)
        guard fm.fileExists(atPath: inside.appendingPathComponent("Contents/MacOS").path) else {
            return .failure(Failure(text: "The disk image has no \(port.installer)."))
        }
        guard NotProtonPlugins.command("/usr/bin/ditto", [inside.path, staged.path], [:]).0 == 0 else {
            return .failure(Failure(text: "The installer could not be copied out of its disk image."))
        }
        return .success(staged)
    }

    /// The port's app started, as the Finder would.
    static func play(_ port: Port) {
        if let app = installedApp(port) { NSWorkspace.shared.open(app) }
    }

    /// One line for each port, for --native-installers-report and the tests.
    static func report() -> String {
        let lines = ports().map { port -> String in
            let state: String
            switch NativeInstallers.state(port) {
            case .notInstalled: state = "not installed"
            case .installed(let version): state = version.map { "installed, \($0)" } ?? "installed, by an installer MacGameFix did not open"
            case .update(let from, let to): state = "installed, \(from); \(to) to install"
            }
            return "\(port.id) \(port.version): \(state); the game is \(gameFolder(port) == nil ? "in no Steam library" : "in a Steam library")"
        }
        return (lines.isEmpty ? ["native installers: none"] : lines).joined(separator: "\n")
    }
}

/// What the Native tab shows of the ports with their own installer, and what its buttons do.
@MainActor
final class NativeInstallersModel: ObservableObject {
    @Published var ports: [NativeInstallers.Port] = []
    @Published var states: [String: NativeInstallers.State] = [:]
    @Published var games: [String: URL] = [:]
    @Published var busy: String?
    @Published var lines: [String: String] = [:]

    func refresh(extra: [URL]) {
        Task {
            let found = await Task.detached { () -> ([NativeInstallers.Port], [String: NativeInstallers.State], [String: URL]) in
                let ports = NativeInstallers.ports()
                var states: [String: NativeInstallers.State] = [:], games: [String: URL] = [:]
                for port in ports {
                    states[port.id] = NativeInstallers.state(port)
                    games[port.id] = NativeInstallers.gameFolder(port, extra: extra)
                }
                return (ports, states, games)
            }.value
            (ports, states, games) = found
        }
    }

    /// The installer downloaded, checked and opened; the version noted once it is open.
    func install(_ port: NativeInstallers.Port, extra: [URL]) {
        busy = port.id
        lines[port.id] = "Getting the installer…"
        Task {
            let staged = await Task.detached { NativeInstallers.stage(port) }.value
            switch staged {
            case .failure(let why):
                lines[port.id] = why.text
            case .success(let installer):
                if NSWorkspace.shared.open(installer) {
                    NativeInstallers.note(port)
                    lines[port.id] = "Its installer is open: it finds your copy and builds the game, in about 15 minutes. "
                        + "Look Again when it is done."
                } else {
                    lines[port.id] = "The installer could not be opened."
                }
            }
            busy = nil
            refresh(extra: extra)
        }
    }
}

struct NativeInstallerSection: View {
    let port: NativeInstallers.Port
    @ObservedObject var model: NativeInstallersModel
    let extra: [URL]

    private var state: NativeInstallers.State { model.states[port.id] ?? .notInstalled }

    private var count: String {
        switch state {
        case .notInstalled: return "Not installed"
        case .installed(let version): return version.map { "Installed \($0)" } ?? "Installed"
        case .update(_, let to): return "\(to) to install"
        }
    }

    private var action: String {
        switch state {
        case .notInstalled: return "Install \(port.version)…"
        case .installed(let version): return version == nil ? "Install \(port.version)…" : "Install Again…"
        case .update(_, let to): return "Update to \(to)…"
        }
    }

    var body: some View {
        Section {
            LabeledContent("Your copy") {
                Text(model.games[port.id]?.path ?? "Not in a Steam library; its installer also looks in CrossOver's and GOG's folders")
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                if let url = URL(string: port.page) { Link("By \(port.by)", destination: url).font(.caption) }
                Spacer()
                Button(action) { model.install(port, extra: extra) }
                    .disabled(model.busy != nil)
                    .help("Downloads this port's installer, checks it is the file MacGameFix's catalog names, and opens it. "
                          + "The installer is \(port.by)'s and is not notarized by Apple.")
                if state != .notInstalled {
                    Button("Play") { NativeInstallers.play(port) }
                }
            }
            if let line = model.lines[port.id] {
                Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            ImprovementHeader(symbol: "shippingbox", title: port.title, summary: port.summary, count: count)
        }
    }
}

/// The ports with their own installer, under the ones MacGameFix builds.
struct NativeInstallersView: View {
    @StateObject private var model = NativeInstallersModel()
    let extra: [URL]

    var body: some View {
        Group {
            if !model.ports.isEmpty {
                Section {
                    HStack {
                        Text("Ports that come with their own installer. MacGameFix downloads it, checks it is the file its "
                             + "catalog names, and opens it; the installer finds your Windows copy of the game and builds "
                             + "the port on this Mac. They are not notarized by Apple.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Look Again") { model.refresh(extra: extra) }.disabled(model.busy != nil)
                    }
                }
                ForEach(model.ports) { port in
                    NativeInstallerSection(port: port, model: model, extra: extra)
                }
            }
        }
        .onAppear { model.refresh(extra: extra) }
    }
}
