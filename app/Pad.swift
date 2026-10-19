// The DualSense options, per game: the Game Feel tab's side of the Wine modules.
//
// The modules (engine/) read their options from two plain files this writes, so
// what reads them never needs more than key=value lines: pad.conf for every game,
// and pad.d/<Steam app id>.conf for one game, whose lines win. What the user chose
// is kept in pad.json, beside the presets the app ships (pad-presets.json, options
// measured on a title) and what the modules saw each game do, which they write to
// their log and this reads back. A game's options are its own over its preset over
// every game's.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One set of options. nil leaves an option to what comes under it.
struct PadOptions: Codable, Equatable, Hashable {
    /// A DualSense on Bluetooth shown to games as the same pad on a cable.
    var bluetoothAsCable: Bool?
    /// The Edge's motor power claimed at full, as Sony's library claims it for a
    /// standard DualSense and never for an Edge.
    var fullMotorPower: Bool?
    /// The Edge shown to the game as a standard DualSense.
    var edgeAsDualSense: Bool?
    /// The haptics multiplied, with a soft limit, per pad and per connection: a
    /// pad does not feel the same stream alike on a cable and over Bluetooth.
    var hapticsGainCable: Double?
    var edgeHapticsGainCable: Double?
    var hapticsGainBluetooth: Double?
    var edgeHapticsGainBluetooth: Double?
    /// What XInput gets of the pad: "off"; "rumble", its motors for a game that
    /// reads the pad itself but rumbles through XInput; "pad", the pad itself as
    /// an XInput controller, for a game that reads nothing else.
    var xinput: String?
    /// Over Bluetooth, the game's motor values played on the haptic actuators,
    /// for a game that rumbles and plays no haptics of its own.
    var rumbleHaptics: Bool?
    /// A trigger effect for a game that sets none of its own: "off", or an
    /// effect with an optional strength, "weapon@6" (PadTrigger).
    var triggerR2: String?
    var triggerL2: String?
    /// A second effect for while the other trigger is pressed; "off" keeps the first.
    var triggerR2WithL2: String?
    var triggerL2WithR2: String?

    /// What the user starts with: everything the modules do turned on, and the
    /// Edge's haptics doubled, which made it feel like a DualSense in Spider-Man 2
    /// on a cable and over Bluetooth.
    static let firstRun = PadOptions(bluetoothAsCable: true, fullMotorPower: true, edgeAsDualSense: false,
                                     hapticsGainCable: 1, edgeHapticsGainCable: 2,
                                     hapticsGainBluetooth: 1, edgeHapticsGainBluetooth: 2,
                                     xinput: "rumble", rumbleHaptics: false, triggerR2: "off", triggerL2: "off",
                                     triggerR2WithL2: "off", triggerL2WithR2: "off")

    /// These over `base`: each option this one sets, else base's.
    func over(_ base: PadOptions) -> PadOptions {
        PadOptions(bluetoothAsCable: bluetoothAsCable ?? base.bluetoothAsCable,
                   fullMotorPower: fullMotorPower ?? base.fullMotorPower,
                   edgeAsDualSense: edgeAsDualSense ?? base.edgeAsDualSense,
                   hapticsGainCable: hapticsGainCable ?? base.hapticsGainCable,
                   edgeHapticsGainCable: edgeHapticsGainCable ?? base.edgeHapticsGainCable,
                   hapticsGainBluetooth: hapticsGainBluetooth ?? base.hapticsGainBluetooth,
                   edgeHapticsGainBluetooth: edgeHapticsGainBluetooth ?? base.edgeHapticsGainBluetooth,
                   xinput: xinput ?? base.xinput,
                   rumbleHaptics: rumbleHaptics ?? base.rumbleHaptics,
                   triggerR2: triggerR2 ?? base.triggerR2,
                   triggerL2: triggerL2 ?? base.triggerL2,
                   triggerR2WithL2: triggerR2WithL2 ?? base.triggerR2WithL2,
                   triggerL2WithR2: triggerL2WithR2 ?? base.triggerL2WithR2)
    }

    var isEmpty: Bool { self == PadOptions() }

