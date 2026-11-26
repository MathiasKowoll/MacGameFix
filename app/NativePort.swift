// A native port, built on this Mac from the owner's copy of the game.
//
// Batman: Arkham Asylum GOTY for the Mac is Feral's port of 2011, a 32-bit Intel program:
// macOS stopped running those with Catalina, and Rosetta never translated them. The port
// here is a static recompilation of that program to arm64 (the BMAA-Recomp sources, with
// Recomp-Framework and DecompRecomp beside them): the game's own executable is read where
// Steam keeps it, translated to C and compiled, all on this Mac. MacGameFix carries none of
// it and nothing of the game: it finds the game, downloads the sources from GitHub (or uses
// a folder the user chose), runs the sources' own build.sh, shows how far it is, and starts
// what it built.
//
// The sources say where they are in steps: a line "== 3/5 translating ..." for each, and a
// line "!! ..." for what stopped them (a missing tool, with the command that installs it).
//
// BioShock Infinite for the Mac (Aspyr's 2013 port, also 32-bit Intel) is the second port. Its
// sources (bmbowdish/bioshock-infinite-recomp) carry their own copy of the recompiler, so they
// are one repository, and they build in two commands: setup.sh, then build_app.sh. They number
// their steps "1/3 ..." without the "== ", and what they build is an app, started with open.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@MainActor
final class NativePort: ObservableObject {
    /// What differs between the ports: where the game is, where the sources are, what builds and what starts.
    struct Config {
        let title: String
        let summary: String
        /// The game's folder in a Steam library, its application inside, and the program in that.
        let gameFolder: String
        let gameApp: String
        let gameExecutable: String
        let sourcesKey: String
        /// The folder name of the sources, tried in ~/Development, in ~ and in the downloads.
        let sourcesFolder: String
        let repositories: [(folder: String, url: String, branch: String?)]
        /// Files the sources' top folder has when it is the port's.
        let sourceFiles: [String]
        /// What the build leaves, relative to the sources.
        let builtPath: String
        let chooseMessage: String
        /// Scripts to run in the sources' folder, each given the game's application.
        let buildScripts: [String]
        /// The build's progress lines carry a "== " in front (Batman) or not (BioShock).
        let stepPrefix: String
        /// A script that starts the port, or nil when the built app is opened.
        let playScript: String?
        let needsSteamRunning: Bool
        let launcherNote: String
        let footer: String
    }

    static let batman = NativePort(Config(
        title: "Batman: Arkham Asylum, native",
        summary: "The Mac version is a 32-bit Intel program that macOS no longer runs. This builds an Apple silicon program from your own copy.",
        gameFolder: "Batman Arkham Asylum GOTY",
        gameApp: "Batman Arkham Asylum GOTY.app",
        gameExecutable: "Batman Arkham Asylum GOTY",
        sourcesKey: "nativePort.batman.sources",
        sourcesFolder: "BMAA-Recomp",
        repositories: [
            ("BMAA-Recomp", "https://github.com/MathiasKowoll/BMAA-Recomp.git", nil),
            ("Recomp-Framework", "https://github.com/MathiasKowoll/Recomp-Framework.git", "mac32-ports"),
            ("DecompRecomp", "https://github.com/MathiasKowoll/DecompRecomp.git", nil),
        ],
        sourceFiles: ["build.sh", "play.sh"],
        builtPath: "build/dr-bmaa",
        chooseMessage: "The BMAA-Recomp folder, with Recomp-Framework and DecompRecomp beside it.",
        buildScripts: ["build.sh"],
        stepPrefix: "== ",
        playScript: "play.sh",
        needsSteamRunning: true,
        launcherNote: "Steam's Play starts it too. Keep the game's Launch Options in Steam empty.",
        footer: "Built on this Mac from the game Steam installed; MacGameFix carries nothing of the game. The build needs Apple's command line tools and FFmpeg (brew install ffmpeg pkg-config)."))

    static let bioshock = NativePort(Config(
        title: "BioShock Infinite, native",
        summary: "The Mac version is a 32-bit Intel program that macOS no longer runs. This builds an Apple silicon app from your own copy.",
        gameFolder: "BioShock Infinite",
        gameApp: "BioShock3.app",
        gameExecutable: "BioShock3",
        sourcesKey: "nativePort.bioshock.sources",
        sourcesFolder: "bioshock-infinite-recomp",
        repositories: [
            ("bioshock-infinite-recomp", "https://github.com/bmbowdish/bioshock-infinite-recomp.git", nil),
        ],
        sourceFiles: ["setup.sh", "build_app.sh"],
        builtPath: "build/BioShockInfiniteRecomp.app",
        chooseMessage: "The bioshock-infinite-recomp folder.",
        buildScripts: ["setup.sh", "build_app.sh"],
        stepPrefix: "",
        playScript: nil,
        needsSteamRunning: false,
        launcherNote: "The app finds your copy of the game by itself. Only the Steam Mac release (Aspyr) fits: the build checks it first.",
        footer: "Built on this Mac from the game Steam installed; MacGameFix carries nothing of the game, and the app that is built is for your own use only. The build needs Apple's command line tools, about 3 GB of free space and, for the game's videos, FFmpeg (brew install ffmpeg pkg-config)."))

