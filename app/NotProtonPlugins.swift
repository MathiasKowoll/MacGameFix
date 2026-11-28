// The NotProton plugins MacGameFix carries: four of MacGameFix's fixes that NotProton's creator
// ported to NotProton's plugins (notproton-plugins/ORIGIN.md), kept in NotProton's plugins folder
// for every game, each off until it is switched on for one.
//
//   40-unreal-video.conf       Unreal video fix          patches winegstreamer.dll in memory
//   50-d3dmetal-freeze.conf    D3DMetal freeze fix       d3dmetal-freeze.dylib
//   55-d3dmetal-notifier.conf  D3DMetal video crash fix  d3dmetal-notifier.dylib
//   60-red-dead-online.conf    Red Dead Online fix       tcp-noopt.dylib, RDR2 and RDO only
//
// and two of MacGameFix's own, kept the same way:
//
//   mgf-controls.conf          DualSense controllers     mgf-controls.dylib (fixes/controls)
//   mgf-shaders.conf           Shaders kept whole        mgf-shaders.dylib (notproton-plugins/mgf-shaders.c)
//
// They carry NotProton's own file names, so a NotProton that installs the same plugins writes
// the same files rather than a second copy: NotProton refuses an id two files declare, and
// neither row would show. A row another file already declares is left alone, with its library.
//
// The libraries need NotProton's plugin host (plugin-host.dylib, which NotProton's Update puts
// in its support folder): without it a library loads and does nothing, so its row is not
// offered. The Unreal row needs a NotProton that reads "patch". Where a row cannot work, the
// one MacGameFix wrote is taken out; a file MacGameFix did not write is never touched.
//
// INSTALLED BY THE PLAYER, KEPT BY THE AGENT. Nothing goes into NotProton's folder until the
// player installs the plugins (Improvements, NotProton plugins; or --plugins-install), and an
// install wants Steam and NotProton's own app closed: Steam reads the folder each time a game's
// page opens, and NotProton's app lists it and deletes from it. What was installed is noted in
// MacGameFix's own folder (notproton-plugins.installed), and from then on the agent's pass and
// the window's scan keep those plugins current with Steam open or not, as before: a row that
// changed, a library a newer MacGameFix carries. A plugin whose row is gone from NotProton's
// folder was deleted there (NotProton's Plugins page moves the row and its library to the
// Trash): it leaves the note and is not put back until the player installs again. Until
// 2026-11-28 every pass wrote whatever was missing, so a plugin deleted in NotProton came back
// at the next one. A Mac with no note yet starts with the plugins it already has.
//
// "Engine fixes" is one more, kept the same way but written by the catalog's own script
// (fixes/notproton-every-game.sh), since every game's installer writes that row too.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What has to be closed for an install: Steam, and NotProton's own app.
enum NotProtonHost {
    /// The names of those that are open. MGVF_STEAM_RUNNING and MGVF_NOTPROTON_RUNNING, 0 or 1,
    /// answer for a test, which must not see the Steam of the Mac it runs on.
    static func open() -> [String] {
        let env = ProcessInfo.processInfo.environment
        var names: [String]?
        func running(_ key: String, _ match: (String) -> Bool) -> Bool {
            if let forced = env[key], forced == "0" || forced == "1" { return forced == "1" }
            if names == nil {
                names = NotProtonPlugins.command("/bin/ps", ["-axo", "comm="], [:]).1
                    .split(separator: "\n").map(String.init)
            }
            return names!.contains(where: match)
        }
        // Steam's process is Steam.AppBundle/Steam/Contents/MacOS/steam_osx.
        let steam = running("MGVF_STEAM_RUNNING") { $0.hasSuffix("/steam_osx") || $0.contains("/Steam.app/Contents/MacOS/steam") }
        let notproton = running("MGVF_NOTPROTON_RUNNING") { $0.contains("/NotProton.app/Contents/MacOS/") }
        return (steam ? ["Steam"] : []) + (notproton ? ["NotProton"] : [])
    }
}

enum NotProtonPlugins {
    struct Plugin {
        let name: String
        let file: String
        let id: String
        let group: String
        let label: String
        let description: String
        /// The library beside the row, in NotProton's plugins folder; built by build-app.sh.
        let library: String?
        /// The fields past the oldest NotProton with plugins that the row needs.
        let fields: [String]
        let rest: [String]
        /// The games the row is for, "<app id> <sentence>" each (NotProtonRow.games): only where
        /// this repository names the game by its Steam app.
        var neededFor: [String] = []
        var improves: [String] = []
    }