    /// The options of these that differ from `base`.
    func differences(from base: PadOptions) -> PadOptions {
        PadOptions(bluetoothAsCable: bluetoothAsCable == base.bluetoothAsCable ? nil : bluetoothAsCable,
                   fullMotorPower: fullMotorPower == base.fullMotorPower ? nil : fullMotorPower,
                   edgeAsDualSense: edgeAsDualSense == base.edgeAsDualSense ? nil : edgeAsDualSense,
                   hapticsGainCable: hapticsGainCable == base.hapticsGainCable ? nil : hapticsGainCable,
                   edgeHapticsGainCable: edgeHapticsGainCable == base.edgeHapticsGainCable ? nil : edgeHapticsGainCable,
                   hapticsGainBluetooth: hapticsGainBluetooth == base.hapticsGainBluetooth ? nil : hapticsGainBluetooth,
                   edgeHapticsGainBluetooth: edgeHapticsGainBluetooth == base.edgeHapticsGainBluetooth
                       ? nil : edgeHapticsGainBluetooth,
                   xinput: xinput == base.xinput ? nil : xinput,
                   rumbleHaptics: rumbleHaptics == base.rumbleHaptics ? nil : rumbleHaptics,
                   triggerR2: triggerR2 == base.triggerR2 ? nil : triggerR2,
                   triggerL2: triggerL2 == base.triggerL2 ? nil : triggerL2,
                   triggerR2WithL2: triggerR2WithL2 == base.triggerR2WithL2 ? nil : triggerR2WithL2,
                   triggerL2WithR2: triggerL2WithR2 == base.triggerL2WithR2 ? nil : triggerL2WithR2)
    }

    /// The lines the modules read, as engine/README.md lists them. Numbers with a
    /// point whatever the language: the modules read them that way.
    var lines: [String] {
        var out: [String] = []
        if let v = bluetoothAsCable { out.append("bluetooth=" + (v ? "wired" : "off")) }
        if let v = fullMotorPower { out.append("motor_power=" + (v ? "full" : "game")) }
        if let v = edgeAsDualSense { out.append("edge=" + (v ? "dualsense" : "edge")) }
        if let v = hapticsGainCable { out.append("haptics_gain_cable=" + PadOptions.number(v)) }
        if let v = edgeHapticsGainCable { out.append("edge_haptics_gain_cable=" + PadOptions.number(v)) }
        if let v = hapticsGainBluetooth { out.append("haptics_gain_bluetooth=" + PadOptions.number(v)) }
        if let v = edgeHapticsGainBluetooth { out.append("edge_haptics_gain_bluetooth=" + PadOptions.number(v)) }
        if let v = xinput, PadOptions.xinputModes.contains(v) { out.append("xinput=" + v) }
        if let v = rumbleHaptics { out.append("rumble=" + (v ? "haptics" : "motors")) }
        if let v = triggerR2, PadTrigger(v) != nil { out.append("trigger_r2=" + v) }
        if let v = triggerL2, PadTrigger(v) != nil { out.append("trigger_l2=" + v) }
        if let v = triggerR2WithL2, PadTrigger(v) != nil { out.append("trigger_r2_with_l2=" + v) }
        if let v = triggerL2WithR2, PadTrigger(v) != nil { out.append("trigger_l2_with_r2=" + v) }
        return out
    }

    static let xinputModes = ["off", "rumble", "pad"]

    static func number(_ v: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), v) }

    /// In words, for the list: what these options change.
    var summary: [String] {
        var out: [String] = []
        if let v = bluetoothAsCable { out.append(v ? "Bluetooth as a cable" : "Bluetooth as it is") }
        if let v = fullMotorPower { out.append(v ? "full motor power" : "the game's motor power") }
        if let v = edgeAsDualSense { out.append(v ? "Edge shown as a DualSense" : "Edge shown as an Edge") }
        if let v = hapticsGainCable { out.append("DualSense haptics \(PadOptions.times(v)) on a cable") }
        if let v = edgeHapticsGainCable { out.append("Edge haptics \(PadOptions.times(v)) on a cable") }
        if let v = hapticsGainBluetooth { out.append("DualSense haptics \(PadOptions.times(v)) over Bluetooth") }
        if let v = edgeHapticsGainBluetooth { out.append("Edge haptics \(PadOptions.times(v)) over Bluetooth") }
        if let v = xinput { out.append(v == "pad" ? "an XInput controller" : v == "rumble" ? "XInput's rumble" : "no XInput") }
        if let v = rumbleHaptics { out.append(v ? "rumble on the actuators" : "rumble on the motors") }
        if let v = triggerR2, let t = PadTrigger(v) { out.append("R2 \(t.words)") }
        if let v = triggerL2, let t = PadTrigger(v) { out.append("L2 \(t.words)") }
        if let v = triggerR2WithL2, let t = PadTrigger(v), t.effect != "off" { out.append("R2 \(t.words) while L2 is pressed") }
        if let v = triggerL2WithR2, let t = PadTrigger(v), t.effect != "off" { out.append("L2 \(t.words) while R2 is pressed") }
        return out
    }

    static func times(_ v: Double) -> String {
        (v.rounded() == v ? String(Int(v)) : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), v)) + "×"
    }
}

