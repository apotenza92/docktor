import Cocoa

enum DockHitTest {
    static func bundleIdentifierAtPoint(_ point: CGPoint) -> String? {
        guard let element = element(at: point) else { return nil }
        guard isInDockProcess(element) else { return nil }

        var current: AXUIElement? = element
        while let el = current, isInDockProcess(el) {
            if let bundle = bundleIdentifier(for: el) {
                Logger.log("Hit test resolved bundle: \(bundle)")
                return bundle
            }
            current = parent(of: el)
        }
        Logger.log("Hit test found no bundle while walking parents.")
        return nil
    }

    private static func element(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element)
        guard result == .success else {
            Logger.log("AXUIElementCopyElementAtPosition failed with \(result.rawValue)")
            return nil
        }
        return element
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard result == .success else { return nil }
        guard let cfValue = value, CFGetTypeID(cfValue) == AXUIElementGetTypeID() else { return nil }
        return (cfValue as! AXUIElement)
    }

    private static func isInDockProcess(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        guard result == .success else {
            Logger.log("AXUIElementGetPid failed with \(result.rawValue)")
            return false
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            Logger.log("No running app for pid \(pid)")
            return false
        }
        let inDock = app.bundleIdentifier == "com.apple.dock"
        if !inDock {
            Logger.log("Element pid \(pid) bundle \(app.bundleIdentifier ?? "nil") is not Dock.")
        }
        return inDock
    }

    private static func bundleIdentifier(for element: AXUIElement) -> String? {
        if let url: URL = attribute(element, for: kAXURLAttribute) {
            if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                Logger.log("Bundle from AXURL: \(id)")
                return id
            }
        }

        if let title: String = attribute(element, for: kAXTitleAttribute) {
            if let match = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == title }) {
                Logger.log("Bundle from title match: \(match.bundleIdentifier ?? "nil")")
                return match.bundleIdentifier
            }
        }

        Logger.log("No bundleIdentifier resolved for element.")
        return nil
    }

    private static func attribute<T>(_ element: AXUIElement, for key: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }
}