    /// Every row MacGameFix writes names it: in its group, or in its label where there is none.
    static let mark = "MacGameFix"
    static var host: URL { Engine.notproton.appendingPathComponent("plugin-host.dylib") }
    /// The libraries this app carries.
    static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("notproton-plugins") }

    /// The descriptions say what a row is for and no more; how each one works:
    /// - Unreal video: CrossOver's winegstreamer hides the NV12 output Unreal's player
    ///   (Electra) asks for, and the patches offer it. x86_64 games, CrossOver 26.3 and
    ///   Preview 41303. Town to City crashes on a menu video with real NV12.
    /// - D3DMetal freeze: answers a D3D12 video memory question about a GPU node other than
    ///   the first with an error, where D3DMetal froze. Acts on D3DMetal 3.0 and 4.0b2; on
    ///   Preview 41303's 4.0b3 it loads and does nothing.
    /// - D3DMetal video crash: gives D3D12 devices the ID3DDestructionNotifier interface older
    ///   D3DMetal lacked; 4.0b3 has it.
    /// - Red Dead Online: sets TCP_NOOPT on the game's sockets before they connect, from
    ///   NotProton's creator's fix. Played online with the row on 2026-11-26. The one row here
    ///   that names its games to NotProton (improves): the other three are for games this
    ///   repository names by title only, or names none, and the pad's row is the player's choice.
    /// - DualSense controllers: mgf-controls.dylib takes the IOKit calls of CodeWeavers'
    ///   winebus.so and the CoreAudio calls of their winecoreaudio.so, and does what engine
    ///   patches 0004-0016 and 0030 do inside ours: the Bluetooth pad as a wired one, haptics,
    ///   XInput, trigger effects, DualShock 4 mode, by the game's settings in Game Feel. For a
    ///   runner that keeps CodeWeavers' two files; where they are MacGameFix's own it leaves
    ///   them alone. Played on NotProton 41303 (Rosetta), 2026-11-26: Marvel's Spider-Man 2
    ///   over Bluetooth and on a cable, Crysis 3 Remastered (XInput, triggers) and Crash
    ///   Bandicoot 4 (DualShock 4 mode).
    /// - Shaders kept whole: ShaderCache.swift's work, done by the game as it starts (mgf-shaders.c):
    ///   the first process of a start clones the fullest Metal cache file over the others while
    ///   none is held, so the game gets them all whatever file it takes. The agent still does it
    ///   after a game closes, for every game; the row is for a game that should not wait for that,
    ///   or a Mac without the agent. It names Ori and Phantom Blade Zero to NotProton (improves),
    ///   whose starts are the ones the split cache costs most.
    static let all: [Plugin] = [
        Plugin(
            name: "Unreal video", file: "40-unreal-video.conf", id: "NOTPROTON_UNREAL_VIDEO",
            group: "MacGameFix / Video", label: "Unreal video fix",
            description: "For Unreal Engine videos that stay black. Not for every game: Town to City crashes with it",
            library: nil, fields: ["patch"],
            rest: [
                "on = 1",
                "patch = winegstreamer.dll: 31 d2 e8 ?? ?? ?? ?? 48 8b 4c 24 ?? 48 8d 15 ?? ?? ?? ?? ff 15 ?? ?? ?? ?? 85 c0 75=eb | 31 d2 e8 ?? ?? ?? ?? 48 8d 15 ?? ?? ?? ?? 48 8b 4c 24 ?? ff 15 ?? ?? ?? ?? 48 8b ?? ?? 85 c0 89 ?? 48 8b ?? ?? 75=eb | 31 d2 e8 ?? ?? ?? ?? 48 8d 15 ?? ?? ?? ?? 48 8b 4c 24 ?? ff 15 ?? ?? ?? ?? 89 c2 89 ?? 85 d2 48 8b ?? ?? 48 8b ?? ?? 75=eb",
                "patch = winegstreamer.dll: 48 8b 0b 48 8b 01 48 8b 15 ?? ?? ?? ?? 41 b8 01=00 00 00 00 ff 90 a8 00 00 00 85 c0 0f 88 ?? ?? ?? ?? 48 8b 0b 48 8b 01 48 8b 15 ?? ?? ?? ?? 41 b8 01=00 00 00 00 ff 90 a8 00 00 00 | 48 8b ?? ?? 41 b8 01=00 00 00 00 48 8d 15 ?? ?? ?? ?? 48 8b 01 ff 90 a8 00 00 00 85 c0 89 ?? 0f 88 ?? ?? ?? ?? 48 8b ?? ?? 41 b8 01=00 00 00 00 48 8d 15 ?? ?? ?? ?? 48 8b 01 ff 90 a8 00 00 00",
            ]),
        Plugin(
            name: "D3DMetal freeze", file: "50-d3dmetal-freeze.conf", id: "NOTPROTON_D3DMETAL_NODEGUARD",
            group: "MacGameFix / D3DMetal", label: "D3DMetal freeze fix",
            description: "For a game that freezes on an older D3DMetal: Town to City, Life is Strange, FATAL FURY. Does nothing on Preview 41303",
            library: "d3dmetal-freeze.dylib", fields: [], rest: ["on = 1", "inject = 1"]),
        Plugin(
            name: "D3DMetal video crash", file: "55-d3dmetal-notifier.conf", id: "NOTPROTON_D3DMETAL_NOTIFIER",
            group: "MacGameFix / D3DMetal", label: "D3DMetal video crash fix",
            description: "For a game that crashes playing a video on an older D3DMetal. Not needed on Preview 41303",
            library: "d3dmetal-notifier.dylib", fields: [], rest: ["on = 1", "inject = 1"]),
        Plugin(
            name: "Red Dead Online", file: "60-red-dead-online.conf", id: "NOTPROTON_TCP_NOOPT",
            group: "MacGameFix / Game fixes", label: "Red Dead Online fix",
            description: "Lets Red Dead Online connect. Played online on NotProton 41303",
            library: "tcp-noopt.dylib", fields: ["apps"],
            rest: ["on = 1", "inject = 1", "apps = 1174180", "apps = 1404210"],
            improves: ["1174180 Red Dead Online connects to its servers.",
                       "1404210 Red Dead Online connects to its servers."]),
        Plugin(
            name: "DualSense controllers", file: "mgf-controls.conf", id: "NOTPROTON_MGF_CONTROLS",
            group: "MacGameFix / Controllers", label: "DualSense controllers",
            description: "The DualSense in this game: Bluetooth as a cable, haptics, XInput, triggers. Set it up in MacGameFix's Game Feel",
            library: "mgf-controls.dylib", fields: [],
            rest: ["on = 1", "inject = 1", "tools = notproton-fex-rosetta*"]),
        Plugin(
            name: "Shaders kept whole", file: "mgf-shaders.conf", id: "NOTPROTON_MGF_SHADERS",
            group: "MacGameFix / Performance", label: "Shaders kept whole",
            description: "The game starts from all the shaders it compiled before, not from a part of them",
            library: "mgf-shaders.dylib", fields: [],
            rest: ["on = 1", "inject = 1"],
            improves: ["387290 Ori and the Blind Forest starts without compiling its shaders again.",
                       "1057090 Ori and the Will of the Wisps does not hitch again where it already was.",
                       "4115450 Phantom Blade Zero starts from all the shaders it compiled before."]),
    ]

    static func text(_ p: Plugin, grouped: Bool) -> String {
        var lines = ["[\(p.id)]", NotProtonRow.label(p.label, grouped: grouped)]
        if grouped { lines.append("group = \(p.group)") }
        lines.append("description = \(p.description)")
        lines += NotProtonRow.games(neededFor: p.neededFor, improves: p.improves)
        lines += p.rest
        if let library = p.library {
            lines.append("requires = Library/Application Support/notproton/plugins/\(library)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Why a plugin cannot work with the NotProton on this Mac, or nil when it can.
    static func unworkable(_ p: Plugin) -> String? {
        if let field = (p.fields + (p.library == nil ? [] : ["inject"])).first(where: { !NotProtonRow.knows($0) }) {
            return "the NotProton in Steam does not read \(field)"
        }
        if p.library != nil && !FileManager.default.fileExists(atPath: host.path) {
            return "NotProton's plugin host is not installed"
        }
        return nil
    }

    /// How a plugin stands on this Mac, for the window; nothing is written.
    enum State: Sendable, Equatable {
        case inPlace
        /// Installed, and not the one this MacGameFix carries: the next pass puts it in place.
        case behind
        /// Never installed, or deleted in NotProton: only an install puts it in.
        case notInstalled
        case unworkable(String)
        case foreign
    }

    /// The plugins the player installed, by id, each with whether its row is out for now because
    /// it could not work (the pass that finds it can again puts it back).
    struct Installed {
        var waiting: [String: Bool] = [:]
        static var file: URL { Paths.support.appendingPathComponent("notproton-plugins.installed") }

        /// nil when nothing was ever noted on this Mac.
        static func load() -> Installed? {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            var list = Installed()
            for line in text.split(separator: "\n") {
                let words = line.split(separator: " ")
                guard let id = words.first else { continue }
                list.waiting[String(id)] = words.dropFirst().first == "waiting"
            }
            return list
        }

        /// A Mac from before the note: the plugins whose rows MacGameFix wrote are the installed ones.
        static func found() -> Installed {
            var list = Installed()
            for p in all where NotProtonPlugins.mine(p) { list.waiting[p.id] = false }
            return list
        }

        func save() {
            let text = waiting.keys.sorted().map { waiting[$0] == true ? "\($0) waiting" : $0 }.joined(separator: "\n")
            try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            try? (text + "\n").write(to: Installed.file, atomically: true, encoding: .utf8)
        }
    }

    /// Whether the row in NotProton's folder is one MacGameFix wrote: its id, and the mark.
    static func mine(_ p: Plugin) -> Bool {
        guard let row = try? String(contentsOf: NotProtonRow.folder.appendingPathComponent(p.file), encoding: .utf8)
        else { return false }
        return row.hasPrefix("[\(p.id)]\n") && row.contains(mark)
    }

    static func state(_ p: Plugin) -> State { state(p, Installed.load() ?? Installed.found()) }

    static func state(_ p: Plugin, _ list: Installed) -> State {
        if let why = unworkable(p) { return .unworkable(why) }
        if NotProtonRow.headers(besides: p.file).contains("[\(p.id)]") { return .foreign }
        let fm = FileManager.default
        let row = try? String(contentsOf: NotProtonRow.folder.appendingPathComponent(p.file), encoding: .utf8)
        guard let waiting = list.waiting[p.id], row != nil || waiting else { return .notInstalled }
        guard row == text(p, grouped: NotProtonRow.knowsGroups()) else { return .behind }
        if let library = p.library {
            guard let source = bundled?.appendingPathComponent(library),
                  let carried = fm.contents(atPath: source.path),
                  fm.contents(atPath: NotProtonRow.folder.appendingPathComponent(library).path) == carried
            else { return .behind }
        }
        return .inPlace
    }

    /// Each plugin's id, label and state; nil when there is no NotProton in Steam.
    static func states() -> [(id: String, label: String, state: State)]? {
        guard FileManager.default.fileExists(atPath: Engine.notproton.path) else { return nil }
        let list = Installed.load() ?? Installed.found()
        return all.map { ($0.id, $0.label, state($0, list)) } + [(EveryGameRows.id, EveryGameRows.label, EveryGameRows.state())]
    }

    /// The rows in NotProton's folder, everyone's, of the most it reads (NotProtonRow.maxRows).
    static func rows() -> Int { NotProtonRow.headers(besides: "").count }

    /// One line per plugin, for --plugins-report and the tests.
    static func report() -> String {
        guard let states = states() else { return "plugins: no NotProton" }
        return states.map { _, label, state in
            switch state {
            case .inPlace: return "\(label): in place"
            case .behind: return "\(label): not in place yet"
            case .notInstalled: return "\(label): not installed"
            case .unworkable(let why): return "\(label): not offered, \(why)"
            case .foreign: return "\(label): another plugin file has it"
            }
        }.joined(separator: "\n") + "\nrows: \(rows()) of \(NotProtonRow.maxRows)"
    }

    /// What to say, with nothing changed, while Steam or NotProton is open; nil when both are closed.
    static func closedFirst(_ then: String) -> String? {
        let open = NotProtonHost.open()
        guard !open.isEmpty else { return nil }
        return "\(open.joined(separator: " and ")) \(open.count == 1 ? "is" : "are") open. "
            + "Quit \(open.count == 1 ? "it" : "them"), then \(then). Nothing was changed."
    }

    /// The plugins not installed yet put in, every one or the one with this id, and the installed
    /// ones kept. Refused, with nothing changed, while Steam or NotProton is open and there is one
    /// to put in. What was done, and whether it was refused.
    static func install(only id: String? = nil) -> (said: [String], refused: Bool) {
        guard FileManager.default.fileExists(atPath: Engine.notproton.path) else { return ([], false) }
        if let id, id != EveryGameRows.id, !all.contains(where: { $0.id == id }) {
            return (["\(id) is no plugin of MacGameFix's."], true)
        }
        var list = Installed.load() ?? Installed.found()
        let fresh = all.filter {
            (id == nil || $0.id == id) && (list.waiting[$0.id] == nil || (!mine($0) && list.waiting[$0.id] == false))
        }
        let rows: State = id == nil || id == EveryGameRows.id ? EveryGameRows.state() : .inPlace
        if !fresh.isEmpty || rows == .notInstalled {
            if let refusal = closedFirst("install") { return ([refusal], true) }
        }
        // Noted as installed and out for now: the pass below puts each one in.
        for p in fresh { list.waiting[p.id] = true }
        list.save()
        var said = keep(everyGame: false)
        if rows == .notInstalled || rows == .behind { said += EveryGameRows.run([]) }
        return (said, false)
    }

    /// One plugin taken out of NotProton: its row, its library where no other row names it, and
    /// its place in the note, so no pass puts it back. Refused while Steam or NotProton is open.
    /// A game with the row switched on keeps the variable in its launch options, which then
    /// names no row. A row MacGameFix did not write is left alone.
    static func remove(_ id: String) -> (said: [String], refused: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Engine.notproton.path) else { return ([], false) }
        guard id == EveryGameRows.id || all.contains(where: { $0.id == id }) else {
            return (["\(id) is no plugin of MacGameFix's."], true)
        }
        if let refusal = closedFirst("remove it") { return ([refusal], true) }
        if id == EveryGameRows.id { return (EveryGameRows.run(["--restore"]), false) }
        guard let p = all.first(where: { $0.id == id }) else { return ([], false) }
        var list = Installed.load() ?? Installed.found()
        var said: [String] = []
        let path = NotProtonRow.folder.appendingPathComponent(p.file)
        if fm.fileExists(atPath: path.path) {
            guard mine(p) else {
                return (["\(p.name) row: \(p.file) is not one MacGameFix wrote, left alone"], true)
            }
            try? fm.removeItem(at: path)
            said.append("\(p.name) row: removed")
        }
        if let library = p.library {
            let lib = NotProtonRow.folder.appendingPathComponent(library)
            let named = ((try? fm.contentsOfDirectory(atPath: NotProtonRow.folder.path)) ?? [])
                .filter { $0.hasSuffix(".conf") }
                .compactMap { try? String(contentsOf: NotProtonRow.folder.appendingPathComponent($0), encoding: .utf8) }
                .contains { $0.contains("/\(library)") }
            if fm.fileExists(atPath: lib.path) && !named {
                try? fm.removeItem(at: lib)
                said.append("\(p.name) library: removed")
            }
        }
        list.waiting[p.id] = nil
        list.save()
        return (said, false)
    }

    /// Every installed plugin brought up to date, taken out where it cannot work, and left out
    /// where it was deleted in NotProton. What was done; nothing when all was already right or
    /// there is no NotProton.
    static func keep(everyGame: Bool = true) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Engine.notproton.path) else { return [] }
        var said: [String] = []
        let noted = Installed.load()
        var list = noted ?? Installed.found()
        let before = list.waiting
        defer { if noted == nil || list.waiting != before { list.save() } }
        for p in all {
            guard let waiting = list.waiting[p.id] else { continue }
            let path = NotProtonRow.folder.appendingPathComponent(p.file)
            if let why = unworkable(p) {
                // Only a row MacGameFix wrote: its id, and the mark.
                if mine(p) {
                    try? fm.removeItem(at: path)
                    said.append("\(p.name) row: taken out, \(why)")
                }
                list.waiting[p.id] = true
                continue
            }
            if NotProtonRow.headers(besides: p.file).contains("[\(p.id)]") {
                said.append("\(p.name) row: another plugin file has \(p.id), left alone")
                continue
            }
            if !waiting && !fm.fileExists(atPath: path.path) {
                list.waiting[p.id] = nil
                said.append("\(p.name) row: deleted from NotProton's plugins, left out until it is installed again")
                continue
            }
            if let library = p.library {
                guard let source = bundled?.appendingPathComponent(library), fm.fileExists(atPath: source.path) else {
                    said.append("\(p.name) row: this build of MacGameFix carries no \(library)")
                    continue
                }
                switch place(source, as: NotProtonRow.folder.appendingPathComponent(library)) {
                case .some(.success): said.append("\(p.name) library: put in place")
                case .some(.failure(let error)):
                    said.append("\(p.name) library: \(error.localizedDescription)")
                    continue
                case .none: break
                }
            }
            if let line = NotProtonRow.keep(name: p.name, id: p.id, file: p.file, written: "written",
                                            text: { .success(text(p, grouped: $0)) }) {
                said.append(line)
            }
            if fm.fileExists(atPath: path.path) { list.waiting[p.id] = false }
        }
        // A Mac from before the note: the rows for every game that a game's fix already put in
        // are taken as installed, as the plugins above were.
        if noted == nil { EveryGameRows.adopt() }
        // The rows for every game, once installed, are kept by the catalog's script.
        if everyGame && EveryGameRows.state() == .behind { said += EveryGameRows.run([]) }
        return said
    }

    /// A command's exit status and its output, trimmed; -1 when it could not be started.
    static func command(_ executable: String, _ arguments: [String], _ environment: [String: String]) -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment { env[k] = v }
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The carried library copied over the one in NotProton's folder when they differ, through a
    /// rename, so a game still running keeps the one it loaded. nil when it was already the same.
    static func place(_ source: URL, as target: URL) -> Result<Void, Error>? {
        let fm = FileManager.default
        if let have = fm.contents(atPath: target.path), have == fm.contents(atPath: source.path) { return nil }
        let staged = target.deletingLastPathComponent().appendingPathComponent("." + target.lastPathComponent + ".mgf-new")
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: staged)
            try fm.copyItem(at: source, to: staged)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
            guard rename(staged.path, target.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return .success(())
        } catch {
            try? fm.removeItem(at: staged)
            return .failure(error)
        }
    }
}


