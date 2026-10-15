import AppKit
import ApplicationServices

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
}

private func elementFrame(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute),
          let size = attribute(element, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(),
          CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
          AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
    return CGRect(origin: point, size: dimensions)
}

private struct SystemWindowAccessibility: WindowAccessibility {
    func role(_ element: AXUIElement) -> String? { attribute(element, kAXRoleAttribute) as? String }
    func parent(_ element: AXUIElement) -> AXUIElement? { elementAttribute(element, kAXParentAttribute) }
    func frame(_ element: AXUIElement) -> CGRect? { elementFrame(element) }
    func minimizeButton(_ window: AXUIElement) -> AXUIElement? { elementAttribute(window, kAXMinimizeButtonAttribute) }
    func enabled(_ element: AXUIElement) -> Bool? { attribute(element, kAXEnabledAttribute) as? Bool }
    func fullScreen(_ window: AXUIElement) -> Bool? { attribute(window, "AXFullScreen") as? Bool }
    func press(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.1)
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}

final class MiddleClickMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var clickSequence = MiddleClickSequence()

    var running: Bool { tap != nil }

    func start() -> Bool {
        if running { return true }
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<MiddleClickMonitor>.fromOpaque(context).takeUnretainedValue()
            return monitor.handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: callback,
                                         userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        clickSequence.reset()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            clickSequence.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let consume = clickSequence.consume(type, button: event.getIntegerValueField(.mouseEventButtonNumber)) {
            minimizeTitleBar(at: event.location)
        }
        return consume ? nil : Unmanaged.passUnretained(event)
    }

    private func minimizeTitleBar(at point: CGPoint) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return false }

        return TitleBarDetector(access: SystemWindowAccessibility()).minimize(hit: hit, at: point)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = MiddleClickMonitor()
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var status: NSMenuItem!
    private var timer: Timer?
    private var enabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mac Middle")
        let menu = NSMenu()
        status = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        toggleItem = menu.addItem(withTitle: "Enabled", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        let permission = menu.addItem(withTitle: "Grant Accessibility Permission…", action: #selector(grantPermission), keyEquivalent: "")
        permission.target = self
        menu.addItem(NSMenuItem.separator())
        let quit = menu.addItem(withTitle: "Quit Mac Middle", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        if !AXIsProcessTrusted() { grantPermission() }
    }

    private func refresh() {
        toggleItem.state = enabled ? .on : .off
        if !AXIsProcessTrusted() {
            monitor.stop()
            status.title = "Accessibility permission required"
        } else if !enabled {
            monitor.stop()
            status.title = "Paused"
        } else {
            status.title = monitor.start() ? "Middle-click a title bar to minimize" : "Unable to listen — quit and reopen"
        }
    }

    @objc private func toggle() { enabled.toggle(); refresh() }

    @objc private func grantPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); monitor.stop() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
