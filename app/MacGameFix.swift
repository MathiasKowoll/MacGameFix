// MacGameFix -- fixes that go into a game's own folder, and nothing else.
//
// Every fix this app carries lives in a game's own folder: a proxy DLL beside
// the game, and for one title registry keys in that game's own prefix. None of
// them changes CrossOver, so they work with CrossOver as CodeWeavers ships it,
// with CrossOver Preview, and with a Steam Play tool such as NotProton.
//
// The app decides nothing about a fix. The installers under Resources are the
// same files fixes/ holds, and they answer every question about a game folder
// themselves: --status says what is there, a plain run installs, --restore
// undoes. This file is the window: it finds the folders, asks, and shows the
// answers. Core.swift runs the installers; Automation.swift keeps marked fixes
// applied in the background and takes newer fixes from the releases.
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
    @Published var busy = false
    @Published var status = ""

    @Published var games: [Game] = []
    @Published var catalogVersion = 0
    @Published var settings = AutoSettings.load()
    @Published var agentOn = LaunchAgent.enabled
    @Published var events: [AgentEvent] = []
    @Published var updateLine = ""
    var resources = URL(fileURLWithPath: ".")

    private let extraKey = "extraFolders"

    init() {
        loadCatalog()
        refreshEvents()
        // A moved app leaves the agent pointing at the old place.
        if agentOn, let me = Bundle.main.executablePath, LaunchAgent.installedProgram != me {
            try? LaunchAgent.enable(executable: me)
        }
    }

    /// The catalog in use: the bundle's, or a newer verified download.
    func loadCatalog() {
        let (dir, manifest) = Catalog.active()
        resources = dir
        games = Catalog.games(in: dir)
        catalogVersion = manifest?.version ?? 0
    }

    func refreshEvents() {
        let state = AgentState.load()
        events = state.events.reversed()
        if !state.lastUpdate.isEmpty { updateLine = state.lastUpdate }
    }

    // MARK: Automatic

    func isKept(_ hit: Hit) -> Bool {
        settings.kept.contains { $0.name == hit.game.name && $0.folder == hit.folder.path }
    }

    func setKept(_ hit: Hit, _ on: Bool) {
        settings.kept.removeAll { $0.name == hit.game.name && $0.folder == hit.folder.path }
        if on {
            settings.kept.append(KeptGame(name: hit.game.name, folder: hit.folder.path,
                                          prefix: hit.game.needsPrefix ? hit.prefix?.path.path : nil))
        }
        settings.save()
    }

    func setAgent(_ on: Bool) {
        if on, let me = Bundle.main.executablePath {
            do { try LaunchAgent.enable(executable: me) } catch { note("Could not start the agent: \(error.localizedDescription)") }
        } else {
            LaunchAgent.disable()
        }
        agentOn = LaunchAgent.enabled
    }

    func setUpdates(_ on: Bool) {
        settings.updates = on
        settings.save()
    }

    func checkForFixes() {
        guard !busy else { return }
        busy = true
        status = "Looking for new fixes…"
        Task {
            do { updateLine = try await Updater.update() } catch { updateLine = "Could not update: \(error.localizedDescription)" }
            loadCatalog()
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
            let (libs, found) = await Task.detached { () -> ([URL], [Hit]) in
                let fm = FileManager.default
                let libs = Libraries.all(extra: extra)
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
                                h.prefixes = Libraries.prefixes(for: folder)
                                h.prefix = h.prefixes.first
                            }
                            hits.append(h)
                        }
                    }
                }
                hits.sort { $0.game.name.lowercased() < $1.game.name.lowercased() }
                return (libs, hits)
            }.value
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
                    else { h.outcome = install ? "Installed" : "Removed" }
                    h.selected = false
                    hits[i] = h
                }
            }
            busy = false
            status = failed == 0 ? "Done: \(done) game(s)." : "Done, \(failed) of \(done) need attention."
        }
    }
}

// MARK: - Interface

