// Fans at full speed for the games the user chooses.
//
// macOS raises the fans about a minute after a game starts to load its world. By
// then the chip is at 73-78 C, and the kernel's power manager sets a thermal power
// budget that holds the performance cores at 1.8 GHz of 4.5 for minutes. Measured
// on 2026-11-14 with Forza Horizon 6 on an M4 Max: with both fans at their maximum
// from launch, the chip levelled at 66-69 C, the cores stayed at 4.5 GHz and no
// budget was set at all.
//
// The fans are the SMC's, and writing to it needs root. fans/mgf-fans.c is the
// helper: a LaunchDaemon, installed and removed here through macOS's own password
// prompt. It forces the fans while a game that asked is running and hands them back
// to macOS when none is. A game asks with MGF_FANS=max in its NotProton launch options;
// a row for it goes into NotProton's panel in Steam, where a game's other options are.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum Fans {
    static let label = "io.github.macgamefix.fans"

    /// MACGAMEFIX_FANS_PREFIX stands in for / in the tests, as MGF_FANS_PREFIX does for the helper.
    static var prefix: String { ProcessInfo.processInfo.environment["MACGAMEFIX_FANS_PREFIX"] ?? "" }
    static var installed: URL { URL(fileURLWithPath: prefix + "/Library/PrivilegedHelperTools/" + label) }
    static var daemonPlist: URL { URL(fileURLWithPath: prefix + "/Library/LaunchDaemons/" + label + ".plist") }
    static var log: URL { URL(fileURLWithPath: prefix + "/var/log/" + label + ".log") }
    /// The helper this app carries.
    static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("fans/" + label) }
    /// NotProton's panel row, in its plugins folder.
    static var notProtonRow: URL { Engine.notproton.appendingPathComponent("plugins/mgf-fans.conf") }

    enum State: String { case absent, outdated, installed }

    /// Whether the helper is in place, and whether the app carries a newer one. The helper says
    /// its version itself: every build is signed anew, so two builds of one source are different
    /// files, and comparing them would ask for the password after every update of the app.
    static func state() -> State {
        let fm = FileManager.default
        guard fm.fileExists(atPath: installed.path), fm.fileExists(atPath: daemonPlist.path) else { return .absent }
        guard let bundled, let ours = version(of: bundled) else { return .installed }
        // A helper from before it had a version answers nothing: older than any.
        return (version(of: installed) ?? 0) < ours ? .outdated : .installed
    }

    /// What a helper answers to --version, or nil when it does not say.
    static func version(of helper: URL) -> Int? {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return nil }
        let (status, output) = run(helper.path, ["--version"], environment: [:])
        return status == 0 ? Int(output) : nil
    }

    /// Installs or updates the helper, or removes it, as root: macOS asks for the password.
    /// What went wrong, or nil.
    static func change(install: Bool) -> String? {
        guard let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) else {
            return "This build of MacGameFix carries no fan helper."
        }
        let verb = install ? "--install" : "--remove"
        let status: Int32
        let output: String
        if !prefix.isEmpty {
            // The tests: no root, no prompt, nothing started.
            (status, output) = run(bundled.path, [verb], environment: ["MGF_FANS_PREFIX": prefix])
        } else {
            let quoted = "\"" + bundled.path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
            let script = "do shell script (quoted form of \(quoted)) & \" \(verb)\" with prompt "
                + "\"MacGameFix \(install ? "installs" : "removes") the helper that runs the fans at full speed for the games that ask.\" "
                + "with administrator privileges"
            (status, output) = run("/usr/bin/osascript", ["-e", script], environment: [:])
        }
        if status == 0 {
            stageNotProtonRow(install)
            return nil
        }
        // -128: the user cancelled the password prompt.
        if output.contains("-128") { return "Cancelled." }
        return output.isEmpty ? "The helper could not be \(install ? "installed" : "removed")." : output
    }

    private static func run(_ executable: String, _ arguments: [String], environment: [String: String]) -> (Int32, String) {
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
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (proc.terminationStatus, text)
    }

    /// The row "Fans at full speed" in NotProton's panel, for the games started through it.
    /// Only where NotProton is; taken away with the helper.
    static func stageNotProtonRow(_ on: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Engine.notproton.path) else { return }
        guard on else { try? fm.removeItem(at: notProtonRow); return }
        let row = """
        [MGF_FANS]
        label = Fans at full speed
        description = Runs the Mac's fans at their maximum while this game runs, before the Mac gets hot enough for macOS to cut the processor's speed (MacGameFix)
        section = dev
        on = max
        requires = /Library/PrivilegedHelperTools/\(label)

        """
        try? fm.createDirectory(at: notProtonRow.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? String(contentsOf: notProtonRow, encoding: .utf8)) != row {
            try? row.write(to: notProtonRow, atomically: true, encoding: .utf8)
        }
    }

    /// What the helper last said: "a game asks: full speed on", "no game asks: automatic".
    static func lastLine() -> String {
        guard let text = try? String(contentsOf: log, encoding: .utf8),
              let line = text.split(separator: "\n").last else { return "" }
        return String(line)
    }
}
