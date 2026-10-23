// The Report tab's probe: what a game is made of, read from its folder alone, and
// the report a user attaches to an issue about a game that does not work; and a
// fix's report, which Games saves for a fix that works or a game that works
// without it. Nothing here writes into a game, its prefix or its bottle.
import Foundation
import CryptoKit

// MARK: - The games on this Mac

/// A Steam game's folder, by its appmanifest.
struct ProbeGame: Identifiable, Hashable, Sendable {
    let appid: String
    let name: String
    let folder: URL
    /// The prefixes and bottles it can run in, in words.
    var places: [String] = []
    /// The same app can sit in two libraries, a Steam Play one and a bottle's.
    var id: String { appid + "|" + folder.path }
}

enum ProbeGames {
    /// Every app in the Steam libraries whose folder is on disk, by name.
    static func all(extra: [URL] = []) -> [ProbeGame] {
        let fm = FileManager.default
        var found: [ProbeGame] = []
        var seen = Set<String>()
        for common in Libraries.all(extra: extra) {
            let steamapps = common.deletingLastPathComponent()
            for file in (try? fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
            where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let fields = SteamGames.manifest(text)
                guard let appid = fields["appid"], let name = fields["name"], let dir = fields["installdir"], !dir.isEmpty,
                      !SteamGames.notGames.contains(appid) else { continue }
                let folder = common.appendingPathComponent(dir)
                guard fm.fileExists(atPath: folder.path), seen.insert(appid + "|" + folder.path).inserted else { continue }
                var places: [String] = []
                for label in Libraries.prefixes(for: folder).map(\.label) where !places.contains(label) { places.append(label) }
                found.append(ProbeGame(appid: appid, name: name, folder: folder, places: places))
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - A Windows executable's imports

/// The DLLs a PE file imports, eagerly or on first use (delay-load), lower case.
struct PEImports: Sendable {
    let machine: String
    let dlls: [String]
}

enum PE {
    static func imports(of url: URL) -> PEImports? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard (try? h.seek(toOffset: offset)) != nil, let d = try? h.read(upToCount: count), !d.isEmpty else { return nil }
            return d
        }
        guard let dos = read(0, 64), dos.count == 64, dos.le16(0) == 0x5a4d else { return nil }
        let pe = UInt64(dos.le32(0x3c))
        guard let coff = read(pe, 24), coff.count == 24, coff.le32(0) == 0x4550 else { return nil }
        let machine = coff.le16(4), count = Int(coff.le16(6)), optSize = Int(coff.le16(20))
        guard optSize >= 96, count > 0, count < 256, let opt = read(pe + 24, optSize), opt.count == optSize else { return nil }
        let plus = opt.le16(0) == 0x20b
        let imageBase = plus ? opt.le64(24) : UInt64(opt.le32(28))
        let dirs = plus ? 112 : 96, dirCount = Int(opt.le32(plus ? 108 : 92))
        func directory(_ i: Int) -> UInt32? {
            guard i < dirCount, dirs + 8 * i + 8 <= optSize else { return nil }
            let rva = opt.le32(dirs + 8 * i)
            return rva == 0 ? nil : rva
        }
        guard let table = read(pe + 24 + UInt64(optSize), 40 * count), table.count == 40 * count else { return nil }
        let sections = (0..<count).map { i in
            (va: table.le32(40 * i + 12), size: max(table.le32(40 * i + 8), table.le32(40 * i + 16)), raw: table.le32(40 * i + 20))
        }
        func offset(_ rva: UInt32) -> UInt64? {
            for s in sections where rva >= s.va && UInt64(rva) < UInt64(s.va) + UInt64(s.size) {
                return UInt64(rva - s.va) + UInt64(s.raw)
            }
            return nil
        }
        func name(_ rva: UInt32) -> String? {
            guard let o = offset(rva), let d = read(o, 256) else { return nil }
            let bytes = d.prefix { $0 != 0 }
            guard !bytes.isEmpty, bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return nil }
            return String(decoding: bytes, as: UTF8.self).lowercased()
        }
        var dlls: [String] = []
        // Imports: 20-byte descriptors, the name's RVA at 12, ended by an empty one.
        if let rva = directory(1), let start = offset(rva) {
            for i in 0..<1024 {
                guard let d = read(start + UInt64(20 * i), 20), d.count == 20 else { break }
                if d.le32(0) == 0 && d.le32(12) == 0 && d.le32(16) == 0 { break }
                if let n = name(d.le32(12)) { dlls.append(n) }
            }
        }
        // Delay-loaded: 32-byte descriptors, the name at 4, an RVA when bit 0 of the
        // attributes is set and an address in the image in the oldest form.
        if let rva = directory(13), let start = offset(rva) {
            for i in 0..<1024 {
                guard let d = read(start + UInt64(32 * i), 32), d.count == 32 else { break }
                let attributes = d.le32(0), field = d.le32(4)
                if field == 0 { break }
                let nameRVA = attributes & 1 == 1 ? field : UInt32(truncatingIfNeeded: UInt64(field) &- imageBase)
                if let n = name(nameRVA) { dlls.append(n) }
            }
        }
        let kind: String
        switch machine {
        case 0x8664: kind = "x64"
        case 0x14c: kind = "x86, 32-bit"
        case 0xaa64: kind = "ARM64"
        default: kind = String(format: "machine 0x%04x", machine)
        }
        var unique: [String] = []
        for d in dlls where !unique.contains(d) { unique.append(d) }
        return PEImports(machine: kind, dlls: unique)
    }
}

private extension Data {
    func le16(_ at: Int) -> UInt16 {
        guard at + 2 <= count else { return 0 }
        return UInt16(self[startIndex + at]) | UInt16(self[startIndex + at + 1]) << 8
    }
    func le32(_ at: Int) -> UInt32 {
        guard at + 4 <= count else { return 0 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + at + $1]) << (8 * UInt32($1)) }
    }
    func le64(_ at: Int) -> UInt64 { UInt64(le32(at)) | UInt64(le32(at + 4)) << 32 }
}

// MARK: - What a game is made of

