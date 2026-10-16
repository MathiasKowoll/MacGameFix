// MacGameFix in the menu bar: the agent with a face. The LaunchAgent starts
// this binary with --agent at login; that process keeps the marked fixes
// applied (Automation.swift) and shows, from a menu bar item, a summary of
// them: how many are in place, to review or left alone. Which games,
// and why, is in the window. The window stays its own process of the
// same app, opened from the menu, so closing it never stops the agent.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// What the agent knows of one game marked "Keep it applied". The menu counts
/// these; the window shows them.
struct KeptLine: Equatable {
    var key: String
    var name: String
    var word: String
    /// The verdict, the failure, or the folder that is gone.
    var detail: String?
    var report: String?

    enum Condition: CaseIterable { case inPlace, review, leftAlone, waiting }

    var condition: Condition {
        switch word {
        case "In place": return .inPlace
        case "Failed", "Folder not found": return .review
        case "Not applied": return .leftAlone
        default: return .waiting
        }
    }

    /// The user has something to see or do about this game.
    var needsUser: Bool { condition == .review || condition == .leftAlone }

    static func all(settings: AutoSettings, state: AgentState) -> [KeptLine] {
        settings.kept.map { kept in
            func line(_ word: String, _ detail: String? = nil, _ report: String? = nil) -> KeptLine {
                KeptLine(key: kept.key, name: kept.name, word: word, detail: detail, report: report)
            }
            guard FileManager.default.fileExists(atPath: kept.folder) else { return line("Folder not found", kept.folder) }
            guard let memory = state.games[kept.key], !memory.fit.isEmpty || !memory.state.isEmpty else {
                return line("Not looked at yet")
            }
            if !memory.fit.isEmpty && memory.fit != Fit.fits.label { return line("Not applied", memory.fit) }
            switch memory.state {
            case "installed": return line("In place")
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
            case .leftAlone: return Group(condition: condition, text: "\(n) left alone: the fix does not fit",
                                          symbol: "minus.circle")
            case .waiting: return Group(condition: condition, text: "\(n) not looked at yet", symbol: "clock")
            }
        }
    }
}

@MainActor
final class MenuBarAgent: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    private var looking = false
    private var lastLook: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            MainActor.assumeIsolated { self.look() }
        }
        look()
    }

    /// Opening the app while the agent runs lands here: the window opens.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return false
    }

    /// A pass of the agent. `everything` looks at every marked game even when
    /// Steam has not changed it; `updates` asks the releases for new fixes now.
    func look(everything: Bool = false, updates: Bool = false) {
        guard !looking else { return }
        looking = true
        Task {
            let events = await Agent.pass(notify: true, everything: everything, updateNow: updates)
            for e in events { print("\(e.date) \(e.game): \(e.message)") }
            if updates { Notifier.post(AgentEvent(date: Date(), game: "", message: AgentState.load().lastUpdate, failed: false)) }
            lastLook = Date()
            looking = false
            refreshIcon()
        }
    }

    /// The raccoon, with a dot while something the agent did asks for a look
    /// and the window has not been opened since.
    private func refreshIcon() {
        let news = AgentState.load().news(since: AutoSettings.load().seen)
        item?.button?.image = RaccoonIcon.image(dot: news)
        item?.button?.setAccessibilityLabel(news ? "MacGameFix: something new to look at" : "MacGameFix")
    }

    // MARK: The menu, built fresh each time it opens

    /// A summary, however many games are marked: how many are in place, to
    /// review, left alone or waiting for a first look. The games
    /// themselves are in the window.
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
                let row = group.condition == .review || group.condition == .leftAlone
                    ? action(group.text + "…", #selector(openReview))
                    : note(group.text)
                row.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: nil)
                row.indentationLevel = 1
                menu.addItem(row)
            }
        }
        if looking {
            menu.addItem(note("Looking at the games…"))
        } else if let lastLook {
            menu.addItem(note("Last look: " + lastLook.formatted(date: .omitted, time: .shortened)))
        }

        menu.addItem(.separator())
        let catalog = Catalog.active().manifest?.version ?? 0
        menu.addItem(note(state.lastUpdate.isEmpty ? "Fixes catalog \(catalog)" : state.lastUpdate))
        let lookNow = action("Look at the Games Now", #selector(lookNow))
        let check = action("Check for New Fixes", #selector(checkNow))
        lookNow.isEnabled = !looking && !lines.isEmpty
        check.isEnabled = !looking
        menu.addItem(lookNow)
        menu.addItem(check)
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
    @objc private func openWindowItem() { openWindow() }
    @objc private func openReview() { openWindow(review: true) }
    @objc private func quit() { NSApp.terminate(nil) }

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
/// A dot by the ear says there is something new to look at.
enum RaccoonIcon {
    static func image(dot: Bool) -> NSImage {
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
