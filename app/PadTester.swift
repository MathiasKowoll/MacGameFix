// Trying the DualSense options on the pad itself, for thirty seconds, before a
// game: the haptics at the strength chosen for this pad and this connection, and
// the trigger effects. The bytes are the Wine modules' own (engine/patches
// 0004-0006): the trigger layouts, the Bluetooth output report 0x31 with its
// sequence and CRC, the haptics in reports 0x33 and 0x32 at 3 kHz; on a cable
// the haptics go to the pad's own 4-channel output, on channels 3 and 4, as a
// game plays them.
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import CoreAudio
import Foundation
import IOKit.hid

/// The 11 bytes of a trigger's effect, as 0006's trigger_effect writes them.
enum PadTriggerBytes {
    static func zones(_ strengths: [Int]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 11)
        var mask: UInt32 = 0, forces: UInt32 = 0
        for (zone, s) in strengths.enumerated() where zone < 10 && (1...8).contains(s) {
            mask |= 1 << zone
            forces |= UInt32(s - 1) << (3 * zone)
        }
        guard mask != 0 else { out[0] = 0x05; return out }
        out[0] = 0x21
        out[1] = UInt8(mask & 0xff)
        out[2] = UInt8(mask >> 8)
        for i in 0..<4 { out[3 + i] = UInt8((forces >> (8 * UInt32(i))) & 0xff) }
        return out
    }

    /// For rumble and recoil, at a step of 0 to 8 of the motor.
    static func effect(_ t: PadTrigger, step: Int = 0) -> [UInt8] {
        var strengths = [Int](repeating: 0, count: 10)
        switch t.effect {
        case "resist":
            for zone in 3..<10 { strengths[zone] = t.strength > 0 ? t.strength : 4 }
            return zones(strengths)
        case "weapon":
            var out = [UInt8](repeating: 0, count: 11)
            out[0] = 0x25
            out[1] = UInt8(((1 << 3) | (1 << 6)) & 0xff)
            out[2] = UInt8(((1 << 3) | (1 << 6)) >> 8)
            out[3] = UInt8((t.strength > 0 ? t.strength : 7) - 1)
            return out
        case "slope":
            let top = t.strength > 0 ? t.strength : 8
            for zone in 2..<10 { strengths[zone] = 1 + (top - 1) * (zone - 2) / 7 }
            return zones(strengths)
        case "recoil":
            let top = (step * (t.strength > 0 ? t.strength : 8) + 7) / 8
            if top > 0 { for zone in 2..<10 { strengths[zone] = top } }
            return zones(strengths)
        case "vibrate", "rumble":
            let top = t.effect == "vibrate" ? (t.strength > 0 ? t.strength : 3)
                : (step * (t.strength > 0 ? t.strength : 8) + 7) / 8
            if top > 0 { for zone in 2..<10 { strengths[zone] = top } }
            var out = zones(strengths)
            if out[0] == 0x21 {
                out[0] = 0x26
                out[9] = t.effect == "vibrate" ? 25 : 40
            }
            return out
        default:
            var out = [UInt8](repeating: 0, count: 11)
            out[0] = 0x05
            return out
        }
    }

    /// A motor value of 0 to 255 in eight steps, as the modules count it.
    static func step(_ motor: Int) -> Int { motor < 4 ? 0 : 1 + (motor - 4) * 8 / 252 }
}

/// One DualSense or DualSense Edge, opened for writing.
final class TestPad {
    let device: IOHIDDevice
    let bluetooth: Bool
    let edge: Bool
    let location: UInt32
    private var sequence: UInt8 = 0
    private let lock = NSLock()

    var name: String { (edge ? "DualSense Edge" : "DualSense") + (bluetooth ? " over Bluetooth" : " on a cable") }

