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
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@MainActor
final class NativePort: ObservableObject {
    static let batman = NativePort()

    /// The game's folder in a Steam library, and its application inside.
    static let gameFolder = "Batman Arkham Asylum GOTY"
    static let gameApp = "Batman Arkham Asylum GOTY.app"
    private static let sourcesKey = "nativePort.batman.sources"

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
            .map { $0.appendingPathComponent(Self.gameFolder).appendingPathComponent(Self.gameApp) }
            .first { fm.fileExists(atPath: $0.appendingPathComponent("Contents/MacOS/" + Self.gameFolder).path) }
        var candidates: [URL] = []
        if let saved = UserDefaults.standard.string(forKey: Self.sourcesKey) { candidates.append(URL(fileURLWithPath: saved)) }
        candidates.append(Paths.home.appendingPathComponent("Development/BMAA-Recomp"))
        candidates.append(Paths.home.appendingPathComponent("BMAA-Recomp"))
        candidates.append(Self.downloads.appendingPathComponent("BMAA-Recomp"))
        sources = candidates.first { Self.isSources($0) }
        built = sources.map { fm.isExecutableFile(atPath: $0.appendingPathComponent("build/dr-bmaa").path) } ?? false
    }

    static func isSources(_ folder: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: folder.appendingPathComponent("build.sh").path)
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("play.sh").path)
    }

    func chooseSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "The BMAA-Recomp folder, with Recomp-Framework and DecompRecomp beside it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard Self.isSources(url) else {
            failure = "That folder has no build.sh and play.sh: it is not the port's sources."
            return
        }
        UserDefaults.standard.set(url.path, forKey: Self.sourcesKey)
        failure = ""
        look()
    }

    /// Where Get Sources puts them: the port and the two projects it is built with, side by side.
    static var downloads: URL { Paths.home.appendingPathComponent("Library/Application Support/MacGameFix/NativePorts") }
    static let repositories: [(folder: String, url: String, branch: String?)] = [
        ("BMAA-Recomp", "https://github.com/MathiasKowoll/BMAA-Recomp.git", nil),
        ("Recomp-Framework", "https://github.com/MathiasKowoll/Recomp-Framework.git", "mac32-ports"),
        ("DecompRecomp", "https://github.com/MathiasKowoll/DecompRecomp.git", nil),
    ]

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
            for (i, repo) in Self.repositories.enumerated() where ok {
                step = "Getting " + repo.folder
                progress = Double(i) / Double(Self.repositories.count)
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
            if ok { UserDefaults.standard.set(Self.downloads.appendingPathComponent("BMAA-Recomp").path, forKey: Self.sourcesKey) }
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
            let status = await runStreaming("/bin/bash", [sources.appendingPathComponent("build.sh").path, game.path],
                                            environment: ["PATH": Self.toolPath]) { line in
                Task { @MainActor in self.took(line) }
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
        guard line.hasPrefix("== ") else { return }
        let rest = line.dropFirst(3)
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
        let steamRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.valvesoftware.steam" }
        if !steamRunning {
            NSWorkspace.shared.open(URL(string: "steam://open/main")!)
            failure = "Steam was not running and has been opened. Press Play again once it is ready: the game asks Steam who owns it."
            return
        }
        failure = ""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [sources.appendingPathComponent("play.sh").path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.toolPath
        env["BMAA_FPS"] = ""          // no frame counter for someone who only plays
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { failure = "The game could not be started: \(error.localizedDescription)" }
    }
}

/// The port's section in the Native tab: where the game and the sources are, the build, and Play.
struct NativePortSection: View {
    @ObservedObject var port = NativePort.batman
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
                    Text("Steam's Play starts it too. Keep the game's Launch Options in Steam empty.")
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
            ImprovementHeader(symbol: "cpu", title: "Batman: Arkham Asylum, native",
                              summary: "The Mac version is a 32-bit Intel program that macOS no longer runs. This builds an Apple silicon program from your own copy.",
                              count: port.state)
        } footer: {
            Text("Built on this Mac from the game Steam installed; MacGameFix carries nothing of the game. The build needs Apple's command line tools and FFmpeg (brew install ffmpeg pkg-config).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { if !port.building { port.look(extra: extra) } }
    }
}

/// Native: the games MacGameFix builds for this Mac from the owner's own copy, one section each.
/// They need no CrossOver, which is why they are not in Improvements.
struct NativeBuildsView: View {
    @ObservedObject var model: Model

    var body: some View {
        Form {
            Section {
                Text("Games built for Apple silicon on this Mac, from the copy you own. They run without CrossOver. "
                     + "MacGameFix carries nothing of any game: it gets the port's sources, builds, and starts what it built.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            NativePortSection(extra: model.extraFolders)
        }
        .formStyle(.grouped)
    }
}
