// NotProton rows switched on for a game, once, by MacGameFix.
//
// NotProton loads a plugin only into a game whose row is switched on in the game's launch
// options (NOTPROTON_<ID>=1); a row has no "on for every game". So the rows a game is known to
// want are switched on for it here, from two sources:
//
//   the catalog   notproton-rows.json, carried by the signed fixes catalog: for each game by its
//                 Steam app id, the rows that help it (Shaders kept whole for Ori and Phantom
//                 Blade Zero). A catalog update adds games without a new app.
//   Game Feel     a game whose DualSense options were set up there gets the DualSense
//                 controllers row, which loads the library that reads those options.
//
// A row is switched on only where its plugin is installed and in place, only for a game a Steam
// library has, only while Steam is closed (Steam writes the launch options back when it quits),
// and only once for each game: steam-launch-options.pl writes it in front of the game's options
// and keeps a journal of what was there. A row the player then switches off in Steam stays off.
// Removing the plugin gives each game's launch options back as they were, through its journal.
// Options that start with a program rather than variables are not touched, and that is noted.
//
// The JSON has a schema version, and the app says in its Info.plist which one it reads
// (MacGameFixRowsSchemaVersion), so another program can tell what this app understands without
// trying it; a newer schema than this app reads is not applied. The idea of a versioned JSON
// with the version in the Info.plist is from Tobias Sauer's games report (PR #139).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum RowsByGame {
    /// The notproton-rows.json schema this app reads.
    static let schema = 1
    static let controls = "NOTPROTON_MGF_CONTROLS"

    struct Table: Decodable {
        let schema: Int
        let games: [Entry]
    }
    struct Entry: Decodable {
        let appid: String
        let title: String
        let rows: [String]
    }

    /// One row for one game, and where it came from.
    struct Want: Hashable {
        let appid: String
        let id: String
        let why: String
    }

    static var record: URL { Paths.support.appendingPathComponent("notproton-rows.applied") }
    static var journals: URL { Paths.support.appendingPathComponent("notproton-rows") }
    static func journal(_ appid: String, _ id: String) -> URL { journals.appendingPathComponent("\(appid)-\(id).json") }

    /// The catalog's table; nil when there is none, or its schema is newer than this app reads.
    static func table(in dir: URL = Catalog.active().dir) -> Table? {
        // MACGAMEFIX_ROWS_TABLE stands in for the catalog's in the tests.
        let file = ProcessInfo.processInfo.environment["MACGAMEFIX_ROWS_TABLE"].map { URL(fileURLWithPath: $0) }
            ?? dir.appendingPathComponent("notproton-rows.json")
        guard let data = try? Data(contentsOf: file),
              let table = try? JSONDecoder().decode(Table.self, from: data), table.schema <= schema else { return nil }
        return table
    }

    /// Every row some source wants, for every game it names.
    static func wanted() -> [Want] {
        var out: [Want] = []
        for game in table()?.games ?? [] where game.appid.allSatisfy(\.isNumber) && !game.appid.isEmpty {
            out += game.rows.map { Want(appid: game.appid, id: $0, why: "catalog") }
        }
        if PadStore.exists {
            for (appid, game) in PadStore.load().games
            where appid.allSatisfy(\.isNumber) && !appid.isEmpty && !game.options.lines.isEmpty {
                out.append(Want(appid: appid, id: controls, why: "Game Feel"))
            }
        }
        return Array(Set(out)).sorted { ($0.appid, $0.id) < ($1.appid, $1.id) }
    }

    /// What was done for each game and row: "<app id> <id> on" or "<app id> <id> refused <why>".
    static func done() -> [String: String] {
        let text = (try? String(contentsOf: record, encoding: .utf8)) ?? ""
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let words = line.split(separator: " ", maxSplits: 2).map(String.init)
            guard words.count >= 3 else { continue }
            out["\(words[0]) \(words[1])"] = words[2]
        }
        return out
    }

    static func save(_ done: [String: String]) {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let text = done.keys.sorted().map { "\($0) \(done[$0]!)" }.joined(separator: "\n")
        try? (text.isEmpty ? "" : text + "\n").write(to: record, atomically: true, encoding: .utf8)
    }

    /// Whether a Steam library has the game.
    static func installed(_ appid: String) -> Bool {
        let fm = FileManager.default
        return Libraries.all(extra: []).contains {
            fm.fileExists(atPath: $0.deletingLastPathComponent().appendingPathComponent("appmanifest_\(appid).acf").path)
        }
    }

    /// The program that writes a game's launch options. MACGAMEFIX_LAUNCH_OPTIONS stands in for it
    /// in the tests, which must not ask whether the Mac's own Steam is running.
    static var writer: URL {
        if let path = ProcessInfo.processInfo.environment["MACGAMEFIX_LAUNCH_OPTIONS"] { return URL(fileURLWithPath: path) }
        return Catalog.active().dir.appendingPathComponent("steam-launch-options.pl")
    }

    static func options(_ mode: String, _ appid: String, _ id: String) -> (Int32, String) {
        NotProtonPlugins.command("/usr/bin/perl", [writer.path, mode, appid, journal(appid, id).path, "\(id)=1"],
                                 ["HOME": Paths.home.path])
    }

    /// The rows whose plugin is installed and in place, by id.
    static func ready() -> Set<String> {
        guard let states = NotProtonPlugins.states() else { return [] }
        return Set(states.filter { $0.state == .inPlace }.map(\.id))
    }

    /// Every wanted row not switched on yet, switched on: nothing while Steam is open. What was done.
    static func pass() -> [String] {
        let ready = ready()
        var done = done()
        let todo = wanted().filter { ready.contains($0.id) && done["\($0.appid) \($0.id)"] == nil && installed($0.appid) }
        guard !todo.isEmpty, !NotProtonHost.open().contains("Steam") else { return [] }
        try? FileManager.default.createDirectory(at: journals, withIntermediateDirectories: true)
        var said: [String] = []
        for want in todo {
            let (status, output) = options("install", want.appid, want.id)
            let key = "\(want.appid) \(want.id)"
            if status == 0 {
                done[key] = "on"
                said.append("\(key): switched on (\(want.why))")
            } else if output.contains("start with a program") {
                // The player's own: never touched, and not tried again.
                done[key] = "refused the launch options start with a program"
                said.append("\(key): not switched on, the game's launch options start with a program")
            }
            // Anything else (a game Steam has not started yet has no launch options) is tried again at
            // the next pass, without a word each time: the report says what waits.
        }
        save(done)
        return said
    }

    /// Every game's launch options given back for one row, as they were before it was switched on;
    /// for a plugin being removed (Steam closed). What was done.
    static func undo(_ id: String) -> [String] {
        var done = done()
        var said: [String] = []
        for key in done.keys.sorted() where key.hasSuffix(" \(id)") {
            let appid = String(key.split(separator: " ")[0])
            if done[key] == "on" {
                let (status, output) = options("restore", appid, id)
                guard status == 0 else {
                    said.append("\(key): launch options not given back, \(output.split(separator: "\n").last.map(String.init) ?? "it failed")")
                    continue
                }
                said.append("\(key): launch options given back")
            }
            done[key] = nil
        }
        save(done)
        return said
    }

    /// One line for each wanted row, for --rows-by-game-report and the tests.
    static func report() -> String {
        let ready = ready(), done = done()
        let lines = wanted().map { want -> String in
            let key = "\(want.appid) \(want.id)"
            let state: String
            if let d = done[key] { state = d == "on" ? "switched on" : d.replacingOccurrences(of: "refused ", with: "not switched on, ") }
            else if !ready.contains(want.id) { state = "waits for its plugin" }
            else if !installed(want.appid) { state = "the game is not installed" }
            else { state = "to switch on while Steam is closed" }
            return "\(key) (\(want.why)): \(state)"
        }
        return (lines.isEmpty ? ["rows by game: none"] : lines).joined(separator: "\n")
    }
}