    init?(_ device: IOHIDDevice) {
        func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
        guard number(kIOHIDVendorIDKey) == 0x054c, [0x0ce6, 0x0df2].contains(number(kIOHIDProductIDKey)),
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
        self.device = device
        edge = number(kIOHIDProductIDKey) == 0x0df2
        location = UInt32(truncatingIfNeeded: number(kIOHIDLocationIDKey))
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
        bluetooth = transport.lowercased().hasPrefix("bluetooth")
        if bluetooth {
            // Reading the calibration switches the pad to its full 0x31 report.
            var calibration = [UInt8](repeating: 0, count: 64)
            calibration[0] = 0x05
            var length = CFIndex(41)
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x05, &calibration, &length)
        }
    }

    deinit { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    static func crc32(seed: UInt8, _ data: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = ~0
        func feed(_ byte: UInt8) {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb8_8320 & (0 &- (crc & 1))) }
        }
        feed(seed)
        data.forEach(feed)
        return ~crc
    }

    private func nextSequence() -> UInt8 {
        lock.lock(); defer { lock.unlock() }
        let s = sequence
        sequence = (sequence &+ 1) & 15
        return s << 4
    }

    private func send(_ report: [UInt8]) {
        var report = report
        if bluetooth {
            let crc = TestPad.crc32(seed: 0xa2, report[0..<(report.count - 4)])
            for i in 0..<4 { report[report.count - 4 + i] = UInt8((crc >> (8 * UInt32(i))) & 0xff) }
        }
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
    }

    /// The pad's output: the 47 bytes after the USB report id, as report 0x02
    /// on a cable or 0x31 over Bluetooth.
    func output(_ payload: [UInt8]) {
        if bluetooth {
            var report = [UInt8](repeating: 0, count: 78)
            report[0] = 0x31
            report[1] = nextSequence()
            report[2] = 0x10
            for i in 0..<47 { report[3 + i] = payload[i] }
            send(report)
        } else {
            var report = [UInt8](repeating: 0, count: edge ? 64 : 48)
            report[0] = 0x02
            for i in 0..<47 { report[1 + i] = payload[i] }
            send(report)
        }
    }

    /// 64 frames of 3 kHz signed 8-bit stereo haptics over Bluetooth: report
    /// 0x33 for the first, which sets the pad's audio up, then 0x32.
    func haptics(index: Int, _ samples: [Int8]) {
        let first = index == 0
        var report = [UInt8](repeating: 0, count: first ? 206 : 142)
        report[0] = first ? 0x33 : 0x32
        report[1] = nextSequence()
        report[2] = 0x91
        let offset: Int
        if first {
            report[3] = 7; report[4] = 0xfe
            for i in 5..<10 { report[i] = 48 }
            report[10] = 0; report[11] = 0xd2; report[12] = 64
            offset = 13
        } else {
            report[3] = 3; report[4] = 0x62; report[5] = 48
            report[6] = UInt8(truncatingIfNeeded: index * 2); report[7] = 0xd2; report[8] = 64
            offset = 9
        }
        for i in 0..<128 { report[offset + i] = UInt8(bitPattern: samples[i]) }
        send(report)
    }

    static func connected() -> [TestPad] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x054c] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.compactMap(TestPad.init)
    }
}

/// The haptics' test: a 65 Hz rumble soft, medium and strong, then short hits
/// left and right, over and over; in -1...1 before the gain.
private func padTestSignal(_ t: Double, channel: Int) -> Double {
    let u = t.truncatingRemainder(dividingBy: 4.5)
    if u < 3 { return [0.25, 0.5, 0.9][Int(u)] * sin(2 * .pi * 65 * t) }
    let k = Int((u - 3) / 0.25), v = (u - 3) - Double(k) * 0.25
    return k % 2 == channel && v < 0.04 ? 0.8 * sin(2 * .pi * 120 * v) : 0
}

/// The modules' soft limit: linear to 0.8, then a curve that never passes 1.
private func padAmplify(_ x: Double, _ gain: Double) -> Double {
    let y = x * gain, a = abs(y)
    if gain == 1 || a <= 0.8 { return y }
    return (0.8 + 0.2 * tanh((a - 0.8) / 0.2)) * (y < 0 ? -1 : 1)
}

/// The trigger test's stand-in for a game's rumble, for rumble and recoil: a
/// burst, a hit, a ramp, over and over; 0 to 255.
private func padTestMotor(_ t: Double) -> Int {
    let u = t.truncatingRemainder(dividingBy: 3)
    switch u {
    case ..<0.3: return 220
    case 1.0..<1.15: return 255
    case 1.6..<2.6: return Int((u - 1.6) * 255)
    default: return 0
    }
}

@MainActor
final class PadTester: ObservableObject {
    enum Kind { case haptics, triggers }
    @Published private(set) var running: Kind?
    @Published private(set) var status = ""
    @Published private(set) var remaining = 0

    private var pad: TestPad?
    private var options = PadOptions()
    private var started = Date()
    private var clock: Timer?
    private var pcm: DispatchSourceTimer?
    private var engine: AVAudioEngine?
    private var triggerTimer: Timer?
    private var held = [false, false], pressed = [false, false], steps = [0, 0]
    /// IOHID writes the pad's input here for as long as the callback is registered.
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    static let seconds = 30

