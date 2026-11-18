// MacGameFix updating itself.
//
// The catalogs reach an installed app on their own (Automation.swift). The app
// did not: somebody on an older one never learned there was a newer, and what a
// new app brings (a tab, an option, a fix the old one cannot install) stayed
// unseen. This asks whether there is a newer MacGameFix, and puts it in this
// one's place when the user says so.
//
// WHO IS ASKED. MacGameFix's site, which keeps a table of the versions and where
// each one's zip is on GitHub; and GitHub's API when the site does not answer,
// or while this build knows no address for it. GitHub's API gives an address
// without an account 60 answers an hour, which is why it is the second.
//
// WHAT IS TRUSTED. Neither of them, nor the checksum either gives: they say
// where a zip is, and a wrong answer must end in a refusal here, not in an
// installed app. The downloaded app must carry a valid
// signature with this app's own identifier and this app's own team's Developer
// ID (the team is read from the running app, so a build somebody else signs
// takes only that somebody's builds), and its version must be the one offered
// and newer than this one, so an older MacGameFix is never put back. An ad hoc
// build has no team to ask for and never replaces itself: it is told there is a
// newer one and where.
//
// HOW IT IS PUT IN PLACE. The zip is unpacked beside nothing the user sees, in
// the folder macOS gives for replacing an item on the app's own volume. Nothing
// is changed until the user asks for the relaunch: then the running app is
// moved out, the new one moved in (back again if that fails), the agent started
// from the new one, and the window opened again once this process has ended.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CryptoKit
import Foundation
import Security

enum AppUpdate {
    /// A newer MacGameFix in the releases.
    struct Offer: Equatable {
        let version: String
        let zip: URL
        /// The zip's SHA-256 as the site gives it, or where the release's
        /// MacGameFix-<version>.zip.sha256 is: with either, a damaged download is
        /// told apart from an app that is not MacGameFix's.
        var sha256: String? = nil
        var sha256File: URL? = nil
        /// The release's page: its notes, and the app for whoever takes it by hand.
        let page: URL?
    }

    /// A downloaded app that passed every check, waiting to take this one's place.
    struct Ready {
        let version: String
        let app: URL
        let staging: URL
    }

    enum Failure: LocalizedError {
        case place(String), damaged, contents, signature(String), version(String, String), system(String)
        var errorDescription: String? {
            switch self {
            case .place(let why): return why
            case .damaged: return "the download does not match the release's checksum"
            case .contents: return "the download does not hold one app"
            case .signature(let why): return "the download is not signed as MacGameFix is: \(why)"
            case .version(let got, let want): return "the download is MacGameFix \(got), not \(want)"
            case .system(let v): return "the new MacGameFix needs macOS \(v) or later"
            }
        }
    }

    /// The latest release that is not a pre-release, whatever release this build
    /// takes its catalogs from: a pre-release build learns of the final one here.
    static let latest = URL(string: "https://api.github.com/repos/MathiasKowoll/MacGameFix/releases/latest")!

    /// Where to look: GitHub, unless the tests name a folder holding release.json,
    /// written as GitHub's API writes a release.
    static var source: URL {
        ProcessInfo.processInfo.environment["MACGAMEFIX_APP_SOURCE"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("release.json") } ?? latest
    }

    /// The site's answer for the latest version: MACGAMEFIX_APP_SITE for the tests,
    /// else the address this build knows, if it knows one.
    static let siteAddress: URL? = nil
    static var site: URL? {
        ProcessInfo.processInfo.environment["MACGAMEFIX_APP_SITE"].map { URL(fileURLWithPath: $0) } ?? siteAddress
    }

    /// One row of the site's table, as it answers: the fields read here.
    private struct SiteVersion: Decodable {
        let version: String
        let downloadUrl: URL
        let sha256: String?
        let releaseUrl: URL?
    }

    /// The newer MacGameFix there is, or nil when this one is the latest. The site
    /// is asked first; what it says is taken, and GitHub is asked only when it
    /// gives no answer that can be read.
    static func check(current: String = Catalog.appVersion) async throws -> Offer? {
        if let site, let data = try? await Updater.fetch(site),
           let row = try? JSONDecoder().decode(SiteVersion.self, from: data),
           ["https", "file"].contains(row.downloadUrl.scheme ?? "") {
            guard Catalog.versionLess(current, row.version) else { return nil }
            return Offer(version: row.version, zip: row.downloadUrl, sha256: row.sha256?.lowercased(), page: row.releaseUrl)
        }
        return try await checkGitHub(current: current)
    }

    /// The same from GitHub's latest release, or nil: this one is it, or the release
    /// has no app zip under its version's name.
    static func checkGitHub(current: String = Catalog.appVersion) async throws -> Offer? {
        let release = try await Updater.release(at: source)
        guard let tag = release.tag_name else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Catalog.versionLess(current, version) else { return nil }
        let name = "MacGameFix-\(version).zip"
        guard let zip = release.assets.first(where: { $0.name == name }) else { return nil }
        return Offer(version: version, zip: zip.browser_download_url,
                     sha256File: release.assets.first { $0.name == name + ".sha256" }?.browser_download_url,
                     page: release.html_url)
    }

