// MacGameFix in the menu bar: the agent with a face. The LaunchAgent starts
// this binary with --agent at login; that process keeps the marked fixes
// applied (Automation.swift) and shows, from a menu bar item, a summary of
// them: how many are in place or to review. Which games,
// and why, is in the window. The window stays its own process of the
// same app, opened from the menu, so closing it never stops the agent.
// Beside the raccoon it also shows the battery of a connected controller,
// the lowest of them, and the menu lists each one.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GameController

/// What the agent knows of one game marked "Keep it applied". The menu counts
/// these; the window shows them.
struct KeptLine: Equatable {
    var key: String
    var name: String
    var word: String
    /// The verdict, the failure, or the folder that is gone.
    var detail: String?
    var report: String?

    enum Condition: CaseIterable { case inPlace, review, recipe, waiting }

    var condition: Condition {
        switch word {
        case "In place": return .inPlace
        case "Failed", "Folder not found", "Cannot be installed here": return .review
        case "Waiting for a recipe": return .recipe
        default: return .waiting
        }
    }

    /// The user has something to see or do about this game.
    var needsUser: Bool { condition == .review }

    static func all(settings: AutoSettings, state: AgentState) -> [KeptLine] {
        settings.kept.map { kept in
            func line(_ word: String, _ detail: String? = nil, _ report: String? = nil) -> KeptLine {
                KeptLine(key: kept.key, name: kept.name, word: word, detail: detail, report: report)
            }
            guard FileManager.default.fileExists(atPath: kept.folder) else { return line("Folder not found", kept.folder) }
            guard let memory = state.games[kept.key], !memory.state.isEmpty else { return line("Not looked at yet") }
            switch memory.state {
            case "installed": return line("In place")
            // A fix made for each build of the game, with none for this build
            // yet: nothing for the user to do, and a catalog update ends it.
            case "norecipe": return line("Waiting for a recipe")
            // A fix for a macOS game's app its installer will not install here:
            // the user has to act (Steam's verify, or Keep off), so it is to
            // review, with the installer's reason, but nothing failed.
            case "blocked":
                let last = state.events.last { $0.game == kept.name && !$0.failed }
                return line("Cannot be installed here", last?.message)
            case "failed":
                let last = state.events.last { $0.game == kept.name && $0.failed }
                return line("Failed", last?.message, last?.report)
            default: return line("Not looked at yet")
            }
        }
    }

    /// One line of the menu's summary: how many games are in one condition.
    struct Group: Equatable {
        var condition: Condition
        var text: String
        var symbol: String
    }

    /// The menu's summary, in this order, leaving out what no game is in.
    static func summary(_ lines: [KeptLine]) -> [Group] {
        Condition.allCases.compactMap { condition in
            let n = lines.filter { $0.condition == condition }.count
            guard n > 0 else { return nil }
            switch condition {
            case .inPlace: return Group(condition: condition, text: "\(n) in place", symbol: "checkmark.circle")
            case .review: return Group(condition: condition, text: "\(n) to review", symbol: "eye")
            case .recipe: return Group(condition: condition, text: "\(n) waiting for a recipe", symbol: "hourglass")
            case .waiting: return Group(condition: condition, text: "\(n) not looked at yet", symbol: "clock")
            }
        }
    }
}