    deinit { inputBuffer.deallocate() }

    func start(_ kind: Kind, with options: PadOptions) {
        stop()
        guard let pad = TestPad.connected().first else {
            status = "No DualSense or DualSense Edge is connected."
            return
        }
        self.pad = pad
        self.options = options
        started = Date()
        remaining = PadTester.seconds
        running = kind
        switch kind {
        case .haptics: startHaptics(pad)
        case .triggers: startTriggers(pad)
        }
        clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        clock?.invalidate(); clock = nil
        triggerTimer?.invalidate(); triggerTimer = nil
        if let pcm {
            pcm.cancel()
            self.pcm = nil
            // Back from haptics to the motors, silent.
            var payload = [UInt8](repeating: 0, count: 47)
            payload[0] = 0x03
            pad?.output(payload)
        }
        engine?.stop(); engine = nil
        if running == .triggers, let pad {
            IOHIDDeviceRegisterInputReportCallback(pad.device, inputBuffer, 128, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(pad.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            var payload = [UInt8](repeating: 0, count: 47)
            payload[0] = 0x0c
            payload[10] = 0x05
            payload[21] = 0x05
            pad.output(payload)
        }
        if running != nil { status = "" }
        running = nil
        pad = nil
    }

    private func tick() {
        remaining = max(0, PadTester.seconds - Int(Date().timeIntervalSince(started)))
        if remaining == 0 { stop() } else { status = statusLine() }
    }

    private func statusLine() -> String {
        guard let pad, let running else { return "" }
        switch running {
        case .haptics: return "Haptics on the \(pad.name) at \(PadOptions.times(gain(pad))), \(remaining) s"
        case .triggers: return "Trigger effects on the \(pad.name), \(remaining) s"
        }
    }

    private func gain(_ pad: TestPad) -> Double {
        (pad.edge ? (pad.bluetooth ? options.edgeHapticsGainBluetooth : options.edgeHapticsGainCable)
                  : (pad.bluetooth ? options.hapticsGainBluetooth : options.hapticsGainCable)) ?? 1
    }

    /// The motor power claimed at full on an Edge, as the modules claim it.
    private func powerPayload(_ pad: TestPad, audio: Bool) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: 47)
        if !audio { payload[0] = 0x03 }
        if options.fullMotorPower == true && pad.edge {
            payload[1] |= 0x40
            payload[36] = 0
        }
        return payload
    }

    // MARK: Haptics