struct HitRow: View {
    @Binding var hit: Hit
    let busy: Bool
    let kept: Bool
    let onKeep: (Bool) -> Void

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
                        Text(o).font(.caption).foregroundStyle(o.hasPrefix("Installed") || o.hasPrefix("Removed") ? .green : .orange)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("MacGameFix").font(.title2.bold())
                Text("Fixes that go into a game's own folder. Nothing here changes CrossOver, so they work with "
                     + "CrossOver as it ships, CrossOver Preview, and Steam Play tools such as NotProton. "
                     + "Quit a game before installing or removing its fix.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                List($model.hits) { $hit in
                    HitRow(hit: $hit, busy: model.busy, kept: model.isKept(hit)) { model.setKept(hit, $0) }
                }
                .frame(minHeight: 260)
            }

            AutomaticView(model: model)

            DisclosureGroup("Folders searched (\(model.libraries.count))") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.libraries, id: \.self) { lib in
                        HStack {
                            Text(lib.path).font(.caption).lineLimit(1).truncationMode(.middle)
                            if model.extraFolders.contains(lib) {
                                Button("Remove") { model.removeExtra(lib) }.font(.caption).disabled(model.busy)
                            }
                        }
                    }
                }
            }

            DisclosureGroup("Log") {
                ScrollView {
                    Text(model.log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 160)
            }

            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout)
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 560)
        .onAppear { model.scan() }
    }
}

/// The background part of the window: the agent, the updates, and what the
/// agent did, with a way to report a failure.
struct AutomaticView: View {
    @ObservedObject var model: Model

    var body: some View {
        DisclosureGroup("Automatic") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Keep the marked fixes applied in the background", isOn: Binding(
                    get: { model.agentOn }, set: { model.setAgent($0) }))
                Text("An agent looks at each game marked “Keep it applied” every two minutes. When Steam updates "
                     + "or verifies the game and the fix is gone, it installs it again, once the game is closed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Get new fixes from GitHub", isOn: Binding(
                    get: { model.settings.updates }, set: { model.setUpdates($0) }))
                HStack {
                    Text("Fixes catalog \(model.catalogVersion)").font(.caption).foregroundStyle(.secondary)
                    if !model.updateLine.isEmpty {
                        Text("— " + model.updateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Check for New Fixes") { model.checkForFixes() }.disabled(model.busy)
                    Button("Refresh") { model.refreshEvents() }
                }
                if !model.events.isEmpty {
                    ForEach(model.events.prefix(8)) { e in
                        HStack(alignment: .firstTextBaseline) {
                            Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(e.game.isEmpty ? e.message : "\(e.game): \(e.message)")
                                .font(.caption).foregroundStyle(e.failed ? .orange : .primary)
                            Spacer()
                            if let r = e.report, let url = URL(string: r) {
                                Button("Report on GitHub…") { NSWorkspace.shared.open(url) }.font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

struct MacGameFixApp: App {
    var body: some Scene {
        WindowGroup("MacGameFix") { ContentView() }
            .windowResizability(.contentMinSize)
    }
}

/// One binary, several ways to run: the window; --agent, which the LaunchAgent
/// starts; and, for the tests and the release, --agent-once, --update-from,
/// --make-catalog and --new-signing-key, which do one thing and exit.
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
        if args.contains("--agent") { Agent.runForever() }
        if args.contains("--agent-once") {
            wait {
                for e in await Agent.pass(notify: false) {
                    print("\(e.failed ? "FAILED" : "ok") \(e.game): \(e.message)")
                    if let r = e.report { print("report \(r)") }
                }
                return 0
            }
        }
        if let source = value("--update-from") {
            let key = value("--pubkey") ?? Updater.publicKey
            wait {
                do {
                    print(try await Updater.update(from: URL(fileURLWithPath: source), publicKey: key))
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
            guard let manifest = Catalog.manifest(in: resources) else { print("no catalog.json"); exit(1) }
            do {
                try Updater.makeRelease(from: resources, to: URL(fileURLWithPath: out), keyFile: URL(fileURLWithPath: key),
                                        version: manifest.version, minimumApp: manifest.minimumApp,
                                        names: manifest.files.keys.sorted())
                print("catalog \(manifest.version) written to \(out)")
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