extension PadOptions {
    private enum CodingKeys: String, CodingKey {
        case bluetoothAsCable, fullMotorPower, edgeAsDualSense
        case hapticsGainCable, edgeHapticsGainCable, hapticsGainBluetooth, edgeHapticsGainBluetooth
        case xinput, rumbleHaptics, triggerR2, triggerL2, triggerR2WithL2, triggerL2WithR2
        /// Before the three modes: XInput's rumble on or off.
        case xinputRumble
        /// Before the two connections had their own: one gain per pad, for both.
        case hapticsGain, edgeHapticsGain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let gain = try c.decodeIfPresent(Double.self, forKey: .hapticsGain)
        let edgeGain = try c.decodeIfPresent(Double.self, forKey: .edgeHapticsGain)
        self.init(bluetoothAsCable: try c.decodeIfPresent(Bool.self, forKey: .bluetoothAsCable),
                  fullMotorPower: try c.decodeIfPresent(Bool.self, forKey: .fullMotorPower),
                  edgeAsDualSense: try c.decodeIfPresent(Bool.self, forKey: .edgeAsDualSense),
                  hapticsGainCable: try c.decodeIfPresent(Double.self, forKey: .hapticsGainCable) ?? gain,
                  edgeHapticsGainCable: try c.decodeIfPresent(Double.self, forKey: .edgeHapticsGainCable) ?? edgeGain,
                  hapticsGainBluetooth: try c.decodeIfPresent(Double.self, forKey: .hapticsGainBluetooth) ?? gain,
                  edgeHapticsGainBluetooth: try c.decodeIfPresent(Double.self, forKey: .edgeHapticsGainBluetooth)
                      ?? edgeGain,
                  xinput: try c.decodeIfPresent(String.self, forKey: .xinput)
                      ?? (try c.decodeIfPresent(Bool.self, forKey: .xinputRumble)).map { $0 ? "rumble" : "off" },
                  rumbleHaptics: try c.decodeIfPresent(Bool.self, forKey: .rumbleHaptics),
                  triggerR2: try c.decodeIfPresent(String.self, forKey: .triggerR2),
                  triggerL2: try c.decodeIfPresent(String.self, forKey: .triggerL2),
                  triggerR2WithL2: try c.decodeIfPresent(String.self, forKey: .triggerR2WithL2),
                  triggerL2WithR2: try c.decodeIfPresent(String.self, forKey: .triggerL2WithR2))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(bluetoothAsCable, forKey: .bluetoothAsCable)
        try c.encodeIfPresent(fullMotorPower, forKey: .fullMotorPower)
        try c.encodeIfPresent(edgeAsDualSense, forKey: .edgeAsDualSense)
        try c.encodeIfPresent(hapticsGainCable, forKey: .hapticsGainCable)
        try c.encodeIfPresent(edgeHapticsGainCable, forKey: .edgeHapticsGainCable)
        try c.encodeIfPresent(hapticsGainBluetooth, forKey: .hapticsGainBluetooth)
        try c.encodeIfPresent(edgeHapticsGainBluetooth, forKey: .edgeHapticsGainBluetooth)
        try c.encodeIfPresent(xinput, forKey: .xinput)
        try c.encodeIfPresent(rumbleHaptics, forKey: .rumbleHaptics)
        try c.encodeIfPresent(triggerR2, forKey: .triggerR2)
        try c.encodeIfPresent(triggerL2, forKey: .triggerL2)
        try c.encodeIfPresent(triggerR2WithL2, forKey: .triggerR2WithL2)
        try c.encodeIfPresent(triggerL2WithR2, forKey: .triggerL2WithR2)
    }
}

