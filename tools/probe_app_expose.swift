#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Carbon
import Darwin
import Foundation

struct HotKey {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

enum Strategy: String, CaseIterable {
    case dockNotify
    case hotkey
    case fallback
}

struct ImageDiffMetrics {
    let meanAbsDelta: Double
    let changedPixelRatio: Double
    let sampledPixels: Int
}

struct DockWindowSignature: Hashable {
    let layer: Int
    let widthBucket: Int
    let heightBucket: Int
    let alphaBucket: Int
    let title: String
}

struct CaptureSnapshot {
    let image: CGImage
    let path: String?
}

struct ProbeResult: Codable {
    let strategy: String
    let targetBundle: String
    let posted: Bool
    let resolvedHotKey: String?
    let resolveError: String?
    let frontmostBefore: String
    let frontmostAfter: String
    let diffChangedRatio: Double?
    let diffMean: Double?
    let sampledPixels: Int?
    let dockSignatureDelta: Int
    let evidence: Bool
    let beforePath: String?
    let afterPath: String?
    let error: String?
}

private enum CoreDockNotify {
    private typealias Fn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void

    private static let fn: Fn? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else {
            return nil
        }
        return unsafeBitCast(symbol, to: Fn.self)
    }()

    static func post(_ notification: String) -> Bool {
        guard let fn else { return false }
        fn(notification as CFString, nil)
        return true
    }
}

private func parseArgs() -> (strategy: Strategy, target: String)? {
    let args = CommandLine.arguments
    var strategy = Strategy.dockNotify
    var target = "com.apple.TextEdit"

    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--strategy":
            guard index + 1 < args.count, let parsed = Strategy(rawValue: args[index + 1]) else {
                return nil
            }
            strategy = parsed
            index += 2
        case "--target":
            guard index + 1 < args.count else { return nil }
            target = args[index + 1]
            index += 2
        default:
            return nil
        }
    }

    return (strategy, target)
}

private func printUsageAndExit() -> Never {
    fputs("Usage: probe_app_expose.swift [--strategy dockNotify|hotkey|fallback] [--target bundleId]\n", stderr)
    exit(2)
}

private func sleepMs(_ ms: useconds_t) {
    usleep(ms * 1000)
}

private func activateApp(bundleIdentifier: String) {
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
        _ = app.activate(options: [])
        sleepMs(180)
        return
    }

    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        return
    }

    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    config.addsToRecentItems = false
    NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    sleepMs(650)

    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
        _ = app.activate(options: [])
        sleepMs(150)
    }
}

private func captureMainDisplay(tag: String) -> CaptureSnapshot? {
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DockActioner-probe-\(tag)-\(stamp).png")

    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", url.path]
    do {
        try capture.run()
        capture.waitUntilExit()
    } catch {
        return nil
    }

    guard let nsImage = NSImage(contentsOf: url) else {
        return nil
    }
    var rect = CGRect(origin: .zero, size: nsImage.size)
    guard let image = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        return nil
    }

    let rep = NSBitmapImageRep(cgImage: image)

    var path: String?
    if let png = rep.representation(using: .png, properties: [:]) {
        do {
            try png.write(to: url)
            path = url.path
        } catch {
            path = nil
        }
    }

    return CaptureSnapshot(image: image, path: path)
}

private func downsampledRGBA(_ image: CGImage, width: Int = 320, height: Int = 180) -> [UInt8]? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}

private func imageDiffMetrics(before: CGImage, after: CGImage) -> ImageDiffMetrics? {
    guard let lhs = downsampledRGBA(before), let rhs = downsampledRGBA(after), lhs.count == rhs.count else {
        return nil
    }
    let pixelCount = lhs.count / 4
    if pixelCount == 0 { return nil }

    var totalDelta: UInt64 = 0
    var changedPixels = 0
    let threshold = 24

    var index = 0
    while index + 3 < lhs.count {
        let dr = abs(Int(lhs[index]) - Int(rhs[index]))
        let dg = abs(Int(lhs[index + 1]) - Int(rhs[index + 1]))
        let db = abs(Int(lhs[index + 2]) - Int(rhs[index + 2]))
        let delta = dr + dg + db
        totalDelta += UInt64(delta)
        if delta >= threshold {
            changedPixels += 1
        }
        index += 4
    }

    return ImageDiffMetrics(
        meanAbsDelta: Double(totalDelta) / Double(pixelCount * 3 * 255),
        changedPixelRatio: Double(changedPixels) / Double(pixelCount),
        sampledPixels: pixelCount
    )
}

