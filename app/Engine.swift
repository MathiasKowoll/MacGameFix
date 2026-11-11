// The Wine modules: the one part of MacGameFix that changes CrossOver itself.
//
// Patched Wine files (engine/README.md) go into a CrossOver app or a NotProton
// runner. They are two improvements, each turned on and off on its own in the
// Improvements tab: the DualSense's controls, and Rosetta's CPU for copy
// protection. As with the game fixes, the app decides nothing: engine-modules.sh,
// carried in the catalog with the modules, answers --status, installs on a plain
// run and undoes with --restore, for one improvement with --part. This file finds
// the places they can go and runs it.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

/// A CrossOver the modules can go into: an app, or a NotProton runner.
struct EngineTarget: Identifiable, Hashable {
    /// The folder that holds lib/wine.
    let root: URL
    /// CrossOver's build, as CFBundleVersion and the runner folders name it.
    let build: String
    /// "CrossOver Preview 20261006", or "NotProton runner crossover-27.0.0.41069-fex".
    let name: String
    /// The app, for a CrossOver app; nil for a runner.
    let app: URL?
    /// Whether it has the FEX (arm64) side as well as the Intel one.
    let fex: Bool
    /// How people tell the release apart: "Preview 20261006", or "26.3" for a stable one.
    var release: String = ""

    var id: String { root.path }
    /// The folder with symlinks resolved, as the settings keep it: /var and
    /// /private/var are one place.
    var key: String { root.resolvingSymlinksInPath().path }
}

/// One improvement the Wine modules make, installed and removed on its own
/// (engine-modules.sh --part).
enum EnginePart: String, CaseIterable, Identifiable {
    case controls, rosetta

    var id: String { rawValue }
    var argument: String { "--part=\(rawValue)" }

    var title: String {
        switch self {
        case .controls: return "DualSense controllers"
        case .rosetta: return "Copy protection under Rosetta"
        }
    }

    /// What it does, in one line under its title.
    var summary: String {
        switch self {
        case .controls: return "Haptics, adaptive triggers, Bluetooth as a cable, and XInput's vibration."
        case .rosetta: return "CPU compatibility under Rosetta, plus corrected timers and guarded exception acceleration for FH6 (WIP) on Preview 41073."
        }
    }

    /// The longer account, for the section's help.
    var detail: String {
        switch self {
        case .controls:
            return "Patched winebus, hidclass, xinput, mmdevapi, setupapi, xaudio2 and winecoreaudio, on both sides. "
                + "Games find the pad's haptic output, set its trigger effects and rumble it as on Windows; "
                + "Game Feel sets the options per game."
        case .rosetta:
            return "Paired ntdll.so and ntdll.dll on Preview 41073; ntdll.so on older supported builds. It runs a cpuid Rosetta skips after self-modifying code, "
                + "emulates CLWB, RDPID and hardware breakpoints, and reports faults as Windows does. "
                + "Preview 41073 also includes corrected relative timers. FH6 exception acceleration remains opt-in and game-build guarded; its fix applies the options. Other builds retain their existing CPU fixes."
        }
    }

    /// Its symbol beside the title.
    var symbol: String {
        switch self {
        case .controls: return "gamecontroller"
        case .rosetta: return "cpu"
        }
    }

    /// The one thing to know under its switches.
    var footer: String {
        switch self {
        case .controls: return "Game Feel sets its options per game. Quit a CrossOver's games before changing it."
        case .rosetta: return "Intel side only. The CPUID bits a game asks for come with that game's fix."
        }
    }

    /// The short name in a status line or a log.
    var short: String {
        switch self {
        case .controls: return "controllers"
        case .rosetta: return "Rosetta CPU"
        }
    }

    /// Whether a build of the modules carries this improvement, from its file list.
    func carried(by build: EngineBuild) -> Bool {
        switch self {
        case .controls: return build.files.keys.contains { $0.hasSuffix("unix/winecoreaudio.so") }
        case .rosetta: return build.files.keys.contains("x86_64-unix/ntdll.so")
        }
    }
}

/// The installer's word for one CrossOver.
enum EngineState: Equatable {
    case unknown, installed, outdated, half, absent, noModules

    var label: String {
        switch self {
        case .unknown: return "…"
        case .installed: return "Installed"
        case .outdated: return "Update available"
        case .half: return "Partly installed"
        case .absent: return "Not installed"
        case .noModules: return "Not available for this build yet"
        }
    }

    var color: Color {
        switch self {
        case .installed: return .green
        case .outdated, .half: return .orange
        default: return .secondary
        }
    }
}

/// One CrossOver build the catalog carries modules for, from engine-modules.json.
struct EngineBuild: Decodable {
    let build: String
    let crossover: String
    let wine: String
    let files: [String: String]
}