@MainActor
final class MenuBarAgent: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    private var batteryTimer: Timer?
    private var looking = false
    private var lastLook: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        self.item = item
        refreshIcon()
        // The window says when the user has looked.
        DistributedNotificationCenter.default().addObserver(forName: Model.seenNotification, object: nil,
                                                            queue: .main) { _ in
            MainActor.assumeIsolated { self.refreshIcon() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Model.settingsNotification, object: nil,
                                                            queue: .main) { _ in
            MainActor.assumeIsolated { self.batterySetting() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            MainActor.assumeIsolated { self.look() }
        }
        batterySetting()
        look()
    }

    /// A pad's battery beside the raccoon, while the setting says so: on
    /// connecting and leaving, and every minute. Off, the controllers are not
    /// asked at all.
    private func batterySetting() {
        if AutoSettings.load().padBattery {
            PadBattery.start { MainActor.assumeIsolated { self.refreshIcon() } }
            if batteryTimer == nil {
                batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                    MainActor.assumeIsolated { self.refreshIcon() }
                }
            }
        } else {
            batteryTimer?.invalidate()
            batteryTimer = nil
        }
        refreshIcon()
    }

    /// Opening the app while the agent runs lands here: the window opens.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return false
    }

    /// A pass of the agent. `everything` looks at every marked game even when
    /// Steam has not changed it; `updates` asks the releases for new fixes now.
    func look(everything: Bool = false, updates: Bool = false, modules: Bool = false) {
        guard !looking else { return }
        looking = true
        Task {
            let events = await Agent.pass(notify: true, everything: everything, updateNow: updates, modulesNow: modules)
            for e in events { print("\(e.date) \(e.game): \(e.message)") }
            if updates { Notifier.post(AgentEvent(date: Date(), game: "", message: AgentState.load().lastUpdate, failed: false)) }
            if modules {
                Notifier.post(AgentEvent(date: Date(), game: "", message: AgentState.load().lastModulesUpdate, failed: false))
            }
            lastLook = Date()
            looking = false
            refreshIcon()
        }
    }

    /// The raccoon, with a dot while something the agent did asks for a look
    /// and the window has not been opened since.
    private func refreshIcon() {
        let settings = AutoSettings.load()
        let news = AgentState.load().news(since: settings.seen)
        let lowest = batteryTimer == nil ? nil : PadBattery.readings().min { $0.level < $1.level }
        // The battery's icon as the settings say; with no pad, the gamepad stays
        // if it was chosen and anything else shows the raccoon, so the item is there.
        switch (settings.padBattery ? settings.batteryIcon : "raccoon", lowest) {
        case ("gamepad", let pad):
            item?.button?.image = RaccoonIcon.gamepad(dot: news)
            item?.button?.title = pad.map { " \($0.level)%" } ?? ""
        case ("none", let pad?):
            item?.button?.image = nil
            item?.button?.title = (news ? "• " : "") + "\(pad.level)%"
        case (_, let pad):
            item?.button?.image = RaccoonIcon.image(dot: news, pad: pad != nil)
            item?.button?.title = pad.map { " \($0.level)%" } ?? ""
        }
        item?.button?.imagePosition = .imageLeading
        item?.button?.setAccessibilityLabel((news ? "MacGameFix: something new to look at" : "MacGameFix")
            + (lowest.map { ", \($0.name) battery \($0.level) percent" } ?? ""))
    }

    // MARK: The menu, built fresh each time it opens

    /// A summary, however many games are marked: how many are in place, to
    /// review, waiting for a recipe for a new game build, or waiting for a first
    /// look. The games themselves are in the window.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = AgentState.load()
        let lines = KeptLine.all(settings: .load(), state: state)

        menu.addItem(note("MacGameFix", bold: true))
        if lines.isEmpty {
            menu.addItem(note("No game is marked “Keep it applied”."))
        } else {
            menu.addItem(note(lines.count == 1 ? "Keeping 1 fix applied" : "Keeping \(lines.count) fixes applied"))
            for group in KeptLine.summary(lines) {
                let row = group.condition == .review
                    ? action(group.text + "…", #selector(openReview))
                    : note(group.text)
                row.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: nil)
                row.indentationLevel = 1
                menu.addItem(row)
            }
        }
        let pads = batteryTimer == nil ? [] : PadBattery.readings()
        if !pads.isEmpty {
            menu.addItem(.separator())
            for pad in pads {
                let row = note("\(pad.name): \(pad.level)%" + (pad.state.isEmpty ? "" : ", \(pad.state)"))
                row.image = NSImage(systemSymbolName: pad.symbol, accessibilityDescription: nil)
                menu.addItem(row)
            }
            refreshIcon()
            menu.addItem(.separator())
        }
        if looking {
            menu.addItem(note("Looking at the games…"))
        } else if let lastLook {
            menu.addItem(note("Last look: " + lastLook.formatted(date: .omitted, time: .shortened)))
        }

        menu.addItem(.separator())
        let catalog = Catalog.active().manifest?.version ?? 0
        menu.addItem(note(state.lastUpdate.isEmpty ? "Fixes catalog \(catalog)" : state.lastUpdate))
        if !state.lastModulesUpdate.isEmpty { menu.addItem(note(state.lastModulesUpdate)) }
        let lookNow = action("Look at the Games Now", #selector(lookNow))
        // Asked first: the catalog the agent verified waits for this.
        let check = action(state.waiting.map { "Install New Fixes (catalog \($0))" } ?? "Check for New Fixes",
                           #selector(checkNow))
        lookNow.isEnabled = !looking && !lines.isEmpty
        check.isEnabled = !looking
        menu.addItem(lookNow)
        menu.addItem(check)
        // Asked first, the Wine modules' catalog waits on its own.
        if let waiting = state.waitingModules {
            let modules = action("Install New Wine Modules (catalog \(waiting))", #selector(modulesNow))
            modules.isEnabled = !looking
            menu.addItem(modules)
        }
        menu.addItem(action("Open MacGameFix…", #selector(openWindowItem)))
        menu.addItem(.separator())
        menu.addItem(action("Quit MacGameFix", #selector(quit)))
    }

    private func note(_ text: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        if bold {
            item.attributedTitle = NSAttributedString(string: text,
                                                      attributes: [.font: NSFont.menuFont(ofSize: 0).withBold()])
        }
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func lookNow() { look(everything: true) }
    @objc private func checkNow() { look(updates: true) }
    @objc private func modulesNow() { look(modules: true) }
    @objc private func openWindowItem() { openWindow() }
    @objc private func openReview() { openWindow(review: true) }
    /// Quitting from the menu bar quits the app: the window, its own process of
    /// this bundle, is asked to quit too (one that is installing finishes first).
    @objc private func quit() {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app.processIdentifier != me {
            app.terminate()
        }
        NSApp.terminate(nil)
    }

    /// The window is the app run plainly: a second process of this bundle,
    /// unless one is already open. `review` opens it on the marked games that
    /// need the user.
    func openWindow(review: Bool = false) {
        let me = ProcessInfo.processInfo.processIdentifier
        if let open = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != me && $0.activationPolicy == .regular }) {
            open.activate()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = review ? ["--review"] : []
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
    }
}

/// RaccoonBot's raccoon, kept from the app MacGameFix grew out of: the same
/// shapes as its logo, in one colour for the menu bar. The mask is darkest, the
/// head and ears lighter, the lower face lightest, and the eyes are cut out.
/// A dot by the ear says there is something new to look at, and a gamepad
/// beside it that the percentage after it is a controller's battery.
enum RaccoonIcon {
    static func image(dot: Bool, pad: Bool = false) -> NSImage {
        let raccoon = image(dot: dot)
        guard pad, let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) else { return raccoon }
        let gap: CGFloat = 4, size = symbol.size
        let image = NSImage(size: NSSize(width: 18 + gap + size.width, height: 18), flipped: false) { _ in
            raccoon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            symbol.draw(in: NSRect(x: 18 + gap, y: (18 - size.height) / 2, width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The gamepad alone, with the dot by its top corner when something is new.
    static func gamepad(dot: Bool) -> NSImage {
        guard let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) else {
            return image(dot: dot)
        }
        let size = symbol.size
        let image = NSImage(size: NSSize(width: size.width + (dot ? 4 : 0), height: 18), flipped: false) { _ in
            symbol.draw(in: NSRect(x: 0, y: (18 - size.height) / 2, width: size.width, height: size.height))
            if dot {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: size.width - 1, y: 12, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func image(dot: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // The logo's shapes span x -78...78 and y -107...66, about its centre.
            let scale: CGFloat = 17.6 / 173
            ctx.translateBy(x: 9, y: 0.2 + 107 * scale)
            ctx.scaleBy(x: scale, y: scale)
            draw(ctx, dot: dot)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ ctx: CGContext, dot: Bool) {
        func shape(_ build: (CGMutablePath) -> Void) -> CGPath {
            let p = CGMutablePath()
            build(p)
            p.closeSubpath()
            return p
        }
        func mirrored(_ p: CGPath) -> CGPath {
            var flip = CGAffineTransform(scaleX: -1, y: 1)
            return p.copy(using: &flip) ?? p
        }
        func fill(_ p: CGPath, _ alpha: CGFloat) {
            ctx.setBlendMode(.normal)
            ctx.setFillColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            ctx.addPath(p)
            ctx.fillPath()
        }
        func cut(_ p: CGPath, _ amount: CGFloat = 1) {
            ctx.setBlendMode(.destinationOut)
            ctx.setFillColor(NSColor.black.withAlphaComponent(amount).cgColor)
            ctx.addPath(p)
            ctx.fillPath()
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil)
        }
        let ear = shape { $0.move(to: CGPoint(x: -78, y: -52)); $0.addLine(to: CGPoint(x: -58, y: -96))
                          $0.addLine(to: CGPoint(x: -26, y: -66)) }
        let innerEar = shape { $0.move(to: CGPoint(x: -70, y: -58)); $0.addLine(to: CGPoint(x: -57, y: -86))
                               $0.addLine(to: CGPoint(x: -37, y: -68)) }
        let face = shape {
            $0.move(to: CGPoint(x: 0, y: -78))
            $0.addCurve(to: CGPoint(x: 78, y: -8), control1: CGPoint(x: 52, y: -78), control2: CGPoint(x: 78, y: -44))
            $0.addCurve(to: CGPoint(x: 0, y: 66), control1: CGPoint(x: 78, y: 40), control2: CGPoint(x: 44, y: 66))
            $0.addCurve(to: CGPoint(x: -78, y: -8), control1: CGPoint(x: -44, y: 66), control2: CGPoint(x: -78, y: 40))
            $0.addCurve(to: CGPoint(x: 0, y: -78), control1: CGPoint(x: -78, y: -44), control2: CGPoint(x: -52, y: -78))
        }
        let top = shape {
            $0.move(to: CGPoint(x: 0, y: -78))
            $0.addCurve(to: CGPoint(x: 78, y: -8), control1: CGPoint(x: 52, y: -78), control2: CGPoint(x: 78, y: -44))
            $0.addLine(to: CGPoint(x: -78, y: -8))
            $0.addCurve(to: CGPoint(x: 0, y: -78), control1: CGPoint(x: -78, y: -44), control2: CGPoint(x: -52, y: -78))
        }
        let mask = shape {
            $0.move(to: CGPoint(x: -78, y: -8))
            $0.addCurve(to: CGPoint(x: -30, y: -16), control1: CGPoint(x: -70, y: -30), control2: CGPoint(x: -44, y: -34))
            $0.addCurve(to: CGPoint(x: -52, y: 8), control1: CGPoint(x: -22, y: -4), control2: CGPoint(x: -34, y: 8))
            $0.addCurve(to: CGPoint(x: -78, y: -8), control1: CGPoint(x: -68, y: 8), control2: CGPoint(x: -76, y: 2))
        }

        fill(face, 0.35)
        fill(top, 0.7)
        for p in [ear, mirrored(ear)] { fill(p, 0.7) }
        for p in [innerEar, mirrored(innerEar)] { cut(p, 0.6) }
        for p in [mask, mirrored(mask)] { fill(p, 1) }
        for x: CGFloat in [-40, 40] { fill(circle(x, -12, 15), 1); cut(circle(x, -12, 7)) }
        fill(CGPath(roundedRect: CGRect(x: -6, y: -96, width: 12, height: 18), cornerWidth: 5, cornerHeight: 5,
                    transform: nil), 0.7)
        fill(circle(0, -100, 7), 1)
        fill(CGPath(ellipseIn: CGRect(x: -12, y: 13, width: 24, height: 18), transform: nil), 1)
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: -16, y: 40))
        mouth.addCurve(to: CGPoint(x: 16, y: 40), control1: CGPoint(x: -8, y: 52), control2: CGPoint(x: 8, y: 52))
        fill(mouth.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 10), 1)
        if dot {
            cut(circle(74, -94, 21))
            fill(circle(74, -94, 14), 1)
        }
    }
}

private extension NSFont {
    func withBold() -> NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}

/// The batteries of the connected controllers, as macOS's GameController
/// reports them for a DualSense, a DualSense Edge or any pad that says.
@MainActor
enum PadBattery {
    struct Reading {
        let name: String
        let level: Int
        /// "charging" or "charged"; empty while it runs on its battery.
        let state: String
        let symbol: String
    }

    private static var started = false

    static func start(onChange: @escaping @Sendable () -> Void) {
        guard !started else { return }
        started = true
        // Without it a process with no window in front sees no controller at all.
        GCController.shouldMonitorBackgroundEvents = true
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in onChange() }
        }
    }

    static func readings() -> [Reading] {
        GCController.controllers().compactMap { pad in
            guard let battery = pad.battery, battery.batteryState != .unknown else { return nil }
            let level = Int((battery.batteryLevel * 100).rounded())
            let name = (pad.vendorName ?? pad.productCategory).replacingOccurrences(of: " Wireless Controller", with: "")
            let charging = battery.batteryState == .charging, full = battery.batteryState == .full
            let step = level >= 88 ? "100" : level >= 63 ? "75" : level >= 38 ? "50" : level >= 13 ? "25" : "0"
            return Reading(name: name, level: level, state: charging ? "charging" : full ? "charged" : "",
                           symbol: charging ? "battery.100percent.bolt" : "battery.\(step)percent")
        }
    }
}