/// A trigger effect as the modules read it: "off", or an effect with an
/// optional strength from 1 to 8, "weapon@6". The effects are the layouts
/// NotProton's controller bridge wrote (engine/patches 0006 says each).
struct PadTrigger: Equatable {
    static let effects = ["off", "resist", "weapon", "slope", "vibrate", "rumble", "recoil"]
    var effect: String
    /// 0 for the effect's own default.
    var strength: Int

    init(effect: String, strength: Int = 0) {
        self.effect = effect
        self.strength = effect == "off" ? 0 : strength
    }

    init?(_ spec: String) {
        let parts = spec.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 2, PadTrigger.effects.contains(parts[0]) else { return nil }
        var strength = 0
        if parts.count == 2 {
            guard parts[0] != "off", let n = Int(parts[1]), (1...8).contains(n) else { return nil }
            strength = n
        }
        self.init(effect: parts[0], strength: strength)
    }

    var spec: String { strength > 0 ? "\(effect)@\(strength)" : effect }

    var words: String {
        switch effect {
        case "off": return "free"
        case "rumble": return "rumbles with the motor" + (strength > 0 ? " up to \(strength)" : "")
        case "recoil": return "kicks back with the motor" + (strength > 0 ? " up to \(strength)" : "")
        default: return effect + (strength > 0 ? " at \(strength)" : "")
        }
    }
}

/// What the modules saw a game do, from their log.
enum PadSeen: String, Codable, CaseIterable, Comparable {
    case haptics, motors, xinput, triggers, power, bluetooth

    var label: String {
        switch self {
        case .haptics: return "haptics as audio"
        case .motors: return "rumble motors"
        case .xinput: return "rumble through XInput"
        case .triggers: return "trigger effects"
        case .power: return "sets the motor power"
        case .bluetooth: return "played over Bluetooth"
        }
    }

    static func < (a: PadSeen, b: PadSeen) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// The kind a log line says, if it says one.
    static func of(_ text: String) -> PadSeen? {
        if text.contains("observed: the game plays haptics on the Bluetooth") { return .haptics }
        if text.contains("observed: the game opens the wired") { return .haptics }
        if text.contains("observed: the game rumbles") && text.contains("through XInput") { return .xinput }
        if text.contains("observed: the game rumbles") { return .motors }
        if text.contains("observed: the game sets trigger effects") { return .triggers }
        if text.contains("observed: the game sets its own") { return .triggers }
        if text.contains("observed: the game claims the") { return .power }
        if text.contains("is shown as wired") { return .bluetooth }
        return nil
    }
}

/// A preset the app ships: options measured on a title.
struct PadPreset: Codable, Equatable {
    let title: String
    let options: PadOptions
    let measured: String
}

enum PadPresets {
    static func load(from bundle: URL? = Bundle.main.resourceURL) -> [String: PadPreset] {
        struct File: Codable { let games: [String: PadPreset] }
        guard let url = bundle?.appendingPathComponent("pad-presets.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return file.games
    }
}

/// One game the user has, or once had, options or observations for.
struct PadGame: Codable, Equatable {
    var name: String
    /// The user's own, over the preset.
    var options = PadOptions()
    /// When each thing was last seen.
    var seen: [PadSeen: Date] = [:]
    /// Whether Steam's store lists the game as supporting the DualSense
    /// (category 57); nil until asked. See PadStore.rule.
    var dualSense: Bool?
    /// The store was asked and knows no such app, so it is not asked again.
    var storeUnknown = false
    /// The modules' diagnostics for this game alone, for a report.
    var diagnose = false

    init(name: String) { self.name = name }

    var isEmpty: Bool { options.isEmpty && seen.isEmpty && dualSense == nil && !storeUnknown && !diagnose }

