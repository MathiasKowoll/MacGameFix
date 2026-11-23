// A Windows program run inside a game's NotProton prefix: a mod installer or a mod manager,
// with the same runner the game uses.
//
// It does what NotProton's own Prefixes › Run Program… does (PrefixTools.run in NotProton's
// app): the runner is NotProton's clone of the CrossOver build the game's tool names, the
// loader and wineserver are the ones for the tool's flavour (FEX or Rosetta), the environment
// is the same few variables, and the program starts in its own folder. Which tool a game uses
// is Steam's CompatToolMapping in config.vdf; each NotProton tool folder says its build and
// flavour. A game whose tool says nothing falls back to the build NotProton wrote into the
// prefix (notproton-build) and the flavour of the prefix's own ntdll.dll.
//
// Nothing starts while the prefix is in use: NotProton holds .notproton-prefix.lock while a
// launch sets the prefix up, and a running game (or anything else in that prefix) keeps its
// wineserver's socket folder open. Wine started beside it would share a half-made prefix or
// the game's own server.
//
// CrossOver bottles are left out: running a program in one goes through CrossOver's own
// launcher and its bottle settings, which MacGameFix does not drive.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum PrefixRunner {
    enum Flavor: String { case rosetta, fex }

    struct Target: Equatable {
        let pfx: URL
        let appid: String
        let build: String
        let flavor: Flavor
        let runner: URL
        let loader: URL
        let server: URL
        let unixDir: URL
        /// The Steam tool it came from, or nil when it came from the prefix's own record.
        let tool: String?
    }

    struct Failure: Error, Equatable { let message: String }

    static var steam: URL { Paths.home.appendingPathComponent("Library/Application Support/Steam") }
    static var runners: URL { Engine.notproton.appendingPathComponent("runners") }
    /// Where wineservers keep their sockets. MACGAMEFIX_WINE_SERVER_ROOT stands in for it in the tests.
    static var serverRoot: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["MACGAMEFIX_WINE_SERVER_ROOT"]
            ?? "/tmp/.wine-\(getuid())")
    }
    /// The last output of each run, per game.
    static var logs: URL { Paths.support.appendingPathComponent("prefix-runs") }
    static let extensions = ["exe", "msi", "bat", "cmd"]

    /// What the loader is given for a program, as NotProton gives it.
    static func arguments(for program: URL) -> [String]? {
        switch program.pathExtension.lowercased() {
        case "exe", "bat", "cmd": return [program.path]
        case "msi": return ["msiexec", "/i", program.path]
        default: return nil
        }
    }

    // MARK: Which runner

    /// The strings and braces of a VDF file, in order.
    private static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "{" || c == "}" { out.append(String(c)); i = text.index(after: i); continue }
            if c == "\"" {
                var s = "", j = text.index(after: i)
                while j < text.endIndex, text[j] != "\"" {
                    if text[j] == "\\", text.index(after: j) < text.endIndex { j = text.index(after: j) }
                    s.append(text[j]); j = text.index(after: j)
                }
                out.append(s)
                i = j < text.endIndex ? text.index(after: j) : j
                continue
            }
            i = text.index(after: i)
        }
        return out
    }

    /// The tool Steam runs appid with, from config.vdf's CompatToolMapping; "0" is the
    /// default Steam Play tool, used when the game names none.
    static func mappedTool(_ appid: String) -> String? {
        let config = steam.appendingPathComponent("config/config.vdf")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        let t = tokens(text)
        guard let start = t.firstIndex(of: "CompatToolMapping"), start + 1 < t.count, t[start + 1] == "{" else { return nil }
        var names: [String: String] = [:]
        var depth = 0, i = start + 1, key: String?
        while i < t.count {
            let tok = t[i]
            if tok == "{" { depth += 1 }
            else if tok == "}" { depth -= 1; if depth == 0 { break } }
            else if depth == 1, i + 1 < t.count, t[i + 1] == "{" { key = tok }
            else if depth == 2, tok == "name", i + 1 < t.count, let k = key { names[k] = t[i + 1]; i += 1 }
            i += 1
        }
        for k in [appid, "0"] { if let n = names[k], !n.isEmpty { return n } }
        return nil
    }

    /// The flavour of a prefix's own ntdll.dll: arm64 is FEX's, anything else Rosetta's.
    static func prefixFlavor(_ pfx: URL) -> Flavor? {
        let dll = pfx.appendingPathComponent("drive_c/windows/system32/ntdll.dll")
        guard let data = try? Data(contentsOf: dll), data.count >= 0x40 else { return nil }
        let lfanew = Int(data[0x3c]) | Int(data[0x3d]) << 8 | Int(data[0x3e]) << 16 | Int(data[0x3f]) << 24
        guard lfanew >= 0, lfanew + 6 <= data.count,
              data[lfanew] == 0x50, data[lfanew + 1] == 0x45, data[lfanew + 2] == 0, data[lfanew + 3] == 0
        else { return nil }
        let machine = Int(data[lfanew + 4]) | Int(data[lfanew + 5]) << 8
        return machine == 0xAA64 ? .fex : .rosetta
    }

    private static func firstLine(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let line = text.split(separator: "\n", omittingEmptySubsequences: false).first?
                .trimmingCharacters(in: .whitespaces), !line.isEmpty else { return nil }
        return line
    }

    /// The runner, loader and wineserver for a game's prefix (steamapps/compatdata/<appid>/pfx).
    static func target(for pfx: URL) -> Result<Target, Failure> {
        let fm = FileManager.default
        let root = pfx.deletingLastPathComponent()
        let appid = root.lastPathComponent
        guard fm.fileExists(atPath: pfx.appendingPathComponent("drive_c").path) else {
            return .failure(Failure(message: "The game has no prefix yet. Start it once from Steam first."))
        }
        var build: String?, flavor: Flavor?, toolName: String?
        if let name = mappedTool(appid), name.lowercased().hasPrefix("notproton") {
            let dir = steam.appendingPathComponent("compatibilitytools.d/\(name)")
            if let b = firstLine(dir.appendingPathComponent("build")),
               let f = firstLine(dir.appendingPathComponent("flavor")).flatMap(Flavor.init(rawValue:)) {
                build = b; flavor = f; toolName = name
            }
        }
        if build == nil {
            build = firstLine(root.appendingPathComponent("notproton-build"))
            flavor = prefixFlavor(pfx)
        }
        guard let build, let flavor else {
            return .failure(Failure(message: "MacGameFix cannot tell which NotProton runner this game uses. Start it once from Steam with NotProton first."))
        }
        let runner = runners.appendingPathComponent("crossover-\(build)/CrossOver")
        guard fm.fileExists(atPath: runner.path) else {
            return .failure(Failure(message: "The game's runner (CrossOver build \(build)) is not in NotProton's runners. Start the game once from Steam, or set its tool up again in NotProton."))
        }
        func executable(_ u: URL) -> Bool { fm.isExecutableFile(atPath: u.path) }
        let bin = runner.appendingPathComponent("bin")
        let arm = runner.appendingPathComponent("lib/wine/aarch64-unix")
        let armLoader = arm.appendingPathComponent("wine.app/Contents/MacOS/wine")
        let armServer = bin.appendingPathComponent("wineserver-arm64")
        let loader: URL, server: URL, unixDir: URL
        if flavor == .fex, executable(armLoader), executable(armServer) {
            (loader, server, unixDir) = (armLoader, armServer, arm)
        } else {
            let unix = runner.appendingPathComponent("lib/wine/x86_64-unix")
            let x86 = bin.appendingPathComponent("wineserver")
            (loader, server, unixDir) = (unix.appendingPathComponent("wine"),
                                         executable(x86) ? x86 : bin.appendingPathComponent("wineserver-x86"), unix)
        }
        guard executable(loader) else {
            return .failure(Failure(message: "The game's runner has no Wine loader at \(loader.path)."))
        }
        return .success(Target(pfx: pfx, appid: appid, build: build, flavor: flavor, runner: runner,
                               loader: loader, server: server, unixDir: unixDir, tool: toolName))
    }

    // MARK: In use

    /// Why nothing may start in this prefix now, or nil when it is free.
    static func busy(_ pfx: URL) -> String? {
        let root = pfx.deletingLastPathComponent()
        // NotProton's lock, held while a launch sets the prefix up.
        let lock = open(root.appendingPathComponent(".notproton-prefix.lock").path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        if lock < 0 {
            if errno != ENOENT { return "NotProton is setting the game's prefix up. Wait for it, or quit the game first." }
        } else {
            defer { close(lock) }
            var info = stat()
            guard fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                return "NotProton is setting the game's prefix up. Wait for it, or quit the game first."
            }
            flock(lock, LOCK_UN)
        }
        // A wineserver for this prefix keeps its socket folder open while anything runs in it.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: pfx.path),
              let device = attributes[.systemNumber] as? Int, let inode = attributes[.systemFileNumber] as? Int
        else { return nil }
        let dir = serverRoot.appendingPathComponent("server-\(String(device, radix: 16))-\(String(inode, radix: 16))")
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-t", "+D", dir.path]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        let inUse = "The game, or another program, is running in this prefix. Quit it first."
        do { try proc.run() } catch { return inUse }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let pids = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return pids.isEmpty ? nil : inUse
    }

    // MARK: Running

    /// NotProton's environment for a program in a prefix.
    static func environment(_ t: Target) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let root = t.runner.path
        env["CX_ROOT"] = root
        env["CX_HOME"] = Paths.home.appendingPathComponent("Library/Application Support/CrossOver").path
        env["WINELOADER"] = t.loader.path
        env["WINESERVER"] = t.server.path
        env["WINEDLLPATH"] = "\(root)/lib/wine/x86_64-windows:" + t.unixDir.path
        env["WINEPREFIX"] = t.pfx.path
        let msync = (try? String(contentsOf: t.pfx.deletingLastPathComponent().appendingPathComponent("notproton-msync"),
                                 encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        env["WINEMSYNC"] = msync == "1" ? "1" : "0"
        env["PATH"] = "\(root)/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    /// Starts program in the prefix and leaves it running. What started, or why it did not.
    static func run(_ program: URL, in pfx: URL) -> Result<String, Failure> {
        guard FileManager.default.fileExists(atPath: program.path) else {
            return .failure(Failure(message: "\(program.lastPathComponent) is no longer at \(program.deletingLastPathComponent().path)."))
        }
        guard let arguments = arguments(for: program) else {
            return .failure(Failure(message: "\(program.lastPathComponent) is not a Windows program. Pick an exe, msi, bat or cmd file."))
        }
        let target: Target
        switch self.target(for: pfx) {
        case .failure(let f): return .failure(f)
        case .success(let t): target = t
        }
        if let why = busy(pfx) { return .failure(Failure(message: why)) }
        let fm = FileManager.default
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("\(target.appid).log")
        fm.createFile(atPath: log.path, contents: Data(
            "\(program.path)\nrunner \(target.build) (\(target.flavor.rawValue))\(target.tool.map { ", tool \($0)" } ?? ", from the prefix's record")\n".utf8))
        let proc = Process()
        proc.executableURL = target.loader
        proc.arguments = arguments
        proc.environment = environment(target)
        proc.currentDirectoryURL = program.deletingLastPathComponent()
        let handle = try? FileHandle(forWritingTo: log)
        handle?.seekToEndOfFile()
        proc.standardOutput = handle ?? FileHandle.nullDevice
        proc.standardError = handle ?? FileHandle.nullDevice
        // The program has its own copy of the log once it runs; this process keeps none.
        defer { try? handle?.close() }
        do { try proc.run() } catch {
            return .failure(Failure(message: "\(program.lastPathComponent) could not be started: \(error.localizedDescription)"))
        }
        return .success("Started \(program.lastPathComponent) in the game's prefix, with CrossOver \(target.build) (\(target.flavor == .fex ? "FEX" : "Rosetta")).")
    }

    // MARK: The program remembered per game

    static var remembered: URL { Paths.support.appendingPathComponent("prefix-programs.json") }

    static func lastProgram(_ key: String) -> URL? {
        guard let data = try? Data(contentsOf: remembered),
              let all = try? JSONDecoder().decode([String: String].self, from: data),
              let path = all[key] else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func remember(_ program: URL, for key: String) {
        var all = (try? Data(contentsOf: remembered)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        all[key] = program.path
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: remembered, options: .atomic) }
    }
}