extension ProbeFindings {
    /// The library the game reaches the pad through, by the names the list of games played
    /// for vibration uses, guessed from its folder. Sony's whenever the game ships it, even
    /// one that also reads HID, reads through DirectInput and rumbles through Sony's library
    /// (Mortal Kombat 11), or rumbles only through XInput (Crysis 2 Remastered, which the list
    /// keeps as XInput). DirectInput only for a game with no other way to the pad.
    var padLibrary: String? {
        if input.contains(where: { $0.hasPrefix("Sony's pad library") }) { return "Sony libScePad" }
        if input.contains("SDL") { return "SDL" }
        if input.contains(where: { $0.hasPrefix("raw HID") }) { return "Raw HID" }
        if input.contains("XInput") { return "XInput" }
        if input == ["DirectInput 8"] { return "DirectInput" }
        return nil
    }
}

struct ProbeFindings: Sendable {
    var exe: String?
    var exeSize: Int64 = 0
    var machine: String?
    var otherExes: [String] = []
    var imports: [String] = []
    var graphics: [String] = []
    var engine: String?
    var input: [String] = []
    var video: [String] = []
    var videoFiles: [String] = []
    var middleware: [String] = []
    var antiCheat: [String] = []
    /// What the look left out, said rather than hidden.
    var limits: [String] = []

    /// The lines the sheet shows and the report starts with.
    var summary: [(String, String)] {
        func list(_ a: [String]) -> String { a.isEmpty ? "none found" : a.joined(separator: ", ") }
        return [("Main executable", exe.map { "\($0) (\(machine ?? "?"))" } ?? "none found"),
                ("Graphics", list(graphics)),
                ("Engine", engine ?? "not recognised"),
                ("Controller", list(input)),
                ("Video", list(video + videoFiles)),
                ("Middleware", list(middleware)),
                ("Anti-cheat", list(antiCheat))]
    }
}

enum Probe {
    private static let notMain = ["crash", "redist", "vcredist", "vc_redist", "dxsetup", "unins", "setup", "dotnet",
                                  "easyanticheat", "battleye", "beservice", "cefprocess", "unrealcefsubprocess",
                                  "uploader", "reporter", "prereq", "directx", "physx"]