private func dockWindowSignatureSnapshot() -> Set<DockWindowSignature> {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    var signatures = Set<DockWindowSignature>()
    for window in raw {
        guard let owner = window[kCGWindowOwnerName as String] as? String, owner == "Dock" else {
            continue
        }

        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let alpha = window[kCGWindowAlpha as String] as? Double ?? 1.0
        let title = window[kCGWindowName as String] as? String ?? ""
        let bounds = window[kCGWindowBounds as String] as? [String: Any]
        let width = Int((bounds?["Width"] as? Double) ?? 0)
        let height = Int((bounds?["Height"] as? Double) ?? 0)

        signatures.insert(DockWindowSignature(
            layer: layer,
            widthBucket: width / 10,
            heightBucket: height / 10,
            alphaBucket: Int(alpha * 10.0),
            title: title
        ))
    }

    return signatures
}

private func cgEventFlags(fromModifiers modifiers: Int) -> CGEventFlags {
    let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    var flags = CGEventFlags()
    if nsFlags.contains(.shift) { flags.insert(.maskShift) }
    if nsFlags.contains(.control) { flags.insert(.maskControl) }
    if nsFlags.contains(.option) { flags.insert(.maskAlternate) }
    if nsFlags.contains(.command) { flags.insert(.maskCommand) }
    if nsFlags.contains(.function) { flags.insert(.maskSecondaryFn) }
    if nsFlags.contains(.numericPad) { flags.insert(.maskNumericPad) }
    if nsFlags.contains(.capsLock) { flags.insert(.maskAlphaShift) }
    return flags
}

private func resolveAppExposeHotKey() -> (hotKey: HotKey, source: String, error: String?) {
    let appId = 33
    let fallback = HotKey(keyCode: 125, flags: [.maskControl])

    _ = CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
    guard let prefs = CFPreferencesCopyValue("AppleSymbolicHotKeys" as CFString,
                                             "com.apple.symbolichotkeys" as CFString,
                                             kCFPreferencesCurrentUser,
                                             kCFPreferencesAnyHost) as? [String: Any]
    else {
        return (fallback, "fallback", "symbolic hotkeys prefs unavailable")
    }

    guard let entry = prefs[String(appId)] as? [String: Any],
          let enabled = entry["enabled"] as? Bool, enabled,
          let value = entry["value"] as? [String: Any],
          let parameters = value["parameters"] as? [Int],
          parameters.count >= 2
    else {
        return (fallback, "fallback", "entry missing/disabled/malformed")
    }

    let keyCode: Int
    let modifiers: Int
    if parameters.count >= 3 {
        keyCode = parameters[1]
        modifiers = parameters[2]
    } else {
        keyCode = parameters[0]
        modifiers = parameters[1]
    }

    return (HotKey(keyCode: CGKeyCode(keyCode), flags: cgEventFlags(fromModifiers: modifiers)), "user", nil)
}

private func modifierEvents(for flags: CGEventFlags) -> [(CGKeyCode, CGEventFlags)] {
    var out: [(CGKeyCode, CGEventFlags)] = []
    if flags.contains(.maskShift) { out.append((56, .maskShift)) }
    if flags.contains(.maskControl) { out.append((59, .maskControl)) }
    if flags.contains(.maskAlternate) { out.append((58, .maskAlternate)) }
    if flags.contains(.maskCommand) { out.append((55, .maskCommand)) }
    return out
}

