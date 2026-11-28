// Each game's compiled shaders, kept whole.
//
// Metal keeps the functions it compiled for a process under the process's bundle
// identifier, in <user cache>/<bundle id>/com.apple.metal/<GPU and macOS>/, in one of
// four files: functions.data, functions1.data, functions2.data and functions3.data,
// each with a .list beside it, and more (functions4.data, ...) when more processes than
// that use the bundle at once: Phantom Blade Zero's folder had five on 2026-11-20, taken by
// Wine's explorer.exe, Steam, the game's launcher, the game and its crash handler. A process takes one of them that no other process
// holds, keeps a lock on it for as long as it runs, reads that one alone and adds to
// it. NotProton starts each game from a bundle of its own
// (com.notproton.launcher.<app id>), and Steam's launcher for the game runs under the
// same bundle, so two processes take a file each and which one the game gets changes
// from one start to the next.
//
// Measured on 2026-11-18 with Ori and the Blind Forest: Definitive Edition (NotProton,
// CrossOver Preview 20261111's Wine under Rosetta, D3DMetal 4, M4 Max), which draws
// with every shader it has before it shows its menu:
//   - first start, nothing kept yet: three minutes with nothing on screen;
//   - second start: the launcher held the file the first start had filled and the game
//     was handed an empty one. 3,650 shaders compiled again, 1 taken from the cache,
//     half a minute with nothing on screen;
//   - the fullest file copied over the other three, third start: 0 compiled, 3,510
//     taken from the cache, frames from the first second.
// In a game that compiles as it goes (Ori and the Will of the Wisps), the same draw of
// the lot is the hitches of the first visit coming back in places already seen.
//
// So while no process holds any of a game's files, the latest full one is copied over
// the others. A copy is an APFS clone: it takes no space of its own until a game
// writes to it. What only another file held is lost and compiled again when the game
// next draws it; from then on every start begins from the same full file, so it is
// lost once.
//
// The latest, not the largest (source(sizes:lists:written:)): a file Metal wrote for one
// tool is no use to another. Ori and the Blind Forest's four files were filled under Rosetta
// on 2026-11-19 (28,925,952 bytes) and the game moved to FEX's tool that night. On
// 2026-11-28 under FEX, Metal made the game's file empty at the start and the game compiled
// it all again (27,656,192 bytes in six minutes, the stutter of a first start); the largest
// file was still Rosetta's, so every pass since the move had copied it back over FEX's and
// every start had compiled again. The game's own file is the last written when it closes.
//
// CrossOver's own folder (com.codeweavers.CrossOver.wineloader) is left alone: every
// game in every bottle shares its four files, each holds a different mix of games, and
// copying one over the others would throw away what the others hold.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

enum ShaderCache {
    static let names = ["functions", "functions1", "functions2", "functions3"]