    /// Looks through a game's folder: its executables, the DLLs beside them and its videos.
    static func look(_ game: ProbeGame, fileLimit: Int = 300_000) -> ProbeFindings {
        let fm = FileManager.default
        var f = ProbeFindings()
        var exes: [(rel: String, size: Int64)] = []
        var dlls = Set<String>()
        var dirs = Set<String>()
        var videos: [String: [String]] = [:]
        var sniffed: [String: [String]] = [:]   // by extension: the labels of the files opened
        var files = 0
        let root = game.folder.standardizedFileURL.path
        if let walk = fm.enumerator(at: game.folder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in walk {
                files += 1
                if files > fileLimit {
                    f.limits.append("stopped after \(fileLimit) files")
                    break
                }
                let rel = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
                let lower = url.lastPathComponent.lowercased()
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    dirs.insert(lower)
                    continue
                }
                switch url.pathExtension.lowercased() {
                case "exe" where walk.level <= 5:
                    exes.append((rel, Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)))
                case "dll":
                    dlls.insert(lower)
                case "bk2", "bik", "usm", "webm", "mkv", "mp4", "m4v", "mov", "wmv", "asf", "avi", "ogv", "mpg", "mpeg", "m2v":
                    // The codec is in the first bytes of a few of each kind; the rest are counted alike.
                    let ext = url.pathExtension.lowercased()
                    let kind: String
                    if let seen = sniffed[ext], seen.count >= 6 {
                        kind = seen[seen.count - 1]
                    } else {
                        kind = videoKind(url)
                        sniffed[ext, default: []].append(kind)
                    }
                    videos[kind, default: []].append(rel)
                default: break
                }
            }
        }

        // The main executable: an Unreal shipping build if there is one, else the largest
        // that is not a crash reporter, an installer or an anti-cheat service.
        let candidates = exes.filter { e in !notMain.contains { e.rel.lowercased().contains($0) } }
        let main = candidates.first { $0.rel.lowercased().hasSuffix("-shipping.exe") }
            ?? candidates.max { $0.size < $1.size } ?? exes.max { $0.size < $1.size }
        if let main {
            f.exe = main.rel
            f.exeSize = main.size
            if let pe = PE.imports(of: game.folder.appendingPathComponent(main.rel)) {
                f.machine = pe.machine
                f.imports = pe.dlls
            }
        }
        f.otherExes = exes.filter { $0.rel != main?.rel }.sorted { $0.size > $1.size }.prefix(6).map(\.rel)
        let imports = Set(f.imports)

        // Graphics: what the executable imports, and what the game ships beside it.
        for (dll, label) in [("d3d9.dll", "Direct3D 9"), ("d3d11.dll", "Direct3D 11"), ("d3d12.dll", "Direct3D 12"),
                             ("vulkan-1.dll", "Vulkan"), ("opengl32.dll", "OpenGL")] where imports.contains(dll) {
            f.graphics.append(label)
        }
        if dlls.contains("d3d12core.dll") { f.graphics.append("ships the Direct3D 12 Agility SDK") }
        if dlls.contains("dstorage.dll") || dlls.contains("dstoragecore.dll") { f.graphics.append("DirectStorage") }

        // The engine.
        if main?.rel.lowercased().hasSuffix("-shipping.exe") == true || dirs.contains("engine") && dirs.contains("binaries") {
            f.engine = unrealVersion(main.map { game.folder.appendingPathComponent($0.rel) }) ?? "Unreal Engine"
        } else if dlls.contains("unityplayer.dll") {
            f.engine = (unityVersion(game.folder).map { "Unity \($0)" } ?? "Unity")
                + (dlls.contains("gameassembly.dll") ? " (IL2CPP)" : " (Mono)")
        }

        // The controller.
        if imports.contains(where: { $0.hasPrefix("xinput") }) { f.input.append("XInput") }
        if imports.contains("dinput8.dll") { f.input.append("DirectInput 8") }
        if imports.contains("hid.dll") { f.input.append("raw HID (reads controllers directly)") }
        if dlls.contains(where: { $0.hasPrefix("libscepad") }) { f.input.append("Sony's pad library (libScePad)") }
        if dlls.contains("gameinput.dll") { f.input.append("GameInput") }
        if dlls.contains("sdl2.dll") || dlls.contains("sdl3.dll") { f.input.append("SDL") }

        // Video: the APIs, and the files by container and codec.
        if imports.contains(where: { ["mfplat.dll", "mfreadwrite.dll", "mf.dll"].contains($0) }) { f.video.append("Media Foundation") }
        if imports.contains("wmvcore.dll") { f.video.append("Windows Media reader") }
        if imports.contains("quartz.dll") { f.video.append("DirectShow") }
        if dlls.contains(where: { $0.hasPrefix("bink") }) { f.video.append("Bink") }
        if dlls.contains(where: { $0.hasPrefix("avcodec") || $0.hasPrefix("avformat") }) { f.video.append("FFmpeg") }
        if dlls.contains(where: { $0.hasPrefix("cri") }) { f.video.append("CRI") }
        f.videoFiles = videos.sorted { $0.value.count > $1.value.count }.map { kind, paths in
            "\(paths.count) \(kind) (\(paths.min { $0.count < $1.count } ?? ""))"
        }

        // Middleware, by the DLLs the game ships.
        let known: [(String, String)] = [("sl.interposer.dll", "NVIDIA Streamline"), ("nvngx_dlss.dll", "DLSS"),
                                         ("nvngx_dlssg.dll", "DLSS frame generation"), ("libxess", "XeSS"),
                                         ("amd_fidelityfx", "FidelityFX (FSR)"), ("ffx_", "FidelityFX (FSR)"),
                                         ("amd_ags", "AMD AGS"), ("gfsdk_", "NVIDIA GameWorks"), ("physx", "PhysX"),
                                         ("fmod", "FMOD"), ("aksoundengine", "Wwise"), ("eossdk", "Epic Online Services"),
                                         ("gfesdk.dll", "GeForce Experience SDK")]
        for (prefix, label) in known where dlls.contains(where: { $0.hasPrefix(prefix) }) && !f.middleware.contains(label) {
            f.middleware.append(label)
        }
        if dirs.contains("easyanticheat") || dlls.contains(where: { $0.hasPrefix("easyanticheat") }) {
            f.antiCheat.append("Easy Anti-Cheat")
        }
        if dirs.contains("battleye") || dlls.contains(where: { $0.hasPrefix("beclient") }) { f.antiCheat.append("BattlEye") }
        return f
    }

    /// A video file's container and, where its first bytes say, its codec.
    static func videoKind(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let opened = ["webm", "mkv", "mp4", "m4v", "mov", "wmv", "asf"].contains(ext)
        let head = !opened ? Data() : (try? FileHandle(forReadingFrom: url)).flatMap { h -> Data? in
            defer { try? h.close() }
            return try? h.read(upToCount: 256 * 1024)
        } ?? Data()
        func has(_ s: String) -> Bool { head.range(of: Data(s.utf8)) != nil }
        switch ext {
        case "bk2": return "Bink 2"
        case "bik": return "Bink"
        case "usm": return "CRI USM"
        case "ogv": return "Ogg Theora"
        case "avi": return "AVI"
        case "mpg", "mpeg", "m2v": return "MPEG"
        case "webm", "mkv":
            let codec = has("V_VP9") ? "VP9" : has("V_VP8") ? "VP8" : has("V_AV1") ? "AV1" : has("V_MPEG4/ISO/AVC") ? "H.264" : nil
            return (ext == "webm" ? "WebM" : "Matroska") + (codec.map { ", " + $0 } ?? "")
        case "mp4", "m4v", "mov":
            let codec = has("avc1") ? "H.264" : has("hvc1") || has("hev1") ? "HEVC" : has("av01") ? "AV1" : has("vp09") ? "VP9" : nil
            return "MP4" + (codec.map { ", " + $0 } ?? "")
        default:
            let codec = has("WMV3") ? "WMV3" : has("WVC1") ? "VC-1" : has("WMV2") ? "WMV2" : has("WMV1") ? "WMV1" : nil
            return "ASF" + (codec.map { ", " + $0 } ?? "")
        }
    }

    /// "Unreal Engine 5.3", from the branch name Unreal builds into its executables.
    static func unrealVersion(_ exe: URL?) -> String? {
        guard let exe, let h = try? FileHandle(forReadingFrom: exe) else { return nil }
        defer { try? h.close() }
        let wide = Data("++UE".utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
        let narrow = Data("++UE".utf8)
        var carry = Data()
        while let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty {
            let data = carry + chunk
            for (needle, step) in [(wide, 2), (narrow, 1)] {
                guard let r = data.range(of: needle) else { continue }
                // ++UE5+Release-5.3: the bytes after the marker, one in each step.
                let tail = data[r.upperBound...].enumerated().filter { $0.offset % step == 0 }.prefix(24).map(\.element)
                let text = String(decoding: tail.prefix { $0 >= 0x20 && $0 < 0x7f }, as: UTF8.self)
                if let v = text.range(of: #"Release-\d+\.\d+"#, options: .regularExpression) {
                    return "Unreal Engine " + text[v].dropFirst("Release-".count)
                }
            }
            carry = Data(data.suffix(64))
        }
        return nil
    }

    /// "2021.3.16f1", from the start of the game's globalgamemanagers.
    static func unityVersion(_ folder: URL) -> String? {
        let fm = FileManager.default
        for data in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where data.lastPathComponent.hasSuffix("_Data") {
            for name in ["globalgamemanagers", "data.unity3d", "mainData"] {
                guard let h = try? FileHandle(forReadingFrom: data.appendingPathComponent(name)) else { continue }
                defer { try? h.close() }
                let head = String(decoding: ((try? h.read(upToCount: 128)) ?? Data()).map { $0 >= 0x20 && $0 < 0x7f ? $0 : 0x20 },
                                  as: UTF8.self)
                if let r = head.range(of: #"\d{4}\.\d+\.\d+[abfp]\d+"#, options: .regularExpression) { return String(head[r]) }
            }
        }
        return nil
    }

    // MARK: The game's own log

    /// The newest log the game wrote itself, in a prefix it runs in: Unreal's
    /// Saved/Logs, Unity's Player.log. Its last lines.
    static func ownLog(_ game: ProbeGame, findings: ProbeFindings, lines: Int = 300) -> (name: String, text: String)? {
        let fm = FileManager.default
        var places: [URL] = []
        let users = Libraries.prefixes(for: game.folder).flatMap { prefix -> [URL] in
            let base = prefix.path.appendingPathComponent("drive_c/users")
            return ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
        }
        if let exe = findings.exe, exe.lowercased().hasSuffix("-shipping.exe") {
            // An Unreal project's name is the shipping executable's, before -Win64-Shipping.
            let project = URL(fileURLWithPath: exe).lastPathComponent
                .replacingOccurrences(of: #"-(Win64|WinGDK)-Shipping\.exe$"#, with: "", options: [.regularExpression, .caseInsensitive])
            for user in users { places.append(user.appendingPathComponent("AppData/Local/\(project)/Saved/Logs")) }
            places.append(game.folder.appendingPathComponent("\(project)/Saved/Logs"))
        }
        // Unity writes to LocalLow/<company>/<product>, which app.info names.
        for data in (try? fm.contentsOfDirectory(at: game.folder, includingPropertiesForKeys: nil)) ?? []
        where data.lastPathComponent.hasSuffix("_Data") {
            let info = ((try? String(contentsOf: data.appendingPathComponent("app.info"), encoding: .utf8)) ?? "")
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard info.count >= 2, !info[0].isEmpty, !info[1].isEmpty else { continue }
            for user in users { places.append(user.appendingPathComponent("AppData/LocalLow/\(info[0])/\(info[1])")) }
        }
        let logs = places.flatMap { dir in
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension.lowercased() == "log" }
        }
        guard let newest = logs.max(by: {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }), let data = try? Data(contentsOf: newest) else { return nil }
        let text = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(lines).joined(separator: "\n")
        return (newest.lastPathComponent, text)
    }

    // MARK: The report

    /// The report for an issue about this game: what it is made of, where it can
    /// run, what MacGameFix has for it, and the logs about it. Only this game; the
    /// home folder is written ~ and the Mac's name is left out. A fix's report
    /// (FixReport) is this one with no symptom, its own title, the prefixes its
    /// fix was given named, and its section on the fix after the first lines.
    static func report(_ game: ProbeGame, symptom: String?, findings f: ProbeFindings, fix: String?,
                       engines: [(name: String, build: String, state: String)], padLines: [String],
                       title: String = "game report", given: [Prefix] = [], section: String = "",
                       now: Date = Date()) -> String {
        func shell(_ args: [String]) -> String {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: args[0])
            p.arguments = Array(args.dropFirst())
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return "" }
            p.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out = "# MacGameFix \(title): \(game.name)\n\n"
        out += "- Made: \(ISO8601DateFormatter().string(from: now))\n"
        out += "- MacGameFix \(Catalog.appVersion); macOS \(ProcessInfo.processInfo.operatingSystemVersionString); "
            + "\(shell(["/usr/sbin/sysctl", "-n", "hw.model"]))\n"
        // A folder the user added holds no appmanifest, and so no app id.
        out += "- Game: \(game.name)" + (game.appid.isEmpty ? "" : ", Steam app \(game.appid)") + "\n"
        if let symptom { out += "- What goes wrong: \(symptom)\n" }
        out += "- Folder: \(game.folder.path)\n"
        let found = places(for: game.folder, given: given)
        var prefixes: [String] = []
        for p in found.named {
            let words = (p.kind == .bottle ? "the CrossOver bottle \"\(p.path.lastPathComponent)\"" : "a Steam Play prefix")
                + " (\(p.path.path))"
            if !prefixes.contains(words) { prefixes.append(words) }
        }
        if let others = others(found.others.count) { prefixes.append(others) }
        out += "- Runs in: " + (prefixes.isEmpty ? "no prefix or bottle found beside its library" : prefixes.joined(separator: "; ")) + "\n"
        out += "- MacGameFix: " + (fix.map { "has a fix for it (\($0))" } ?? "has no fix for it") + "\n"
        out += section

        out += "\n## What the game is made of\n\n"
        for (label, value) in f.summary { out += "- \(label): \(value)\n" }
        if f.exeSize > 0 {
            out += "- Main executable's size: " + String(format: "%.1f MB", locale: Locale(identifier: "en_US_POSIX"),
                                                         Double(f.exeSize) / 1e6) + "\n"
        }
        if !f.otherExes.isEmpty { out += "- Other executables: " + f.otherExes.joined(separator: ", ") + "\n" }
        if !f.limits.isEmpty { out += "- The look " + f.limits.joined(separator: "; ") + "\n" }
        // The API sets (api-ms-win-*, ext-ms-*) say nothing of the game; they are counted, not listed.
        let sets = f.imports.filter { $0.hasPrefix("api-ms-") || $0.hasPrefix("ext-ms-") }
        let listed = f.imports.filter { !sets.contains($0) }
        out += "\nThe main executable imports" + (sets.isEmpty ? "" : " (and \(sets.count) Windows API sets)") + ":\n\n```\n"
            + (listed.isEmpty ? "(nothing read)" : listed.joined(separator: "\n")) + "\n```\n"

        out += "\n## Wine modules\n\n"
        out += engines.isEmpty ? "None found.\n" : engines.map { "- \($0.name) (\($0.build)): \($0.state)" }.joined(separator: "\n") + "\n"
        if !padLines.isEmpty {
            out += "\n## The modules' log for this game\n\n```\n" + padLines.suffix(400).joined(separator: "\n") + "\n```\n"
        }
        if let log = ownLog(game, findings: f) {
            out += "\n## The game's own log: \(log.name), its last lines\n\n```\n" + log.text + "\n```\n"
        } else {
            out += "\n## The game's own log\n\nNone found.\n"
        }
        return redact(out)
    }

    /// The prefixes and bottles a report names for a game: its own Steam Play
    /// prefix, a bottle that holds its folder, and those its fix was given in
    /// Games. Any other bottle whose Steam lists the game's library is counted,
    /// not named: a bottle is often named after another game, and a report names
    /// its own game alone.
    static func places(for folder: URL, given: [Prefix] = []) -> (named: [Prefix], others: [Prefix]) {
        let game = folder.resolvingSymlinksInPath().standardizedFileURL.path
        var named: [Prefix] = [], others: [Prefix] = []
        for p in Libraries.prefixes(for: folder) + given where !named.contains(p) && !others.contains(p) {
            let root = p.path.resolvingSymlinksInPath().standardizedFileURL.path
            if p.kind == .steamPlay || given.contains(p) || game.hasPrefix(root + "/") { named.append(p) } else { others.append(p) }
        }
        return (named, others)
    }

    /// The bottles places(for:) counts and does not name, in words; nil for none.
    static func others(_ count: Int) -> String? {
        count == 0 ? nil : count == 1 ? "another CrossOver bottle whose Steam lists its library, not named here"
            : "\(count) other CrossOver bottles whose Steam lists its library, not named here"
    }

    /// The home folder as ~, and neither the account's name nor the Mac's.
    static func redact(_ text: String) -> String {
        var out = text
        // The home as realpath gives it first: a folder found under a home in /var is named
        // from /private/var, and was written "/private~" (seen in the tests, 2026-10-23).
        var homes = [Paths.home.path, NSHomeDirectory()]
        if let real = realpath(Paths.home.path, nil) { homes.insert(String(cString: real), at: 0); free(real) }
        for home in homes where home.count > 1 {
            out = out.replacingOccurrences(of: home, with: "~")
        }
        var host = [CChar](repeating: 0, count: 256)
        gethostname(&host, host.count)
        let hostName = String(cString: host).replacingOccurrences(of: ".local", with: "")
        // Wine names the computer from the host, in capitals and cut to fifteen characters.
        // A name shorter than six ("iMac") would take words with it, and is left.
        for name in [hostName, String(hostName.prefix(15))] where name.count >= 6 {
            out = out.replacingOccurrences(of: name, with: "<this Mac>", options: .caseInsensitive)
        }
        let user = NSUserName()
        if user.count >= 3 {
            out = out.replacingOccurrences(of: "/Users/\(user)", with: "~")
            out = out.replacingOccurrences(of: "\\Users\\\(user)", with: "\\Users\\<user>", options: .caseInsensitive)
        }
        return out
    }
}

