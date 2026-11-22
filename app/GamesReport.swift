// A machine-readable companion to --games-report. No paths or raw logs are included.
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct GamesReport: Encodable {
    let schemaVersion = 1
    let appVersion: String
    let games: [Game]

    struct Game: Encodable {
        let name: String
        let executable: String
        let requirement: String
        let manualInstall: Bool
        let needsPrefix: Bool
        let prefixCount: Int
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