    /// The files of one folder: the four Metal makes first, and any further numbered one it made
    /// there (functions4, functions5, ...), in order.
    static func names(in dir: URL) -> [String] {
        let more = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).compactMap { file -> Int? in
            guard file.hasPrefix("functions"), file.hasSuffix(".data") else { return nil }
            let digits = file.dropFirst("functions".count).dropLast(".data".count)
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let n = Int(digits), n >= names.count else { return nil }
            return n
        }
        return names + Set(more).sorted().map { "functions\($0)" }
    }

    /// The user's cache folder, where macOS keeps each bundle's Metal cache. MACGAMEFIX_CACHE_DIR
    /// stands in for it in the tests; and under MACGAMEFIX_HOME alone it is a folder of that home,
    /// so that nothing run in a throwaway home ever reaches the real games' caches.
    static var root: URL {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["MACGAMEFIX_CACHE_DIR"] { return URL(fileURLWithPath: dir) }
        if env["MACGAMEFIX_HOME"] != nil { return Paths.home.appendingPathComponent("Library/Caches/metal-stand-in") }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let n = confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count)
        return URL(fileURLWithPath: n > 0 ? String(cString: buffer) : NSTemporaryDirectory())
    }

    /// One game's folder of cache files: the bundle it belongs to and where they are.
    struct Folder {
        let bundle: String
        let dir: URL
    }

    /// The Metal cache folders of the games NotProton runs: a bundle named
    /// com.notproton.launcher.<app id>, and under it one folder for each GPU and macOS it ran on.
    static func folders() -> [Folder] {
        let fm = FileManager.default
        var out: [Folder] = []
        for bundle in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        where bundle.hasPrefix("com.notproton.launcher.") {
            let metal = root.appendingPathComponent(bundle).appendingPathComponent("com.apple.metal")
            for sub in ((try? fm.contentsOfDirectory(atPath: metal.path)) ?? []).sorted() {
                let dir = metal.appendingPathComponent(sub)
                if names.contains(where: { fm.fileExists(atPath: dir.appendingPathComponent($0 + ".data").path) }) {
                    out.append(Folder(bundle: bundle, dir: dir))
                }
            }
        }
        return out
    }

    private static func size(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? -1
    }

    private static func written(_ url: URL) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
    }

    /// The file the others are made the same as: of those holding at least a quarter of the largest,
    /// the one written last, and of two written at once the larger. A game's own file is the last one
    /// written when it closes; the quarter keeps out a file Metal has just made empty and a helper
    /// process's few shaders. nil when no file holds anything.
    static func source(sizes: [Int], lists: [Int], written: [Date]) -> Int? {
        guard let most = sizes.max(), most > 0 else { return nil }
        return sizes.indices
            .filter { sizes[$0] > 0 && lists[$0] >= 0 && sizes[$0] * 4 >= most }
            .max { (written[$0], sizes[$0]) < (written[$1], sizes[$1]) }
    }

    enum Outcome: Equatable {
        /// The four are the same already.
        case whole
        /// A process holds one of them: the game, or its launcher, is running.
        case inUse
        /// The latest was copied over this many of the others.
        case copied(Int)
        case failed(String)
    }

    /// Makes one folder's files the same as its latest full one (source), unless they are already or one is held.
    static func keep(_ folder: Folder) -> Outcome {
        let fm = FileManager.default
        let files = Self.names(in: folder.dir)
        let data = files.map { folder.dir.appendingPathComponent($0 + ".data") }
        let list = files.map { folder.dir.appendingPathComponent($0 + ".list") }
        let sizes = data.map(size), lists = list.map(size)
        guard let best = source(sizes: sizes, lists: lists, written: data.map(written)) else { return .whole }
        let most = sizes[best]
        // The same sizes all round, data and list: nothing was added to any of them since they were made the same.
        if sizes.allSatisfy({ $0 == most }) && lists.allSatisfy({ $0 == lists[best] }) { return .whole }

        // Metal keeps a lock on the file a process took. All of them free means nobody is using the folder,
        // and they stay locked here until the copies are in place.
        var held: [Int32] = []
        defer { for fd in held { flock(fd, LOCK_UN); close(fd) } }
        for url in data where fm.fileExists(atPath: url.path) {
            let fd = open(url.path, O_RDONLY)
            guard fd >= 0 else { return .failed("cannot open \(url.lastPathComponent)") }
            held.append(fd)
            if flock(fd, LOCK_EX | LOCK_NB) != 0 { return .inUse }
        }

        var copied = 0
        for i in files.indices where i != best {
            if sizes[i] == most && lists[i] == lists[best] { continue }
            for (from, to) in [(data[best], data[i]), (list[best], list[i])] {
                let tmp = to.appendingPathExtension("mgf-new")
                try? fm.removeItem(at: tmp)
                // A clone: no space of its own until one of the two is written to.
                if clonefile(from.path, tmp.path, 0) != 0 {
                    do { try fm.copyItem(at: from, to: tmp) } catch { return .failed("cannot copy \(from.lastPathComponent)") }
                }
                guard rename(tmp.path, to.path) == 0 else {
                    try? fm.removeItem(at: tmp)
                    return .failed("cannot put \(to.lastPathComponent) in place")
                }
            }
            copied += 1
        }
        return .copied(copied)
    }

    /// Every game's folder, looked at once. What was done, a line for each folder that changed or failed.
    @discardableResult
    static func keepAll() -> [String] {
        var lines: [String] = []
        for folder in folders() {
            switch keep(folder) {
            case .copied(let n) where n > 0:
                lines.append("\(folder.bundle): the latest shader cache copied over \(n) other\(n == 1 ? "" : "s")")
            case .failed(let why):
                lines.append("\(folder.bundle): \(why)")
            default: break
            }
        }
        return lines
    }

    /// For Improvements: how many games have a cache, and how many of those have all their files the same.
    static func coverage() -> String {
        let all = folders()
        guard !all.isEmpty else { return "No game NotProton runs has compiled shaders yet." }
        let games = Set(all.map(\.bundle)).count
        let whole = all.filter { folder in
            let files = Self.names(in: folder.dir)
            let sizes = files.map { size(folder.dir.appendingPathComponent($0 + ".data")) }
            let lists = files.map { size(folder.dir.appendingPathComponent($0 + ".list")) }
            return Set(sizes).count == 1 && Set(lists).count == 1 && sizes[0] > 0
        }
        let done = Set(whole.map(\.bundle)).count
        return "\(games) game\(games == 1 ? "" : "s") with compiled shaders, \(done) kept whole. A game is done once it is closed."
    }
}