/// What goes wrong, which decides what the user is asked to do before the report.
enum ProbeSymptom: String, CaseIterable, Identifiable, Sendable {
    case start = "It does not start, or closes at once"
    case crash = "It crashes while playing"
    case video = "Videos or cutscenes are black, frozen or missing"
    case graphics = "Something looks wrong on screen"
    case slow = "It runs slowly"
    case controller = "The controller, its haptics or its triggers"
    case sound = "Sound"
    case other = "Something else"

    var id: String { rawValue }

    /// What to do before making the report, in order.
    var steps: [String] {
        switch self {
        case .start, .crash:
            return ["Start the game once more from where you play it, and let it fail.",
                    "If a window says the program had a problem, open its details and copy what it shows into the issue.",
                    "Close everything the game left open, then come back here. The report picks up the game's own log when it writes one."]
        case .video:
            return ["Play to the video that fails, and note where it is: the chapter or mission, and how long into the game.",
                    "Close the game, then come back here."]
        case .graphics:
            return ["Take a screenshot of the moment: ⇧⌘4, then Space, then click the game's window.",
                    "Note the game's graphics settings, and the upscaler if it has one (DLSS, FSR, XeSS).",
                    "Close the game, then come back here."]
        case .slow:
            return ["Note the game's graphics settings, its resolution and the upscaler if it has one (DLSS, FSR, XeSS).",
                    "If you know how to turn on the Metal HUD, take a screenshot with it: ⇧⌘4, then Space, then click the game's window.",
                    "Close the game, then come back here."]
        case .controller:
            return ["Turn on Diagnose this game below.",
                    "Play the moment that goes wrong, then close the game.",
                    "Come back here. The report adds what the Wine modules saw of this game."]
        case .sound:
            return ["Note what is missing: all sound, voices, music or effects, and where in the game.",
                    "Close the game, then come back here."]
        case .other:
            return ["Play to the moment, note where it is, close the game and come back here."]
        }
    }
}