private func postSimple(keyCode: CGKeyCode, flags: CGEventFlags, tap: CGEventTapLocation, sourceState: CGEventSourceStateID) -> Bool {
    guard let source = CGEventSource(stateID: sourceState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else { return false }

    down.flags = flags
    up.flags = flags
    down.post(tap: tap)
    usleep(20_000)
    up.post(tap: tap)
    return true
}

private func postChord(keyCode: CGKeyCode, flags: CGEventFlags, tap: CGEventTapLocation, sourceState: CGEventSourceStateID) -> Bool {
    guard let source = CGEventSource(stateID: sourceState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else { return false }

    let mods = modifierEvents(for: flags)
    var currentFlags = CGEventFlags()
    for (code, flag) in mods {
        currentFlags.insert(flag)
        guard let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { continue }
        ev.flags = currentFlags
        ev.post(tap: tap)
    }

    if !mods.isEmpty {
        usleep(8_000)
    }

    down.flags = flags
    up.flags = flags
    down.post(tap: tap)
    usleep(20_000)
    up.post(tap: tap)

    for (code, flag) in mods.reversed() {
        guard let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { continue }
        ev.flags = currentFlags
        ev.post(tap: tap)
        currentFlags.remove(flag)
    }

    return true
}

private func postHotKey(_ hotKey: HotKey) -> Bool {
    let attempts: [() -> Bool] = [
        { postSimple(keyCode: hotKey.keyCode, flags: hotKey.flags, tap: .cgSessionEventTap, sourceState: .combinedSessionState) },
        { postSimple(keyCode: hotKey.keyCode, flags: hotKey.flags, tap: .cghidEventTap, sourceState: .hidSystemState) },
        { postChord(keyCode: hotKey.keyCode, flags: hotKey.flags, tap: .cgSessionEventTap, sourceState: .combinedSessionState) },
        { postChord(keyCode: hotKey.keyCode, flags: hotKey.flags, tap: .cghidEventTap, sourceState: .hidSystemState) }
    ]

    var any = false
    for attempt in attempts {
        any = attempt() || any
        usleep(24_000)
    }
    return any
}

private func emit(_ result: ProbeResult) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(result), let text = String(data: data, encoding: .utf8) {
        print(text)
    } else {
        print("{\"error\":\"failed to encode result\"}")
    }
}

guard let args = parseArgs() else {
    printUsageAndExit()
}

let strategy = args.strategy
let targetBundle = args.target
let threshold = 0.035

activateApp(bundleIdentifier: targetBundle)
sleepMs(160)

let frontmostBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
let before = captureMainDisplay(tag: "before")
let dockBefore = dockWindowSignatureSnapshot()

let resolved = resolveAppExposeHotKey()
let posted: Bool
switch strategy {
case .dockNotify:
    posted = CoreDockNotify.post("com.apple.expose.front.awake")
case .hotkey:
    posted = postHotKey(resolved.hotKey)
case .fallback:
    posted = postHotKey(HotKey(keyCode: 125, flags: [.maskControl]))
}

var bestMetrics: ImageDiffMetrics?
var bestSnapshot: CaptureSnapshot?
var maxDockSignatureDelta = 0

for (index, delayMs) in [220, 420, 680].enumerated() {
    sleepMs(useconds_t(delayMs))
    let after = captureMainDisplay(tag: "after-\(index + 1)")
    if let before, let after, let metrics = imageDiffMetrics(before: before.image, after: after.image) {
        if bestMetrics == nil || metrics.changedPixelRatio > (bestMetrics?.changedPixelRatio ?? 0) {
            bestMetrics = metrics
            bestSnapshot = after
        }
    }

    let dockAfter = dockWindowSignatureSnapshot()
    let delta = dockBefore.symmetricDifference(dockAfter).count
    if delta > maxDockSignatureDelta {
        maxDockSignatureDelta = delta
    }
}

let frontmostAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
let visualStrong = (bestMetrics?.changedPixelRatio ?? 0) >= threshold
let evidence = visualStrong || maxDockSignatureDelta > 0 || frontmostAfter == "com.apple.dock"

let result = ProbeResult(
    strategy: strategy.rawValue,
    targetBundle: targetBundle,
    posted: posted,
    resolvedHotKey: "keyCode=\(resolved.hotKey.keyCode) flags=\(resolved.hotKey.flags.rawValue) source=\(resolved.source)",
    resolveError: resolved.error,
    frontmostBefore: frontmostBefore,
    frontmostAfter: frontmostAfter,
    diffChangedRatio: bestMetrics?.changedPixelRatio,
    diffMean: bestMetrics?.meanAbsDelta,
    sampledPixels: bestMetrics?.sampledPixels,
    dockSignatureDelta: maxDockSignatureDelta,
    evidence: evidence,
    beforePath: before?.path,
    afterPath: bestSnapshot?.path,
    error: nil
)

emit(result)