    private enum CodingKeys: String, CodingKey { case name, options, seen, dualSense, storeUnknown, diagnose }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        options = try c.decodeIfPresent(PadOptions.self, forKey: .options) ?? PadOptions()
        let raw = try c.decodeIfPresent([String: Date].self, forKey: .seen) ?? [:]
        seen = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in PadSeen(rawValue: k).map { ($0, v) } })
        dualSense = try c.decodeIfPresent(Bool.self, forKey: .dualSense)
        storeUnknown = try c.decodeIfPresent(Bool.self, forKey: .storeUnknown) ?? false
        diagnose = try c.decodeIfPresent(Bool.self, forKey: .diagnose) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        if !options.isEmpty { try c.encode(options, forKey: .options) }
        if !seen.isEmpty {
            try c.encode(Dictionary(uniqueKeysWithValues: seen.map { ($0.key.rawValue, $0.value) }), forKey: .seen)
        }
        try c.encodeIfPresent(dualSense, forKey: .dualSense)
        if storeUnknown { try c.encode(true, forKey: .storeUnknown) }
        if diagnose { try c.encode(true, forKey: .diagnose) }
    }
}

/// What Steam's store says of a game, from its public endpoint, or from a folder
/// of saved answers (<app id>.json) when MACGAMEFIX_STORE_DIR names one, for the
/// tests.
enum SteamStore {
    enum Answer { case yes, no, unknownApp }

    /// Whether the store lists the game as supporting the DualSense (category
    /// 57), or knows no such app; nil when it does not answer.
    static func dualSense(_ appid: String) async -> Answer? {
        guard appid.allSatisfy(\.isNumber) else { return .unknownApp }
        let data: Data
        if let dir = ProcessInfo.processInfo.environment["MACGAMEFIX_STORE_DIR"] {
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("\(appid).json"))
            else { return .unknownApp }
            data = d
        } else {
            guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appid)&filters=categories")
            else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            guard let (d, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            data = d
        }
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entry = top[appid] as? [String: Any] else { return nil }
        guard entry["success"] as? Bool == true else { return .unknownApp }
        let categories = ((entry["data"] as? [String: Any])?["categories"] as? [[String: Any]]) ?? []
        return categories.contains { ($0["id"] as? Int) == 57 } ? .yes : .no
    }
}

/// A Steam game on this Mac.
struct InstalledGame: Hashable, Identifiable {
    let appid: String
    let name: String
    var id: String { appid }
}

enum SteamGames {
    /// Steamworks' redistributables and such, which are not games.
    private static let notGames: Set<String> = ["228980"]

    /// Every app the Steam libraries hold, by its appmanifest, by name.
    static func installed(extra: [URL] = []) -> [InstalledGame] {
        var found: [String: InstalledGame] = [:]
        for common in Libraries.all(extra: extra) {
            let steamapps = common.deletingLastPathComponent()
            let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let fields = manifest(text)
                guard let appid = fields["appid"], let name = fields["name"], !notGames.contains(appid) else { continue }
                found[appid] = InstalledGame(appid: appid, name: name)
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The top-level "key" "value" pairs of an appmanifest.
    static func manifest(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 5 else { continue }
            let key = String(parts[1]).lowercased()
            if fields[key] == nil { fields[key] = String(parts[3]) }
        }
        return fields
    }
}

/// Everything the Game Feel tab keeps, in pad.json.
struct PadStore: Codable, Equatable {
    var defaults = PadOptions.firstRun
    /// The modules add what a game writes to the pad, and a level meter, to their log.
    var diagnostics = false
    var games: [String: PadGame] = [:]
    /// How far the modules' log has been read, and which log that was.
    var logRead: UInt64 = 0
    var logInode: UInt64 = 0

    static var file: URL { Paths.support.appendingPathComponent("pad.json") }
    static var config: URL { Paths.support.appendingPathComponent("pad.conf") }
    static var perGame: URL { Paths.support.appendingPathComponent("pad.d") }
    /// The modules' log, beside the pads' sockets.
    static var log: URL {
        if let path = ProcessInfo.processInfo.environment["MACGAMEFIX_PAD_LOG"] { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: "/tmp/macgamefix-\(getuid())/pad.log")
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaults = try c.decodeIfPresent(PadOptions.self, forKey: .defaults)?.over(.firstRun) ?? .firstRun
        diagnostics = try c.decodeIfPresent(Bool.self, forKey: .diagnostics) ?? false
        games = try c.decodeIfPresent([String: PadGame].self, forKey: .games) ?? [:]
        logRead = try c.decodeIfPresent(UInt64.self, forKey: .logRead) ?? 0
        logInode = try c.decodeIfPresent(UInt64.self, forKey: .logInode) ?? 0
    }