// MARK: - A fix's report

/// What It Works… and Works Without the Fix… in Games save and fill in: the Report
/// tab's report for the game, with a section on its fix after its first lines, and
/// the form for a fix that works (fix-works.yml) or for a game that works without
/// its fix (works-without-fix.yml). A field of the form is filled in only from what
/// is read here; one that is not read is left to the player.
enum FixReport {
    enum Kind: String, Sendable {
        case works, without

        /// The state the row must be in: its fix installed, or not installed.
        var state: FixState { self == .works ? .installed : .absent }
        var button: String { self == .works ? "It Works…" : "Works Without the Fix…" }
        /// What the save panel's name starts with.
        var file: String { self == .works ? "MacGameFix fix report" : "MacGameFix report without the fix" }
        var template: String { self == .works ? "fix-works.yml" : "works-without-fix.yml" }
        var title: String { self == .works ? "[Works] " : "[No longer needed] " }
    }

    /// How much of the end of each of the fix's own logs a report carries.
    static let logLines = 200
    /// How much of a log's end is read: two hundred lines of the longest a report
    /// keeps, and never the whole of a log a fix let grow.
    static let logTail = 256 * 1024
    /// The longest line of a log a report keeps; a longer one is cut, and says so.
    static let lineLength = 1000

    /// A log the fix writes beside its DLL, as found in the game folder.
    struct OwnLog: Sendable {
        let name: String
        /// Where it was found, from the game folder.
        let path: String
        var modified: Date?
        /// Its last lines, logLines at most, of `total`; nil when only its end was read.
        var lines: [String] = []
        var total: Int?
        var size = 0
        /// Why it could not be read, when it is there and could not be.
        var error: String?
    }

    /// A CrossOver app or a NotProton runner, as Engine finds it, with the D3DMetal
    /// builds it carries.
    struct Runner: Sendable {
        let name: String
        let build: String
        let d3dmetal: [(folder: String, version: String)]
    }

    /// What the report and the form say, read for one row of Games.
    struct Facts: Sendable {
        var kind: Kind
        var game: Game
        var folder: URL
        var appid = ""
        /// The installer's --status: once, or once for each prefix the fix was given.
        var status: [(place: String?, lines: [String], state: FixState)] = []
        var state = FixState.unknown
        /// The game's build, as an installer made for each build of the game names it.
        var build: String?
        var steamBuild: String?
        var matches: [(file: String, catalog: String)] = []
        var catalogVersion = 0
        /// The prefixes and bottles the fix was given, or else those the game can run in
        /// that a report names (Probe.places).
        var places: [Prefix] = []
        /// The bottles whose Steam lists the game's library, counted and not named.
        var otherBottles = 0
        /// The CrossOver apps or NotProton runners of the kind those places are.
        var runners: [Runner] = []
        var ownLogs: [OwnLog] = []
        /// This window's Settings › Log lines for the game.
        var session: [String] = []
        var model = ""
        var chip = ""
    }

