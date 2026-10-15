import ApplicationServices

// Keep click-sequence decisions independent of the global event tap.
struct MiddleClickSequence {
    private var swallowedClick = false

    mutating func reset() { swallowedClick = false }

    mutating func consume(_ type: CGEventType, button: Int64, minimize: () -> Bool) -> Bool {
        guard button == 2 else { return false }
        if type == .otherMouseDown {
            swallowedClick = minimize()
            return swallowedClick
        }
        if type == .otherMouseDragged || type == .otherMouseUp {
            let consume = swallowedClick
            if type == .otherMouseUp { swallowedClick = false }
            return consume
        }
        return false
    }
}

// The live adapter uses Accessibility; tests supply an in-memory window tree.
protocol WindowAccessibility {
    associatedtype Element
    func role(_ element: Element) -> String?
    func parent(_ element: Element) -> Element?
    func frame(_ element: Element) -> CGRect?
    func minimizeButton(_ window: Element) -> Element?
    func enabled(_ element: Element) -> Bool?
    func fullScreen(_ window: Element) -> Bool?
    func press(_ element: Element) -> Bool
}

struct TitleBarDetector<Access: WindowAccessibility> {
    let access: Access

    func minimize(hit: Access.Element, at point: CGPoint) -> Bool {
        // Reject interactive elements anywhere between the hit and its window.
        let allowedRoles: Set<String> = [kAXWindowRole, kAXStaticTextRole, kAXGroupRole, kAXToolbarRole]
        var current: Access.Element? = hit
        var window: Access.Element?
        for _ in 0..<16 {
            guard let node = current, let role = access.role(node),
                  allowedRoles.contains(role) else { return false }
            if role == kAXWindowRole { window = node; break }
            current = access.parent(node)
        }
        guard let window, let bounds = access.frame(window),
              let button = access.minimizeButton(window),
              let buttonBounds = access.frame(button),
              access.enabled(button) == true,
              access.fullScreen(window) != true else { return false }

        // Use traffic-light geometry instead of assuming a fixed title height.
        let strip = CGRect(x: bounds.minX, y: max(bounds.minY, buttonBounds.minY - 5),
                           width: bounds.width, height: buttonBounds.height + 10)
        guard strip.contains(point) else { return false }
        return access.press(button)
    }
}