    private func startHaptics(_ pad: TestPad) {
        let gain = gain(pad)
        status = statusLine()
        if pad.bluetooth {
            pad.output(powerPayload(pad, audio: true))
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue(label: "pad-haptics", qos: .userInteractive))
            var index = 0, frame = 0
            timer.schedule(deadline: .now() + 0.03, repeating: 64.0 / 3000, leeway: .milliseconds(1))
            timer.setEventHandler {
                var samples = [Int8](repeating: 0, count: 128)
                for i in 0..<64 {
                    let t = Double(frame + i) / 3000
                    for ch in 0..<2 {
                        let v = padAmplify(padTestSignal(t, channel: ch), gain) * 127
                        samples[2 * i + ch] = Int8(max(-127, min(127, v.rounded())))
                    }
                }
                frame += 64
                pad.haptics(index: index, samples)
                index += 1
            }
            pcm = timer
            timer.resume()
            return
        }
        // On a cable: the pad's own output, channels 3 and 4; 1 and 2 are its speaker.
        if options.fullMotorPower == true && pad.edge { pad.output(powerPayload(pad, audio: true)) }
        guard let device = PadTester.audioDevice(location: pad.location) else {
            status = "The \(pad.name)'s audio output was not found."
            running = nil
            return
        }
        let engine = AVAudioEngine()
        guard let unit = engine.outputNode.audioUnit else { return }
        var id = device
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
                             UInt32(MemoryLayout<AudioDeviceID>.size))
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate > 0 ? engine.outputNode.outputFormat(forBus: 0).sampleRate : 48000
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 4) else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
        var frame = 0
        let source = AVAudioSourceNode(format: format) { _, _, count, buffers -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            for i in 0..<Int(count) {
                let t = Double(frame + i) / rate
                for (ch, buffer) in list.enumerated() {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    data[i] = ch < 2 ? 0 : Float(padAmplify(padTestSignal(t, channel: ch - 2), gain))
                }
            }
            frame += Int(count)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.outputNode, format: format)
        do { try engine.start() } catch {
            status = "The \(pad.name)'s audio output did not start: \(error.localizedDescription)"
            running = nil
            return
        }
        self.engine = engine
    }

    /// The pad's output as CoreAudio lists it, by the UID macOS gives it:
    /// AppleUSBAudioEngine:Sony Interactive Entertainment:<product>:<location>:1.
    static func audioDevice(location: UInt32) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return nil }
        let suffix = ":" + String(location, radix: 16) + ":1"
        for id in ids {
            var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                        mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uid) == noErr,
                  let name = uid?.takeRetainedValue() as String? else { continue }
            if name.hasPrefix("AppleUSBAudioEngine:Sony Interactive Entertainment:") && name.hasSuffix(suffix) { return id }
        }
        return nil
    }

    // MARK: Triggers

    private func choice(_ side: Int) -> PadTrigger {
        let first = PadTrigger((side == 0 ? options.triggerR2 : options.triggerL2) ?? "off") ?? PadTrigger(effect: "off")
        let second = PadTrigger((side == 0 ? options.triggerR2WithL2 : options.triggerL2WithR2) ?? "off")
        if held[side], let second, second.effect != "off" { return second }
        return first
    }

    private func chosen(_ side: Int) -> Bool {
        let first = (side == 0 ? options.triggerR2 : options.triggerL2) ?? "off"
        let second = (side == 0 ? options.triggerR2WithL2 : options.triggerL2WithR2) ?? "off"
        return first != "off" || second != "off"
    }

    private func write(sides: [Int]) {
        guard let pad, !sides.isEmpty else { return }
        var payload = [UInt8](repeating: 0, count: 47)
        for side in sides {
            payload[0] |= UInt8(4 << side)
            let bytes = PadTriggerBytes.effect(choice(side), step: steps[side])
            for i in 0..<11 { payload[10 + 11 * side + i] = bytes[i] }
        }
        pad.output(payload)
    }

    private func startTriggers(_ pad: TestPad) {
        held = [false, false]; pressed = [false, false]; steps = [0, 0]
        guard chosen(0) || chosen(1) else {
            status = "No trigger effect is chosen."
            running = nil
            return
        }
        write(sides: [0, 1].filter(chosen))
        status = statusLine()
        // The pad's own input: which trigger is pressed, for a second effect and to
        // write a fixed one again as its trigger starts to move.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceScheduleWithRunLoop(pad.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(pad.device, inputBuffer, 128, { context, _, _, _, id, report, length in
            guard let context else { return }
            let tester = Unmanaged<PadTester>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { tester.input(id: id, bytes) }
        }, context)
        // rumble and recoil follow a stand-in for a game's rumble.
        let all = [options.triggerR2, options.triggerL2, options.triggerR2WithL2, options.triggerL2WithR2]
        if all.contains(where: { ["rumble", "recoil"].contains(PadTrigger($0 ?? "off")?.effect ?? "off") }) {
            triggerTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.followMotor() }
            }
        }
    }

    private func input(id: UInt32, _ report: [UInt8]) {
        // L2 and R2: bytes 5 and 6 of the USB report 0x01, 6 and 7 of the Bluetooth 0x31.
        let at = id == 0x31 ? 6 : 5
        guard (id == 0x01 || id == 0x31), report.count > at + 1 else { return }
        let l2 = Int(report[at]), r2 = Int(report[at + 1])
        var sides: [Int] = []
        for side in 0..<2 where chosen(side) {
            let own = side == 0 ? r2 : l2, other = side == 0 ? l2 : r2
            let nowPressed = pressed[side] ? own >= 20 : own >= 40
            if nowPressed != pressed[side] {
                pressed[side] = nowPressed
                if nowPressed && !["off", "rumble", "recoil"].contains(choice(side).effect) { sides.append(side) }
            }
            let nowHeld = held[side] ? other >= 20 : other >= 40
            if nowHeld != held[side] {
                held[side] = nowHeld
                steps[side] = 0
                if !sides.contains(side) { sides.append(side) }
            }
        }
        write(sides: sides)
    }

    private func followMotor() {
        let motor = padTestMotor(Date().timeIntervalSince(started))
        var sides: [Int] = []
        for side in 0..<2 where ["rumble", "recoil"].contains(choice(side).effect) {
            let step = PadTriggerBytes.step(motor)
            if step != steps[side] { steps[side] = step; sides.append(side) }
        }
        write(sides: sides)
    }
}
