// What a game runs on, and whether its fix fits it.
//
// The table (process-features.json, through games.json) says what each fix
// needs: a backend (DXMT or D3DMetal), a D3DMetal generation, a CrossOver that
// ships a codec or that needs no patched engine, and a toolkit from which the
// fix is not needed at all. This file finds what each game actually runs on:
//
// - a Steam Play tool such as NotProton: Steam's CompatToolMapping names the
//   tool for the game's app id, the tool names its CrossOver build and whether
//   it runs under Rosetta or FEX, the build's runner carries the D3DMetal
//   versions, and the game's launch options choose the backend and generation;
// - a CrossOver bottle whose Steam holds the game: cxbottle.conf names the
//   CrossOver version and the backend, and that CrossOver carries D3DMetal.
//
// When it cannot tell, or tells two things, the user says which, and that
// choice wins over detection from then on.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// MARK: - What a game runs on

struct GameRuntime: Codable, Hashable {
    /// Where this came from, in the user's terms.
    var source: String
    /// CrossOver's build, e.g. 26.3.0.39832 or 27.0.0.41069; nil when unknown.
    var build: String?
    /// The D3DMetal version in use, e.g. 4.0b3; nil when unknown or none.
    var d3dmetal: String?
    /// The backend the launch options or the bottle ask for; nil for automatic.
    var backend: String?
    /// FEX runs arm64 Wine, which has no D3DMetal.
    var noD3DMetal = false
    /// Steam maps this very game to this Steam Play tool, and the tool has run
    /// it. Of several places that could run a library's game, this is the one
    /// the user set up. (Steam's LastPlayed cannot tell them apart: it belongs
    /// to the account and is the same in every Steam signed in to it.)
    var setUpHere = false

    /// The backend the game gets. Left automatic, CrossOver runs Direct3D 11
    /// and 12 games on D3DMetal; FEX has none, and what it picks is not known here.
    var effectiveBackend: String? { backend ?? (noD3DMetal ? nil : "d3dmetal") }

    /// "CrossOver 26.3" or "CrossOver Preview 27", from the build's first number.
    var crossover: String? {
        guard let major = build.flatMap({ $0.split(separator: ".").first }).flatMap({ Int($0) }) else { return nil }
        if major >= 27 { return "CrossOver Preview \(major)" }
        let parts = build!.split(separator: ".")
        return "CrossOver \(parts[0]).\(parts.count > 1 ? parts[1] : "0")"
    }

    var summary: String {
        var parts = [crossover ?? "CrossOver unknown"]
        if noD3DMetal { parts.append("no D3DMetal (FEX)") } else if let d = d3dmetal { parts.append("D3DMetal \(d)") }
        if let b = backend {
            parts.append(Game.backendName(b))
        } else {
            parts.append(noD3DMetal ? "automatic backend" : "D3DMetal (automatic)")
        }
        return parts.joined(separator: ", ") + " — " + source
    }
}

// MARK: - Steam's text files

/// Steam's text VDF: quoted keys, quoted values or braces. Keys are looked up
/// without regard to case, as Steam itself writes them both ways.
enum VDF {
    indirect enum Node { case value(String), section([String: Node]) }

    static func parse(_ text: String) -> [String: Node] {
        var tokens: [String?] = [] // nil stands for a brace: true open below
        var opens: [Bool] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "\"" {
                var s = ""
                i = text.index(after: i)
                while i < text.endIndex, text[i] != "\"" {
                    if text[i] == "\\", text.index(after: i) < text.endIndex {
                        i = text.index(after: i)
                    }
                    s.append(text[i])
                    i = text.index(after: i)
                }
                tokens.append(s); opens.append(false)
            } else if c == "{" || c == "}" {
                tokens.append(nil); opens.append(c == "{")
            } else if c == "/", text[i...].hasPrefix("//") {
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                continue
            }
            if i < text.endIndex { i = text.index(after: i) }
        }
        var at = 0
        func section() -> [String: Node] {
            var out: [String: Node] = [:]
            while at < tokens.count {
                guard let key = tokens[at] else { at += 1; return out } // a closing brace
                at += 1
                guard at < tokens.count else { break }
                if let value = tokens[at] {
                    out[key.lowercased()] = .value(value); at += 1
                } else if opens[at] {
                    at += 1
                    // Steam writes some sections twice in different case
                    // ("apps" and "Apps"): the two are merged, not replaced.
                    let inner = section(), k = key.lowercased()
                    if case .section(let earlier)? = out[k] {
                        out[k] = .section(earlier.merging(inner) { _, new in new })
                    } else {
                        out[k] = .section(inner)
                    }
                } else {
                    at += 1 // a closing brace where a value belongs: the file is cut short
                    return out
                }
            }
            return out
        }
        return section()
    }

    static func find(_ root: [String: Node], _ path: [String]) -> Node? {
        var node: Node = .section(root)
        for key in path {
            guard case .section(let s) = node, let next = s[key.lowercased()] else { return nil }
            node = next
        }
        return node
    }

    static func string(_ root: [String: Node], _ path: [String]) -> String? {
        if case .value(let v)? = find(root, path) { return v }
        return nil
    }
}