/// "Engine fixes", the row MacGameFix keeps on every game's page for a game no fix knows (one
/// with Denuvo needs it to start), and the library it loads. Every game's installer writes that
/// row too, into one file they share, so the app writes nothing itself: it runs the catalog's
/// script (fixes/notproton-every-game.sh), which says how the row stands and installs it.
enum EveryGameRows {
    static let id = "NOTPROTON_MGF_ENGINE"
    static let label = "Engine fixes"

    static var script: URL { Catalog.active(.fixes).dir.appendingPathComponent("notproton-every-game.sh") }

    private static func script(_ arguments: [String]) -> (Int32, String) {
        NotProtonPlugins.command("/bin/bash", [script.path] + arguments,
                                 ["HOME": Paths.home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
    }

    static func state() -> NotProtonPlugins.State {
        guard FileManager.default.fileExists(atPath: script.path) else {
            return .unworkable("this catalog of fixes has no installer for it")
        }
        let lines = script(["--status"]).1.split(separator: "\n").map(String.init)
        switch lines.last {
        case "installed": return .inPlace
        case "half": return .behind
        case "absent": return .notInstalled
        default:
            let why = lines.first { $0.hasPrefix("Why: ") }.map { String($0.dropFirst(5)) }
            return .unworkable(why ?? "its installer could not say how it stands")
        }
    }

    /// Rows a game's fix already put in, noted as installed; nothing where there are none.
    static func adopt() {
        guard FileManager.default.fileExists(atPath: script.path) else { return }
        _ = script(["--adopt"])
    }

    /// The script's install, or its removal with ["--restore"]: what it said, each line named.
    static func run(_ arguments: [String]) -> [String] {
        let (code, text) = script(arguments)
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "Installed." && $0 != "Restored." }
        if lines.isEmpty {
            return code != 0 ? ["\(label): its installer failed"] : arguments.isEmpty ? [] : ["\(label): removed"]
        }
        return lines.map { "\(label): \($0)" }
    }
}
