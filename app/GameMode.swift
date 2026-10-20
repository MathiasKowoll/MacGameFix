// Game Mode for CrossOver's games.
//
// macOS turns Game Mode on for the app in front, in full screen, when its bundle
// says it is a game (LSApplicationCategoryType public.app-category.games). A game
// in CrossOver never is one: CrossOver's ntdll (CW HACK 22144, create_preloader_link
// in dlls/ntdll/unix/loader.c) starts each process again from a link named after
// its exe, in $TMPDIR/winetemp-<inode>-<size>-<mtime>-<nsec>/ of the loader, and
// that link is in no bundle. ntdll keeps a link that is already there. So for each
// game's exe this leaves one pointing at a copy of the loader inside a bundle that
// says it is a game; beside the copy, a symlink to CrossOver's ntdll.so, whose real
// path is where Wine finds the rest of itself. CrossOver itself is not changed.
//
// Measured on 2026-10-19 with NotProton's launcher bundle, which works the same
// way: Spider-Man 2 in full screen ran with Game Mode on, and Game Mode doubles
// what a DualSense's Bluetooth link carries (engine/README.md).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum GameMode {
    /// The CrossOver releases whose ntdll names and reuses the link as above, read in
    /// their sources: 26.1 and 26.3 (Wine 11.0), Preview 20261006 and 20261015 (Wine 11.17).
    static let checked = ["26.1.0.", "26.3.0.", "27.0.0.41069", "27.0.0.41073"]

    /// One loader a CrossOver app starts games with: its Intel side, and on a
    /// CrossOver with FEX the arm64 one, kept in a wine.app (CW HACK 27336).
    struct Loader {
        let target: EngineTarget
        let arch: String
        let path: URL
        /// The folder of its ntdll.so.
        let unix: URL
    }

    static var root: URL { Paths.support.appendingPathComponent("GameMode") }

    static func loaders() -> [Loader] {
        let fm = FileManager.default
        var out: [Loader] = []
        for target in Engine.targets() where target.app != nil {
            guard checked.contains(where: { target.build == $0 || ($0.hasSuffix(".") && target.build.hasPrefix($0)) })
            else { continue }
            let wine = target.root.appendingPathComponent("lib/wine")
            for (arch, dir) in [("x86_64", "x86_64-unix"), ("arm64", "aarch64-unix")] {
                let unix = wine.appendingPathComponent(dir)
                guard fm.fileExists(atPath: unix.appendingPathComponent("ntdll.so").path) else { continue }
                // Where ntdll's init_paths looks: wine.app/Contents/MacOS/wine first, then wine.
                let inApp = unix.appendingPathComponent("wine.app/Contents/MacOS/wine")
                let flat = unix.appendingPathComponent("wine")
                let path = fm.isReadableFile(atPath: inApp.path) ? inApp : flat
                guard fm.isExecutableFile(atPath: path.path) else { continue }
                out.append(Loader(target: target, arch: arch, path: path, unix: unix))
            }
        }
        return out
    }

    /// One per CrossOver app and side: two apps of one build (CrossOver.app and a copy) each have theirs.
    static func bundle(for loader: Loader) -> URL {
        let app = loader.target.app?.deletingPathExtension().lastPathComponent ?? "CrossOver"
        return root.appendingPathComponent("\(app) \(loader.target.build) \(loader.arch)/CrossOver Game.app")
    }

    /// The user's temporary folder, as ntdll asks for it; MACGAMEFIX_TEMP_DIR for the tests.
    static var temporary: URL {
        if let dir = ProcessInfo.processInfo.environment["MACGAMEFIX_TEMP_DIR"] { return URL(fileURLWithPath: dir) }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    /// ntdll's folder for a loader: "winetemp-%llu-%llu-%lu-%lu", its inode, size,
    /// and modification time in seconds and nanoseconds.
    static func winetemp(for loader: URL) -> URL? {
        var st = stat()
        guard stat(loader.path, &st) == 0 else { return nil }
        let name = "winetemp-\(st.st_ino)-\(st.st_size)-\(st.st_mtimespec.tv_sec)-\(st.st_mtimespec.tv_nsec)"
        return temporary.appendingPathComponent(name)
    }

    /// Puts the bundle in place, or brings its copy of the loader up to date: the
    /// copy, and whether anything had to change.
    static func makeBundle(for loader: Loader) -> (copy: URL, changed: Bool)? {
        let fm = FileManager.default
        let app = bundle(for: loader)
        let macos = app.appendingPathComponent("Contents/MacOS")
        let copy = macos.appendingPathComponent("wine")
        let launcher = macos.appendingPathComponent("launcher")
        let source = macos.appendingPathComponent(".source")
        let ntdll = macos.appendingPathComponent("ntdll.so")
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let info: [String: Any] = [
            "CFBundleName": "CrossOver Game",
            "CFBundleIdentifier": "io.github.macgamefix.game-mode.\(loader.target.build).\(loader.arch)",
            // Not the copy of the loader: a main executable is checked against the bundle's
            // Info.plist, and CodeWeavers sign the loader with an Info.plist of its own, so
            // the copy read as modified. NotProton's launcher bundles keep it beside a script.
            "CFBundleExecutable": "launcher",
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSApplicationCategoryType": "public.app-category.games",
            // As CrossOver's own loader declares: Wine shows a process in the Dock when it opens a window.
            "LSUIElement": true,
            "NSPrincipalClass": "WineApplication",
            "NSHighResolutionCapable": true,
            "NSMicrophoneUsageDescription": "This game would like to access your microphone.",
            "NSCameraUsageDescription": "This game would like to access your camera.",
        ]
        var changed = false
        do {
            try fm.createDirectory(at: macos, withIntermediateDirectories: true)
            // The copy is redone when CrossOver's loader changes, which its stamp says;
            // comparing contents would redo a copy that had to be signed again every time.
            let stamp = winetemp(for: loader.path)?.lastPathComponent ?? ""
            if (try? String(contentsOf: source, encoding: .utf8)) != stamp || !fm.fileExists(atPath: copy.path) {
                try? fm.removeItem(at: copy)
                try fm.copyItem(at: loader.path, to: copy)
                // The arm64 loader is signed as the executable of its own wine.app, whose
                // sealed resources a copy leaves behind: such a copy is signed again, ad hoc,
                // with its entitlements, as NotProton's runners have it.
                if !codesign(["-v", copy.path]) {
                    _ = codesign(["--force", "--sign", "-", "--preserve-metadata=entitlements,flags,runtime", copy.path])
                }
                try stamp.write(to: source, atomically: true, encoding: .utf8)
                changed = true
            }
            let target = loader.unix.appendingPathComponent("ntdll.so").path
            if (try? fm.destinationOfSymbolicLink(atPath: ntdll.path)) != target {
                try? fm.removeItem(at: ntdll)
                try fm.createSymbolicLink(atPath: ntdll.path, withDestinationPath: target)
                changed = true
            }
            let script = Data("#!/bin/sh\n# Only there to name the bundle's executable: games run from wine beside it.\nexit 0\n".utf8)
            if (try? Data(contentsOf: launcher)) != script {
                try script.write(to: launcher, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
                changed = true
            }
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            if (try? Data(contentsOf: plist)) != data {
                try data.write(to: plist, options: .atomic)
                changed = true
            }
        } catch {
            return nil
        }
        return (copy, changed)
    }

    /// Where games are: every game folder of every Steam library the app knows, and
    /// each CrossOver bottle's Program Files.
    static func gameFolders() -> [URL] {
        let fm = FileManager.default
        var folders: [URL] = []
        for common in Libraries.all(extra: []) {
            folders += ((try? fm.contentsOfDirectory(at: common, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.path < $1.path }
        }
        for bottle in Libraries.bottles() {
            for name in ["Program Files", "Program Files (x86)"] {
                folders.append(bottle.appendingPathComponent("drive_c").appendingPathComponent(name))
            }
        }
        return folders
    }

    /// The exes in those folders, four folders deep, but for Wine's own programs,
    /// which every CrossOver runs as well.
    static func exeNames(in folders: [URL], excluding: Set<String>) -> Set<String> {
        let fm = FileManager.default
        var names = Set<String>()
        var seen = Set<String>()   // APFS does not tell Launcher.exe from launcher.exe: one of them
        for folder in folders {
            guard let walk = fm.enumerator(at: folder, includingPropertiesForKeys: nil,
                                           options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walk {
                if walk.level > 4 { walk.skipDescendants(); continue }
                let name = url.lastPathComponent
                let key = name.lowercased()
                if key.hasSuffix(".exe"), !excluding.contains(key), seen.insert(key).inserted { names.insert(name) }
            }
        }
        return names
    }

    /// The exes Wine itself ships: services, explorer and the rest.
    static func wineOwn(_ loaders: [Loader]) -> Set<String> {
        var own = Set<String>()
        for loader in loaders {
            let windows = loader.unix.deletingLastPathComponent()
                .appendingPathComponent(loader.arch == "arm64" ? "aarch64-windows" : "x86_64-windows")
            for url in (try? FileManager.default.contentsOfDirectory(at: windows, includingPropertiesForKeys: nil)) ?? []
            where url.pathExtension.lowercased() == "exe" {
                own.insert(url.lastPathComponent.lowercased())
            }
        }
        return own
    }

    /// What the last look through the game folders found, so that the agent's
    /// two-minute pass does not walk every library each time.
    private struct Scan: Codable {
        var folders: [String]
        var at: Date
        var names: [String]
    }

    private static var scanFile: URL { root.appendingPathComponent("scan.json") }

    /// The exe names, looked for again when the game folders change, or after half an hour.
    static func currentNames(_ loaders: [Loader], now: Date = Date()) -> Set<String> {
        let folders = gameFolders()
        let paths = folders.map(\.path)
        if let data = try? Data(contentsOf: scanFile), let scan = try? JSONDecoder().decode(Scan.self, from: data),
           scan.folders == paths, now.timeIntervalSince(scan.at) < 1800 {
            return Set(scan.names)
        }
        let names = exeNames(in: folders, excluding: wineOwn(loaders))
        if let data = try? JSONEncoder().encode(Scan(folders: paths, at: now, names: names.sorted())) {
            try? data.write(to: scanFile, options: .atomic)
        }
        return names
    }

    /// Puts every bundle and link in place; what it changed, for the log.
    @discardableResult
    static func keep() -> [String] {
        let fm = FileManager.default
        let loaders = loaders()
        guard !loaders.isEmpty else { return [] }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let names = currentNames(loaders)
        var changed: [String] = []
        for loader in loaders {
            guard let bundled = makeBundle(for: loader), let dir = winetemp(for: loader.path) else { continue }
            let copy = bundled.copy
            if bundled.changed { register(bundle(for: loader)) }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var linked = 0
            for name in names {
                // The loader again under the exe's name, as ntdll's own link has it, so the
                // Dock names the game: a hard link to the copy, which takes no room.
                let named = copy.deletingLastPathComponent().appendingPathComponent(name)
                if !sameFile(named, copy) {
                    try? fm.removeItem(at: named)
                    guard (try? fm.linkItem(at: copy, to: named)) != nil else { continue }
                }
                let link = dir.appendingPathComponent(name)
                if let to = try? fm.destinationOfSymbolicLink(atPath: link.path) {
                    // Ours already, or somebody else's link, which is left alone.
                    if to == named.path || !to.hasPrefix(root.path) { continue }
                }
                try? fm.removeItem(at: link)   // ntdll's own link, in no bundle
                if (try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: named.path)) != nil { linked += 1 }
            }
            if linked > 0 { changed.append("Game Mode: \(linked) exe(s) linked for \(loader.target.name) (\(loader.arch)).") }
        }
        return changed
    }

    /// What the settings say beside the switch: the CrossOvers it covers.
    static func coverage() -> String {
        var sides: [String: [String]] = [:]
        var order: [String] = []
        for loader in loaders() {
            if sides[loader.target.name] == nil { order.append(loader.target.name) }
            sides[loader.target.name, default: []].append(loader.arch == "arm64" ? "FEX" : "Intel")
        }
        guard !order.isEmpty else {
            return "No CrossOver of a release this was checked with: 26.1, 26.3, Preview 20261006 or 20261015."
        }
        return "For " + order.map { "\($0) (\(sides[$0]!.joined(separator: " and ")))" }.joined(separator: ", ") + "."
    }

    /// Takes every link of ours out of ntdll's folders, and the bundles with them.
    static func remove() {
        let fm = FileManager.default
        for dir in (try? fm.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        where dir.lastPathComponent.hasPrefix("winetemp-") {
            for link in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                if let to = try? fm.destinationOfSymbolicLink(atPath: link.path), to.hasPrefix(root.path) {
                    try? fm.removeItem(at: link)
                }
            }
        }
        try? fm.removeItem(at: root)
    }

    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        var sa = stat(), sb = stat()
        return lstat(a.path, &sa) == 0 && lstat(b.path, &sb) == 0 && sa.st_ino == sb.st_ino && sa.st_dev == sb.st_dev
    }

    private static func codesign(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Tells Launch Services about a bundle, as NotProton does for its launchers.
    private static func register(_ app: URL) {
        let tool = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
            + "LaunchServices.framework/Support/lsregister"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["-f", app.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
