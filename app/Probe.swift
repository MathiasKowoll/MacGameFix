// The Report tab's probe: what a game is made of, read from its folder alone, and
// the report a user attaches to an issue about a game that does not work.
// Nothing here writes into a game, its prefix or its bottle.
import Foundation

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
    /// home folder is written ~ and the Mac's name is left out.
    static func report(_ game: ProbeGame, symptom: String, findings f: ProbeFindings, fix: String?,
                       engines: [(name: String, build: String, state: String)], padLines: [String],
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
        var out = "# MacGameFix game report: \(game.name)\n\n"
        out += "- Made: \(ISO8601DateFormatter().string(from: now))\n"
        out += "- MacGameFix \(Catalog.appVersion); macOS \(ProcessInfo.processInfo.operatingSystemVersionString); "
            + "\(shell(["/usr/sbin/sysctl", "-n", "hw.model"]))\n"
        out += "- Game: \(game.name), Steam app \(game.appid)\n"
        out += "- What goes wrong: \(symptom)\n"
        out += "- Folder: \(game.folder.path)\n"
        var prefixes: [String] = []
        for p in Libraries.prefixes(for: game.folder) {
            let words = (p.kind == .bottle ? "the CrossOver bottle \"\(p.path.lastPathComponent)\"" : "a Steam Play prefix")
                + " (\(p.path.path))"
            if !prefixes.contains(words) { prefixes.append(words) }
        }
        out += "- Runs in: " + (prefixes.isEmpty ? "no prefix or bottle found beside its library" : prefixes.joined(separator: "; ")) + "\n"
        out += "- MacGameFix: " + (fix.map { "has a fix for it (\($0))" } ?? "has no fix for it") + "\n"

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

    /// The home folder as ~, and neither the account's name nor the Mac's.
    static func redact(_ text: String) -> String {
        var out = text
        for home in [Paths.home.path, NSHomeDirectory()] where home.count > 1 {
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