    /// The report and the form's address, for a row of Games, and the state its
    /// installer gives now, which the row may no longer show.
    static func make(_ hit: Hit, kind: Kind, catalog: URL, session: [String],
                     engines: [(name: String, build: String, state: String)],
                     now: Date = Date()) async -> (text: String, issue: URL?, state: FixState) {
        let f = await facts(hit, kind: kind, catalog: catalog, session: session)
        let game = ProbeGame(appid: f.appid, name: hit.game.name, folder: hit.folder, places: f.places.map(\.label))
        // The Wine modules' lines for the game, as the Report tab takes them: by its app id.
        let log = f.appid.isEmpty ? "" : (try? String(contentsOf: PadStore.log, encoding: .utf8)) ?? ""
        let padLines = log.split(separator: "\n").map(String.init).filter { $0.contains(" game=\(f.appid) ") }
        let text = Probe.report(game, symptom: nil, findings: Probe.look(game), fix: hit.game.name, engines: engines,
                                padLines: padLines, title: "fix report", given: given(hit), section: section(f), now: now)
        return (text, issue(f), f.state)
    }

    /// The prefixes the fix was given in Games: a fix that needs one goes into those chosen.
    static func given(_ hit: Hit) -> [Prefix] { hit.game.needsPrefix ? hit.chosen : [] }

    /// The row, read: its installer asked as the window asks it, the files that match
    /// the catalog, where the game runs, the fix's own logs and this Mac.
    static func facts(_ hit: Hit, kind: Kind, catalog: URL, session: [String]) async -> Facts {
        var f = Facts(kind: kind, game: hit.game, folder: hit.folder)
        let steam = SteamApp.of(folder: hit.folder)
        f.appid = steam?.appid ?? ""
        f.steamBuild = steam.flatMap { $0.buildid.isEmpty ? nil : $0.buildid }
        let prefixes: [Prefix?] = hit.game.needsPrefix ? hit.chosen : [nil]
        for prefix in prefixes {
            let run = await Fixer.statusRun(hit.game, folder: hit.folder, prefix: prefix?.path.path, catalog: catalog)
            f.status.append((prefix?.label, run.lines, run.look.state))
            f.build = f.build ?? run.look.build
        }
        f.state = Fixer.combined(f.status.map(\.state))
        let manifest = Catalog.manifest(in: catalog)
        f.catalogVersion = manifest?.version ?? 0
        f.matches = matches(hit, catalog: catalog, files: manifest?.files ?? [:])
        if given(hit).isEmpty {
            let found = Probe.places(for: hit.folder)
            (f.places, f.otherBottles) = (found.named, found.others.count)
        } else {
            f.places = given(hit)
        }
        if !hit.game.inApp {
            // A game in Steam Play prefixes alone runs from a runner; in bottles alone, from a CrossOver app.
            let kinds = kinds(f)
            f.runners = Engine.targets()
                .filter { kinds == [.steamPlay] ? $0.app == nil : kinds == [.bottle] ? $0.app != nil : true }
                .map { Runner(name: $0.name, build: $0.build, d3dmetal: Engine.d3dmetal(in: $0.root)) }
        }
        f.ownLogs = ownLogs(hit.game, folder: hit.folder)
        f.session = session
        f.model = sysctl("hw.model")
        f.chip = sysctl("machdep.cpu.brand_string")
        return f
    }

    /// The row a button acts on, of those selected in Games: exactly one, in the
    /// state the button needs. The window and the command line both ask this.
    static func target(_ selected: [Hit], kind: Kind) -> Hit? {
        selected.count == 1 && refusal(selected[0].game.name, state: selected[0].state, kind: kind) == nil ? selected[0] : nil
    }

    /// Why a button does not act on a game in this state, as the command line
    /// prints it and the window's status line says it; nil when it does.
    static func refusal(_ name: String, state: FixState, kind: Kind) -> String? {
        state == kind.state ? nil : "\(name): \(state.label); \(kind.button) needs \(kind.state.label)"
    }

    /// For the command line: the row of Games for a game, by its name, probed as the
    /// window probes it; or, when there is none this button may act on, why.
    static func row(_ name: String, kind: Kind, catalog: URL) async -> (hit: Hit?, why: String) {
        guard var hit = Libraries.find(Catalog.games(in: catalog), extra: []).hits.first(where: { $0.game.name == name })
        else { return (nil, "no such game here: \(name)") }
        if hit.game.needsPrefix && hit.chosen.isEmpty {
            hit.state = .unknown
        } else {
            hit.state = await Fixer.status(hit.game, folder: hit.folder, prefixes: hit.chosen.map(\.path.path), catalog: catalog)
        }
        guard let target = target([hit], kind: kind) else { return (nil, refusal(name, state: hit.state, kind: kind) ?? "") }
        return (target, "")
    }

