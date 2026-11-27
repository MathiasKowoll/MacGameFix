// NotProton panel rows MacGameFix keeps for every game: one plugin file each, written where
// NotProton is, and rewritten only when what this Mac calls for has changed.
//
//   ProcessorsRow  "Processors the game sees"   (ProcessorsRow.swift)
//   FrameCapRow    "Frame rate cap"              D3DM_MAX_FPS, in the rates this Mac's display holds
//   RayTracingRow  "Ray tracing off"             D3DM_SUPPORT_DXR=0
//   DriverVersionRow "NVIDIA driver version"     D3DMetal's driver version, patched in memory
//
// and the plugins NotProton's creator ported from MacGameFix's fixes (NotProtonPlugins.swift).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

enum NotProtonRow {
    /// NotProton keeps 32 rows in all and offers 16 values in a choice row.
    static let maxRows = 32
    static let maxChoices = 16
    static var folder: URL { Engine.notproton.appendingPathComponent("plugins") }

    /// Whether the NotProton Steam runs knows the group field. An older one refuses a row with a
    /// field it does not know.
    static func knowsGroups() -> Bool { knows("group") }

    /// A row's label line. A row in one of MacGameFix's groups does not name MacGameFix again;
    /// with no group to say whose it is, the label does.
    static func label(_ name: String, grouped: Bool) -> String {
        grouped ? "label = \(name)" : "label = \(name) (MacGameFix)"
    }

    /// Whether every NotProton Steam runs knows a field: its run script lists the fields it reads.
    static func knows(_ field: String) -> Bool {
        let tools = Paths.home.appendingPathComponent("Library/Application Support/Steam/compatibilitytools.d")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: tools.path) else { return false }
        // A folder with no run script is no tool Steam can run (one NotProton emptied, with
        // other files left in it), so it has no say.
        let runs = names.filter { $0.lowercased().hasPrefix("notproton") }
            .map { tools.appendingPathComponent($0).appendingPathComponent("run") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !runs.isEmpty else { return false }
        return runs.allSatisfy { run in
            guard let script = try? String(contentsOf: run, encoding: .utf8),
                  let line = script.split(separator: "\n").first(where: { $0.contains("split(\"label description") })
            else { return false }
            return line.split(whereSeparator: { $0 == " " || $0 == "\"" }).contains(Substring(field))
        }
    }

    /// One row put in place, or brought up to date. `text` is the row for a NotProton that
    /// knows groups or not, or nil with the reason it cannot be made on this Mac. What it did,
    /// or why it did nothing; nil when the row was already right or there is no NotProton.
    static func keep(name: String, id: String, file: String, written: String,
                     text: (Bool) -> Result<String, Failure>) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Engine.notproton.path) else { return nil }
        let path = folder.appendingPathComponent(file)
        let headers = headers(besides: file)
        // NotProton refuses an id that two files declare: neither row would show.
        if headers.contains("[\(id)]") { return "\(name) row: another plugin file has \(id), left alone" }
        let mine = try? String(contentsOf: path, encoding: .utf8)
        if mine == nil && headers.count >= maxRows { return "\(name) row: NotProton's \(maxRows) rows are taken" }
        let row: String
        switch text(knowsGroups()) {
        case .success(let made): row = made
        case .failure(let why): return "\(name) row: \(why.text)"
        }
        guard mine != row else { return nil }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try row.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            return "\(name) row: \(error.localizedDescription)"
        }
        return "\(name) row: \(written)"
    }

    /// The ids the other plugin files in NotProton's folder declare, "[ID]" each.
    static func headers(besides file: String) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".conf") && $0 != file }
            .compactMap { try? String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) }
            .flatMap { $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { $0.hasPrefix("[") && $0.hasSuffix("]") }
    }

    struct Failure: Error { let text: String }

    /// Every row MacGameFix keeps, in the agent's pass and the window's scan.
    static func keepAll() -> [String] {
        [ProcessorsRow.keep(), FrameCapRow.keep(), RayTracingRow.keep(), DriverVersionRow.keep()].compactMap { $0 }
            + NotProtonPlugins.keep()
    }
}

/// D3DMetal 4 holds a game to D3DM_MAX_FPS by presenting each frame no sooner than 1/cap after
/// the one before. A Mac's display only shows a frame at its own steps: an M4 Max MacBook Pro's
/// panel at 240/n, so 120, 80, 60, 48, 40... A cap of exactly 60 asks for no sooner than the
/// 60 Hz step itself, any delay pushes a frame to the next one, and the game holds 48: any cap
/// from 48 to 60 held 48, and 70 held 60.00 with a flat 16.67 ms (measured 2026-09-26, Metal
/// HUD). So each rate offered writes the value halfway to the next faster step, and the row
/// is made from the display this Mac has. D3DMetal 3 has no such variable: the row is for the
/// Preview tools, which run D3DMetal 4.
enum FrameCapRow {
    static let id = "NOTPROTON_ENV_D3DM_MAX_FPS"
    static let file = "mgf-fps.conf"

    /// The main display's fastest rate and the rate of its steps (0: steps of its refresh).
    /// MACGAMEFIX_DISPLAY="<fastest>,<steps>" stands in for the display in the tests.
    static func display() -> (fastest: Int, steps: Double)? {
        if let given = ProcessInfo.processInfo.environment["MACGAMEFIX_DISPLAY"] {
            let parts = given.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 && parts[0] > 0 ? (Int(parts[0]), parts[1]) : nil
        }
        guard let screen = NSScreen.screens.first, screen.maximumFramesPerSecond > 0 else { return nil }
        let granularity = screen.displayUpdateGranularity
        // The step comes as an interval (1/240 s reads back as 239.99... Hz): whole hertz.
        return (screen.maximumFramesPerSecond, granularity > 0 ? (1 / granularity).rounded() : 0)
    }

