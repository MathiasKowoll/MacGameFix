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
    /// What the agent knows of each marked game.
    @Published var keptLines: [KeptLine] = []
    /// Only the games that need the user; the menu bar opens the window so.
    @Published var onlyReview = CommandLine.arguments.contains("--review")
    var resources = URL(fileURLWithPath: ".")

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
        catalogVersion = manifest?.version ?? 0
    }

    func refreshEvents() {
        let state = AgentState.load()
        events = state.events.reversed()
        keptLines = KeptLine.all(settings: settings, state: state)
        if !state.lastUpdate.isEmpty { updateLine = state.lastUpdate }
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

/// The background part of the window: the agent, the updates, and what the
/// agent did, with a way to report a failure.
struct AutomaticView: View {
    @ObservedObject var model: Model
    @State private var open = false

    var body: some View {
        DisclosureGroup("Automatic", isExpanded: $open) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.keptLines.filter { $0.word == "Folder not found" }, id: \.key) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(line.name): marked, and its folder is gone (\(line.detail ?? ""))")
                            .font(.caption).foregroundStyle(.orange).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Stop Keeping It") { model.forget(line) }.font(.caption)
                    }
                }
                Toggle("Run in the background, from the menu bar", isOn: Binding(
                    get: { model.agentOn }, set: { model.setAgent($0) }))
                Text("MacGameFix stays in the menu bar and starts when you log in. Every two minutes it looks at "
                     + "each game marked “Keep it applied”: when Steam updates or verifies the game and the fix is "
                     + "gone, it installs it again, once the game is closed. Its menu says what it keeps and what "
                     + "it did.")
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
        .onAppear { open = model.keptLines.contains { $0.condition == .review } }
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
/// --agent-once, --menu-report, --runtime-report, --update-from, --make-catalog
/// and --new-signing-key, which do one thing and exit.
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