    static func load() -> PadStore {
        guard let data = try? Data(contentsOf: file),
              let store = try? JSONDecoder().decode(PadStore.self, from: data) else { return PadStore() }
        return store
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) { try? data.write(to: PadStore.file, options: .atomic) }
    }

    /// What a game gets without options of its own: its preset, over what the
    /// store says of it, over every game's. A game the store does not list as
    /// supporting the DualSense reads XInput, and gets the pad as an XInput
    /// controller; one it does list speaks Sony and keeps every game's (XInput's
    /// rumble on the motors). A preset is a measured exception.
    func base(_ appid: String, presets: [String: PadPreset]) -> PadOptions {
        (presets[appid]?.options ?? PadOptions()).over(PadStore.rule(games[appid]?.dualSense)).over(defaults)
    }

    static func rule(_ dualSense: Bool?) -> PadOptions {
        dualSense == false ? PadOptions(xinput: "pad") : PadOptions()
    }

    /// What a game gets: its own options over its base.
    func effective(_ appid: String, presets: [String: PadPreset]) -> PadOptions {
        (games[appid]?.options ?? PadOptions()).over(base(appid, presets: presets))
    }

    /// Asks the store about each installed game it has not answered for yet.
    /// Returns whether anything was learned.
    mutating func learnStore(_ installed: [InstalledGame]) async -> Bool {
        var learned = false
        for game in installed where games[game.appid]?.dualSense == nil && games[game.appid]?.storeUnknown != true {
            // No answer: the network is down or the store is busy; ask again next time.
            guard let answer = await SteamStore.dualSense(game.appid) else { break }
            var entry = games[game.appid] ?? PadGame(name: game.name)
            if answer == .unknownApp { entry.storeUnknown = true } else { entry.dualSense = answer == .yes }
            games[game.appid] = entry
            learned = true
        }
        return learned
    }

    /// pad.conf for every game, and pad.d/<app id>.conf for each game whose
    /// options differ from every game's; a file no game needs any more goes.
    func writeConfig(presets: [String: PadPreset]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: PadStore.perGame, withIntermediateDirectories: true)
        let header = "# Written by MacGameFix (Game Feel); read by its Wine modules. Edit it there.\n"
        let common = defaults.lines + (diagnostics ? ["diagnostics=on"] : [])
        try? (header + common.joined(separator: "\n") + "\n").write(to: PadStore.config, atomically: true, encoding: .utf8)
        var wanted: Set<String> = []
        for appid in Set(games.keys).union(presets.keys) {
            let own = effective(appid, presets: presets).differences(from: defaults)
            let diagnose = games[appid]?.diagnose == true && !diagnostics
            guard !own.isEmpty || diagnose else { continue }
            let name = games[appid]?.name ?? presets[appid]?.title ?? appid
            let text = header + "# \(name)\n" + (own.lines + (diagnose ? ["diagnostics=on"] : [])).joined(separator: "\n") + "\n"
            try? text.write(to: PadStore.perGame.appendingPathComponent("\(appid).conf"), atomically: true, encoding: .utf8)
            wanted.insert("\(appid).conf")
        }
        for file in (try? fm.contentsOfDirectory(atPath: PadStore.perGame.path)) ?? []
        where file.hasSuffix(".conf") && !wanted.contains(file) {
            try? fm.removeItem(at: PadStore.perGame.appendingPathComponent(file))
        }
    }

    /// Reads what the modules logged since the last read: which game did what.
    /// Returns whether anything new was learned. Lines name the game as
    /// game=<app id>; a line without one says nothing about a game.
    @discardableResult
    mutating func absorbLog(names lookup: () -> [String: String] = { [:] }, now: Date = Date()) -> Bool {
        let path = PadStore.log.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        // A new log (after a restart, /tmp is emptied) or a shorter one starts over.
        if inode != logInode || size < logRead { logRead = 0; logInode = inode }
        guard size > logRead else { return false }
        try? handle.seek(toOffset: logRead)
        let data = handle.readDataToEndOfFile()
        // Only whole lines; the rest is read next time.
        guard let last = data.lastIndex(of: 0x0A) else { return false }
        logRead += UInt64(last + 1)
        var learned = false
        var names: [String: String]?
        for line in String(decoding: data[..<last], as: UTF8.self).split(separator: "\n") {
            guard let range = line.range(of: " game="), let kind = PadSeen.of(String(line)) else { continue }
            let appid = String(line[range.upperBound...].prefix { $0.isNumber })
            guard !appid.isEmpty else { continue }
            if games[appid] == nil || games[appid]?.name == appid, names == nil { names = lookup() }
            var game = games[appid] ?? PadGame(name: names?[appid] ?? appid)
            if game.name == appid, let name = names?[appid] { game.name = name }
            game.seen[kind] = now
            games[appid] = game
            learned = true
        }
        return learned
    }

    /// What can be shared: each game the user set apart or the modules saw, by
    /// app id and name, with the options it plays with and what it was seen to do.
    /// Nothing of this Mac's paths or accounts.
    func export(presets: [String: PadPreset], now: Date = Date()) -> Data {
        struct Entry: Codable {
            let appid: String
            let name: String
            let options: PadOptions
            let seen: [PadSeen]
            let preset: String?
        }
        struct File: Codable {
            let format: String
            let version: Int
            let exported: Date
            let every: PadOptions
            let games: [Entry]
        }
        let entries = games.keys.sorted().compactMap { appid -> Entry? in
            guard let game = games[appid] else { return nil }
            let own = effective(appid, presets: presets).differences(from: defaults)
            guard !own.isEmpty || !game.seen.isEmpty else { return nil }
            return Entry(appid: appid, name: game.name, options: own, seen: game.seen.keys.sorted(),
                         preset: presets[appid]?.measured)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(File(format: "macgamefix-pad", version: 1, exported: now, every: defaults,
                                         games: entries))) ?? Data()
    }
}