// MARK: - Finding it

enum Runtimes {
    static var steam: URL { Paths.home.appendingPathComponent("Library/Application Support/Steam") }
    static var notproton: URL { Paths.home.appendingPathComponent("Library/Application Support/notproton") }

    /// Every way this game folder could be run that the Mac shows: usually one.
    static func detect(folder: URL) -> [GameRuntime] {
        var found: [GameRuntime] = []
        if let app = SteamApp.of(folder: folder), let r = steamPlay(appid: app.appid) { found.append(r) }
        found += bottles(holding: folder)
        return found
    }

    /// The Steam Play tool Steam maps the app to, when it is one whose build
    /// NotProton's runners carry.
    static func steamPlay(appid: String) -> GameRuntime? {
        guard let text = try? String(contentsOf: steam.appendingPathComponent("config/config.vdf"), encoding: .utf8)
        else { return nil }
        let root = VDF.parse(text)
        let mapping = ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"]
        guard let tool = VDF.string(root, mapping + [appid, "name"]) ?? VDF.string(root, mapping + ["0", "name"]),
              !tool.isEmpty else { return nil }
        let dir = steam.appendingPathComponent("compatibilitytools.d/\(tool)")
        guard let build = (try? String(contentsOf: dir.appendingPathComponent("build"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !build.isEmpty else {
            return GameRuntime(source: "Steam Play tool \(tool)")
        }
        let flavor = (try? String(contentsOf: dir.appendingPathComponent("flavor"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let options = launchOptions(appid: appid)
        var r = GameRuntime(source: "NotProton, \(tool)", build: build.split(separator: "-").first.map(String.init),
                            backend: options["CX_GRAPHICS_BACKEND"].flatMap { $0.isEmpty ? nil : $0.lowercased() })
        r.setUpHere = VDF.string(root, mapping + [appid, "name"]) != nil && ranHere(appid: appid)
        if flavor == "fex" {
            r.noD3DMetal = true
        } else {
            let root = notproton.appendingPathComponent("runners/crossover-\(build)/CrossOver")
            r.d3dmetal = d3dmetal(in: root, generation: options["CX_GRAPHICS_BACKEND_VERSION"])
        }
        return r
    }

    /// The bottles whose Steam declares the library this game sits in.
    static func bottles(holding folder: URL) -> [GameRuntime] {
        let library = folder.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .standardizedFileURL.path.lowercased()
        var out: [GameRuntime] = []
        for bottle in Libraries.bottles() {
            let vdf = bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam/config/libraryfolders.vdf")
            guard let text = try? String(contentsOf: vdf, encoding: .utf8) else { continue }
            let declared = Libraries.paths(in: text).compactMap { Libraries.translate($0, inBottle: bottle)?.path.lowercased() }
            guard declared.contains(library) else { continue }
            let conf = (try? String(contentsOf: bottle.appendingPathComponent("cxbottle.conf"), encoding: .utf8)) ?? ""
            let version = confValue("Version", in: conf)
            var r = GameRuntime(source: "CrossOver bottle “\(bottle.lastPathComponent)”", build: version,
                                backend: confValue("CX_GRAPHICS_BACKEND", in: conf).map { $0.lowercased() })
            if let version, let app = crossOverApp(build: version) {
                r.d3dmetal = d3dmetal(in: app.appendingPathComponent("Contents/SharedSupport/CrossOver"),
                                      generation: confValue("CX_GRAPHICS_BACKEND_VERSION", in: conf))
            }
            out.append(r)
        }
        return out
    }

    /// NotProton has started this game: its run log sits in the game's
    /// compatdata, in any library Steam knows.
    static func ranHere(appid: String) -> Bool {
        Libraries.all(extra: []).contains { common in
            FileManager.default.fileExists(atPath: common.deletingLastPathComponent()
                .appendingPathComponent("compatdata/\(appid)/notproton-run.log").path)
        }
    }

    /// Each user's localconfig.vdf in a Steam, the most recently written first.
    static func localConfigs(_ steam: URL) -> [URL] {
        let userdata = steam.appendingPathComponent("userdata")
        return ((try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("config/localconfig.vdf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
    }

    /// KEY=value pairs of a game's Steam launch options, before %command%.
    static func launchOptions(appid: String) -> [String: String] {
        let userdata = steam.appendingPathComponent("userdata")
        let users = ((try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .map { $0.appendingPathComponent("config/localconfig.vdf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
        for file in users {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let root = VDF.parse(text)
            guard let options = VDF.string(root, ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", appid,
                                                  "LaunchOptions"]) else { continue }
            let head = options.components(separatedBy: "%command%").first ?? options
            var out: [String: String] = [:]
            let pattern = try! NSRegularExpression(pattern: #"(?:^|\s)([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|'[^']*'|\S*)"#)
            for m in pattern.matches(in: head, range: NSRange(head.startIndex..., in: head)) {
                guard let k = Range(m.range(at: 1), in: head), let v = Range(m.range(at: 2), in: head) else { continue }
                out[String(head[k])] = String(head[v]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            return out
        }
        return [:]
    }

    /// The D3DMetal a CrossOver tree runs: apple_gptk, or the generation the
    /// launch options or the bottle choose (apple_gptk3, apple_gptk_4, ...).
    static func d3dmetal(in crossover: URL, generation: String?) -> String? {
        let fm = FileManager.default
        for lib in ["lib", "lib64"] {
            let base = crossover.appendingPathComponent(lib)
            var names = ["apple_gptk"]
            if let g = generation, !g.isEmpty, g.allSatisfy(\.isNumber) { names = ["apple_gptk\(g)", "apple_gptk_\(g)"] }
            for name in names {
                let plist = base.appendingPathComponent("\(name)/external/D3DMetal.framework/Versions/A/Resources/Info.plist")
                if fm.fileExists(atPath: plist.path),
                   let v = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String { return v }
            }
        }
        return nil
    }

    /// An installed CrossOver whose build is this one.
    static func crossOverApp(build: String) -> URL? {
        let fm = FileManager.default
        for dir in [URL(fileURLWithPath: "/Applications"), Paths.home.appendingPathComponent("Applications")] {
            for app in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where app.pathExtension == "app" && app.lastPathComponent.lowercased().hasPrefix("crossover") {
                let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
                if info?["CFBundleVersion"] as? String == build { return app }
            }
        }
        return nil
    }

    static func confValue(_ key: String, in conf: String) -> String? {
        for line in conf.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("\"\(key)\"") else { continue }
            let parts = t.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 4 { return String(parts[3]) }
        }
        return nil
    }

    /// What can be chosen when detection cannot tell: the CrossOver builds and
    /// D3DMetal versions this Mac carries.
    static func installedChoices() -> (builds: [String], d3dmetal: [String]) {
        var builds = Set<String>(), versions = Set<String>()
        let fm = FileManager.default
        func scan(_ crossover: URL) {
            for lib in ["lib", "lib64"] {
                let base = crossover.appendingPathComponent(lib)
                for name in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] where name.hasPrefix("apple_gptk") {
                    let plist = base.appendingPathComponent("\(name)/external/D3DMetal.framework/Versions/A/Resources/Info.plist")
                    if let v = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String { versions.insert(v) }
                }
            }
        }
        for dir in [URL(fileURLWithPath: "/Applications"), Paths.home.appendingPathComponent("Applications")] {
            for app in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where app.pathExtension == "app" && app.lastPathComponent.lowercased().hasPrefix("crossover") {
                if let b = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleVersion"] as? String {
                    builds.insert(b)
                }
                scan(app.appendingPathComponent("Contents/SharedSupport/CrossOver"))
            }
        }
        for runner in (try? fm.contentsOfDirectory(at: notproton.appendingPathComponent("runners"), includingPropertiesForKeys: nil)) ?? [] {
            let name = runner.lastPathComponent
            if name.hasPrefix("crossover-") {
                builds.insert(String(name.dropFirst("crossover-".count).split(separator: "-").first ?? ""))
            }
            scan(runner.appendingPathComponent("CrossOver"))
        }
        builds.remove("")
        return (builds.sorted(by: { Catalog.versionLess($1, $0) }), versions.sorted(by: { D3DMetalVersion($1) < D3DMetalVersion($0) }))
    }
}

// MARK: - Whether the fix fits

/// A D3DMetal version that orders 4.0b2 < 4.0b3 < 4.0.
struct D3DMetalVersion: Comparable {
    let parts: [Int]
    init(_ s: String) {
        let lower = s.lowercased()
        let (release, beta) = lower.contains("b")
            ? (String(lower.split(separator: "b")[0]), Int(lower.split(separator: "b").last ?? "") ?? 0)
            : (lower, Int.max)
        var p = release.split(separator: ".").map { Int($0) ?? 0 }
        while p.count < 2 { p.append(0) }
        parts = p + [beta]
    }
    static func < (a: Self, b: Self) -> Bool {
        for (x, y) in zip(a.parts, b.parts) where x != y { return x < y }
        return a.parts.count < b.parts.count
    }
}

enum Fit: Equatable {
    case fits
    case notNeeded(String)
    case mismatch([String])
    case unknown([String])

    var label: String {
        switch self {
        case .fits: return "Fits what this game runs on"
        case .notNeeded(let why): return "Not needed: \(why)"
        case .mismatch(let why): return "Does not fit: " + why.joined(separator: "; ")
        case .unknown(let why): return "Cannot tell: " + why.joined(separator: "; ")
        }
    }

    /// Whether the agent may install the fix by itself.
    var allowsAutomatic: Bool { self == .fits }
}

extension Game {
    static func backendName(_ b: String) -> String {
        ["dxmt": "DXMT", "d3dmetal": "D3DMetal", "dxvk": "DXVK", "wined3d": "WineD3D"][b] ?? b
    }

    /// The fix against what the game runs on, by the table's requirements.
    func fit(on r: GameRuntime) -> Fit {
        var bad: [String] = [], unknown: [String] = []
        let needsCrossOver = codecShippedBy.isEmpty ? engineFreeOn : codecShippedBy
        if !needsCrossOver.isEmpty {
            let wanted = Int(needsCrossOver.split(whereSeparator: { !$0.isNumber }).first ?? "") ?? 0
            if let have = r.build.flatMap({ $0.split(separator: ".").first }).flatMap({ Int($0) }) {
                if have < wanted { bad.append("needs \(needsCrossOver); this is \(r.crossover ?? "older")") }
            } else {
                unknown.append("needs \(needsCrossOver)")
            }
        }
        if !backend.isEmpty {
            let name = Self.backendName(backend)
            if backend == "d3dmetal" && r.noD3DMetal {
                bad.append("made for D3DMetal, which FEX does not have")
            } else if let have = r.effectiveBackend {
                if have != backend {
                    bad.append("made for \(name), and this game runs on \(Self.backendName(have))"
                               + (r.backend == nil ? ", the automatic backend" : "")
                               + "; CX_GRAPHICS_BACKEND=\(backend) runs it on \(name)")
                }
            } else {
                unknown.append("made for \(name), and the backend is automatic: set CX_GRAPHICS_BACKEND=\(backend), "
                               + "or say which backend below")
            }
        }
        if !gptk.isEmpty && backend != "dxmt" {
            let allowed = [gptk, gptkAlso].filter { !$0.isEmpty }
            if let have = r.d3dmetal {
                if !allowed.contains(where: { have.hasPrefix($0) }) {
                    bad.append("needs D3DMetal \(allowed.joined(separator: " or ")); this is \(have)")
                }
            } else if !r.noD3DMetal {
                unknown.append("needs D3DMetal \(allowed.joined(separator: " or "))")
            }
        }
        if !bad.isEmpty { return .mismatch(bad) }
        if !notNeededFrom.isEmpty, backend != "dxmt", r.effectiveBackend == "d3dmetal", let have = r.d3dmetal,
           D3DMetalVersion(have) >= D3DMetalVersion(notNeededFrom) {
            return .notNeeded("the game plays without it on D3DMetal \(notNeededFrom) and later")
        }
        if !unknown.isEmpty { return .unknown(unknown) }
        return .fits
    }
}
