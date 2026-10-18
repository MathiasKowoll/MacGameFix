// The Wine modules: the one part of MacGameFix that changes CrossOver itself.
//
// Three patched Wine files (engine/README.md) go into a CrossOver app or a
// NotProton runner, so that games find a DualSense's haptic output on a cable.
// As with the game fixes, the app decides nothing: engine-modules.sh, carried in
// the catalog with the modules, answers --status, installs on a plain run and
// undoes with --restore. This file finds the places it can go and runs it.
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

    var id: String { root.path }
    /// The folder with symlinks resolved, as the settings keep it: /var and
    /// /private/var are one place.
    var key: String { root.resolvingSymlinksInPath().path }
}

/// The installer's word for one CrossOver.
enum EngineState: Equatable {
    case unknown, installed, outdated, half, absent, noModules

    var label: String {
        switch self {
        case .unknown: return "…"
        case .installed: return "Installed"
        case .outdated: return "Older modules: install again"
        case .half: return "Partly installed"
        case .absent: return "Not installed"
        case .noModules: return "No modules for this build yet"
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

    static func builds(in catalog: URL) -> [EngineBuild] {
        struct Table: Decodable { let builds: [EngineBuild] }
        let data = (try? Data(contentsOf: catalog.appendingPathComponent("engine-modules.json"))) ?? Data()
        return (try? JSONDecoder().decode(Table.self, from: data))?.builds ?? []
    }

    /// Every CrossOver app in /Applications and ~/Applications, and every
    /// NotProton runner.
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
                let short = info?["CFBundleShortVersionString"] as? String ?? build
                let name = (info?["CFBundleName"] as? String ?? app.deletingPathExtension().lastPathComponent) + " " + short
                found.append(EngineTarget(root: root, build: build, name: name, app: app, fex: fex(root)))
            }
        }
        let runners = Runtimes.notproton.appendingPathComponent("runners")
        for runner in ((try? fm.contentsOfDirectory(at: runners, includingPropertiesForKeys: nil)) ?? [])
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where runner.lastPathComponent.hasPrefix("crossover-") {
            let root = runner.appendingPathComponent("CrossOver")
            guard wine(root) else { continue }
            let build = String(runner.lastPathComponent.dropFirst("crossover-".count).split(separator: "-").first ?? "")
            found.append(EngineTarget(root: root, build: build, name: "NotProton runner \(runner.lastPathComponent)",
                                      app: nil, fex: fex(root)))
        }
        return found
    }

    static func status(_ target: EngineTarget, catalog: URL) async -> EngineState {
        let out = Collected()
        let code = await run(target, catalog: catalog, ["--status"]) { out.add($0) }
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
    static func run(_ target: EngineTarget, catalog: URL, _ extra: [String],
                    onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        let lock = InstallLock()
        defer { lock.release() }
        let script = catalog.appendingPathComponent(Self.script).path
        return await runStreaming("/bin/bash", [script, target.root.path] + extra,
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

    /// The agent's part. With the Wine modules on automatic it keeps them in the
    /// NotProton runners the user put them into -- after a CrossOver or NotProton
    /// update put CrossOver's own files back, or when newer modules came -- and
    /// puts them into a runner that appears for a new CrossOver build, once they
    /// are in a runner already; always after that CrossOver's games close. Asked
    /// first, it says so instead, once. A CrossOver app is only ever reported:
    /// changing one needs App Management and signs the app again, which is the
    /// user's to do. Off, it does nothing.
    static func keep(_ settings: inout AutoSettings, state: inout AgentState, now: Date) async -> [AgentEvent] {
        guard settings.modulesUpdates else { return [] }
        let catalog = Catalog.active(.modules).dir
        let targets = Engine.targets()
        // The first look only learns what is there: those runners are not new.
        let firstLook = state.engineSeen == nil
        let seen = Set(state.engineSeen ?? [])
        state.engineSeen = targets.map(\.key)
        let keptPaths = Set(settings.modulesKept.map(resolved)), declined = Set(settings.modulesDeclined.map(resolved))
        let runnerKept = targets.contains { $0.app == nil && keptPaths.contains($0.key) }
        var events: [AgentEvent] = []
        func once(_ path: String, _ message: String, failed: Bool) {
            guard state.engineNoted[path] != message else { return }
            state.engineNoted[path] = message
            events.append(AgentEvent(date: now, game: "", message: message, failed: failed))
        }
        for target in targets {
            let path = target.key
            guard !declined.contains(path) else { continue }
            let kept = keptPaths.contains(path)
            let fresh = !firstLook && !seen.contains(path) && target.app == nil && runnerKept
            guard kept || fresh else { continue }
            let before = await status(target, catalog: catalog)
            let needs: String
            if before == .outdated {
                needs = "newer Wine modules"
            } else if before == .absent || before == .half {
                needs = kept ? "the Wine modules again: an update put CrossOver's own files back"
                    : "the Wine modules: it is a new CrossOver build"
            } else {
                state.engineNoted[path] = nil
                continue
            }
            if target.app != nil || settings.modulesAskFirst {
                once(path, "\(target.name) needs \(needs). Install them from MacGameFix's Wine Modules tab.", failed: false)
                continue
            }
            if running(target) { continue }
            let out = Collected()
            let code = await run(target, catalog: catalog, []) { out.add($0) }
            if code == 0, await status(target, catalog: catalog) == .installed {
                if !kept { settings.modulesKept.append(path) }
                state.engineNoted[path] = nil
                let did = before == .outdated ? "updated in" : kept ? "put back in" : "installed in the new"
                events.append(AgentEvent(date: now, game: "", message: "Wine modules \(did) \(target.name).", failed: false))
            } else {
                once(path, "The Wine modules could not go into \(target.name): \(out.all.last ?? "see the log").",
                     failed: true)
            }
        }
        return events
    }
}