    let config: Config
    init(_ config: Config) { self.config = config }

    @Published var game: URL?
    @Published var sources: URL?
    @Published var building = false
    @Published var step = ""
    @Published var progress: Double?
    @Published var failure = ""
    @Published var built = false

    /// The sources in use are the ones Get Sources downloaded.
    var usesDownloads: Bool { sources?.path.hasPrefix(Self.downloads.path) ?? false }

    var state: String {
        if building { return "Building" }
        if game == nil { return "Game not found" }
        if sources == nil { return "No sources" }
        return built ? "Built" : "Not built"
    }

    /// Finds the game in the Steam libraries and the sources where they were last chosen, or
    /// in the folders they are usually cloned to.
    func look(extra: [URL] = []) {
        let fm = FileManager.default
        game = Libraries.all(extra: extra)
            .map { $0.appendingPathComponent(config.gameFolder).appendingPathComponent(config.gameApp) }
            .first { fm.fileExists(atPath: $0.appendingPathComponent("Contents/MacOS/" + config.gameExecutable).path) }
        var candidates: [URL] = []
        if let saved = UserDefaults.standard.string(forKey: config.sourcesKey) { candidates.append(URL(fileURLWithPath: saved)) }
        candidates.append(Paths.home.appendingPathComponent("Development/" + config.sourcesFolder))
        candidates.append(Paths.home.appendingPathComponent(config.sourcesFolder))
        candidates.append(Self.downloads.appendingPathComponent(config.sourcesFolder))
        sources = candidates.first { isSources($0) }
        built = sources.map { fm.fileExists(atPath: $0.appendingPathComponent(config.builtPath).path) } ?? false
    }

    func isSources(_ folder: URL) -> Bool {
        config.sourceFiles.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    func chooseSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = config.chooseMessage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard isSources(url) else {
            failure = "That folder has no " + config.sourceFiles.joined(separator: " and ") + ": it is not the port's sources."
            return
        }
        UserDefaults.standard.set(url.path, forKey: config.sourcesKey)
        failure = ""
        look()
    }

    /// Where Get Sources puts them: the port and the two projects it is built with, side by side.
    static var downloads: URL { Paths.home.appendingPathComponent("Library/Application Support/MacGameFix/NativePorts") }

    /// Clones the three repositories, or brings the ones already there up to date. Sources the
    /// user chose or keeps elsewhere are left alone: this only ever writes under `downloads`.
    func getSources() {
        guard !building else { return }
        building = true
        failure = ""
        progress = 0
        Task {
            try? FileManager.default.createDirectory(at: Self.downloads, withIntermediateDirectories: true)
            var ok = true
            for (i, repo) in config.repositories.enumerated() where ok {
                step = "Getting " + repo.folder
                progress = Double(i) / Double(config.repositories.count)
                let dest = Self.downloads.appendingPathComponent(repo.folder)
                var args: [String]
                if FileManager.default.fileExists(atPath: dest.appendingPathComponent(".git").path) {
                    args = ["-C", dest.path, "pull", "--ff-only", "--quiet"]
                } else {
                    args = ["clone", "--quiet", "--depth", "1"]
                    if let branch = repo.branch { args += ["--branch", branch] }
                    args += [repo.url, dest.path]
                }
                let status = await runStreaming("/usr/bin/git", args,
                                                environment: ["PATH": Self.toolPath, "GIT_TERMINAL_PROMPT": "0"]) { _ in }
                if status != 0 {
                    ok = false
                    failure = repo.folder + " could not be downloaded from " + repo.url + " (git status \(status))."
                }
            }
            building = false
            progress = nil
            step = ""
            if ok { UserDefaults.standard.set(Self.downloads.appendingPathComponent(config.sourcesFolder).path, forKey: config.sourcesKey) }
            look()
        }
    }

    /// The tools the build looks for are Homebrew's (pkg-config, FFmpeg) and Apple's.
    private static var toolPath: String { "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" }

    func build() {
        guard let game, let sources, !building else { return }
        building = true
        failure = ""
        step = "Starting"
        progress = 0
        Task {
            // Each script is run in turn and given the game's application; the first to stop ends the build.
            var status: Int32 = 0
            for script in config.buildScripts where status == 0 {
                status = await runStreaming("/bin/bash", [sources.appendingPathComponent(script).path, game.path],
                                            environment: ["PATH": Self.toolPath]) { line in
                    Task { @MainActor in self.took(line) }
                }
            }
            building = false
            progress = nil
            if status != 0 && failure.isEmpty { failure = "The build stopped (status \(status)). " + step }
            look()
            if status == 0 { step = "" }
        }
    }