    /// Why this copy cannot put another in its own place, or nil when it can. It is
    /// asked before anything is downloaded, so the user is sent to the release's
    /// page instead of to a failure.
    static func whyNot(_ app: URL = Bundle.main.bundleURL) -> String? {
        if app.path.contains("/AppTranslocation/") {
            return "macOS is running this copy from a read-only place. Move MacGameFix to the Applications "
                + "folder and open it from there."
        }
        guard app.pathExtension == "app" else { return "This MacGameFix is not running from an app." }
        guard team(of: app) != nil else {
            return "This copy is not signed with a Developer ID, so it cannot tell whether a download is MacGameFix's."
        }
        let folder = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            return "This account cannot change \(folder.path), where MacGameFix is."
        }
        return nil
    }

    /// The team whose Developer ID signed an app, or nil for an ad hoc signature
    /// or none.
    static func team(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return team
    }

    /// An app whose every file is what its signature sealed, signed with `team`'s
    /// Developer ID under `identifier`. Throws what macOS says is wrong with it.
    static func verify(_ app: URL, identifier: String, team: String) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure.signature("macOS cannot read it as an app")
        }
        // Apple's own wording of "a Developer ID Application certificate of this team".
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else {
            throw Failure.signature("its requirement could not be written")
        }
        var error: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &error) == errSecSuccess else {
            let why = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "its signature does not verify"
            throw Failure.signature(why)
        }
    }

    /// Downloads the offered app and checks it: the release's checksum, the
    /// signature, the version, and the macOS it asks for. Nothing of this app is
    /// touched; what comes back waits for install(_:over:).
    static func prepare(_ offer: Offer, for app: URL = Bundle.main.bundleURL,
                        current: String = Catalog.appVersion) async throws -> Ready {
        if let why = whyNot(app) { throw Failure.place(why) }
        guard let team = team(of: app), let identifier = Bundle(url: app)?.bundleIdentifier else {
            throw Failure.place("This copy's own signature could not be read.")
        }
        let fm = FileManager.default
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        do {
            let zip = try await Updater.fetch(offer.zip)
            var want = offer.sha256
            if want == nil, let sums = offer.sha256File {
                want = String(decoding: try await Updater.fetch(sums), as: UTF8.self)
                    .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map { $0.lowercased() }
            }
            if let want {
                guard Updater.hex(SHA256.hash(data: zip)) == want else { throw Failure.damaged }
            }
            let file = staging.appendingPathComponent("update.zip")
            try zip.write(to: file)
            let unpacked = staging.appendingPathComponent("new")
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", file.path, unpacked.path]
            ditto.standardOutput = FileHandle.nullDevice
            ditto.standardError = FileHandle.nullDevice
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw Failure.damaged }
            try? fm.removeItem(at: file)

            let apps = ((try? fm.contentsOfDirectory(atPath: unpacked.path)) ?? []).filter { !$0.hasPrefix(".") }
            guard apps.count == 1, apps[0].hasSuffix(".app") else { throw Failure.contents }
            let new = unpacked.appendingPathComponent(apps[0])
            try verify(new, identifier: identifier, team: team)

            let plist = NSDictionary(contentsOf: new.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
            let version = plist["CFBundleShortVersionString"] as? String ?? ""
            guard version == offer.version, Catalog.versionLess(current, version) else {
                throw Failure.version(version.isEmpty ? "of no version" : version, offer.version)
            }
            if let minimum = plist["LSMinimumSystemVersion"] as? String {
                let n = minimum.split(separator: ".").map { Int($0) ?? 0 }
                let wanted = OperatingSystemVersion(majorVersion: n.first ?? 0, minorVersion: n.count > 1 ? n[1] : 0,
                                                    patchVersion: n.count > 2 ? n[2] : 0)
                guard ProcessInfo.processInfo.isOperatingSystemAtLeast(wanted) else { throw Failure.system(minimum) }
            }
            return Ready(version: version, app: new, staging: staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Puts the checked app where this one is. The running one is moved aside
    /// first and moved back if the new one cannot take its place, so the path
    /// never holds half of either.
    static func install(_ ready: Ready, over app: URL = Bundle.main.bundleURL) throws {
        let fm = FileManager.default
        let aside = ready.staging.appendingPathComponent("replaced.app")
        do {
            try fm.moveItem(at: app, to: aside)
        } catch {
            throw Failure.place("macOS did not let MacGameFix replace itself in "
                + "\(app.deletingLastPathComponent().path): \(error.localizedDescription)")
        }
        do {
            try fm.moveItem(at: ready.app, to: app)
        } catch {
            try? fm.moveItem(at: aside, to: app)
            throw Failure.place("The new MacGameFix could not be put in place, and the one that was there is "
                + "back: \(error.localizedDescription)")
        }
        try? fm.removeItem(at: ready.staging)
    }

    /// Ends this process and opens the app that is at `app` now. The agent, which
    /// is the old app's process too, is started again from the new one first; the
    /// window opens once this process is gone, so the two never run together.
    @MainActor
    static func relaunch(_ app: URL = Bundle.main.bundleURL) {
        if LaunchAgent.enabled {
            try? LaunchAgent.enable(executable: app.appendingPathComponent("Contents/MacOS/MacGameFix").path)
        }
        // What the tests set for this process (MACGAMEFIX_HOME and the like) goes to the
        // one opened, which macOS would otherwise start without it: a window opened on a
        // throwaway home must not come back on the real one.
        let kept = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("MACGAMEFIX_") }
            .flatMap { ["--env", "\($0.key)=\($0.value)"] }
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", "pid=\"$1\"; shift; while /bin/kill -0 \"$pid\" 2>/dev/null; do /bin/sleep 0.2; done; "
                                + "exec /usr/bin/open \"$@\"",
                            "sh", String(ProcessInfo.processInfo.processIdentifier)] + kept + [app.path]
        waiter.standardInput = FileHandle.nullDevice
        waiter.standardOutput = FileHandle.nullDevice
        waiter.standardError = FileHandle.nullDevice
        try? waiter.run()
        NSApp.terminate(nil)
    }
}