// MARK: - A report for an issue

extension PadStore {
    /// One game's report, for an issue: MacGameFix and macOS, the game and what
    /// the store says of it, the Wine modules in each CrossOver by name, the
    /// settings it gets, and what the modules logged for it. The home folder is
    /// written ~, and nothing names another game.
    func report(appid: String, name: String, presets: [String: PadPreset],
                engines: [(name: String, build: String, state: String)], now: Date = Date()) -> String {
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
        let stamp = ISO8601DateFormatter().string(from: now)
        var out = "# MacGameFix report: \(name)\n\n"
        out += "- Made: \(stamp)\n"
        out += "- MacGameFix \(Catalog.appVersion); macOS \(ProcessInfo.processInfo.operatingSystemVersionString); "
            + "\(shell(["/usr/sbin/sysctl", "-n", "hw.model"]))\n"
        out += "- Game: \(name), Steam app \(appid)\n"
        switch games[appid]?.dualSense {
        case true?: out += "- Steam store: lists the DualSense (category 57)\n"
        case false?: out += "- Steam store: does not list the DualSense\n"
        case nil: out += "- Steam store: not asked\n"
        }
        let seen = (games[appid]?.seen.keys.sorted() ?? []).map(\.label)
        if !seen.isEmpty { out += "- Seen: " + seen.joined(separator: ", ") + "\n" }
        out += "\n## Wine modules\n\n"
        out += engines.isEmpty ? "None found.\n" : engines.map { "- \($0.name) (\($0.build)): \($0.state)" }.joined(separator: "\n") + "\n"
        out += "\n## Settings\n\nEvery game:\n\n```\n" + defaults.lines.joined(separator: "\n") + "\n```\n\n"
        let own = effective(appid, presets: presets).differences(from: defaults).lines
        out += "This game's own, suggested or by the store's rule:\n\n```\n"
            + (own.isEmpty ? "(none)" : own.joined(separator: "\n")) + "\n```\n"
        let log = (try? String(contentsOf: PadStore.log, encoding: .utf8)) ?? ""
        var lines = log.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            .filter { $0.contains(" game=\(appid) ") }
        var note = ""
        if lines.isEmpty {
            // A CrossOver bottle gives the modules no game id: the latest lines without one.
            lines = log.split(separator: "\n").map(String.init).filter { $0.contains(" game=- ") }
            note = "No line names this game (a CrossOver bottle gives none): the latest lines without a game.\n\n"
        }
        out += "\n## The modules' log\n\n" + note + "```\n" + lines.suffix(600).joined(separator: "\n") + "\n```\n"
        for home in [Paths.home.path, NSHomeDirectory()] where home.count > 1 {
            out = out.replacingOccurrences(of: home, with: "~")
        }
        return out
    }
}