    /// The files where the fix goes whose SHA-256 is that of a file of the catalog,
    /// each with that file's name: in the game folder itself and its carrier's
    /// folder, and, for a fix whose DLLs go into the prefix, in the system32 of each
    /// prefix it was given. None of them is looked into further. Only a file of the
    /// size of one of the catalog's is read, so a game's large archives are not.
    static func matches(_ hit: Hit, catalog: URL, files: [String: String]) -> [(file: String, catalog: String)] {
        let fm = FileManager.default
        func size(_ url: URL) -> Int? {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            return values.fileSize
        }
        var byHash: [String: String] = [:]
        var sizes = Set<Int>()
        for (name, hash) in files.sorted(by: { $0.key < $1.key }) {
            if byHash[hash] == nil { byHash[hash] = name }
            if let s = size(catalog.appendingPathComponent(name)) { sizes.insert(s) }
        }
        var places: [(dir: URL, shown: String)] = [(hit.folder, "")]
        if !hit.game.carrierDir.isEmpty {
            places.append((hit.folder.appendingPathComponent(hit.game.carrierDir), hit.game.carrierDir + "/"))
        }
        if hit.game.inPrefix {
            for p in hit.chosen {
                places.append((p.path.appendingPathComponent("drive_c/windows/system32"), "\(p.label): windows/system32/"))
            }
        }
        var found: [(file: String, catalog: String)] = []
        for (dir, shown) in places {
            let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])) ?? []
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let s = size(url), sizes.contains(s), let hash = sha256(url), let name = byHash[hash] else { continue }
                found.append((shown + url.lastPathComponent, name))
            }
        }
        return found
    }

    static func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Each log the fix writes beside its DLL (Game.logs) that is in the carrier's
    /// folder or the game folder itself, with its last lines; one that is there and
    /// cannot be read, with why.
    static func ownLogs(_ game: Game, folder: URL, lines: Int = logLines) -> [OwnLog] {
        var found: [OwnLog] = []
        for name in game.logs ?? [] {
            for dir in game.carrierDir.isEmpty ? [""] : [game.carrierDir, ""] {
                let path = dir.isEmpty ? name : dir + "/" + name
                let url = folder.appendingPathComponent(path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                found.append(ownLog(url, name: name, path: path, lines: lines))
                break
            }
        }
        return found
    }

    /// A log's last lines, read from its end alone (logTail), each cut at lineLength
    /// and with its control characters but the tab shown as U+FFFD, so that neither
    /// a log a fix let grow nor one with binary in it reaches the report or the link
    /// as it is.
    static func ownLog(_ url: URL, name: String, path: String, lines: Int) -> OwnLog {
        var log = OwnLog(name: name, path: path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
        log.modified = values?.contentModificationDate
        guard values?.isRegularFile == true else { log.error = "it is not a file"; return log }
        // open(2) for the reason in its own words: Foundation's for a read refused is about saving.
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { log.error = String(cString: strerror(errno)); return log }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let data: Data
        do {
            let size = try handle.seekToEnd()
            log.size = Int(size)
            try handle.seek(toOffset: size > UInt64(logTail) ? size - UInt64(logTail) : 0)
            data = try handle.readToEnd() ?? Data()
        } catch {
            log.error = error.localizedDescription
            return log
        }
        var all = String(decoding: data, as: UTF8.self)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if all.last == "" { all.removeLast() }
        // Read from inside the file, the first line is the end of one.
        if log.size > logTail, !all.isEmpty { all.removeFirst() } else { log.total = all.count }
        log.lines = all.suffix(lines).map { line in
            let shown = String(String.UnicodeScalarView(line.unicodeScalars.map {
                $0 != "\t" && $0.properties.generalCategory == .control ? "\u{FFFD}" : $0
            }))
            return shown.count > lineLength ? shown.prefix(lineLength) + " [cut: \(shown.count) characters]" : shown
        }
        return log
    }

    /// This window's Settings › Log lines for the game: each block an install or a
    /// removal wrote, from its "▸ <game> — <folder>" line through the indented lines
    /// under it. The log is the window's alone, kept in memory. The folder is
    /// compared as gameKey compares it, /var and /private/var as one.
    static func session(_ log: [String], game: String, folder: URL) -> [String] {
        let head = "▸ \(game) — ", key = gameKey(folder, game)
        var out: [String] = []
        var inside = false
        for line in log {
            if line.hasPrefix(head) {
                inside = gameKey(URL(fileURLWithPath: String(line.dropFirst(head.count))), game) == key
            } else if !(inside && line.hasPrefix("  ")) {
                inside = false
            }
            if inside { out.append(line) }
        }
        return out
    }

    static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return "" }
        return String(cString: value)
    }

    /// macOS's version, as the forms ask for it: "27.0".
    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    // MARK: The form's fields

    /// "Where it runs", one of the form's options exactly; nil, for the player,
    /// unless the folder says it: a macOS game; Steam Play prefixes alone, with a
    /// NotProton runner on this Mac; CrossOver bottles alone.
    static func runs(_ f: Facts) -> String? {
        if f.game.inApp { return "Native macOS (no Wine)" }
        let kinds = kinds(f)
        if kinds == [.steamPlay] && !f.runners.isEmpty { return "A NotProton runner" }
        if kinds == [.bottle] { return "A CrossOver bottle" }
        return nil
    }

    /// The kinds of place the game runs in: those the report names, or, when it
    /// names none, the bottles it only counts.
    static func kinds(_ f: Facts) -> Set<Prefix.Kind> {
        f.places.isEmpty && f.otherBottles > 0 ? [.bottle] : Set(f.places.map(\.kind))
    }

    /// "Graphics backend", one of the form's options exactly, for a macOS game
    /// alone: which backend ran a Windows game is not read, and the one the
    /// catalog names is what the fix was made for, not what was played. Mortal
    /// Kombat 11's names D3DMetal, and its fix works on DXMT as well.
    static func backend(_ game: Game) -> String? {
        game.inApp ? "None (a macOS game)" : nil
    }

    /// The backend the catalog says the fix is made for (games.json's backend),
    /// by the form's names, for the report.
    static func madeFor(_ game: Game) -> String? {
        switch game.backend {
        case "d3dmetal": return "D3DMetal"
        case "dxmt": return "DXMT"
        case "dxvk": return "DXVK / MoltenVK"
        default: return nil
        }
    }

    /// "Versions": MacGameFix and its catalog, the CrossOver apps or runners of the
    /// kind the game runs in with the D3DMetal builds each carries, macOS and the chip.
    static func versions(_ f: Facts) -> String {
        var parts = ["MacGameFix \(Catalog.appVersion), catalog \(f.catalogVersion)"]
        if !f.runners.isEmpty {
            parts.append(f.runners.map { r in
                let d3dmetal = Set(r.d3dmetal.map(\.version)).sorted()
                return "\(r.name) (\(r.build)" + (d3dmetal.isEmpty ? "" : ", D3DMetal " + d3dmetal.joined(separator: " and ")) + ")"
            }.joined(separator: " or "))
        }
        parts.append("macOS \(macOS)")
        if !f.chip.isEmpty { parts.append(f.chip) }
        return parts.joined(separator: "; ")
    }

    /// "Game Porting Toolkit (D3DMetal)": the one D3DMetal the places the game runs
    /// from carry, when they carry only one; which of several ran it is not read.
    static func toolkit(_ f: Facts) -> String? {
        let all = Set(f.runners.flatMap { $0.d3dmetal.map(\.version) })
        return all.count == 1 ? all.first : nil
    }

    /// "The game's version": the build its installer names, or Steam's build id.
    static func gameVersion(_ f: Facts) -> String? {
        f.build ?? f.steamBuild.map { "Steam build \($0)" }
    }

    /// "MacGameFix's log": the fix's own log, then this window's Settings › Log lines
    /// for the game, each while the field stays within what an issue's address
    /// carries (Report.longest). What does not fit is in the report, and the field
    /// says so; with no Settings › Log lines, the field says that instead.
    static func logField(_ f: Facts) -> String {
        let names = (f.game.logs ?? []).joined(separator: ", ")
        let none = "Settings › Log: nothing this window ran for this game."
        let elsewhere = "Settings › Log's lines for this game are in the attached report: more than this link carries."
        // The own log fits beside the least the session's part says: none, or where its lines are.
        let least = f.session.isEmpty ? none : elsewhere
        var own: String
        if names.isEmpty {
            own = "The fix writes no log of its own."
        } else if f.ownLogs.isEmpty {
            own = "No \(names) in the game's folder."
        } else {
            own = Probe.redact(f.ownLogs.map { log in
                log.error.map { "\(log.path) is there and could not be read (\($0))." }
                    ?? "\(log.path), \(written(log)):\n" + log.lines.joined(separator: "\n")
            }.joined(separator: "\n\n"))
            if own.utf8.count + 2 + least.utf8.count > Report.longest {
                own = "The fix's own log, \(names), is in the attached report: more than this link carries."
            }
        }
        let lines = Probe.redact(f.session.joined(separator: "\n"))
        let session = f.session.isEmpty ? none : own.utf8.count + 2 + lines.utf8.count > Report.longest ? elsewhere : lines
        return own + "\n\n" + session
    }

    /// The form, filled in: fields left out are the player's to fill.
    static func issue(_ f: Facts) -> URL? {
        var fields = [("title", f.kind.title + f.game.name),
                      ("game", f.game.name + (f.appid.isEmpty ? "" : " (Steam app \(f.appid))"))]
        switch f.kind {
        case .works:
            if let runs = runs(f) { fields.append(("runs", runs)) }
            if let backend = backend(f.game) { fields.append(("backend", backend)) }
            fields.append(("versions", versions(f)))
            if let version = gameVersion(f) { fields.append(("game-version", version)) }
            fields.append(("log", logField(f)))
        case .without:
            if let toolkit = toolkit(f) { fields.append(("toolkit", toolkit)) }
            fields.append(("versions", versions(f)))
        }
        return Issue.new(template: f.kind.template, fields: fields.map { ($0.0, Probe.redact($0.1)) })
    }

    // MARK: The report's section

    private static func written(_ log: OwnLog) -> String {
        log.modified.map { "last written \(ISO8601DateFormatter().string(from: $0))" } ?? "its time not read"
    }

    /// The section on the fix, after the report's first lines: blocks of Markdown,
    /// a blank line between each.
    static func section(_ f: Facts) -> String {
        func fenced(_ lines: [String]) -> String { "```\n" + (lines.isEmpty ? "(nothing)" : lines.joined(separator: "\n")) + "\n```" }
        func list(_ items: [String]) -> String { items.map { "- " + $0 }.joined(separator: "\n") }
        var blocks = ["## The fix"]
        var about = ["State: \(f.state.label), as its installer says below",
                     "Installer: \(f.game.script), of catalog \(f.catalogVersion)"]
        if let build = f.build { about.append("The game's build: \(build), as its installer reads it") }
        if let build = f.steamBuild { about.append("Steam's build: \(build), from the game's appmanifest") }
        blocks.append(list(about))

        blocks.append("### What its installer says (--status)")
        if f.status.isEmpty { blocks.append("Not asked: no prefix is chosen for it in Games.") }
        for s in f.status {
            if let place = s.place { blocks.append("Into the \(place): \(s.state.label)") }
            blocks.append(fenced(s.lines))
        }

        blocks.append("### Files that match the catalog")
        blocks.append(f.matches.isEmpty
            ? "None: no file in the game folder" + (f.game.carrierDir.isEmpty ? "" : " or in \(f.game.carrierDir)")
                + " matches a file of catalog \(f.catalogVersion)."
            : list(f.matches.map { "`\($0.file)` is the catalog's `\($0.catalog)`" }))

        blocks.append("### Where it runs")
        var places: [String] = []
        if f.game.inApp {
            places.append("A macOS game: no Wine runs it")
        } else {
            let named = f.places.map(\.label) + [Probe.others(f.otherBottles)].compactMap { $0 }
            places.append(named.isEmpty ? "No prefix or bottle found beside its library" : "In: " + named.joined(separator: ", "))
            for r in f.runners {
                places.append("\(r.name), build \(r.build): " + (r.d3dmetal.isEmpty ? "no D3DMetal found"
                    : r.d3dmetal.map { "D3DMetal \($0.version) (\($0.folder))" }.joined(separator: ", ")))
            }
            if f.runners.isEmpty { places.append("No CrossOver app or NotProton runner found of the kind it runs in") }
            if f.runners.count > 1 || f.runners.contains(where: { $0.d3dmetal.count > 1 }) {
                places.append("Which of these ran the game is not read")
            }
            if let backend = madeFor(f.game) { places.append("Graphics backend: not read; the fix is made for \(backend)") }
        }
        places.append("This Mac: " + ([f.model, f.chip].filter { !$0.isEmpty } + ["macOS \(macOS)"]).joined(separator: ", "))
        blocks.append(list(places))

        blocks.append("### The fix's own log")
        let names = f.game.logs ?? []
        if names.isEmpty { blocks.append("The fix writes no log of its own beside its DLL.") }
        for name in names {
            guard let log = f.ownLogs.first(where: { $0.name == name }) else {
                blocks.append("\(name): not in the game's folder. The fix writes it beside its DLL while the game runs.")
                continue
            }
            if let error = log.error {
                blocks.append("\(log.path) is there and could not be read (\(error)).")
                continue
            }
            blocks.append("#### \(log.path), \(written(log)): its last \(log.lines.count) "
                + (log.total.map { "of \($0) lines" } ?? "lines, read from the end of its \(log.size) bytes"))
            if f.kind == .without { blocks.append("Written while the fix was in place: it is not installed now.") }
            blocks.append(fenced(log.lines))
        }

        blocks.append("### Settings › Log")
        blocks.append(f.session.isEmpty
            ? "None. Settings › Log is kept in memory only and holds what this window ran since it opened; "
                + "it ran nothing for \(f.game.name)."
            : fenced(f.session))

        let report = f.kind == .works ? "its fix works, played with the fix installed"
                                      : "it works without its fix, played with the fix removed"
        return "- Report: \(report)\n\n" + blocks.joined(separator: "\n\n") + "\n"
    }
}
