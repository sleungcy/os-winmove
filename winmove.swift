import Cocoa
import ApplicationServices

// MARK: - State

var trackWindow: AXUIElement? = nil
var trackMode: Int = 0
var trackStartMouse = CGPoint.zero
var trackStartFrame = CGRect.zero

let stateLock = NSLock()
let axQueue = DispatchQueue(label: "winmove.ax", qos: .userInteractive)
var sequence: UInt64 = 0

let debugMode = CommandLine.arguments.contains("-debug")

// MARK: - AX helpers

func axWindowUnderCursor(_ point: CGPoint) -> AXUIElement? {
    // Use CGWindowListCopyWindowInfo to find which window is at the cursor point,
    // then get its AX window element via the owning app's PID.
    // This avoids walking Firefox's deep web content AX tree which often fails
    // on canvas elements, iframes, or complex web content.
    guard let winList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }

    for w in winList {
        guard let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let width = bounds["Width"], let height = bounds["Height"] else { continue }
        let frame = CGRect(x: x, y: y, width: width, height: height)
        guard frame.contains(point) else { continue }

        // Skip our own process
        guard let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
        guard pid != ProcessInfo.processInfo.processIdentifier else { continue }

        // Skip windows with layer != 0 (menu bar, dock, etc.)
        if let layer = w[kCGWindowLayer as String] as? Int, layer != 0 { continue }

        // Got the topmost window at this point. Get its AX window.
        let axApp = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows) == .success,
              let winArray = windows as? [AXUIElement] else { continue }

        // Find the AX window that matches the position
        for axWin in winArray {
            let pos = axGetPoint(axWin, kAXPositionAttribute)
            let sz  = axGetSize(axWin, kAXSizeAttribute)
            let axFrame = CGRect(origin: pos, size: sz)
            // Allow small tolerance for frame differences
            if abs(axFrame.origin.x - x) < 5 && abs(axFrame.origin.y - y) < 5 {
                return axWin
            }
        }

        // Fallback: return the first (frontmost) window of the app
        if let first = winArray.first { return first }
    }
    return nil
}

func axGetPoint(_ win: AXUIElement, _ attr: String) -> CGPoint {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, attr as CFString, &v) == .success, let v = v else { return .zero }
    var p = CGPoint.zero; AXValueGetValue(v as! AXValue, .cgPoint, &p); return p
}

func axGetSize(_ win: AXUIElement, _ attr: String) -> CGSize {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, attr as CFString, &v) == .success, let v = v else { return .zero }
    var s = CGSize.zero; AXValueGetValue(v as! AXValue, .cgSize, &s); return s
}

func axSetPoint(_ win: AXUIElement, _ attr: String, _ p: CGPoint) {
    var p = p
    if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(win, attr as CFString, v) }
}

func axSetSize(_ win: AXUIElement, _ attr: String, _ s: CGSize) {
    var s = s
    if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(win, attr as CFString, v) }
}

func pidForAXElement(_ el: AXUIElement) -> pid_t {
    var pid: pid_t = 0; AXUIElementGetPid(el, &pid); return pid
}

// MARK: - Activation / deactivation

func activateTracking(mode: Int, cgMousePos: CGPoint) {
    guard let win = axWindowUnderCursor(cgMousePos) else {
        if debugMode { print("no window at", cgMousePos) }
        return
    }

    AXUIElementPerformAction(win, kAXRaiseAction as CFString)
    let pid = pidForAXElement(win)
    if let app = NSRunningApplication(processIdentifier: pid) { app.activate() }

    let origin = axGetPoint(win, kAXPositionAttribute)
    let size   = axGetSize(win, kAXSizeAttribute)

    stateLock.lock()
    trackWindow     = win
    trackMode       = mode
    trackStartMouse = cgMousePos
    trackStartFrame = CGRect(origin: origin, size: size)
    sequence       += 1
    stateLock.unlock()

    if debugMode { print("activated mode=\(mode) at=\(cgMousePos)") }
}

func deactivateTracking() {
    stateLock.lock()
    let wasActive = trackWindow != nil
    trackWindow = nil
    sequence   += 1
    stateLock.unlock()
    if debugMode && wasActive { print("deactivated") }
}

// MARK: - Event handling

func handleEvent(type: CGEventType, event: CGEvent) {
    switch type {

    case .flagsChanged:
        let flags     = event.flags
        let hasCtrl   = flags.contains(.maskControl)
        let hasOpt    = flags.contains(.maskAlternate)
        let hasCmd    = flags.contains(.maskCommand)
        let hasShift  = flags.contains(.maskShift)
        let isCtrlOpt = hasCtrl && hasOpt && !hasCmd && !hasShift
        let isOptCmd  = hasOpt && hasCmd && !hasCtrl && !hasShift

        if debugMode { print("flags: ctrl=\(hasCtrl) opt=\(hasOpt) cmd=\(hasCmd)") }

        stateLock.lock()
        let currentWindow = trackWindow
        let currentMode   = trackMode
        stateLock.unlock()

        if isCtrlOpt || isOptCmd {
            let mode = isCtrlOpt ? 1 : 2
            if currentWindow == nil || currentMode != mode {
                deactivateTracking()
                activateTracking(mode: mode, cgMousePos: event.location)
            }
        } else {
            deactivateTracking()
        }

    case .mouseMoved:
        stateLock.lock()
        guard let win = trackWindow else { stateLock.unlock(); return }

        let loc = event.location
        let dx  = loc.x - trackStartMouse.x
        let dy  = loc.y - trackStartMouse.y
        trackStartMouse = loc

        if trackMode == 1 {
            // MOVE: call AX synchronously in the event tap callback.
            // This is the simplest possible path — the 0.1-0.2ms call is fast enough
            // to not queue up. Calling synchronously means the window position is
            // updated before the next mouse event arrives, matching native drag behavior.
            trackStartFrame.origin.x += dx
            trackStartFrame.origin.y += dy
            let origin = trackStartFrame.origin
            stateLock.unlock()

            axSetPoint(win, kAXPositionAttribute, origin)
        } else {
            // RESIZE: coalesce via sequence number since resize calls can be slow (22ms+)
            trackStartFrame.size.width  = max(100, trackStartFrame.size.width  + dx)
            trackStartFrame.size.height = max(100, trackStartFrame.size.height + dy)
            let size = trackStartFrame.size
            sequence += 1
            let mySeq = sequence
            stateLock.unlock()

            axQueue.async {
                stateLock.lock()
                let current = sequence
                stateLock.unlock()
                guard mySeq == current else { return }
                axSetSize(win, kAXSizeAttribute, size)
            }
        }

    default:
        break
    }
}

// MARK: - Main

guard AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
) else {
    print("Accessibility permission required.")
    print("Grant it in System Settings → Privacy & Security → Accessibility, then re-run.")
    exit(1)
}

let eventMask: CGEventMask =
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.mouseMoved.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: eventMask,
    callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
        handleEvent(type: type, event: event)
        return Unmanaged.passRetained(event)
    },
    userInfo: nil
) else {
    print("Failed to create event tap.")
    exit(1)
}

let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("winmove running:")
print("  hold ctrl+option  → move window under cursor")
print("  hold option+cmd   → resize window under cursor")
print("Press Ctrl-C to quit.")

CFRunLoopRun()