enum Engine {
    static let script = "engine-modules.sh"
    /// CrossOver's own files, kept while the modules are in.
    static var backups: URL { Paths.support.appendingPathComponent("engine-backup") }
    /// NotProton's folder, which holds its runners.
    static var notproton: URL { Paths.home.appendingPathComponent("Library/Application Support/notproton") }

    /// A value of a CrossOver .conf file, written as "Key" = "value".
    static func confValue(_ key: String, in conf: String) -> String? {
        for line in conf.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("\"\(key)\"") else { continue }
            let parts = t.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 4 { return String(parts[3]) }
        }
        return nil
    }

    static func builds(in catalog: URL) -> [EngineBuild] {
        struct Table: Decodable { let builds: [EngineBuild] }
        let data = (try? Data(contentsOf: catalog.appendingPathComponent("engine-modules.json"))) ?? Data()
        return (try? JSONDecoder().decode(Table.self, from: data))?.builds ?? []
    }

    /// Every CrossOver app in /Applications and ~/Applications, and every
    /// NotProton runner.
    /// The release, from the BuildTag CodeWeavers writes into every CrossOver's
    /// etc/CrossOver.conf ("cxpreview-20261006-rc2"); a stable one by its version.
    static func release(of root: URL, build: String) -> String {
        let conf = (try? String(contentsOf: root.appendingPathComponent("etc/CrossOver.conf"), encoding: .utf8)) ?? ""
        if let tag = confValue("BuildTag", in: conf), tag.hasPrefix("cxpreview-") {
            return "Preview " + tag.dropFirst("cxpreview-".count).prefix(8)
        }
        let parts = build.split(separator: ".")
        return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : build
    }

    static func targets() -> [EngineTarget] {
        let fm = FileManager.default
        var found: [EngineTarget] = []
        func wine(_ root: URL) -> Bool {
            fm.fileExists(atPath: root.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so").path)
        }
        func fex(_ root: URL) -> Bool {
            fm.fileExists(atPath: root.appendingPathComponent("lib/wine/aarch64-unix").path)
        }
        for dir in [URL(fileURLWithPath: "/Applications"), Paths.home.appendingPathComponent("Applications")] {
            for app in ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where app.pathExtension == "app" && app.lastPathComponent.lowercased().hasPrefix("crossover") {
                let root = app.appendingPathComponent("Contents/SharedSupport/CrossOver")
                let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
                guard wine(root), let build = info?["CFBundleVersion"] as? String else { continue }
                let release = release(of: root, build: build)
                found.append(EngineTarget(root: root, build: build, name: "CrossOver \(release)", app: app,
                                          fex: fex(root), release: release))
            }
        }
        let runners = notproton.appendingPathComponent("runners")
        for runner in ((try? fm.contentsOfDirectory(at: runners, includingPropertiesForKeys: nil)) ?? [])
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where runner.lastPathComponent.hasPrefix("crossover-") {
            let root = runner.appendingPathComponent("CrossOver")
            guard wine(root) else { continue }
            let build = String(runner.lastPathComponent.dropFirst("crossover-".count).split(separator: "-").first ?? "")
            let release = release(of: root, build: build)
            found.append(EngineTarget(root: root, build: build, name: "NotProton runner · CrossOver \(release)",
                                      app: nil, fex: fex(root), release: release))
        }
        // Several copies of one CrossOver (CrossOver.app and a patched copy, or two runners of one
        // release) are told apart by their app or runner folder.
        let names = found.map(\.name)
        for i in found.indices where names.filter({ $0 == names[i] }).count > 1 {
            let file = found[i].app?.lastPathComponent ?? found[i].root.deletingLastPathComponent().lastPathComponent
            found[i] = EngineTarget(root: found[i].root, build: found[i].build, name: "\(found[i].name) (\(file))",
                                    app: found[i].app, fex: found[i].fex, release: found[i].release)
        }
        return found
    }

    static func status(_ target: EngineTarget, part: EnginePart? = nil, catalog: URL) async -> EngineState {
        let out = Collected()
        let code = await run(target, part: part, catalog: catalog, ["--status"]) { out.add($0) }
        let word = out.all.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { ["installed", "outdated", "half", "absent", "nomodules"].contains($0) }
        guard code == 0, let word else { return .unknown }
        switch word {
        case "installed": return .installed
        case "outdated": return .outdated
        case "half": return .half
        case "nomodules": return .noModules
        default: return .absent
        }
    }

    /// Runs engine-modules.sh on one CrossOver, under the lock the game
    /// installers take, so it never runs beside one of them.
    static func run(_ target: EngineTarget, part: EnginePart? = nil, catalog: URL, _ extra: [String],
                    onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        let lock = InstallLock()
        defer { lock.release() }
        let script = catalog.appendingPathComponent(Self.script).path
        return await runStreaming("/bin/bash", [script, target.root.path] + extra + (part.map { [$0.argument] } ?? []),
                                  environment: ["MGVF_ENGINE_BACKUP": backups.path], onLine: onLine)
    }

    static func resolved(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }

    /// Whether a Wine of this CrossOver runs: its processes name its folder.
    static func running(_ target: EngineTarget) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "args="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        guard (try? proc.run()) != nil else { return true }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self).contains(target.root.path + "/")
    }

    /// The agent's part. With the Wine modules on automatic it keeps each improvement
    /// in the NotProton runners the user put it into -- after a CrossOver or NotProton
    /// update put CrossOver's own files back, or when newer modules came -- and puts
    /// it into a runner that appears for a new CrossOver build, once it is in a
    /// runner already and the user left "new CrossOver builds" on; always after that
    /// CrossOver's games close. Asked first, it says so instead, once. A CrossOver
    /// app is only ever reported: changing one needs App Management and signs the
    /// app again, which is the user's to do. Off, it does nothing.
    static func keep(_ settings: inout AutoSettings, state: inout AgentState, now: Date) async -> [AgentEvent] {
        guard settings.modulesUpdates else { return [] }
        let catalog = Catalog.active(.modules).dir
        let targets = Engine.targets()
        let builds = Engine.builds(in: catalog)
        // The first look only learns what is there: those runners are not new.
        let firstLook = state.engineSeen == nil
        let seen = Set(state.engineSeen ?? [])
        state.engineSeen = targets.map(\.key)
        var events: [AgentEvent] = []
        func once(_ key: String, _ message: String, failed: Bool) {
            guard state.engineNoted[key] != message else { return }
            state.engineNoted[key] = message
            events.append(AgentEvent(date: now, game: "", message: message, failed: failed))
        }
        for part in EnginePart.allCases {
            let runnerKept = targets.contains { $0.app == nil && settings.kept(part, $0.key) }
            for target in targets {
                let path = target.key
                // The controls keep the key they always had, so what was noted before stays noted.
                let noted = part == .controls ? path : "\(path)#\(part.rawValue)"
                guard !settings.declined(part, path),
                      let build = builds.first(where: { $0.build == target.build }), part.carried(by: build) else { continue }
                let kept = settings.kept(part, path)
                let fresh = !firstLook && !seen.contains(path) && target.app == nil && runnerKept && settings.modulesNewBuilds
                guard kept || fresh else { continue }
                let before = await status(target, part: part, catalog: catalog)
                let needs: String
                if before == .outdated {
                    needs = "a newer \(part.title) improvement"
                } else if before == .absent || before == .half {
                    needs = kept ? "the \(part.title) improvement again: something replaced it, such as a CrossOver or NotProton update"
                        : "the \(part.title) improvement: it is a new CrossOver build"
                } else {
                    state.engineNoted[noted] = nil
                    continue
                }
                if target.app != nil || settings.modulesAskFirst {
                    once(noted, "\(target.name) needs \(needs). Install it from MacGameFix's Improvements tab.", failed: false)
                    continue
                }
                if running(target) { continue }
                let out = Collected()
                let code = await run(target, part: part, catalog: catalog, []) { out.add($0) }
                if code == 0, await status(target, part: part, catalog: catalog) == .installed {
                    if !kept { settings.setKept(part, path, true) }
                    state.engineNoted[noted] = nil
                    let did = before == .outdated ? "updated in" : kept ? "put back in" : "installed in the new"
                    events.append(AgentEvent(date: now, game: "", message: "\(part.title) \(did) \(target.name).", failed: false))
                } else {
                    once(noted, "\(part.title) could not go into \(target.name): \(out.all.last ?? "see the log").",
                         failed: true)
                }
            }
        }
        return events
    }

    /// The D3DMetal builds a CrossOver carries, by the folder each sits in and the
    /// version its framework's Info.plist gives: lib64/apple_gptk and
    /// lib64/apple_gptk_4 in stable 26.3, lib/apple_gptk and lib/apple_gptk3 in
    /// Preview 27 (read 2026-10-23). Which one a game ran on is not read here.
    static func d3dmetal(in root: URL) -> [(folder: String, version: String)] {
        let fm = FileManager.default
        var found: [(folder: String, version: String)] = []
        for lib in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() where lib.hasPrefix("lib") {
            for gptk in ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(lib).path)) ?? []).sorted()
            where gptk.hasPrefix("apple_gptk") {
                let plist = root.appendingPathComponent("\(lib)/\(gptk)/external/D3DMetal.framework/Resources/Info.plist")
                if let version = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String {
                    found.append(("\(lib)/\(gptk)", version))
                }
            }
        }
        return found
    }
}