    /// "== 3/5 translating the game's code to C": the step and how far; "!! ...": why it stopped.
    private func took(_ line: String) {
        if line.hasPrefix("!! ") { failure = String(line.dropFirst(3)); return }
        // The BioShock sources say what stopped them without the "!! ": a MISSING item, a failed
        // version check or a failed build. The last such line is what the window shows.
        if config.stepPrefix.isEmpty {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("MISSING ") || t.contains("FAILED") || t.hasSuffix("failed") || t.hasPrefix("build failed")
                || t.hasPrefix("translation failed") || t.hasPrefix("the app was not produced") {
                failure = t
                return
            }
        }
        guard line.hasPrefix(config.stepPrefix) else { return }
        let rest = line.dropFirst(config.stepPrefix.count)
        // Without a marker only a line that starts "2/3 " is a step; the rest is the build talking.
        if config.stepPrefix.isEmpty {
            let first = rest.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            let frac = first.split(separator: "/")
            guard frac.count == 2, Int(frac[0]) != nil, Int(frac[1]) != nil else { return }
        }
        let parts = rest.split(separator: " ", maxSplits: 1)
        if let first = parts.first, parts.count == 2 {
            let frac = first.split(separator: "/")
            if frac.count == 2, let n = Double(frac[0]), let of = Double(frac[1]), of > 0 {
                progress = (n - 1) / of
                step = String(parts[1]).prefix(1).uppercased() + String(parts[1]).dropFirst()
                return
            }
        }
        step = String(rest)
    }

    /// Starts the port. The game asks Steam who owns it, so Steam has to be running: it is
    /// opened when it is not, and the game is started once it is.
    func play() {
        guard let sources, built else { return }
        if config.playScript == nil {
            failure = ""
            NSWorkspace.shared.open(sources.appendingPathComponent(config.builtPath))
            return
        }
        let steamRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.valvesoftware.steam" }
        if config.needsSteamRunning && !steamRunning {
            NSWorkspace.shared.open(URL(string: "steam://open/main")!)
            failure = "Steam was not running and has been opened. Press Play again once it is ready: the game asks Steam who owns it."
            return
        }
        failure = ""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [sources.appendingPathComponent(config.playScript ?? "play.sh").path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.toolPath
        env["BMAA_FPS"] = ""          // no frame counter for someone who only plays
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { failure = "The game could not be started: \(error.localizedDescription)" }
    }
}

/// The port's section in Improvements: where the game and the sources are, the build, and Play.
struct NativePortSection: View {
    @ObservedObject var port: NativePort
    let extra: [URL]

    var body: some View {
        Section {
            LabeledContent("Game") {
                Text(port.game?.deletingLastPathComponent().path ?? "Not found in a Steam library. Install the Mac version from Steam.")
                    .foregroundStyle(port.game == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
            }
            LabeledContent("Sources") {
                HStack {
                    Text(port.sources?.path ?? "Not found")
                        .foregroundStyle(port.sources == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    // Sources the user keeps elsewhere are theirs to update: the button is for the downloaded ones.
                    if port.sources == nil || port.usesDownloads {
                        Button(port.sources == nil ? "Get Sources" : "Update") { port.getSources() }
                            .controlSize(.small).disabled(port.building)
                            .help("Downloads the port's sources from GitHub, or brings the downloaded ones up to date, in MacGameFix's own folder in Application Support.")
                    }
                    Button("Choose…") { port.chooseSources() }.controlSize(.small).disabled(port.building)
                }
            }
            if port.building {
                HStack {
                    ProgressView(value: port.progress ?? 0).frame(width: 160)
                    Text(port.step).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !port.failure.isEmpty {
                Label(port.failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack {
                if port.built {
                    // The build leaves a launcher in the place of the game's program, so Steam
                    // needs nothing set. A launch option left from another runner breaks it:
                    // Steam for Mac runs its first word as the program (OS Error 260).
                    Text(port.config.launcherNote)
                        .font(.caption).foregroundStyle(.secondary)
                        .help("The build puts a small launcher where the game's program was and keeps the original beside it. Verify Integrity in Steam puts the original back: build again after it.")
                }
                Spacer()
                Button(port.built ? "Build Again" : "Build") { port.build() }
                    .help("Translates the game's own program and compiles it on this Mac. The first time takes several minutes; after an update of the sources, only what changed.")
                    .disabled(port.building || port.game == nil || port.sources == nil)
                Button("Play") { port.play() }
                    .keyboardShortcut(port.built ? .defaultAction : nil)
                    .disabled(port.building || !port.built)
            }
        } header: {
            ImprovementHeader(symbol: "cpu", title: port.config.title,
                              summary: port.config.summary,
                              count: port.state)
        } footer: {
            Text(port.config.footer)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { if !port.building { port.look(extra: extra) } }
    }
}
