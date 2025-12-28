import Cocoa

enum ScrollDirection {
    case up
    case down
}

final class DockClickEventTap {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var clickHandler: ((CGPoint, Int, CGEventFlags) -> Bool)? // Returns true if event should be consumed
    private var scrollHandler: ((CGPoint, ScrollDirection, CGEventFlags) -> Bool)? // Returns true if event should be consumed

    func start(clickHandler: @escaping (CGPoint, Int, CGEventFlags) -> Bool, scrollHandler: @escaping (CGPoint, ScrollDirection, CGEventFlags) -> Bool) -> Bool {
        stop()
        self.clickHandler = clickHandler
        self.scrollHandler = scrollHandler

        // Capture both mouse clicks and scroll wheel events
        let clickMask = (1 << CGEventType.leftMouseDown.rawValue)
        let scrollMask = (1 << CGEventType.scrollWheel.rawValue)
        let mask = clickMask | scrollMask
        
        Logger.log("Attempting to create event tap.")
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, refcon in
                                              let coordinator = Unmanaged<DockClickEventTap>.fromOpaque(refcon!).takeUnretainedValue()
                                              
                                              var shouldConsume = false
                                              switch type {
                                              case .tapDisabledByTimeout, .tapDisabledByUserInput:
                                                  Logger.log("DockClickEventTap: Tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabling.")
                                                  if let tapPort = coordinator.eventTap {
                                                      CGEvent.tapEnable(tap: tapPort, enable: true)
                                                  }
                                                  return Unmanaged.passUnretained(event)
                                              case .leftMouseDown:
                                                  shouldConsume = coordinator.didReceiveClick(event: event)
                                              case .scrollWheel:
                                                  shouldConsume = coordinator.didReceiveScroll(event: event)
                                              default:
                                                  break
                                              }
                                              
                                              // Return nil to consume the event, or the event to let it pass through
                                              return shouldConsume ? nil : Unmanaged.passUnretained(event)
                                          },
                                          userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())) else {
            Logger.log("Failed to create event tap (tapCreate returned nil).")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Logger.log("Event tap run loop source added and enabled.")
        }
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            Logger.log("Event tap disabled.")
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            Logger.log("Event tap run loop source removed.")
        }
        runLoopSource = nil
        eventTap = nil
        clickHandler = nil
        scrollHandler = nil
    }

    private func didReceiveClick(event: CGEvent) -> Bool {
        let location = event.location
        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let timestamp = event.timestamp
        let flags = event.flags
        Logger.log("DockClickEventTap: Raw click event received at \(location.x), \(location.y) (timestamp: \(timestamp), button: \(buttonNumber))")
        let shouldConsume = clickHandler?(location, buttonNumber, flags) ?? false
        Logger.log("DockClickEventTap: Click handler called for click at \(location.x), \(location.y), button: \(buttonNumber), flags: \(flags.rawValue), consume: \(shouldConsume)")
        return shouldConsume
    }
    
    private func didReceiveScroll(event: CGEvent) -> Bool {
        let location = event.location
        let timestamp = event.timestamp
        let flags = event.flags
        
        // Use the first non-zero delta we can get, preferring point deltas for sensitivity.
        let pointDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) // pixel-ish for trackpads
        let fixedDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) / 256.0 // convert 16.16 fixed to float
        let coarseDelta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1) // wheel notch count
        let delta = [pointDelta, fixedDelta, coarseDelta].first(where: { $0 != 0 }) ?? 0
        
        // Require a small threshold so accidental micro-movements are ignored, but single notches still count.
        let threshold = 0.2
        if abs(delta) < threshold {
            Logger.log("DockClickEventTap: Scroll delta below threshold (\(delta)); ignoring")
            return false
        }
        
        // Treat positive deltas as scroll down to align with trackpad “natural” scrolling and observed behavior.
        let direction: ScrollDirection = delta > 0 ? .down : .up
        
        Logger.log("DockClickEventTap: Raw scroll event received at \(location.x), \(location.y) (timestamp: \(timestamp), delta: \(delta), direction: \(direction == .up ? "up" : "down"))")
        let shouldConsume = scrollHandler?(location, direction, flags) ?? false
        Logger.log("DockClickEventTap: Scroll handler called for scroll at \(location.x), \(location.y), direction: \(direction == .up ? "up" : "down"), flags: \(flags.rawValue), consume: \(shouldConsume)")
        return shouldConsume
    }
}