    /// The rates offered below the fastest, each with the value that holds it: whole rates
    /// from 24 up, the display's steps.
    static func choices(fastest: Int, steps: Double) -> [(rate: Int, value: Int)] {
        let base = steps > 0 ? steps : Double(fastest)
        var picked: [(Int, Int)] = []
        var n = 2.0
        while base / n >= 24 {
            let rate = base / n, faster = base / (n - 1)
            if rate < Double(fastest) - 0.01, abs(rate - rate.rounded()) < 0.01 {
                picked.append((Int(rate.rounded()), Int(((rate + faster) / 2).rounded(.down))))
            }
            n += 1
        }
        return Array(picked.prefix(NotProtonRow.maxChoices - 1))
    }

    static func text(fastest: Int, steps: Double, grouped: Bool) -> String {
        var lines = ["[\(id)]", NotProtonRow.label("Frame rate cap", grouped: grouped)]
        if grouped { lines.append("group = MacGameFix / Performance") }
        lines += [
            "description = Holds the game to a rate this display (\(fastest) Hz) can keep. Preview tools only",
            "section = dev",
            "type = choice",
            "default = 0",
            "choice = 0 = No limit (\(fastest) Hz)",
        ]
        for (rate, value) in choices(fastest: fastest, steps: steps) {
            lines.append("choice = \(value) = \(rate) fps")
        }
        lines += ["tools = notproton-fex*", "tools = notproton-preview*"]
        return lines.joined(separator: "\n") + "\n"
    }

    @discardableResult
    static func keep() -> String? {
        let shown = display()
        return NotProtonRow.keep(name: "frame rate cap", id: id, file: file,
                                 written: "written for a \(shown?.fastest ?? 0) Hz display") { grouped in
            guard let (fastest, steps) = shown else { return .failure(.init(text: "this Mac's display could not be read")) }
            return .success(text(fastest: fastest, steps: steps, grouped: grouped))
        }
    }
}

/// D3DM_SUPPORT_DXR=0 makes D3DMetal say it has no ray tracing. A game that closes, or crashes
/// as it loads a level, where D3DMetal offers ray tracing it cannot do then starts without it:
/// Phantom Blade Zero with DLSS on (D3DMetal's NVAPI offers opacity micromaps it cannot build),
/// played on Preview 41073. The game's own ray tracing settings go away with it.
enum RayTracingRow {
    static let id = "NOTPROTON_MGF_DXR_OFF"
    static let file = "mgf-dxr.conf"

    static func text(grouped: Bool) -> String {
        var lines = ["[\(id)]", NotProtonRow.label("Ray tracing off", grouped: grouped)]
        if grouped { lines.append("group = MacGameFix / D3DMetal") }
        lines += [
            "description = The game sees no ray tracing. For a game that closes as a level loads: Phantom Blade Zero with DLSS on",
            "section = dev",
            "on = 1",
            "env = D3DM_SUPPORT_DXR=0",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    @discardableResult
    static func keep() -> String? {
        NotProtonRow.keep(name: "ray tracing", id: id, file: file, written: "written") { .success(text(grouped: $0)) }
    }
}

/// D3DMetal answers a game's question for the NVIDIA driver (NvAPI) with a version of its own:
/// 576.02 in D3DMetal 4 (CrossOver Preview 41303), 561.09 in D3DMetal 3 and in CrossOver 26.3's
/// D3DMetal 4. A game that wants a newer one asks for a driver update at every start: EA SPORTS
/// FC 27 1.0.143 wants 610.62. The version is a constant in two instructions, each followed by
/// the driver's branch ("r616_41", "r560_88"), and the row writes 99999 (999.99) over both, in
/// memory: one form per version, each found once in the builds named above. A D3DMetal that
/// reports another version needs a form of its own (NotProton reads four in a patch).
///
/// With the row on, FC 27 started with no dialog and reached its menu (NotProton 41303 under
/// Rosetta, 2026-11-26). Wine's own driver version, in the registry, is not this one.
enum DriverVersionRow {
    static let id = "NOTPROTON_MGF_NVIDIA_DRIVER"
    static let file = "mgf-nvidia-driver.conf"

    static func text(grouped: Bool) -> String {
        var lines = ["[\(id)]", NotProtonRow.label("NVIDIA driver version", grouped: grouped)]
        if grouped { lines.append("group = MacGameFix / D3DMetal") }
        lines += [
            "description = The game sees a newer NVIDIA driver and stops asking for a driver update. Played with EA SPORTS FC 27",
            "on = 1",
            "tools = notproton-fex-rosetta*",
            "patch = D3DMetal/x86_64: 48 c7 42 04 02=9f e1=86 00=01 00 48 b8 72 36 31 36 5f 34 31 | 48 c7 42 04 2d=9f db=86 00=01 00 48 b8 72 35 36 30 5f 38 38",
            "patch = D3DMetal/x86_64: c7 01 02=9f e1=86 00=01 00 48 b8 72 36 31 36 5f 34 31 | c7 01 2d=9f db=86 00=01 00 48 b8 72 35 36 30 5f 38 38",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    @discardableResult
    static func keep() -> String? {
        // An older NotProton refuses a row with a field it does not know: it gets none.
        guard NotProtonRow.knows("patch") else {
            let path = NotProtonRow.folder.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: path.path) else { return nil }
            try? FileManager.default.removeItem(at: path)
            return "NVIDIA driver row: taken out, the NotProton in Steam does not read patch"
        }
        return NotProtonRow.keep(name: "NVIDIA driver", id: id, file: file, written: "written") { .success(text(grouped: $0)) }
    }
}
