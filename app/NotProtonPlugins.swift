// The NotProton plugins MacGameFix carries: four of MacGameFix's fixes that NotProton's creator
// ported to NotProton's plugins (notproton-plugins/ORIGIN.md), kept in NotProton's plugins folder
// for every game, each off until it is switched on for one.
//
//   40-unreal-video.conf       Unreal video fix          patches winegstreamer.dll in memory
//   50-d3dmetal-freeze.conf    D3DMetal freeze fix       d3dmetal-freeze.dylib
//   55-d3dmetal-notifier.conf  D3DMetal video crash fix  d3dmetal-notifier.dylib
//   60-red-dead-online.conf    Red Dead Online fix       tcp-noopt.dylib, RDR2 and RDO only
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
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

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
    }

    /// Every row MacGameFix writes says so at the end of its description.
    static let mark = "(MacGameFix)"
    static var host: URL { Engine.notproton.appendingPathComponent("plugin-host.dylib") }
    /// The libraries this app carries.
    static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("notproton-plugins") }

    static let all: [Plugin] = [
        Plugin(
            name: "Unreal video", file: "40-unreal-video.conf", id: "NOTPROTON_UNREAL_VIDEO",
            group: "MacGameFix · Video", label: "Unreal video fix",
            description: "Unreal Engine videos that stay black: CrossOver's winegstreamer hides the NV12 output Unreal's player (Electra) asks for, and this patches winegstreamer.dll in memory to offer it. x86_64 games, CrossOver 26.3 and Preview 41303. Not for every game: Town to City crashes on a menu video with real NV12. Turn it on per game",
            library: nil, fields: ["patch"],
            rest: [
                "on = 1",
                "patch = winegstreamer.dll: 31 d2 e8 ?? ?? ?? ?? 48 8b 4c 24 ?? 48 8d 15 ?? ?? ?? ?? ff 15 ?? ?? ?? ?? 85 c0 75=eb | 31 d2 e8 ?? ?? ?? ?? 48 8d 15 ?? ?? ?? ?? 48 8b 4c 24 ?? ff 15 ?? ?? ?? ?? 48 8b ?? ?? 85 c0 89 ?? 48 8b ?? ?? 75=eb | 31 d2 e8 ?? ?? ?? ?? 48 8d 15 ?? ?? ?? ?? 48 8b 4c 24 ?? ff 15 ?? ?? ?? ?? 89 c2 89 ?? 85 d2 48 8b ?? ?? 48 8b ?? ?? 75=eb",
                "patch = winegstreamer.dll: 48 8b 0b 48 8b 01 48 8b 15 ?? ?? ?? ?? 41 b8 01=00 00 00 00 ff 90 a8 00 00 00 85 c0 0f 88 ?? ?? ?? ?? 48 8b 0b 48 8b 01 48 8b 15 ?? ?? ?? ?? 41 b8 01=00 00 00 00 ff 90 a8 00 00 00 | 48 8b ?? ?? 41 b8 01=00 00 00 00 48 8d 15 ?? ?? ?? ?? 48 8b 01 ff 90 a8 00 00 00 85 c0 89 ?? 0f 88 ?? ?? ?? ?? 48 8b ?? ?? 41 b8 01=00 00 00 00 48 8d 15 ?? ?? ?? ?? 48 8b 01 ff 90 a8 00 00 00",
            ]),
        Plugin(
            name: "D3DMetal freeze", file: "50-d3dmetal-freeze.conf", id: "NOTPROTON_D3DMETAL_NODEGUARD",
            group: "MacGameFix · D3DMetal", label: "D3DMetal freeze fix",
            description: "Answers a D3D12 video memory question about a GPU node other than the first with an error, where D3DMetal froze (Town to City, Life is Strange, FATAL FURY). Acts on D3DMetal 3.0 and 4.0b2 only: on Preview 41303's D3DMetal 4.0b3 it loads and does nothing",
            library: "d3dmetal-freeze.dylib", fields: [], rest: ["on = 1", "inject = 1"]),
        Plugin(
            name: "D3DMetal video crash", file: "55-d3dmetal-notifier.conf", id: "NOTPROTON_D3DMETAL_NOTIFIER",
            group: "MacGameFix · D3DMetal", label: "D3DMetal video crash fix",
            description: "Gives D3D12 devices the ID3DDestructionNotifier interface older D3DMetal lacked, where some games crashed playing a video. Not needed on Preview 41303: its D3DMetal 4.0b3 has the interface itself",
            library: "d3dmetal-notifier.dylib", fields: [], rest: ["on = 1", "inject = 1"]),
        Plugin(
            name: "Red Dead Online", file: "60-red-dead-online.conf", id: "NOTPROTON_TCP_NOOPT",
            group: "MacGameFix · Per game", label: "Red Dead Online fix",
            description: "Red Dead Online's connection: sets TCP_NOOPT on the game's sockets before they connect, from NotProton's creator's fix. Only Red Dead Redemption 2 and Red Dead Online. Any runner; not yet confirmed in play",
            library: "tcp-noopt.dylib", fields: ["apps"],
            rest: ["on = 1", "inject = 1", "apps = 1174180", "apps = 1404210"]),
    ]

    static func text(_ p: Plugin, grouped: Bool) -> String {
        var lines = ["[\(p.id)]", "label = \(p.label)"]
        if grouped { lines.append("group = \(p.group)") }
        lines.append("description = \(p.description) \(mark)")
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

    /// Every plugin put in place, brought up to date, or taken out where it cannot work. What
    /// was done; nothing when all was already right or there is no NotProton.
    static func keep() -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Engine.notproton.path) else { return [] }
        var said: [String] = []
        for p in all {
            let path = NotProtonRow.folder.appendingPathComponent(p.file)
            if let why = unworkable(p) {
                // Only a row MacGameFix wrote: its id, and the mark.
                if let mine = try? String(contentsOf: path, encoding: .utf8),
                   mine.hasPrefix("[\(p.id)]\n"), mine.contains(mark) {
                    try? fm.removeItem(at: path)
                    said.append("\(p.name) row: taken out, \(why)")
                }
                continue
            }
            if NotProtonRow.headers(besides: p.file).contains("[\(p.id)]") {
                said.append("\(p.name) row: another plugin file has \(p.id), left alone")
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
        }
        return said
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
