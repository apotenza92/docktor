import ApplicationServices
import CoreGraphics

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64
typealias CGSSpaceMask = UInt64

let kCGSAllSpacesMask: CGSSpaceMask = 0xFFFF_FFFF_FFFF_FFFF

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: CGSConnectionID,
                                     _ mask: CGSSpaceMask,
                                     _ windowIDs: CFArray) -> CFArray?

@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ axUIElement: AXUIElement,
                                   _ windowID: inout CGWindowID) -> AXError

enum WindowSpacePrivateApis {
    nonisolated static func windowID(for axWindow: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0 else {
            return nil
        }
        return windowID
    }

    nonisolated static func spaces(for windowID: CGWindowID) -> Set<Int> {
        let ids: CFArray = [NSNumber(value: UInt32(windowID))] as CFArray
        guard let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(),
                                                   kCGSAllSpacesMask,
                                                   ids) as? [NSNumber] else {
            return []
        }
        return Set(spaces.map { Int($0.uint64Value) })
    }
}
