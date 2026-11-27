// The "Processors the game sees" row in NotProton's panel, made for this Mac.
//
// CrossOver's ntdll shows a game WINENCPU processors when it is set, and NotProton sets it
// from a game's NOTPROTON_ENV_WINENCPU launch option. Fewer processors make some engines
// start fewer worker threads, and the Mac runs cooler: Forza Horizon 6 with 8 of an M4
// Max's 16 was measured cooler. Most games want every processor, so the row says All
// unless the player picks a count for one game, and it only offers counts this Mac has:
// a game shown more processors than there are would start threads for cores that do
// not exist.
//
// NotProton's panel shows a choice row's `default` when a game has no option, and picking
// the default clears the option. So `default` has to be what a game gets with no option,
// which is All (0, as NotProton's own defaults page writes it).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum ProcessorsRow {
    static let id = "NOTPROTON_ENV_WINENCPU"
    static var file: URL { Engine.notproton.appendingPathComponent("plugins/mgf-ncpu.conf") }
    static let maxChoices = NotProtonRow.maxChoices

    /// This Mac's processors, and how many of them are performance cores.
    /// MACGAMEFIX_CPUS="<all>,<performance>" stands in for the Mac in the tests.
    static func counts() -> (all: Int, performance: Int) {
        if let given = ProcessInfo.processInfo.environment["MACGAMEFIX_CPUS"] {
            let parts = given.split(separator: ",").compactMap { Int($0) }
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        func sysctl(_ name: String) -> Int {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
        }
        let all = ProcessInfo.processInfo.processorCount
        return (all, sysctl("hw.perflevel0.logicalcpu"))
    }

    /// The counts offered besides All: even ones from 4, and the performance cores, all
    /// below what the Mac has. A Mac with so many that they do not fit goes in steps of 4.
    static func choices(all: Int, performance: Int) -> [Int] {
        for step in [2, 4, 8] {
            var values = Set(stride(from: 4, to: all, by: step))
            if performance > 1 && performance < all { values.insert(performance) }
            let sorted = values.filter { $0 < all && $0 <= 64 }.sorted()
            if sorted.count < maxChoices { return sorted }
        }
        return []
    }

    /// The row's text. `grouped` when the NotProton in Steam knows the group field: an
    /// older one refuses a row with a field it does not know.
    static func text(all: Int, performance: Int, grouped: Bool) -> String {
        var lines = [
            "[\(id)]",
            NotProtonRow.label("Processors the game sees", grouped: grouped),
        ]
        if grouped { lines.append("group = MacGameFix / Performance") }
        lines += [
            "description = All by default. Some games run cooler or steadier with fewer",
            "section = dev",
            "type = choice",
            "default = 0",
            "choice = 0 = All (\(all))",
        ]
        for n in choices(all: all, performance: performance) {
            lines.append(n == performance ? "choice = \(n) = \(n) (performance cores)" : "choice = \(n)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The row put in place, or brought up to date, where NotProton is (NotProtonRow.keep).
    @discardableResult
    static func keep() -> String? {
        let (all, performance) = counts()
        return NotProtonRow.keep(name: "processors", id: id, file: file.lastPathComponent,
                                 written: "written for \(all) processors") { grouped in
            guard all > 0 else { return .failure(.init(text: "this Mac's processors could not be read")) }
            return .success(text(all: all, performance: performance, grouped: grouped))
        }
    }
}
